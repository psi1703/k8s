# OTP Relay Kubernetes

Kubernetes/K3s deployment for the OTP Relay Portal.

This repository contains the containerized OTP Relay Portal, the required monitor service, Kubernetes manifests, and the installer used by GitHub Actions to deploy to the K3s server.

The current deployment model is:

```text
GitHub main branch
  ↓
GitHub Actions workflow
  ↓
Self-hosted runner on the K3s server
  ↓
install-otp-relay-k8s.sh
  ↓
Docker local build → K3s image import → kubectl apply
```

The GitHub repository is the source of truth. After the self-hosted runner is installed, edit files in GitHub/local Git and push to `main`; do not manually edit deployment files under `/opt/otp-relay-k8s` except for emergency recovery.

---

## What the app does

The OTP Relay Portal lets users claim a single active OTP slot, trigger the external OTP only when they are first in queue, and view the received OTP on-screen.

OTP values are kept in memory only. They are never written to disk or audit logs.

The portal includes:

- user token login from `users.xlsx`
- admin dashboard
- admin credential setup/login
- admin upload for `users.xlsx`
- admin token configuration saved in `admin_config.json`
- wizard progress saved in `wizard_progress.json`
- audit log at `audit.log`
- generated help documentation served from the frontend
- required monitor deployment for phone presence and WhatsApp alerts

---

## Important runtime design constraints

Keep the portal deployment at one replica for now:

```text
replicas: 1
```

The OTP queue and admin sessions are currently stored in process memory. Multiple replicas of the same portal would create separate in-memory queues and sessions, so OTP verification could fail if different requests are routed to different pods.

Safe current model:

```text
one portal instance → one app pod → one PVC → one in-memory OTP state
```

Multiple separate portals are possible later by deploying isolated namespaces/PVCs/Ingress hosts, but each portal should still run one app replica until OTP state is moved to Redis, a database, or another shared backend.

---

## Repository structure

```text
otp-relay-k8s/
├── main.py
├── monitor.py
├── requirements.txt
├── install-otp-relay-k8s.sh
├── .github/
│   └── workflows/
│       └── deploy-k3s.yml
├── frontend/
│   ├── index.html
│   ├── app.jsx
│   ├── guide.html
│   ├── style.css
│   └── help/
├── docs/
│   ├── operations/
│   │   └── github-actions-deploy.md
│   └── help/
├── scripts/
│   ├── build_help_docs.py
│   └── generate_sample_users.py
├── k8s/
│   ├── Dockerfile
│   ├── Dockerfile.monitor
│   ├── docs/
│   └── manifests/
│       ├── namespace.yaml
│       ├── configmap.yaml
│       ├── pvc.yaml
│       ├── deployment.yaml
│       ├── deployment-monitor.yaml
│       ├── service.yaml
│       ├── ingress.yaml
│       └── secret-example.env
└── README.md
```

---

## Deployment method

The preferred deployment method is GitHub Actions with a self-hosted runner installed on the same server that runs K3s.

The workflow file is:

```text
.github/workflows/deploy-k3s.yml
```

The workflow should run the checked-out installer from the GitHub workspace, not an old server-side copy:

```bash
chmod +x "$GITHUB_WORKSPACE/install-otp-relay-k8s.sh"
sudo -n -E /usr/bin/bash "$GITHUB_WORKSPACE/install-otp-relay-k8s.sh"
```

This ensures every deployment uses the installer version from the commit that triggered the workflow.

---

## One-time server bootstrap

The self-hosted runner must be installed once before GitHub Actions can deploy to the server.

In GitHub, create a runner token from:

```text
Repository → Settings → Actions → Runners → New self-hosted runner → Linux → x64
```

Then run the installer once on the server with runner setup enabled:

```bash
sudo INSTALL_GITHUB_RUNNER=1 \
  RUNNER_ONLY=1 \
  GITHUB_RUNNER_URL="https://github.com/psi1703/k8s" \
  GITHUB_RUNNER_TOKEN="PASTE_RUNNER_TOKEN_HERE" \
  NONINTERACTIVE=1 \
  bash install-otp-relay-k8s.sh
```

