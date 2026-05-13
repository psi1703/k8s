# Dockerfile design notes

This document explains the Kubernetes image build files used by the OTP Relay K8s deployment.

The source-of-truth files are:

```text
k8s/Dockerfile
k8s/Dockerfile.monitor
```

The installer must build from these committed files. It should not generate hidden Dockerfiles during deployment.

---

## App image: `k8s/Dockerfile`

The app image uses three stages:

```text
frontend-builder  -> builds frontend/app.jsx into frontend/app.js
python-builder    -> builds the Python virtual environment from requirements.txt
runtime           -> contains only the runtime venv, main.py, and built frontend assets
```

This keeps the final image smaller and makes the build behavior reviewable in GitHub.

### Frontend build stage

The frontend source is:

```text
frontend/app.jsx
```

The browser runtime uses:

```text
frontend/app.js
```

The Dockerfile builds `frontend/app.js` during image build and removes `frontend/app.jsx` from the runtime image. This avoids browser-side Babel and keeps JSX source out of the deployed container.

### Python dependency stage

Python dependencies are installed from:

```text
requirements.txt
```

The dependency install happens before `main.py` is copied so Docker layer caching can avoid reinstalling Python packages when only application code changes.

### Runtime stage

The final image runs as non-root user `otprelay` with UID `999`. This matches the Kubernetes pod security context:

```yaml
runAsNonRoot: true
runAsUser: 999
fsGroup: 999
```

The app exposes port `8000` and runs uvicorn with one worker:

```text
/app/venv/bin/python -m uvicorn main:app --host 0.0.0.0 --port 8000 --workers 1
```

One worker is intentional. OTP queue state, pending OTPs, and admin sessions are currently process-memory state. The Kubernetes deployment also remains `REPLICA_COUNT=1` for the same reason.

### Why `python -m uvicorn`

The image calls uvicorn as a Python module instead of calling the `venv/bin/uvicorn` launcher directly. This avoids hardcoded launcher/shebang path issues when a virtualenv is created in a builder stage and copied into a different runtime path.

---

## Monitor image: `k8s/Dockerfile.monitor`

The monitor runs separately from the portal app.

It installs:

```text
iputils-arping
python-dotenv
```

`arping` is required for phone-presence checks because the monitor uses ARP-level detection through the selected phone network interface.

The monitor pod requires:

```yaml
hostNetwork: true
dnsPolicy: ClusterFirstWithHostNet
securityContext:
  capabilities:
    add:
      - NET_RAW
```

The monitor must not be exposed by a Kubernetes Service or Ingress.

---

## Runtime data

Neither image bakes runtime data into the container.

Runtime data lives on the PVC mounted at:

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

---

## Build commands

From the repository root:

```bash
docker build -t otp-relay:latest -f k8s/Dockerfile .
docker build -t otp-monitor:latest -f k8s/Dockerfile.monitor .
```

The installer performs these builds only when the deployment mode requires an app or monitor image rebuild.
