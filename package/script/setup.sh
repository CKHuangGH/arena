mkdir /var/log/ntpsec
sudo apt-get install tcpdump -y
sudo systemctl stop ntp
sudo ntpd -gq
sudo systemctl start ntp
export DEBIAN_FRONTEND=noninteractive
ip=$(cat node_list)

> node_ip_all

for i in {2..5}; do
  new_ip=$(echo "$ip" | sed "s/\.[0-9]*$/.${i}/")
  echo "$new_ip" >> node_ip_all
done

while IFS= read -r ip_address; do
  scp -o StrictHostKeyChecking=no /root/mqtt/package/node_ip_all root@$ip_address:/root/
  scp -o StrictHostKeyChecking=no /root/mqtt/package/script/ntp.sh root@$ip_address:/root/
done < "node_ip_all"

while IFS= read -r ip_address; do
  ssh -n -o StrictHostKeyChecking=no root@"$ip_address" mkdir -p /var/log/ntpsec
  ssh -n -o StrictHostKeyChecking=no root@"$ip_address" "nohup bash /root/ntp.sh > /var/log/ntpsec/ntp.log 2>&1 &"
done < node_ip_all

wait

kubectl taint nodes --all node-role.kubernetes.io/control-plane-

helm repo update
helm install cilium cilium/cilium --version 1.17.5 --wait --wait-for-jobs --namespace kube-system --set operator.replicas=1
sleep 30

# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update

sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  -o Dpkg::Options::="--force-confold" \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

cd /root/bench_ctrl

docker compose build

helm repo add influxdata https://helm.influxdata.com/
helm repo add jetstack https://charts.jetstack.io
helm repo add emqx https://repos.emqx.io/charts
helm repo update

kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml

# Install and start cert-manager
helm upgrade --install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --set crds.enabled=true

# # Install the EMQX
# helm install --version 5.8.7 emqx emqx/emqx --namespace emqx --create-namespace 

helm install --version 2.1.2 influxdb2 influxdata/influxdb2 --namespace influxdb --create-namespace --set persistence.enabled=true --set persistence.storageClass=local-path --set persistence.size=30Gi --set config.authEnabled=false --set service.type=NodePort --set service.nodePort=32086

# ---- InfluxDB 設定 ----
NAMESPACE="influxdb"  # InfluxDB 的 namespace
ORG="influxdata"
BUCKET="default"
INFLUX_HOST="http://influxdb-influxdb2.${NAMESPACE}.svc.cluster.local:8086"


# ---- Helm 安裝 Prometheus Stack ----
helm install --version 75.9.0 prometheus-community/kube-prometheus-stack \
  --generate-name \
  --namespace monitoring \
  --create-namespace \
  --set grafana.enabled=false \
  --set alertmanager.enabled=false \
  --set prometheus.service.type=NodePort \
  --set prometheus.prometheusSpec.scrapeInterval="5s" \
  --set prometheus.prometheusSpec.enableAdminAPI=true \
  --set prometheus.prometheusSpec.resources.requests.cpu="1000m" \
  --set prometheus.prometheusSpec.resources.requests.memory="1024Mi" \
  --set prometheus.prometheusSpec.remoteWrite[0].url="${INFLUX_HOST}/api/v2/write?org=${ORG}&bucket=${BUCKET}&precision=s" \
  --set prometheus.prometheusSpec.retention="5m"