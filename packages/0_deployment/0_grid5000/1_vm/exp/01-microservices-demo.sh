#!/bin/bash
set -e

NAMESPACE="default"

log_info()  { echo -e "\033[1;34m[INFO]\033[0m $1"; }
log_error() { echo -e "\033[1;31m[ERROR]\033[0m $1"; exit 1; }

echo "請選擇要使用的數字:"
echo "1) 100"
echo "2) 200"
echo "3) 300"
read -p "輸入選項 (1/2/3): " choice

case $choice in
  1) number=100 ;;
  2) number=200 ;;
  3) number=300 ;;
  *) log_error "無效選項，請輸入 1、2 或 3。" ;;
esac

# 這次執行編號（只用於 scp 路徑辨識）
read -p "這是第幾次執行？(僅用於 scp 目標路徑，例如輸入 7): " run_id
[[ -z "$run_id" || ! "$run_id" =~ ^[0-9]+$ ]] && log_error "請輸入數字。"

log_info "已選擇數字：$number"
log_info "執行編號（用於 scp 路徑）：$run_id"
log_info "========== 開始執行 =========="

log_info "Deploying microservices-demo to Kubernetes..."
kubectl apply -f kubernetes-manifests.yaml

log_info "Waiting for all pods to be ready..."
kubectl wait --for=condition=Ready pods --all -n "$NAMESPACE" --timeout=300s

sleep 30

bash "./test-microservices-demo-$number.sh"

sleep 30

log_info "Copying results to remote server..."
scp -o StrictHostKeyChecking=no -r ./results \
  "chuang@172.16.207.100:/home/chuang/arena_results-vm-${number}-run${run_id}"

sleep 30

kubectl delete -f kubernetes-manifests.yaml

sleep 60

log_info "本次執行完成 ✅"
log_info "============================="
