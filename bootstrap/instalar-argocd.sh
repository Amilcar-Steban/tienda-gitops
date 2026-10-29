#!/usr/bin/env bash
# Arranca un clúster desde cero con GitOps: kind + Argo CD + la app raíz. A partir de aquí, todo
# lo demás (Envoy Gateway, metrics-server, Argo Rollouts y la tienda en dev y prod) lo instala
# Argo CD leyendo este repositorio. Es también el procedimiento de recuperación ante desastres.
# Uso: ./bootstrap/instalar-argocd.sh [nombre-del-cluster]
# Requiere: docker, kind, kubectl y helm 3.18+ o 4.
set -Eeuo pipefail

CLUSTER="${1:-gitops}"
ARGOCD_CHART="10.11.6" # Argo CD v3.5
cd "$(dirname "$0")/.."

if ! grep -qx "$CLUSTER" <<<"$(kind get clusters)"; then
  kind create cluster --name "$CLUSTER" --config bootstrap/kind.yaml
fi
kubectl config use-context "kind-$CLUSTER"

echo "== Argo CD (chart $ARGOCD_CHART)"
helm upgrade --install argocd argo-cd --repo https://argoproj.github.io/argo-helm --version "$ARGOCD_CHART" \
  -n argocd --create-namespace --wait --timeout 10m \
  --set 'configs.params.server\.insecure=true' # TLS lo termina el port-forward o el Gateway

echo "== Repositorio OCI de Envoy Gateway (los charts OCI hay que declararlos)"
kubectl apply -n argocd -f - <<'YAML'
apiVersion: v1
kind: Secret
metadata:
  name: repo-envoyproxy
  labels: { argocd.argoproj.io/secret-type: repository }
stringData:
  name: envoyproxy
  url: docker.io/envoyproxy
  type: helm
  enableOCI: "true"
YAML

echo "== App raíz: desde aquí, todo sale de Git"
kubectl apply -n argocd -f argocd/root.yaml

echo
echo "Interfaz:   kubectl -n argocd port-forward svc/argocd-server 8080:80  →  http://localhost:8080"
echo "Usuario:    admin"
echo "Contraseña: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo "Progreso:   kubectl -n argocd get applications -w"
