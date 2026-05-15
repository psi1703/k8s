# OTP Relay Kubernetes

Kubernetes/K3s deployment for the OTP Relay Portal.

This repository contains the FastAPI portal, required monitor service, React frontend source, help-documentation source, Kubernetes manifests, Dockerfiles, and installer used by GitHub Actions to deploy onto a K3s server or cluster.

This README is the single operational documentation file for the repository. It combines the root README, architecture notes, deployment guide, storage guide, development guide, operations runbook, validation notes, and help-documentation map into one SCH-style document.

---

## Current status

The repository is at a Phase 3 SCH-alignment validation baseline.

Validated foundations:

- 3-node K3s cluster baseline.
- Official HTTPS exposure through Traefik Ingress.
- Internal `otp-relay` app Service using `ClusterIP`.
- Redis-required runtime state.
- Redis StatefulSet, Sentinel, and HAProxy topology validated.
- Redis Sentinel is spread one-per-node.
- Redis HAProxy is spread across worker nodes.
- NFS/RWX application storage validated for `/app/data`.
- Portal app runs with two replicas and validated load balancing.
- Portal pod self-healing validated.
- Node-level portal failover validated.
- Monitor pod isolated from Service/Ingress.
- Health monitor reports deployment healthy.

Current live posture:

```text
SERVICE_TYPE=ClusterIP
INGRESS_ENABLED=1
TLS_ENABLED=1
TLS_HOST=srvotptest26.init-db.lan
PORTAL_URL=https://srvotptest26.init-db.lan
REPLICA_COUNT=2
REDIS_REQUIRED=1
REDIS_URL=redis://otp-redis-haproxy:6379/0
NFS_ENABLED=1
PVC_STORAGE_CLASS=otp-relay-nfs
strategy: RollingUpdate
rollingUpdate: maxUnavailable=0, maxSurge=1
TLS self-signed is enabled until IT distributes/trusts the certificate by Group Policy
```

---

## How it works

```text
Client browser
  -> DNS: srvotptest26.init-db.lan
  -> Traefik HTTPS Ingress
  -> Kubernetes Service: otp-relay
  -> FastAPI portal pod
  -> Redis HAProxy service
  -> Redis Sentinel-managed Redis master/replicas
  -> NFS-backed /app/data storage
  -> Portal UI displays OTP

IPhone receiving SMS
  -> iOS Shortcut
  -> POST /sms-received
  -> FastAPI portal
  -> Redis pending OTP state
  -> Browser polling displays OTP

Monitor pod
  -> hostNetwork + NET_RAW
  -> phone presence checks
  -> SMS-path checks
  -> shared audit log checks
  -> WhatsApp alerts
  -> no Service / no Ingress
```

The portal is not an SMS gateway. The phone receives the SMS. The iOS Shortcut forwards the received OTP to the portal. The portal stores runtime state in Redis and displays the OTP to the waiting user.

OTP values are not written to disk. Runtime files such as users, wizard state, admin config, and audit log are stored on the shared `/app/data` PVC.

---

## Current cluster

| Item | Value |
|---|---|
| Platform | K3s |
| Namespace | `otp-relay` |
| Control-plane node | `debian` |
| Worker nodes | `otp-worker-1`, `otp-worker-2` |
| Portal host | `srvotptest26.init-db.lan` |
| Portal URL | `https://srvotptest26.init-db.lan` |
| App replicas | 2 |
| Redis replicas | 3 |
| Redis Sentinel replicas | 3 |
| Redis HAProxy replicas | 2 |
| App storage | NFS RWX PVC mounted at `/app/data` |
| Monitor | Required internal workload |
| Health monitor | `/usr/local/bin/otp-relayk3s-monitor.sh` |

---

## Repository structure

```text
.
├── main.py
├── monitor.py
├── requirements.txt
├── install-otp-relay-k8s.sh
├── frontend/
│   ├── index.html
│   ├── app.jsx
│   ├── app.js
│   ├── style.css
│   └── guide.html
├── docs/
│   ├── help/
│   ├── architecture/
│   ├── deployment/
│   ├── development/
│   └── operations/
├── scripts/
│   ├── build_help_docs.py
│   └── generate_sample_users.py
└── k8s/
    ├── Dockerfile
    ├── Dockerfile.monitor
    └── manifests/
```

