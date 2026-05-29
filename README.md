# Secure Cloud Infrastructure on Microservices

Exam project — secure cloud infrastructure based on microservices with managed services.

**Stack:** Java 17 + Spring Boot 3 + Spring Security · Docker · Kubernetes · LocalStack · Terraform · Prometheus · Grafana

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                Kubernetes Cluster (minikube)         │
│  namespace: cloud-app                               │
│                                                     │
│  ┌──────────────┐      ┌──────────────────────┐    │
│  │  cloud-app   │─────▶│     LocalStack       │    │
│  │  (2 replicas)│      │  S3 + DynamoDB       │    │
│  │  :8080       │      │  :4566               │    │
│  └──────┬───────┘      └──────────────────────┘    │
│         │ /actuator/prometheus                      │
│  ┌──────▼───────┐      ┌──────────────────────┐    │
│  │  Prometheus  │      │      Grafana          │    │
│  │  :9090       │◀─────│  :3000               │    │
│  └──────────────┘      └──────────────────────┘    │
└─────────────────────────────────────────────────────┘
        │ NodePort
   ┌────▼────────────────────────────────────┐
   │  :30080 — app                           │
   │  :30090 — Prometheus                    │
   │  :30030 — Grafana                       │
   └─────────────────────────────────────────┘
```

---

## Project Structure

```
├── terraform/                  # IaC — LocalStack resources
│   ├── main.tf                 # AWS provider → http://localhost:4566
│   ├── s3.tf                   # S3 bucket: documents-bucket
│   ├── dynamodb.tf             # DynamoDB: users + roles tables (with seed data)
│   ├── variables.tf
│   └── outputs.tf
├── app/                        # Spring Boot application
│   ├── Dockerfile              # Multi-stage build, non-root user (uid 1001)
│   ├── pom.xml
│   └── src/main/
│       ├── java/com/example/cloudapp/
│       │   ├── CloudAppApplication.java
│       │   ├── config/
│       │   │   ├── SecurityConfig.java   # RBAC + @PreAuthorize
│       │   │   └── AwsConfig.java        # S3Client → LocalStack
│       │   ├── service/
│       │   │   └── S3Service.java        # listFiles(), uploadFile()
│       │   └── controller/
│       │       ├── FileController.java   # GET /files, POST /files/upload
│       │       └── AdminController.java  # GET /admin/secret
│       └── resources/
│           └── application.yml           # reads all config from env vars
├── k8s/                        # Kubernetes manifests
│   ├── namespace.yaml
│   ├── localstack.yaml         # LocalStack Deployment + ClusterIP Service
│   ├── serviceaccount.yaml     # Least Privilege (automountServiceAccountToken: false)
│   ├── configmap.yaml          # LOCALSTACK_URL, AWS_REGION, S3_BUCKET_NAME
│   ├── secret.yaml             # AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
│   ├── deployment.yaml         # 2 replicas, non-root securityContext, probes
│   ├── service.yaml            # NodePort :30080
│   └── networkpolicy.yaml      # egress только к LocalStack + DNS
├── monitoring/
│   ├── prometheus/
│   │   ├── prometheus.yml      # scrape config (reference)
│   │   ├── configmap.yaml      # prometheus.yml as K8s ConfigMap
│   │   └── deployment.yaml     # Prometheus + NodePort :30090
│   └── grafana/
│       ├── datasource-configmap.yaml    # auto-provisioned Prometheus datasource
│       ├── dashboard-configmap.yaml     # auto-provisioned 403-errors dashboard
│       └── deployment.yaml             # Grafana + NodePort :30030
├── scripts/
│   ├── setup.sh                # Start LocalStack + terraform apply (local dev)
│   └── deploy-k8s.sh           # Build image + full K8s deploy
└── docker-compose.yml          # LocalStack for local development
```

---

## Prerequisites (Ubuntu Server 22.04 VM)

```bash
# Docker
sudo apt update && sudo apt install -y docker.io docker-compose-plugin
sudo usermod -aG docker $USER && newgrp docker

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
minikube start --driver=docker --cpus=4 --memory=8192

# Terraform
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y terraform

# Java 17 + Maven
sudo apt install -y openjdk-17-jdk maven

