# Phase 2: 3-node, LoadBalancer, and Redis foundation alignment

Phase 2 keeps the Phase 1 source-of-truth model:

```text
GitHub main -> GitHub Actions -> installer -> K3s
```

The deployment source of truth remains the GitHub repository. The installer runs from the checked-out commit, syncs `/opt/otp-relay-k8s` to `origin/main`, stages the committed Dockerfiles and Kubernetes manifests, renders runtime values, and applies them to K3s.

Phase 2 adds cluster deployment options and prepares the application for Redis-backed shared state.

## Phase 2 status

Phase 2 is being implemented in two parts.

### Phase 2A: deployment and platform alignment

Completed:

```text
GitHub Actions deployment through self-hosted runner
repo Dockerfiles as source of truth
repo Kubernetes manifests as source of truth
LoadBalancer service support
MetalLB support
MetalLB auto-assigned IP with LOADBALANCER_IP blank
PVC persistence
nodeSelector support
single replica enforcement
automatic PORTAL_URL update from assigned LoadBalancer IP
```

### Phase 2B: Redis shared-state foundation

In progress:

```text
Redis service and StatefulSet
Redis PVC
Redis PDB
REDIS_URL passed to app
/readyz Redis connectivity check
```

Pending after Redis foundation:

```text
move claim_queue to Redis
move pending_otps to Redis
move admin sessions to Redis
then allow REPLICA_COUNT=2
```

Until queue, OTP, and session state are moved to Redis, the app must remain:

```text
REPLICA_COUNT=1
```

## Supported Phase 2 options

```text
SERVICE_TYPE=NodePort|LoadBalancer
INGRESS_ENABLED=0|1
LOADBALANCER_IP=
INSTALL_METALLB=0|1
REQUIRE_METALLB=0|1
METALLB_IP_RANGE=
METALLB_POOL_NAME=otp-relay-pool

PVC_STORAGE_CLASS=local-path
PVC_SIZE=1Gi

APP_NODE_SELECTOR_KEY=
APP_NODE_SELECTOR_VALUE=
MONITOR_NODE_SELECTOR_KEY=
MONITOR_NODE_SELECTOR_VALUE=

REDIS_ENABLED=0|1
REDIS_URL=redis://otp-redis:6379/0
REDIS_REQUIRED=0|1
REDIS_STORAGE_CLASS=local-path
REDIS_SIZE=1Gi

REPLICA_COUNT=1
```

## Recommended Phase 2A / current production values

```text
SERVICE_TYPE=LoadBalancer
INGRESS_ENABLED=0
INSTALL_METALLB=0
REQUIRE_METALLB=1
METALLB_IP_RANGE=
LOADBALANCER_IP=

APP_NODE_SELECTOR_KEY=kubernetes.io/hostname
APP_NODE_SELECTOR_VALUE=<app-node>

MONITOR_NODE_SELECTOR_KEY=kubernetes.io/hostname
MONITOR_NODE_SELECTOR_VALUE=<phone-network-node>

PVC_STORAGE_CLASS=local-path
PVC_SIZE=1Gi

REDIS_ENABLED=1
REDIS_URL=redis://otp-redis:6379/0
REDIS_REQUIRED=0
REDIS_STORAGE_CLASS=local-path
REDIS_SIZE=1Gi

REPLICA_COUNT=1
```

Use `INSTALL_METALLB=1` only when the installer should install/configure MetalLB. If MetalLB is already installed and the address pool already exists, keep:

```text
INSTALL_METALLB=0
REQUIRE_METALLB=1
```

Keep `LOADBALANCER_IP=` blank so MetalLB auto-assigns an available IP from the configured pool.

## MetalLB model

Phase 2 exposes the portal directly through a Kubernetes `LoadBalancer` Service:

```text
Client
  ↓
MetalLB-assigned VIP
  ↓
Service/otp-relay type LoadBalancer
  ↓
otp-relay pod port 8000
```

Current Phase 2 does not require Traefik Ingress:

```text
INGRESS_ENABLED=0
```

Traefik may still be installed by K3s, but OTP Relay should use the MetalLB LoadBalancer service as the primary exposure path for this phase.

## Why replicas remain 1

The app currently keeps these in process memory:

```text
claim_queue
pending_otps
ADMIN_SESSIONS
ADMIN_LOGIN_ATTEMPTS
```