Active Kubernetes assets are under `k8s/` and `k8s/manifests/`.

Documentation source may remain under `docs/`, but this root README is the single handoff document.

Do not restore old conflicting documentation paths such as:

```text
docs/k8s-plan.md
k8s/docs/
docs/dev/
docs/diagrams/
```

---

## Architecture

Current validated architecture:

```text
                           +-----------------------------+
                           |  srvotptest26.init-db.lan   |
                           +--------------+--------------+
                                          |
                                          v
                           +-----------------------------+
                           | Traefik HTTPS Ingress       |
                           +--------------+--------------+
                                          |
                                          v
                           +-----------------------------+
                           | Service: otp-relay          |
                           | Type: ClusterIP             |
                           +--------------+--------------+
                                          |
                       +------------------+------------------+
                       |                                     |
                       v                                     v
          +-------------------------+           +-------------------------+
          | otp-relay app pod      |           | otp-relay app pod      |
          | FastAPI + frontend     |           | FastAPI + frontend     |
          +-----------+-------------+           +-----------+-------------+
                      |                                     |
                      +------------------+------------------+
                                         |
                                         v
                           +-----------------------------+
                           | Service: otp-redis-haproxy  |
                           +--------------+--------------+
                                          |
                       +------------------+------------------+
                       |                                     |
                       v                                     v
          +-------------------------+           +-------------------------+
          | Redis HAProxy pod       |           | Redis HAProxy pod       |
          | otp-worker-1            |           | otp-worker-2            |
          +-----------+-------------+           +-----------+-------------+
                      |                                     |
                      +------------------+------------------+
                                         |
                                         v
                           +-----------------------------+
                           | Redis master/replicas       |
                           | Sentinel-managed            |
                           +-----------------------------+
```

Shared application files:

```text
/app/data
  users.xlsx
  admin_auth.json
  admin_config.json
  wizard_progress.json
  audit.log
```

Redis runtime state:

```text
OTP queue
Pending OTP state
OTP TTL data
Admin sessions
Admin login attempts and lockout state
```

---

## SCH production alignment

SCH production direction:

```text
Clients
  -> internal DNS
  -> approved LB/VIP layer
  -> HTTPS ingress/controller
  -> Kubernetes service
  -> multiple app pods across nodes
  -> shared Redis/Sentinel/HAProxy or approved managed Redis
  -> shared RWX/network persistent app storage

Monitor pod remains internal and unexposed.
```

Current alignment:

| Area | SCH target | Current status |
|---|---|---|
| External access | DNS plus approved ingress/LB path | DNS and Traefik HTTPS ingress active |
| TLS | HTTPS trusted on user machines | Self-signed enabled; IT trust rollout pending |
| App replicas | Multiple app pods | 2 replicas running and validated |
| App storage | Shared RWX/network storage | NFS RWX PVC validated |
| Redis | HA Redis/Sentinel/HAProxy or approved managed Redis | Redis StatefulSet, Sentinel, HAProxy validated |
| Sentinel placement | Spread across nodes | 3 pods, one per node validated |
| HAProxy placement | Spread across nodes | 2 pods across workers validated |
| Failover | Pod and node-level validation | Portal pod and node-level failover validated |
| Monitor | Internal only | No Service / no Ingress aligned |
| Documentation | Clear active docs | This root README is the single handoff document |

Remaining production items:

- IT certificate trust rollout for the self-signed/internal certificate.
- Final SCH acceptance of Redis Sentinel/HAProxy versus a managed Redis service.
- Redis backup/restore expectations.
- Controlled Redis failover and worker-drain retest during maintenance windows when needed.
- Manager final business-flow OTP validation if not already signed off.

---

## Current validated pod placement

Final validated Redis access/control placement:

```text
Redis HAProxy:
- otp-worker-1
- otp-worker-2

Redis Sentinel:
- debian
- otp-worker-1
- otp-worker-2
```

Latest validated combined placement:

