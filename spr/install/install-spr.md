# Kubernetesのセットアップ 
Debian 13にて動作確認済み、シングルノード
## k3sのインストール
```
curl -sfL https://get.k3s.io | K3S_KUBECONFIG_MODE="644" INSTALL_K3S_EXEC="--flannel-backend=none --cluster-cidr=10.9.0.0/16 --disable-network-policy --disable=traefik" sh -
```
## Calicoのインストール
```
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.30.2/manifests/operator-crds.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.30.2/manifests/tigera-operator.yaml
```
## calicoctlのインストール
```
## PATHの通っているディレクトリに移動
cd /usr/local/bin
## calicoctlのダウンロード
sudo curl -L https://github.com/projectcalico/calico/releases/download/v3.30.2/calicoctl-linux-amd64 -o calicoctl
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
wget https://raw.githubusercontent.com/dodolia907/k8s/main/spr/install/calico/custom-resources.yaml
wget https://raw.githubusercontent.com/dodolia907/k8s/main/spr/install/calico/bgppeer.yaml
wget https://raw.githubusercontent.com/dodolia907/k8s/main/spr/install/calico/bgpconfig.yaml
## CIDRやAS番号など、環境に合わせて編集
vim custom-resources.yaml
vim bgppeer.yaml
vim bgpconfig.yaml
## 設定適用
kubectl create -f custom-resources.yaml
calicoctl apply -f bgppeer.yaml
calicoctl apply -f bgpconfig.yaml
```
## 確認
```
watch kubectl get pod -A -o wide
```
## ルーターの設定
富士通Si-RルータとBGPでピアリングを行う。
```
configure
routemanage ip redist bgp connected on
bgp as 0.65001
bgp neighbor 0 address 172.31.5.1
bgp neighbor 0 as 0.64513
bgp neighbor 0 ip filter 0 act pass out
bgp neighbor 0 ip filter 0 route 172.31.0.0/20 exact
bgp neighbor 0 ip filter 0 set medmetric 100
bgp ip redist 0 reject default
bgp ip redist 1 pass any
save
commit
show ip bgp status
```
## 確認
```
calicoctl get nodes -o wide
calicoctl get bgpPeer -o wide
calicoctl get ippool -o wide
calicoctl get bgpConfiguration -o wide
watch kubectl get pod -A -o wide
```
## nfs-subdir-external-provisionerのインストール
```
sudo apt-get install --yes nfs-kernel-server
sudo vim /etc/exports
/nfs localhost(rw,no_root_squash)
sudo systemctl restart nfs-server
sudo systemctl enable --now nfs-server
sudo apt-get update && sudo apt-get install gpg --yes
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
sudo apt-get install apt-transport-https --yes
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install helm
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner --set nfs.server=localhost --set nfs.path=/nfs
```
## MetalLBのインストール
```
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.15.2/config/manifests/metallb-native.yaml
kubectl apply -f https://raw.githubusercontent.com/dodolia907/k8s/main/spr/install/metallb/metallb-ipaddresspool.yaml
```
## ArgoCDのインストール
```
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
cd /usr/local/bin
curl -L https://github.com/argoproj/argo-cd/releases/download/v3.1.0/argocd-linux-amd64 -o argocd
chmod +x argocd
argocd admin initial-password -n argocd
argocd login 10.89.0.0
argocd account update-password
```
## KubeVirtのインストール
```
export RELEASE=$(curl https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt)
kubectl apply -f https://github.com/kubevirt/kubevirt/releases/download/${RELEASE}/kubevirt-operator.yaml
kubectl apply -f https://github.com/kubevirt/kubevirt/releases/download/${RELEASE}/kubevirt-cr.yaml
kubectl -n kubevirt wait kv kubevirt --for condition=Available
```
## CDIのインストール
```
export TAG=$(curl -s -w %{redirect_url} https://github.com/kubevirt/containerized-data-importer/releases/latest)
export VERSION=$(echo ${TAG##*/})
kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/$VERSION/cdi-operator.yaml
kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/$VERSION/cdi-cr.yaml
```
# リセット
```
/usr/local/bin/k3s-uninstall.sh
```

# 参考資料
https://docs.tigera.io/calico/latest/getting-started/kubernetes/k3s/quickstart  
https://docs.tigera.io/calico/latest/networking/configuring/bgp#top-of-rack-tor  
https://metallb.universe.tf/installation/  
https://metallb.universe.tf/configuration/calico/  