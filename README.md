# Wisecow - Containerized & Deployed on Kubernetes

> **Accuknox DevOps Trainee Practical Assessment**
> Containerisation and Deployment of the Wisecow Application on Kubernetes with TLS Communication and CI/CD Pipeline

---

## Project Structure

```
wisecow/
  wisecow.sh                      # Application source code
  Dockerfile                      # Container image definition
  k8s/
    namespace.yaml                # Dedicated Kubernetes namespace
    deployment.yaml               # Application deployment with health checks
    service.yaml                  # ClusterIP service for internal routing
    ingress.yaml                  # Ingress with TLS termination
    kubearmor-policy.yaml         # Zero-trust KubeArmor security policy (PS3)
  scripts/
    system_health_monitor.sh      # PS2: System health monitoring script
    app_health_checker.sh         # PS2: Application health checker script
  tls/
    generate-certs.sh             # TLS certificate generation helper
  .github/
    workflows/
      ci-cd.yml                   # GitHub Actions CI/CD pipeline
  README.md                       # This file
```

---

## Problem Statement 1: Wisecow Application on Kubernetes

### About the Application

Wisecow is a Cow Wisdom Web Server that serves random fortune quotes rendered with cowsay. It uses a bash script with netcat to listen on port 4499 and responds with HTTP responses containing fortune cookies.

### Prerequisites

- Docker
- A Kubernetes cluster (Minikube / Kind / cloud-managed)
- kubectl configured to access the cluster
- Git

### Step 1: Docker Build

```bash
docker build -t wisecow:latest .
docker run -d -p 4499:4499 --name wisecow-test wisecow:latest
curl http://localhost:4499/
```

### Step 2: Deploy to Kubernetes

```bash
kubectl apply -f k8s/namespace.yaml
chmod +x tls/generate-certs.sh
./tls/generate-certs.sh
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/ingress.yaml
kubectl get pods -n wisecow
kubectl get svc -n wisecow
kubectl get ingress -n wisecow
```

### Step 3: Access the Application

```bash
kubectl port-forward svc/wisecow-service 8080:80 -n wisecow
curl http://localhost:8080/
```

For Ingress access, add to /etc/hosts:
```
127.0.0.1 wisecow.local
```
Then: `curl https://wisecow.local/ -k`

---

## TLS Implementation (Challenge Goal)

The TLS implementation uses self-signed certificates for development and supports Let's Encrypt for production.

```bash
./tls/generate-certs.sh
```

This creates:
- A self-signed CA and server certificate for wisecow.local
- A Kubernetes TLS secret (wisecow-tls) in the wisecow namespace
- Supports both wisecow.local and internal Kubernetes DNS names

For production, uncomment the cert-manager annotation in k8s/ingress.yaml.

---

## CI/CD Pipeline (GitHub Actions)

### Workflow: .github/workflows/ci-cd.yml

Triggers: Push to main, Pull request to main

| Job       | Description                                              |
|-----------|----------------------------------------------------------|
| build     | Builds Docker image and pushes to GitHub Container Registry (GHCR) |
| deploy    | Deploys to Kubernetes cluster after successful build     |

### Required GitHub Secrets

| Secret       | Description                              |
|--------------|------------------------------------------|
| KUBE_CONFIG  | Base64-encoded kubeconfig for cluster access |
| GITHUB_TOKEN | Auto-provided by GitHub Actions          |

### Setup

1. Generate a kubeconfig for your cluster and base64 encode it
2. Add the base64-encoded output as a GitHub secret named KUBE_CONFIG
3. Push to main - the pipeline will automatically build, push, deploy, and smoke-test.

---

## Problem Statement 2: DevOps Scripts

### System Health Monitor (scripts/system_health_monitor.sh)

Checks: CPU usage, Memory usage, Disk space, Processes (zombies), Load average, Network connectivity.

```bash
./scripts/system_health_monitor.sh
./scripts/system_health_monitor.sh --cpu-threshold 70 --disk-threshold 90
./scripts/system_health_monitor.sh --interval 30
./scripts/system_health_monitor.sh --log-only --log-file /var/log/health.log
```

Exit Codes: 0 = Good, 1 = Warning, 2 = Critical

### Application Health Checker (scripts/app_health_checker.sh)

Checks HTTP status codes to determine if an application is up or down.

```bash
./scripts/app_health_checker.sh
./scripts/app_health_checker.sh -u http://wisecow-service:80 -r 5 -t 10
./scripts/app_health_checker.sh -u https://wisecow.local -e 200
./scripts/app_health_checker.sh -u http://localhost:4499 -q -l /var/log/app-health.log
```

Exit Codes: 0 = UP, 1 = DOWN, 2 = UNREACHABLE

---

## KubeArmor Zero-Trust Policy (PS3)

Defined in k8s/kubearmor-policy.yaml:

| Policy                       | Action | Description                                         |
|------------------------------|--------|-----------------------------------------------------|
| wisecow-allow-processes      | Allow  | Only allows bash, cowsay, fortune, nc, cat, readlink |
| wisecow-restrict-files       | Allow  | Only allows /app/, /tmp/, /usr/share/games/         |
| wisecow-block-sensitive-files| Block  | Blocks /etc/shadow, /root/, /credentials/           |
| wisecow-restrict-network     | Block  | Blocks ICMP and non-nc TCP connections               |
| wisecow-block-capabilities   | Block  | Blocks net_raw, sys_admin, sys_ptrace, net_admin     |

### Apply the Policy

```bash
kubectl apply -f k8s/kubearmor-policy.yaml
kubectl get kubearmorpolicy -n wisecow
karmor logs -n wisecow
```

### Verify Policy Violations

```bash
kubectl exec -n wisecow deployment/wisecow-deployment -- cat /etc/shadow
kubectl exec -n wisecow deployment/wisecow-deployment -- /bin/ls
```

---

## Quick Start

```bash
git clone https://github.com/<your-username>/wisecow.git
cd wisecow
docker build -t wisecow:latest .
docker run -d -p 4499:4499 wisecow:latest
curl http://localhost:4499/
kubectl apply -f k8s/namespace.yaml
./tls/generate-certs.sh
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/ingress.yaml
kubectl apply -f k8s/kubearmor-policy.yaml
./scripts/system_health_monitor.sh
./scripts/app_health_checker.sh -u http://wisecow-service:80
```

---

## License

This project is part of the Accuknox DevOps Trainee Practical Assessment.
