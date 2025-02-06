## Set-up Talos OS
 
## Set up CoreDNS
```shell
    helm repo add coredns https://coredns.github.io/helm
```
```shell
    helm --namespace=kube-system install coredns coredns/coredns --values coredns/values.yaml
```

## Set-up Cilium CNI
1. Add repo
```shell

```
2. Install
```shell
    helm install \
        cilium \
        cilium/cilium \
        --version 1.16.6 \
        --namespace kube-system \
        --values cilium/values.yaml
```

## Instal Traefik
1. Add repo
```shell
    
```
2. Install with values
```shell
  helm install -n traefik --create-namespace traefik traefik/traefik -f /home/vehkiya/IdeaProjects/homelab-k8s/k8s/traefik/traefik-config.yaml
```

## Install Cert Manager
1. Add repo
```shell
    helm repo add jetstack https://charts.jetstack.io --force-update
```
2. Install cert-manager
```shell
    helm install \
      cert-manager jetstack/cert-manager \
      --namespace cert-manager \
      --create-namespace \
      --version v1.16.3 \
      --values cert-manager/values.yaml
#      --set crds.enabled=true \
#      --set config.enableGatewayAPI=true \
#      --set dns01RecursiveNameservers=8.8.8.8:53,1.1.1.1:53
```
3. Provision Cloudflare API Token secret
```shell
    kubectl apply -f cert-manager/00-cloudflare-token.yaml
```
4. Create cluster issuer
```shell
    kubectl apply -f cert-manager/01-acme-issuer-cf-solver.yaml
```
5. Create certificate config
```shell
    kubectl apply -f cert-manager/02-certificate-config.yaml
```

# Configuration Storage
## Synology CSI Driver
https://github.com/SynologyOpenSource/synology-csi

## Talos Synology CSI Driver
https://github.com/zebernst/synology-csi-talos

In deploy/kubernetes/v1.20/node.yaml add for `csi-plugin `
```yaml
            - '--chroot-dir=/host'
            - '--iscsiadm-path=/usr/local/sbin/iscsiadm'
```
Install
```shell
  ./scripts/deploy.sh build && ./scripts/deploy.sh install --basic
```
Install StorageClass

# Dashboard
1. Add repo
```shell
    helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
```
2. Install 
```shell
helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
  --create-namespace \
  --namespace kubernetes-dashboard \
  --set app.ingress.issuer.scope=cluster
```
3. Provision dashboard credentials
```shell
  kubectl apply -f kubernetes-dashboard/dashboard-data.yaml
```
4. Generate token for your user
```shell
  kubectl -n kubernetes-dashboard create token vehkiya
```
5. FW dashboard
```shell
  kubectl -n kubernetes-dashboard port-forward svc/kubernetes-dashboard-kong-proxy 8443:443
```

# Tailscale
## Operator
https://tailscale.com/kb/1236/kubernetes-operator
```shell
    helm upgrade \
      --install \
      tailscale-operator \
      tailscale/tailscale-operator \
      --namespace=tailscale \
      --create-namespace \
      --set-string oauth.clientId="kN6GWhA23g11CNTRL" \
      --set-string oauth.clientSecret="tskey-client-kN6GWhA23g11CNTRL-HQzzF7oWZjVRrQSYeBEQkVPnZen64ZEuP" \
      --wait
```

## Ingress
https://tailscale.com/kb/1439/kubernetes-operator-cluster-ingress

## Dashboard
https://tailscale.com/kb/1437/kubernetes-operator-api-server-proxy

# ArgoCD
https://argo-cd.readthedocs.io/en/stable/getting_started/

```shell
    kubectl create namespace argocd
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Create ingress-route