# glaucus

kind クラスタ向けの K8s マニフェスト置き場。手元の作業ツリーをローカルレジストリ（kind-registry）へ OCI artifact として push し、Flux（flux-system）がそれを同期する。ルートの `kustomization.yaml` で束ねたディレクトリ（flux-system / authentik / mailpit / caddy-demo / unleash / unleash-demo）と、`flux-system/apps.yaml` で適用順序を付けたディレクトリ（cert-manager / openfeature / openfeature-demo / prometheus / imgproxy-2）をクラスタに反映する。
push 手順とローカルレジストリの起動は `flux-system/README.md` を参照する。
各アプリは Flux の HelmRepository / HelmRelease か素の manifest で管理する。
`authentik/` の再構築手順（Secret 作成など手作業の部分を含む）は `authentik/README.md` を参照する。

## 検証コマンド

変更後は次の 4 つが exit 0 になることを確認する。これ以外の検証手段は組み立てない。

```sh
# ルートの kustomize（authentik を含む）が壊れていないこと
kustomize build . > /dev/null

# authentik の kustomize（kubectl apply -k authentik で入れる単位）が壊れていないこと
kustomize build authentik > /dev/null

# caddy-demo の kustomize（kubectl apply -k caddy-demo で入れる単位）が壊れていないこと
kustomize build caddy-demo > /dev/null

# HelmRelease が valuesFrom で読む authentik/values.yaml が chart に対して描画できること
helm template authentik authentik --repo https://charts.goauthentik.io --version 2026.8.3 -n authentik -f authentik/values.yaml > /dev/null
```

## 日報

日報の保存先ルートは `daily-reports/`（リポジトリ直下）とする。
