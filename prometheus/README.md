https://fluxcd.io/flux/use-cases/helm/

```
flux create source helm prometheus-community \
  --url https://prometheus-community.github.io/helm-charts \
  --namespace prometheus \
  --export >> prometheus/prometheus-helm.yaml
```

```
flux create helmrelease kube-prometheus-stack --chart kube-prometheus-stack \
  --source HelmRepository/prometheus-community \
  --namespace prometheus \
  --chart-version 67.5.0 \
  --export >> prometheus/prometheus-helm.yaml
```
