# Kubernetesのセットアップ
Debian 13.7.0を使用する．要件は [AGENTS.md](../AGENTS.md) を参照．

`<...>` は実機の値に置き換える．以下は `enp3s0`，コントロールプレーン兼NFSサーバ `10.1.88.101` を前提とする．

# リポジトリの取得
```
git clone --recurse-submodules https://github.com/dodolia907/k8s.git
```

# ノードの準備
全てのノードで実施する．

## OSのインストール
`10.1.88.101` では，データ用ディスクにOSを入れないよう，ディスクを外すか `/dev/disk/by-id` で確認する．

## 確認とswapの無効化
MACアドレスと `product_uuid` がノード間で重複していないことを確認する．
```
ip link
sudo cat /sys/class/dmi/id/product_uuid

sudo swapoff -a
## /etc/fstab のswapの行を削除する
sudoedit /etc/fstab
```

## ネットワーク
IPv4とULAは固定し，GUAはRAからSLAACで取得する．RA prefixは変わる可能性があるので，kubeletなどに設定しない．
```
sudo tee /etc/network/interfaces.d/enp3s0 <<EOF
auto enp3s0
iface enp3s0 inet static
    address <このノードのIPv4>/24
    gateway <IPv4ゲートウェイ>
iface enp3s0 inet6 static
    address <このノードの固定ULA>/64
    autoconf 1
    accept_ra 2
EOF

## APIサーバの名前はクラスタ内のPi-holeに依存させない
echo "10.1.88.101 k8s-api.internal" | sudo tee -a /etc/hosts
```

カーネルの設定
```
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
net.ipv6.conf.default.forwarding    = 1
## forwarding有効時もRAを受ける
net.ipv6.conf.enp3s0.accept_ra      = 2
net.ipv6.conf.enp3s0.autoconf       = 1
EOF
sudo sysctl --system

## GUAとRAの経路を確認
ip -6 addr show dev enp3s0 scope global
ip -6 route show default
```

## containerdのインストール
https://github.com/containerd/containerd/blob/main/docs/getting-started.md の Option 2 に従い，Dockerのaptリポジトリから `containerd.io` を入れる．runcは同梱されている．CNIはCiliumが入れるので，CNI pluginsは入れない．
```
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update
## 入るバージョンがKubernetes 1.37に対応していることを確認する
apt list --all-versions containerd.io
sudo apt install -y containerd.io
sudo apt-mark hold containerd.io
```

設定．パッケージの既定の設定はCRIが無効なので，生成し直す．
```
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
## disabled_plugins に cri がないこと，SystemdCgroup = true であることを確認
grep -nE 'disabled_plugins|SystemdCgroup' /etc/containerd/config.toml
sudo systemctl restart containerd
```

## kubeadm，kubelet，kubectlのインストール
https://kubernetes.io/ja/docs/setup/production-environment/tools/kubeadm/install-kubeadm/
```
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg nfs-common
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.37/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.37/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable --now kubelet
```

sandboxイメージをkubeadmに合わせる．
```
kubeadm config images list | grep pause
## 上の値と異なれば，/etc/containerd/config.toml の sandbox を書き換えて再起動する
grep -n sandbox /etc/containerd/config.toml
sudo systemctl restart containerd
```

# NFSサーバのセットアップ
`10.1.88.101` で実施する．**指定したディスクの内容は全て消える．**
```
sudo apt install -y nfs-kernel-server
ls -l /dev/disk/by-id/
sudo mkfs.ext4 /dev/disk/by-id/<データ用ディスク>
sudo mkdir -p /ext
echo "UUID=$(sudo blkid -s UUID -o value /dev/disk/by-id/<データ用ディスク>) /ext ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
sudo mount /ext
echo "/ext 10.1.88.0/24(rw,sync,no_root_squash,no_subtree_check)" | sudo tee -a /etc/exports
sudo exportfs -ra
sudo systemctl enable --now nfs-kernel-server
```
`no_root_squash` はPi-holeなどrootで動くPodの書き込みに使う．不要と確認できたら外す．

# クラスタの初期化
デュアルスタックの設定は [kubeadm/init-config.yaml](kubeadm/init-config.yaml) にある．`node-ip` を実機の値にしてから実行する．
```
cd ~/k8s/install/kubeadm
sudoedit init-config.yaml
sudo kubeadm init --config init-config.yaml

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

# Ciliumのインストール
最新の安定版を確認し，[argocd/apps/cilium.yaml](argocd/apps/cilium.yaml) のバージョンと揃える．
```
curl -s https://raw.githubusercontent.com/cilium/cilium/main/stable.txt

curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 | bash
helm install cilium cilium --repo https://helm.cilium.io --version 1.20.4 -n kube-system -f ~/k8s/install/cilium/values.yaml
```

Cilium CLIのインストールと確認
```
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}

