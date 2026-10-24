https://fluxcd.io/flux/use-cases/helm/

```
flux create source helm prometheus-community \
  --url https://prometheus-community.github.io/helm-charts \
  --namespace prometheus \
  --export >> manifests/prometheus/prometheus-helm.yaml
```

```
flux create helmrelease kube-prometheus-stack --chart kube-prometheus-stack \
  --source HelmRepository/prometheus-community \
  --namespace prometheus \
  --chart-version 67.5.0 \
  --export >> manifests/prometheus/prometheus-helm.yaml
```

## ambient

prometheus Namespace は `istio.io/dataplane-mode: ambient` で Istio ambient に参加させる。稼働中の Pod を可能な限りメッシュに入れ、ztunnel のメトリクスで通信を観測するため。
ambient では他 Pod からの通信が Pod IP の TCP 15008（HBONE）に届くため、Ingress を特定ポートに絞る NetworkPolicy があると遮断される。kube-prometheus-stack は現在の values では NetworkPolicy を作らないので、追加の許可は置いていない。chart の `networkPolicy.enabled` を有効にするときは 15008 も許可する（`manifests/kiali/networkpolicy.yaml` を参照）。