```text
otp-redis-haproxy    otp-worker-1
otp-redis-haproxy    otp-worker-2
otp-redis-sentinel   debian
otp-redis-sentinel   otp-worker-1
otp-redis-sentinel   otp-worker-2
otp-relay            debian
otp-relay            otp-worker-1
```

Portal app placement can move depending on scheduling and failover. It has been validated across nodes, including control-plane cordon and pod recreation.

---

## Deployment overview

Recommended deployment path is GitHub Actions with the self-hosted runner.

```text
git push to main
  -> GitHub Actions job starts
  -> self-hosted runner checks out the repo
  -> installer syncs /opt/otp-relay-k8s to origin/main
  -> installer builds frontend app.js and help docs
  -> installer builds/imports app and monitor images
  -> installer renders/applies Kubernetes resources
  -> installer waits for rollouts
```

The workflow should call `install-otp-relay-k8s.sh`. Deployment logic should stay in the installer and manifests, not duplicated into the workflow YAML.

Required GitHub Actions secrets:

```text
PHONE_IP
PHONE_INTERFACE
WHATSAPP_API_KEY
WHATSAPP_RECIPIENT
PORTAL_URL
```

Do not commit:

```text
.env
secret.env
runtime tokens
WhatsApp credentials
users.xlsx from production
admin_auth.json
admin_config.json
audit.log
*.tar
*.log
```

---

## Quick start

Clone or update the repo on the runner host:

```bash
git clone https://github.com/<owner>/<repo>.git /opt/otp-relay-k8s
cd /opt/otp-relay-k8s
```

Run deployment through GitHub Actions where possible.

Manual fallback from the repo root:

```bash
sudo ./install-otp-relay-k8s.sh
```

Check deployment:

```bash
sudo k3s kubectl get nodes -o wide
sudo k3s kubectl get pods -n otp-relay -o wide
sudo k3s kubectl get svc -n otp-relay
sudo k3s kubectl get ingress -n otp-relay
sudo /usr/local/bin/otp-relayk3s-monitor.sh
```

Expected health monitor result:

```text
OK: OTP Relay K3s deployment is healthy.
```

---

## Updating

Preferred update:

```bash
git add .
git commit -m "Update OTP Relay Kubernetes deployment"
git push origin main
```

Then let GitHub Actions run the deployment.

Manual verification after workflow:

```bash
sudo k3s kubectl -n otp-relay rollout status deployment/otp-relay
sudo k3s kubectl -n otp-relay rollout status deployment/otp-monitor
sudo k3s kubectl -n otp-relay rollout status deployment/otp-redis-sentinel
sudo k3s kubectl -n otp-relay rollout status deployment/otp-redis-haproxy
sudo k3s kubectl -n otp-relay get pods -o wide
sudo /usr/local/bin/otp-relayk3s-monitor.sh
```

---

## Kubernetes services

Expected service posture:

```text
otp-relay            ClusterIP   portal app service
otp-redis            ClusterIP   Redis access service, may point to HAProxy
otp-redis-haproxy    ClusterIP   Redis HAProxy service
otp-redis-headless   ClusterIP   None, Redis StatefulSet discovery
otp-redis-sentinel   ClusterIP   Sentinel service
```

The monitor must not have a public Service or Ingress.

The app Service should remain internal when Ingress is used:

```text
SERVICE_TYPE=ClusterIP
INGRESS_ENABLED=1
```

---

## Redis HA model

Redis is required in the current validated posture.

```text
REDIS_REQUIRED=1
REDIS_URL=redis://otp-redis-haproxy:6379/0
```

Redis components:

```text
otp-redis             StatefulSet, 3 replicas
otp-redis-sentinel    Deployment, 3 replicas
otp-redis-haproxy     Deployment, 2 replicas
otp-redis-headless    Headless service for Redis pod discovery
```

The app talks to HAProxy. HAProxy routes Redis traffic to the current Redis master. Sentinel monitors Redis pods and handles master promotion.

Validated target:

```text
Redis StatefulSet: 3/3
Redis Sentinel:    3/3, one per node
Redis HAProxy:     2/2, spread across workers
```

Redis check commands:

