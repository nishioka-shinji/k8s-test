# glaucus

kind クラスタ向けの K8s マニフェスト置き場。マニフェストはすべて `manifests/` 配下に置き、手元の作業ツリーの `manifests/` をローカルレジストリ（kind-registry）へ OCI artifact として push し、Flux（flux-system）がそれを同期する。artifact のルートは `manifests/` になる。`manifests/kustomization.yaml` は `manifests/flux-system/` だけを束ね、各アプリ（authentik / mailpit / caddy-demo / unleash / unleash-demo / cert-manager / openfeature / openfeature-demo / prometheus / imgproxy-2 / istio / istio-ingress / istio-demo / istio-external / kiali / dependency-track）は常時同期せず、検証したいアプリだけを `manifests/flux-system/apps.yaml` に Flux Kustomization として宣言して同期する（既定は空）。宣言の書き方と依存するアプリの組み合わせ（wait / dependsOn）は `manifests/flux-system/README.md` の「アプリを宣言するとき」を参照する。
クラスタは `kind/cluster.yaml`（control-plane 1 台 + worker 2 台）から作る。これは Flux の同期対象ではないので `manifests/` の外に置く。
クラスタ作成・push 手順とローカルレジストリの起動は `manifests/flux-system/README.md` を参照する。
各アプリは Flux の HelmRepository / HelmRelease か素の manifest で管理する。
`manifests/authentik/` の再構築手順（Secret 作成など手作業の部分を含む）は `manifests/authentik/README.md` を参照する。

## 外部公開と ambient

- クラスタ外（ブラウザなど）からの通信を受けるアプリは、`istio-ingress` の共有 Gateway に HTTPRoute でぶら下げて公開する。手順は `manifests/istio-ingress/README.md` の「新しいアプリをぶら下げる」を参照する。
- アプリの Namespace は、ambient に参加させて動作に問題がない限り `istio.io/dataplane-mode: ambient` ラベルを付けて参加させる。参加させない場合は理由をアプリの README に書く。
- ambient に参加させると Pod 宛ての通信が TCP 15008（HBONE）に届くため、NetworkPolicy がある場合は 15008 を許可する（`manifests/kiali/` を参照する）。
- どちらも istio が入れる CRD や istio-cni / ztunnel を前提にするので、`apps.yaml` では `istio`（外から入るなら `istio-ingress` も）を一緒に宣言し、アプリに `dependsOn: istio` を付ける。

## 検証コマンド

変更後は次の 2 つが exit 0 になることを確認する。これ以外の検証手段は組み立てない。

```sh
# ルート（flux-system と apps.yaml に宣言した Flux Kustomization）と全アプリの kustomize が壊れていないこと
sh -ec 'for d in manifests manifests/*/; do kustomize build "$d" > /dev/null; done'

# HelmRelease が valuesFrom で読む authentik/values.yaml が chart に対して描画できること
helm template authentik authentik --repo https://charts.goauthentik.io --version 2026.8.3 -n authentik -f manifests/authentik/values.yaml > /dev/null
```

## 日報

日報の保存先ルートは `daily-reports/`（リポジトリ直下）とする。
