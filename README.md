# OTP Relay Kubernetes

**Kubernetes/K3s deployment for the OTP Relay Portal**  
FastAPI + React frontend + persistent runtime data on a PVC.

This repository contains the Kubernetes version of the OTP Relay Portal. It is intended to match the current portal application behavior while replacing the Ubuntu/systemd deployment with containers and Kubernetes manifests.

---

## What the app does

The OTP Relay Portal lets users claim a single active OTP slot, trigger the external OTP only when they are first in queue, and view the received OTP on-screen. OTP values are kept in memory only. They are never written to disk or audit logs.

The portal also includes:

- User token login from `users.xlsx`
- RTA onboarding wizard
- Admin dashboard
- Admin credential setup/login
- Admin token configuration saved in `admin_config.json`
- Wizard progress saved in `wizard_progress.json`
- Audit log at `audit.log`
- Optional monitor container for phone presence and WhatsApp alerts

---

## Repository structure

```text
otp-relay-k8s/
├── main.py
├── monitor.py
├── requirements.txt
├── frontend/
│   ├── index.html
│   ├── app.jsx
│   ├── guide.html
│   └── style.css
├── k8s/
│   ├── Dockerfile
│   ├── Dockerfile.monitor
│   ├── manifests/
│   │   ├── namespace.yaml
│   │   ├── configmap.yaml
│   │   ├── secret-example.env
│   │   ├── pvc.yaml
│   │   ├── deployment.yaml
│   │   ├── deployment-monitor.yaml
│   │   └── service.yaml
│   └── docs/
└── README.md
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

The equivalent VM/systemd path was:

```text
/opt/otp-relay/data
```

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

Create/update the Kubernetes secret:

```bash
kubectl create secret generic otp-relay-secrets \
  --from-env-file=k8s/manifests/secret.env \
  --namespace=otp-relay \
  --dry-run=client -o yaml | kubectl apply -f -
```

Never commit `k8s/manifests/secret.env`.

---

## Build images

Build the main portal image:

```bash
docker build -t otp-relay:latest -f k8s/Dockerfile .
```

Build the optional monitor image:

```bash
docker build -t otp-monitor:latest -f k8s/Dockerfile.monitor .
```

For K3s without a registry, export/import the images:

```bash
docker save otp-relay:latest -o otp-relay-latest.tar
docker save otp-monitor:latest -o otp-monitor-latest.tar

sudo k3s ctr images import otp-relay-latest.tar
sudo k3s ctr images import otp-monitor-latest.tar
```

---

## Deploy to Kubernetes

Apply the namespace first:

```bash
kubectl apply -f k8s/manifests/namespace.yaml
```

Create the secret if not already created:

```bash
kubectl create secret generic otp-relay-secrets \
  --from-env-file=k8s/manifests/secret.env \
  --namespace=otp-relay \
  --dry-run=client -o yaml | kubectl apply -f -
```

Apply the app resources:

```bash
kubectl apply -f k8s/manifests/configmap.yaml
kubectl apply -f k8s/manifests/pvc.yaml
kubectl apply -f k8s/manifests/deployment.yaml
kubectl apply -f k8s/manifests/service.yaml
```

Optional monitor:

```bash
kubectl apply -f k8s/manifests/deployment-monitor.yaml
```

Check rollout:

```bash
kubectl get pods -n otp-relay
kubectl rollout status deployment/otp-relay -n otp-relay
kubectl logs -n otp-relay deployment/otp-relay
kubectl get svc -n otp-relay
```

---

## Upload runtime files into the PVC

After the pod is running, copy the user list into `/app/data`:

```bash
POD=$(kubectl get pod -n otp-relay -l app=otp-relay -o jsonpath='{.items[0].metadata.name}')
kubectl cp ./users.xlsx otp-relay/$POD:/app/data/users.xlsx -n otp-relay
```

If migrating from the VM/systemd deployment, also copy:

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

---

## Important design constraints

Keep the main app at one replica for now:

```yaml
replicas: 1
```

The OTP queue and admin sessions are currently in process memory. Multiple replicas would create separate queues and sessions unless state is moved to Redis or a database.

The PVC uses `ReadWriteOnce`, which is correct for the current single-node/single-replica design.

---

## Monitor notes

The optional `otp-monitor` container uses `arping`, which requires:

```yaml
hostNetwork: true
capabilities:
  add:
    - NET_RAW
```

Without host networking, the pod may not see the real LAN interface used to ARP the phone.

---

## Local validation

Run these checks before deploying:

```bash
python3 -m py_compile main.py monitor.py
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
```
