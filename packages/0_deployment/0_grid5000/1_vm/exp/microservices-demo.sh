#!/bin/bash
set -e
echo "./microservices-demo.sh 1"
number=$1

if [ -z "$number" ]; thens
  echo "❌ Error: missing argument <number>."
  echo "Please provide a number. Example: $0 42"
  exit 1
fi

NAMESPACE="default"
REPO_URL="https://github.com/GoogleCloudPlatform/microservices-demo.git"
REPO_DIR="microservices-demo"
BRANCH="v0"

log_info()  { echo -e "\033[1;34m[INFO]\033[0m $1"; }
log_error() { echo -e "\033[1;31m[ERROR]\033[0m $1"; exit 1; }

# 1. Check if frontend service exists (means demo is already installed)
if kubectl get svc frontend-external -n "$NAMESPACE" >/dev/null 2>&1; then
    log_info "Microservices Demo already installed in namespace '$NAMESPACE'."
    kubectl get pods -n "$NAMESPACE" -o wide
    exit 0
fi

# # 2. Clone repository if not present
# if [ ! -d "$REPO_DIR" ]; then
#     log_info "Cloning microservices-demo repository..."
#     git clone --depth 1 --branch "$BRANCH" "$REPO_URL"
# else
#     log_info "Repository already exists. Pulling latest changes..."
#     cd "$REPO_DIR"
#     git pull origin "$BRANCH"
#     cd ..
# fi

# 3. Deploy manifests
log_info "Deploying microservices-demo to Kubernetes..."
kubectl apply -f kubernetes-manifests.yaml

# 4. Wait until all pods are ready
log_info "Waiting for all pods to be ready..."
kubectl wait --for=condition=Ready pods --all -n "$NAMESPACE" --timeout=300s

# 5. Output service info
log_info "Deployment complete. Listing services:"
kubectl get svc -n "$NAMESPACE"

FRONTEND_IP=$(kubectl get svc frontend-external -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
if [ -n "$FRONTEND_IP" ]; then
    log_info "Access the demo at: http://$FRONTEND_IP"
else
    log_info "To access the frontend, run:"
    echo "kubectl port-forward svc/frontend-external 8080:80 -n $NAMESPACE"
    echo "Then open: http://localhost:8080"
fi

sleep 30

nohup kubectl -n monitoring port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 > /tmp/port-forward.log 2>&1 &

bash ./test-microservices-demo-$number.sh

sleep 30

scp -r ./results chuang@172.16.207.100:/home/chuang/arena_results-$number