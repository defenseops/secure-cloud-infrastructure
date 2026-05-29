#!/bin/bash
set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# k3s использует собственный kubectl — создаём алиас если нужно
if ! command -v kubectl &>/dev/null; then
  alias kubectl='k3s kubectl'
fi
export KUBECONFIG="$HOME/.kube/config"

echo "==> Building Docker images..."
docker build -t cloud-app:latest "$PROJECT_ROOT/app"
docker build -t cloud-web:latest "$PROJECT_ROOT/web"

echo "==> Loading images into k3s (bypassing registry)..."
docker save cloud-app:latest | sudo k3s ctr images import -
docker save cloud-web:latest | sudo k3s ctr images import -

echo "==> Applying Kubernetes manifests..."
kubectl apply -f "$PROJECT_ROOT/k8s/namespace.yaml"
kubectl apply -f "$PROJECT_ROOT/k8s/localstack.yaml"
kubectl apply -f "$PROJECT_ROOT/k8s/serviceaccount.yaml"
kubectl apply -f "$PROJECT_ROOT/k8s/configmap.yaml"
kubectl apply -f "$PROJECT_ROOT/k8s/secret.yaml"
kubectl apply -f "$PROJECT_ROOT/k8s/deployment.yaml"
kubectl apply -f "$PROJECT_ROOT/k8s/service.yaml"
kubectl apply -f "$PROJECT_ROOT/k8s/networkpolicy.yaml"
kubectl apply -f "$PROJECT_ROOT/k8s/web.yaml"

echo "==> Applying monitoring manifests..."
kubectl apply -f "$PROJECT_ROOT/monitoring/prometheus/configmap.yaml"
kubectl apply -f "$PROJECT_ROOT/monitoring/prometheus/deployment.yaml"
kubectl apply -f "$PROJECT_ROOT/monitoring/grafana/datasource-configmap.yaml"
kubectl apply -f "$PROJECT_ROOT/monitoring/grafana/dashboard-configmap.yaml"
kubectl apply -f "$PROJECT_ROOT/monitoring/grafana/deployment.yaml"

echo "==> Waiting for pods to be ready..."
kubectl rollout status deployment/cloud-app  -n cloud-app --timeout=180s
kubectl rollout status deployment/prometheus -n cloud-app --timeout=180s
kubectl rollout status deployment/grafana    -n cloud-app --timeout=180s
kubectl rollout status deployment/web        -n cloud-app --timeout=60s

echo ""
echo "==> Создаём S3 bucket в кластерном LocalStack..."
sleep 5
kubectl exec -n cloud-app deployment/localstack -- awslocal s3 mb s3://documents-bucket 2>/dev/null || true

NODE_IP=$(hostname -I | awk '{print $1}')
echo ""
echo "==> Готово! Все сервисы запущены."
echo "    Веб-сайт:   http://$NODE_IP:30000"
echo "    App API:    http://$NODE_IP:30080"
echo "    Prometheus: http://$NODE_IP:30090"
echo "    Grafana:    http://$NODE_IP:30030  (admin / admin)"
echo ""
echo "==> Тест RBAC:"
echo "    VIEWER  → curl -u viewer:password  http://$NODE_IP:30080/files"
echo "    EDITOR  → curl -u editor:password  -F file=@test.txt http://$NODE_IP:30080/files/upload"
echo "    ADMIN   → curl -u admin:password   http://$NODE_IP:30080/admin/secret"
echo "    403     → curl -u viewer:password  http://$NODE_IP:30080/admin/secret"
echo ""
echo "==> PromQL для 403 ошибок:"
echo "    rate(http_server_requests_seconds_count{status=\"403\"}[1m]) * 60"
