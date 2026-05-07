# Kubernetesのセットアップ  
AlmaLinux 9を使用する． 
## コンテナランタイムの準備  
全てのノードで実施する．  
```
## IPv4フォワーディングを有効化、iptablesからブリッジされたトラフィックを見えるようにする
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# この構成に必要なカーネルパラメーター、再起動しても値は永続します
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1
EOF

# 再起動せずにカーネルパラメーターを適用
sudo sysctl --system

lsmod | grep br_netfilter
lsmod | grep overlay

sysctl net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables net.ipv4.ip_forward net.ipv6.conf.all.forwarding net.ipv6.conf.default.forwarding
```
CRI-Oのインストール  
https://github.com/cri-o/packaging/blob/main/README.md#usage
```
## リポジトリの追加
KUBERNETES_VERSION=v1.36
CRIO_VERSION=v1.35

cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/rpm/repodata/repomd.xml.key
EOF

cat <<EOF | sudo tee /etc/yum.repos.d/cri-o.repo
[cri-o]
name=CRI-O
baseurl=https://download.opensuse.org/repositories/isv:/cri-o:/stable:/$CRIO_VERSION/rpm/
enabled=1
gpgcheck=1
gpgkey=https://download.opensuse.org/repositories/isv:/cri-o:/stable:/$CRIO_VERSION/rpm/repodata/repomd.xml.key
EOF
```

## kubeadm、kubelet、kubectlのインストール
```
sudo dnf install -y container-selinux
sudo dnf install -y cri-o kubelet kubeadm kubectl
sudo systemctl enable --now crio.service
sudo systemctl enable kubelet.service
sudo systemctl disable --now firewalld
```

## クラスタの初期化
```
## kubeadm join... と表示されるので、後でワーカーノードで使うためにメモしておく
## pod-network-cidrは他と被らない任意のCIDRを指定する
sudo kubeadm init --pod-network-cidr=10.8.0.0/16,fdf6:ad60:1db0:feed::/56 --service-cidr=10.96.0.0/12,fdf6:ad60:1db0:beef::/112 --skip-phases=addon/kube-proxy
## kubectlをroot以外のユーザーでも使えるようにする
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

## ネットワークのセットアップ
Ciliumを使用する．  
Cilium CLIのインストール
```
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
```

Ciliumのインストール
```
cilium install \
  --version 1.19.3 \
  --set ipv4.enabled=true \
  --set ipv6.enabled=true \
  --set routingMode=native \
  --set ipam.mode=kubernetes \
  --set ipv4NativeRoutingCIDR="10.8.0.0/16" \
  --set ipv6NativeRoutingCIDR="fdf6:ad60:1db0:feed::/56" \
  --set autoDirectNodeRoutes=true \
  --set kubeProxyReplacement=true \
  --set l2announcements.enabled=true \
  --set bgpControlPlane.enabled=true \
  --set k8sRequireIPv4PodCIDR=true \
  --set k8sRequireIPv6PodCIDR=true \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true \
  --set devices=enp3s0 \
  --set enableIPv4Masquerade=false \
  --set enableIPv6Masquerade=true \
  --set k8sServiceHost=10.1.88.101 \
  --set k8sServicePort=6443
```


## 一旦確認
```
cilium status --wait
watch kubectl get pod -A -o wide
```

## テスト
```
cilium connectivity test
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


# NFSサーバのセットアップ
```
## NFSサーバにSSH接続する
mkdir -p /ext
sudo dnf install -y nfs-utils
echo "/ext 10.1.88.0/24(rw,sync,no_root_squash,no_subtree_check)" | sudo tee -a /etc/exports
sudo systemctl enable --now rpcbind nfs-server
```

# NFSクライアントのセットアップ
```
## 全てのノードで実施
sudo dnf install -y nfs-utils
```

# nfs-subdir-external-provisionerのインストール
```
## Helmのインストール
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
## nfs-subdir-external-provisionerのインストール
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner --set nfs.server=10.1.88.101 --set nfs.path=/ext --namespace nfs-provisioner --create-namespace
```

# pi-holeのインストール
```
git clone https://github.com/dodolia907/k8s.git
cd ~/k8s/install/pi-hole
kubectl create ns pi-hole
kubectl apply -f .
```

# external-dnsのインストール
```
## 宅内環境
cd ~/k8s/install/external-dns
kubectl create ns external-dns
kubectl apply -f manifest.yaml
```

```
## ArgoCDのインストール
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
kubectl patch svc argocd-server -n argocd -p '{"metadata": {"annotations": {"external-dns.alpha.kubernetes.io/hostname": "cd.k8s.ddlia.com"}}}'
cd /usr/local/bin
curl -L https://github.com/argoproj/argo-cd/releases/download/v3.1.7/argocd-linux-amd64 -o argocd
chmod +x argocd
argocd admin initial-password -n argocd
argocd login cd.k8s.ddlia.com
argocd account update-password

## cloudflaredのインストール
kubectl create namespace cloudflare
wget https://raw.githubusercontent.com/dodolia907/k8s/main/tyh/install/cloudflared/token.yaml
echo "<your_tunnel_token>" | base64
vim token.yaml  ## 先ほどのbase64エンコードしたトークンに書き換え
kubectl apply -f token.yaml
kubectl apply -f https://raw.githubusercontent.com/dodolia907/k8s/main/tyh/install/cloudflared/tunnel.yaml

## KubeVirtのインストール
export RELEASE=$(curl https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt)
kubectl apply -f https://github.com/kubevirt/kubevirt/releases/download/${RELEASE}/kubevirt-operator.yaml
kubectl apply -f https://github.com/kubevirt/kubevirt/releases/download/${RELEASE}/kubevirt-cr.yaml
## virtctlのインストール
export VERSION=$(curl https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt)
curl -L https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/virtctl-${VERSION}-linux-amd64 -o virtctl
sudo mv virtctl /usr/local/bin/
sudo chmod +x /usr/local/bin/virtctl
## Containerized Data Importerのインストール
export VERSION=$(basename $(curl -s -w %{redirect_url} https://github.com/kubevirt/containerized-data-importer/releases/latest))
kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/$VERSION/cdi-operator.yaml
kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/$VERSION/cdi-cr.yaml
```

# リセット
```
sudo kubeadm reset
## 手順が表示されるので従う
sudo rm -rf /etc/cni/net.d
sudo rm -rf $HOME/.kube/config
sudo iptables -F
sudo reboot
```

# 参考資料
https://kubernetes.io/ja/docs/setup/production-environment/tools/kubeadm/install-kubeadm/  
https://kubernetes.io/ja/docs/setup/production-environment/container-runtimes/  
https://kubernetes.io/ja/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/  
https://kubernetes.io/docs/setup/production-environment/container-runtimes/#containerd-systemd  

https://kubevirt.io/user-guide/cluster_admin/installation/#installing-kubevirt-on-kubernetes  
https://kubevirt.io/user-guide/user_workloads/virtctl_client_tool/  
https://kubevirt.io/labs/kubernetes/lab2.html