# istio-demo

Istio ambient モードの動作確認アプリ。Namespace に `istio.io/dataplane-mode=ambient` を付け、`curl` から `httpbin` への通信が ztunnel を経由する（HBONE）ことを確かめる。
使うときは `manifests/flux-system/apps.yaml` に `istio` と一緒に宣言し、`istio-demo` に `dependsOn: istio` を付ける。

## 構成

| ファイル | 内容 |
|---|---|
| `namespace.yaml` | Namespace `istio-demo`（ambient ラベル付き） |
| `httpbin.yaml` | Deployment / Service `httpbin`（go-httpbin、Service は 8000 → 8080） |
| `curl.yaml` | Deployment `curl`（`sleep infinity` で常駐） |

## 確認

```sh
kubectl -n istio-demo exec deploy/curl -- curl -sS http://httpbin:8000/get
kubectl -n istio-system logs ds/ztunnel | grep istio-demo
```

ztunnel のアクセスログに `dst.addr=<httpbin の Pod IP>:15008`（HBONE のポート）と、送信元・宛先の `spiffe://cluster.local/ns/istio-demo/sa/default` が出ていれば ambient 経由。
