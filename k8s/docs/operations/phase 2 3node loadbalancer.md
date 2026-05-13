# Phase 2 and Phase 3: 3-node, LoadBalancer, Traefik HTTPS, and Redis alignment

This document keeps the historical Phase 2 work visible, but the current repository state has moved into the Phase 3 validation baseline.

For SCH target/current alignment, see:

```text
docs/operations/sch-target-vs-current.md
```

## Deployment source of truth

The deployment source of truth remains the GitHub repository:

```text
GitHub main -> GitHub Actions -> installer -> K3s
```

The installer runs from the checked-out commit, syncs `/opt/otp-relay-k8s` to `origin/main`, stages the committed Dockerfiles and Kubernetes manifests, renders runtime values, and applies them to K3s.

## Historical Phase 2 status

Phase 2 completed the foundation needed before SCH-style cluster validation:

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
Redis service, StatefulSet, PVC, and PDB
REDIS_URL passed to app
/readyz Redis connectivity check
Redis-backed OTP queue
Redis-backed pending OTP display state
Redis-backed admin sessions
Redis-backed admin login-attempt and lockout state
REDIS_REQUIRED=1 validation/default posture
```

## Current Phase 3 validation values

The current SCH-alignment validation path is:

```text
SERVICE_TYPE=LoadBalancer
LOADBALANCER_IP=
INGRESS_ENABLED=1
TLS_ENABLED=1
TLS_HOST=srvotptest26.init-db.lan
TLS_SECRET_NAME=otp-relay-tls
TLS_SELF_SIGNED=1
INSTALL_METALLB=0
REQUIRE_METALLB=1
METALLB_IP_RANGE=

PVC_STORAGE_CLASS=local-path
PVC_SIZE=1Gi

APP_NODE_SELECTOR_KEY=otp-relay/storage-node
APP_NODE_SELECTOR_VALUE=true
REDIS_NODE_SELECTOR_KEY=otp-relay/storage-node
REDIS_NODE_SELECTOR_VALUE=true
MONITOR_NODE_SELECTOR_KEY=otp-relay/monitor-node
MONITOR_NODE_SELECTOR_VALUE=true

REDIS_ENABLED=1
REDIS_URL=redis://otp-redis:6379/0
REDIS_REQUIRED=1
REDIS_STORAGE_CLASS=local-path
REDIS_SIZE=1Gi

REPLICA_COUNT=1
```

Current SCH/IT runs keep TLS enabled and generate/update the self-signed secret:

```text
TLS_ENABLED=1
TLS_SELF_SIGNED=1
```

IT will distribute/trust the certificate by Group Policy. Users may see a browser warning until that policy lands on their machine.

## Exposure model

The current Phase 3 exposure model is:

```text
Client
  -> DNS: srvotptest26.init-db.lan
  -> Traefik Ingress HTTPS
  -> Service/otp-relay
  -> otp-relay app pod port 8000
```

The `LoadBalancer` service and MetalLB remain part of the bare-metal implementation. SCH still needs to confirm whether the final production LB/VIP model is MetalLB, F5, HAProxy, Keepalived, or another company-managed VIP.

The older Phase 2 direct service model is retained only as historical context:

```text
Client -> MetalLB-assigned service IP -> Service/otp-relay -> app pod
```

Do not present the direct HTTP service path as the final user-facing production path unless SCH explicitly approves it.

## Why replicas remain 1

The app runtime state has been moved to Redis, but two production blockers remain:

```text
app PVC is still local-path/ReadWriteOnce
Redis is still a single StatefulSet pod
```

Because of those blockers, the repository intentionally keeps:

```text
REPLICA_COUNT=1
strategy: Recreate
```

Do not raise the app replica count until shared storage, Redis HA, and final OTP flow validation are complete.

## Storage status

Current app storage:

```text
PVC: otp-relay-data
storageClassName: local-path
accessModes: ReadWriteOnce
```

Current Redis storage:

```text
PVC: redis-data-otp-redis-0
storageClassName: local-path
accessModes: ReadWriteOnce
```

This is acceptable for validation. It is not SCH's final production target. The target requires shared/RWX/network storage for app data and a Redis storage model appropriate for HA Redis.

## Redis status

Redis is required and used by the app, but the current manifest is still single-instance Redis:

```text
StatefulSet: otp-redis
replicas: 1
Service: otp-redis ClusterIP
```

SCH target expects Redis HA/Sentinel/Cluster or an approved managed/internal Redis service.

## Verify MetalLB and LoadBalancer

```bash
sudo k3s kubectl get pods -n metallb-system -o wide
sudo k3s kubectl get ipaddresspool -n metallb-system
sudo k3s kubectl get l2advertisement -n metallb-system
sudo k3s kubectl describe svc otp-relay -n otp-relay
sudo k3s kubectl get svc otp-relay -n otp-relay -o wide
```

Expected current service shape:

```text
Type: LoadBalancer
LoadBalancer Ingress: <assigned-ip>
metallb.io/ip-allocated-from-pool: <pool-name>
```

## Verify Traefik HTTPS

```bash
sudo k3s kubectl get ingress otp-relay -n otp-relay -o wide
sudo k3s kubectl describe ingress otp-relay -n otp-relay
curl -k -s https://srvotptest26.init-db.lan/readyz
```

Expected Redis-required readiness:

```json
{
  "status": "ok",
  "redis": "ok",
  "redis_required": true
}
```

## Verify Redis

```bash
sudo k3s kubectl get svc otp-redis -n otp-relay
sudo k3s kubectl get statefulset otp-redis -n otp-relay
sudo k3s kubectl get pods -n otp-relay -l app=otp-redis -o wide
sudo k3s kubectl get pdb otp-redis-pdb -n otp-relay
sudo k3s kubectl rollout status statefulset/otp-redis -n otp-relay --timeout=180s
```

## Verify monitor isolation

```bash
sudo k3s kubectl get deploy otp-monitor -n otp-relay -o wide
sudo k3s kubectl get svc -n otp-relay
sudo k3s kubectl get ingress -n otp-relay
```

There should be no Service or Ingress for `otp-monitor`.

## Next SCH-alignment work

1. Confirm final LB/VIP model.
2. Confirm IT Group Policy distribution/trust of the self-signed TLS certificate.
3. Move app data to approved shared RWX/network storage.
4. Move Redis to HA Redis/Sentinel/Cluster or approved managed Redis.
5. Re-run restart-survival and OTP flow validation.
6. Run controlled two-replica app validation.
7. Only then consider changing the replica default.
