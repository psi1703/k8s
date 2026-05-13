# OTP Relay Kubernetes Architecture Plan

> Current status: this repository is now a Phase 3 SCH-alignment validation baseline. Redis-backed OTP/admin runtime state is enabled and required, Traefik HTTPS is the current validation path, and the app supports NFS/RWX storage for `/app/data`. The live app should remain at `REPLICA_COUNT=1` until the final manager OTP validation, pending-OTP restart validation, two-replica OTP flow validation, and Redis HA production decision are complete.

**Audience:** Christian, SCH, the IT team, and anyone learning or operating the OTP Relay Kubernetes deployment.  
**Goal:** document the current Kubernetes architecture, explain how the project reached this point, and define the remaining production-alignment work in a controlled order.

---

## Why this repo exists

The OTP Relay portal originally worked as a VM/company-server deployment. This repository is the Kubernetes deployment track for the same portal.

The goal is not to rewrite the application. The goal is to move the working portal into Kubernetes while keeping the deployment understandable, reviewable, and safe for SCH validation.

The repository now provides:

- FastAPI portal application source.
- React frontend source/static assets.
- Required monitor service.
- Help documentation source.
- Dockerfiles for the app and monitor images.
- Kubernetes manifests as deployment source of truth.
- Installer and GitHub Actions workflow for deployment to K3s.
- Redis-backed runtime state for OTP queue, pending OTPs, admin sessions, and admin login-attempt tracking.
- NFS/RWX support for shared app data storage.

---

## Repo strategy

There are two related but separate tracks:

| Repo / branch | Purpose |
|---|---|
| `SCH-INIT/otp-relay` `portal` branch | Ubuntu 24.04 VM / company-server portal deployment baseline. |
| `psi1703/k8s` `main` branch | Kubernetes/K3s deployment track for the OTP Relay portal. |

Do not merge the repos blindly. The Kubernetes repo should remain focused on Kubernetes deployment, validation, and SCH-alignment work.

---

## Current validated posture

The current safe live posture is:

```text
SERVICE_TYPE=LoadBalancer
INGRESS_ENABLED=1
TLS_ENABLED=1
TLS_SELF_SIGNED=1
REQUIRE_METALLB=1
REDIS_ENABLED=1
REDIS_REQUIRED=1
REPLICA_COUNT=1
strategy: Recreate
```

NFS support exists and is the target app storage direction:

```text
NFS_ENABLED=1
NFS_STORAGE_CLASS=otp-relay-nfs
PVC_STORAGE_CLASS=otp-relay-nfs
```

Use those NFS settings only after the NFS server/export exists and the existing app PVC data has been backed up and migrated.

---

## Current application model

The portal is currently:

- **FastAPI backend** running in the app pod.
- **React frontend** served by the FastAPI/static frontend layer.
- **On-screen OTP delivery** through browser polling.
- **iPhone Shortcut** posts received SMS content to `/sms-received`.
- **Redis-backed runtime OTP/admin state** when Redis is enabled and required.
- **PVC-backed runtime files** under `/app/data`.
- **SMTP diagnostics only**; OTP delivery does not use email.

Runtime files under `/app/data` include:

```text
users.xlsx
audit.log
wizard_progress.json
admin_auth.json
admin_config.json
```

OTP values must not be written to disk or audit logs.

---

## Redis shared-state model

Redis is now part of the required validation posture.

Redis-backed scope:

```text
OTP claim queue
Pending OTP display state with TTL
Admin sessions with sliding TTL
Admin login-attempt tracking and lockout/window TTL
/readzy Redis status reporting
```

Current Redis resources:

```text
otp-redis Service
otp-redis StatefulSet
otp-redis-pdb PodDisruptionBudget
redis-data-otp-redis-0 PVC
REDIS_URL=redis://otp-redis:6379/0
REDIS_REQUIRED=1
```

Current limitation: Redis is still a single-instance dependency unless the HA Redis/Sentinel/HAProxy model is validated and accepted for production.

---

## App storage model

The app stores durable runtime files in `/app/data`.

Earlier validation used K3s `local-path` storage. That is acceptable for single-node or pinned-node validation, but it is not the final multi-node production posture.

The target storage model is NFS/RWX:

```text
NFS server/export
↓
static NFS PersistentVolume
↓
otp-relay-data PVC using ReadWriteMany
↓
/app/data mounted into the app pod
```

Important constraint:

