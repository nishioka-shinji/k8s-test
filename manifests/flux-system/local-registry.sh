#!/bin/sh
# kind 公式手順（https://kind.sigs.k8s.io/docs/user/local-registry/）のステップ 1・4・5 を冪等に実行する。
# source-controller は Pod 内から kind-registry:5000 を直接読むので、containerd の hosts.toml（ステップ 2・3）は設定しない。
set -o errexit

reg_name='kind-registry'
reg_port='5001'

# 1. レジストリコンテナを起動する
case "$(docker inspect -f '{{.State.Running}}' "${reg_name}" 2>/dev/null || true)" in
  true) ;;
  false) docker start "${reg_name}" ;;
  *) docker run -d --restart=always -p "127.0.0.1:${reg_port}:5000" --network bridge --name "${reg_name}" registry:3 ;;
esac

# 4. kind ネットワークに接続する
if [ "$(docker inspect -f='{{json .NetworkSettings.Networks.kind}}' "${reg_name}")" = 'null' ]; then
  docker network connect "kind" "${reg_name}"
fi

# 5. ローカルレジストリの存在をクラスタに知らせる
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:${reg_port}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF
