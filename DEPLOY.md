# Полное руководство по запуску проекта — для начинающих

Это пошаговая инструкция. Выполняй команды строго по порядку. Каждая команда объяснена.

---

## Что нам понадобится

- Компьютер с Ubuntu Server 22.04 (или виртуальная машина)
- Минимум 4 GB оперативной памяти
- Доступ в интернет
- Подключение по SSH или терминал прямо на машине

---

## Шаг 0. Подключиться к серверу

Если у тебя виртуальная машина — подключись по SSH с основного компьютера:

```bash
ssh yarik@192.168.31.22
```

Замени `yarik` на своё имя пользователя, `192.168.31.22` — на IP твоей машины.

Узнать IP можно командой прямо на Ubuntu:

```bash
hostname -I
```

Первый адрес из вывода — это и есть IP.

---

## Шаг 1. Создать пользователя для деплоя

Лучше не работать от имени `root`. Создадим отдельного пользователя `yarik` (или любое другое имя).

Если ты уже зашёл под нужным пользователем — пропусти этот шаг.

```bash
# Создать пользователя (выполнять от root или через sudo)
sudo adduser yarik
```

Система спросит пароль и несколько вопросов — введи пароль, остальное можно пропустить нажав Enter.

```bash
# Дать пользователю права sudo (чтобы мог устанавливать программы)
sudo usermod -aG sudo yarik
```

```bash
# Переключиться на нового пользователя
su - yarik
```

---

## Шаг 2. Скачать проект

```bash
# Перейти в домашнюю папку
cd ~
```

```bash
# Скачать проект с GitHub
git clone https://github.com/ВАШ_ЛОГИН/ВАШ_РЕПОЗИТОРИЙ.git
```

```bash
# Войти в папку проекта
cd secure-cloud-infrastructure
```

> Если git не установлен:
> ```bash
> sudo apt-get install -y git
> ```

---

## Шаг 3. Установить все зависимости

Один скрипт установит всё необходимое: Docker, Kubernetes (k3s), Terraform, Java 17, Maven, AWS CLI.

```bash
chmod +x scripts/install-ubuntu.sh
./scripts/install-ubuntu.sh
```

Это займёт 5–10 минут. Скрипт будет выводить прогресс.

После завершения **обязательно** выполни эту команду — она применяет права на Docker без перезахода:

```bash
newgrp docker
```

Проверь что всё установилось:

```bash
docker --version
kubectl version --client
terraform --version
java -version
```

Каждая команда должна вывести версию без ошибок.

---

## Шаг 4. Настроить kubectl (управление Kubernetes)

k3s создаёт файл конфигурации от имени root. Нужно скопировать его в домашнюю папку чтобы пользоваться без sudo:

```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
```

```bash
# Добавить переменную окружения — чтобы kubectl знал где конфиг
echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc
source ~/.bashrc
```

Проверь что kubectl работает:

```bash
kubectl get nodes
```

Должно вывести что-то вроде:
```
NAME   STATUS   ROLES           AGE   VERSION
yari   Ready    control-plane   1m    v1.35.5+k3s1
```

Статус должен быть `Ready`.

---

## Шаг 5. Настроить IP в k3s (важно при смене сети)

Если виртуальная машина получила новый IP (например после смены режима сети), k3s нужно об этом сообщить. Узнай текущий IP:

```bash
hostname -I | awk '{print $1}'
```

Открой файл настроек k3s:

```bash
sudo nano /etc/systemd/system/k3s.service
```

Найди строку `ExecStart=/usr/local/bin/k3s` и добавь флаги с твоим IP (замени `192.168.31.22` на свой):

```
ExecStart=/usr/local/bin/k3s \
    server \
    --node-ip=192.168.31.22 \
    --node-external-ip=192.168.31.22 \
    --advertise-address=192.168.31.22 \
```

Сохрани файл: `Ctrl+O`, Enter, `Ctrl+X`.

Применить изменения:

```bash
sudo systemctl daemon-reload
sudo systemctl restart k3s
sleep 30
kubectl get nodes
```

