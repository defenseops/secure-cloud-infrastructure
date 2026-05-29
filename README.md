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
│       │   │   ├── SecurityConfig.java   # RBAC + @PreAuthorize + HTTP Basic + CORS
│       │   │   └── AwsConfig.java        # S3Client → LocalStack endpoint
│       │   ├── service/
│       │   │   └── S3Service.java        # listFiles(), uploadFile(), downloadFile()
│       │   └── controller/
│       │       ├── FileController.java   # GET /files, POST /files/upload, GET /files/download/{name}, GET /files/view/{name}
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

Проверка:

```bash
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1

aws --endpoint-url=http://localhost:4566 s3 ls
aws --endpoint-url=http://localhost:4566 dynamodb list-tables
aws --endpoint-url=http://localhost:4566 dynamodb scan --table-name users
```

> **Важно:** если `terraform apply` зависает на создании S3 bucket дольше 30 секунд — это
> проблема виртуального-hosted стиля. В AWS provider v5 по умолчанию используется
> `bucket.localhost:4566`, которого не существует. Исправлено добавлением
> `s3_use_path_style = true` в `terraform/main.tf`.

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
6. Создание S3 bucket в кластерном LocalStack
7. Вывод адресов для доступа

> **Важно:** LocalStack внутри кластера Kubernetes изолирован от локального LocalStack.
> После деплоя скрипт автоматически создаёт bucket внутри кластера:
> ```bash
> kubectl exec -n cloud-app deployment/localstack -- awslocal s3 mb s3://documents-bucket
> ```
> Если всё равно ошибка 500 на `/files` — выполните эту команду вручную.

---

## Адреса сервисов

```bash
NODE_IP=$(hostname -I | awk '{print $1}')   # узнать IP VM

Веб-сайт:   http://$NODE_IP:30000
Spring API: http://$NODE_IP:30080
Prometheus: http://$NODE_IP:30090
Grafana:    http://$NODE_IP:30030  (admin / admin)
```

> **Примечание:** если NodePort не доступен снаружи (k3s по умолчанию слушает только на
> localhost), используйте socat для проброса портов:
>
> ```bash
> # Установить socat
> sudo apt-get install -y socat
>
> # Пробросить все 4 порта на внешний интерфейс (запустить в фоне)
> sudo socat TCP-LISTEN:30000,fork,reuseaddr,bind=0.0.0.0 TCP:127.0.0.1:30000 &
> sudo socat TCP-LISTEN:30080,fork,reuseaddr,bind=0.0.0.0 TCP:127.0.0.1:30080 &
> sudo socat TCP-LISTEN:30090,fork,reuseaddr,bind=0.0.0.0 TCP:127.0.0.1:30090 &
> sudo socat TCP-LISTEN:30030,fork,reuseaddr,bind=0.0.0.0 TCP:127.0.0.1:30030 &
> ```

---

## RBAC — Управление доступом

| Endpoint | VIEWER | EDITOR | ADMIN |
|----------|:------:|:------:|:-----:|
| `GET /files` | ✅ | ✅ | ✅ |
| `GET /files/download/{name}` | ✅ | ✅ | ✅ |
| `GET /files/view/{name}` | ✅ | ✅ | ✅ |
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
| RBAC (3 роли) | Spring Security `@PreAuthorize` на каждом endpoint |
| Без хардкода секретов | AWS credentials хранятся в K8s Secret → env vars |
| Non-root контейнер | `USER appuser` (uid 1001) в Dockerfile + `runAsNonRoot: true` в Pod spec |
| Минимум привилегий | `ServiceAccount` с `automountServiceAccountToken: false` + `drop: ALL` capabilities |
| Сетевая изоляция | `NetworkPolicy` — egress только к LocalStack (:4566) + DNS (:53) |
| Разделение конфигурации | K8s ConfigMap для несекретных настроек (URL, регион, имя bucket) |
| Высокая доступность | `replicas: 2` + liveness/readiness probes на `/actuator/health` |

---

## Известные проблемы и решения

### Terraform зависает при создании S3 bucket
AWS provider v5 по умолчанию использует virtual-hosted style (`bucket.host`), которого нет в LocalStack. Исправлено в `terraform/main.tf`:
```hcl
s3_use_path_style = true
```

### kubectl: permission denied на k3s.yaml
k3s.yaml принадлежит root. Решение — скопировать в домашнюю папку:
```bash
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
export KUBECONFIG=~/.kube/config
```

### /files возвращает 500 после деплоя
LocalStack внутри кластера — отдельный экземпляр без данных. Нужно создать bucket:
```bash
kubectl exec -n cloud-app deployment/localstack -- awslocal s3 mb s3://documents-bucket
```

### CoreDNS не готов после перезапуска k3s
Если k3s запущен с неправильным IP (например после смены сети в VM), CoreDNS не может подключиться к API server:
```bash
# Добавить IP в /etc/systemd/system/k3s.service в секцию ExecStart:
#   --node-ip=<VM_IP>
#   --node-external-ip=<VM_IP>
#   --advertise-address=<VM_IP>
sudo systemctl daemon-reload
sudo systemctl restart k3s
# Если endpoint kubernetes всё ещё старый — удалить etcd базу:
sudo systemctl stop k3s
sudo rm -rf /var/lib/rancher/k3s/server/db
sudo systemctl start k3s
# После запуска k3s заново выполнить deploy-k8s.sh
```

### NodePort не доступен снаружи VM
k3s NodePort по умолчанию слушает только на 127.0.0.1. Пробросить через socat:
```bash
sudo apt-get install -y socat
sudo socat TCP-LISTEN:30080,fork,reuseaddr,bind=0.0.0.0 TCP:127.0.0.1:30080 &
```

---

## Соответствие критериям оценивания

| Категория | Критерий | Баллы | Статус |
|-----------|----------|-------|--------|
| IaC | Terraform создаёт S3 + DynamoDB в LocalStack | 20 | ✅ |
| Безопасность | Spring Security RBAC — 3 роли работают корректно | 20 | ✅ |
| Безопасность | Нет хардкода — AWS credentials через K8s Secrets | 15 | ✅ |
| Kubernetes | Приложение запущено в K8s (2 реплики) и доступно | 15 | ✅ |
| Мониторинг | Prometheus собирает метрики (включая 403 ошибки) | 10 | ✅ |
| Интеграция | Приложение читает/пишет S3 в LocalStack | 10 | ✅ |
| Защита | Уверенное объяснение проекта | 10 | — |
| **ИТОГО** | | **100** | |
