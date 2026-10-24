# istio-demo

Istio ambient モードの動作確認アプリ。Namespace に `istio.io/dataplane-mode=ambient` を付け、`curl` から `httpbin` への通信が ztunnel を経由する（HBONE）ことを確かめる。
あわせて `manifests/istio-ingress/` の共有 Gateway に HTTPRoute をぶら下げ、クラスタの外から `httpbin` へメッシュ経由で入れることを確かめる。
使うときは `manifests/flux-system/apps.yaml` に `istio` と一緒に宣言し、`istio-demo` に `dependsOn: istio` を付ける。外から入る確認をするときは `istio-ingress` も宣言する。

## 構成

| ファイル | 内容 |
|---|---|
| `namespace.yaml` | Namespace `istio-demo`（ambient ラベルと、共有 Gateway に参加する `shared-gateway-access: "true"` ラベル付き） |
| `httpbin.yaml` | Deployment / Service `httpbin`（go-httpbin、Service は 8000 → 8080） |
| `curl.yaml` | Deployment `curl`（`sleep infinity` で常駐） |
| `httproute.yaml` | HTTPRoute `httpbin`（`istio-ingress` の Gateway `ingress` で Host `istio-demo.localhost` を `httpbin:8000` へ向ける） |

`curl` と `httpbin` は互いに podAntiAffinity（`kubernetes.io/hostname`）を持ち、必ず別ノードに置かれる。送信側ノードの ztunnel から受信側ノードの ztunnel へ HBONE が張られることを確かめるためで、worker 2 台のクラスタ（`kind/cluster.yaml`）が前提になる。

HTTPRoute は backend の `httpbin` と同じ Namespace に置くので ReferenceGrant は要らない。Gateway 側の構成は `manifests/istio-ingress/README.md` を参照する。

## 確認（メッシュ内）

```sh
kubectl get pods -n istio-demo -o wide
kubectl -n istio-demo exec deploy/curl -- curl -sS -o /dev/null -w '%{http_code}\n' http://httpbin:8000/get
# 送信側（curl と同じノード）と受信側（httpbin と同じノード）の ztunnel Pod を見る
kubectl get pods -n istio-system -l app=ztunnel -o wide
kubectl -n istio-system logs <送信側ノードの ztunnel Pod> | grep istio-demo
kubectl -n istio-system logs <受信側ノードの ztunnel Pod> | grep istio-demo
```

送信側 ztunnel に `direction="outbound"`、受信側 ztunnel に `direction="inbound"` のアクセスログが出て、どちらにも `dst.addr=<httpbin の Pod IP>:15008`（HBONE のポート）と、送信元・宛先の `spiffe://cluster.local/ns/istio-demo/sa/default` が出ていれば、ノード間を ambient（HBONE）で通っている。

## 確認（ingress gateway）

```sh
kubectl get gateway -n istio-ingress
kubectl get httproute -n istio-demo
kubectl -n istio-ingress port-forward svc/ingress-istio 18080:80
# 別のターミナルで
curl -sS -o /dev/null -w '%{http_code}\n' http://istio-demo.localhost:18080/get
```

`*.localhost` は `/etc/hosts` に書かなくても 127.0.0.1 に解決されるので、ホスト名を付けたまま port-forward に届く。
Gateway が `PROGRAMMED=True`、HTTPRoute の `status.parents[].conditions` が `Accepted=True` / `ResolvedRefs=True` になっていて、curl が 200 を返せば外から入れている。HTTPRoute は `hostnames` で振り分けるので、`http://localhost:18080/get` のように Host が違うと 404 になる。確認が済んだら port-forward は Ctrl-C で止める。

gateway Pod には Istio が `istio.io/dataplane-mode=none` を付け、gateway 自身の Envoy が HBONE で `httpbin` 側ノードの ztunnel へ直接つなぐ。そのため見るのは `httpbin` と同じノードの ztunnel で、gateway Pod と同じノードの ztunnel にはこの通信のログは出ない。

```sh
kubectl get pods -n istio-demo -o wide
kubectl get pods -n istio-system -l app=ztunnel -o wide
kubectl -n istio-system logs <httpbin と同じノードの ztunnel Pod> | grep istio-ingress
```

`direction="inbound"` のアクセスログに `src.identity="spiffe://cluster.local/ns/istio-ingress/sa/ingress-istio"` と `dst.addr=<httpbin の Pod IP>:15008` が出ていれば、gateway から `httpbin` へ HBONE で届いている。ログは接続が閉じたときに出るので、curl の直後に出ていなければ数秒待つ。
