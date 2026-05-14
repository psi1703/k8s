# Operations and Validation Runbook

## Purpose

This runbook is the single operations and validation reference for OTP Relay Kubernetes. It combines the current Phase 3 resilience validation state with the practical commands needed for day-to-day checks and remaining SCH validation.

## Current validated state

Validated cluster baseline:

```text
3-node K3s cluster
NFS/RWX app storage for /app/data
Redis Sentinel/HAProxy topology
Redis failover validated
Traefik HTTPS ingress enabled
MetalLB LoadBalancer exposure
Monitor pod isolated from Service/Ingress
```

Known node labels used for OTP Relay placement:

```text
otp-relay/storage-node=true
otp-relay/monitor-node=true
```

The monitor remains pinned to the node with phone-network visibility. Redis-capable nodes are labelled with `otp-relay/storage-node=true`.

## Daily health checks

```bash
kubectl get nodes -o wide
kubectl get pods -n otp-relay -o wide
kubectl get svc -n otp-relay
kubectl get ingress -n otp-relay
kubectl get pvc -n otp-relay
```

Application endpoints:

```bash
curl -k https://srvotptest26.init-db.lan/healthz
curl -k https://srvotptest26.init-db.lan/readyz
```

Expected:

- `/healthz` returns OK.
- `/readyz` returns Redis OK and Redis required.
- App pod is Running/Ready.
- Monitor pod is Running/Ready.
- Redis, Sentinel, and HAProxy pods are Running/Ready.

## Application storage checks

Confirm app PVC:

```bash
kubectl get pv,pvc -n otp-relay
kubectl describe pvc otp-relay-data -n otp-relay
```

Expected app storage:

```text
PVC:           otp-relay-data
PV:            otp-relay-data-nfs-pv
Access mode:   RWX
StorageClass:  otp-relay-nfs
NFS path:      /export/otp-relay-data
Mount path:    /app/data
```

Confirm runtime files from the app pod:

```bash
kubectl exec -n otp-relay deployment/otp-relay -- ls -l /app/data
```

Expected files:

```text
users.xlsx
admin_auth.json
admin_config.json
wizard_progress.json
audit.log
```

Confirm monitor can see the shared audit log:

```bash
kubectl exec -n otp-relay deployment/otp-monitor -- ls -l /app/data/audit.log
```

## Redis/Sentinel/HAProxy checks

List Redis-related pods:

```bash
kubectl get pods -n otp-relay -o wide | grep -E 'redis|haproxy'
```

Check Redis service:

```bash
kubectl get svc -n otp-relay | grep redis
```

Check Sentinel logs:

```bash
kubectl logs -n otp-relay deployment/otp-redis-sentinel --tail=100
```

Check HAProxy logs:

```bash
kubectl logs -n otp-relay deployment/otp-redis-haproxy --tail=100
```

The app should continue using:

```text
redis://otp-redis:6379/0
```

`otp-redis` should route to HAProxy, which then routes to the current Redis master.

## Redis failover validation

Redis HA/Sentinel/HAProxy failover has been validated as a Phase 3 foundation. Repeat only during a controlled maintenance/test window.

Before testing:

```bash
kubectl get pods -n otp-relay -o wide | grep redis
curl -k https://srvotptest26.init-db.lan/readyz
```

During failover, delete or stop the current Redis master pod according to the planned test method, then watch:

```bash
kubectl get pods -n otp-relay -w
kubectl logs -n otp-relay deployment/otp-redis-sentinel --tail=200
curl -k https://srvotptest26.init-db.lan/readyz
```

Pass criteria:

- Sentinel promotes a new master.
- HAProxy routes to the new master.
- `/readyz` returns Redis OK after recovery.
- The app does not need a Redis URL change.

## TLS and ingress checks

```bash
kubectl get ingress -n otp-relay
kubectl describe ingress -n otp-relay
kubectl get secret otp-relay-tls -n otp-relay
curl -k https://srvotptest26.init-db.lan/healthz
```

Expected:

- Ingress host is `srvotptest26.init-db.lan`.
- TLS secret exists.
- HTTPS endpoint works.
- Browser warning may remain until IT distributes/trusts the certificate by Group Policy.

## Monitor checks

The monitor is required and must not be exposed publicly.

Check pod and logs:

```bash
kubectl get pods -n otp-relay -o wide | grep monitor
kubectl logs -n otp-relay deployment/otp-monitor --tail=100
```

Expected monitor properties:

- `hostNetwork: true`.
- `NET_RAW` capability.
- No Service.
- No Ingress.
- Can check phone presence on the configured phone network.
- Can read `/app/data/audit.log`.
- Can send WhatsApp alerts when configured.

## OTP validation checklist

Run this before approving multi-replica app validation:

- Login page loads through HTTPS.
- User token login works.
- OTP claim flow works.
- iPhone Shortcut posts SMS to `/sms-received`.
- OTP appears on screen for the waiting user.
- Audit log records the flow.
- Manager live OTP trigger test passes.
- Pending OTP survives app restart when Redis is healthy.
- Two-replica OTP flow works in a controlled test.

Do not make two replicas the default until these checks pass.

## DNS/TLS client validation checklist

- `srvotptest26.init-db.lan` resolves from user machines.
- HTTPS loads from user machines.
- Certificate trust warning is gone after Group Policy trust rollout.
- Portal works from the intended client network.
- iPhone Shortcut target URL is correct after DNS/TLS finalization.

## Worker-drain validation checklist

Run only in a controlled test window.

Before drain:

```bash
kubectl get pods -n otp-relay -o wide
curl -k https://srvotptest26.init-db.lan/readyz
```

Drain one worker according to SCH-approved procedure, then verify:

- App pod reschedules or remains healthy according to placement rules.
- Redis Sentinel/HAProxy remains healthy.
- Redis master remains available or fails over correctly.
- NFS app storage remains mounted.
- `/readyz` returns healthy after the cluster settles.
- OTP flow still works after recovery.

## Useful commands

```bash
kubectl get all -n otp-relay
kubectl get pods -n otp-relay -o wide
kubectl describe pod -n otp-relay <pod-name>
kubectl logs -n otp-relay deployment/otp-relay --tail=200
kubectl logs -n otp-relay deployment/otp-monitor --tail=200
kubectl rollout status deployment/otp-relay -n otp-relay
kubectl rollout restart deployment/otp-relay -n otp-relay
kubectl get events -n otp-relay --sort-by=.lastTimestamp
```

## Current validation summary

| Area | Status |
|---|---|
| K3s 3-node baseline | Validated |
| NFS/RWX app storage | Validated |
| Redis HA/Sentinel/HAProxy topology | Validated |
| Redis failover | Validated |
| `/readyz` with Redis required | Validated |
| TLS/Ingress | Enabled; client trust rollout pending |
| Monitor isolation | Aligned |
| App multi-replica default | Not yet approved |
| Worker-drain validation | Pending |
