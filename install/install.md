# Kubernetesのセットアップ
Debian 13.7.0を使用する．要件は [AGENTS.md](../AGENTS.md) を参照．

`<...>` は実機の値に置き換える．以下は `enp2s0`，コントロールプレーン兼NFSサーバ `10.1.88.101` を前提とする．

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
## IPv4は /etc/network/interfaces に設定済み（10.1.88.x/16，ゲートウェイ 10.1.0.1）
## ULAはノードごとに cp00: fd00:20::101，wk01〜wk03: fd00:20::151〜153
sudo tee /etc/network/interfaces.d/enp2s0-ipv6 <<EOF
iface enp2s0 inet6 static
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
net.ipv6.conf.enp2s0.accept_ra      = 2
net.ipv6.conf.enp2s0.autoconf       = 1
EOF
sudo sysctl --system

## GUAとRAの経路を確認
ip -6 addr show dev enp2s0 scope global
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
最新の安定版を確認し，下のコマンドのバージョンを更新する．
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

```
`/dev/dri` は全ノードにある．GIDは `getent group video render` で確認し，[manifest/live/deployment.yaml](../manifest/live/deployment.yaml) の `supplementalGroups` に合わせる．

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

# システムコンポーネントのインストール
`install/` 以下はArgo CDで管理しない．誤った同期や削除でクラスタごと落とさないため，HelmとkubectlでGitの内容を手動で適用する．変更時は同じコマンドを再実行する．
```
cd ~/k8s
kubectl apply -f install/namespaces/
kubectl apply -k install/cilium/

## cilium-ingress のチャートにはIPファミリーの設定がない
kubectl patch service cilium-ingress -n kube-system -p '{"spec": {"ipFamilyPolicy": "PreferDualStack", "ipFamilies": ["IPv4", "IPv6"]}}'

helm upgrade --install sealed-secrets-controller sealed-secrets --repo https://bitnami.github.io/sealed-secrets --version 2.22.0 -n kube-system -f install/sealed-secrets/values.yaml
helm upgrade --install nfs-provisioner nfs-subdir-external-provisioner --repo https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/ --version 4.0.18 -n storage -f install/nfs-provisioner/values.yaml
helm upgrade --install ra-prefix-controller plugins/ra-prefix-controller/chart -n kube-system -f install/ra-prefix-controller/values.yaml
kubectl apply -k install/metrics-server/
kubectl apply -f install/fortigate/
kubectl apply --server-side --force-conflicts -k install/kubevirt/
```

# Secretの作成
公開リポジトリなので，Secretは `kubeseal` で暗号化してコミットする．
```
KUBESEAL_VERSION=0.41.2
curl -L https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz | tar xz kubeseal
sudo install -m 755 kubeseal /usr/local/bin/kubeseal

seal() { kubeseal --controller-name sealed-secrets-controller --controller-namespace kube-system -o yaml > ~/k8s/install/sealed/$1.yaml; }

## Cloudflare Tunnelのトークン（Private Network専用．Public Hostnameは設定しない）
kubectl create secret generic tunnel-token -n tunnel --from-literal=token=<トークン> --dry-run=client -o yaml | seal tunnel-token

## Cloudflare APIトークン (Zone/DNS/Edit，Zone/Zone/Read)
kubectl create secret generic cloudflare-api-key -n dns --from-literal=apiKey=<トークン> --dry-run=client -o yaml | seal cloudflare-api-key

## Tunnel Ingressコントローラ用のAPIトークン (Zone/DNS/Edit，Zone/Zone/Read，Account/Cloudflare Tunnel/Edit)
## Web公開用のTunnel．tunnel_name はPrivate Network用のTunnelと別の名前にする．なければ作られ，既存なら経路が上書きされる
kubectl create secret generic cloudflare-tunnel-ingress -n tunnel --from-literal=api_token=<トークン> --from-literal=account_id=<アカウントID> --from-literal=tunnel_name=k8s-ingress --dry-run=client -o yaml | seal cloudflare-tunnel-ingress

kubectl apply -f install/sealed/
```

cloud-consoleに必要なものは [manifest/cloud-console/README.md](../manifest/cloud-console/README.md) を参照．Secretは同じ手順で暗号化する．

**復号鍵のバックアップ．** クラスタを作り直すと復号できなくなるので，オフラインに保管する．この出力は絶対にコミットしない．
```
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > sealed-secrets-key.yaml
```
復元するときは，`kubectl apply -f sealed-secrets-key.yaml` を実行してコントローラを再起動する．

Secretを作ってから，DNSとTunnelを入れる．
```
kubectl apply -f install/pi-hole/
kubectl apply -f install/external-dns/
kubectl apply -k install/cloudflared/
helm upgrade --install cloudflare-tunnel-ingress-controller cloudflare-tunnel-ingress-controller --repo https://helm.strrl.dev --version 0.1.0 -n tunnel -f install/cloudflared/ingress-controller-values.yaml
```

Web Appを公開するときは，Ingressに `ingressClassName: cloudflare-tunnel` を指定する．DNSのCNAMEはコントローラが作るので，external-dnsのアノテーションは付けない．
```
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: <アプリ>
  namespace: <アプリ>
