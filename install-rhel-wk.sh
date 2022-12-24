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
dnf update -y && dnf install -y ufw
systemctl start ufw
ufw allow 22/tcp
ufw allow 179/tcp
ufw allow 443/tcp
ufw allow 4789/tcp
ufw allow 5473/tcp
ufw allow 10250/tcp
ufw allow 30000:32767/tcp
ufw enable
systemctl restart ufw
systemctl enable ufw
systemctl disable firewalld
systemctl stop firewalld

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
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF

# SELinuxをpermissiveモードに設定する(効果的に無効化する)
setenforce 0
sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes

systemctl enable --now kubelet