helm repo add cilium https://helm.cilium.io/
helm repo update

helm install cilium cilium/cilium \
  --version 1.17.6 \
  --namespace kube-system \
  --set operator.replicas=1 \
  --set operator.nodeSelector."node-role\.kubernetes\.io/control-plane"="" \
  --set operator.tolerations[0].key=node-role.kubernetes.io/control-plane \
  --set operator.tolerations[0].operator=Exists \
  --set operator.tolerations[0].effect=NoSchedule \
  --set operator.tolerations[1].key=node.kubernetes.io/not-ready \
  --set operator.tolerations[1].operator=Exists \
  --set operator.tolerations[1].effect=NoSchedule \
  --set operator.tolerations[2].key=node.kubernetes.io/unreachable \
  --set operator.tolerations[2].operator=Exists \
  --set operator.tolerations[2].effect=NoExecute

sleep 30

kubectl -n kube-system patch deploy coredns --type=merge -p '{
  "spec": { "template": { "spec": {
    "nodeSelector": { "node-role.kubernetes.io/control-plane": "" },
    "tolerations": [
      { "key":"node-role.kubernetes.io/control-plane","operator":"Exists","effect":"NoSchedule" }
    ]
  } } }
}'

kubectl -n local-path-storage patch deploy local-path-provisioner \
  --type=merge -p '{
  "spec": { "template": { "spec": {
    "nodeSelector": { "node-role.kubernetes.io/control-plane": "" },
    "tolerations": [
      { "key":"node-role.kubernetes.io/control-plane","operator":"Exists","effect":"NoSchedule" }
    ]
  } } }
}'

sleep 30

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --version 75.18.1 \
  -n monitoring --create-namespace \
  --wait \
  --set grafana.enabled=false \
  --set alertmanager.enabled=false \
  --set prometheus.service.type=NodePort \
  --set prometheus.prometheusSpec.scrapeInterval='5s' \
  --set prometheus.prometheusSpec.enableAdminAPI=true \
  \
  --set 'prometheus.prometheusSpec.nodeSelector.node-role\.kubernetes\.io/control-plane'='' \
  --set 'prometheus.prometheusSpec.tolerations[0].key=node-role.kubernetes.io/control-plane' \
  --set 'prometheus.prometheusSpec.tolerations[0].operator=Exists' \
  --set 'prometheus.prometheusSpec.tolerations[0].effect=NoSchedule' \
  \
  --set 'prometheusOperator.nodeSelector.node-role\.kubernetes\.io/control-plane'='' \
  --set 'prometheusOperator.tolerations[0].key=node-role.kubernetes.io/control-plane' \
  --set 'prometheusOperator.tolerations[0].operator=Exists' \
  --set 'prometheusOperator.tolerations[0].effect=NoSchedule' \
  \
  --set 'kube-state-metrics.nodeSelector.node-role\.kubernetes\.io/control-plane'='' \
  --set 'kube-state-metrics.tolerations[0].key=node-role.kubernetes.io/control-plane' \
  --set 'kube-state-metrics.tolerations[0].operator=Exists' \
  --set 'kube-state-metrics.tolerations[0].effect=NoSchedule'