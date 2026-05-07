# OTP Relay Kubernetes

Kubernetes/K3s deployment for the OTP Relay Portal.

FastAPI backend + React frontend + persistent runtime data on a Kubernetes PVC.

This repository contains the Kubernetes version of the OTP Relay Portal. It is intended to match the current portal application behavior while replacing the older VM/systemd deployment with containers and Kubernetes resources.

---

## What the app does

The OTP Relay Portal lets users claim a single active OTP slot, trigger the external OTP only when they are first in queue, and view the received OTP on-screen.

OTP values are kept in memory only. They are never written to disk or audit logs.

The portal includes:

- User token login from `users.xlsx`
- RTA onboarding wizard
- Admin dashboard
- Admin credential setup/login
- Admin token configuration saved in `admin_config.json`
- Wizard progress saved in `wizard_progress.json`
- Audit log at `audit.log`
- Help documentation served from the frontend
- Optional monitor container for phone presence and WhatsApp alerts

---

## One-click installation

For Debian, Ubuntu, and Raspberry Pi OS servers, use the installer:

```bash
sudo bash install-otp-relay-k8s.sh
```

The installer will:

- detect OS, CPU architecture, and Raspberry Pi hardware
- install required system packages with `apt-get`
- install K3s if missing
- clone or sync this repository to `/opt/otp-relay-k8s`
- create a local Python virtual environment for build-time tools
- install Python dependencies from `requirements.txt`
- build help documentation using `scripts/build_help_docs.py`
- build the OTP Relay container image
- import the image into K3s containerd
- apply Kubernetes resources
- expose the portal through Traefik Ingress
- expose a NodePort fallback on port `30080`
- optionally configure a GitHub Actions self-hosted runner

After installation, the portal should be available at:

```text
http://<server-ip>/
http://<server-ip>:30080/
```

Example:

```text
http://172.31.11.107/
http://172.31.11.107:30080/
```

---

## Installer safety behavior

The installer is designed to be safe for mixed-use servers.

It does not intentionally:

- modify SSH configuration
- stop or restart unrelated services
- edit firewall rules
- modify cron jobs
- delete existing non-repository directories

Before making deployment changes, it performs preflight checks for:

- SSH listener
- existing K3s installation
- existing repository checkout
- required frontend files
- required help-doc build script
- required Python dependency file

Network and firewall snapshots are saved under:

```text
/var/backups/otp-relay-k8s/
```

---

## Git sync behavior

On every run, the installer syncs `/opt/otp-relay-k8s` to `origin/main`.

For an existing checkout, it runs:

```bash
git fetch --prune origin main
git reset --hard origin/main
git clean -ffd
```

This means all deployment files must be committed and pushed to GitHub before running the installer.

Do not manually place deployment files only on the server unless you intentionally disable cleanup.

To disable cleanup temporarily:

```bash
sudo GIT_CLEAN=0 bash install-otp-relay-k8s.sh
```

---

## GitHub Actions deployment

The preferred deployment path is a GitHub Actions workflow running on a self-hosted runner installed on the K3s server.

The workflow is stored at:

```text
.github/workflows/deploy-k3s.yml
```

It runs on:

- push to `main`
- manual `workflow_dispatch` from the GitHub Actions tab

The workflow calls the installer on the server:

```bash
sudo -E /usr/bin/bash /opt/otp-relay-k8s/install-otp-relay-k8s.sh
```

The installer remains the source of truth. It builds the app image and the required monitor image locally, imports both images into K3s containerd, applies manifests, and waits for rollout completion.

One-time runner bootstrap:

```bash
sudo INSTALL_GITHUB_RUNNER=1 \
  GITHUB_RUNNER_URL="https://github.com/psi1703/k8s" \
  GITHUB_RUNNER_TOKEN="PASTE_RUNNER_TOKEN_HERE" \
  PHONE_IP="172.31.10.161" \
  PHONE_INTERFACE="eth0" \
  WHATSAPP_API_KEY="PASTE_WHATSAPP_API_KEY_HERE" \
  WHATSAPP_RECIPIENT="PASTE_WHATSAPP_RECIPIENT_HERE" \
  PORTAL_URL="http://SERVER_IP_OR_DNS" \
  NONINTERACTIVE=1 \
  bash install-otp-relay-k8s.sh
```

