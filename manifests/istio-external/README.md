# istio-external

ambient の Pod がクラスタ外へ出す通信の宛先を ServiceEntry で宣言し、Kiali のグラフと ztunnel のメトリクス（`istio_tcp_*` の `destination_service`）で名前付きで見えるようにする。
表示のためだけに置くので、egress の制限（`outboundTrafficPolicy: REGISTRY_ONLY` など）や egress 用の waypoint は置かない。宣言していない宛先もこれまでどおり通る。
使うときは `manifests/flux-system/apps.yaml` に `istio` と一緒に宣言し、`istio-external` に `dependsOn: istio` を付ける。

## 構成

| ファイル | 内容 |
|---|---|
| `namespace.yaml` | Namespace `istio-external`（Pod は置かないので ambient のラベルは付けない） |
| `serviceentry.yaml` | 外部宛先の ServiceEntry（1 ホスト 1 つ） |

名前は Istio の設定だけを置く既存の `istio-ingress` に合わせ、`istio-` に用途を続けた `istio-external` にする。`istio-egress` にしないのは、egress gateway のように通信を絞る構成と取り違えないため。
ServiceEntry を置く Namespace は、ディレクトリ名と同じ専用の `istio-external` にする。メトリクスの `destination_service_namespace` / `destination_workload_namespace` がこの名前になり、外部宛先だと一目でわかる。使い終わって `apps.yaml` から消せば、Namespace ごと prune される。

ambient では ServiceEntry の `exportTo` が効かない。istiod が ztunnel に配る情報（`pilot/pkg/serviceregistry/ambient/`）は `exportTo` を参照しないため、どの Namespace に置いてもメッシュ全体の Pod から見える。`exportTo: ["."]` は ingress gateway などの Envoy に不要な cluster を配らないために付けている。

## 対象ホスト

| ServiceEntry | ホスト | ポート | 使う Workload | 用途 |
|---|---|---|---|---|
| `kind-registry` | `kind-registry` | 5000（HTTP） | flux-system / source-controller | OCIRepository `flux-system`（`oci://kind-registry:5000/k8s-test`） |
| `blob-istio-io` | `blob.istio.io` | 443（TLS） | flux-system / source-controller | HelmRepository `istio`（index.yaml と chart） |
| `istio-release-r2-istio-io` | `istio-release.r2.istio.io` | 443（TLS） | flux-system / source-controller | 上の `blob.istio.io` のリダイレクト先（index.yaml が 301 で転送される） |
| `kiali-org` | `kiali.org` | 443（TLS） | flux-system / source-controller | HelmRepository `kiali`（index.yaml と chart） |
| `prometheus-community-github-io` | `prometheus-community.github.io` | 443（TLS） | flux-system / source-controller | HelmRepository `prometheus-community`（index.yaml） |
| `github-com` | `github.com` | 443（TLS） | flux-system / source-controller、kustomize-controller | kube-prometheus-stack の chart（index.yaml の URL が GitHub Releases）、`manifests/istio/` の Gateway API CRD（remote URL） |
| `release-assets-githubusercontent-com` | `release-assets.githubusercontent.com` | 443（TLS） | flux-system / source-controller、kustomize-controller | 上の GitHub Releases のリダイレクト先 |
| `grafana-com` | `grafana.com` | 443（TLS） | prometheus / kube-prometheus-stack-grafana | Grafana の更新確認（`check_for_updates`） |

IP では宛先を分けられない。`kiali.org` と `prometheus-community.github.io` は同じ GitHub Pages の IP（185.199.108-111.153）を返し、`blob.istio.io` は Cloudflare の IP を返すため、ホスト名で宣言する。

kind のノード IP（172.18.0.x）宛ての Prometheus のスクレイプ（etcd、kube-proxy、kube-controller-manager、kube-scheduler）はクラスタの構成要素なので対象外にしている。

## 名前付きで出る仕組み

