$ErrorActionPreference = 'Stop'

$required = @(
  'Dockerfile',
  'README.md',
  'k8s/kustomization.yaml',
  '.github/workflows/build-scan-deploy.yml'
)

foreach ($path in $required) {
  if (-not (Test-Path $path)) {
    throw "Missing required file: $path"
  }
}

if ((Select-String -Path 'Dockerfile' -Pattern '^USER nginx$').Count -ne 1) {
  throw 'Dockerfile must run nginx as a non-root user.'
}

if ((Select-String -Path 'k8s/deployment.yaml' -Pattern 'runAsNonRoot: true').Count -ne 1) {
  throw 'Deployment must enforce non-root execution.'
}

if ((Select-String -Path 'k8s/ingress.yaml' -Pattern 'auth-type: basic').Count -ne 1) {
  throw 'Ingress basic authentication annotation is missing.'
}

Write-Output 'Repository smoke validation passed.'