Create these GitHub Actions repository secrets before using the workflow:

```text
PHONE_IP
PHONE_INTERFACE
WHATSAPP_API_KEY
WHATSAPP_RECIPIENT
PORTAL_URL
```

Detailed instructions are in:

```text
docs/operations/github-actions-deploy.md
k8s/docs/operations/build-guide.md
```

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
│       ├── manifest.json
│       ├── wizard-guide.json
│       ├── rendered/
│       └── assets/
├── docs/
│   ├── operations/
│   │   └── github-actions-deploy.md
│   └── help/
│       ├── *.md
│       └── assets/
├── scripts/
│   └── build_help_docs.py
├── k8s/
│   ├── Dockerfile
│   ├── Dockerfile.monitor
│   └── manifests/
│       ├── namespace.yaml
│       ├── configmap.yaml
│       ├── secret-example.env
│       ├── pvc.yaml
│       ├── deployment.yaml
│       ├── deployment-monitor.yaml
│       ├── service.yaml
│       └── ingress.yaml
└── README.md
```

---

## Frontend files

The portal frontend lives in:

```text
frontend/
```

Required frontend files:

```text
frontend/index.html
frontend/app.jsx
frontend/style.css
```

Optional/additional frontend files:

```text
frontend/guide.html
frontend/help/
```

The installer verifies the required frontend files before building the Docker image.

If frontend files are changed, commit and push them to GitHub, then rerun:

```bash
sudo bash install-otp-relay-k8s.sh
```

After deployment, hard-refresh the browser:

```text
Ctrl + F5
```

or open the portal in an incognito window to avoid cached CSS/JavaScript.

---

## Help docs build

Help documentation source files live in:

```text
docs/help/
```

The installer runs this before building the container image:

```bash
python3 scripts/build_help_docs.py
```

The help-doc builder reads from:

```text
docs/help/
```

and generates frontend output under:

```text
frontend/help/
```

Expected generated output includes:

```text
frontend/help/manifest.json
frontend/help/wizard-guide.json
frontend/help/rendered/
frontend/help/assets/
```

The generated help files are baked into the container image during installation.

To skip help-doc generation in an emergency:

```bash
sudo SKIP_HELP_DOCS_BUILD=1 bash install-otp-relay-k8s.sh
```

---

## Runtime data

Do not commit runtime data to Git.

In Kubernetes, runtime data is stored on the PVC mounted at:

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

The equivalent older VM/systemd path was:

```text
/opt/otp-relay/data
```

If migrating data from an older install, copy those files into the PVC-backed `/app/data` location.

---

## Required secrets

Copy the example file and fill in real values:

```bash
cp k8s/manifests/secret-example.env k8s/manifests/secret.env
```

Generate the SMS secret:

```bash
python3 - <<'PY'
import secrets
print(secrets.token_hex(32))
PY
```

Create or update the Kubernetes secret:

```bash
kubectl create secret generic otp-relay-secrets \
  --from-env-file=k8s/manifests/secret.env \
  --namespace=otp-relay \
  --dry-run=client -o yaml | kubectl apply -f -
```

Never commit:

```text
k8s/manifests/secret.env
```

---

## Network exposure

The app is exposed in two ways.

Primary route through Traefik Ingress:

```text
http://<server-ip>/
```

Fallback route through NodePort:

```text
http://<server-ip>:30080/
```

The OTP Relay app container listens internally on:

```text
0.0.0.0:8000
```

The Kubernetes Service maps:

```text
service port 80 -> container port 8000
```

The default K3s Traefik controller owns normal HTTP port `80`. For that reason, the main app service should not depend on a direct `LoadBalancer` service for port `80`.

Correct traffic flow:

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

## Verify installation

Check K3s:

```bash
sudo systemctl status k3s --no-pager
sudo k3s kubectl get nodes
```

Check all pods:

```bash
sudo k3s kubectl get pods -A
```

Check OTP Relay resources:

```bash
sudo k3s kubectl get pods,svc,ingress -n otp-relay
```

Expected service shape:

```text
service/otp-relay   NodePort   ...   80:30080/TCP
```

Expected ingress shape:

```text
ingress.networking.k8s.io/otp-relay   traefik   *   <server-ip>   80
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

