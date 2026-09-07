# Hello World on Kubernetes

## 1. Architecture

This repository contains a static nginx application, its container image, Kubernetes resources, security scanning, and delivery configuration.

```text
GitHub Actions: build -> scan -> SBOM -> publish to GHCR
                                      |
                                      v
                              Argo CD watches Git main
                                      |
                                      v
                              Minikube or AKS cluster
```

| Repository part | Responsibility |
| --- | --- |
| `nginx/index.html` | Static hello-world page. |
| `nginx/nginx.conf` | Runs nginx on unprivileged port `8080` and sends logs to container output. |
| `Dockerfile` | Builds the pinned Alpine nginx image and runs it as user `nginx`. |
| `k8s/deployment.yaml` | Runs the application with non-root execution, read-only root filesystem, dropped capabilities, probes, and resource limits. GitHub Actions updates its image reference to the scanned GHCR SHA. |
| `k8s/service.yaml` | Provides internal ClusterIP access to the application. |
| `k8s/ingress.yaml` | Provides HTTP access with nginx basic authentication. |
| `k8s/serviceaccount.yaml` | Gives the workload no API permissions, no mounted token, and a scoped read-only `imagePullSecrets` credential for the private GHCR image. |
| `k8s/network-policy.yaml` | Restricts application traffic to ingress-nginx and DNS egress. |
| `k8s/trivy-cronjob.yaml` | Runs the scheduled in-cluster Trivy scan and fails on HIGH or CRITICAL findings. |
| `k8s/scan-config.yaml` | Selects the registry image scanned by the CronJob. It uses pinned public nginx for the local demo; production can point to the GHCR image. |
| `k8s/kustomization.yaml` | Applies the Kubernetes resources as one unit. |
| `argocd/application.yaml` | Tells Argo CD to watch `main` and sync `k8s/` into the cluster. |
| `.github/workflows/build-scan-deploy.yml` | CI pipeline: builds, scans, generates an SBOM, and publishes the image to GHCR for Minikube or AKS. |

## 2. Prerequisites

Run commands from the repository root in PowerShell.

- Docker Desktop with the Linux engine running
- Minikube using the Docker driver
- kubectl
- Trivy CLI
- Git and access to the GitHub repository

Verify the tools:

```powershell
docker --version
minikube version
kubectl version --client
trivy --version
git --version
```

## 3. Outcomes And Security Expectations

These are the five outcomes from the assessment brief.

### Outcome 1: The page is served from an image you built

**Fulfilled.** GitHub Actions builds, scans, and publishes the same image to a private GHCR package, then updates the Deployment to the immutable scanned commit-SHA image. Argo CD deploys that image in our local minikube cluster; Minikube authenticates the pull with a narrowly scoped, read-only `imagePullSecrets` credential rather than a public, unauthenticated pull.

The image and Pod run with security controls including non-root execution, dropped capabilities, disabled privilege escalation, a default seccomp profile, a read-only root filesystem, probes, and resource limits.

### Outcome 2: Everything lives in a Git repository

**Fulfilled.** The repository contains the application, Dockerfile, Kubernetes manifests, Argo CD Application, GitHub Actions workflow, and documentation. The cluster itself is not provisioned as code because the assessment excludes Terraform/Bicep and expects a local cluster.

### Outcome 3: The application reaches the cluster through automation

**Fulfilled.** GitHub Actions is the CI stage: it builds, scans, publishes the image, generates an SBOM and attaches it to the image, and updates the Git-managed image reference. Argo CD is the continuous delivery stage: it watches `main`, sees that commit, and syncs `k8s/` into Minikube.

Usually the GitHub actions pipeline blocks if the Trivy scan detect any CRITICAL or HIGH vulnerabilities, of which this nginx-image has a ton. I've added a skip-scan input just to be able to push the initial image onto the GHCR for our demonstration.

Once the workflow publishes a passing image and updates Git, Argo CD performs the deployment from Git, even if Argo is in our local minikube cluster AKS could use the same GHCR image and Argo CD configuration.

### Outcome 4: Scheduled vulnerability scanning runs inside Kubernetes

**Fulfilled** `k8s/trivy-cronjob.yaml` runs daily, downloads the vulnerability database, scans the configured registry image, and fails on HIGH or CRITICAL findings. Job status and logs are then posted to https://ntfy.sh/hello-world-scan-example-k8s for humans to read. In our ideal solution, this would post directly to a teams channel through webhooks.