spec:
  ingressClassName: cloudflare-tunnel
  rules:
  - host: <アプリ>.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: <Service>
            port:
              number: 80
```

# Argo CDのインストール
Argo CDが管理するのは `manifest/` のアプリだけ（[argocd/apps/](argocd/apps/)）．事前に，このリポジトリの変更をGitHubへpushしておく．
```
cd ~/k8s
helm upgrade --install argocd argo-cd --repo https://argoproj.github.io/argo-helm --version 10.11.6 -n argocd --create-namespace -f install/argocd/values.yaml
kubectl -n argocd rollout status deploy/argocd-server
kubectl apply -f install/argocd/root.yaml

cd /usr/local/bin
sudo curl -L https://github.com/argoproj/argo-cd/releases/download/v3.5.6/argocd-linux-amd64 -o argocd
sudo chmod +x argocd
argocd admin initial-password -n argocd
kubectl -n argocd get svc argocd-server
argocd login <argocd-serverのLB IP> --insecure
argocd account update-password
```

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

# 札幌クラスタ（cts）
豊橋（tyh）とは別の単一ノードクラスタとして，Windowsの上のHyper-V VMに建てる．J:COMはIPv4のみなので，シングルスタックにする．tyhを操作できる管理マシンからVPN経由で操作し，`manifest/cts/` のアプリはtyhのArgo CDが同期する．

| 項目 | tyh | cts |
|---|---|---|
| PodCIDR | `10.8.0.0/16` | `10.9.0.0/16` |
| Service | `10.96.0.0/12` | `10.112.0.0/12` |
| LBプール | `10.88.0.0/16` | `10.89.0.0/24` |
| AS番号 | 64512 | 64513 |

札幌のLANがこれらと重なるときは，`install/cts/` の値を変える．

## VMの作成
Hyper-Vが使えるWindowsのエディション（ProやEnterpriseなど）で，管理者のPowerShellから実行する．WSL2はLANから直接到達できる構成にしにくいので使わず，WindowsノードはCiliumが対応していないので使わない．ホストのメモリに余裕がなければ `-MemoryStartupBytes` を減らす．
```
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All
## 再起動後
Get-NetAdapter
New-VMSwitch -Name external -NetAdapterName "<NIC名>" -AllowManagementOS $true
New-VM -Name cts01 -Generation 2 -MemoryStartupBytes 10GB -NewVHDPath "<保存先>\cts01.vhdx" -NewVHDSizeBytes 128GB -SwitchName external
Set-VM -Name cts01 -ProcessorCount 4 -StaticMemory -CheckpointType Disabled -AutomaticStartAction Start -AutomaticStopAction ShutDown
Set-VMFirmware -VMName cts01 -SecureBootTemplate MicrosoftUEFICertificateAuthority
Add-VMDvdDrive -VMName cts01 -Path "<Debian 13.7.0のISO>"
Set-VMFirmware -VMName cts01 -FirstBootDevice (Get-VMDvdDrive -VMName cts01)
Start-VM -Name cts01
```
ホストの再起動でctsも止まるので，Windows Updateの再起動の時間を調整しておく．

## ノードの準備
DebianをインストールしてIPv4を固定する．続けて，「ノードの準備」のうちswapの無効化，カーネルの設定，containerd，kubeadmの手順を実施する．次の点は読み替える．
- NICは `ip link` で確認する．`eth0` でなければ [cts/cilium/values.yaml](cts/cilium/values.yaml) の `devices` を変える．
- ULAとRAの設定，`enp2s0` のsysctl，`/etc/hosts`，NFSは不要．
- `net.ipv6.conf.*` のforwardingの行も不要．

## ルーターの設定
Si-R（AS65001）にctsノードをAS64513のネイバーとして追加し，`10.89.0.0/24` だけを受け取って，IXへ広報する．

tyhのArgo CDはPodのIP（`10.8.x.x`）のままctsのAPIに接続する．次を確認する．
- Si-Rが `10.1.0.0/16`，`10.8.0.0/16`，`10.88.0.0/16` の経路を持つこと．
- IXとFortiGateが，札幌のLANと `10.89.0.0/24` の経路を持ち，ネクストホップに到達できること．届かなければFortiGateで `next-hop-self` を有効にする．
- FortiGateで，`10.8.0.0/16` から札幌ノードの6443番への通信を許可すること．このポリシーではNATを無効にする．
- 6443番とSSHはSi-Rでポート開放しないこと．

## クラスタの初期化
ctsノードで実行する．
```
cd ~/k8s/install/cts/kubeadm
sudoedit init-config.yaml
sudo kubeadm init --config init-config.yaml
## 単一ノードなのでコントロールプレーンにPodを載せる
sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl taint nodes --all node-role.kubernetes.io/control-plane-

