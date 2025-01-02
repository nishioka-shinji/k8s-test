https://fluxcd.io/flux/use-cases/helm/

```
flux create source helm prometheus-community \
  --url https://prometheus-community.github.io/helm-charts \
  --namespace prometheus \
  --export >> prometheus/prometheus-helm.yaml
```

```
flux create helmrelease prometheus --chart prometheus \
  --source HelmRepository/prometheus \
  --namespace prometheus \
  --chart-version 26.0.1 \
  --export >> prometheus/prometheus-helm.yaml
```
