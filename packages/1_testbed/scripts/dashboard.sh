#!/bin/bash
set -e
 
KIND_CLUSTER_NAME="pandora-testbed"
NAMESPACE="kubernetes-dashboard"
SERVICE_NAME="kubernetes-dashboard-kong-proxy"
PORT_LOCAL=8443
 
log_info()  { echo -e "\n\033[1;34m[INFO]\033[0m $1"; }
log_warn()  { echo -e "\n\033[1;33m[WARN]\033[0m $1"; }
log_error() { echo -e "\n\033[1;31m[ERROR]\033[0m $1"; exit 1; }
exists()    { command -v "$1" >/dev/null 2>&1; }
 
install_helm_if_missing() {
  if ! exists helm; then
    log_info "Helm not found. Installing Helm..."

    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
      if command -v apt-get >/dev/null 2>&1; then
        curl https://baltocdn.com/helm/signing.asc | sudo apt-key add -
        sudo apt-get install apt-transport-https --yes
        echo "deb https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
        sudo apt-get update
        sudo apt-get install -y helm
      elif command -v yum >/dev/null 2>&1; then
        curl https://baltocdn.com/helm/signing.asc | sudo rpm --import -
        sudo yum install -y yum-utils
        sudo yum-config-manager --add-repo https://baltocdn.com/helm/stable/rpm
        sudo yum install -y helm
      else
        log_error "Unsupported Linux OS. Please install Helm manually: https://helm.sh/docs/intro/install/"
      fi

    elif [[ "$OSTYPE" == "darwin"* ]]; then
      if ! command -v brew >/dev/null 2>&1; then
        log_info "Homebrew not found. Installing Homebrew..."
        NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

        # Add Homebrew to PATH if needed
        if [ -d "/opt/homebrew/bin" ]; then
          eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [ -d "/usr/local/bin" ]; then
          eval "$(/usr/local/bin/brew shellenv)"
        fi
      fi

      if command -v brew >/dev/null 2>&1; then
        brew install helm
      else
        log_error "Homebrew installation failed. Please install it manually from https://brew.sh/"
      fi

    else
      log_error "Unsupported OS. Please install Helm manually: https://helm.sh/docs/intro/install/"
    fi

    if ! exists helm; then
      log_error "Helm installation failed. Please install it manually."
    fi

    log_info "Helm installed successfully."
  else
    log_info "Helm is already installed: $(helm version --short)"
  fi
}


 
# --- Checks ---
exists kubectl || log_error "kubectl not installed"
 
install_helm_if_missing
 
kubectl config use-context "kind-${KIND_CLUSTER_NAME}" >/dev/null || log_error "Kind cluster not found"
 
# --- Install Dashboard if not installed ---
if ! kubectl get ns "$NAMESPACE" --context "kind-${KIND_CLUSTER_NAME}" >/dev/null 2>&1; then
  log_info "Installing Kubernetes Dashboard"
  helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/ --kube-context "kind-${KIND_CLUSTER_NAME}" || true
  helm repo update --kube-context "kind-${KIND_CLUSTER_NAME}"
 
  helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
    --namespace "$NAMESPACE" \
    --create-namespace \
    --set protocolHttp=true \
    --set 'extraArgs[0]={--enable-skip-login,--disable-settings-save}' \
    --wait --timeout 300s \
    --kube-context "kind-${KIND_CLUSTER_NAME}"
fi
 
kubectl wait --for=condition=Available deployment/kubernetes-dashboard-web \
  -n "$NAMESPACE" --timeout=300s --context "kind-${KIND_CLUSTER_NAME}"
 
# --- Service Account & Token ---
log_info "Ensuring admin account exists..."
kubectl create serviceaccount dashboard-admin -n "$NAMESPACE" --context "kind-${KIND_CLUSTER_NAME}" 2>/dev/null || true
kubectl create clusterrolebinding dashboard-admin \
  --clusterrole=cluster-admin \
  --serviceaccount="${NAMESPACE}:dashboard-admin" \
  --context "kind-${KIND_CLUSTER_NAME}" 2>/dev/null || true
 
log_info "Fetching login token..."
TOKEN=$(kubectl -n "$NAMESPACE" create token dashboard-admin --context "kind-${KIND_CLUSTER_NAME}")
[[ -z "$TOKEN" ]] && log_error "Failed to retrieve token"
 
echo -e "\n\033[1;36m[🔑 Dashboard Login Token]\033[0m\n$TOKEN"
log_warn "💾 Please save this token securely in case you need to log in again manually."
 
# --- Port Forward ---
log_info "Starting port-forward on https://localhost:${PORT_LOCAL}"
kill $(lsof -ti tcp:${PORT_LOCAL}) 2>/dev/null || true
kubectl -n "$NAMESPACE" port-forward svc/$SERVICE_NAME ${PORT_LOCAL}:443 --context "kind-${KIND_CLUSTER_NAME}" &
PORT_PID=$!
trap "kill $PORT_PID 2>/dev/null" EXIT
 
sleep 5
 
DASHBOARD_URL="https://localhost:${PORT_LOCAL}/#/login?token=${TOKEN}"
log_info "Opening Dashboard..."
if exists open; then
  open "$DASHBOARD_URL"
elif exists xdg-open; then
  xdg-open "$DASHBOARD_URL"
else
  echo "$DASHBOARD_URL"
fi
 
# --- User Reminder ---
echo -e "\n\033[1;32m[💡 Reminder]\033[0m"
echo "To reopen the dashboard manually later:"
echo "  kubectl port-forward -n $NAMESPACE svc/$SERVICE_NAME 8443:443 --context kind-${KIND_CLUSTER_NAME}"
echo "  TOKEN=\$(kubectl -n $NAMESPACE create token dashboard-admin --context kind-${KIND_CLUSTER_NAME})"
echo "  open https://localhost:8443/#/login?token=\$TOKEN"
 
log_info "✅ Dashboard is live. Press Ctrl+C to stop port-forward."
wait