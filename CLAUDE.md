# glaucus

kind クラスタ向けの K8s マニフェスト置き場。マニフェストはすべて `manifests/` 配下に置き、手元の作業ツリーの `manifests/` をローカルレジストリ（kind-registry）へ OCI artifact として push し、Flux（flux-system）がそれを同期する。artifact のルートは `manifests/` になる。`manifests/kustomization.yaml` は `manifests/flux-system/` だけを束ね、各アプリ（authentik / mailpit / caddy-demo / unleash / unleash-demo / cert-manager / openfeature / openfeature-demo / prometheus / imgproxy-2 / istio / istio-ingress / istio-demo / kiali）は常時同期せず、検証したいアプリだけを `manifests/flux-system/apps.yaml` に Flux Kustomization として宣言して同期する（既定は空）。宣言の書き方と依存するアプリの組み合わせ（wait / dependsOn）は `manifests/flux-system/README.md` の「アプリを宣言するとき」を参照する。
クラスタは `kind/cluster.yaml`（control-plane 1 台 + worker 2 台）から作る。これは Flux の同期対象ではないので `manifests/` の外に置く。
クラスタ作成・push 手順とローカルレジストリの起動は `manifests/flux-system/README.md` を参照する。
各アプリは Flux の HelmRepository / HelmRelease か素の manifest で管理する。
`manifests/authentik/` の再構築手順（Secret 作成など手作業の部分を含む）は `manifests/authentik/README.md` を参照する。

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
