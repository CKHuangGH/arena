helm repo add cilium https://helm.cilium.io/
helm repo update
helm install cilium cilium/cilium \
  --version 1.18.0 \
  --namespace kube-system \
  --wait --wait-for-jobs \
  --set operator.replicas=1 \
  --set operator.nodeSelector."kubernetes\.io/hostname"=control-plane \
  --set operator.tolerations[0].key=node-role.kubernetes.io/control-plane \
  --set operator.tolerations[0].operator=Exists \
  --set operator.tolerations[0].effect=NoSchedule

echo "wait 30 secs"
sleep 30

kubectl -n kube-system patch deploy coredns --type=merge -p '{
  "spec": { "template": { "spec": {
    "nodeSelector": { "kubernetes.io/hostname": "control-plane" },
    "tolerations": [
      { "key":"node-role.kubernetes.io/control-plane","operator":"Exists","effect":"NoSchedule" }
    ]
  } } }
}'

echo "wait 10 secs"
sleep 10

helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --version 75.18.1 \
  --namespace monitoring --create-namespace \
  --wait \
  --set grafana.enabled=false \
  --set alertmanager.enabled=false \
  --set prometheus.service.type=NodePort \
  --set prometheus.prometheusSpec.scrapeInterval="5s" \
  --set prometheus.prometheusSpec.enableAdminAPI=true \
  \
  --set prometheus.prometheusSpec.nodeSelector."kubernetes\.io/hostname"=control-plane \
  --set prometheus.prometheusSpec.tolerations[0].key=node-role.kubernetes.io/control-plane \
  --set prometheus.prometheusSpec.tolerations[0].operator=Exists \
  --set prometheus.prometheusSpec.tolerations[0].effect=NoSchedule \
  \
  --set prometheusOperator.nodeSelector."kubernetes\.io/hostname"=control-plane \
  --set prometheusOperator.tolerations[0].key=node-role.kubernetes.io/control-plane \
  --set prometheusOperator.tolerations[0].operator=Exists \
  --set prometheusOperator.tolerations[0].effect=NoSchedule \
  \
  --set kube-state-metrics.nodeSelector."kubernetes\.io/hostname"=control-plane \
  --set kube-state-metrics.tolerations[0].key=node-role.kubernetes.io/control-plane \
  --set kube-state-metrics.tolerations[0].operator=Exists \
  --set kube-state-metrics.tolerations[0].effect=NoSchedule

echo "wait 10 secs"
sleep 30

kubectl 