# Безопасная облачная инфраструктура на микросервисах

Финальный экзаменационный проект — безопасная облачная инфраструктура на основе микросервисов с использованием managed-сервисов.

---

## Стек технологий

| Слой | Технология |
|------|------------|
| Язык / Фреймворк | Java 17 + Spring Boot 3.3 |
| Безопасность | Spring Security 6 — HTTP Basic, `@PreAuthorize`, RBAC |
| Контейнеризация | Docker (multi-stage build, non-root пользователь) |
| Оркестрация | Kubernetes — k3s (облегчённый дистрибутив, ~512 MB RAM) |
| Эмуляция AWS | LocalStack 3.4 — S3 + DynamoDB на порту 4566 |
| IaC | Terraform 1.5+ (provider hashicorp/aws ~5.0) |
| Мониторинг | Prometheus + Grafana (автоматически provisioned дашборд) |
| Метрики | Spring Actuator + Micrometer Prometheus Registry |
| AWS SDK | AWS SDK for Java v2 (2.25.60) — S3Client, path-style |
| ОС / Архитектура | Ubuntu Server 22.04, arm64 (aarch64) |

---

## Архитектура

```
┌──────────────────────────────────────────────────────────┐
│              Kubernetes Cluster (k3s)                    │
│  namespace: cloud-app                                    │
│                                                          │
│  ┌─────────────────┐      ┌──────────────────────────┐  │
│  │   cloud-app     │─────▶│       LocalStack         │  │
│  │   (2 реплики)   │      │   S3 + DynamoDB          │  │
│  │   :8080         │      │   :4566                  │  │
│  └────────┬────────┘      └──────────────────────────┘  │
│           │ /actuator/prometheus                         │
│  ┌────────▼────────┐      ┌──────────────────────────┐  │
│  │   Prometheus    │◀─────│        Grafana            │  │
│  │   :9090         │      │   :3000                  │  │
│  └─────────────────┘      └──────────────────────────┘  │
│                                                          │
│  ┌─────────────────┐                                    │
│  │   nginx (web)   │  — статический сайт               │
│  │   :80           │                                    │
│  └─────────────────┘                                    │
└──────────────────────────────────────────────────────────┘
         │ NodePort
   ──────┴──────────────────────────────────
   :30000 — веб-сайт (nginx)
   :30080 — Spring Boot API
   :30090 — Prometheus
   :30030 — Grafana
```

---

## Структура проекта

```
├── terraform/
│   ├── main.tf           # AWS provider → LocalStack (s3_use_path_style = true)
│   ├── s3.tf             # S3 bucket: documents-bucket
│   ├── dynamodb.tf       # DynamoDB: таблицы users + roles (seed данные)
│   ├── variables.tf
│   └── outputs.tf
├── app/
│   ├── Dockerfile        # Multi-stage build, non-root пользователь appuser (uid 1001)
│   ├── pom.xml
│   └── src/main/
│       ├── java/com/example/cloudapp/
│       │   ├── config/
│       │   │   ├── SecurityConfig.java   # RBAC + @PreAuthorize + HTTP Basic
│       │   │   └── AwsConfig.java        # S3Client → LocalStack endpoint
│       │   ├── service/
│       │   │   └── S3Service.java        # listFiles(), uploadFile()
│       │   └── controller/
│       │       ├── FileController.java   # GET /files, POST /files/upload
│       │       └── AdminController.java  # GET /admin/secret
│       └── resources/
│           └── application.yml
├── k8s/
│   ├── namespace.yaml
│   ├── localstack.yaml       # LocalStack Deployment + ClusterIP Service
│   ├── serviceaccount.yaml   # automountServiceAccountToken: false
│   ├── configmap.yaml        # LOCALSTACK_URL, AWS_REGION, S3_BUCKET_NAME
│   ├── secret.yaml           # AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
│   ├── deployment.yaml       # 2 реплики, runAsNonRoot, drop ALL capabilities
│   ├── service.yaml          # NodePort :30080
│   ├── web.yaml              # nginx для веб-сайта, NodePort :30000
│   └── networkpolicy.yaml    # egress только к LocalStack + DNS
├── monitoring/
│   ├── prometheus/
│   │   ├── configmap.yaml    # scrape config
│   │   └── deployment.yaml   # NodePort :30090
│   └── grafana/
│       ├── datasource-configmap.yaml   # автоматический datasource Prometheus
│       ├── dashboard-configmap.yaml    # дашборд 403 ошибок
│       └── deployment.yaml            # NodePort :30030
├── web/
│   ├── Dockerfile        # nginx образ со статическим сайтом
│   ├── index.html        # Glassmorphism лендинг
│   ├── dashboard.html    # интерактивный дашборд
│   ├── css/
│   └── js/
├── scripts/
│   ├── setup.sh          # запуск LocalStack + terraform apply
│   ├── deploy-k8s.sh     # сборка образов + деплой в k3s
│   └── install-ubuntu.sh # установка всех зависимостей
└── docker-compose.yml    # LocalStack для локальной разработки
```

