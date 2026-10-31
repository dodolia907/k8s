# AGENTS.md

このリポジトリは自宅Kubernetesクラスタの構成を管理する。公開リポジトリなので、平文のSecret、実アドレスを含む設定、RA prefixをコミットしない。

## 基盤の要件
- **OS:** 全ノード Debian 13.7.0。
- **ノード:** メモリは各10GB。エッジサーバーとして運用し、常駐コンポーネントとメモリ消費を最小限にする。全Podにrequests/limitsを設定する。
- **クラスタ:** kubeadmで構築する。手順は [install/install.md](install/install.md) に書き、Kubernetes公式の [install-kubeadm](https://kubernetes.io/ja/docs/setup/production-environment/tools/kubeadm/install-kubeadm/) と [container-runtimes](https://kubernetes.io/ja/docs/setup/production-environment/container-runtimes/#containerd) に従う。
- **ランタイム:** containerd。[getting-started](https://github.com/containerd/containerd/blob/main/docs/getting-started.md) に従い、aptでDockerのリポジトリから `containerd.io` を導入する。CRI-Oは使わない。
- **CNI:** Ciliumの最新安定版。導入時に確認してその版に固定する。kube-proxyは置き換える。

## ネットワークの要件
- IPv4/IPv6デュアルスタック。
- **IPv4:** BGPでLB IPとPodCIDRを広報する。
- **IPv6:** L2（NDP）でLB IPとexternalIPを広報する。PodCIDRはL2で広報できないので、Podの外向き通信はマスカレードする。
- **RA prefix:** GUAはNTT西日本のRAで与えられる/64を使う。設備工事で変わる可能性がある。
  - クラスタ内部（kubeletの `node-ip`、Pod、Service、内部向けLB）は固定ULAを使い、RA prefixに依存させない。
  - RA prefixを使うのは、ノードのGUA（SLAAC）と外部公開用LBのみ。
  - forwardingを有効にするため、ノードのNICは `accept_ra=2` にする。

## RA prefix自動追従の要件
- CronJobではなく、Kubernetesのプラグインとして導入できるコントローラにする。
- プラグインは別リポジトリで管理し、submoduleとして参照する（[dodolia907/ra-prefix-controller](https://github.com/dodolia907/ra-prefix-controller)、[plugins/ra-prefix-controller/](plugins/ra-prefix-controller/)）。変更は先にプラグイン側へ入れ、こちらでは参照先コミットを更新する。
- ポーリングせず、netlinkでprefixの変化を検知する。
- CiliumのLBプール（`CiliumLoadBalancerIPPool`）を、検出したprefixへ追従させる。
- メモリ消費を小さく抑え、このクラスタ固有の値は設定として外から渡せるようにする。
- prefixを検出できないときは、プールを変更しない。
- 権限は対象プールの更新に必要な範囲に絞る。

## namespaceの要件
- 基盤は役割ごと: `dns`（Pi-hole、external-dns）、`tunnel`（cloudflared）、`storage`（NFSプロビジョナ）。
- アプリは1アプリ1namespaceで、`manifest/` のディレクトリ名と揃える。
- `kube-system`、`argocd`、`kubevirt`、`cdi` は上流の前提に合わせる。ra-prefix-controller、Sealed Secrets、Cilium、metrics-serverは `kube-system`。
- 共通の名前空間は [install/namespaces/](install/namespaces/) で作る（`cloud-console` は自身のマニフェストで作る）。

## ストレージの要件
- `10.1.88.101` のext4 + NFSを `nfs-subdir-external-provisioner` で動的プロビジョニングする。StorageClass名は `nfs-client`。
- iSCSIとZFSは検討のうえ不採用とした（メモリ消費と構成の複雑さのため）。提案し直さない。
- NFS上のSQLiteやPrometheusは1レプリカかつ `Recreate` で動かす。

## 運用の要件
- Argo CDは `manifest/` のアプリだけをApp of Appsで管理する。`install/` のシステムコンポーネント（Cilium、Argo CD自身、Sealed Secrets、NFS、DNS、Tunnel、KubeVirtなど）は、誤って落とさないようArgo CDで管理せず、HelmとkubectlでGitの内容を手動で適用する。
- 全コンポーネントのバージョンを固定する。`latest` などの可変タグは使わない。
- Secretは Sealed Secrets で暗号化してコミットする。復号鍵はオフラインに保管する。
- 再インストールを想定し、手作業の手順は `install/install.md` に残す。
