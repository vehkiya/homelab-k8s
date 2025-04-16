## Set-up Talos OS

## Set-up Cilium CNI
1. Add repo
```shell
    helm repo add cilium https://helm.cilium.io/
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

**_In case of DNS failures, make sure you're using the correct CoreDNS ConfigMap_**

### If needed, restore SealedSecrets with master key

## Install Traefik
1. Add repo
```shell
    helm repo add traefik https://traefik.github.io/charts
```
2. Install with values
```shell
    helm upgrade --install -n traefik --create-namespace traefik traefik/traefik -f traefik/values/traefik-config.yaml
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
      --version v1.17.1 \
      --values cert-manager/values/values.yaml
```
3. Provision Cloudflare API Token secret
```shell
    kubectl apply -f cert-manager/00-sealed-cloudflare-token.yaml
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

# Kubernetes Dashboard
1. Add repo
```shell
    helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
```
2. Install 
```shell
    helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
      --create-namespace \
      --namespace kubernetes-dashboard
```
3. Provision dashboard credentials
```shell
  kubectl apply -f kubernetes-dashboard/dashboard-data.yaml
```
4. Generate token for your user
```shell
  kubectl -n kubernetes-dashboard create token vehkiya
```
Get long-lived token
```shell
    kubectl get secret vehkiya -n kubernetes-dashboard -o jsonpath="{.data.token}" | base64 -d
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
#    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/ha/install.yaml
```

Create ingress-route


# Plex

## Install Intel GPU Driver
_Requires Talos I915 driver_
_Requires inteldeviceplugins-system namespace to run as root_
https://github.com/intel/intel-device-plugins-for-kubernetes/blob/main/INSTALL.md
```shell
    helm repo add jetstack https://charts.jetstack.io # for cert-manager
    helm repo add nfd https://kubernetes-sigs.github.io/node-feature-discovery/charts # for NFD
    helm repo add intel https://intel.github.io/helm-charts/ # for device-plugin-operator and plugins
    helm repo update
```

```shell
    helm install nfd nfd/node-feature-discovery \
      --namespace node-feature-discovery --create-namespace --version 0.16.4
```

```shell
    helm install dp-operator intel/intel-device-plugins-operator --namespace inteldeviceplugins-system --create-namespace
```

```shell
    helm install gpu intel/intel-device-plugins-gpu --namespace inteldeviceplugins-system --create-namespace \
  --set nodeFeatureRule=true
```

Label: `intel.feature.node.kubernetes.io/gpu: true`