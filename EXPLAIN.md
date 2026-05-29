# Объяснение проекта простыми словами

Этот документ объясняет каждую часть проекта так, как если бы вы никогда раньше не программировали. Никаких сложных слов без объяснения.

---

## Что такое этот проект вообще?

Представьте, что вы строите небольшой офис в облаке. В этом офисе:

- Есть **сотрудники** трёх уровней: наблюдатель, редактор и администратор
- Каждый может делать только то, что разрешено его уровню
- Всё хранится в специальном хранилище файлов (как Google Drive, только ваш)
- Специальная система следит за тем, кто пытался войти куда не разрешено
- Всё это работает внутри контейнеров — изолированных «коробок», каждая со своей программой

---

## Из чего состоит проект

```
Пользователь
    │
    ▼
[ Веб-сайт ] — красивый интерфейс для демонстрации
    │
    ▼
[ Spring Boot приложение ] — основная логика, проверяет кто есть кто
    │
    ├──▶ [ LocalStack S3 ] — хранилище файлов (имитация Amazon)
    │
    └──▶ [ LocalStack DynamoDB ] — база данных пользователей
    
[ Prometheus ] — каждые 15 секунд собирает статистику у приложения
    │
    ▼
[ Grafana ] — рисует красивые графики из этой статистики

Всё это упаковано в [ Docker контейнеры ]
и управляется системой [ Kubernetes (k3s) ]
Инфраструктура создана через [ Terraform ]
```

---

## Папка `terraform/` — создание инфраструктуры

> **Terraform** — это инструмент, которому вы говорите «создай мне вот такие ресурсы», и он их создаёт. Как заказ мебели из каталога: описываешь что хочешь, нажимаешь кнопку — получаешь.

> **LocalStack** — это программа, которая притворяется Amazon Web Services (AWS). Вместо того чтобы платить Amazon за облачные сервисы, мы запускаем их копию прямо на нашем компьютере. Бесплатно.

### `terraform/main.tf` — настройка подключения

```hcl
provider "aws" {
  region     = var.aws_region
  access_key = "test"
  secret_key = "test"
  s3_use_path_style = true        # ← ВАЖНО для LocalStack
  ...
  endpoints {
    s3       = var.localstack_endpoint   # http://localhost:4566
    dynamodb = var.localstack_endpoint
  }
}
```

**Что это делает:** говорит Terraform «когда ты думаешь что работаешь с Amazon — на самом деле иди по адресу localhost:4566, это наш локальный Amazon».

`s3_use_path_style = true` — без этой строки Terraform пытается обратиться к `documents-bucket.localhost:4566` (несуществующий адрес) вместо `localhost:4566/documents-bucket`. Мы добавили это после того как terraform завис на 9 минут.

### `terraform/s3.tf` — создание хранилища файлов

```hcl
resource "aws_s3_bucket" "documents" {
  bucket = "documents-bucket"
}
```

**Что это делает:** создаёт «папку» (bucket) с именем `documents-bucket` в LocalStack. Туда наше приложение будет загружать и читать файлы. S3 — это как Dropbox, только от Amazon.

### `terraform/dynamodb.tf` — создание базы данных пользователей

**Что это делает:** создаёт две таблицы:
- `users` — список пользователей с их паролями и ролями
- `roles` — список ролей

Туда сразу добавляются три пользователя: viewer, editor, admin. Пароли хранятся не в открытом виде, а зашифрованными (BCrypt хеш). Даже если кто-то украдёт базу — пароли не узнает.

### `terraform/variables.tf` — переменные

Как «настройки» для Terraform. Например: какой адрес у LocalStack, как называется регион. Это сделано чтобы не писать одно и то же значение в 10 местах — меняешь в одном месте, меняется везде.

### `terraform/outputs.tf` — что показать после создания

После того как Terraform всё создал, он выводит итог: имя bucket, имена таблиц. Как чек после покупки.

---

## Папка `app/` — основное приложение

> **Spring Boot** — это фреймворк (готовый каркас) для написания веб-приложений на Java. Как конструктор LEGO: берёшь готовые блоки и собираешь нужное.

### `app/Dockerfile` — рецепт для сборки контейнера

