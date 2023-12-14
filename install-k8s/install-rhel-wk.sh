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
update-alternatives --set iptables /usr/sbin/iptables-legacy

# ファイアウォールの設定
firewall-cmd --permanent --add-port=179/tcp
firewall-cmd --permanent --add-port=443/tcp
firewall-cmd --permanent --add-port=4789/tcp
firewall-cmd --permanent --add-port=5473/tcp
firewall-cmd --permanent --add-port=6443/tcp
firewall-cmd --permanent --add-port=10250/tcp
firewall-cmd --permanent --add-port=30000-32767/tcp
firewall-cmd --reload

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
### 必要なパッケージのインストール
dnf install -y yum-utils device-mapper-persistent-data lvm2
## Dockerのリポジトリの追加
yum-config-manager \
    --add-repo \
    https://download.docker.com/linux/centos/docker-ce.repo
## containerdのインストール
dnf update -y && dnf install -y containerd.io
## containerdの設定
mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
# containerdの再起動
systemctl restart containerd

# kubeadm, kubelet, kubectlのインストール
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

# SELinuxをpermissiveモードに設定する(効果的に無効化する)
setenforce 0
sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes

systemctl enable --now kubelet
systemctl enable --now containerd