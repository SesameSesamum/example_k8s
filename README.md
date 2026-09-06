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

## 3. Outcomes And Fulfilment

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

### Build and scan

```powershell
echo $GITHUB_TOKEN | docker login ghcr.io -u sesamesesamum --password-stdin
docker build --tag hello-world:local .
trivy image --severity HIGH,CRITICAL --ignore-unfixed hello-world:local
trivy image --format spdx-json --output sbom-hello-world.spdx.json hello-world:local
trivy config --severity HIGH,CRITICAL k8s/
```

The image scan may return exit code `1` because vulnerabilities are present. That is the intended security gate. The configuration scan should report zero HIGH/CRITICAL misconfigurations.

### Start Minikube and create demo authentication

```powershell
minikube start --driver=docker --ports=127.0.0.1:18080:30080
minikube addons enable ingress
kubectl -n ingress-nginx patch service ingress-nginx-controller --type=merge -p --% "{\"spec\":{\"ports\":[{\"name\":\"http\",\"port\":80,\"targetPort\":\"http\",\"protocol\":\"TCP\",\"nodePort\":30080},{\"name\":\"https\",\"port\":443,\"targetPort\":\"https\",\"protocol\":\"TCP\",\"nodePort\":30443}]}}"
minikube image load hello-world:local

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
