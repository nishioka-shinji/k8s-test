https://docs.goauthentik.io/install-config/install/kubernetes/

Flux の HelmRelease で管理する。`flux-system/apps.yaml` の Flux Kustomization `authentik` が `authentik/` を同期する。

chart: goauthentik/authentik `2026.8.3`

手作業は Secret `authentik-credentials` の作成だけ。akadmin（bootstrap）、Google ソース、Caddy 動作確認アプリ（`caddy-demo/`）の Authentik 側設定、パスワードログインの MFA（メール OTP）必須化はすべてマニフェストと blueprint から作られる。

## 構成

| ファイル | 内容 |
|---|---|
| `namespace.yaml` | Namespace `authentik` |
| `authentik-helm.yaml` | HelmRepository `goauthentik`、HelmRelease `authentik`（values は `valuesFrom` で ConfigMap から読む） |
| `values.yaml` | chart の values。kustomize の configMapGenerator で ConfigMap `authentik-values-<hash>` になる。グローバルのメール設定（`authentik.email`）は Mailpit（`mailpit/`）に向けている |
| `blueprint-google.yaml` | blueprint。Google OAuth ソース `google`、property mapping `google-username-from-email`、`default-authentication-identification` ステージへのソース追加 |
| `blueprint-caddy-demo.yaml` | blueprint。`caddy-demo/` の Caddy 動作確認アプリ向けの Proxy Provider / Application / outpost 割り当て（後述） |
| `blueprint-mfa.yaml` | blueprint。パスワードログインの MFA（メール OTP）必須化と、メール OTP の登録用 flow / stage（後述） |

blueprint の ConfigMap は `values.yaml` の `blueprints.configMaps` で worker にマウントされる。ConfigMap と HelmRelease は同じ kustomize で同時に apply され、helm-controller が install するのはその後なので、ConfigMap 不在で worker が起動しない問題は起きない。

blueprint を追加した apply では、rollout 中に新しい ConfigMap をマウントしていない旧 worker が適用タスクを拾い、その blueprint が `error`（No such file or directory）になることがある。その場合は worker を再起動すると再適用される（`kubectl -n authentik rollout restart deploy/authentik-worker`）。

## Secret

Secret はリポジトリに置かず手で作る。HelmRelease より先に作っておく（後から作った場合は Pod が Secret 待ちになり、作成後に起動する）。

```sh
kubectl apply -f authentik/namespace.yaml
printf 'Google Client ID: ' && read -r GOOGLE_CLIENT_ID
printf 'Google Client Secret: ' && read -rs GOOGLE_CLIENT_SECRET && echo
printf 'akadmin password: ' && read -rs AKADMIN_PASSWORD && echo
kubectl -n authentik create secret generic authentik-credentials \
  --from-literal=secret-key="$(openssl rand -base64 60 | tr -d '\n')" \
  --from-literal=password="$(openssl rand -base64 36 | tr -d '\n')" \
  --from-literal=postgres-password="$(openssl rand -base64 36 | tr -d '\n')" \
  --from-literal=bootstrap-password="$AKADMIN_PASSWORD" \
  --from-literal=bootstrap-email='akadmin@example.com' \
  --from-literal=google-client-id="$GOOGLE_CLIENT_ID" \
  --from-literal=google-client-secret="$GOOGLE_CLIENT_SECRET"
unset GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET AKADMIN_PASSWORD
```

| key | 注入先 | 用途 |
|---|---|---|
| secret-key | AUTHENTIK_SECRET_KEY | 初回インストール後は変更しない |
| password | AUTHENTIK_POSTGRESQL__PASSWORD、PostgreSQL | PostgreSQL の authentik ユーザー |
| postgres-password | PostgreSQL | PostgreSQL の postgres 管理ユーザー |
| bootstrap-password | AUTHENTIK_BOOTSTRAP_PASSWORD | akadmin のパスワード |
| bootstrap-email | AUTHENTIK_BOOTSTRAP_EMAIL | akadmin のメールアドレス |
| google-client-id | GOOGLE_OAUTH_CLIENT_ID | Google ソースの Client ID（blueprint の `!Env`） |
| google-client-secret | GOOGLE_OAUTH_CLIENT_SECRET | Google ソースの Client Secret（blueprint の `!Env`） |

bootstrap-password / bootstrap-email は DB の初回起動時（Setup 未完了時）だけ使われ、akadmin 作成と同時に Setup 完了になる。そのため初期セットアップ画面（`/setup`）は出ず、`/` はログイン画面に転送される。後から Secret を変えても akadmin のパスワードは変わらない。

Google の Client ID / Secret を変えたときは Secret を更新して worker を再起動し（`kubectl -n authentik rollout restart deploy/authentik-worker`）、Customization > Blueprints で `google-source` を再適用する。blueprint はファイルが変わったときにしか自動適用されないため。

## 再構築手順（kind）

### 1. kind クラスタ作成

```sh
kind create cluster
```

### 2. Flux controller 導入

```sh
kubectl apply -f flux-system/gotk-components.yaml
kubectl -n flux-system wait --for=condition=Available deploy --all --timeout=300s
```

### 3. Secret 作成

上記「Secret」のコマンドを実行する。

### 4. apply

どちらか一方で入れる。

#### A. Flux（ローカルレジストリへ push して同期する）

手順は `flux-system/README.md`。`flux-system/apps.yaml` の Flux Kustomization 経由で authentik / mailpit / caddy-demo などがすべて同期される。

#### B. kubectl apply -k（マージ前のブランチを試す）

