# flux-system

kind クラスタの Flux（v2.9.6）は、手元の作業ツリーをローカルレジストリへ push した OCI artifact を同期する。
GitHub は同期元にしない。

| ファイル | 内容 |
|---|---|
| `gotk-components.yaml` | Flux 本体（`flux install --export` で生成） |
| `gotk-sync.yaml` | 同期元の OCIRepository と、ルート `kustomization.yaml` を適用する Kustomization |
| `apps.yaml` | 適用順序が必要なアプリ（CRD・webhook の提供元と利用側）を `dependsOn` で並べた Kustomization |
| `local-registry.sh` | ローカルレジストリ `kind-registry` の起動（冪等） |

## 1. ローカルレジストリを起動する

kind 公式手順（https://kind.sigs.k8s.io/docs/user/local-registry/ ）のステップ 1・4・5 を実行する。
`kind-registry`（registry:3）を `127.0.0.1:5001` で起動して kind ネットワークに接続し、kube-public に `local-registry-hosting` ConfigMap を置く。

```sh
./flux-system/local-registry.sh
```

source-controller は Pod 内から `kind-registry:5000` を直接読むため、containerd の hosts.toml（ステップ 2・3）は設定しない。

## 2. Flux をインストールする

```sh
kubectl apply --server-side -f flux-system/gotk-components.yaml
flux check
```

Flux のバージョンを上げるときは `gotk-components.yaml` を再生成する。

```sh
flux install --export \
  --components=source-controller,kustomize-controller,helm-controller,notification-controller \
  > flux-system/gotk-components.yaml
```

## 3. マニフェストを push する

リポジトリ直下で実行する。`.git` や `daily-reports/` など同期対象外のパスは `--ignore-paths` で除外する。

```sh
flux push artifact oci://localhost:5001/k8s-test:latest \
  --path=. \
  --source="$(git config --get remote.origin.url)" \
  --revision="$(git branch --show-current)@sha1:$(git rev-parse HEAD)" \
  --ignore-paths='.git/,.gitignore,.gitmodules,.gitattributes,.claude/,daily-reports/'
```

## 4. 同期を開始する

初回だけ同期設定を手で入れる。以降は OCIRepository が 1 分ごとに `latest` を確認し、push した内容が反映される。

```sh
kubectl apply -k flux-system
```

すぐ反映させたいときは reconcile する。

```sh
flux reconcile source oci flux-system
flux get kustomizations -A
```

## アプリを追加するとき

- 他のアプリが提供する CRD や webhook に依存しないものは、ルート `kustomization.yaml` の `resources` に足す
- 依存するものは `apps.yaml` に Kustomization を足し、提供元に `wait: true`、利用側に `dependsOn` を付ける。ルート `kustomization.yaml` には足さない
