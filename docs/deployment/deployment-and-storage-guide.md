# Deployment and Storage Guide

## Purpose

This guide is the single deployment reference for OTP Relay Kubernetes. It combines the previous GitHub Actions deployment guide, K3s setup notes, manual image fallback, and NFS shared-storage migration notes.

## Recommended deployment path

Use GitHub Actions with the self-hosted runner.

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

The workflow intentionally calls `install-otp-relay-k8s.sh` instead of duplicating deployment logic in YAML.

## Required GitHub Actions secrets

Create these in GitHub Actions secrets:

```text
PHONE_IP
PHONE_INTERFACE
WHATSAPP_API_KEY
WHATSAPP_RECIPIENT
PORTAL_URL
```

Do not commit WhatsApp credentials, runtime tokens, generated secrets, or `.env` files.

## Current Phase 3 deployment defaults

Current validation values:

```text
SERVICE_TYPE=LoadBalancer
INGRESS_ENABLED=1
TLS_ENABLED=1
TLS_HOST=srvotptest26.init-db.lan
TLS_SECRET_NAME=otp-relay-tls
TLS_SELF_SIGNED=1
INSTALL_METALLB=0
REQUIRE_METALLB=1
LOADBALANCER_IP=
REDIS_ENABLED=1
REDIS_REQUIRED=1
REDIS_URL=redis://otp-redis:6379/0
NFS_ENABLED=1
NFS_SERVER=172.31.11.108
NFS_PATH=/export/otp-relay-data
NFS_STORAGE_CLASS=otp-relay-nfs
PVC_STORAGE_CLASS=otp-relay-nfs
REPLICA_COUNT=1
```

`REPLICA_COUNT=1` is intentional until final OTP and worker-drain validation are complete.

## MetalLB, Traefik, and TLS

The current validation path uses:

- MetalLB for LoadBalancer IP allocation.
- Traefik Ingress for HTTP/HTTPS routing.
- Kubernetes TLS secret for HTTPS.
- Self-signed TLS until IT distributes/trusts the certificate by Group Policy.

Validate exposure after deployment:

```bash
kubectl get svc -n otp-relay
kubectl get ingress -n otp-relay
kubectl get secret otp-relay-tls -n otp-relay
curl -k https://srvotptest26.init-db.lan/healthz
curl -k https://srvotptest26.init-db.lan/readyz
```

## NFS/RWX application storage

The app data PVC should use shared NFS/RWX storage after migration.

Expected NFS export:

```text
NFS server: 172.31.11.108
NFS path:   /export/otp-relay-data
```

Expected Kubernetes storage:

```text
PV:            otp-relay-data-nfs-pv
PVC:           otp-relay-data
StorageClass:  otp-relay-nfs
Access mode:   ReadWriteMany
Mount path:    /app/data
```

Expected files in `/app/data`:

```text
users.xlsx
admin_auth.json
admin_config.json
wizard_progress.json
audit.log
```

The monitor also reads the shared audit log from this storage path.

## Existing PVC migration rule

Before moving an existing live deployment from local-path/RWO to NFS/RWX:

1. Scale the app and monitor safely if needed.
2. Back up the existing `/app/data` contents.
3. Confirm the NFS export exists and is mounted by Kubernetes.
4. Restore app data onto the NFS export.
5. Apply `pv-nfs.yaml` and the updated PVC settings.
6. Restart the app and monitor.
7. Verify that `users.xlsx`, config files, wizard progress, and `audit.log` are present.

Do not delete old PVC data until the NFS-backed deployment is verified.

## Redis deployment model

Redis is required in the Phase 3 validation posture.

Redis components:

```text
redis-statefulset.yaml
redis-service.yaml
redis-pdb.yaml
redis-sentinel-configmap.yaml
redis-sentinel-deployment.yaml
redis-sentinel-service.yaml
redis-haproxy-configmap.yaml
redis-haproxy-deployment.yaml
```

The app keeps using:

```text
REDIS_URL=redis://otp-redis:6379/0
```

`otp-redis` points to HAProxy, and HAProxy routes to the current Redis master.

## Manual image build fallback

GitHub Actions is preferred. Manual build is only a fallback.

Build locally from the repo root:

```bash
docker build -t otp-relay:latest -f k8s/Dockerfile .
docker build -t otp-monitor:latest -f k8s/Dockerfile.monitor .
```

Export images:

```bash
docker save otp-relay:latest -o otp-relay-latest.tar
docker save otp-monitor:latest -o otp-monitor-latest.tar
```

Import on the K3s node:

```bash
sudo k3s ctr images import otp-relay-latest.tar
sudo k3s ctr images import otp-monitor-latest.tar
```

Restart workloads:

```bash
kubectl rollout restart deployment/otp-relay -n otp-relay
kubectl rollout restart deployment/otp-monitor -n otp-relay
kubectl rollout status deployment/otp-relay -n otp-relay
kubectl rollout status deployment/otp-monitor -n otp-relay
```

## Post-deployment verification

Run these after deployment:

```bash
kubectl get pods -n otp-relay -o wide
kubectl get svc -n otp-relay
kubectl get ingress -n otp-relay
kubectl get pvc -n otp-relay
kubectl logs -n otp-relay deployment/otp-relay --tail=100
kubectl logs -n otp-relay deployment/otp-monitor --tail=100
curl -k https://srvotptest26.init-db.lan/healthz
curl -k https://srvotptest26.init-db.lan/readyz
```

Expected `/readyz` result should include Redis healthy and Redis required.