# AWS CLI (для проверки LocalStack)
sudo apt install -y awscli
```

---

## Quick Start

### Stage 1 — LocalStack + Terraform (local dev)

```bash
./scripts/setup.sh
```

Что создаётся в LocalStack:
- S3 bucket: `documents-bucket`
- DynamoDB таблица `users` (viewer, editor, admin)
- DynamoDB таблица `roles`

Проверка:
```bash
aws --endpoint-url=http://localhost:4566 s3 ls
aws --endpoint-url=http://localhost:4566 dynamodb list-tables
```

### Stage 2–5 — Full Kubernetes Deploy

```bash
./scripts/deploy-k8s.sh
```

Скрипт выполняет:
1. `docker build` образа приложения
2. `minikube image load` — загрузка образа в кластер
3. `kubectl apply` всех манифестов (app + LocalStack + monitoring)
4. Ожидание готовности всех deployments
5. Вывод адресов для доступа

---

## RBAC — Access Control

| Endpoint | VIEWER | EDITOR | ADMIN |
|----------|:------:|:------:|:-----:|
| `GET /files` | ✅ | ✅ | ✅ |
| `POST /files/upload` | ❌ 403 | ✅ | ✅ |
| `GET /admin/secret` | ❌ 403 | ❌ 403 | ✅ |
| `/actuator/prometheus` | public | public | public |

**Users (password: `password` for all):**

| Username | Role |
|----------|------|
| viewer | ROLE_VIEWER |
| editor | ROLE_EDITOR |
| admin | ROLE_ADMIN |

### Testing RBAC

```bash
NODE_IP=$(minikube ip)

# VIEWER — list files (allowed)
curl -u viewer:password http://$NODE_IP:30080/files

# EDITOR — upload file (allowed)
echo "hello" > test.txt
curl -u editor:password -F file=@test.txt http://$NODE_IP:30080/files/upload

# ADMIN — secret endpoint (allowed)
curl -u admin:password http://$NODE_IP:30080/admin/secret

# VIEWER → /admin/secret (must return 403)
curl -u viewer:password http://$NODE_IP:30080/admin/secret

# VIEWER → upload (must return 403)
curl -u viewer:password -F file=@test.txt http://$NODE_IP:30080/files/upload
```

---

## Monitoring

| Service | URL | Credentials |
|---------|-----|-------------|
| Prometheus | `http://<minikube-ip>:30090` | — |
| Grafana | `http://<minikube-ip>:30030` | admin / admin |

### Key Prometheus Queries

```promql
# 403 Authorization errors rate per minute
rate(http_server_requests_seconds_count{status="403"}[1m]) * 60

# Total 403 errors (cumulative)
sum(http_server_requests_seconds_count{status="403"})

# All HTTP requests by status
rate(http_server_requests_seconds_count[1m]) * 60
```

### Generate 403 errors for demo

```bash
NODE_IP=$(minikube ip)
for i in $(seq 1 20); do
  curl -s -u viewer:password http://$NODE_IP:30080/admin/secret > /dev/null
done
# Open Grafana → "Auth Errors Dashboard" to see the spike
```

---

## Security Design

| Requirement | Implementation |
|-------------|----------------|
| RBAC (3 roles) | Spring Security `@PreAuthorize` on every method |
| No hardcoded secrets | All credentials via K8s Secrets → env vars |
| Non-root container | `USER appuser` (uid 1001) in Dockerfile + `runAsNonRoot: true` |
| Least Privilege | `ServiceAccount` with `automountServiceAccountToken: false` |
| Network isolation | `NetworkPolicy` — app egress only to LocalStack + DNS |
| Config separation | K8s ConfigMap for non-sensitive config |
| HA (High Availability) | `replicas: 2` with liveness/readiness probes |

---

## Grading Checklist

| Category | Criterion | Points |
|----------|-----------|--------|
| IaC | Terraform provisions S3 + DynamoDB in LocalStack | 20 |
| Security | Spring Security RBAC — 3 roles work correctly | 20 |
| Security | Zero hardcode — Secrets managed via K8s Secrets | 15 |
| K8s | App runs in K8s and is accessible | 15 |
| Monitoring | Prometheus collects metrics (including 403 errors) | 10 |
| Integration | App reads/writes S3 in LocalStack | 10 |
| Defense | Student confidently explains the project | 10 |
| **TOTAL** | | **100** |
