# OTP Relay Kubernetes

Kubernetes/K3s deployment for the OTP Relay Portal.

This repository contains the FastAPI portal, the required monitor service, the React frontend source, help-documentation source, Kubernetes manifests, Dockerfiles, and the installer used by GitHub Actions to deploy onto a K3s server or cluster.

---

## Deployment phases

This README intentionally separates **Phase 1** and **Phase 2** so reviewers can see what was already deployed and what changed for the Phase 2 deployment model.

### Phase 1 - deployed baseline

Phase 1 deployed the OTP Relay portal on K3s as a single-server/single-node workload.

Phase 1 characteristics:

```text
GitHub main branch
  ↓
GitHub Actions workflow
  ↓
self-hosted runner on the K3s server
  ↓
install-otp-relay-k8s.sh
  ↓
local Docker build → K3s image import → kubectl apply
```

Phase 1 exposure model:

```text
SERVICE_TYPE=NodePort
SERVICE_NODE_PORT=30080
INGRESS_ENABLED=1
INSTALL_METALLB=0
REPLICA_COUNT=1
```

Phase 1 routes:

```text
http://<server-ip>/        # Traefik ingress
http://<server-ip>:30080/  # NodePort fallback
```

Phase 1 runtime state:

```text
/app/data/users.xlsx
/app/data/admin_auth.json
/app/data/admin_config.json
/app/data/wizard_progress.json
/app/data/audit.log
```

The application stayed at one replica because OTP queue state, pending OTPs, and admin sessions are still process-memory state.

---

### Phase 2 - LoadBalancer / MetalLB / source-of-truth deployment

Phase 2 aligns the deployment with the 3-node/bare-metal Kubernetes diagram discussed with management.

Phase 2 target flow:

```text
GitHub main branch
  ↓
GitHub Actions workflow
  ↓
self-hosted runner on the K3s server/cluster node
  ↓
install-otp-relay-k8s.sh
  ↓
repo Dockerfiles + repo Kubernetes manifests
  ↓
local Docker build → K3s image import → rendered repo manifests → kubectl apply
  ↓
K3s Service type LoadBalancer
  ↓
MetalLB assigns portal IP from LAN pool
```

Phase 2 exposure model:

```text
SERVICE_TYPE=LoadBalancer
LOADBALANCER_IP=
INGRESS_ENABLED=0
INSTALL_METALLB=0
REQUIRE_METALLB=1
PVC_STORAGE_CLASS=local-path
PVC_SIZE=1Gi
REPLICA_COUNT=1
```

Notes:

- `LOADBALANCER_IP` is intentionally blank so MetalLB auto-assigns an address from its configured pool.
- `INGRESS_ENABLED=0` means OTP Relay does not use Traefik in Phase 2. Traefik may still exist in K3s, but it is not the OTP Relay exposure path.
- `REQUIRE_METALLB=1` makes deployment fail fast if LoadBalancer mode is selected but MetalLB is not available.
- `REPLICA_COUNT=1` remains required until OTP queue, pending OTPs, and admin sessions are moved to shared state.

Phase 2 changed the deployment source-of-truth model:

```text
k8s/Dockerfile                  # app image source of truth
k8s/Dockerfile.monitor          # monitor image source of truth
k8s/manifests/*.yaml            # Kubernetes object source of truth
install-otp-relay-k8s.sh        # orchestrates, renders runtime values, applies
.github/workflows/deploy-k3s.yml # chooses deployment mode and invokes installer
```

The installer no longer owns hidden Dockerfile/YAML definitions. It stages committed repo files into `/tmp`, renders runtime values there, applies them, and cleans up the temporary staging directory.

---

## What changed in Phase 2

Phase 2 added or corrected the following areas:

| Area | Phase 1 | Phase 2 |
|---|---|---|
| Service exposure | NodePort and Traefik ingress | LoadBalancer service through MetalLB |
| Portal IP | server IP / NodePort | MetalLB-assigned `EXTERNAL-IP` |
| `LOADBALANCER_IP` | not used | blank by default for auto-assignment |
| Ingress | enabled | disabled for OTP Relay by default |
| Manifests | installer-generated YAML | committed `k8s/manifests/*.yaml` are source of truth |
| Dockerfiles | installer-generated Dockerfiles | committed `k8s/Dockerfile*` are source of truth |
| PVC | persistent app data | PVC storage class preserved safely across deploys |
| Rollout strategy | default/rolling behavior | `Recreate` for single-replica RWO PVC safety |
| Deployment restarts | multiple restart points possible | coalesced restart requests, one restart per deployment |
| Wizard progress | could lock to stale browser client | token-owned progress with silent client rebinding |
| Workflow modes | deployment-system changes could force full rebuild | manifests-only changes avoid unnecessary image rebuilds |