---

## Шаг 6. Запустить LocalStack и создать инфраструктуру через Terraform

LocalStack — это эмулятор AWS (работает как настоящий Amazon, но бесплатно и локально).
Terraform — инструмент который создаёт нужные ресурсы (хранилище файлов S3, базу данных DynamoDB) по описанию.

```bash
chmod +x scripts/setup.sh
./scripts/setup.sh
```

Скрипт:
1. Запустит LocalStack в Docker
2. Подождёт пока он будет готов
3. Запустит Terraform — создаст S3 bucket и DynamoDB таблицы

Успешный вывод выглядит примерно так:
```
==> LocalStack is ready.
==> Running Terraform...
Apply complete! Resources: 4 added, 0 changed, 0 destroyed.
```

Проверить что ресурсы созданы:

```bash
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1

aws --endpoint-url=http://localhost:4566 s3 ls
aws --endpoint-url=http://localhost:4566 dynamodb list-tables
```

Должно вывести `documents-bucket` и список таблиц `["roles", "users"]`.

---

## Шаг 7. Собрать и задеплоить в Kubernetes

Этот шаг собирает Docker образы приложения, загружает их в Kubernetes и запускает все сервисы.

```bash
export KUBECONFIG=~/.kube/config
chmod +x scripts/deploy-k8s.sh
./scripts/deploy-k8s.sh
```

Скрипт делает:
1. Собирает образ Spring Boot приложения
2. Собирает образ веб-сайта (nginx)
3. Загружает образы в k3s
4. Применяет все Kubernetes манифесты
5. Ждёт пока все поды запустятся
6. Создаёт S3 bucket внутри кластерного LocalStack
7. Выводит адреса всех сервисов

Ожидание займёт 2–4 минуты. В конце увидишь:
```
==> Готово! Все сервисы запущены.
    Веб-сайт:   http://192.168.31.22:30000
    App API:    http://192.168.31.22:30080
    Prometheus: http://192.168.31.22:30090
    Grafana:    http://192.168.31.22:30030  (admin / admin)
```

---

## Шаг 8. Проверить что всё работает

Посмотреть статус всех подов:

```bash
kubectl get pods -n cloud-app
```

Все поды должны иметь статус `Running` и `READY` = `1/1` или `2/2`:

```
NAME                          READY   STATUS    RESTARTS
cloud-app-xxx                 1/1     Running   0
cloud-app-yyy                 1/1     Running   0
localstack-xxx                1/1     Running   0
prometheus-xxx                1/1     Running   0
grafana-xxx                   1/1     Running   0
web-xxx                       1/1     Running   0
```

Проверить API:

```bash
NODE_IP=$(hostname -I | awk '{print $1}')

# Получить список файлов (должен вернуть [])
curl -u viewer:password http://$NODE_IP:30080/files

# Загрузить файл
echo "Привет мир" > test.txt
curl -u editor:password -F file=@test.txt http://$NODE_IP:30080/files/upload

# Снова получить список (теперь должен вернуть ["test.txt"])
curl -u viewer:password http://$NODE_IP:30080/files

# Проверить блокировку (должен вернуть 403)
curl -u viewer:password http://$NODE_IP:30080/admin/secret
```

---

## Шаг 9. Сделать порты доступными снаружи VM (если нужен доступ с другого компьютера)

k3s по умолчанию привязывает NodePort только к `127.0.0.1` — с другого компьютера не достучаться.
Решение — socat: программа которая перенаправляет трафик.

```bash
# Установить socat
sudo apt-get install -y socat
```

```bash
# Пробросить все 4 порта (каждую команду выполнять отдельно, они уходят в фон)
sudo socat TCP-LISTEN:30000,fork,reuseaddr,bind=0.0.0.0 TCP:127.0.0.1:30000 &
sudo socat TCP-LISTEN:30080,fork,reuseaddr,bind=0.0.0.0 TCP:127.0.0.1:30080 &
sudo socat TCP-LISTEN:30090,fork,reuseaddr,bind=0.0.0.0 TCP:127.0.0.1:30090 &
sudo socat TCP-LISTEN:30030,fork,reuseaddr,bind=0.0.0.0 TCP:127.0.0.1:30030 &
```

