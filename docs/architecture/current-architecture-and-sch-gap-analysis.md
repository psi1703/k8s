# Current Architecture and SCH Gap Analysis

## Purpose

This document is the single architecture reference for the OTP Relay Kubernetes deployment. It combines the previous architecture plan and SCH target/current gap document into one compact source of truth.

## Current validated baseline

The current implementation is a Phase 3 SCH-alignment validation baseline.

```text
Clients / browsers / iPhone Shortcut
  -> DNS: srvotptest26.init-db.lan
  -> Traefik Ingress with HTTPS
  -> Kubernetes Service otp-relay
  -> FastAPI app pod
  -> Redis HAProxy service
  -> Redis Sentinel-managed Redis master/replicas
  -> NFS-backed /app/data storage
  -> Portal UI displays OTP

Monitor pod
  -> hostNetwork + NET_RAW
  -> phone presence and SMS-path checks
  -> reads shared audit log
  -> sends WhatsApp alerts
  -> no Service / no Ingress
```

Current conservative posture:

```text
SERVICE_TYPE=LoadBalancer
INGRESS_ENABLED=1
TLS_ENABLED=1
TLS_SELF_SIGNED=1
REQUIRE_METALLB=1
REDIS_ENABLED=1
REDIS_REQUIRED=1
NFS_ENABLED=1
PVC_STORAGE_CLASS=otp-relay-nfs
REPLICA_COUNT=1
strategy: Recreate
```

## Current application model

The portal consists of:

- FastAPI backend served from the app pod.
- React frontend source/static assets served by the app.
- On-screen OTP delivery through browser polling.
- iPhone Shortcut posting received SMS content to `/sms-received`.
- Redis-backed OTP queue and pending OTP state.
- Redis-backed admin sessions and admin login-attempt tracking.
- PVC-backed runtime files under `/app/data`.
- Required monitor pod for phone presence, SMS-path, audit-log, and alert checks.

Runtime app files under `/app/data`:

```text
users.xlsx
admin_auth.json
admin_config.json
wizard_progress.json
audit.log
```

## Redis shared-state model

Redis is required in the validated Phase 3 posture.

The app uses:

```text
REDIS_URL=redis://otp-redis:6379/0
REDIS_REQUIRED=1
```

The stable `otp-redis` service points to HAProxy. HAProxy routes Redis traffic to the current Redis master. Sentinel monitors Redis pods and performs master promotion when needed.

Redis currently supports:

- OTP claim queue.
- Pending OTP display state.
- OTP TTL behavior.
- Admin sessions.
- Admin login-attempt and lockout state.

This Redis foundation is why two app replicas can be tested later without the old in-memory split-brain OTP problem. The live default still remains one app replica until final OTP and worker-drain validation are complete.

## Storage model

Application data has been moved from local-path/RWO storage toward NFS/RWX shared storage.

Validated storage path:

```text
PVC:           otp-relay-data
PV:            otp-relay-data-nfs-pv
Access mode:   ReadWriteMany
StorageClass:  otp-relay-nfs
NFS server:    172.31.11.108
NFS path:      /export/otp-relay-data
Mount path:    /app/data
```

Redis PVCs are separate from the app NFS storage. That is acceptable for validation, but Redis backup/restore expectations still need SCH production sign-off.

## Kubernetes deployment assets

The active Kubernetes assets live under `k8s/`:

```text
k8s/
├── Dockerfile
├── Dockerfile.monitor
└── manifests/
    ├── configmap.yaml
    ├── deployment-monitor.yaml
    ├── deployment.yaml
    ├── ingress.yaml
    ├── namespace.yaml
    ├── pv-nfs.yaml
    ├── pvc.yaml
    ├── redis-configmap.yaml
    ├── redis-haproxy-configmap.yaml
    ├── redis-haproxy-deployment.yaml
    ├── redis-pdb.yaml
    ├── redis-sentinel-configmap.yaml
    ├── redis-sentinel-deployment.yaml
    ├── redis-sentinel-service.yaml
    ├── redis-service.yaml
    ├── redis-statefulset.yaml
    ├── secret-example.env
    └── service.yaml
```

Do not restore `k8s/docs/`. Documentation belongs under `docs/` only.

## SCH target architecture

SCH's production direction is:

```text
Clients
  -> internal DNS
  -> approved LB/VIP layer
  -> HTTPS ingress/controller
  -> Kubernetes service
  -> multiple app pods across worker nodes
  -> shared Redis/Sentinel/HAProxy or approved managed Redis
  -> shared RWX/network persistent app storage

Monitor pod remains internal and unexposed.
```

## Current vs target gap table

| Area | SCH target | Current repo status / remaining work |
|---|---|---|
| External access | DNS plus approved LB/VIP path such as F5, HAProxy, Keepalived, or confirmed MetalLB equivalent | MetalLB/Traefik path validated; final production VIP/LB model still needs SCH confirmation. |
| TLS | HTTPS trusted on user machines | Self-signed TLS enabled; IT Group Policy trust rollout pending. |
| App replicas | Multiple FastAPI app pods | Redis and NFS foundations are in place; final OTP, restart, and two-replica flow validation still pending. |
| App storage | Shared RWX/network persistent storage | Implemented and validated as static NFS PV/PVC for `/app/data`. |
| Redis | HA Redis/Sentinel/Cluster or approved managed Redis | Redis Sentinel/HAProxy topology implemented and failover validated; production acceptance/backups pending. |
| Failover | Pod kill, node drain, and app movement tests with state survival | Redis failover validated; full worker-drain and app-level OTP validation still pending. |
| Monitor | Isolated monitor workload on phone-network-capable node | Current no-Service/no-Ingress model is aligned. |
| Documentation | Clear active docs with no conflicting legacy guidance | This compact docs structure is the intended active documentation set. |

## Why the app still stays at one live replica

Redis and NFS remove the main architectural blockers for multi-replica validation, but the live default remains conservative because the business-critical flow is OTP delivery.

Do not raise `REPLICA_COUNT` above `1` until all of these pass:

- Manager live OTP trigger test.
- Pending OTP restart-survival test.
- Two-replica OTP claim/SMS/display flow validation.
- DNS/TLS client validation from user machines.
- Controlled worker-drain validation.

## Remaining production-alignment gaps

1. Confirm final production LB/VIP model with SCH.
2. Complete TLS trust rollout through IT Group Policy.
3. Validate app-level OTP behavior through restart and two-replica scenarios.
4. Document Redis backup/restore expectations.
5. Complete worker-drain validation.
6. Decide whether Redis Sentinel/HAProxy is accepted for production or replaced by an approved managed Redis service.

## Implementation rule

Do not loosen safeguards just to make the architecture look complete.

The correct current position is:

```text
Redis and NFS foundations are validated.
Redis HA/Sentinel/HAProxy failover is validated.
The app remains one replica until final OTP and node-drain validations pass.
```
