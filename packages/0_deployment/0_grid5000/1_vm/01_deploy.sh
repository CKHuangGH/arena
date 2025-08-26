helm repo add cilium https://helm.cilium.io/
helm repo update
helm install cilium cilium/cilium \
  --version 1.18.0 \
  --namespace kube-system \
  --wait --wait-for-jobs \
  --set operator.replicas=1 \
  --set operator.nodeSelector."node-role\.kubernetes\.io/control-plane"="" \
  --set operator.tolerations[0].key=node-role.kubernetes.io/control-plane \
  --set operator.tolerations[0].operator=Exists \
  --set operator.tolerations[0].effect=NoSchedule

echo "wait 30 secs"
for i in $(seq 30 -1 1); do
    # show countdown in English
    echo -ne "\rCountdown: $i seconds"
    sleep 1
done

# final message
echo -e "\rTime's up!     "

kubectl -n kube-system patch deploy coredns --type=merge -p '{
  "spec": { "template": { "spec": {
    "nodeSelector": { "node-role.kubernetes.io/control-plane": "" },
    "tolerations": [
      { "key":"node-role.kubernetes.io/control-plane","operator":"Exists","effect":"NoSchedule" }
    ]
  } } }
}'


echo "wait 30 secs"
for i in $(seq 30 -1 1); do
    # show countdown in English
    echo -ne "\rCountdown: $i seconds"
    sleep 1
done

# final message
echo -e "\rTime's up!     "

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install prometheus prometheus-community/kube-prometheus-stack \
  --version 75.18.1 \
  --namespace monitoring --create-namespace \
  --wait \
  --set grafana.enabled=false \
  --set alertmanager.enabled=false \
  --set prometheus.service.type=NodePort \
  --set prometheus.prometheusSpec.scrapeInterval="5s" \
  --set prometheus.prometheusSpec.enableAdminAPI=true \
  \
  --set prometheus.prometheusSpec.nodeSelector."node-role\.kubernetes\.io/control-plane"="" \
  --set prometheus.prometheusSpec.tolerations[0].key=node-role.kubernetes.io/control-plane \
  --set prometheus.prometheusSpec.tolerations[0].operator=Exists \
  --set prometheus.prometheusSpec.tolerations[0].effect=NoSchedule \
  \
  --set prometheusOperator.nodeSelector."node-role\.kubernetes\.io/control-plane"="" \
  --set prometheusOperator.tolerations[0].key=node-role.kubernetes.io/control-plane \
  --set prometheusOperator.tolerations[0].operator=Exists \
  --set prometheusOperator.tolerations[0].effect=NoSchedule \
  \
  --set kube-state-metrics.nodeSelector."node-role\.kubernetes\.io/control-plane"="" \
  --set kube-state-metrics.tolerations[0].key=node-role.kubernetes.io/control-plane \
  --set kube-state-metrics.tolerations[0].operator=Exists \
  --set kube-state-metrics.tolerations[0].effect=NoSchedule

echo "wait 30 secs"
for i in $(seq 30 -1 1); do
    # show countdown in English
    echo -ne "\rCountdown: $i seconds"
    sleep 1
done

# final message
echo -e "\rTime's up!     "
kubectl get pod -A
read -n1 -s -r -p "Press any key to continue"
echo -e "\n"
kubectl describe node