```text
An existing local-path PVC cannot be changed in place into an NFS/RWX PVC.
```

Required migration sequence:

1. Back up current `/app/data` contents.
2. Create/verify the NFS export.
3. Enable the NFS PV/PVC configuration.
4. Restore app data into the NFS-backed volume.
5. Confirm `users.xlsx`, admin files, wizard progress, and audit log behavior.
6. Validate app restart and pod movement behavior.

---

## Current repository layout

```text
otp-relay-k8s/
├── .github/
│   └── workflows/
│       └── deploy-k3s.yml
├── docs/
│   ├── README.md
│   ├── architecture/
│   │   ├── diagrams/
│   │   ├── kubernetes-architecture-plan.md
│   │   └── sch-target-architecture-gap-analysis.md
│   ├── archive/
│   │   └── historical-phase-notes/
│   ├── deployment/
│   │   ├── github-actions-deployment-guide.md
│   │   ├── k3s-setup-and-operations-guide.md
│   │   ├── manual-image-build-and-deployment-fallback.md
│   │   └── nfs-shared-storage-migration-guide.md
│   ├── development/
│   │   ├── docker-image-build-guide.md
│   │   └── dockerfile-design-background-notes.md
│   ├── help/
│   ├── operations/
│   │   └── phase-3-resilience-validation-report.md
│   └── validation/
│       └── phase-2-loadbalancer-and-redis-alignment-report.md
├── frontend/
│   ├── app.jsx
│   ├── guide.html
│   ├── index.html
│   └── style.css
├── k8s/
│   ├── Dockerfile
│   ├── Dockerfile.monitor
│   └── manifests/
├── scripts/
│   ├── build_help_docs.py
│   └── generate_sample_users.py
├── .dockerignore
├── .gitignore
├── LICENSE
├── README.md
├── install-otp-relay-k8s.sh
├── main.py
├── monitor.py
├── package-lock.json
├── package.json
└── requirements.txt
```

Documentation lives under `docs/`. Kubernetes runtime assets live under `k8s/`. The old nested `k8s/docs/` path should not be restored.

---

## Kubernetes manifests

The app deployment is described by committed Kubernetes manifests under `k8s/manifests/`.

Core manifests:

```text
namespace.yaml
configmap.yaml
secret-example.env
pvc.yaml
pv-nfs.yaml
deployment.yaml
deployment-monitor.yaml
service.yaml
ingress.yaml
```

Redis manifests:

```text
redis-configmap.yaml
redis-service.yaml
redis-statefulset.yaml
redis-pdb.yaml
redis-sentinel-configmap.yaml
redis-sentinel-deployment.yaml
redis-sentinel-service.yaml
redis-haproxy-configmap.yaml
redis-haproxy-deployment.yaml
```

The installer may render runtime values, but the committed manifests and Dockerfiles remain the source of truth.

---

## Deployment source of truth

Deployment assets come from GitHub:

```text
k8s/Dockerfile
k8s/Dockerfile.monitor
k8s/manifests/*.yaml
install-otp-relay-k8s.sh
.github/workflows/deploy-k3s.yml
```

The installer stages committed files into a temporary render directory, applies environment/runtime values, deploys them to the cluster, and cleans up the temporary directory.

Do not manually edit deployment files under `/opt/otp-relay-k8s` except for emergency recovery. The installer resets the checkout to `origin/main` during deployment.

---

## Phase history

### Phase 1 — K3s single-replica baseline

Phase 1 proved the portal could run in K3s with the same basic behavior as the VM deployment.

Validated concepts:

- App Docker image.
- Monitor Docker image.
- Single app Deployment with `replicas: 1`.
- PVC mounted at `/app/data`.
- ConfigMap/Secret separation.
- Basic health/readiness endpoints.
- NodePort/Ingress access path.
- Help docs generation.

Phase 1 deliberately avoided Redis, horizontal app scaling, and multi-node assumptions.

### Phase 2 — MetalLB, GitHub source of truth, and Redis shared state

Phase 2 aligned the deployment with the bare-metal Kubernetes direction.

Major changes:

- GitHub main branch became the deployment source of truth.
- GitHub Actions self-hosted runner deployment path was introduced.
- Committed Dockerfiles/manifests replaced hidden installer-generated definitions.
- Service exposure moved toward MetalLB LoadBalancer behavior.
- Redis was added for OTP runtime state.
- Admin sessions and admin login-attempt tracking moved to Redis.
- `/readyz` reports Redis status and fails when `REDIS_REQUIRED=1` and Redis is unavailable.
- Temporary two-replica validation proved the app pods can become healthy with Redis-backed state.

