#!/bin/bash
set -e

NAMESPACE="default"

log_info()  { echo -e "\033[1;34m[INFO]\033[0m $1"; }
log_error() { echo -e "\033[1;31m[ERROR]\033[0m $1"; exit 1; }

echo "請選擇要使用的數字:"
echo "0) 0"
echo "1) 1"
echo "2) 2"
echo "5) 5"
echo "10) 10"
read -p "輸入選項 (0/1/2/5/10): " choice

case $choice in
  0) number=0 ;;
  1) number=1 ;;
  2) number=2 ;;
  5) number=5 ;;
  10) number=10 ;;
  *) log_error "無效選項，請輸入 0、1、2、5 或 10。" ;;
esac

# 這次執行編號（只用於 scp 路徑辨識）
read -p "這是第幾次執行？(僅用於 scp 目標路徑，例如輸入 7): " run_id
[[ -z "$run_id" || ! "$run_id" =~ ^[0-9]+$ ]] && log_error "請輸入數字。"

log_info "已選擇數字：$number"
log_info "執行編號（用於 scp 路徑）：$run_id"
log_info "========== 開始執行 =========="

log_info "Deploying microservices-demo to Kubernetes..."
kubectl apply -f yaml/

log_info "Waiting for all pods to be ready..."
kubectl wait --for=condition=Ready pods --all --timeout=300s -n "$NAMESPACE"

sleep 30

log_info "Port-forward Elasticsearch service..."
nohup kubectl -n "$NAMESPACE" port-forward svc/elastic-service 9200:9200 > /tmp/pf-elastic.log 2>&1 &

sleep 5

if [[ "$number" -eq 0 ]]; then
  log_info "選擇 0 跳過 network 規則安裝。"
else
  log_info "套用 network 規則 (iot <-> kafka, 檔案 net_iot_kafka-${number}.yaml)..."
  kubectl apply -f "./network/net_iot_kafka-${number}.yaml"
fi

sleep 5

log_info "執行 network 測試..."
python3 network_test.py

sleep 30

log_info "Copying results to remote server..."
scp -o StrictHostKeyChecking=no es_throughput_10min.csv \
  "chuang@172.16.207.100:/home/chuang/es_throughput_10min-${number}-${run_id}.csv"

log_info "本次執行完成"
log_info "============================="