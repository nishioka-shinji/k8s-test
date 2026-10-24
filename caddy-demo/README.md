# caddy-demo

Authentik の埋め込み outpost で forward auth（Proxy Provider の forward_single）を確認する Caddy アプリ。`flux-system/apps.yaml` の Flux Kustomization `caddy-demo` が同期する。

Authentik 側の設定（Proxy Provider / Application / outpost 割り当て）は `authentik/blueprint-caddy-demo.yaml` にあり、説明は `authentik/README.md` の「Caddy 動作確認アプリの blueprint」。

## 構成

| ファイル | 内容 |
|---|---|
| `namespace.yaml` | Namespace `caddy-demo` |
| `deployment.yaml` / `service.yaml` | Deployment / Service `caddy` |
| `Caddyfile` | configMapGenerator で ConfigMap `caddy-config-<hash>` になる。認証後は Authentik が付与した `X-Authentik-*` ヘッダを表示する |

## apply

Authentik の再構築手順（`authentik/README.md`）の後に入れる。

```sh
kubectl apply -k caddy-demo
kubectl -n caddy-demo get pods
```

authentik → caddy-demo の順を推奨する。逆順でも Caddy は Authentik の起動を待たずに立ち上がり、Authentik 起動後に forward auth が通るようになる。

## アクセス

```sh
kubectl -n authentik port-forward svc/authentik-server 9000:80
kubectl -n caddy-demo port-forward svc/caddy 9100:80
```

未認証で http://localhost:9100/ を開くと http://localhost:9000 のログインに転送され、ログイン後に戻る。

http://localhost:9100/hello は認証後に名前とメールアドレスで挨拶する HTML ページ。
