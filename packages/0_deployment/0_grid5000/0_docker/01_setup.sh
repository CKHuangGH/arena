# Add Docker's official GPG key:
apt-get update
apt-get install -y ca-certificates curl sudo python3-pip
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update

VERSION_STRING=5:28.0.4-1~debian.11~bullseye
apt-get install -y docker-ce=$VERSION_STRING docker-ce-cli=$VERSION_STRING containerd.io docker-buildx-plugin docker-compose-plugin

wget https://get.helm.sh/helm-v3.17.4-linux-amd64.tar.gz

tar -zxvf helm-v3.17.4-linux-amd64.tar.gz
mv linux-amd64/helm /usr/local/bin/helm
rm -rf linux-amd64/
rm -f helm-v3.17.4-linux-amd64.tar.gz

sudo bash -c 'cat > /etc/docker/daemon.json <<EOF
{
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Soft": 1048576,
      "Hard": 1048576
    }
  },
  "registry-mirrors": [
    "http://docker-cache.grid5000.fr",
    "https://mirror.gcr.io",
    "https://docker.m.daocloud.io",
    "https://docker.nju.edu.cn",
    "https://ccr.ccs.tencentyun.com",
    "https://hub-mirror.c.163.com"
  ]
}
EOF'

sudo systemctl daemon-reload
sudo systemctl restart docker


echo 'fs.inotify.max_user_instances=2048' | sudo tee /etc/sysctl.d/99-inotify-instances.conf
sudo sysctl --system

sudo systemctl daemon-reload
sudo systemctl restart docker

pip3 install requests

sleep 5