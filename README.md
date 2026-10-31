# k8s
このリポジトリでは、Kubernetesクラスタの管理を行います。

- 要件: [AGENTS.md](AGENTS.md)
- 構築と復旧の手順: [install/install.md](install/install.md)

## 構成
```
install/argocd/      Argo CDのHelm値とApp of Apps（apps/ に manifest/ の各アプリ）
install/kubeadm/     kubeadmの設定（デュアルスタック）
install/cilium/      Ciliumのvaluesと、BGP / L2 / LBプールの設定
install/sealed/      暗号化済みのSecret（手動で適用）
install/*            DNS、Tunnel、KubeVirtなどの基盤（Argo CD管理外、手動で適用）
manifest/*           アプリケーション（Argo CD管理）
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
3. 手順書に沿って `install/` のシステムコンポーネントを入れ、最後にArgo CDを入れると、アプリが自動で同期される。

PVの中身はバックアップされない。

## プラグインの更新
```
git -C plugins/ra-prefix-controller pull origin main
git add plugins/ra-prefix-controller
```