`RUNNER_ONLY=1` registers the GitHub Actions runner and exits before Docker, K3s, image builds, or Kubernetes deployment work.

After this step, confirm the runner is online in GitHub:

```text
Repository → Settings → Actions → Runners
```

The runner should show as online/idle.

---

## Runner sudo requirement

GitHub Actions runs as the runner service user, usually:

```text
actions-runner
```

That user must be allowed to run the installer without a password. The installer attempts to create a narrow sudoers rule during runner setup.

If sudo fails in GitHub Actions with:

```text
sudo: a terminal is required to read the password
```

validate the runner user:

```bash
ps -ef | grep '[R]unner.Listener'
ps -o user= -p <Runner.Listener PID>
```

Then add or correct the sudoers rule with `visudo`:

```sudoers
actions-runner ALL=(root) NOPASSWD:SETENV: /usr/bin/bash /opt/actions-runner/_work/k8s/k8s/install-otp-relay-k8s.sh
```

Validate before closing the terminal:

```bash
sudo visudo -c
```

The workflow uses `sudo -n` so it fails immediately if sudoers is wrong instead of waiting for a password prompt.

---

## GitHub Actions secrets

Create these repository secrets before running the deployment workflow:

```text
PHONE_IP
PHONE_INTERFACE
WHATSAPP_API_KEY
WHATSAPP_RECIPIENT
PORTAL_URL
```

Path:

```text
Repository → Settings → Secrets and variables → Actions → New repository secret
```

Example non-secret values:

```text
PHONE_IP=172.31.10.161
PHONE_INTERFACE=eth0
PORTAL_URL=http://server-ip-or-dns
```

Do not commit WhatsApp credentials to Git.

---

## GitHub Actions workflow environment

The deploy workflow should pass the standard deployment environment to the installer:

```yaml
env:
  REPO_URL: https://github.com/psi1703/k8s.git
  REPO_REF: main
  INSTALL_DIR: /opt/otp-relay-k8s
  NAMESPACE: otp-relay
  APP_IMAGE: otp-relay:latest
  MONITOR_IMAGE: otp-monitor:latest
  SERVICE_NODE_PORT: "30080"
  INGRESS_ENABLED: "1"
  NONINTERACTIVE: "1"
  GIT_CLEAN: "1"
  PHONE_IP: ${{ secrets.PHONE_IP }}
  PHONE_INTERFACE: ${{ secrets.PHONE_INTERFACE }}
  WHATSAPP_API_KEY: ${{ secrets.WHATSAPP_API_KEY }}
  WHATSAPP_RECIPIENT: ${{ secrets.WHATSAPP_RECIPIENT }}
  PORTAL_URL: ${{ secrets.PORTAL_URL }}
```

Recommended runner target:

```yaml
runs-on:
  - self-hosted
  - Linux
  - X64
```

---

## Installer behavior

The installer is the deployment source of truth. It performs the following work:

1. Runs non-invasive preflight checks.
2. Installs base packages with `apt-get`.
3. Installs or validates the GitHub Actions runner if requested.
4. Exits early if `RUNNER_ONLY=1`.
5. Installs deployment packages.
6. Ensures Docker is available for local image builds.
7. Installs K3s if missing.
8. Syncs `/opt/otp-relay-k8s` to `origin/main`.
9. Builds help docs from `docs/help` into `frontend/help`.
10. Builds the app image locally with Docker.
11. Imports the app image into K3s containerd.
12. Builds the monitor image locally with Docker.
13. Imports the monitor image into K3s containerd.
14. Applies Kubernetes resources.
15. Restarts and waits for the app and monitor rollouts.

The installer is designed to avoid unrelated host changes. It does not intentionally:

- modify SSH configuration
- stop unrelated services
- edit firewall rules
- modify cron jobs
- delete non-repository directories
- change CIFS mounts

