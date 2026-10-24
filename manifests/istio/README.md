# istio

Istio 1.31.3 を ambient モードで入れる。公式の Helm 手順（https://istio.io/latest/docs/ambient/install/helm/ ）を Flux の HelmRelease に置き換えたもの。
使うときは `manifests/flux-system/apps.yaml` に Flux Kustomization `istio` を宣言して同期する。

## 構成

| ファイル | 内容 |
|---|---|
| `kustomization.yaml` | Gateway API v1.6.0 の standard CRD（remote URL）と下の 2 ファイルを束ねる |
| `namespace.yaml` | Namespace `istio-system` |
| `istio-helm.yaml` | HelmRepository `istio` と HelmRelease `istio-base` → `istiod` → `istio-cni` → `ztunnel`（順序は `dependsOn`） |

istiod と istio-cni は `profile: ambient` を values に渡す。kind は公式の platform prerequisites に個別設定がないため、platform 系の値は渡していない。

## 生成

https://fluxcd.io/flux/use-cases/helm/

```
flux create source helm istio \
  --url https://blob.istio.io/istio-release/charts \
  --namespace istio-system \
  --export >> manifests/istio/istio-helm.yaml
```

```
flux create helmrelease istiod --chart istiod \
  --source HelmRepository/istio \
  --namespace istio-system \
  --chart-version 1.31.3 \
  --depends-on istio-base \
  --export >> manifests/istio/istio-helm.yaml
```

`istio-base`（chart `base`）、`istio-cni`（chart `cni`、`--depends-on istiod`）、`ztunnel`（chart `ztunnel`、`--depends-on istio-cni`）も同様に生成し、istiod と istio-cni に `values.profile: ambient` を足す。

## バージョンを上げるとき

- 4 つの HelmRelease の `version` を同じ値に揃える
- Gateway API の版は、その Istio リリースの ambient Helm 手順が指定するものに合わせる
- 旧リポジトリ https://istio-release.storage.googleapis.com/charts は 1.30 系までしかないため使わない

## 確認

```sh
flux get helmreleases -n istio-system
kubectl get pods -n istio-system
```

`istiod` / `istio-cni-node` / `ztunnel` が Running になる。メッシュ内通信の確認は `manifests/istio-demo/README.md`。
