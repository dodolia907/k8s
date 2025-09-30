# Kubernetesのセットアップ  
Debian 13にて動作確認済み  
## コンテナランタイムの準備  
```
## 全てのノードで実施  
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
net.ipv6.conf.all.forwarding        = 1
EOF
##カーネルパラメーターを適用
sysctl --system
## CRI-Oのインストール
## リポジトリの追加
KUBERNETES_VERSION=v1.34
CRIO_VERSION=v1.34
curl -fsSL https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/Release.key |
    gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/ /" |
    tee /etc/apt/sources.list.d/kubernetes.list
curl -fsSL https://download.opensuse.org/repositories/isv:/cri-o:/stable:/$CRIO_VERSION/deb/Release.key |
    gpg --dearmor -o /etc/apt/keyrings/cri-o-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/cri-o-apt-keyring.gpg] https://download.opensuse.org/repositories/isv:/cri-o:/stable:/$CRIO_VERSION/deb/ /" |
    tee /etc/apt/sources.list.d/cri-o.list
## kubeadm、kubelet、kubectlのインストール
apt-get update
apt-get install -y cri-o kubelet kubeadm kubectl
systemctl start crio.service
```

## クラスタの初期化
```
## kubeadm join... と表示されるので、後でワーカーノードで使うためにメモしておく
## pod-network-cidrは他と被らない任意のCIDRを指定する
kubeadm init --pod-network-cidr=10.8.0.0/16,fdf6:ad60:1db0::/64 --service-cidr=10.88.0.0/16,<NTT-NGN RA Prefix>:feed::/112
## kubectlをroot以外のユーザーでも使えるようにする
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

## ネットワークのセットアップ
```  
## SSHで一般ユーザーとしてコントロールプレーンノードに接続し、インストール
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.30.3/manifests/operator-crds.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.30.3/manifests/tigera-operator.yaml
```
## calicoctlのインストール
```
## PATHの通っているディレクトリに移動
cd /usr/local/bin
## calicoctlのダウンロード
sudo curl -L https://github.com/projectcalico/calico/releases/download/v3.30.3/calicoctl-linux-amd64 -o calicoctl
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
wget https://raw.githubusercontent.com/dodolia907/k8s/main/tyh/install/calico/custom-resources.yaml
wget https://raw.githubusercontent.com/dodolia907/k8s/main/tyh/install/calico/bgppeer.yaml
wget https://raw.githubusercontent.com/dodolia907/k8s/main/tyh/install/calico/config.yaml
## CIDRやAS番号など、環境に合わせて編集
vim custom-resources.yaml
vim bgppeer.yaml
vim config.yaml
## 設定適用
kubectl create -f custom-resources.yaml
calicoctl apply -f bgppeer.yaml
calicoctl apply -f config.yaml
```
## 一旦確認
```
watch kubectl get pod -A -o wide
```

## ワーカーノードのクラスタへの参加
```
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
apt -y install nfs-kernel-server
echo "/nfs 10.1.88.0/24(rw,sync,no_root_squash,no_subtree_check)" >> /etc/exports
exportfs -a
exportfs -v
systemctl enable --now nfs-server
```

# NFSクライアントのセットアップ
```
## 全てのノードで実施
apt -y install nfs-common
```

## コントロールプレーンノードに戻って作業
```
## Helmのインストール
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
## nfs-subdir-external-provisionerのインストール
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner --set nfs.server=10.1.88.101 --set nfs.path=/nfs --namespace nfs-provisioner --create-namespace
## MetalLBのインストール
# see what changes would be made, returns nonzero returncode if different
kubectl get configmap kube-proxy -n kube-system -o yaml | \
sed -e "s/strictARP: false/strictARP: true/" | \
kubectl diff -f - -n kube-system

# actually apply the changes, returns nonzero returncode on errors only
kubectl get configmap kube-proxy -n kube-system -o yaml | \
sed -e "s/strictARP: false/strictARP: true/" | \
kubectl apply -f - -n kube-system

kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.15.2/config/manifests/metallb-native.yaml
kubectl apply -f https://raw.githubusercontent.com/dodolia907/k8s/main/tyh/install/metallb/metallb-ipaddresspool.yaml
kubectl apply -f https://raw.githubusercontent.com/dodolia907/k8s/main/tyh/install/metallb/metallb-l2advertisement.yaml

## Nginx Ingress Controllerのインストール
helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx --create-namespace
## ArgoCDのインストール
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
kubectl patch svc argocd-server -n argocd -p '{"metadata": {"annotations": {"external-dns.alpha.kubernetes.io/hostname": "cd.k8s.ddlia.com"}}}'
cd /usr/local/bin
curl -L https://github.com/argoproj/argo-cd/releases/download/v3.1.7/argocd-linux-amd64 -o argocd
chmod +x argocd
argocd admin initial-password -n argocd
argocd login argocd.k8s.ddlia.com
argocd account update-password

## kubernetes-dashboardのインストール
## https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/  
# Add kubernetes-dashboard repository
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
# Deploy a Helm Release named "kubernetes-dashboard" using the kubernetes-dashboard chart
helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard --create-namespace --namespace kubernetes-dashboard
kubectl patch svc kubernetes-dashboard-kong-proxy -n kubernetes-dashboard -p '{"spec": {"type": "LoadBalancer"}}'
kubectl patch svc kubernetes-dashboard-kong-proxy -n kubernetes-dashboard -p '{"metadata": {"annotations": {"external-dns.alpha.kubernetes.io/hostname": "dash.k8s.ddlia.com"}}}'

## cloudflaredのインストール
kubectl create namespace cloudflare
wget https://raw.githubusercontent.com/dodolia907/k8s/main/tyh/install/cloudflared/token.yaml
echo "<your_tunnel_token>" | base64
vim token.yaml  ## 先ほどのbase64エンコードしたトークンに書き換え
kubectl apply -f token.yaml
kubectl apply -f https://raw.githubusercontent.com/dodolia907/k8s/main/tyh/install/cloudflared/tunnel.yaml

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