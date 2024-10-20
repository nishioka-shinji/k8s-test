https://fluxcd.io/flux/get-started/

## マニフェスト作成
```
export GITHUB_TOKEN=<your-token>
export GITHUB_USER=<your-username>
```

```
flux bootstrap github \
  --owner=$GITHUB_USER \
  --repository=fleet-infra-kind \
  --branch=main \
  --path=./ \
  --personal
```

## GitRepository作成
```
flux create source git k8s-test \
  --url=https://github.com/nishioka-shinji/k8s-test.git \
  --branch=main \
  --interval=1m \
  --export > flux-system/git-repository.yaml
```

```
flux create kustomization k8s-test \
  --source=k8s-test \
  --path="./" \
  --prune=true \
  --wait=true \
  --interval=30m \
  --retry-interval=2m \
  --health-check-timeout=3m \
  --export >> flux-system/git-repository.yaml
```