Network and firewall snapshots are saved under:

```text
/var/backups/otp-relay-k8s/
```

---

## Git sync behavior

On every full deployment, the installer syncs the server checkout to GitHub:

```bash
git fetch --prune origin main
git reset --hard origin/main
git clean -ffd
```

This means:

```text
commit + push first, then deploy
```

Do not manually place application changes only on the server. They will be removed by the next clean deployment.

To temporarily disable cleanup during emergency debugging:

```bash
sudo GIT_CLEAN=0 bash install-otp-relay-k8s.sh
```

---

## Docker and K3s image flow

This repo does not require Docker Hub or an external container registry.

Images are built locally on the server:

```text
Docker build on server
  ↓
docker save
  ↓
k3s ctr images import
  ↓
Kubernetes rollout restart
```

Images:

```text
otp-relay:latest
otp-monitor:latest
```

Docker is required on the server for this build/import flow.

---

## Kubernetes resources

Default namespace:

```text
otp-relay
```

Default deployments:

```text
deployment/otp-relay
deployment/otp-monitor
```

Default PVC:

```text
otp-relay-data
```

Default service shape:

```text
service/otp-relay   NodePort   80:30080/TCP
```

Default ingress:

```text
ingress/otp-relay   Traefik   port 80
```

Primary route:

```text
http://<server-ip>/
```

Fallback route:

```text
http://<server-ip>:30080/
```

Traffic flow:

```text
Browser
  ↓
Traefik on port 80
  ↓
Ingress otp-relay
  ↓
Service otp-relay
  ↓
Pod otp-relay:8000
```

NodePort fallback flow:

```text
Browser on port 30080
  ↓
Service otp-relay
  ↓
Pod otp-relay:8000
```

---

## Runtime data

Runtime data is stored on the Kubernetes PVC mounted at:

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

Runtime data must not be committed to Git.

---

## Loading users.xlsx

Preferred method: upload from the portal admin UI.

Flow:

```text
Admin dashboard → Upload users.xlsx → file saved to /app/data/users.xlsx → users reload immediately
```

The upload feature validates that:

- the uploaded file is `.xlsx`
- the workbook can be opened
- required columns exist
- upload activity is recorded in `audit.log`

Manual fallback if the portal is not usable yet:

```bash
POD=$(sudo k3s kubectl get pod -n otp-relay -l app=otp-relay -o jsonpath='{.items[0].metadata.name}')
sudo k3s kubectl cp ./users.xlsx otp-relay/$POD:/app/data/users.xlsx -n otp-relay
sudo k3s kubectl rollout restart deployment/otp-relay -n otp-relay
```

After the upload feature is deployed, manual `kubectl cp` should only be needed for recovery or first-time emergency setup.

---

## Required monitor deployment

The monitor is a required deployment in this Kubernetes version.

It:

- checks phone presence using `arping`
- reads the shared `audit.log` from the PVC
- sends WhatsApp alerts using `WHATSAPP_API_KEY` and `WHATSAPP_RECIPIENT`

The monitor requires:

```yaml
hostNetwork: true
dnsPolicy: ClusterFirstWithHostNet
securityContext:
  capabilities:
    add:
      - NET_RAW
```

The monitor must not be exposed through a Kubernetes Service or Ingress.

---

## Help docs build

Help documentation source files live in:

```text
docs/help/
```

The installer runs:

```bash
python3 scripts/build_help_docs.py
```

Generated frontend output is written to:

```text
frontend/help/
```

To skip help-doc generation in an emergency:

```bash
sudo SKIP_HELP_DOCS_BUILD=1 bash install-otp-relay-k8s.sh
```

---

## Verify deployment

Check all OTP Relay resources:

```bash
sudo k3s kubectl get pods,svc,ingress -n otp-relay
```

Expected pods:

```text
otp-relay
otp-monitor
```

Expected service:

```text
otp-relay   NodePort   80:30080/TCP
```

Check rollout status:

```bash
sudo k3s kubectl rollout status deployment/otp-relay -n otp-relay
sudo k3s kubectl rollout status deployment/otp-monitor -n otp-relay
```

Check logs:

```bash
sudo k3s kubectl logs -n otp-relay deployment/otp-relay --tail=100
sudo k3s kubectl logs -n otp-relay deployment/otp-monitor --tail=100
```

Test locally on the server:

```bash
curl -i http://127.0.0.1/
curl -i http://127.0.0.1:30080/
```

Expected result:

```text
HTTP/1.1 200 OK
```

---

## Health checks

The app exposes:

```text
/healthz
/readyz
```

Example:

```bash
curl -i http://127.0.0.1/healthz
curl -i http://127.0.0.1/readyz
```

---

## Troubleshooting

### GitHub Actions is using an old installer

If the workflow logs show:

```text
/opt/otp-relay-k8s/install-otp-relay-k8s.sh
```

then the workflow is running an old server-side script. Change the workflow to run:

```bash
sudo -n -E /usr/bin/bash "$GITHUB_WORKSPACE/install-otp-relay-k8s.sh"
```

### GitHub Actions secrets are null

If workflow debug logs show values like:

```text
secrets.PHONE_IP => null
```

create the missing repository secrets under:

```text
Repository → Settings → Secrets and variables → Actions
```

### sudo asks for a password in GitHub Actions

Fix the runner sudoers rule. The workflow should use `sudo -n` so this fails clearly.

### Docker command is missing

Docker is required for local image builds. On Debian-family systems, make sure the Docker CLI is installed and visible to root:

```bash
sudo command -v docker
sudo docker version
```

Then rerun the workflow.

### Pod is not ready

```bash
sudo k3s kubectl get pods -n otp-relay -o wide
sudo k3s kubectl logs -n otp-relay deployment/otp-relay --tail=100
sudo k3s kubectl describe pod -n otp-relay -l app=otp-relay
```

### Frontend did not update

Confirm the latest commit is present on the server checkout:

```bash
cd /opt/otp-relay-k8s
git log -1 --oneline
```

Then hard-refresh the browser:

```text
Ctrl + F5
```

or open the portal in an incognito window.

---

## Manual full deployment

Manual deployment is still supported, but GitHub Actions is preferred after the runner is online.

```bash
sudo NONINTERACTIVE=1 bash install-otp-relay-k8s.sh
```

Useful overrides:

```bash
sudo NAMESPACE=otp-relay \
  SERVICE_NODE_PORT=30080 \
  PHONE_IP=172.31.10.161 \
  PHONE_INTERFACE=eth0 \
  WHATSAPP_API_KEY="..." \
  WHATSAPP_RECIPIENT="..." \
  NONINTERACTIVE=1 \
  bash install-otp-relay-k8s.sh
```

---

## Manual image build for debugging

The installer is preferred. Manual build commands are for troubleshooting only.

```bash
docker build -t otp-relay:latest -f k8s/Dockerfile .
docker build -t otp-monitor:latest -f k8s/Dockerfile.monitor .

docker save otp-relay:latest -o otp-relay-latest.tar
docker save otp-monitor:latest -o otp-monitor-latest.tar

sudo k3s ctr images import otp-relay-latest.tar
sudo k3s ctr images import otp-monitor-latest.tar
```

---

## Local validation before deploy

```bash
python3 -m py_compile main.py monitor.py
python3 scripts/build_help_docs.py
docker build -t otp-relay:latest -f k8s/Dockerfile .
docker build -t otp-monitor:latest -f k8s/Dockerfile.monitor .
kubectl apply --dry-run=client -f k8s/manifests/
```

---

## Git hygiene

Do not commit:

```text
.env
k8s/manifests/secret.env
data/
*.log
*.tar
.installer-venv/
__pycache__/
```

Runtime data belongs in the Kubernetes PVC, not in Git.

Generated frontend help files may be committed only if the project chooses to track generated docs. Otherwise, they are generated during deployment.

---

## License

MIT
