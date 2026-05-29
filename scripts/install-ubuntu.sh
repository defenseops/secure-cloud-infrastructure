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

sleep 10

mkdir -p "$HOME/.kube"
sudo cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
sudo chown "$USER":"$USER" "$HOME/.kube/config"
export KUBECONFIG="$HOME/.kube/config"

echo "    k3s installed."

# ── Terraform ───────────────────────────────
echo ""
echo "==> Installing Terraform (via snap)..."
sudo snap install terraform --classic
echo "    $(terraform version | head -1)"

# ── Java 17 + Maven ─────────────────────────
echo ""
echo "==> Installing Java 17 + Maven..."
sudo apt-get install -y openjdk-17-jdk maven
echo "    $(java -version 2>&1 | head -1)"

# ── AWS CLI ─────────────────────────────────
echo ""
echo "==> Installing AWS CLI..."
sudo apt-get install -y awscli
echo "    $(aws --version)"

# ── kubectl ─────────────────────────────────
echo ""
echo "==> Configuring kubectl..."
if ! command -v kubectl &>/dev/null; then
  sudo bash -c 'echo "#!/bin/bash" > /usr/local/bin/kubectl'
  sudo bash -c 'echo "k3s kubectl \"\$@\"" >> /usr/local/bin/kubectl'
  sudo chmod +x /usr/local/bin/kubectl
fi

# ── KUBECONFIG в .bashrc ────────────────────
if ! grep -q "KUBECONFIG" "$HOME/.bashrc"; then
  echo 'export KUBECONFIG=~/.kube/config' >> "$HOME/.bashrc"
fi

# ── Summary ─────────────────────────────────
echo ""
echo "========================================"
echo " Installation complete!"
echo "========================================"
echo ""
echo " IMPORTANT: Run this to apply docker group:"
echo "   newgrp docker"
echo ""
echo " Then deploy:"
echo "   ./scripts/setup.sh        # Stage 1: LocalStack + Terraform"
echo "   ./scripts/deploy-k8s.sh   # Stages 2-5: K8s deploy"
echo ""
echo " Node IP:"
echo "   $(hostname -I | awk '{print $1}')"