ServiceEntry に `addresses` を書かず、`resolution: DNS` にする。Istio 1.31 では次が既定で有効なので、`manifests/istio/` の values は変えていない。

- istiod の `PILOT_ENABLE_IP_AUTOALLOCATE`（既定 `true`）が、`addresses` のない ServiceEntry のホストに 240.240.0.0/16 の VIP を割り当てる
- istio-cni の `AMBIENT_DNS_CAPTURE`（既定 `true`）と ztunnel の DNS プロキシにより、ambient の Pod の DNS 問い合わせに ztunnel が VIP で答える

Pod は VIP へ接続し、ztunnel が VIP から ServiceEntry を特定してメトリクスの `destination_service` にホスト名を、`destination_workload` に ServiceEntry 名を入れる。実際の接続先は ztunnel がホスト名を引き直して決め、TLS は Pod と外部の間でそのまま張られる。
`addresses` を書かない ServiceEntry や `resolution: NONE` では、Pod は実 IP へ接続するので、これまでどおり `unknown` になる。

`kind-registry` のような短いホスト名も `hosts` に書ける（`resolution: DNS` で `endpoints` がない場合の FQDN 検査は単一ラベルを通す）。Pod が `kind-registry.flux-system.svc.cluster.local` などの search domain 付きで問い合わせても、ztunnel の DNS プロキシが search domain を外して照合し、CNAME と VIP を返す。ztunnel 自身は CoreDNS 経由で `kind-registry` を引き、kind の Docker ネットワーク上の IP へ接続する。

参考:

- https://istio.io/latest/docs/ops/configuration/traffic-management/dns-proxy/
- https://istio.io/latest/docs/reference/config/networking/service-entry/

## 宛先を追加するとき

1. ztunnel のアクセスログで、`dst.service` がなく `dst.addr` がクラスタ外の IP になっている接続を探す

   ```sh
   kubectl logs -n istio-system -l app=ztunnel --tail=-1 \
     | grep 'direction="outbound"' | grep -v 'dst.service=' \
     | grep -oE 'src.workload="[^"]*" src.namespace="[^"]*" .*dst.addr=[^ ]*' | sort | uniq -c
   ```

2. IP からホスト名を特定する。HelmRepository / OCIRepository の URL、chart の values、index.yaml の chart URL とリダイレクト先を `dig +short <ホスト>` の結果と照合する
3. `serviceentry.yaml` に ServiceEntry を足す。名前はホスト名の `.` を `-` にしたもの、ポートは実際に使うものをすべて書く（宣言していないポートで VIP に接続すると ztunnel が転送できない）。HTTPS は `protocol: TLS`、平文の HTTP は `protocol: HTTP` にする
4. 上の表に行を足す

ワイルドカードのホスト（`*.example.com`）は `resolution: DNS` では VIP が割り当てられず、名前付きにならない。

## 確認

```sh
flux get kustomizations istio-external
kubectl get serviceentry -n istio-external -o custom-columns=NAME:.metadata.name,HOSTS:.spec.hosts,ADDRESSES:.status.addresses
```

`ADDRESSES` に 240.240.x.x の VIP が入っていれば自動割り当てが効いている。ambient の Pod からは VIP で解決される。

```sh
kubectl -n istio-demo exec deploy/curl -- curl -sS -o /dev/null -w '%{remote_ip} %{http_code}\n' https://github.com/
```

`remote_ip` が 240.240.x.x になっていれば、DNS キャプチャ経由で ServiceEntry に向いている。Flux の取得が続いているかは `flux get sources all -A` の READY で見る。
メトリクスは Prometheus で次を実行し、`destination_service` に上の表のホストが出れば名前付きになっている。

```promql
sum by (source_workload_namespace, source_workload, destination_service) (
  increase(istio_tcp_connections_opened_total{reporter="source", destination_service_namespace="istio-external"}[10m])
)
```

Kiali の Traffic Graph で `flux-system` / `prometheus` を選ぶと、`source-controller` などから ServiceEntry のノード（ホスト名）へ辺が出る。
