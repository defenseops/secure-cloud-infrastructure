#!/bin/bash
set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> Starting LocalStack..."
docker compose -f "$PROJECT_ROOT/docker-compose.yml" up -d localstack

echo "==> Waiting for LocalStack to be ready..."
until curl -s http://localhost:4566/_localstack/health | grep -q '"s3": "available"'; do
  sleep 2
  echo "    still waiting..."
done
echo "    LocalStack is ready."

echo "==> Running Terraform..."
cd "$PROJECT_ROOT/terraform"
terraform init
terraform apply -auto-approve

echo ""
echo "==> Done! Resources created:"
terraform output
