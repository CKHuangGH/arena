#!/bin/bash
set -euo pipefail

# Logging helpers
log_info()  { echo -e "\033[1;34m[INFO]\033[0m $1"; }
log_warn()  { echo -e "\033[1;33m[WARN]\033[0m $1"; }
log_error() { echo -e "\033[1;31m[ERROR]\033[0m $1"; exit 1; }

NAMESPACE="chaos-mesh"
RELEASE_NAME="chaos-mesh"
NETWORK_CHAOS_YAML="./manifests/networkchaos.yaml"

log_info "🧪 Starting Chaos Mesh installation..."

# Ensure iptables and ipset installed (simple Debian/Ubuntu example)
if ! command -v iptables >/dev/null 2>&1 || ! command -v ipset >/dev/null 2>&1; then
  log_warn "iptables or ipset not found. Attempting to install..."
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y iptables ipset
  elif command -v yum >/dev/null 2>&1; then
    sudo yum install -y iptables ipset
  else
    log_warn "Unsupported package manager. Please install iptables and ipset manually."
  fi
fi

# Check Helm
if ! command -v helm >/dev/null 2>&1; then
  log_info "Helm not found. Installing Helm..."
  OS=$(uname -s | tr '[:upper:]' '[:lower:]')
  ARCH=$(uname -m)
  ARCH_DL="amd64"
  [[ "$ARCH" == "arm64" || "$ARCH" == "aarch64" ]] && ARCH_DL="arm64"
  curl -fsSL "https://get.helm.sh/helm-v3.14.4-${OS}-${ARCH_DL}.tar.gz" -o helm.tar.gz
  tar -xzf helm.tar.gz
  mkdir -p "$HOME/.local/bin"
  mv "${OS}-${ARCH_DL}/helm" "$HOME/.local/bin/helm"
  export PATH="$HOME/.local/bin:$PATH"
  rm -rf helm.tar.gz "${OS}-${ARCH_DL}"
  log_info "Helm installed to $HOME/.local/bin"
else
  log_info "Helm found: $(helm version --short)"
fi

# Create namespace if not exists
if ! kubectl get ns "$NAMESPACE" >/dev/null 2>&1; then
  log_info "Creating namespace '$NAMESPACE'..."
  kubectl create ns "$NAMESPACE"
fi

# Add Chaos Mesh repo
helm repo add chaos-mesh https://charts.chaos-mesh.org || true
helm repo update

# Default to containerd
RUNTIME="containerd"
SOCKET_PATH="/run/containerd/containerd.sock"
if docker info >/dev/null 2>&1; then
  RUNTIME="docker"
  SOCKET_PATH="/var/run/docker.sock"
  log_info "🧩 Docker runtime detected."
else
  log_info "🧩 Defaulting to containerd runtime."
fi

# Remove conflicting release
if helm status "$RELEASE_NAME" -n chaos-testing >/dev/null 2>&1; then
  log_info "Uninstalling conflicting release $RELEASE_NAME in namespace chaos-testing to avoid ownership conflicts..."
  helm uninstall "$RELEASE_NAME" -n chaos-testing || true
fi

# Install or upgrade Chaos Mesh
if helm status "$RELEASE_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
  log_info "Upgrading Chaos Mesh..."
  helm upgrade "$RELEASE_NAME" chaos-mesh/chaos-mesh -n "$NAMESPACE" \
    --set dashboard.create=true \
    --set chaosDaemon.runtime="$RUNTIME" \
    --set chaosDaemon.socketPath="$SOCKET_PATH" \
    --set chaosDaemon.privileged=true \
    --set chaosDaemon.hostNetwork=true \
    --reuse-values
else
  log_info "Installing Chaos Mesh..."
  helm install "$RELEASE_NAME" chaos-mesh/chaos-mesh -n "$NAMESPACE" \
    --set dashboard.create=true \
    --set chaosDaemon.runtime="$RUNTIME" \
    --set chaosDaemon.socketPath="$SOCKET_PATH" \
    --set chaosDaemon.privileged=true \
    --set chaosDaemon.hostNetwork=true
fi
# Always apply post-install upgrade override (containerd setup)
log_info "🔁 Ensuring correct configuration with a post-upgrade override..."
helm upgrade "$RELEASE_NAME" chaos-mesh/chaos-mesh -n "$NAMESPACE" \
  --set chaosDaemon.runtime=containerd \
  --set chaosDaemon.socketPath=/run/containerd/containerd.sock \
  --set chaosDaemon.securityContext.privileged=true \
  --reuse-values

# Wait for Controller Manager to be ready
log_info "⏳ Waiting for Chaos Mesh controller-manager pod..."
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/component=controller-manager -n "$NAMESPACE" --timeout=180s

# Apply NetworkChaos manifest if present
if [ -f "$NETWORK_CHAOS_YAML" ]; then
  log_info "Applying NetworkChaos from: $NETWORK_CHAOS_YAML"
  kubectl apply -f "$NETWORK_CHAOS_YAML"
else
  log_warn "NetworkChaos file not found at: $NETWORK_CHAOS_YAML"
fi

log_info "✅ Chaos Mesh setup complete. Access the dashboard with:"
log_info "   kubectl port-forward -n ${NAMESPACE} svc/chaos-dashboard 2333:2333"
log_info "   http://localhost:2333"