Test using the server IP:

```bash
curl -i http://<server-ip>/
curl -i http://<server-ip>:30080/
```

Check application logs:

```bash
sudo k3s kubectl logs -n otp-relay deployment/otp-relay --tail=100
```

A healthy startup should show something similar to:

```text
Application startup complete.
Uvicorn running on http://0.0.0.0:8000
```

---

## Troubleshooting

### `http://<server-ip>/` returns 404

Check the ingress:

```bash
sudo k3s kubectl get ingress -n otp-relay
sudo k3s kubectl describe ingress otp-relay -n otp-relay
```

Check Traefik:

```bash
sudo k3s kubectl get pods -n kube-system | grep -i traefik
sudo k3s kubectl get svc -n kube-system traefik
```

Expected:

```text
ingress/otp-relay   traefik   *   <server-ip>   80
```

If Traefik is working but the ingress is missing, rerun the installer:

```bash
sudo bash install-otp-relay-k8s.sh
```

---

### NodePort times out

Check the service:

```bash
sudo k3s kubectl get svc -n otp-relay
```

Expected:

```text
otp-relay   NodePort   ...   80:30080/TCP
```

Test from the server:

```bash
curl -i http://127.0.0.1:30080/
```

If local curl works but browser access fails, check host firewall or cloud firewall rules for TCP port `30080`.

---

### Pod is not ready

Check pod status:

```bash
sudo k3s kubectl get pods -n otp-relay -o wide
```

Check logs:

```bash
sudo k3s kubectl logs -n otp-relay deployment/otp-relay --tail=100
```

Check rollout:

```bash
sudo k3s kubectl rollout status deployment/otp-relay -n otp-relay
```

Restart the deployment:

```bash
sudo k3s kubectl rollout restart deployment/otp-relay -n otp-relay
```

---

### Help docs build fails

Run the builder manually:

```bash
cd /opt/otp-relay-k8s
.installer-venv/bin/python scripts/build_help_docs.py
```

If input files are missing, confirm this directory exists and was committed to GitHub:

```text
docs/help/
```

If Python modules are missing, reinstall requirements in the installer venv:

```bash
cd /opt/otp-relay-k8s
.installer-venv/bin/python -m pip install -r requirements.txt
.installer-venv/bin/python scripts/build_help_docs.py
```

---

### Frontend did not update

Confirm the latest repo commit is present on the server:

```bash
cd /opt/otp-relay-k8s
git log -1 --oneline
```

Check frontend files:

```bash
ls -la frontend/
```

Rerun installer:

```bash
sudo bash install-otp-relay-k8s.sh
```

Then hard-refresh the browser:

```text
Ctrl + F5
```

or open in incognito mode.

---

## Upload runtime files into the PVC

After the pod is running, copy the user list into `/app/data`:

```bash
POD=$(kubectl get pod -n otp-relay -l app=otp-relay -o jsonpath='{.items[0].metadata.name}')

kubectl cp ./users.xlsx otp-relay/$POD:/app/data/users.xlsx -n otp-relay
```

If migrating from the older VM/systemd deployment, also copy:

```bash
kubectl cp ./admin_auth.json otp-relay/$POD:/app/data/admin_auth.json -n otp-relay
kubectl cp ./admin_config.json otp-relay/$POD:/app/data/admin_config.json -n otp-relay
kubectl cp ./wizard_progress.json otp-relay/$POD:/app/data/wizard_progress.json -n otp-relay
```

Restart the deployment after data migration:

```bash
kubectl rollout restart deployment/otp-relay -n otp-relay
```

---

## Health checks

The app exposes:

```text
/healthz
/readyz
```

Use these for Kubernetes liveness and readiness probes.

Example:

```bash
curl -i http://127.0.0.1/healthz
curl -i http://127.0.0.1/readyz
```

---

## Important design constraints

