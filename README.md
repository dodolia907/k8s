# k8s
このリポジトリでは、Kubernetesクラスタの管理を行います。

- 要件: [AGENTS.md](AGENTS.md)
- 構築と復旧の手順: [install/install.md](install/install.md)

## 構成
```
install/argocd/      Argo CD本体とApp of Apps（apps/ に各コンポーネント）
install/kubeadm/     kubeadmの設定（デュアルスタック）
install/cilium/      Ciliumのvaluesと、BGP / L2 / LBプールの設定
install/sealed/      暗号化済みのSecret
install/*            DNS、Tunnel、KubeVirtなどの基盤
manifest/*           アプリケーション
plugins/*            別リポジトリのプラグイン（submodule）
```

```
          IPv4: BGP (LB IP, PodCIDR)     IPv6: NDP (LB IP)
                       |                       |
                     ルーター ---- NTT西日本 (RA /64)
                       |
      +----------------+----------------+
      |                |                |
 10.1.88.101         ワーカー          ワーカー
 CP + NFS (/ext)
```

## 復旧
1. `git clone --recurse-submodules` で取得し、手順書に沿ってノードとクラスタを構築する。
2. オフラインに保管したSealed Secretsの復号鍵を戻す。これがないと `install/sealed/` のSecretを復号できない。
3. Argo CDを入れると、残りは自動で同期される。

PVの中身はバックアップされない。

## プラグインの更新
```
git -C plugins/ra-prefix-controller pull origin main
git add plugins/ra-prefix-controller
```
