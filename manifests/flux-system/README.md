# flux-system

kind クラスタの Flux（v2.9.6）は、手元の作業ツリーをローカルレジストリへ push した OCI artifact を同期する。
GitHub は同期元にしない。

| ファイル | 内容 |
|---|---|
| `gotk-components.yaml` | Flux 本体（`flux install --export` で生成） |
| `gotk-sync.yaml` | 同期元の OCIRepository と、`manifests/kustomization.yaml` を適用する Kustomization |
| `apps.yaml` | 同期するアプリの Kustomization。検証したいアプリだけを宣言する（既定は空） |
| `local-registry.sh` | ローカルレジストリ `kind-registry` の起動（冪等） |

## 1. ローカルレジストリを起動する

kind 公式手順（https://kind.sigs.k8s.io/docs/user/local-registry/ ）のステップ 1・4・5 を実行する。
`kind-registry`（registry:3）を `127.0.0.1:5001` で起動して kind ネットワークに接続し、kube-public に `local-registry-hosting` ConfigMap を置く。

```sh
./manifests/flux-system/local-registry.sh
```

source-controller は Pod 内から `kind-registry:5000` を直接読むため、containerd の hosts.toml（ステップ 2・3）は設定しない。

## 2. Flux をインストールする

```sh
kubectl apply --server-side -f manifests/flux-system/gotk-components.yaml
flux check
```

Flux のバージョンを上げるときは `gotk-components.yaml` を再生成する。

```sh
flux install --export \
  --components=source-controller,kustomize-controller,helm-controller,notification-controller \
  > manifests/flux-system/gotk-components.yaml
```

## 3. マニフェストを push する

リポジトリ直下で実行する。`manifests/` だけを push するので、`.git` や `daily-reports/` は対象外になる。

```sh
flux push artifact oci://localhost:5001/k8s-test:latest \
  --path=./manifests \
  --source="$(git config --get remote.origin.url)" \
  --revision="$(git branch --show-current)@sha1:$(git rev-parse HEAD)"
```

## 4. 同期を開始する

初回だけ同期設定を手で入れる。以降は OCIRepository が 1 分ごとに `latest` を確認し、push した内容が反映される。

```sh
kubectl apply -k manifests/flux-system
```

すぐ反映させたいときは reconcile する。

```sh
flux reconcile source oci flux-system
flux get kustomizations -A
```

## アプリを宣言するとき

テスト環境なので全アプリは同期しない。検証したいアプリだけを `apps.yaml` に Kustomization として宣言し、push する。使い終わったら消す（`prune: true` によりクラスタからも消える）。

```yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: mailpit
  namespace: flux-system
spec:
  interval: 10m0s
  path: ./mailpit
  prune: true
  sourceRef:
    kind: OCIRepository
    name: flux-system
```

- `manifests/kustomization.yaml` には足さない
- 他のアプリが提供する CRD や webhook に依存するものは、提供元も一緒に宣言し、提供元に `wait: true`（と `timeout`）、利用側に `dependsOn` を付ける。実行時に通信するだけの依存（SMTP、forward auth、API 呼び出しなど）には付けない

依存があるアプリの組み合わせは次のとおり。

| 使うアプリ | 一緒に宣言するもの | `wait: true` を付ける | `dependsOn` を付ける |
|---|---|---|---|
| openfeature | cert-manager | cert-manager（timeout 5m0s） | openfeature → cert-manager |
| openfeature-demo | cert-manager、openfeature | cert-manager、openfeature（timeout 5m0s） | openfeature → cert-manager、openfeature-demo → openfeature |
| imgproxy-2 | prometheus | prometheus（timeout 10m0s） | imgproxy-2 → prometheus |
| istio-demo | istio | istio（timeout 10m0s） | istio-demo → istio |

authentik / mailpit / caddy-demo / unleash / unleash-demo は CRD・webhook の依存がなく、単独で宣言できる。
istio は単独で宣言できるが、Gateway API と Istio の CRD を提供し 4 つの HelmRelease の完了を待たせるため `wait: true`（timeout 10m0s）を付ける。
istio-demo は CRD を使わないが、istio-cni と ztunnel が揃ってから Pod を起動して ambient 参加を確認するため `dependsOn` を付ける。
