# Kubernetesのセットアップ  
Debian 12にて動作確認済み  
# コントロールプレーンのセットアップ  
## コントロールプレーンにKubernetesをインストールする  
```
## コントロールプレーンノードにSSH接続する  
## rootユーザーに切り替える
sudo su -
## IPv4フォワーディングを有効化、iptablesからブリッジされたトラフィックを見えるようにする
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
##カーネルパラメーターを適用
sudo sysctl --system
## containerdのインストール
## リポジトリの追加
apt-get update
apt-get install ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y containerd.io
containerd config default > /etc/containerd/config.toml
## cgroupの設定
## 以下の場所のSystemdCgroup = falseをtrueに変更
# [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
#  ...
#  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
#    SystemdCgroup = true
sed -i '/\[plugins\."io\.containerd\.grpc\.v1\.cri"\.containerd\.runtimes\.runc\.options\]/,/^$/s/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
## containerdの再起動
systemctl restart containerd
## kubeadm、kubelet、kubectlのインストール
apt-get update
apt-get install -y apt-transport-https ca-certificates curl gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
## root以外のユーザーでもkubectlを使えるようにする
export KUBECONFIG=/etc/kubernetes/admin.conf
## ~/.bashrcに追記
echo "export KUBECONFIG=/etc/kubernetes/admin.conf" >> ~/.bashrc
## クラスタの初期化
## kubeadm join... と表示されるので、後でワーカーノードで使うためにメモしておく
## pod-network-cidrは他と被らない任意のCIDRを指定する
kubeadm init --pod-network-cidr=10.8.0.0/16
## kubectlをroot以外のユーザーでも使えるようにする
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

# ネットワークのセットアップ
## Calicoのインストール
```  
## SSHで一般ユーザーとしてコントロールプレーンノードに接続し、インストール
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.1/manifests/tigera-operator.yaml
```
## calicoctlのインストール
```
## PATHの通っているディレクトリに移動
cd /usr/local/bin
## calicoctlのダウンロード
sudo curl -L https://github.com/projectcalico/calico/releases/download/v3.28.1/calicoctl-linux-amd64 -o calicoctl
## 実行権限の付与
sudo chmod +x ./calicoctl
```
## Calicoの設定
```
## コントロールプレーンの適当なディレクトリに移動し、適当にディレクトリを作成　(必須ではない)
cd ~
mkdir manifests
cd manifests
## Calicoの設定ファイルをダウンロード
wget https://raw.githubusercontent.com/dodolia907/k8s/main/calico/custom-resources.yaml
wget https://raw.githubusercontent.com/dodolia907/k8s/main/calico/bgppeer.yaml
## CIDRやAS番号など、環境に合わせて編集
vim custom-resources.yaml
vim bgppeer.yaml
## 設定適用
kubectl create -f custom-resources.yaml
calicoctl apply -f ixbgp.yaml
```
## 一旦確認
```
watch kubectl get pod -A -o wide
```
# ワーカーノードのセットアップ
```
## ワーカーノードにSSH接続する
## rootユーザーに切り替える
sudo su -
## IPv4フォワーディングを有効化、iptablesからブリッジされたトラフィックを見えるようにする
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
##カーネルパラメーターを適用
sudo sysctl --system
## containerdのインストール
## リポジトリの追加
apt-get update
apt-get install ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y containerd.io
containerd config default > /etc/containerd/config.toml
## cgroupの設定
## 以下の場所のSystemdCgroup = falseをtrueに変更
# [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
#  ...
#  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
#    SystemdCgroup = true
sed -i '/\[plugins\."io\.containerd\.grpc\.v1\.cri"\.containerd\.runtimes\.runc\.options\]/,/^$/s/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
## containerdの再起動
systemctl restart containerd
## kubeadm、kubelet、kubectlのインストール
apt-get update
apt-get install -y apt-transport-https ca-certificates curl gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
## クラスタへ参加
## コントロールプレーンノードで実行したkubeadm initの結果 kubeadm join ... を実行する
kubeadm join ...
```

## ルーターの設定
ここではNEC IXルータを用いる。
```
## ルーターにSSH接続する
## グローバルコンフィグモードに移行
enable-config
## BGP起動・BGPコンフィグモードに移行 (ルータ自身のAS番号を入力)
router bgp 65000
## 新規ピア設定 (全てのコントロールプレーン・ワーカーノードのIPアドレスを入力)
neighbor [ノード1のIPアドレス] remote-as 64512
neighbor [ノード2のIPアドレス] remote-as 64512
neighbor [ノード3のIPアドレス] remote-as 64512
neighbor [ノード4のIPアドレス] remote-as 64512
## グローバルコンフィグモードに戻る
exit
## 設定保存
write memory
## 確認 (StateがESTABLISHEDになっていればOK)
show ip bgp summary
```

## 確認
```
calicoctl get nodes -o wide
calicoctl get bgpPeer -o wide
calicoctl get ippool -o wide
calicoctl get bgpConfiguration -o wide
watch kubectl get pod -A -o wide
```

# NFSサーバのセットアップ
```
## NFSサーバにSSH接続する
## rootユーザーに切り替える
sudo su -
mkdir /nfs
dnf install nfs-utils
systemctl enable --now nfs-server
echo "/nfs 10.1.88.0/24(rw,sync,no_root_squash,no_subtree_check)" >> /etc/exports
exportfs -a
exportfs -v
firewall-cmd --add-service=nfs --permanent
firewall-cmd --reload
```
## コントロールプレーンノードに戻って作業
```
## Helmのインストール
cd /usr/local/bin
wget https://get.helm.sh/helm-v3.13.2-linux-amd64.tar.gz
tar -zxvf helm-v3.13.2-linux-amd64.tar.gz
mv linux-amd64/helm /usr/local/bin/helm 
## nfs-subdir-external-provisionerのインストール
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner --set nfs.server=<nfsサーバのIPアドレス> --set nfs.path=/nfs
## MetalLBのインストール
kubectl apply -f https://raw.githubusercontent.com/dodolia907/k8s/main/metallb/metallb.yaml
kubectl apply -f https://raw.githubusercontent.com/dodolia907/k8s/main/metallb/metallb-ipaddresspool.yaml
## Nginx Ingress Controllerのインストール
helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx --create-namespace
## ArgoCDのインストール
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
kubectl patch svc argocd-server -n argocd -p '{"metadata": {"annotations": {"external-dns.alpha.kubernetes.io/hostname": "argocd.k8s.ddlia.com"}}}'
cd /usr/local/bin
curl -L https://github.com/argoproj/argo-cd/releases/download/v2.11.8/argocd-linux-amd64 -o argocd
chmod +x argocd
argocd admin initial-password -n argocd
argocd login argocd.k8s.ddlia.com
argocd account update-password
## cert-managerのインストール
helm repo add jetstack https://charts.jetstack.io --force-update
helm install \
cert-manager jetstack/cert-manager \
--namespace cert-manager \
--create-namespace \
--version v1.15.3 \
--set crds.enabled=true
## Rancherのインストール
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
kubectl create namespace cattle-system
helm install rancher rancher-stable/rancher --namespace cattle-system --set hostname=rancher.k8s.ddlia.com"}}}' --set bootstrapPassword=admin
kubectl patch svc rancher -n cattle-system -p '{"spec": {"type": "LoadBalancer"}}'
kubectl patch svc rancher -n cattle-system -p '{"metadata": {"annotations": {"external-dns.alpha.kubernetes.io/hostname": "rancher.k8s.ddlia.com"}}}'
```

# リセット
```
kubeadm reset
## 手順が表示されるので従う
rm -rf /etc/cni/net.d
rm -rf $HOME/.kube/config
iptables -F
sudo reboot
```

# 参考資料
https://kubernetes.io/ja/docs/setup/production-environment/tools/kubeadm/install-kubeadm/
https://kubernetes.io/ja/docs/setup/production-environment/container-runtimes/
https://kubernetes.io/ja/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/
https://kubernetes.io/docs/setup/production-environment/container-runtimes/#containerd-systemd