## ctsノード上でもkubectlを使えるようにする
mkdir -p $HOME/.kube
sudo install -m 600 -o "$(id -u)" -g "$(id -g)" /etc/kubernetes/admin.conf $HOME/.kube/config
```

以降はtyhを操作できる管理マシンで実行する．この管理者権限の設定ファイルは絶対にコミットしない．`values.yaml` と `bgp.yaml` に入れた実アドレスもコミットしない（作業用のコピーを編集してもよい）．tyhと同じ版にするため，`containerd.io` と `kubeadm` などはaptでバージョンを指定して入れる．
```
ssh <ctsノード> sudo cat /etc/kubernetes/admin.conf > ~/.kube/cts.conf
chmod 600 ~/.kube/cts.conf
export KUBECONFIG=~/.kube/cts.conf
kubectl get nodes

cd ~/k8s
sudoedit install/cts/cilium/values.yaml
sudoedit install/cts/cilium/bgp.yaml
helm upgrade --install cilium cilium --repo https://helm.cilium.io --version 1.20.4 -n kube-system -f install/cts/cilium/values.yaml
cilium status --wait
kubectl apply -f install/cts/namespaces.yaml
kubectl apply -k install/cts/cilium/
kubectl apply -f install/cts/argocd/rbac.yaml
kubectl apply -k install/metrics-server/
helm upgrade --install sealed-secrets-controller sealed-secrets --repo https://bitnami.github.io/sealed-secrets --version 2.22.0 -n kube-system -f install/sealed-secrets/values.yaml

cilium bgp peers
```

## Secretの作成とTunnel
Web公開用のTunnelは `k8s-ingress-cts` にする．`k8s-ingress` にするとtyhの経路を上書きする．external-dnsは入れない．
```
export KUBECONFIG=~/.kube/cts.conf
kubectl create secret generic cloudflare-tunnel-ingress -n tunnel --from-literal=api_token=<トークン> --from-literal=account_id=<アカウントID> --from-literal=tunnel_name=k8s-ingress-cts --dry-run=client -o yaml \
  | kubeseal --controller-name sealed-secrets-controller --controller-namespace kube-system -o yaml > ~/k8s/install/cts/sealed/cloudflare-tunnel-ingress.yaml
kubectl apply -f install/cts/sealed/cloudflare-tunnel-ingress.yaml
helm upgrade --install cloudflare-tunnel-ingress-controller cloudflare-tunnel-ingress-controller --repo https://helm.strrl.dev --version 0.1.0 -n tunnel -f install/cts/cloudflared/ingress-controller-values.yaml

## 復号鍵のバックアップ．tyhとは別の鍵なので，別に保管する．絶対にコミットしない
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > sealed-secrets-key-cts.yaml
```

## tyhのArgo CDへの登録
`namespaces` に書いた名前空間だけをArgo CDが操作する．アプリを増やすときは，ここと [cts/argocd/rbac.yaml](cts/argocd/rbac.yaml) に追加する．`argocd-manager` のトークンはtyhの鍵で暗号化する．
```
TOKEN=$(KUBECONFIG=~/.kube/cts.conf kubectl -n kube-system get secret argocd-manager-token -o jsonpath='{.data.token}' | base64 -d)
CA=$(KUBECONFIG=~/.kube/cts.conf kubectl -n kube-system get secret argocd-manager-token -o jsonpath='{.data.ca\.crt}')

unset KUBECONFIG
kubectl create secret generic cluster-cts -n argocd \
  --from-literal=name=cts \
  --from-literal=server=https://<ctsノードのIPv4>:6443 \
  --from-literal=namespaces=nginx-test \
  --from-literal=config="{\"bearerToken\":\"$TOKEN\",\"tlsClientConfig\":{\"caData\":\"$CA\"}}" \
  --dry-run=client -o yaml \
  | kubectl label --local -f - argocd.argoproj.io/secret-type=cluster -o yaml \
  | kubeseal --controller-name sealed-secrets-controller --controller-namespace kube-system -o yaml > ~/k8s/install/sealed/cluster-cts.yaml
kubectl apply -f install/sealed/cluster-cts.yaml
argocd cluster list
```
[argocd/apps/cts-nginx-test.yaml](argocd/apps/cts-nginx-test.yaml) はGitHubへpushするとtyhのArgo CDに作られる．登録が済むまでは同期エラーになるので，登録してからpushする．

## 確認
```
kubectl -n argocd get application cts-nginx-test

## tyhのノードとPodから到達を確認する
KUBECONFIG=~/.kube/cts.conf kubectl -n nginx-test get svc nginx
traceroute <札幌のLB IP>
curl http://<札幌のLB IP>/

## Tunnel経由で確認する
curl https://test-cts.ddlia.com/
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
