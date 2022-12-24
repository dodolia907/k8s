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
firewalld-cmd --permanent --add-port=179/tcp
firewalld-cmd --permanent --add-port=443/tcp
firewalld-cmd --permanent --add-port=2379/tcp
firewalld-cmd --permanent --add-port=2380/tcp
firewalld-cmd --permanent --add-port=4789/tcp
firewalld-cmd --permanent --add-port=5473/tcp
firewalld-cmd --permanent --add-port=6443/tcp
firewalld-cmd --permanent --add-port=10250/tcp
firewalld-cmd --permanent --add-port=10251/tcp
firewalld-cmd --permanent --add-port=10252/tcp
firewalld-cmd --reload

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