```bash
sudo k3s kubectl -n otp-relay get pods -o wide | grep -E 'redis|haproxy'
sudo k3s kubectl -n otp-relay get svc | grep redis
sudo k3s kubectl -n otp-relay logs deployment/otp-redis-sentinel --tail=100
sudo k3s kubectl -n otp-relay logs deployment/otp-redis-haproxy --tail=100
```

Sentinel master lookup:

```bash
SENTINEL_POD=$(sudo k3s kubectl -n otp-relay get pod -l app=otp-redis-sentinel -o jsonpath='{.items[0].metadata.name}')
sudo k3s kubectl -n otp-relay exec "$SENTINEL_POD" -- redis-cli -p 26379 sentinel get-master-addr-by-name mymaster
```

---

## NFS shared storage

Application storage is NFS-backed RWX storage.

```text
PVC:           otp-relay-data
PV:            otp-relay-data-nfs-pv
Access mode:   ReadWriteMany
StorageClass:  otp-relay-nfs
NFS server:    172.31.11.108
NFS path:      /export/otp-relay-data
Mount path:    /app/data
```

The app container runs as:

```text
uid=999(otprelay)
gid=999(otprelay)
```

The NFS export must allow UID/GID `999:999` to write.

On the NFS server:

```bash
sudo chown -R 999:999 /export/otp-relay-data
sudo chmod -R u+rwX,g+rwX /export/otp-relay-data
```

Validate write access from both app pods:

```bash
sudo k3s kubectl -n otp-relay get pods -l app=otp-relay -o name | while read p; do
  echo "=== $p ==="
  sudo k3s kubectl -n otp-relay exec "${p#pod/}" -- sh -c '
    id
    touch /app/data/write-test &&
    rm -f /app/data/write-test &&
    echo WRITE_OK || echo WRITE_FAILED
  '
done
```

Expected:

```text
WRITE_OK
WRITE_OK
```

---

## TLS and DNS

Current portal endpoint:

```text
https://srvotptest26.init-db.lan
```

Because the certificate is currently self-signed, command-line validation uses `curl -k`:

```bash
curl -k https://srvotptest26.init-db.lan/healthz
curl -k https://srvotptest26.init-db.lan/readyz
```

Production requirement:

```text
IT distributes/trusts the internal certificate by Group Policy, or a trusted certificate is installed.
```

Until trust rollout is complete, browsers may show a certificate warning.

---

## Monitor and alerts

The monitor is required.

Expected monitor properties:

```text
hostNetwork: true
dnsPolicy: ClusterFirstWithHostNet
NET_RAW capability
No Service
No Ingress
Can read /app/data/audit.log
Can check phone presence on phone network
Can send WhatsApp alerts when configured
```

Run monitor check:

```bash
sudo /usr/local/bin/otp-relayk3s-monitor.sh
```

Expected:

```text
OK: OTP Relay K3s deployment is healthy.
```

If SMTP settings are incomplete, the monitor can still report health locally but may fail to send email alerts. Edit:

```bash
sudo nano /etc/otp-relay-k3s-monitor.env
```

---

## Build and development

App image:

```text
k8s/Dockerfile
```

Monitor image:

```text
k8s/Dockerfile.monitor
```

The app image includes:

- Python runtime for FastAPI/Uvicorn.
- Python dependencies from `requirements.txt`.
- Frontend static files.
- Generated production `frontend/app.js` from `frontend/app.jsx`.
- Generated help pages from `docs/help/`.

The app starts Uvicorn through Python:

```text
python -m uvicorn main:app
```

The monitor image runs the required monitor workload.

Frontend source:

```text
frontend/app.jsx
```

Frontend production output:

```text
frontend/app.js
```

Do not restore browser Babel or `text/babel` as the production model.

Help source:

```text
docs/help/
```

Help build script:

```text
scripts/build_help_docs.py
```

Generated help output:

```text
frontend/help/
```

Manual local build fallback:

```bash
docker build -t otp-relay:latest -f k8s/Dockerfile .
docker build -t otp-monitor:latest -f k8s/Dockerfile.monitor .
```

For K3s without registry:

