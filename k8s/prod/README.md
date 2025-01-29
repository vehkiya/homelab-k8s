## Set-up Talos OS
<!-- 
```shell
    helm repo add coredns https://coredns.github.io/helm
    helm --namespace=kube-system install coredns coredns/coredns
``` -->

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
  helm install -n traefik --create-namespace traefik traefik/traefik -f /home/vehkiya/IdeaProjects/homelab-k8s/k8s/prod/traefik/traefik-config.yaml
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
      --set crds.enabled=true \
      --set config.enableGatewayAPI=true
```
3. Provision Cloudflare API Token secret
```shell
    kubectl apply -f prod/cert-manager/00-cloudflare-token.yaml
```
4. Create cluster issuer
```shell
    kubectl apply -f prod/cert-manager/01-acme-issuer-cf-solver.yaml
```
5. Create certificate config
```shell
    kubectl apply -f prod/cert-manager/02-certificate-config.yaml
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

# Dashboard
FW dashboard
```shell
kubectl -n kubernetes-dashboard port-forward svc/kubernetes-dashboard-kong-proxy 8443:443
```

# Tailscale
## Operator
https://tailscale.com/kb/1236/kubernetes-operator

## Ingress
https://tailscale.com/kb/1439/kubernetes-operator-cluster-ingress

## Dashboard
https://tailscale.com/kb/1437/kubernetes-operator-api-server-proxy