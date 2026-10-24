# kiali

Kiali 2.33.0 を operator なしの `kiali-server` chart で入れ、`manifests/istio/` の ambient メッシュをグラフで見る。公式の Helm 手順（https://kiali.io/docs/installation/installation-guide/install-with-helm/ ）を Flux の HelmRelease に置き換えたもの。
使うときは `manifests/flux-system/apps.yaml` に `istio` と `prometheus` と一緒に宣言し、`kiali` に `dependsOn: istio, prometheus` を付ける。外から入るときは `istio-ingress` も宣言する。グラフに通信を出すには `istio-demo` など ambient の Namespace も宣言する。

## 構成

| ファイル | 内容 |
|---|---|
| `namespace.yaml` | Namespace `kiali`（共有 Gateway に参加する `shared-gateway-access: "true"` ラベル付き） |
| `kiali-helm.yaml` | HelmRepository `kiali` と HelmRelease `kiali`（chart `kiali-server`） |
| `istio-monitor.yaml` | PodMonitor `envoy-stats-monitor` と ServiceMonitor `istio-component-monitor`（Istio のメトリクス収集） |
| `httproute.yaml` | HTTPRoute `kiali`（`istio-ingress` の Gateway `ingress` で Host `kiali.localhost` を `kiali:20001` へ向ける） |

HelmRelease の values は次のとおり。

- `auth.strategy: anonymous`: テスト環境なのでログインを省く
- `external_services.prometheus.url`: kube-prometheus-stack の Service `kube-prometheus-stack-prometheus.prometheus:9090`
- `external_services.grafana.enabled` / `external_services.tracing.enabled`: `false`。接続先を置いていないため、到達できない警告を出さない
- `istio_namespace: istio-system`

kiali Namespace は ambient に参加させない。Kiali は Prometheus と Kubernetes API を読むだけで、メッシュ内の通信を観測する側にいるため。

## バージョン

公式の互換表（https://kiali.io/docs/installation/installation-guide/prerequisites/ ）は Istio 1.30 までしか載っていないため、Istio 1.31.0 公開後に出た 2.32.0 以降を選び、その中の最新安定版 2.33.0 に固定している。Kiali の CI（`.github/workflows/test-istio-version.yml`）は既定で Istio の最新 minor を対象にする。
Istio を上げるときは互換表を確認し、表にない場合は同じ基準（Istio の minor 公開後に出た Kiali）で選ぶ。

## メトリクス収集

Kiali のグラフは Istio の標準メトリクス（`istio_requests_total` / `istio_tcp_*` など）を Prometheus から読む。ambient では次から出る。

| 収集元 | 対象 | 収集設定 |
|---|---|---|
| ztunnel | L4（TCP）メトリクス | PodMonitor `envoy-stats-monitor`（`istio-proxy` コンテナ、`prometheus.io/port` = 15020、`/stats/prometheus`） |
| waypoint / ingress gateway | L7（HTTP）メトリクス | 同上（Istio が自動生成する Deployment も `istio-proxy` コンテナと `prometheus.io` annotation を持つ） |
| istiod | コントロールプレーンのメトリクス | ServiceMonitor `istio-component-monitor`（`istio: pilot` の Service の `http-monitoring` ポート） |

収集設定は Istio 公式の `samples/addons/extras/prometheus-operator.yaml`（Istio 1.31.3）と同じもので、`namespaceSelector.any: true` によりどの Namespace に置いても全 Namespace の Pod / Service を拾う。

PodMonitor / ServiceMonitor を `manifests/kiali/` に置くのは、CRD の提供元と依存の向きのため。

- `manifests/prometheus/` には置けない。CRD（`monitoring.coreos.com`）は同じ Kustomization の HelmRelease が入れるので、適用時の dry-run で CRD がまだなく失敗する
- `manifests/istio/` に置くと、単独で宣言できる istio が prometheus に依存するようになる
- Kiali はもともと Prometheus を必要とし、`kiali` に `dependsOn: prometheus` を付けるので、CRD が揃ってから適用される。Kiali を使わないときは収集も要らない

kube-prometheus-stack は既定で `release: kube-prometheus-stack` ラベルの PodMonitor しか拾わないため、`manifests/prometheus/` の values に `podMonitorSelectorNilUsesHelmValues: false` を足している（ServiceMonitor 側の `serviceMonitorSelectorNilUsesHelmValues: false` と揃える）。

## 生成

https://fluxcd.io/flux/use-cases/helm/

```
flux create source helm kiali \
  --url https://kiali.org/helm-charts \
  --namespace kiali \
  --export >> manifests/kiali/kiali-helm.yaml
```

```
flux create helmrelease kiali --chart kiali-server \
  --source HelmRepository/kiali \
  --namespace kiali \
  --chart-version 2.33.0 \
  --export >> manifests/kiali/kiali-helm.yaml
```

生成後に上の values を足す。

## 確認

```sh
flux get helmreleases -n kiali
kubectl get pods -n kiali
kubectl get podmonitor,servicemonitor -n kiali
kubectl get httproute -n kiali
kubectl -n istio-ingress port-forward svc/ingress-istio 18080:80
# 別のターミナルで
curl -sS -o /dev/null -w '%{http_code}\n' http://kiali.localhost:18080/kiali/
```

Kiali の web root は chart の既定 `/kiali` なので、ブラウザでは `http://kiali.localhost:18080/kiali/` を開く。ログイン画面を経ずに Overview が出れば anonymous で入れている。
Prometheus に収集されているかは、Prometheus の Targets に `podMonitor/kiali/envoy-stats-monitor` と `serviceMonitor/kiali/istio-component-monitor` が出て、ztunnel と istiod が UP になっているかで見る。

```sh
kubectl -n prometheus port-forward svc/kube-prometheus-stack-prometheus 9090:9090
# 別のターミナルで http://localhost:9090/targets を開く
```

`istio-demo` を宣言して `curl` から `httpbin` へ何度か通信すると、Kiali の Traffic Graph で `istio-demo` Namespace に `curl` → `httpbin` の辺が出る。waypoint を置いていないので、ztunnel の L4（TCP）メトリクスだけで描かれる。確認が済んだら port-forward は Ctrl-C で止める。
