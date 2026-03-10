#!/bin/bash
set -eo pipefail

echo "================================================="
echo " Homelab K8s Bootstrap Script"
echo "================================================="
echo "This script will deploy the foundational cluster"
echo "components in the required order."
echo "================================================="
echo ""

apply_and_wait() {
  local app_name=$1
  local app_dir=$2
  local wait_resource=$3
  local wait_namespace=$4

  echo "[*] Deploying ${app_name} from ${app_dir}..."
  kustomize build --enable-helm "${app_dir}" | kubectl apply --server-side -f -
  
  if [ -n "$wait_resource" ] && [ -n "$wait_namespace" ]; then
    echo "[*] Waiting for ${app_name} to be ready..."
    if [[ "$wait_resource" == ds/* ]]; then
      # Wait for daemonsets
      kubectl rollout status "$wait_resource" -n "$wait_namespace" --timeout=300s
    elif [[ "$wait_resource" == deployment/* ]]; then
      # Wait for deployments
      kubectl rollout status "$wait_resource" -n "$wait_namespace" --timeout=300s
    fi
  else
    echo "[*] Skipping wait for ${app_name} (no wait condition specified)"
  fi
  
  echo "[+] ${app_name} deployment complete."
  echo ""
}

# 1. Deploy Cilium (CNI)
apply_and_wait "Cilium" "apps/bootstrap/cilium" "ds/cilium" "kube-system"

# 2. Deploy CoreDNS (DNS)
apply_and_wait "CoreDNS" "apps/bootstrap/coredns" "ds/coredns" "kube-system"

# 3. Deploy External Secrets Operator
apply_and_wait "External Secrets Operator" "apps/bootstrap/external-secrets-operator" "deployment/external-secrets" "external-secrets"

# 4. Deploy ArgoCD
apply_and_wait "ArgoCD" "apps/bootstrap/argocd" "deployment/argocd-server" "argocd"

echo "================================================="
echo " Bootstrap Complete!"
echo " The cluster foundation is now running."
echo "================================================="