### Outcome 5: Unauthenticated users cannot reach the page

**Fulfilled locally.** `k8s/ingress.yaml` uses the `hello-world-auth` Secret for nginx basic authentication. Anonymous requests return `401`; valid demo credentials (Username: demo Password; change-me) return `200` and the page.

Basic auth is only a local demonstration. Production would use TLS and an actual identity provider such as Entra ID linked to AKS.

### Security Expectation 1: Pipeline credentials.
How does your pipeline authenticate to the image registry, and to the cluster if it talks to it at all? Be ready to explain what you chose, what the alternatives were, and why. If a long-lived secret is stored anywhere, tell us where it lives, who can read it, and how you'd rotate it. If your deployment model means the pipeline never holds cluster credentials, say so — that's an answer, and a good one.

Answer:
I made it so that the pipeline on Github actions authenticates to the image registry using a GitHub classic PAT with read:package permissions only. The PAT expires in one year, and without the PAT the image is private and can't be pulled otherwise. After a year, the PAT should require a refresh. No one has access to the PAT, and it's handled as a secret by the k8s cluster to prevent it leaking in logs or elsewhere. This does mean we have some necessary manual steps when setting up the minikube cluster for the first time.
The pipeline doesn't talk to the cluster at all, it simply builds, scans, and publishes the image to the GHCR. The cluster reaches out and grabs the image from the registry, sidestepping needing to connect the pipeline to my locak minikube OR a hypothetical future implementation on AKS

### Security Expectation 2: Acting on scan results.
A scheduled scan that writes to stdout meets the letter of the request and is worth very little. Who — or what — learns that a critical vulnerability has appeared, and through what path? Does anything block, alert, or roll back?

Answer:
For now I've simply made the scheduled scan dump the results of the scan to https://ntfy.sh/hello-world-scan-example-k8s, which I have also manually subscribed to find alerts. Obviously this is terrible, as I don't even get notifications unless I have the tab open in a browser somewhere or an app on my phone. Ideally in prod it'd simply be sending notifications to an appropriate teams or slack channel, and ONLY when unacceptable amounts of vulnerabilities are detected that require immediate attention. Notification spam isn't helpful and desensitises devs.

### Security Expectation 3: The finding you can't fix.
Sooner or later your nginx base image will carry a critical CVE with no patch available. What's your process? Describe it in prose; don't build it.

Answer: It depends on what the actual CVE is and whether it affects us. If it's for a module or library we don't even use, in which case it shouldn't affect us. We can also check if it's something we can mitigate by either turning off xyz module. We could also see if there WILL be a fix that just hasn't released yet vs no fix ever, in which case we might make an exception if we think the fix is coming soon. Either way our alerts should let us know if we have any vulnerabilities as described (Trivy is configured to treat CRITICAL and HIGH as blockers)

### Security Expectation 4: Image hygiene.
What base image did you choose, is it pinned, and does the container run as root? Justify each.

Answer: Base image is nginx:1.27.5-alpine.
It's pinned to a specific version tag rather than  latest, which prevents unexpected  changes causing problems on rebuilds.
We're not running in root, I've made sure of that. In the dockerfile we swap to USER nginx, and in the deployment.yaml file we're purposely not using the root user (UID 101 is nginx again).
Additionally I've prevented being able to escalate privledges, writing to the filesystem (hello world application shouldn't need that), any account tokens aren't automatically mounted, and we default the seccomp set.

### Security Expectation 5: Scan coverage.
Scanning running workloads is one layer. What about scanning at build time, or scanning infrastructure code before it's applied? Tell us which layers you covered, which you skipped, and what each one catches that the others miss. Infrastructure scanning is a discussion point rather than something to build here — see section 4.

Answer:
I'm scanning the image once at build time, then regularly once the cluster is up. Scanning once at build time lets us know before we go through the costly deployment step whether the image has any known issues, but doesn't cover when images slowly get out of date and gain vulnerabilities. The regular chron job as asked for by the brief helps remedy that issue, but obviously doesn't block deployments seeing as it's running on the same cluster.

Infrastructure scanning would be for scanning the k8s config that's in this repo, I think in this case it'd be something like kube-linter for mistakes in the manifests. Never used it, but from what I know it covers things like privileged containers, missing security contexts, over-permissive network policies etc. If we were to implement this, it'd go in the same CI pipeline in Github actions as the build scan.