```bash
docker save otp-relay:latest -o otp-relay-latest.tar
docker save otp-monitor:latest -o otp-monitor-latest.tar
sudo k3s ctr images import otp-relay-latest.tar
sudo k3s ctr images import otp-monitor-latest.tar
```

Restart workloads:

```bash
sudo k3s kubectl -n otp-relay rollout restart deployment/otp-relay
sudo k3s kubectl -n otp-relay rollout restart deployment/otp-monitor
sudo k3s kubectl -n otp-relay rollout status deployment/otp-relay
sudo k3s kubectl -n otp-relay rollout status deployment/otp-monitor
```

---

## Phase 3 validation summary

| Check | Result |
|---|---|
| Health monitor | PASS |
| Portal 2 replicas | PASS |
| Portal load balancing | PASS |
| Portal pod self-healing | PASS |
| Node-level portal failover | PASS |
| NFS `/app/data` shared write | PASS |
| Wizard progress endpoint | PASS |
| Redis StatefulSet 3/3 | PASS |
| Redis Sentinel 3/3 one-per-node | PASS |
| Redis HAProxy 2/2 spread across workers | PASS |

Final monitor result:

```text
OK: OTP Relay K3s deployment is healthy.
```

---

## Portal load-balancing validation

Watch app logs:

```bash
sudo k3s kubectl -n otp-relay logs -f -l app=otp-relay --tail=20
```

Generate traffic:

```bash
for i in $(seq 1 100); do
  curl -k -s https://srvotptest26.init-db.lan/readyz >/dev/null
  sleep 0.2
done
```

For pod-specific visibility, watch each pod separately:

```bash
sudo k3s kubectl -n otp-relay get pods -l app=otp-relay -o name
sudo k3s kubectl -n otp-relay logs -f pod/<FIRST_POD_NAME> --tail=20
sudo k3s kubectl -n otp-relay logs -f pod/<SECOND_POD_NAME> --tail=20
```

Pass criteria:

```text
Both app pods receive traffic.
/readyz returns 200.
No app crash or permission error appears.
```

---

## Portal pod failover validation

Delete one app pod:

```bash
sudo k3s kubectl -n otp-relay get pods -l app=otp-relay -o wide
sudo k3s kubectl -n otp-relay delete pod <POD_NAME>
```

Immediately test portal continuity:

```bash
for i in $(seq 1 30); do
  curl -k -s -o /dev/null -w "%{http_code}\n" https://srvotptest26.init-db.lan/readyz
  sleep 0.5
done
```

Expected:

```text
200
200
200
...
```

Check recovery:

```bash
sudo k3s kubectl -n otp-relay get pods -l app=otp-relay -o wide
```

Pass criteria:

```text
Portal remains available.
Deleted pod is recreated.
Deployment returns to 2/2.
```

---

## Node-level portal failover validation

Cordon the control-plane node and delete the app pod on that node:

```bash
sudo k3s kubectl cordon debian
sudo k3s kubectl -n otp-relay delete pod -l app=otp-relay --field-selector spec.nodeName=debian
```

Traffic test:

```bash
for i in $(seq 1 30); do
  curl -k -s -o /dev/null -w "%{http_code}\n" https://srvotptest26.init-db.lan/readyz
  sleep 0.5
done
```

Expected:

```text
200
200
200
...
```

Recover:

```bash
sudo k3s kubectl uncordon debian
sudo k3s kubectl -n otp-relay get pods -o wide
```

Pass criteria:

```text
Portal remains available during the test.
Replacement app pod is scheduled on an available worker.
Health monitor passes after recovery.
```

---

## Redis Sentinel and HAProxy spread validation

Check placement:

```bash
sudo k3s kubectl -n otp-relay get pods -o wide | egrep 'redis-haproxy|redis-sentinel|NAME'
```

Expected target:

```text
Redis HAProxy:
- otp-worker-1
- otp-worker-2

Redis Sentinel:
- debian
- otp-worker-1
- otp-worker-2
```

If spread rules are present but pods are already running on the same node, recreate the affected pods or restart the deployments:

```bash
sudo k3s kubectl -n otp-relay rollout restart deployment/otp-redis-sentinel
sudo k3s kubectl -n otp-relay rollout restart deployment/otp-redis-haproxy
sudo k3s kubectl -n otp-relay rollout status deployment/otp-redis-sentinel
sudo k3s kubectl -n otp-relay rollout status deployment/otp-redis-haproxy
```