Multiple app replicas would create multiple independent queues, OTP display states, and admin sessions. Redis is being introduced first as a shared-state backend, but Redis readiness alone is not enough to increase replicas.

`REPLICA_COUNT` must stay at `1` until these states are actually migrated to Redis:

```text
claim_queue -> Redis
pending_otps -> Redis
ADMIN_SESSIONS -> Redis
```

After that migration is complete and tested, `REPLICA_COUNT=2` can be enabled with anti-affinity and PodDisruptionBudget support.

## Redis foundation

Redis is introduced in Phase 2B as infrastructure first.

The first Redis step deploys:

```text
k8s/manifests/redis-service.yaml
k8s/manifests/redis-statefulset.yaml
k8s/manifests/redis-pdb.yaml
```

The app receives:

```text
REDIS_URL=redis://otp-redis:6379/0
```

The `/readyz` endpoint reports Redis connectivity:

```json
{
  "status": "ok",
  "users_loaded": 123,
  "redis": "ok",
  "redis_required": false
}
```

For the first Redis foundation deployment, keep:

```text
REDIS_REQUIRED=0
```

After Redis is confirmed healthy, this can be changed to:

```text
REDIS_REQUIRED=1
```

Do not increase replicas until Redis is used by the application state code.

## Verify MetalLB and LoadBalancer

Check MetalLB:

```bash
sudo k3s kubectl get pods -n metallb-system -o wide
sudo k3s kubectl get ipaddresspool -n metallb-system
sudo k3s kubectl get l2advertisement -n metallb-system
```

Check the OTP Relay LoadBalancer service:

```bash
sudo k3s kubectl describe svc otp-relay -n otp-relay
sudo k3s kubectl get svc otp-relay -n otp-relay -o wide
```

Expected:

```text
Type: LoadBalancer
LoadBalancer Ingress: <assigned-ip>
metallb.io/ip-allocated-from-pool: otp-relay-pool
```

Check only the assigned IP:

```bash
sudo k3s kubectl get svc otp-relay -n otp-relay -o jsonpath='{.status.loadBalancer.ingress[0].ip}'; echo
```

Check the portal URL in ConfigMap:

```bash
sudo k3s kubectl get configmap otp-relay-config -n otp-relay -o jsonpath='{.data.PORTAL_URL}'; echo
```

Expected:

```text
http://<assigned-loadbalancer-ip>
```

## Verify Redis foundation

Check Redis resources:

```bash
sudo k3s kubectl get svc otp-redis -n otp-relay
sudo k3s kubectl get statefulset otp-redis -n otp-relay
sudo k3s kubectl get pods -n otp-relay -l app=otp-redis -o wide
sudo k3s kubectl get pdb otp-redis-pdb -n otp-relay
```

Check Redis rollout:

```bash
sudo k3s kubectl rollout status statefulset/otp-redis -n otp-relay --timeout=180s
```

Check app readiness through the portal:

```bash
curl -s http://<loadbalancer-ip>/readyz
```

Expected Redis foundation result:

```json
{
  "status": "ok",
  "redis": "ok",
  "redis_required": false
}
```

## GitHub source of truth

Phase 2 deployments use the committed Dockerfiles and manifests as source.

Source files:

```text
k8s/Dockerfile
k8s/Dockerfile.monitor
k8s/manifests/*.yaml
```

The installer only stages these files into a temporary render directory and injects runtime values such as:

```text
namespace
service type
PVC size and storage class
node selectors
LoadBalancer IP
PORTAL_URL
Redis settings
image names
```

Do not edit files under `/opt/otp-relay-k8s` for normal deployment changes. Commit changes to GitHub and deploy through Actions.

## Phase 2 completion criteria

Phase 2A is complete when:

```text
LoadBalancer service receives a MetalLB IP
PORTAL_URL matches the assigned IP
repo Dockerfiles and manifests are source of truth
PVC remains bound and preserved
app and monitor deploy successfully from Actions
```

Phase 2B is complete when:

```text
Redis deploys successfully
app /readyz reports redis=ok
claim queue is Redis-backed
pending OTPs are Redis-backed
admin sessions are Redis-backed
REPLICA_COUNT=2 works safely
```

Only after Phase 2B should Phase 3 resilience testing begin.
