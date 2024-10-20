https://fluxcd.io/flux/use-cases/helm/

```
flux create source helm imgproxy --url https://helm.imgproxy.net/ --namespace imgproxy --export > imgproxy/imgproxy-helm.yaml
```

```
flux create helmrelease imgproxy --chart imgproxy \
  --source HelmRepository/imgproxy \
  --namespace imgproxy \
  --chart-version 3.19.0 \
  --export >> imgproxy/imgproxy-helm.yaml
```