---

## Установка зависимостей (Ubuntu Server 22.04, arm64)

```bash
chmod +x scripts/install-ubuntu.sh
./scripts/install-ubuntu.sh
```

Скрипт устанавливает: Docker, k3s, Terraform, Java 17, Maven, AWS CLI.

После установки настроить kubectl без sudo:

```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
export KUBECONFIG=~/.kube/config
```

Добавить в `~/.bashrc` чтобы не вводить каждый раз:

```bash
echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc
source ~/.bashrc
```

---

## Запуск проекта

### Этап 1 — LocalStack + Terraform

```bash
chmod +x scripts/setup.sh
./scripts/setup.sh
```

Создаётся в LocalStack:
- S3 bucket: `documents-bucket`
- DynamoDB таблица `users` (viewer, editor, admin + BCrypt хеши)
- DynamoDB таблица `roles`

Проверка (установить credentials перед запуском):

```bash
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1

aws --endpoint-url=http://localhost:4566 s3 ls
aws --endpoint-url=http://localhost:4566 dynamodb list-tables
aws --endpoint-url=http://localhost:4566 dynamodb scan --table-name users
```

> **Важно:** если terraform apply зависает на создании S3 bucket — проблема в отсутствии `s3_use_path_style = true` в provider. Это уже исправлено в `terraform/main.tf`.

### Этап 2–5 — Сборка и деплой в Kubernetes

```bash
export KUBECONFIG=~/.kube/config
chmod +x scripts/deploy-k8s.sh
./scripts/deploy-k8s.sh
```

Скрипт выполняет:
1. `docker build` образа приложения (`cloud-app:latest`)
2. `docker build` образа веб-сайта (`cloud-web:latest`)
3. `docker save | k3s ctr images import` — загрузка образов в k3s (без registry)
4. `kubectl apply` всех манифестов (namespace → localstack → app → monitoring → web)
5. Ожидание готовности всех Deployments
6. Вывод адресов для доступа

> **Важно:** после первого деплоя нужно создать S3 bucket в кластерном LocalStack (он изолирован от локального):
>
> ```bash
> kubectl exec -n cloud-app deployment/localstack -- awslocal s3 mb s3://documents-bucket
> ```

---

## Адреса сервисов

```
NODE_IP=192.168.64.11   # IP вашей VM (узнать: hostname -I | awk '{print $1}')

Веб-сайт:   http://$NODE_IP:30000
Spring API: http://$NODE_IP:30080
Prometheus: http://$NODE_IP:30090
Grafana:    http://$NODE_IP:30030  (admin / admin)
```

---

## RBAC — Управление доступом

