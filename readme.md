Kubernetes/k8s setup  
# 参考
https://kubernetes.io/ja/docs/setup/production-environment/tools/kubeadm/install-kubeadm/
https://kubernetes.io/ja/docs/setup/production-environment/container-runtimes/
https://kubernetes.io/ja/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/
https://kubernetes.io/docs/setup/production-environment/container-runtimes/#containerd-systemd

# 注意
RHEL系OS用のスクリプトも用意してあるが未検証。
Ubuntu用のスクリプトはUbuntu 20.04 LTSで動作確認済み。

# コントロールプレーンのセットアップ  
## コントロールプレーンにKubernetesをインストールする    
```
## コントロールプレーンノードにSSH接続する  
## rootユーザーに切り替える
sudo su -

## コントロールプレーンノードでシェルスクリプトを実行
cd ~
(ubuntu) wget https://raw.githubusercontent.com/dodolia907/k8s/main/install-ubuntu-cp.sh
(ubuntu) chmod +x install-ubuntu-cp.sh
(ubuntu) ./install-ubuntu-cp.sh  
(rhel) wget https://raw.githubusercontent.com/dodolia907/k8s/main/install-rhel-cp.sh
(rhel) chmod +x install-rhel-cp.sh  
(rhel) ./install-rhel-cp.sh
export KUBECONFIG=/etc/kubernetes/admin.conf  

## cgroupの設定
vim /etc/containerd/config.toml
## 以下の場所でSystemdCgroup = trueに変更
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
  ...
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
    SystemdCgroup = true
## containerdの再起動
systemctl restart containerd

## ~/.bashrcの編集
vim ~/.bashrc  
export KUBECONFIG=/etc/kubernetes/admin.conf

## クラスタの初期化
## kubeadm join... と表示されるので、後でワーカーノードで使うためにメモしておく
## pod-network-cidrは他と被らない任意のCIDRを指定する
kubeadm init --pod-network-cidr=10.244.0.0/16

## kubectlをroot以外のユーザーでも使えるようにする
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

# ネットワークのセットアップ
## Calicoのインストール
```  
## SSHで一般ユーザーとしてコントロールプレーンノードに接続する
kubectl create -f https://projectcalico.docs.tigera.io/manifests/tigera-operator.yaml
```
## calicoctlのインストール
```
## PATHの通っているディレクトリに移動
cd /usr/local/bin
## calicoctlのダウンロード
sudo curl -L https://github.com/projectcalico/calico/releases/download/v3.24.5/calicoctl-linux-amd64 -o calicoctl
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
wget https://raw.githubusercontent.com/dodolia907/k8s/main/custom-resources.yaml
wget https://raw.githubusercontent.com/dodolia907/k8s/main/ixbgp.yaml
wget https://raw.githubusercontent.com/dodolia907/k8s/main/bgpconfig.yaml
## CIDRやAS番号など、環境に合わせて編集
vim custom-resources.yaml
vim ixbgp.yaml
vim bgpconfig.yaml
## 設定適用
kubectl apply -f custom-resources.yaml
calicoctl apply -f ixbgp.yaml
calicoctl apply -f bgpconfig.yaml
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

## ワーカーノードでシェルスクリプトを実行
cd ~
(ubuntu) wget https://raw.githubusercontent.com/dodolia907/k8s/main/install-ubuntu-wk.sh
(ubuntu) chmod +x install-ubuntu-wk.sh
(ubuntu) ./install-ubuntu-wk.sh
(rhel) wget https://raw.githubusercontent.com/dodolia907/k8s/main/install-rhel-wk.sh
(rhel) chmod +x install-rhel-wk.sh
(rhel) ./install-rhel-wk.sh  

## cgroupの設定
vim /etc/containerd/config.toml
## 以下の場所でSystemdCgroup = trueに変更
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
  ...
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
    SystemdCgroup = true
## containerdの再起動
systemctl restart containerd
```

## クラスタへ参加
```
## コントロールプレーンノードで実行したkubeadm initの結果に表示されたkubeadm join ... をペーストして実行する
kubeadm join ...
```

## ルーターの設定
ここではNEC IXルータを例とする
```
## ルーターにSSH接続する
## グローバルコンフィグモードに移行
enable-config
## BGP起動・BGPコンフィグモードに移行 (ルータ自身のAS番号を入力)
router bgp 65000
## 新規ピア設定 (全てのコントロールプレーン・ワーカーノードのIPアドレスを入力)
neighbor [ノード1のIPアドレス] remote-as 65000
neighbor [ノード2のIPアドレス] remote-as 65000
neighbor [ノード3のIPアドレス] remote-as 65000
neighbor [ノード4のIPアドレス] remote-as 65000
## ルートリフレクタクライアントの設定
neighbor [ノード1のIPアドレス] route-reflector-client
neighbor [ノード2のIPアドレス] route-reflector-client
neighbor [ノード3のIPアドレス] route-reflector-client
neighbor [ノード4のIPアドレス] route-reflector-client
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

# リセット
```
kubeadm reset
rm -rf /etc/cni/net.d
rm -rf $HOME/.kube/config
iptables -F
sudo reboot
```
