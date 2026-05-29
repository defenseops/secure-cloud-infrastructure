#!/bin/bash
set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# k3s использует собственный kubectl — создаём алиас если нужно
if ! command -v kubectl &>/dev/null; then
  alias kubectl='k3s kubectl'
fi
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "==> Building Docker image..."
docker build -t cloud-app:latest "$PROJECT_ROOT/app"

echo "==> Loading image into k3s (bypassing registry)..."
docker save cloud-app:latest | sudo k3s ctr images import -

echo "==> Applying Kubernetes manifests..."
kubectl apply -f "$PROJECT_ROOT/k8s/namespace.yaml"
kubectl apply -f "$PROJECT_ROOT/k8s/localstack.yaml"
kubectl apply -f "$PROJECT_ROOT/k8s/serviceaccount.yaml"
kubectl apply -f "$PROJECT_ROOT/k8s/configmap.yaml"
kubectl apply -f "$PROJECT_ROOT/k8s/secret.yaml"
kubectl apply -f "$PROJECT_ROOT/k8s/deployment.yaml"
kubectl apply -f "$PROJECT_ROOT/k8s/service.yaml"
kubectl apply -f "$PROJECT_ROOT/k8s/networkpolicy.yaml"

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

NODE_IP=$(hostname -I | awk '{print $1}')
echo ""
echo "==> Done! All services are running."
echo "    App:        http://$NODE_IP:30080"
echo "    Prometheus: http://$NODE_IP:30090"
echo "    Grafana:    http://$NODE_IP:30030  (admin / admin)"
echo ""
echo "==> Test RBAC:"
echo "    VIEWER  → curl -u viewer:password  http://$NODE_IP:30080/files"
echo "    EDITOR  → curl -u editor:password  -F file=@test.txt http://$NODE_IP:30080/files/upload"
echo "    ADMIN   → curl -u admin:password   http://$NODE_IP:30080/admin/secret"
echo "    403     → curl -u viewer:password  http://$NODE_IP:30080/admin/secret"
echo ""
echo "==> Prometheus query for 403 errors:"
echo "    rate(http_server_requests_seconds_count{status=\"403\"}[1m]) * 60"
