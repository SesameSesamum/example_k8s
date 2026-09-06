# Hello World on Kubernetes

A small DevSecOps demonstration for a static nginx page running on a local Minikube cluster. The repository intentionally keeps the application boring and makes the delivery and security controls visible.

## Architecture

- Docker builds a non-root nginx image listening on port 8080.
- Kubernetes runs one restricted Deployment behind a ClusterIP Service.
- Minikube's nginx ingress controller protects the page with HTTP basic authentication.
- A scheduled Trivy CronJob scans the registry image and fails for HIGH or CRITICAL vulnerabilities.
- GitHub Actions builds, scans, generates an SBOM, and publishes to GHCR.
- An optional self-hosted GitHub Actions runner on the Windows machine applies the manifests to Minikube. A hosted runner cannot reach a laptop-local cluster.

## Local prerequisites

Install and expose these commands in PowerShell:

- Docker Desktop
- Minikube
- kubectl
- Trivy CLI (optional, but recommended for the local demo)
- Git

The build and deployment commands below are intended for PowerShell.

## Repository guide

| Path | Purpose |
| --- | --- |
| `Dockerfile` | Builds the pinned Alpine nginx image, copies the page and config, and runs as the non-root `nginx` user. |
| `nginx/index.html` | The deliberately simple static application shown in the browser. |
| `nginx/nginx.conf` | Configures nginx to listen on unprivileged port 8080 and write logs to container output. |
| `.dockerignore` | Keeps Git metadata, manifests, and documentation out of the image build context. |
| `k8s/namespace.yaml` | Isolates the application in the `hello-world` namespace. |
| `k8s/deployment.yaml` | Runs the nginx Pod with resource limits and container hardening. |
| `k8s/service.yaml` | Provides internal ClusterIP networking to the Pod. |
| `k8s/ingress.yaml` | Publishes the page through Minikube's nginx ingress and requires basic authentication. |
| `k8s/serviceaccount.yaml` | Gives the workload an identity with no API permissions and no automatically mounted token. |
| `k8s/network-policy.yaml` | Allows application traffic only from ingress-nginx and allows DNS egress. |
| `k8s/trivy-cronjob.yaml` | Re-scans the configured registry image on a schedule and fails on HIGH/CRITICAL findings. |
| `k8s/scan-config.yaml` | Holds the image reference used by the scheduled scan. Replace the placeholder with your GHCR image. |
| `k8s/kustomization.yaml` | Applies the Kubernetes resources as one repeatable unit. |
| `.github/workflows/build-scan-deploy.yml` | Builds, scans, creates an SBOM, publishes to GHCR, and optionally deploys using a self-hosted runner. |
| `scripts/validate.ps1` | Performs quick repository checks for required files and core security settings. |
| `README.md` | Documents the architecture, demo, security choices, and production follow-up. |

## Demo walkthrough

The following is a practical showcase sequence. Run it from the repository root in PowerShell.

### 1. Prove the image works

```powershell
docker build --tag hello-world:local .
docker run --detach --publish 18080:8080 --name hello-world-test hello-world:local
Invoke-WebRequest http://127.0.0.1:18080 -UseBasicParsing
docker exec hello-world-test id
docker rm --force hello-world-test
```

The response should contain `Hello, Kubernetes.` and the container identity should be UID 101 (`nginx`).

### 2. Scan the image locally

```powershell
trivy image --severity HIGH,CRITICAL --ignore-unfixed hello-world:local
```

This command may exit with code 1 because the current base image can have known findings. That is the expected blocking behavior of the CI gate. Explain the finding, update the base image when a fix exists, and do not hide or ignore a vulnerability without a documented risk decision.

### 3. Start Minikube and prepare authentication

```powershell
minikube start --driver=docker
minikube addons enable ingress
minikube image load hello-world:local

$auth = (docker run --rm httpd:2.4-alpine htpasswd -nbB demo 'change-me' | Out-String).Trim()
kubectl create namespace hello-world --dry-run=client -o yaml | kubectl apply -f -
kubectl -n hello-world create secret generic hello-world-auth --from-literal=auth=$auth --dry-run=client -o yaml | kubectl apply -f -
```

### 4. Deploy and verify Kubernetes

```powershell
kubectl apply -k k8s
kubectl -n hello-world rollout status deployment/hello-world --timeout=120s
kubectl -n hello-world get pods,svc,ingress,cronjob
```

### 5. Demonstrate authentication

For a reliable Windows demo without changing the hosts file, forward the ingress controller in a second terminal:

```powershell
kubectl -n ingress-nginx port-forward service/ingress-nginx-controller 18080:80
```

In the first terminal, anonymous access should return `401`:

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

### 6. Demonstrate scanning in the cluster

The scheduled job normally runs at `02:17` UTC. Trigger it immediately for the showcase:

```powershell
kubectl -n hello-world create job --from=cronjob/hello-world-vulnerability-scan scan-now
kubectl -n hello-world wait --for=condition=complete job/scan-now --timeout=300s
if ($LASTEXITCODE -ne 0) { kubectl -n hello-world wait --for=condition=failed job/scan-now --timeout=30s }
kubectl -n hello-world logs job/scan-now
kubectl -n hello-world get job scan-now
```

The Job can fail when the scanned image contains HIGH or CRITICAL vulnerabilities. That failure is intentional: it is the visible signal that an image needs security triage. A production alerting rule should notify a team channel or incident system from Job failures.

### 7. Scan the Kubernetes configuration

```powershell
trivy config --severity HIGH,CRITICAL k8s/
```

This is separate from image scanning. Image scanning finds vulnerable packages; configuration scanning finds insecure Kubernetes settings. Both checks are useful and should be run in CI before deployment.

