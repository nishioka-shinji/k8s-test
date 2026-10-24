# dependency-track

OWASP Dependency-Track 5.2.0 を公式 chart `dependency-track` 2.8.0（https://dependencytrack.github.io/helm-charts ）で入れ、SBOM を取り込んで脆弱性を見る。chart の quickstart（`values-quickstart.yaml`）を Flux の HelmRelease に置き換えたもの。
使うときは `manifests/flux-system/apps.yaml` に `istio` と `istio-ingress` と一緒に宣言し、`dependency-track` に `dependsOn: istio` を付ける。

## 構成

| ファイル | 内容 |
|---|---|
| `namespace.yaml` | Namespace `dependency-track`（ambient に参加する `istio.io/dataplane-mode: ambient` と、共有 Gateway に参加する `shared-gateway-access: "true"` ラベル付き） |
| `db-deployment.yaml` / `db-service.yaml` | PostgreSQL（`postgres:18-alpine`、DB / ユーザー / パスワードはすべて `dtrack`、永続化なし）と Service `postgres` |
| `dependency-track-helm.yaml` | HelmRepository `dependency-track` と HelmRelease `dependency-track`（chart `dependency-track`） |
| `httproute.yaml` | HTTPRoute `dependency-track`（`istio-ingress` の Gateway `ingress` で Host `dependency-track.localhost` の `/api` を `dependency-track-api-server:8080`、それ以外を `dependency-track-frontend:8080` へ向ける） |

Dependency-Track 5 は組み込み DB（H2）を廃止して PostgreSQL 必須になり、chart も DB を同梱しない。chart の quickstart と同じく、永続化なしの PostgreSQL を別に置く。Pod を作り直すとデータは消える。

HelmRelease の values は次のとおり。

- `database`: 上の PostgreSQL へ接続する
- `secretManagement.database.kek.value`: chart は KEK を生成しないため、quickstart と同じ公開の固定値を使う。テスト環境専用
- `fileStorage.local.size: 2Gi`: chart 既定は 10Gi。PVC は kind 既定の StorageClass で作られる
- `apiServer.initContainers`: postgres と同時に適用されるため、`pg_isready` が通るまで api-server の起動を待たせる
- `apiServer.web.resources`: chart 既定の memory 2Gi を quickstart と同じ 1Gi に下げる。イメージの JVM は `-XX:MaxRAMPercentage=80.0` なので、ヒープは limit に連動して下がる
- `timeout: 10m0s`: 初回は image pull と DB の migration で既定の 5m を超えることがある

`frontend.apiBaseUrl` は chart 既定の空のままにする。UI と API を Gateway で同じホストに出すので、UI は相対 URL（同一オリジン）で API を呼び、CORS の設定も port-forward のポートの指定も要らない。

## Gateway と ambient

UI と API は `istio-ingress` の共有 Gateway に HTTPRoute でぶら下げる。UI が呼ぶ API はすべて `/api` 配下（`/api/version`、`/api/v1`、`/api/v2`）で、それ以外（`/static/config.json` など）は frontend の nginx が返すので、`/api` だけを api-server に振る。chart の `httpRoute` も同じ振り分けの HTTPRoute を作れるが、kiali と同じく HTTPRoute を `kustomize build` で見える場所に置くため自前で書く。

Namespace は ambient に参加させる。PostgreSQL への接続（api-server の initContainer の `pg_isready` を含む）も ambient では ztunnel を経由する TCP になるだけで、initContainer の通信も istio-cni が Pod 起動前にリダイレクトを仕込むので通る。readinessProbe の `pg_isready` は Pod 内で完結する。
chart 2.8.0 は NetworkPolicy を作らず、このディレクトリにも置いていないので、HBONE（TCP 15008）を許可する NetworkPolicy は要らない。

## アクセス

istio-ingress の Service を port-forward する。

```sh
kubectl -n istio-ingress port-forward svc/ingress-istio 18080:80
```

ブラウザで `http://dependency-track.localhost:18080/` を開き、初期ユーザー `admin` / `admin` でログインする。初回ログイン時にパスワード変更を求められる。

## SBOM のアップロード

Administration → Access Management → Teams の `Automation` チームの API key を使う（`BOM_UPLOAD` と `PROJECT_CREATION_UPLOAD` 権限を持つ）。`autoCreate=true` でプロジェクトがなければ作る。

```sh
curl -X POST http://dependency-track.localhost:18080/api/v1/bom \
  -H "X-Api-Key: ${DT_API_KEY}" \
  -F autoCreate=true \
  -F projectName=example \
  -F projectVersion=1.0.0 \
  -F bom=@bom.json
```

## 生成

https://fluxcd.io/flux/use-cases/helm/

```
flux create source helm dependency-track \
  --url https://dependencytrack.github.io/helm-charts \
  --namespace dependency-track \
  --export >> manifests/dependency-track/dependency-track-helm.yaml
```

```
flux create helmrelease dependency-track --chart dependency-track \
  --source HelmRepository/dependency-track \
  --namespace dependency-track \
  --chart-version 2.8.0 \
  --export >> manifests/dependency-track/dependency-track-helm.yaml
```

生成後に上の values と `timeout` を足す。

## 確認

```sh
flux get helmreleases -n dependency-track
kubectl get pods,pvc -n dependency-track
kubectl get httproute -n dependency-track
# port-forward したまま別のターミナルで
curl -sS http://dependency-track.localhost:18080/api/version
```