Remaining Phase 2 acceptance items:

```text
Manager-led live OTP trigger test
Pending OTP restart-survival test during a real OTP flow
Final two-replica OTP flow validation
```

### Phase 3 — SCH-alignment validation baseline

Phase 3 focuses on production-style alignment inside one Kubernetes cluster.

Validated/current direction:

- 3-node K3s target architecture.
- MetalLB LoadBalancer service exposure.
- Traefik HTTPS validation path.
- Self-signed TLS retained until IT distributes/trusts the certificate by Group Policy.
- Redis required for readiness.
- NFS/RWX app storage path added.
- Monitor remains isolated and required.
- App remains at one replica until final OTP and storage validation is complete.

Current safe controls:

```text
REPLICA_COUNT=1
strategy: Recreate
REDIS_REQUIRED=1
```

These controls prevent the deployment from claiming high availability before shared storage, OTP behavior, and Redis HA behavior are fully validated.

---

## Why the app still stays at one live replica

The original blocker was process-local OTP/admin state. That part has been addressed with Redis.

The current reason to keep the live app at one replica is more specific:

1. Final manager-led OTP acceptance is still pending.
2. Pending OTP restart-survival must be proven during a real OTP flow.
3. Final two-replica OTP flow validation must be completed.
4. App data must be on NFS/RWX before the app is treated as movable across worker nodes.
5. Redis HA/Sentinel/HAProxy behavior must be accepted before Redis stops being a single-instance dependency.

Until those are complete, `REPLICA_COUNT=1` is the correct production-safe validation posture.

---

## Validation checklist

Current validation should focus on these items, in order:

1. Confirm the consolidated documentation paths are correct.
2. Confirm GitHub Actions deploys from the current repo structure.
3. Confirm `/healthz` returns OK.
4. Confirm `/readyz` returns Redis OK with `REDIS_REQUIRED=1`.
5. Confirm user token login from `users.xlsx`.
6. Confirm admin login and admin session behavior.
7. Confirm admin login-attempt lockout behavior.
8. Confirm OTP claim flow.
9. Confirm SMS POST to `/sms-received`.
10. Confirm OTP appears on screen and expires correctly.
11. Confirm no OTP values are written to disk or audit logs.
12. Confirm app pod restart behavior during normal idle operation.
13. Confirm pending OTP behavior during app pod restart.
14. Confirm NFS-backed `/app/data` after migration.
15. Confirm final two-replica OTP flow.
16. Confirm Redis failure behavior and readiness failure.
17. Confirm monitor pod behavior and WhatsApp alert path.

---

## Production-alignment gaps

The remaining production-alignment gaps are:

```text
Final manager OTP validation
Pending OTP restart-survival validation
Final two-replica OTP flow validation
Live app PVC migration to NFS/RWX
Redis HA/Sentinel/HAProxy production decision
Trusted TLS distribution through IT Group Policy
Node placement and drain validation
Operational runbook completion
Monitoring/logging review
```

Track the active gap table in:

```text
docs/architecture/sch-target-architecture-gap-analysis.md
```

---

## Future direction

### Near-term

- Complete final OTP acceptance testing.
- Complete NFS/RWX app data migration.
- Validate app restart and pending OTP behavior.
- Validate final two-replica OTP flow.
- Confirm TLS trust path with IT.

### Medium-term

- Decide whether Redis Sentinel/HAProxy is sufficient or whether a managed/approved Redis HA pattern is required.
- Add stronger monitoring and alerting.
- Validate node drain behavior.
- Formalize backup/restore procedures for app data and Redis state.

### Later / optional

- Helm packaging, if the deployment needs reusable install profiles.
- HPA only after metrics and multi-replica behavior are accepted.
- Warm standby or DR procedure for a second data centre.
- Active/active only if the application is deliberately redesigned for distributed coordination.

---

## Practical rule

The project has moved beyond the original Phase 1 learning plan. Do not restore old assumptions such as `k8s/docs/`, in-memory-only OTP state, or "Redis later" language.

The current rule is:

```text
Keep the live deployment conservative while validating the SCH target architecture step by step.
```

That means:

```text
Redis required
NFS/RWX target app storage
Traefik HTTPS validation path
One live app replica until final OTP/storage/Redis validation is complete
GitHub repo remains the source of truth
```