cilium status --wait
```

# ワーカーノードのクラスタへの参加
```
## コントロールプレーンノードで実行する．トークンとハッシュをコミットしないこと
kubeadm token create --print-join-command

## ワーカーノードで実行する
cd ~/k8s/install/kubeadm
sudoedit join-config.yaml
sudo kubeadm join --config join-config.yaml

## 確認．全ノードにIPv4とULAがあること
kubectl get nodes -o wide
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.podCIDRs}{"\n"}{end}'

## 実機のあるノードにラベルを付ける（live）
kubectl label node <GPUのあるノード> ddlia.com/gpu=true
```
`/dev/dri` のGIDはDebianの実値を `getent group video render` で確認し，[manifest/live/deployment.yaml](../manifest/live/deployment.yaml) の `supplementalGroups` に合わせる．`dmx` は `/dev/ttyUSB0` のあるノード名を [manifest/dmx/deployment.yaml](../manifest/dmx/deployment.yaml) の `nodeName` に合わせる．

# ルーターの設定
IPv4のLB IPとPodCIDRをBGPで受ける．ルーターのAS番号は65000，クラスタのAS番号は64512．ピアのアドレスは [cilium/v4-bgp.yaml](cilium/v4-bgp.yaml) に合わせる．

NEC IXルータの場合
```
enable-config
router bgp 65000
## 全てのノードのIPアドレスを入力
neighbor <ノードのIPアドレス> remote-as 64512
exit
write memory
## StateがESTABLISHEDになっていればOK
show ip bgp summary
```

IPv6はL2（NDP）で広報する．ルーターがRA prefixをWANとLANで共有している（ND proxy）場合，GUAのLB IPのNDPも中継できることを確認する．

# Argo CDのインストール
ここから先はArgo CDが管理する．事前に，このリポジトリの変更をGitHubへpushしておく．
```
cd ~/k8s
kubectl apply --server-side --force-conflicts -k install/argocd

cd /usr/local/bin
sudo curl -L https://github.com/argoproj/argo-cd/releases/download/v3.4.1/argocd-linux-amd64 -o argocd
sudo chmod +x argocd
argocd admin initial-password -n argocd
kubectl -n argocd get svc argocd-server
argocd login <argocd-serverのLB IP>
argocd account update-password
```

`cilium-ingress` のチャートにはIPファミリーの設定がないので，デュアルスタックだけ手動で設定する．
```
kubectl patch service cilium-ingress -n kube-system -p '{"spec": {"ipFamilyPolicy": "PreferDualStack", "ipFamilies": ["IPv4", "IPv6"]}}'
```

# Secretの作成
公開リポジトリなので，Secretは `kubeseal` で暗号化してコミットする．コントローラはArgo CDが入れる．
```
KUBESEAL_VERSION=0.41.2
curl -L https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz | tar xz kubeseal
sudo install -m 755 kubeseal /usr/local/bin/kubeseal

seal() { kubeseal --controller-name sealed-secrets-controller --controller-namespace kube-system -o yaml > ~/k8s/install/sealed/$1.yaml; }

## Pi-hole APIのパスワード．Pi-holeとexternal-dnsで同じSecret名を使う
kubectl create secret generic pihole-api -n dns --from-literal=password=<パスワード> --dry-run=client -o yaml | seal pihole-api

## Cloudflare Tunnelのトークン
kubectl create secret generic tunnel-token -n tunnel --from-literal=token=<トークン> --dry-run=client -o yaml | seal tunnel-token

## Cloudflare APIトークン (Zone/DNS/Edit，Zone/Zone/Read)
kubectl create secret generic cloudflare-api-key -n dns --from-literal=apiKey=<トークン> --dry-run=client -o yaml | seal cloudflare-api-key
```

cloud-consoleに必要なものは [manifest/cloud-console/README.md](../manifest/cloud-console/README.md) を参照．Secretは同じ手順で暗号化する．

コミットしてpushすると，Argo CDが同期する．

**復号鍵のバックアップ．** クラスタを作り直すと復号できなくなるので，オフラインに保管する．この出力は絶対にコミットしない．
```
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > sealed-secrets-key.yaml
```
復元するときは，コントローラを入れる前後で `kubectl apply -f sealed-secrets-key.yaml` を実行し，コントローラを再起動する．

# 確認
```
kubectl -n argocd get applications
cilium connectivity test

## RA prefixへの追従
kubectl -n kube-system logs deploy/ra-prefix-controller
kubectl get ciliumloadbalancerippools

## メモリの余力
kubectl top nodes
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
https://kubernetes.io/ja/docs/setup/production-environment/container-runtimes/#containerd
https://github.com/containerd/containerd/blob/main/docs/getting-started.md
https://docs.docker.com/engine/install/debian/
https://kubernetes.io/ja/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/
https://docs.cilium.io/en/stable/network/l2-announcements/
https://kubevirt.io/user-guide/cluster_admin/installation/#installing-kubevirt-on-kubernetes