---

## What the app does

The OTP Relay Portal lets users claim a single active OTP slot, trigger the external OTP only when they are first in queue, and view the received OTP on-screen.

OTP values are held in memory only. They are never written to disk or audit logs.

The portal includes:

- token login from `users.xlsx` through `POST /user/login`
- admin dashboard and admin credential setup/login
- admin upload for `users.xlsx`
- admin token configuration saved in `admin_config.json`
- wizard progress saved in `wizard_progress.json`
- audit log at `audit.log`
- generated help documentation
- required monitor deployment for phone presence and WhatsApp alerts

---

## Runtime design constraint

Keep the portal deployment at one replica for now:

```text
REPLICA_COUNT=1
```

The OTP queue, pending OTPs, and admin sessions are currently stored in process memory. Multiple replicas would create separate queues and sessions and could route a user to the wrong in-memory state.

A 3-node cluster is supported for placement and LoadBalancer exposure, but the app remains a single-replica workload until shared state is introduced.

---

## Repository structure

```text
otp-relay-k8s/
├── .github/
│   └── workflows/
│       └── deploy-k3s.yml
├── docs/
│   ├── diagrams/
│   │   ├── phase-map.svg
│   │   └── phase1-architecture.svg
│   └── k8s-plan.md
├── frontend/
│   ├── app.jsx
│   ├── guide.html
│   ├── index.html
│   └── style.css
├── k8s/
│   ├── Dockerfile
│   ├── Dockerfile.monitor
│   ├── docs/
│   └── manifests/
│       ├── configmap.yaml
│       ├── deployment-monitor.yaml
│       ├── deployment.yaml
│       ├── namespace.yaml
│       ├── pvc.yaml
│       ├── secret-example.env
│       └── service.yaml
├── scripts/
│   ├── build_help_docs.py
│   └── generate_sample_users.py
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

Generated files such as `frontend/app.js`, `frontend/help/`, `node_modules/`, and rendered deployment files under `/tmp` are not source files.

---

## Deployment source of truth

The GitHub repository is the source of truth for deployment assets.

The installer uses committed files:

```text
k8s/Dockerfile
k8s/Dockerfile.monitor
k8s/manifests/*.yaml
```

The installer stages those files into a temporary render directory and applies runtime values such as:

```text
NAMESPACE
APP_IMAGE
MONITOR_IMAGE
SERVICE_TYPE
LOADBALANCER_IP
PVC_STORAGE_CLASS
PVC_SIZE
REPLICA_COUNT
APP_NODE_SELECTOR_KEY / APP_NODE_SELECTOR_VALUE
MONITOR_NODE_SELECTOR_KEY / MONITOR_NODE_SELECTOR_VALUE
PHONE_IP
PHONE_INTERFACE
PORTAL_URL
```

Do not manually edit deployment files under `/opt/otp-relay-k8s` except for emergency recovery. The installer resets that checkout to `origin/main` on deployment.

Do not edit generated files under `/tmp`. Commit source changes to GitHub instead.

---

## Deployment modes

### Phase 1 / single-server compatibility mode

Use this only when you need the original single-server NodePort/Ingress behavior:

```text
SERVICE_TYPE=NodePort
SERVICE_NODE_PORT=30080
INGRESS_ENABLED=1
INSTALL_METALLB=0
REQUIRE_METALLB=0
REPLICA_COUNT=1
```

Routes:

```text
http://<server-ip>/        # Traefik ingress
http://<server-ip>:30080/  # NodePort fallback
```

### Phase 2 / LoadBalancer mode

Recommended Phase 2 values:

```text
SERVICE_TYPE=LoadBalancer
LOADBALANCER_IP=
INGRESS_ENABLED=0
INSTALL_METALLB=0
REQUIRE_METALLB=1
PVC_STORAGE_CLASS=local-path
PVC_SIZE=1Gi
REPLICA_COUNT=1
```

Use `INSTALL_METALLB=1` only when the installer should install/configure MetalLB itself:

```text
INSTALL_METALLB=1
METALLB_IP_RANGE=172.31.11.120-172.31.11.130
METALLB_POOL_NAME=otp-relay-pool
```

Optional node placement:

```text
APP_NODE_SELECTOR_KEY=kubernetes.io/hostname
APP_NODE_SELECTOR_VALUE=<app-node-name>
MONITOR_NODE_SELECTOR_KEY=kubernetes.io/hostname
MONITOR_NODE_SELECTOR_VALUE=<phone-network-node-name>
```

With K3s `local-path` storage, pin the app pod to the node where the PVC should live. The monitor should be pinned to the node that can see the phone network/interface used by `arping`.

---

## MetalLB operations

Phase 2 uses a Kubernetes `LoadBalancer` service. On bare-metal K3s this requires MetalLB or another load balancer implementation.

Check MetalLB namespace and pods:

```bash
sudo k3s kubectl get namespace metallb-system
sudo k3s kubectl get pods -n metallb-system -o wide
```

Expected components include:

```text
controller
speaker
```

Check MetalLB address pools:

```bash
sudo k3s kubectl get ipaddresspool -n metallb-system
sudo k3s kubectl get l2advertisement -n metallb-system
sudo k3s kubectl describe ipaddresspool -n metallb-system
sudo k3s kubectl describe l2advertisement -n metallb-system
```

Check the OTP Relay LoadBalancer service:

```bash
sudo k3s kubectl get svc otp-relay -n otp-relay -o wide
```

Expected Phase 2 service shape:

```text
NAME        TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)
otp-relay   LoadBalancer   <cluster-ip>     <assigned-ip>    80:<node-port>/TCP
```

Get only the assigned LoadBalancer IP:

```bash
sudo k3s kubectl get svc otp-relay -n otp-relay -o jsonpath='{.status.loadBalancer.ingress[0].ip}'; echo
```

Check that `PORTAL_URL` was updated from the assigned IP:

```bash
sudo k3s kubectl get configmap otp-relay-config -n otp-relay -o jsonpath='{.data.PORTAL_URL}'; echo
```

Expected:

```text
http://<assigned-loadbalancer-ip>
```

Check MetalLB logs:

```bash
sudo k3s kubectl logs -n metallb-system deployment/controller
sudo k3s kubectl logs -n metallb-system daemonset/speaker
```

If `EXTERNAL-IP` stays pending:

```bash
sudo k3s kubectl describe svc otp-relay -n otp-relay
sudo k3s kubectl get pods -n metallb-system -o wide
sudo k3s kubectl get ipaddresspool -n metallb-system -o yaml
```

Confirm the configured MetalLB IP range is free on the LAN and outside DHCP assignment.

---

## GitHub Actions deployment

Workflow:

```text
.github/workflows/deploy-k3s.yml
```

The workflow runs the installer from the checked-out commit:

```bash
sudo -n -E /usr/bin/bash "$GITHUB_WORKSPACE/install-otp-relay-k8s.sh"
```

Required repository secrets:

```text
PHONE_IP
PHONE_INTERFACE
WHATSAPP_API_KEY
WHATSAPP_RECIPIENT
```

`PORTAL_URL` should normally be left unset for Phase 2 auto-detection. If `PORTAL_URL` is explicitly supplied, the installer preserves that value and does not replace it with the MetalLB-assigned IP.

Manual workflow dispatch can override service type, MetalLB install, LoadBalancer IP, node selectors, PVC storage class, PVC size, ingress, and deployment mode.

Deployment mode behavior:

```text
main.py / frontend / requirements / k8s/Dockerfile       → app rebuild
monitor.py / k8s/Dockerfile.monitor                     → monitor rebuild
k8s/manifests / installer / workflow deployment changes  → manifests deploy
README/docs-only changes                                 → no deployment
```

Manual override can still force `full`, `app`, `monitor`, `manifests`, or `none`.

---

## One-time runner bootstrap

Create a runner token in GitHub:

```text
Repository → Settings → Actions → Runners → New self-hosted runner
```

Then run once on the server:

```bash
sudo INSTALL_GITHUB_RUNNER=1 \
  RUNNER_ONLY=1 \
  GITHUB_RUNNER_URL="https://github.com/psi1703/k8s" \
  GITHUB_RUNNER_TOKEN="PASTE_RUNNER_TOKEN_HERE" \
  NONINTERACTIVE=1 \
  bash install-otp-relay-k8s.sh
```

After this, push to `main` or use manual workflow dispatch.

---

## Frontend build

The browser loads:

```text
frontend/app.js
```

The source is:

```text
frontend/app.jsx
```

The installer runs the frontend build when the app image is rebuilt:

```bash
npm ci
npm run build:frontend
```

Do not commit `frontend/app.js`, `frontend/app.raw.js`, `node_modules/`, or `frontend/help/` unless the project explicitly changes that policy.

---

## Runtime data

Runtime data is stored on the PVC mounted at:

```text
/app/data
```

The PVC stores:

```text
users.xlsx
admin_auth.json
admin_config.json
wizard_progress.json
audit.log
```

Preferred user import flow:

```text
Admin dashboard → Upload users.xlsx → /app/data/users.xlsx → immediate reload
```

Manual fallback:

```bash
POD="$(sudo k3s kubectl get pod -n otp-relay -l app=otp-relay -o jsonpath='{.items[0].metadata.name}')"
sudo k3s kubectl cp ./users.xlsx "otp-relay/$POD:/app/data/users.xlsx" -n otp-relay
sudo k3s kubectl rollout restart deployment/otp-relay -n otp-relay
```

Do not delete the PVC during repo cleanup or reinstall work.

---

## Wizard progress ownership

Wizard progress is persisted in:

```text
/app/data/wizard_progress.json
```

The progress record is owned by the user token. The browser/client secret is only a background edit binding marker. If the same valid token opens the wizard from a new browser/client, the backend silently rebinds that record and continues without showing a reclaim message to the user.

This avoids stale PVC-persisted browser ownership from blocking the RTA Wizard after redeployments or browser changes.

---

## Required monitor

The monitor is required. It:

- checks phone presence using `arping`
- reads the shared `audit.log` from the PVC
- sends WhatsApp alerts using `WHATSAPP_API_KEY` and `WHATSAPP_RECIPIENT`

It uses:

```yaml
hostNetwork: true
dnsPolicy: ClusterFirstWithHostNet
securityContext:
  capabilities:
    add:
      - NET_RAW
```

It must not be exposed through a Service or Ingress.

---

## Verify deployment

General checks:

```bash
sudo k3s kubectl get pods,svc,pvc,ingress -n otp-relay
sudo k3s kubectl rollout status deployment/otp-relay -n otp-relay
sudo k3s kubectl rollout status deployment/otp-monitor -n otp-relay
sudo k3s kubectl get configmap otp-relay-config -n otp-relay -o yaml
```

Phase 2 checks:

```bash
sudo k3s kubectl get svc otp-relay -n otp-relay -o wide
sudo k3s kubectl get svc otp-relay -n otp-relay -o jsonpath='{.status.loadBalancer.ingress[0].ip}'; echo
sudo k3s kubectl get configmap otp-relay-config -n otp-relay -o jsonpath='{.data.PORTAL_URL}'; echo
curl -i http://<assigned-loadbalancer-ip>/readyz
```

Check that the running deployment uses the expected runtime shape:

```bash
sudo k3s kubectl get deploy otp-relay -n otp-relay -o jsonpath='{.spec.strategy.type}'; echo
sudo k3s kubectl get deploy otp-relay -n otp-relay -o jsonpath='{.spec.replicas}'; echo
sudo k3s kubectl get pvc otp-relay-data -n otp-relay -o jsonpath='{.spec.storageClassName}'; echo
sudo k3s kubectl get svc otp-relay -n otp-relay -o jsonpath='{.spec.type}'; echo
```

Expected Phase 2 values:

```text
Recreate
1
local-path
LoadBalancer
```

---

## Clean repo verification on server

The working tree under `/opt/otp-relay-k8s` should remain clean after deployment.

```bash
cd /opt/otp-relay-k8s
git remote -v
git branch --show-current
git rev-parse HEAD
git status --short
```

Expected:

```text
main
# no modified tracked files
```

Python cache files should not be committed. `.gitignore` should include:

```text
__pycache__/
*.py[cod]
```

---

## Git hygiene

Do not commit runtime/build artifacts:

```text
.env
data/
*.log
.installer-venv/
node_modules/
frontend/app.js
frontend/app.raw.js
frontend/help/
__pycache__/
*.py[cod]
*.tar
*.tar.gz
```

After deployment, the installer checks that `/opt/otp-relay-k8s` is clean.
