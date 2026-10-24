# istio-ingress

クラスタの外からの入口になる共有 Gateway（Gateway API、`gatewayClassName: istio`）を置く。
各アプリは Gateway を持たず、自分の Namespace に HTTPRoute を置いて `parentRefs` でこの Gateway を指すだけにする。
使うときは `manifests/flux-system/apps.yaml` に `istio` と一緒に宣言し、`istio-ingress` に `dependsOn: istio` を付ける。

## 構成

| ファイル | 内容 |
|---|---|
| `namespace.yaml` | Namespace `istio-ingress` |
| `gateway.yaml` | Gateway `ingress`（HTTP 80、ラベル `shared-gateway-access: "true"` の Namespace の HTTPRoute を受け付ける） |

Istio は Gateway から Deployment / Service `ingress-istio`（ServiceAccount も同名）を自動生成する。kind には LoadBalancer がないため、annotation `networking.istio.io/service-type: ClusterIP` で Service を ClusterIP にし、`kubectl port-forward` で入る。

`allowedRoutes` は `from: All` ではなく `from: Selector` にしている。`All` だとどの Namespace からでも共有の listener にルートを足せてしまうため、ラベルを付けた Namespace だけが参加できるようにし、どのアプリが入口を使っているかを Namespace のマニフェストで読めるようにする。

## 新しいアプリをぶら下げる

1. アプリの Namespace に `shared-gateway-access: "true"` ラベルを付ける
2. アプリの Namespace に HTTPRoute を置き、`parentRefs` を `name: ingress` / `namespace: istio-ingress` にする。backend の Service は HTTPRoute と同じ Namespace に置けば ReferenceGrant は要らない
3. HTTPRoute の `hostnames` に `<アプリ名>.localhost` を指定し、ホスト名でルートを分ける。`*.localhost` は `/etc/hosts` に書かなくても 127.0.0.1 に解決されるので、port-forward したまま `http://<アプリ名>.localhost:18080/` で入れる

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: <アプリ名>
  namespace: <アプリの Namespace>
spec:
  parentRefs:
  - name: ingress
    namespace: istio-ingress
  hostnames:
  - <アプリ名>.localhost
  rules:
  - backendRefs:
    - name: <Service 名>
      port: <Service のポート>
```

## 確認

```sh
kubectl get gateway -n istio-ingress
kubectl get httproute -A
kubectl -n istio-ingress port-forward svc/ingress-istio 18080:80
# 別のターミナルで
curl -sS -o /dev/null -w '%{http_code}\n' http://<アプリ名>.localhost:18080/<パス>
```

Gateway が `PROGRAMMED=True`、HTTPRoute の `status.parents[].conditions` が `Accepted=True` / `ResolvedRefs=True` になっていれば、ルートが Gateway に載っている。確認が済んだら port-forward は Ctrl-C で止める。