### 8. Show the GitHub Actions path

Push a branch and open a pull request to show the build and blocking image scan. Merge to `main` to publish the image and SBOM to GHCR. To deploy to local Minikube from Actions, register a self-hosted runner on this Windows machine with labels `self-hosted`, `windows`, and `minikube`, then manually run the workflow with `deploy_local=true`.

The hosted runner can build and publish, but it cannot normally reach Minikube on your laptop. The self-hosted runner is only a local assessment solution; production should use a pull-based deployer inside a private AKS cluster.

### 9. Clean up

```powershell
kubectl delete namespace hello-world
minikube stop
```

## Run locally

```powershell
minikube start --driver=docker
minikube addons enable ingress

docker build -t hello-world:local .
minikube image load hello-world:local
```

Create the demo basic-auth secret. This uses Docker to generate the bcrypt value, so the plaintext password is not stored in Git:

```powershell
$auth = (docker run --rm httpd:2.4-alpine htpasswd -nbB demo 'change-me' | Out-String).Trim()
kubectl create namespace hello-world --dry-run=client -o yaml | kubectl apply -f -
kubectl -n hello-world create secret generic hello-world-auth --from-literal=auth=$auth --dry-run=client -o yaml | kubectl apply -f -
```

Apply the application:

```powershell
kubectl apply -k k8s
kubectl -n hello-world get pods,svc,ingress,cronjob
```

Add the ingress address to the Windows hosts file as Administrator. Get the address with:

```powershell
minikube ip
```

Add a line such as this to `C:\Windows\System32\drivers\etc\hosts`:

```text
<minikube-ip> hello-world.local
```

Open `http://hello-world.local` and authenticate with `demo` / `change-me`. Replace that demo password before presenting the solution.

The scan CronJob is configured for the GHCR image in `k8s/scan-config.yaml`. For a local-only run, use a public registry image or change the ConfigMap to an image Trivy can pull. Trigger a scan immediately with:

```powershell
kubectl -n hello-world create job --from=cronjob/hello-world-vulnerability-scan scan-now
kubectl -n hello-world logs -f job/scan-now
kubectl -n hello-world get jobs
```

A failed Job is intentional when the configured severity threshold is met. Its status and logs are the first human-visible signal. In production, the Job failure would feed an alerting rule or a Teams/Slack/PagerDuty webhook.

## GitHub Actions

The workflow in `.github/workflows/build-scan-deploy.yml` runs on pull requests and pushes to `main`:

1. Builds the image.
2. Scans HIGH and CRITICAL vulnerabilities with Trivy and fails the job on findings.
3. Generates and uploads an SPDX SBOM.
4. Publishes the image to GHCR on non-PR events.

The workflow uses the short-lived `GITHUB_TOKEN`; no registry password is committed. Repository Actions settings must allow the workflow to write packages. For a demo, make the GHCR package public or configure an image pull secret in the cluster. A production AKS deployment should use Azure Workload Identity and an ACR pull role rather than a long-lived registry secret.

To deploy through GitHub Actions, register a self-hosted runner on the Windows machine with labels `self-hosted`, `windows`, and `minikube`. The runner must have Docker Desktop, Minikube, kubectl, and a running Minikube cluster. Start the workflow manually and set `deploy_local` to `true`. The deploy job applies the manifests and updates the Deployment and scan target to the scanned commit image.

The self-hosted runner is useful for this local assessment but would be isolated and tightly controlled in a real environment. The preferred production design is hosted CI publishing to ACR and a pull-based deployer such as Flux or Argo CD inside a private AKS cluster.

## Security decisions

### Image hygiene

The image uses the small Alpine nginx variant and exposes an unprivileged port. Kubernetes enforces UID/GID 101, drops Linux capabilities, disables privilege escalation, uses the RuntimeDefault seccomp profile, and mounts `/tmp` as writable while keeping the root filesystem read-only. The example uses a version tag for readability; production should pin the base image by digest and update it through a controlled dependency process.

### Least privilege

The application has no Kubernetes API permissions and does not receive a service-account token. The Service is internal, and the NetworkPolicy permits traffic only from the Minikube ingress controller plus DNS egress. The scanner also has no Kubernetes API access. It only needs outbound access to pull the image and vulnerability database.

### Authentication

Basic auth is deliberately a cheap local demonstration. It protects against anonymous access but is not a production identity system. Production would use TLS, Entra ID or another OIDC provider, centralized identity lifecycle, and an identity-aware proxy.

### Scan coverage and response

- CI image scanning blocks a pull request or publish when HIGH/CRITICAL vulnerabilities are found.
- The scheduled in-cluster scan catches vulnerabilities introduced after deployment or discovered later in the image.
- The SBOM records component provenance for triage.
- Kubernetes manifest and container configuration review are included here; production would add IaC scanning with tools such as Checkov or Trivy config and admission enforcement with Kyverno or Gatekeeper.

When a critical vulnerability has no fix, the response is to confirm exploitability and exposure, record a risk acceptance with an expiry, reduce exposure where possible, and choose a compensating control such as a stricter network policy or temporary rollback. The exception is reviewed regularly and removed when a patched base image is available.

## What is implemented versus designed

Implemented: Docker image, static page, Kubernetes Deployment/Service/Ingress, basic auth, network policy, scheduled Trivy scan, GitHub Actions build/scan/SBOM/publish workflow, and optional local self-hosted deployment job.

Designed but not provisioned: AKS, ACR, private networking, Entra ID, Workload Identity, centralized alerting, admission policy, and production TLS/DNS. Those are intentionally discussed rather than represented by untested Terraform.

## Teardown

```powershell
kubectl delete namespace hello-world
minikube stop
```