```dockerfile
# Шаг 1: берём контейнер с Maven и Java, собираем приложение
FROM maven:3.9.6-eclipse-temurin-17 AS builder
WORKDIR /build
COPY pom.xml .
RUN mvn dependency:go-offline    # скачать все библиотеки
COPY src ./src
RUN mvn package -DskipTests      # собрать .jar файл

# Шаг 2: берём чистый контейнер только с Java (без Maven)
FROM eclipse-temurin:17-jre-jammy
RUN useradd -m -u 1001 -s /bin/sh appuser   # создать пользователя без прав администратора
WORKDIR /app
COPY --from=builder /build/target/*.jar app.jar
USER appuser     # запускать от имени обычного пользователя, не root
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

**Зачем два шага?** Первый шаг — «строительная площадка» с кучей инструментов. Второй шаг — готовый маленький контейнер только с результатом. Итоговый образ меньше и безопаснее.

**Зачем `appuser`?** Запускать программу от имени `root` (администратора) внутри контейнера — плохая практика. Если программу взломают, взломщик получит права администратора. `appuser` — обычный пользователь без лишних прав.

### `app/pom.xml` — список зависимостей

> **pom.xml** — это как список покупок для Java. Описывает какие готовые библиотеки нужно скачать.

Ключевые зависимости:
- `spring-boot-starter-security` — безопасность и авторизация
- `spring-boot-starter-web` — HTTP сервер, обработка запросов
- `spring-boot-starter-actuator` — эндпоинты для мониторинга (/health, /prometheus)
- `micrometer-registry-prometheus` — экспорт метрик в формате Prometheus
- `aws-sdk-s3` и `aws-sdk-dynamodb` — работа с AWS (LocalStack)

### `app/src/main/resources/application.yml` — конфигурация приложения

```yaml
cloud.aws:
  endpoint: ${LOCALSTACK_URL:http://localhost:4566}
  region: ${AWS_REGION:us-east-1}
  s3-bucket: ${S3_BUCKET_NAME:documents-bucket}

management.endpoints.web.exposure.include: health,prometheus,info
```

**Что делают `${LOCALSTACK_URL:http://localhost:4566}`?** Это переменная среды. Приложение сначала смотрит — есть ли переменная `LOCALSTACK_URL` в системе? Есть — использует её. Нет — использует значение по умолчанию `http://localhost:4566`. Это позволяет одно и то же приложение запускать и локально, и в Kubernetes — просто меняя переменные среды.

---

## Папка `app/src/main/java/` — исходный код

### `config/SecurityConfig.java` — кто что может делать

```java
@EnableMethodSecurity(prePostEnabled = true)  // включить проверки на уровне методов
```

Здесь описаны три пользователя:
- `viewer` с ролью `ROLE_VIEWER`
- `editor` с ролью `ROLE_EDITOR`
- `admin` с ролью `ROLE_ADMIN`

Все с паролем `password`, зашифрованным BCrypt.

**HTTP Basic авторизация** — самый простой способ: браузер или curl отправляет логин:пароль в заголовке каждого запроса. Приложение проверяет — правильно ли.

### `config/AwsConfig.java` — подключение к LocalStack S3

```java
S3Client.builder()
    .endpointOverride(URI.create(localstackUrl))  // идти в LocalStack, не в Amazon
    .forcePathStyle(true)                          // path-style: localhost/bucket
    .build();
```

Создаёт клиент для работы с S3. Без `forcePathStyle(true)` клиент пытается обратиться к `bucket.localhost` — такого адреса нет, всё ломается.

### `service/S3Service.java` — работа с файлами

Два метода:
- `listFiles()` — получить список файлов из bucket (как `ls` в папке)
- `uploadFile(MultipartFile)` — загрузить файл в bucket

### `controller/FileController.java` — HTTP эндпоинты для файлов

```java
@GetMapping("/files")
@PreAuthorize("hasAnyRole('VIEWER','EDITOR','ADMIN')")
public List<String> listFiles() { ... }

@PostMapping("/files/upload")
@PreAuthorize("hasAnyRole('EDITOR','ADMIN')")
public String uploadFile(@RequestParam MultipartFile file) { ... }
```

**`@PreAuthorize`** — аннотация (пометка), которая говорит: «прежде чем выполнить этот метод — проверь роль пользователя». Если роль не подходит — автоматически вернуть ошибку 403 Forbidden. Не нужно писать проверки вручную.

### `controller/AdminController.java` — секретный эндпоинт

```java
@GetMapping("/admin/secret")
@PreAuthorize("hasRole('ADMIN')")
public Map<String, String> getSecret() { ... }
```

Только для ADMIN. Viewer и Editor получат 403. Именно эти 403 ошибки мы потом видим в Grafana.

---

## Папка `k8s/` — управление контейнерами в Kubernetes

> **Kubernetes** (сокращённо K8s) — система управления контейнерами. Представьте, что контейнеры — это корабли в море, а Kubernetes — это диспетчерский центр порта. Он решает: где поставить корабль, сколько их должно быть, что делать если один затонул.

> **k3s** — облегчённая версия Kubernetes. Обычный Kubernetes требует ~2 ГБ RAM, k3s работает с ~512 МБ. Идеально для нашей VM с 4 ГБ.

### `k8s/namespace.yaml` — отдельное пространство

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: cloud-app
```

Namespace — как отдельная комната в большом здании. Все наши компоненты живут в комнате `cloud-app`. Это изолирует их от других приложений в кластере.

### `k8s/deployment.yaml` — запуск приложения

```yaml
replicas: 2              # запустить 2 копии приложения
```

**Зачем 2 копии?** Если одна упадёт — вторая продолжает работать. Пользователи не заметят сбоя. Это называется High Availability (высокая доступность).

```yaml
securityContext:
  runAsNonRoot: true     # не запускать от имени root
  runAsUser: 1001        # запускать от имени пользователя с ID 1001 (appuser)
  capabilities:
    drop: ["ALL"]        # убрать все системные привилегии
```

Это безопасность на уровне Kubernetes — дополнительная защита поверх того, что уже есть в Dockerfile.

```yaml
livenessProbe:           # проверять жив ли контейнер
  httpGet:
    path: /actuator/health
readinessProbe:          # готов ли принимать запросы
  httpGet:
    path: /actuator/health
```

**Probe** — Kubernetes периодически «стучится» на `/actuator/health`. Если приложение не отвечает — Kubernetes перезапускает контейнер.

### `k8s/service.yaml` — как попасть к приложению снаружи

```yaml
type: NodePort
ports:
  - port: 8080
    nodePort: 30080
```

Контейнер закрыт внутри кластера. `Service` создаёт «дырочку» наружу. `NodePort` означает: открыть порт на самой виртуальной машине. Заходишь на `VM_IP:30080` — попадаешь в приложение.

### `k8s/secret.yaml` — секреты

```yaml
kind: Secret
data:
  AWS_ACCESS_KEY_ID: dGVzdA==     # "test" в base64
  AWS_SECRET_ACCESS_KEY: dGVzdA==
```

Секреты хранятся отдельно от конфигурации. В коде нет паролей — они приходят как переменные среды из Secret. Base64 — это не шифрование, просто кодировка. Настоящие секреты в production шифруются иначе.

### `k8s/configmap.yaml` — конфигурация

```yaml
kind: ConfigMap
data:
  LOCALSTACK_URL: "http://localstack.cloud-app.svc.cluster.local:4566"
```

Несекретные настройки. Внутри кластера сервисы общаются по DNS-имени: `localstack.cloud-app.svc.cluster.local` — это автоматически создаваемый адрес сервиса LocalStack внутри кластера.

### `k8s/networkpolicy.yaml` — сетевой брандмауэр

```yaml
kind: NetworkPolicy
```

Ограничивает сетевой трафик. Наше приложение может:
- Отправлять запросы к LocalStack на порту 4566
- Обращаться к DNS на порту 53

Всё остальное — запрещено. Даже если приложение взломают — взломщик не сможет «позвонить домой» через интернет.

### `k8s/serviceaccount.yaml` — учётная запись для приложения

```yaml
automountServiceAccountToken: false
```

Каждый pod в Kubernetes автоматически получает токен для доступа к API кластера. Нашему приложению это не нужно. Выключаем — убираем лишний вектор атаки.

### `k8s/localstack.yaml` — LocalStack внутри кластера

LocalStack запускается как отдельный pod внутри Kubernetes. Приложение общается с ним через внутреннюю сеть кластера.

**Важный момент:** LocalStack внутри кластера — это отдельный экземпляр. У него своё хранилище. Поэтому после деплоя нужно создавать bucket заново:
```bash
kubectl exec -n cloud-app deployment/localstack -- awslocal s3 mb s3://documents-bucket
```

### `k8s/web.yaml` — веб-сайт

```yaml
# Deployment для nginx с нашим сайтом
nodePort: 30000
```

nginx — популярный веб-сервер. Отдаёт статические HTML/CSS/JS файлы. Доступен на порту 30000.

---

## Папка `monitoring/` — сбор и отображение метрик

### `monitoring/prometheus/configmap.yaml` — что собирать

```yaml
scrape_configs:
  - job_name: 'cloud-app'
    scrape_interval: 15s
    static_configs:
      - targets: ['cloud-app-service.cloud-app.svc.cluster.local:8080']
    metrics_path: '/actuator/prometheus'
```

**Prometheus** — система мониторинга. Каждые 15 секунд идёт к нашему приложению на `/actuator/prometheus` и забирает свежую статистику. Это называется scraping (скрейпинг).

Spring Boot с библиотекой Micrometer автоматически предоставляет метрики на этом эндпоинте: количество запросов, время ответа, статусы (200, 403, 500...).

### `monitoring/grafana/dashboard-configmap.yaml` — дашборд

Grafana читает данные из Prometheus и рисует графики. Мы заранее описали дашборд в JSON — он появляется автоматически при запуске, не нужно настраивать вручную.

Три панели:
1. График частоты 403 ошибок в минуту
2. Счётчик всего 403 ошибок
3. Все HTTP статусы вместе

PromQL запрос для 403 ошибок:
```
rate(http_server_requests_seconds_count{status="403"}[1m]) * 60
```
Читается: «взять метрику `http_server_requests_seconds_count` где статус = 403, посчитать скорость изменения за последнюю минуту, умножить на 60 чтобы получить количество в минуту».

---

## Папка `web/` — сайт-интерфейс

### `web/index.html` — главная страница

Красивый лендинг в стиле Glassmorphism (стекло + размытие). Объясняет что такое проект, показывает архитектуру, таблицу RBAC.

### `web/dashboard.html` — интерактивный дашборд

Позволяет:
- Войти как viewer/editor/admin
- Видеть список файлов из S3
- Загружать файлы (если есть права)
- Вызвать `/admin/secret`
- Тестировать RBAC — нажимаешь кнопку, видишь 200 или 403

Работает в двух режимах:
- **Боевой режим**: если Spring Boot запущен — реальные запросы к API
- **Демо режим**: если Spring Boot не запущен — показывает симулированные данные

### `web/Dockerfile` — упаковка сайта в контейнер

```dockerfile
FROM nginx:alpine
COPY index.html /usr/share/nginx/html/
COPY dashboard.html /usr/share/nginx/html/
COPY css/ /usr/share/nginx/html/css/
COPY js/ /usr/share/nginx/html/js/
```

Берём минимальный образ nginx, кладём туда наши файлы. nginx будет отдавать их браузеру.

---

## Папка `scripts/` — автоматизация

### `scripts/setup.sh` — запуск локальной инфраструктуры

```bash
docker compose up -d    # запустить LocalStack в Docker
# подождать пока LocalStack готов
terraform init          # скачать провайдер AWS для Terraform
terraform apply         # создать S3 bucket и DynamoDB таблицы
```

Запускается один раз перед разработкой. Поднимает LocalStack и создаёт все нужные ресурсы.

### `scripts/deploy-k8s.sh` — полный деплой в Kubernetes

```bash
docker build -t cloud-app:latest ./app         # собрать образ приложения
docker build -t cloud-web:latest ./web         # собрать образ веб-сайта
docker save cloud-app:latest | sudo k3s ctr images import -  # загрузить в k3s
kubectl apply -f k8s/                          # задеплоить всё
kubectl exec ... -- awslocal s3 mb s3://documents-bucket  # создать bucket в кластере
```

**Почему `docker save | k3s ctr images import`?** Обычно образы берутся из интернет-реестра (Docker Hub). У нас нет реестра. Поэтому мы «экспортируем» образ из Docker в файл и «импортируем» его прямо в k3s. Это локальная загрузка без интернета.

### `scripts/install-ubuntu.sh` — установка всего на Ubuntu

Автоматически устанавливает: Docker, k3s, Terraform, Java 17, Maven, AWS CLI. Чтобы не делать это вручную командами.

---

## `docker-compose.yml` — LocalStack для локальной разработки

```yaml
services:
  localstack:
    image: localstack/localstack:3.4
    ports:
      - "4566:4566"     # единый порт для всех AWS сервисов
    environment:
      - SERVICES=s3,dynamodb
```

Запускает LocalStack только с S3 и DynamoDB. Этот файл используется для локальной разработки на компьютере разработчика — когда ещё нет Kubernetes.

---

## Как всё связано вместе

```
1. Разработчик пишет код в папке app/

2. Terraform создаёт инфраструктуру в LocalStack:
   - S3 bucket для файлов
   - DynamoDB с пользователями

3. Docker собирает приложение в образ:
   app/ → Dockerfile → cloud-app:latest

4. k3s (Kubernetes) запускает образ:
   cloud-app:latest → 2 рабочих пода

5. Kubernetes настраивает сеть:
   - Service открывает порт 30080 наружу
   - NetworkPolicy закрывает лишний трафик

6. Приложение работает:
   - Проверяет логин через Spring Security
   - Читает/пишет файлы в LocalStack S3
   - Выдаёт метрики на /actuator/prometheus

7. Prometheus каждые 15 секунд забирает метрики

8. Grafana показывает красивые графики из данных Prometheus

9. Пользователь открывает браузер:
   - :30000 — красивый сайт
   - :30080 — API приложения
   - :30090 — Prometheus
   - :30030 — Grafana
```

---

## Частые ошибки и их причины

### Terraform завис на создании S3 bucket
**Причина:** не указан `s3_use_path_style = true` в provider. Terraform пытается обратиться к `bucket-name.localhost:4566` — такого адреса не существует.
**Решение:** добавить `s3_use_path_style = true` в `terraform/main.tf`.

### `kubectl: permission denied` на k3s.yaml
**Причина:** файл `/etc/rancher/k3s/k3s.yaml` принадлежит root. kubectl не может его читать.
**Решение:**
```bash
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
export KUBECONFIG=~/.kube/config
```

### `/files` возвращает 500 — NoSuchBucketException
**Причина:** LocalStack внутри Kubernetes — это новый экземпляр с пустым хранилищем. Bucket надо создать заново.
**Решение:**
```bash
kubectl exec -n cloud-app deployment/localstack -- awslocal s3 mb s3://documents-bucket
```

### `aws: command not found`
**Причина:** AWS CLI не установлен.
**Решение:** `sudo apt install -y awscli`

### `Unable to locate credentials`
**Причина:** AWS CLI не знает какой ключ использовать.
**Решение:** задать переменные среды:
```bash
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
```

---

## Глоссарий

| Термин | Объяснение |
|--------|------------|
| **API** | Интерфейс для программ. Как меню в ресторане: список того, что можно заказать |
| **BCrypt** | Алгоритм шифрования паролей. Даже зная хеш — не можешь восстановить пароль |
| **ConfigMap** | Конфигурация в Kubernetes. Как файл настроек, но в кластере |
| **Container** | Изолированная «коробка» с программой и всем что ей нужно |
| **Docker** | Инструмент для создания и запуска контейнеров |
| **DynamoDB** | База данных Amazon в формате «ключ-значение» (как словарь) |
| **Endpoint** | Адрес в API. Например `/files` — это эндпоинт для работы с файлами |
| **Grafana** | Инструмент для визуализации данных. Рисует графики |
| **HTTP 200** | Всё хорошо, запрос выполнен успешно |
| **HTTP 403** | Forbidden — доступ запрещён, нет прав |
| **HTTP 500** | Internal Server Error — что-то сломалось внутри приложения |
| **IaC** | Infrastructure as Code — описание инфраструктуры в коде вместо ручных настроек |
| **Image** | Заготовка контейнера. Контейнер = запущенный image |
| **Kubernetes / k8s** | Система управления контейнерами |
| **k3s** | Лёгкая версия Kubernetes для небольших машин |
| **LocalStack** | Программа, которая имитирует сервисы Amazon на вашем компьютере |
| **Maven** | Инструмент сборки Java проектов. Скачивает зависимости, компилирует код |
| **Namespace** | Изолированное пространство в Kubernetes для группы компонентов |
| **NetworkPolicy** | Правила файрвола внутри Kubernetes |
| **NodePort** | Способ открыть порт на сервере чтобы попасть в сервис Kubernetes |
| **Pod** | Минимальная единица в Kubernetes. Обычно = один контейнер |
| **Prometheus** | Система сбора метрик (статистики) |
| **PromQL** | Язык запросов Prometheus. Как SQL, но для метрик |
| **RBAC** | Role-Based Access Control — управление доступом на основе ролей |
| **S3** | Simple Storage Service — облачное хранилище файлов от Amazon |
| **Secret** | Зашифрованная конфигурация в Kubernetes для паролей и ключей |
| **Service** | Объект Kubernetes, который открывает доступ к подам |
| **Spring Boot** | Фреймворк для быстрого создания Java веб-приложений |
| **Terraform** | Инструмент создания инфраструктуры через код |
| **YAML** | Формат файлов настроек. Используется в Kubernetes и многих других местах |
