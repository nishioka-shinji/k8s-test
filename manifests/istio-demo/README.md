# istio-demo

Istio ambient モードの動作確認アプリ。Namespace に `istio.io/dataplane-mode=ambient` を付け、`curl` から `httpbin` への通信が ztunnel を経由する（HBONE）ことを確かめる。
使うときは `manifests/flux-system/apps.yaml` に `istio` と一緒に宣言し、`istio-demo` に `dependsOn: istio` を付ける。

## 構成

| ファイル | 内容 |
|---|---|
| `namespace.yaml` | Namespace `istio-demo`（ambient ラベル付き） |
| `httpbin.yaml` | Deployment / Service `httpbin`（go-httpbin、Service は 8000 → 8080） |
| `curl.yaml` | Deployment `curl`（`sleep infinity` で常駐） |

`curl` と `httpbin` は互いに podAntiAffinity（`kubernetes.io/hostname`）を持ち、必ず別ノードに置かれる。送信側ノードの ztunnel から受信側ノードの ztunnel へ HBONE が張られることを確かめるためで、worker 2 台のクラスタ（`kind/cluster.yaml`）が前提になる。

## 確認

```sh
kubectl get pods -n istio-demo -o wide
kubectl -n istio-demo exec deploy/curl -- curl -sS -o /dev/null -w '%{http_code}\n' http://httpbin:8000/get
# 送信側（curl と同じノード）と受信側（httpbin と同じノード）の ztunnel Pod を見る
kubectl get pods -n istio-system -l app=ztunnel -o wide
kubectl -n istio-system logs <送信側ノードの ztunnel Pod> | grep istio-demo
kubectl -n istio-system logs <受信側ノードの ztunnel Pod> | grep istio-demo
```

送信側 ztunnel に `direction="outbound"`、受信側 ztunnel に `direction="inbound"` のアクセスログが出て、どちらにも `dst.addr=<httpbin の Pod IP>:15008`（HBONE のポート）と、送信元・宛先の `spiffe://cluster.local/ns/istio-demo/sa/default` が出ていれば、ノード間を ambient（HBONE）で通っている。