If needed, delete only one extra Sentinel pod from a duplicated node to allow Kubernetes to place the replacement on the empty node. Do not delete multiple Sentinel pods at the same time unless the maintenance window explicitly allows it.

---

## Daily health checks

```bash
sudo k3s kubectl get nodes -o wide
sudo k3s kubectl get pods -n otp-relay -o wide
sudo k3s kubectl get svc -n otp-relay
sudo k3s kubectl get ingress -n otp-relay
sudo k3s kubectl get pvc -n otp-relay
sudo /usr/local/bin/otp-relayk3s-monitor.sh
```

Application endpoints:

```bash
curl -k https://srvotptest26.init-db.lan/healthz
curl -k https://srvotptest26.init-db.lan/readyz
```

Expected:

```text
/healthz returns OK
/readyz returns Redis OK and Redis required
All required pods are Running/Ready
All required PVCs are Bound
Monitor reports OK
```

---

## OTP validation checklist

Use this checklist for final business-flow validation:

- Login page loads through HTTPS.
- User token login works.
- OTP claim flow works.
- iPhone receives OTP by SMS.
- iOS Shortcut posts SMS to `/sms-received`.
- OTP appears on screen for the waiting user.
- Audit log records the flow.
- Wizard progress endpoint returns 200 for authenticated users.
- Pending OTP survives app pod restart while Redis is healthy.
- Two-replica OTP flow works under load-balanced traffic.
- Manager live OTP trigger test passes.

---

## DNS/TLS client validation checklist

- `srvotptest26.init-db.lan` resolves from user machines.
- HTTPS loads from user machines.
- Certificate trust warning disappears after IT trust rollout.
- Portal works from the intended client network.
- iPhone Shortcut target URL matches the final portal URL.

---

## Worker-drain validation checklist

Run only in a controlled test window.

Before drain:

```bash
sudo k3s kubectl get pods -n otp-relay -o wide
curl -k https://srvotptest26.init-db.lan/readyz
sudo /usr/local/bin/otp-relayk3s-monitor.sh
```

During worker-drain validation, verify:

- App pod reschedules or remaining app pod continues serving traffic.
- Redis Sentinel remains healthy.
- Redis HAProxy remains healthy.
- Redis master remains available or fails over correctly.
- NFS app storage remains mounted.
- `/readyz` returns healthy after the cluster settles.
- OTP flow still works after recovery.

---

## Troubleshooting

### Portal readyz fails with self-signed certificate

Symptom:

```text
curl: (60) SSL certificate problem: self-signed certificate
HTTP_CODE=000
```

Cause:

```text
Monitor or curl does not trust the current self-signed/internal certificate.
```

Temporary validation command:

```bash
curl -k https://srvotptest26.init-db.lan/readyz
```

Production fix:

```text
Install a trusted certificate or distribute the internal CA/certificate through IT Group Policy.
```

### Wizard progress returns 500 PermissionError

Symptom:

```text
PermissionError: [Errno 13] Permission denied: '/app/data/wizard_progress.json.tmp'
```

Cause:

```text
NFS export ownership does not match the app container UID/GID.
```

Fix on NFS server:

```bash
sudo chown -R 999:999 /export/otp-relay-data
sudo chmod -R u+rwX,g+rwX /export/otp-relay-data
```

Validate:

```bash
sudo k3s kubectl -n otp-relay get pods -l app=otp-relay -o name | while read p; do
  echo "=== $p ==="
  sudo k3s kubectl -n otp-relay exec "${p#pod/}" -- sh -c '
    id
    touch /app/data/write-test &&
    rm -f /app/data/write-test &&
    echo WRITE_OK || echo WRITE_FAILED
  '
done
```

### Redis StatefulSet is not fully ready

Check:

```bash
sudo k3s kubectl -n otp-relay get statefulset otp-redis
sudo k3s kubectl -n otp-relay get pods -l app=otp-redis -o wide
sudo k3s kubectl -n otp-relay describe pod otp-redis-<N>
sudo k3s kubectl -n otp-relay logs otp-redis-<N>
```

