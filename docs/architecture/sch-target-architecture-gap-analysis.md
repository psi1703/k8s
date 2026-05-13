# SCH Target Architecture vs Current Validated Implementation

This document is the working alignment sheet for the OTP Relay Kubernetes architecture. It separates the design SCH is aiming for from the implementation that is currently validated in this repository.

## Current validated implementation

The current implementation is a validated Phase 3 baseline, not the final production target.

```text
Clients / browsers / iPhone Shortcut
  -> DNS: srvotptest26.init-db.lan
  -> Traefik Ingress with HTTPS
  -> Kubernetes Service otp-relay
  -> FastAPI app pod
  -> Redis shared runtime state
  -> Portal UI displays OTP

Monitor pod remains isolated from Service/Ingress and only performs phone presence, iPhone SMS-path, audit-log, and health checks.
```

Current validated characteristics:

| Area | Current implementation | Status |
|---|---|---|
| Cluster | 3-node K3s cluster | Validated baseline |
| Exposure | Traefik Ingress plus LoadBalancer service through MetalLB | Validated, but final VIP/LB path still needs confirmation |
| TLS | Kubernetes TLS secret generated as self-signed by workflow/installer | IT must distribute/trust the certificate via Group Policy; browser warning may appear until policy applies |
| App runtime state | OTP queue, pending OTPs, admin sessions, and login attempts are Redis-backed | Good |
| Redis | Single Redis StatefulSet, one pod | Functional but not HA |
| App replicas | `REPLICA_COUNT=1` | Safe current setting, not final target |
| App storage | Supports static NFS `ReadWriteMany` PV/PVC when `NFS_ENABLED=1`; existing clusters may still be on `local-path` until migrated | NFS support added; live migration requires NFS server/export and PVC migration |
| Redis storage | Redis PVC using `local-path`, `ReadWriteOnce` by default | Functional but not HA production storage |
| Monitor | Required pod, `hostNetwork: true`, `NET_RAW`, no Service/Ingress | Aligned |
| Rollout strategy | `Recreate` | Correct while app PVC is RWO |

## SCH target production architecture

SCH's target architecture is the production design direction:

```text
Clients
  -> internal DNS
  -> LB/VIP layer
  -> HTTPS ingress/controller
  -> Kubernetes service
  -> multiple app pods across worker nodes
  -> shared Redis/Sentinel/cluster state
  -> shared RWX/network persistent storage

Monitor pod stays internal and unexposed.
```

Target characteristics:

| Area | SCH target | Required change from current repo |
|---|---|---|
| External access | DNS plus approved LB/VIP path such as F5, HAProxy, Keepalived, or confirmed MetalLB equivalent | Confirm final production LB/VIP model |
| TLS | HTTPS using certificate trusted on user machines | Keep self-signed TLS enabled; IT distributes/trusts the certificate via Group Policy |
| App replicas | Multiple FastAPI app pods | Requires shared storage and final OTP multi-replica validation |
| App storage | Shared RWX/network persistent storage | Implemented as static NFS PV/PVC for app data; migrate existing local-path PVC during maintenance |
| Redis | HA Redis/Sentinel/Cluster or managed Redis | Replace single Redis pod with HA Redis design |
| Redis persistence | Resilient storage appropriate for Redis HA design | Replace local single-PVC assumption |
| Failover | Pod kill, node drain, and app movement tests with real state survival | Run after shared storage and Redis HA are implemented |
| Monitor | Isolated monitor workload on phone-network-capable node | Keep current no-Service/no-Ingress model |

## Known gaps that must not be hidden

These are expected gaps between the current validated implementation and SCH's production target:

1. **Storage gap:** app PVC now has an NFS/RWX path available, but any live `local-path` PVC must still be migrated. Redis PVC remains `local-path`/`ReadWriteOnce` until the Redis HA design is implemented.
2. **Redis HA gap:** Redis is currently a single StatefulSet replica, not Sentinel/Cluster/managed HA Redis.
3. **App HA gap:** app replicas remain forced to `1`; this is intentional until storage and HA state are ready.
4. **TLS trust gap:** self-signed TLS stays enabled. IT must distribute/trust the certificate by Group Policy. Users may see a browser warning until policy reaches their machines.
5. **LB/VIP gap:** MetalLB is the current bare-metal implementation. SCH still needs to confirm whether final production uses MetalLB, F5, HAProxy, Keepalived, or another company VIP.
6. **Documentation gap:** older Phase 2 notes may describe direct LoadBalancer-only exposure. Current Phase 3 uses Traefik HTTPS in front of the app.

## Implementation rule for this repo

Do not loosen the safe guards just to make the design look complete.

Keep these controls until their dependencies are finished:

```text
REPLICA_COUNT=1
strategy: Recreate
REDIS_REQUIRED=1
monitor has no Service or Ingress
self-signed TLS stays enabled; IT will distribute/trust the certificate by Group Policy
NFS shared app storage is the target path; local-path remains validation-only or pre-migration storage
```

## Recommended next engineering order

1. Confirm the final production LB/VIP model with SCH.
2. Confirm IT Group Policy distribution/trust of the self-signed TLS certificate on user machines.
3. Provision the NFS export and migrate `/app/data` from local-path to the NFS-backed RWX PVC.
4. Replace single Redis with HA Redis/Sentinel/Cluster or a managed Redis endpoint.
5. Re-test pending OTP survival, admin sessions, and queue behavior during app pod restart.
6. Run controlled `REPLICA_COUNT=2` OTP validation.
7. Only then update the default app replica count and rollout strategy.
8. Run node-drain and failover tests with real app movement across nodes.

## Current wording for SCH/status updates

Use this wording when reporting project status:

```text
The current repo has a validated Phase 3 baseline on K3s with MetalLB, Traefik HTTPS, Redis-required shared runtime state, an isolated monitor pod, and repo support for NFS-backed RWX app storage. It is not yet the final SCH production architecture until the live PVC is migrated to NFS, Redis is made HA, TLS trust is distributed by IT Group Policy, VIP alignment is confirmed, and safe multi-replica app validation is complete.
```
