# OTP Relay Kubernetes

Kubernetes/K3s deployment for the OTP Relay Portal.

This repository contains the FastAPI portal, the required monitor service, the React frontend source, help-documentation source, and the installer used by GitHub Actions to deploy onto a K3s server or cluster.

The repository is the source of truth:

```text
GitHub main branch
  ↓
GitHub Actions workflow
  ↓
self-hosted runner on the K3s server/cluster node
  ↓
install-otp-relay-k8s.sh
  ↓
Docker local build → K3s image import → generated manifests → kubectl apply
```

Do not manually edit deployment files under `/opt/otp-relay-k8s` except for emergency recovery. The installer resets that checkout to `origin/main` on deployment.

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
├── main.py
├── monitor.py
├── requirements.txt
├── package.json
├── package-lock.json
├── install-otp-relay-k8s.sh
├── .github/workflows/deploy-k3s.yml
├── frontend/
│   ├── index.html
│   ├── app.jsx
│   ├── guide.html
│   └── style.css
├── docs/
│   ├── operations/
│   └── help/
├── scripts/
│   ├── build_help_docs.py
│   └── generate_sample_users.py
└── k8s/
    ├── docs/
    └── manifests/
```

Generated files such as `frontend/app.js`, `frontend/help/`, `node_modules/`, and deployment manifests generated under `/tmp` are not source files.

---

## Deployment modes

### Default single-server mode

The default mode is compatible with the current Debian K3s server:

```text
SERVICE_TYPE=NodePort
SERVICE_NODE_PORT=30080
INGRESS_ENABLED=1
INSTALL_METALLB=0
REPLICA_COUNT=1
```

Routes:

```text
http://<server-ip>/        # Traefik ingress
http://<server-ip>:30080/  # NodePort fallback
```

### 3-node / LoadBalancer mode

For manager-style bare-metal cluster alignment, run with LoadBalancer support:

```text
SERVICE_TYPE=LoadBalancer
INGRESS_ENABLED=0
INSTALL_METALLB=1
REQUIRE_METALLB=1
METALLB_IP_RANGE=172.31.11.120-172.31.11.130
LOADBALANCER_IP=172.31.11.120
REPLICA_COUNT=1
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

## MetalLB

The installer can optionally install and configure MetalLB:

```text
INSTALL_METALLB=1
METALLB_IP_RANGE=172.31.11.120-172.31.11.130
METALLB_POOL_NAME=otp-relay-pool
```

The IP range must be free on the LAN and outside DHCP assignment. If MetalLB is managed separately, leave `INSTALL_METALLB=0` and set `REQUIRE_METALLB=1` to fail fast if the cluster is not ready for `LoadBalancer` services.

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
PORTAL_URL
```

Manual workflow dispatch can override service type, MetalLB install, LoadBalancer IP, node selectors, PVC storage class, and deployment mode.

---

## One-time runner bootstrap

Create a runner token in GitHub:

```text
Repository → Settings → Actions → Runners → New self-hosted runner
```

Then run once on the server:

```bash
sudo INSTALL_GITHUB_RUNNER=1   RUNNER_ONLY=1   GITHUB_RUNNER_URL="https://github.com/psi1703/k8s"   GITHUB_RUNNER_TOKEN="PASTE_RUNNER_TOKEN_HERE"   NONINTERACTIVE=1   bash install-otp-relay-k8s.sh
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

The installer runs:

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

```bash
sudo k3s kubectl get pods,svc,ingress -n otp-relay
sudo k3s kubectl rollout status deployment/otp-relay -n otp-relay
sudo k3s kubectl rollout status deployment/otp-monitor -n otp-relay
curl -i http://127.0.0.1/
curl -i http://127.0.0.1:30080/
curl -i http://127.0.0.1:30080/readyz
```

For LoadBalancer mode:

```bash
sudo k3s kubectl get svc -n otp-relay otp-relay
```

Confirm `EXTERNAL-IP` is assigned.

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
*.tar
*.tar.gz
```

After deployment, the installer checks that `/opt/otp-relay-k8s` is clean.