GitHub 同期はせず、ローカルの `authentik/`、`mailpit/`、`caddy-demo/` だけを入れる。helm-controller / source-controller が HelmRelease を処理する。

```sh
kubectl apply -k authentik
kubectl apply -k mailpit
kubectl apply -k caddy-demo
```

authentik → caddy-demo の順を推奨する。逆順でも Caddy は Authentik の起動を待たずに立ち上がり、Authentik 起動後に forward auth が通るようになる。

### 5. 完了確認

```sh
kubectl -n authentik wait helmrelease/authentik --for=condition=Ready --timeout=15m
kubectl -n authentik get pods
kubectl -n mailpit get pods
kubectl -n caddy-demo get pods
```

worker が起動すると blueprint が適用され、数十秒で Google ソースと Application `caddy-demo` ができる（Customization > Blueprints で状態を確認できる）。

## アクセス

Ingress は使わず port-forward でアクセスする。

```sh
kubectl -n authentik port-forward svc/authentik-server 9000:80
kubectl -n caddy-demo port-forward svc/caddy 9100:80
kubectl -n mailpit port-forward svc/mailpit 8025:8025
```

http://localhost:9000/ から akadmin（bootstrap-password）か Google でログインする。

## Google ソース

Google Cloud Console の OAuth クライアントで、承認済みのリダイレクト URI に次を登録しておく。

```
http://localhost:9000/source/oauth/callback/google/
```

`blueprint-google.yaml` が次を作る。

- OAuth ソース `google`（Google、認証フロー `default-source-authentication`、登録フロー `default-source-enrollment`）
- property mapping `google-username-from-email`（username を email にする）をソースの user property mapping に設定
- ステージ `default-authentication-identification` の sources に `google` を設定（ログイン画面に Google ボタンが出る）

## Caddy 動作確認アプリの blueprint

Caddy アプリ本体（Deployment / Service / Caddyfile）は `caddy-demo/` にあり、説明は `caddy-demo/README.md`。ここには Authentik 側の設定だけを置く。

`blueprint-caddy-demo.yaml` は configMapGenerator で ConfigMap `authentik-blueprint-caddy-demo`（authentik namespace、suffix なし）になり、次を作る。

- Proxy Provider `caddy-demo`（mode `forward_single`、external_host `http://localhost:9100`）
- Application `caddy-demo`。ポリシーを付けていないので、Google ソースで入った external ユーザーもアクセスできる
- 埋め込み outpost（`authentik Embedded Outpost`）への provider `caddy-demo` の割り当てと、`authentik_host`（`http://localhost:9000`）の設定

blueprint は埋め込み outpost の `providers` を一覧ごと上書きする。UI で他の provider を埋め込み outpost に割り当てても、blueprint の再適用で外れるので、追加する場合は blueprint の `providers` に書き足す。

## MFA（二段階認証）

`blueprint-mfa.yaml` は configMapGenerator で ConfigMap `authentik-blueprint-mfa`（suffix なし）になり、パスワードログインに MFA を必須にする。

- 対象はパスワードログイン（認証フロー `default-authentication-flow`）のユーザー全員で、akadmin も含む。Google ログイン（`default-source-authentication`）は対象外
- 使える方式はメール OTP だけ。コードは `values.yaml` の `authentik.email` に設定した SMTP（テスト用の Mailpit）から送られる
- MFA 未登録のユーザーは、パスワード入力後にメール OTP の登録を求められ、登録するまでログインできない。ユーザーにメールアドレスがあればそこへ、なければ入力したアドレスへコードが送られ、入力すると登録される。Google 経由で作られる external ユーザーはユーザーポータルに入れないため、登録はこのログイン時に行う
- 以前に登録した TOTP / WebAuthn デバイスは DB に残るが、validation では使われない

blueprint は次を作る / 上書きする。

- flow `default-authenticator-email-setup`（designation `stage_configuration`）と、それに紐づく Email Authenticator ステージ `default-authenticator-email-setup`（`use_global_settings: true`）。authentik 2026.8 の default blueprint にはメール OTP の登録用 flow がないため、この blueprint で作る
- default blueprint が作るステージ `default-authentication-mfa-validation` の `not_configured_action`（`configure`）、`device_classes`（`email`）、`configuration_stages`（`default-authenticator-email-setup`）。default blueprint はこのステージを name だけで定義しているため、worker 再起動などで default blueprint が再適用されても上書きした設定は戻らない

### メールの確認（Mailpit）

`mailpit/` の Mailpit（namespace `mailpit`）が認証・TLS なしで SMTP（1025）を受け、届いたメールを Web UI（8025）で見られる。宛先のドメインに関係なくすべて Mailpit に溜まり、外部には送られない。

```sh
kubectl -n mailpit port-forward svc/mailpit 8025:8025
```

http://localhost:8025/ を開き、ログイン時に送られたコードを確認して入力する。Mailpit はメールを Pod 内にしか持たないので、Pod が再起動すると消える。

### MFA デバイスを失くした場合

管理者がそのユーザーの MFA デバイスを削除する。削除後の次回ログインで再登録を求められる。

- 管理画面: Directory > Users でユーザーを開き、MFA Authenticators タブでデバイスを削除する
- akadmin 自身がデバイスを失くして管理画面に入れない場合は ak shell で削除する

```sh
kubectl -n authentik exec -it deploy/authentik-worker -- ak shell -c '
from authentik.core.models import User
from authentik.stages.authenticator_email.models import EmailDevice
user = User.objects.get(username="akadmin")
print(EmailDevice.objects.filter(user=user).delete())
'
```
