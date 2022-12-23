# スワップの無効化
swapoff -a
sed -i -e 's/\/swap.img/#\/swap.img/g' /etc/fstab

# iptablesの設定
modprobe br_netfilter
cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl --system

# レガシーモードへの切り替え
apt-get install -y iptables arptables ebtables
update-alternatives --set iptables /usr/sbin/iptables-legacy
update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
update-alternatives --set arptables /usr/sbin/arptables-legacy
update-alternatives --set ebtables /usr/sbin/ebtables-legacy

# ファイアウォールの設定
apt-get install -y ufw
systemctl start ufw
ufw allow 22/tcp
ufw allow 179/tcp
ufw allow 443/tcp
ufw allow 6443/tcp
ufw allow 2379/tcp
ufw allow 2380/tcp
ufw allow 10250/tcp
ufw allow 10251/tcp
ufw allow 10252/tcp
ufw allow 30000:32767/tcp
ufw enable
systemctl restart ufw

# Containerdに必要な設定の追加
cat > /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF

# 必要なカーネルパラメータの設定をします。これらの設定値は再起動後も永続化されます。
modprobe overlay
modprobe br_netfilter

cat > /etc/sysctl.d/99-kubernetes-cri.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sysctl --system

#Containerdのインストール
## リポジトリの設定
### HTTPS越しのリポジトリの使用をaptに許可するために、パッケージをインストール
apt-get update && apt-get install -y apt-transport-https ca-certificates curl software-properties-common
## Docker公式のGPG鍵を追加
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
## Dockerのaptリポジトリの追加
add-apt-repository \
    "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) \
    stable"
## containerdのインストール
apt-get update && apt-get install -y containerd.io
# containerdの設定
mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
# containerdの再起動
systemctl restart containerd
systemctl enable containerd

# kubeadm, kubelet, kubectlのインストール
apt-get update && sudo apt-get install -y apt-transport-https curl
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
cat <<EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
systemctl enable kubelet