### Security Expectation 6: Least privilege.
What can your workload do that it doesn't need to be able to do — in the cluster, and in Azure?

Answer:
Service account for hello-world has literally 0 permissions, simply exists to attach the GitHub PAT to. The PAT itself is worth talking about, it only has read permissions specifically on packages, no other permissions within GitHub. This wouldn't change in Azure.

Network policy is default-deny, and built up to allow very specific things in and out. Problem with the egress though is that because ntfy.sh doesn't have a fixed IP, I had to make it allow all destinations for TCP 443 traffic, so technically speaking the hello-world workload can egress to any destination on the internet. Obviously fixed if we move off ntfy.sh for the full AKS solution.
## 4. Local Minikube And Future AKS

### Local solution

Minikube substitutes for AKS during the demonstration. The Github actions pipeline still publishes the image and Minikube receives that image from GHCR while Argo CD runs inside the cluster and watches the public GitHub repository. The GHCR package itself is private, so Minikube pulls it using a read-only credential in `ghcr-pull-secret`, and the Trivy pod created for the daily scan authenticates the same way through `ghcr-scan-credentials` to scan that private image, pushing notifications to ntfy.sh.

### AKS switch

1. Keep the GitHub Actions build, scan, SBOM, GHCR publication, and GitOps image-update stages.
2. AKS would replace the static, PAT-based `ghcr-pull-secret`/`ghcr-scan-credentials` used here with a federated identity integration (Workload Identity), avoiding a long-lived credential entirely.
3. Keep using the immutable GHCR commit-SHA tag or digest instead of `hello-world:local`.
4. Install Argo CD inside private AKS and configure the Application for the production overlay.
5. Replace Minikube ingress/basic auth with TLS, DNS, and Entra ID/OIDC authentication.
6. Swap the alerting from ntfy.sh to something like teams or slack notifications.

No Azure infrastructure is provisioned here, as requested by the assessment.

## 5. Local Demonstration

Run this sequence from PowerShell.

### Start Minikube and create demo authentication

```powershell
echo $GITHUB_TOKEN | docker login ghcr.io -u sesamesesamum --password-stdin
minikube start --driver=docker --ports=127.0.0.1:18080:30080
minikube addons enable ingress
# Patch the ingress-nginx-controller ton not pick a random port so that our setup always works
kubectl -n ingress-nginx patch service ingress-nginx-controller --type=merge -p --% "{\"spec\":{\"ports\":[{\"name\":\"http\",\"port\":80,\"targetPort\":\"http\",\"protocol\":\"TCP\",\"nodePort\":30080},{\"name\":\"https\",\"port\":443,\"targetPort\":\"https\",\"protocol\":\"TCP\",\"nodePort\":30443}]}}"

$auth = (docker run --rm httpd:2.4-alpine htpasswd -nbB demo 'change-me' | Out-String).Trim()
kubectl create namespace hello-world --dry-run=client -o yaml | kubectl apply -f -
kubectl -n hello-world create secret generic hello-world-auth --from-literal=auth=$auth --dry-run=client -o yaml | kubectl apply -f -
```

The `--ports` flag publishes the container's NodePort to `127.0.0.1:18080` at Minikube's creation time, and the `kubectl patch` pins the ingress controller to that same NodePort. This binding is owned by Docker, not by a foreground command, so `http://hello-world.local:18080/` stays reachable for as long as `minikube status` reports the cluster running — unlike `kubectl port-forward`, which dies the moment its terminal closes or the machine sleeps.

The Secret is generated locally and must not be committed.

### Make the GHCR image private and create pull credentials

Set the `example_k8s` GHCR package visibility to Private (package settings -> Danger Zone -> Change visibility). GitHub Actions can still push to a private package with the same `GITHUB_TOKEN`; only pulling requires a credential.

Create a classic PAT scoped to `read:packages` only. Paste it directly into the variable below rather than using `Read-Host`; an interactive secure prompt can silently capture a stray character instead of the real value when this block is pasted in as one paste, which produces a broken credential and a `403 Forbidden` pull error that looks unrelated to the cause:

```powershell
$ghcrUser = 'sesamesesamum'
$ghcrTokenPlain = 'REPLACE_WITH_YOUR_PAT'  # paste your token here, then run; never commit this file with the real value

kubectl -n hello-world create secret docker-registry ghcr-pull-secret `
  --docker-server=ghcr.io `
  --docker-username=$ghcrUser `
  --docker-password=$ghcrTokenPlain `
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n hello-world create secret generic ghcr-scan-credentials `
  --from-literal=username=$ghcrUser `
  --from-literal=password=$ghcrTokenPlain `
  --dry-run=client -o yaml | kubectl apply -f -
```

`ghcr-pull-secret` lets kubelet pull the private image through `k8s/serviceaccount.yaml`'s `imagePullSecrets`. `ghcr-scan-credentials` is separate because `imagePullSecrets` only covers kubelet pulls, not Trivy's own registry calls when scanning the image in `k8s/scan-config.yaml`; Trivy reads `TRIVY_USERNAME`/`TRIVY_PASSWORD` directly. Neither Secret is committed to Git.

### Deploy through Argo CD

Install Argo CD once per Minikube cluster:

```powershell
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply --server-side --force-conflicts -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd wait --for=condition=Available deployment/argocd-server --timeout=300s
```

Commit and push the repository first. Argo CD reads GitHub, not uncommitted local files:

```powershell
git add .dockerignore .gitignore Dockerfile README.md .github k8s nginx scripts argocd
git commit -m "Update Kubernetes GitOps solution"
git push origin main
```

Register the Application:

```powershell
kubectl apply -f argocd/application.yaml
kubectl -n argocd get application hello-world
```

Expected status:

```text
Synced / Healthy
```

To demonstrate reconciliation, edit `nginx/index.html`, commit, and push to `main`:
Or delete the deployment using kubectl delete deployment hello-world -n hello-world

```powershell
git add nginx/index.html
git commit -m "Update hello world page"
git push origin main
kubectl -n argocd get application hello-world -w
```

### Verify the application

```powershell
kubectl -n hello-world rollout status deployment/hello-world --timeout=120s
kubectl -n hello-world get pods,svc,ingress,cronjob
```

No port-forward is needed; the ingress is already reachable at `hello-world.local:18080` as long as the Minikube container is running.

Anonymous access should return `401`:

```powershell
try { Invoke-WebRequest http://127.0.0.1:18080/ -Headers @{ Host = 'hello-world.local' } -UseBasicParsing -ErrorAction Stop } catch { $_.Exception.Response.StatusCode }
```

Authenticated access should return `200` and the page:

```powershell
$secure = ConvertTo-SecureString 'change-me' -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential('demo', $secure)
$response = Invoke-WebRequest http://127.0.0.1:18080/ -Headers @{ Host = 'hello-world.local' } -Credential $credential -UseBasicParsing
$response.StatusCode
$response.Content | Select-String 'Hello, Kubernetes'
```

With a `127.0.0.1 hello-world.local` entry in the Windows hosts file, the same URL also works directly in a browser: `http://hello-world.local:18080/`.

In which case you can just go to the URL on a browser and login using username demo and password change-me

### Demonstrate the scheduled scan

Argo manages the scan target from `k8s/scan-config.yaml`. Trigger a Job immediately:

```powershell
kubectl -n hello-world delete job scheduled-trivy-scan --ignore-not-found
kubectl -n hello-world create job --from=cronjob/hello-world-vulnerability-scan scheduled-trivy-scan
kubectl -n hello-world logs -f job/scheduled-trivy-scan
kubectl -n hello-world get job scheduled-trivy-scan
```

For our demo, we can see the result of the scan here: https://ntfy.sh/hello-world-scan-example-k8s

The scan should download its database and print a vulnerability report. The Job may be `Failed` when HIGH or CRITICAL findings are detected; that is the configured security gate, not a scanner startup failure.

### Clean up

```powershell
kubectl delete namespace hello-world
minikube stop
```

## Testing commands

### Manually building and scanning (for testing, GitHub actions takes the place of building and scanning)

```powershell
echo $GITHUB_TOKEN | docker login ghcr.io -u sesamesesamum --password-stdin
docker build --tag hello-world:local .
trivy image --severity HIGH,CRITICAL --ignore-unfixed hello-world:local
trivy image --format spdx-json --output sbom-hello-world.spdx.json hello-world:local
trivy config --severity HIGH,CRITICAL k8s/
```

The image scan may return exit code `1` because vulnerabilities are present. That is the intended security gate. The configuration scan should report zero HIGH/CRITICAL misconfigurations.

### Loading the hello-world:local image locally

```powershell
minikube image load hello-world:local
```