| Endpoint | VIEWER | EDITOR | ADMIN |
|----------|:------:|:------:|:-----:|
| `GET /files` | ✅ | ✅ | ✅ |
| `POST /files/upload` | ❌ 403 | ✅ | ✅ |
| `GET /admin/secret` | ❌ 403 | ❌ 403 | ✅ |
| `/actuator/prometheus` | публичный | публичный | публичный |
| `/actuator/health` | публичный | публичный | публичный |

**Пользователи (пароль для всех: `password`):**

| Логин | Роль |
|-------|------|
| `viewer` | ROLE_VIEWER |
| `editor` | ROLE_EDITOR |
| `admin` | ROLE_ADMIN |

### Тестирование RBAC

```bash
NODE_IP=$(hostname -I | awk '{print $1}')

# VIEWER — читает файлы (разрешено)
curl -u viewer:password http://$NODE_IP:30080/files

# EDITOR — загружает файл (разрешено)
echo "test" > test.txt
curl -u editor:password -F file=@test.txt http://$NODE_IP:30080/files/upload

# ADMIN — секретный эндпоинт (разрешено)
curl -u admin:password http://$NODE_IP:30080/admin/secret

# VIEWER → /admin/secret — должен вернуть 403
curl -u viewer:password http://$NODE_IP:30080/admin/secret

# VIEWER → /files/upload — должен вернуть 403
curl -u viewer:password -F file=@test.txt http://$NODE_IP:30080/files/upload
```

---

## Мониторинг

Prometheus автоматически собирает метрики с `cloud-app-service.cloud-app.svc.cluster.local:8080/actuator/prometheus` каждые 15 секунд.

Grafana содержит автоматически provisioned дашборд **"Auth Errors Dashboard"** с тремя панелями:
- Частота 403 ошибок в минуту
- Суммарное количество 403 ошибок
- Все HTTP запросы по статусам

### Ключевые PromQL запросы

```promql
# Частота 403 ошибок в минуту
rate(http_server_requests_seconds_count{status="403"}[1m]) * 60

# Суммарное количество 403 ошибок
sum(http_server_requests_seconds_count{status="403"})

# Все запросы по статусам
rate(http_server_requests_seconds_count[1m]) * 60
```

### Генерация 403 ошибок для демонстрации

```bash
NODE_IP=$(hostname -I | awk '{print $1}')
for i in {1..20}; do
  curl -s -u viewer:password http://$NODE_IP:30080/admin/secret
done
# Открыть Grafana → Auth Errors Dashboard — всплеск на графике
```

---

## Безопасность

| Требование | Реализация |
|------------|------------|
| RBAC (3 роли) | Spring Security `@PreAuthorize` на каждом методе |
| Без хардкода секретов | Все credentials через K8s Secrets → env vars |
| Non-root контейнер | `USER appuser` (uid 1001) в Dockerfile + `runAsNonRoot: true` |
| Минимум привилегий | `ServiceAccount` с `automountServiceAccountToken: false` + `drop: ALL` capabilities |
| Сетевая изоляция | `NetworkPolicy` — egress только к LocalStack (4566) + DNS (53) |
| Разделение конфигурации | K8s ConfigMap для несекретных настроек |
| Высокая доступность | `replicas: 2` + liveness/readiness probes на `/actuator/health` |

---

## Баллы

| Категория | Критерий | Баллы |
|-----------|----------|-------|
| IaC | Terraform создаёт S3 + DynamoDB в LocalStack | 20 |
| Безопасность | Spring Security RBAC — 3 роли работают корректно | 20 |
| Безопасность | Нет хардкода — секреты через K8s Secrets | 15 |
| Kubernetes | Приложение запущено в K8s и доступно | 15 |
| Мониторинг | Prometheus собирает метрики (включая 403 ошибки) | 10 |
| Интеграция | Приложение читает/пишет S3 в LocalStack | 10 |
| Защита | Уверенное объяснение проекта | 10 |
| **ИТОГО** | | **100** |