Проверить что порты слушают:

```bash
sudo ss -tlnp | grep socat
```

Теперь с другого компьютера (например с Mac) проверь:

```bash
curl -u viewer:password http://192.168.31.22:30080/files
```

---

## Шаг 10. Открыть в браузере

Открой в браузере на своём компьютере:

| Что | Адрес |
|-----|-------|
| Веб-сайт | `http://192.168.31.22:30000` |
| Дашборд | `http://192.168.31.22:30000/dashboard.html` |
| Prometheus | `http://192.168.31.22:30090` |
| Grafana | `http://192.168.31.22:30030` |

В Grafana логин: `admin`, пароль: `admin`.

На дашборде можно войти под любым пользователем:

| Логин | Пароль | Роль |
|-------|--------|------|
| `viewer` | `password` | Только просмотр файлов |
| `editor` | `password` | Просмотр + загрузка файлов |
| `admin` | `password` | Полный доступ |

---

## Шаг 11. Сгенерировать 403 ошибки для Grafana

Чтобы увидеть графики мониторинга — нужно несколько раз попробовать зайти куда нельзя:

```bash
NODE_IP=$(hostname -I | awk '{print $1}')
for i in {1..20}; do
  curl -s -u viewer:password http://$NODE_IP:30080/admin/secret
done
```

Открой Grafana → левое меню → Dashboards → **Auth Errors Dashboard** — увидишь всплеск на графике.

---

## Что делать если что-то пошло не так

### /files возвращает 500

Значит S3 bucket не создан внутри кластера. Создай вручную:

```bash
kubectl exec -n cloud-app deployment/localstack -- awslocal s3 mb s3://documents-bucket
```

### Поды не запускаются — смотреть логи

```bash
# Посмотреть состояние подов
kubectl get pods -n cloud-app

# Посмотреть логи конкретного пода (замени имя на своё из предыдущей команды)
kubectl logs -n cloud-app deployment/cloud-app

# Посмотреть события пода
kubectl describe pod -n cloud-app -l app=cloud-app
```

### CoreDNS не готов (0/1 Running)

Это бывает после смены IP виртуальной машины. Решение:

```bash
# Проверить какой IP зарегистрирован в Kubernetes
kubectl get endpoints -n default kubernetes
```

Если IP старый — значит нужно пересоздать базу данных k3s (все поды потом запустить заново через `deploy-k8s.sh`):

```bash
sudo systemctl stop k3s
sudo rm -rf /var/lib/rancher/k3s/server/db
sudo systemctl start k3s
sleep 60
kubectl get nodes
```

### Docker: permission denied

```bash
newgrp docker
# или выйти и снова войти
exit
su - yarik
```

### terraform: command not found

Установи через snap (не требует внешних репозиториев):
```bash
sudo snap install terraform --classic
terraform --version
```

### terraform apply зависает больше минуты

Нажми `Ctrl+C`. Проверь что в `terraform/main.tf` есть строка `s3_use_path_style = true` внутри блока `provider "aws"`. Потом снова запусти `./scripts/setup.sh`.

---

## Быстрая проверка всего проекта одной командой

```bash
NODE_IP=$(hostname -I | awk '{print $1}')

echo "=== Поды ===" && kubectl get pods -n cloud-app
echo ""
echo "=== VIEWER читает файлы ===" && curl -s -u viewer:password http://$NODE_IP:30080/files
echo ""
echo "=== ADMIN видит секрет ===" && curl -s -u admin:password http://$NODE_IP:30080/admin/secret
echo ""
echo "=== VIEWER заблокирован на /admin/secret ===" && curl -s -o /dev/null -w "%{http_code}" -u viewer:password http://$NODE_IP:30080/admin/secret
echo ""
echo "=== Prometheus собирает метрики ===" && curl -s http://$NODE_IP:30090/-/ready
```
