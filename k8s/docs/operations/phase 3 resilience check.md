# Phase 3 Resilience Checkpoint

Phase 3 validates the current K3s implementation against SCH's target architecture. It does not mark the platform as final production architecture.

For the target/current gap table, see:

```text
docs/operations/sch-target-vs-current.md
```

## Completed validation

- 3-node K3s cluster is running.
- K3s ServiceLB/Klipper is disabled.
- MetalLB is the active bare-metal LoadBalancer implementation.
- Traefik Ingress is enabled for the portal path.
- HTTPS is enabled through a Kubernetes TLS secret.
- Redis is required by the app with `REDIS_REQUIRED=1`.
- `/readyz` reports Redis status and fails readiness when Redis is unavailable.
- OTP queue state is Redis-backed.
- Pending OTP display state is Redis-backed.
- Admin sessions are Redis-backed.
- Admin login-attempt and lockout state is Redis-backed.
- Monitor pod remains internal: no Service, no Ingress.
- Monitor keeps `hostNetwork: true`, `dnsPolicy: ClusterFirstWithHostNet`, and `NET_RAW` for phone presence checks.
- App pod restart test passed.
- Redis pod restart test passed.
- Monitor pod restart test passed.
- Worker scheduling/drain checks were performed for cluster resilience validation.

## Current topology

The intended current validation topology is:

```text
debian        control-plane / cluster management / app-capable node
otp-worker-1  Redis-capable worker
otp-worker-2  monitor-capable worker with phone-network reachability
```

Actual placement is controlled by these workflow/installer variables:

```text
APP_NODE_SELECTOR_KEY / APP_NODE_SELECTOR_VALUE
REDIS_NODE_SELECTOR_KEY / REDIS_NODE_SELECTOR_VALUE
MONITOR_NODE_SELECTOR_KEY / MONITOR_NODE_SELECTOR_VALUE
```

Do not hard-code a node name in documentation or manifests unless the live cluster is deliberately pinned for a specific validation run.

## Current safe constraints

Keep these constraints until SCH target gaps are closed:

```text
REPLICA_COUNT=1
strategy: Recreate
REDIS_REQUIRED=1
PVC_STORAGE_CLASS=local-path unless an approved shared storage class is supplied
REDIS_STORAGE_CLASS=local-path unless an approved Redis storage design is supplied
TLS_SELF_SIGNED=1; TLS remains enabled and IT will distribute/trust the certificate by Group Policy
```

## Storage note

The current app and Redis persistent volumes default to K3s `local-path` storage with `ReadWriteOnce` access.

That is acceptable for validation, but it is not SCH's final target. SCH's target design expects shared or network-backed persistent storage so that workloads can move between nodes safely.

Do not scale the app above one replica or move storage-bound workloads freely across workers until `/app/data` storage is migrated to an approved shared/RWX/network storage backend.

## Redis note

Redis is now required for runtime state, but the current Redis manifest is still a single StatefulSet replica.

That is acceptable for current functional validation, but it is not the target HA design. SCH's target expects Redis HA/Sentinel/Cluster or an approved managed/internal Redis service.

## TLS note

Self-signed TLS is the current approved internal path. TLS remains enabled. IT will distribute/trust the certificate by Group Policy. Users may see a browser warning until that policy reaches their machine. The path is:

```text
internal DNS hostname -> self-signed certificate trusted by IT Group Policy -> Traefik Ingress -> otp-relay service
```

## Remaining production-alignment work

1. Confirm final LB/VIP model with SCH.
2. Confirm self-signed TLS certificate trust distribution through IT Group Policy.
3. Replace app `local-path`/RWO storage with approved shared RWX/network storage.
4. Replace single Redis pod with HA Redis/Sentinel/Cluster or managed Redis.
5. Re-run pending OTP restart-survival test.
6. Re-run manager live OTP trigger test.
7. Run final two-replica OTP flow validation.
8. Only then consider changing `REPLICA_COUNT` above `1`.