Keep the main app at one replica for now:

```text
replicas: 1
```

The OTP queue and admin sessions are currently in process memory.

Multiple replicas would create separate queues and separate sessions unless state is moved to Redis, a database, or another shared state backend.

The PVC uses `ReadWriteOnce`, which is correct for the current single-node/single-replica design.

Do not scale to multiple pods for production until shared state and file-write safety are handled.

---

## Optional monitor

The optional `otp-monitor` container is used for phone presence and WhatsApp alerts.

The monitor uses `arping`, which requires:

```yaml
hostNetwork: true
capabilities:
  add:
    - NET_RAW
```

Without host networking, the pod may not see the real LAN interface used to ARP the phone.

To deploy the monitor manually:

```bash
kubectl apply -f k8s/manifests/deployment-monitor.yaml
```

To enable monitor deployment through the installer:

```bash
sudo INSTALL_MONITOR=1 \
  WHATSAPP_API_KEY="<api-key>" \
  WHATSAPP_RECIPIENT="<recipient>" \
  bash install-otp-relay-k8s.sh
```

---

## Optional GitHub Actions runner

The GitHub Actions self-hosted runner is not required to run OTP Relay.

Install it only if this server should receive deployments from GitHub Actions.

The installer can configure it when enabled:

```bash
sudo INSTALL_GITHUB_RUNNER=1 \
  GITHUB_RUNNER_URL="https://github.com/psi1703/k8s" \
  GITHUB_RUNNER_TOKEN="<token>" \
  bash install-otp-relay-k8s.sh
```

The runner token must be generated from GitHub when adding a self-hosted runner.

---

## Manual build

The installer is the preferred deployment method.

Manual build commands are useful for debugging.

Build the main portal image:

```bash
docker build -t otp-relay:latest -f k8s/Dockerfile .
```

Build the optional monitor image:

```bash
docker build -t otp-monitor:latest -f k8s/Dockerfile.monitor .
```

For K3s without a registry, export and import the images:

```bash
docker save otp-relay:latest -o otp-relay-latest.tar
docker save otp-monitor:latest -o otp-monitor-latest.tar

sudo k3s ctr images import otp-relay-latest.tar
sudo k3s ctr images import otp-monitor-latest.tar
```

---

## Manual Kubernetes deployment

The installer is preferred, but the app can also be deployed manually.

Apply namespace:

```bash
kubectl apply -f k8s/manifests/namespace.yaml
```

Create the secret:

```bash
kubectl create secret generic otp-relay-secrets \
  --from-env-file=k8s/manifests/secret.env \
  --namespace=otp-relay \
  --dry-run=client -o yaml | kubectl apply -f -
```

Apply app resources:

```bash
kubectl apply -f k8s/manifests/configmap.yaml
kubectl apply -f k8s/manifests/pvc.yaml
kubectl apply -f k8s/manifests/deployment.yaml
kubectl apply -f k8s/manifests/service.yaml
kubectl apply -f k8s/manifests/ingress.yaml
```

Check rollout:

```bash
kubectl get pods -n otp-relay
kubectl rollout status deployment/otp-relay -n otp-relay
kubectl logs -n otp-relay deployment/otp-relay
kubectl get svc,ingress -n otp-relay
```

---

## Local validation

Run these checks before deploying:

```bash
python3 -m py_compile main.py monitor.py
python3 scripts/build_help_docs.py
docker build -t otp-relay:latest -f k8s/Dockerfile .
docker build -t otp-monitor:latest -f k8s/Dockerfile.monitor .
kubectl apply --dry-run=client -f k8s/manifests/
```

Run the app container locally with a data mount:

```bash
mkdir -p data

docker run --rm -p 8000:8000 \
  -e OTP_RELAY_DATA_DIR=/app/data \
  -v "$PWD/data:/app/data" \
  otp-relay:latest
```

Open:

```text
http://localhost:8000
```

---

## Git hygiene

These files must not be committed:

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

Generated frontend help files may be committed only if the project chooses to track generated docs. Otherwise, they should be generated during installation by:

```bash
python3 scripts/build_help_docs.py
```

---

## License

MIT
