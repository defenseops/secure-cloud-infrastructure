#!/bin/bash
# Установка всех зависимостей на Ubuntu Server 22.04 (4 GB RAM, k3s вместо minikube)
set -e

echo "========================================"
echo " SecureCloud — Ubuntu Setup (k3s mode)"
echo "========================================"

# ── Docker ──────────────────────────────────
echo ""
echo "==> Installing Docker..."
sudo apt-get update -q
sudo apt-get install -y ca-certificates curl gnupg lsb-release

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update -q
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

sudo usermod -aG docker "$USER"
echo "    Docker installed."

# ── k3s ─────────────────────────────────────
echo ""
echo "==> Installing k3s (lightweight Kubernetes)..."
curl -sfL https://get.k3s.io | sh -

# Дать k3s время запуститься
sleep 10

# Настроить kubectl без sudo
mkdir -p "$HOME/.kube"
sudo cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
sudo chown "$USER":"$USER" "$HOME/.kube/config"
export KUBECONFIG="$HOME/.kube/config"

echo "    k3s installed. Kubernetes version:"
k3s kubectl version --short 2>/dev/null || kubectl version --short

# ── Terraform ───────────────────────────────
echo ""
echo "==> Installing Terraform..."
sudo apt-get install -y gnupg software-properties-common

wget -O- https://apt.releases.hashicorp.com/gpg | \
  sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list

sudo apt-get update -q
sudo apt-get install -y terraform
echo "    Terraform $(terraform version -json | python3 -c 'import sys,json; print(json.load(sys.stdin)["terraform_version"])')"

# ── Java 17 + Maven ─────────────────────────
echo ""
echo "==> Installing Java 17 + Maven..."
sudo apt-get install -y openjdk-17-jdk maven
echo "    $(java -version 2>&1 | head -1)"

# ── AWS CLI ─────────────────────────────────
echo ""
echo "==> Installing AWS CLI (for LocalStack testing)..."
sudo apt-get install -y awscli
echo "    $(aws --version)"

# ── kubectl alias ───────────────────────────
echo ""
echo "==> Configuring kubectl..."
# k3s ставит свой kubectl, делаем симлинк для удобства
if ! command -v kubectl &>/dev/null; then
  sudo ln -s /usr/local/bin/k3s /usr/local/bin/kubectl
  echo '#!/bin/bash' | sudo tee /usr/local/bin/kubectl > /dev/null
  echo 'k3s kubectl "$@"' | sudo tee /usr/local/bin/kubectl > /dev/null
  sudo chmod +x /usr/local/bin/kubectl
fi

# ── Summary ─────────────────────────────────
echo ""
echo "========================================"
echo " Installation complete!"
echo "========================================"
echo ""
echo " IMPORTANT: Run this to apply group changes:"
echo "   newgrp docker"
echo ""
echo " Then deploy the project:"
echo "   ./scripts/setup.sh          # Stage 1: LocalStack + Terraform"
echo "   ./scripts/deploy-k8s.sh     # Stages 2-5: Full K8s deploy"
echo ""
echo " Node IP (use in browser):"
echo "   $(hostname -I | awk '{print $1}')"