### Sentinel or HAProxy did not spread

Check live deployment rules:

```bash
sudo k3s kubectl -n otp-relay get deployment otp-redis-haproxy -o yaml | grep -A45 -E 'affinity:|topologySpreadConstraints:'
sudo k3s kubectl -n otp-relay get deployment otp-redis-sentinel -o yaml | grep -A45 -E 'affinity:|topologySpreadConstraints:'
```

Restart deployments:

```bash
sudo k3s kubectl -n otp-relay rollout restart deployment/otp-redis-sentinel
sudo k3s kubectl -n otp-relay rollout restart deployment/otp-redis-haproxy
```

Check placement:

```bash
sudo k3s kubectl -n otp-relay get pods -o wide | egrep 'redis-sentinel|redis-haproxy|NAME'
```

---

## Useful commands

```bash
sudo k3s kubectl get all -n otp-relay
sudo k3s kubectl get nodes -o wide
sudo k3s kubectl get pods -n otp-relay -o wide
sudo k3s kubectl get svc -n otp-relay
sudo k3s kubectl get ingress -n otp-relay
sudo k3s kubectl get pvc -n otp-relay
sudo k3s kubectl get pv
sudo k3s kubectl get events -n otp-relay --sort-by=.lastTimestamp
```

Logs:

```bash
sudo k3s kubectl logs -n otp-relay deployment/otp-relay --tail=200
sudo k3s kubectl logs -n otp-relay deployment/otp-monitor --tail=200
sudo k3s kubectl logs -n otp-relay deployment/otp-redis-sentinel --tail=200
sudo k3s kubectl logs -n otp-relay deployment/otp-redis-haproxy --tail=200
```

Rollouts:

```bash
sudo k3s kubectl -n otp-relay rollout status deployment/otp-relay
sudo k3s kubectl -n otp-relay rollout restart deployment/otp-relay
sudo k3s kubectl -n otp-relay rollout status deployment/otp-monitor
sudo k3s kubectl -n otp-relay rollout status deployment/otp-redis-sentinel
sudo k3s kubectl -n otp-relay rollout status deployment/otp-redis-haproxy
```

Endpoints:

```bash
curl -k https://srvotptest26.init-db.lan/healthz
curl -k https://srvotptest26.init-db.lan/readyz
```

Service endpoints:

```bash
sudo k3s kubectl -n otp-relay get endpoints otp-relay -o wide
sudo k3s kubectl -n otp-relay get endpoints otp-redis-haproxy -o wide
sudo k3s kubectl -n otp-relay get endpoints otp-redis-sentinel -o wide
```

---

## Help documentation source

Portal help source lives under:

```text
docs/help/
```

Current help pages:

```text
00-overview.md
01-new-user-onboarding.md
02-reset-rta-password.md
03-configure-oracle-authenticator.md
04-request-rdp-sftp-pam-access.md
05-install-rta-vpn.md
06-renew-rdp-sftp-pam-access.md
07-install-winscp.md
08-use-pam.md
09-rta-it-support-ticket.md
10-terminal-server-access.md
11-notes-and-tips.md
```

Help screenshots live under:

```text
docs/help/assets/
```

The help source is generated into portal-consumable files by:

```text
scripts/build_help_docs.py
```

Build help docs during deployment, not manually inside the running pod.

---

## Branches

Use the Kubernetes branch/repository as the source of truth for this deployment.

Do not copy stale deployment instructions from older portal or Pi-specific branches into this repo.

For this Kubernetes repository, use:

```text
Ubuntu 24.04 VM / Debian K3s node terminology
company server
server
runner host
self-hosted runner
```

Do not describe this branch as a Raspberry Pi deployment.

---

## Current checkpoint

This checkpoint is ready for SCH review:

```text
Portal load balancing validated.
Portal pod failover validated.
Node-level portal failover validated.
NFS shared write fixed and validated.
Redis Sentinel spread one-per-node validated.
Redis HAProxy spread across workers validated.
Health monitor passed.
```

Final expected health result:

```text
OK: OTP Relay K3s deployment is healthy.
```
