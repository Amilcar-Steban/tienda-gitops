# tienda-gitops

La fuente de verdad del clúster de la tienda (Fase 6 del Roadmap DevOps 2027). Nadie despliega con
`kubectl` ni `helm upgrade`: se cambia este repositorio y Argo CD lo aplica.

```
argocd/root.yaml            app de apps: lo único que se aplica a mano
argocd/apps/proyectos.yaml  AppProjects "plataforma" y "tienda" (+ ventana sin despliegues en prod)
argocd/apps/plataforma.yaml Envoy Gateway, metrics-server, Argo Rollouts y la GatewayClass
argocd/apps/tienda.yaml     ApplicationSet: una Application por carpeta de apps/tienda/
apps/tienda/dev/            values.yaml (versión, réplicas, dominio) + manifiestos/ (Rollout, análisis)
apps/tienda/prod/           igual, con una pausa manual en el canary
platform/gateway/           GatewayClass y EnvoyProxy (Service ClusterIP en kind)
bootstrap/                  instalar-argocd.sh y la configuración de kind
ci/promover.yml             workflow para el repo de código: dev automático y PR para prod
.github/workflows/validar.yml  cada PR se renderiza con el chart real y se valida con kubeconform
```

La aplicación sale del chart de Helm del repositorio de código (`tienda-pipeline/chart/tienda`,
Fase 5); este repositorio solo guarda los valores de cada entorno y los manifiestos propios de la
entrega progresiva. Es el patrón *multi-source* de Argo CD.

## Empezar

```bash
# Si haces un fork, cambia Amilcar-Steban/amilcar-steban por tu usuario en URLs e imágenes:
#   grep -rli amilcar-steban . | xargs sed -i.bak -e 's#Amilcar-Steban#TU-USUARIO#g' -e 's#amilcar-steban#tu-usuario#g'

# Clúster + Argo CD + app raíz (unos 5 minutos hasta tener todo Healthy)
./bootstrap/instalar-argocd.sh
kubectl -n argocd get applications -w
```

Los dos repositorios deben ser públicos, o registra sus credenciales en Argo CD
(`argocd repo add … --github-app-id …`, mejor que un token personal).

## Probarlo

| Prueba | Cómo | Esperado |
|---|---|---|
| Autorreparación | `kubectl scale deploy/tienda-frontend -n tienda-dev --replicas=5` | vuelve a 2 en ~10 s |
| Recursos borrados | `kubectl delete svc tienda-frontend -n tienda-dev` | Argo CD lo recrea en ~10 s |
| Promoción | cambia `etiqueta` en `apps/tienda/dev/values.yaml` y haz push | canary 34 % → 67 % → 100 % con análisis `Successful` |
| Versión rota | pon una etiqueta que no existe | el Rollout se aborta solo (`progressDeadlineAbort`), la tienda sigue sirviendo la versión estable; Argo CD queda `Synced/Degraded` |
| Volver atrás | `git revert` del commit roto | `Synced/Healthy` en segundos |
| Recuperación | `kind delete cluster --name gitops` y `./bootstrap/instalar-argocd.sh` | todo igual que antes, desde Git |

Para ver la tienda: `kubectl -n envoy-gateway-system port-forward svc/<envoy-tienda-dev-…> 8081:80` y
abre `http://dev.tienda.localhost:8081`. Para el canary: `kubectl argo rollouts get rollout tienda-api -n tienda-dev --watch`.

## Promoción automática desde el CI

Copia `ci/promover.yml` a `.github/workflows/` de `tienda-pipeline` y llámalo desde `image.yml`
(instrucciones dentro del archivo). Crea una GitHub App instalada solo en este repositorio con
permisos de escritura en contenido y pull requests. El CI no tiene ni necesita credenciales del clúster.

## En EKS

Quita `parametersRef` de `platform/gateway/gatewayclass.yaml` (allí el Service LoadBalancer crea un
NLB), cambia `local.enabled` a `false` en los `values.yaml` y usa los valores de producción del chart
(RDS, ElastiCache, External Secrets).
