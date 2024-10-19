https://fluxcd.io/flux/get-started/

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
