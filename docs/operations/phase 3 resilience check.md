# OTP Relay Kubernetes Phase 3 Resilience Validation

## Purpose

This document records the current Phase 3 resilience state for the OTP Relay Kubernetes deployment and the validation checks completed against SCH's target design.

The goal of this phase is to move the deployment from a single-node/single-storage posture toward a resilient 3-node K3s topology with:

- shared application data storage,
- Redis-backed shared runtime state,
- Redis high availability with Sentinel and HAProxy,
- pod distribution across nodes,
- monitor isolation from public ingress,
- TLS-enabled ingress.

## Current cluster topology

Validated cluster nodes:

```text
NAME           ROLE            STATUS
debian         control-plane   Ready
otp-worker-1   worker          Ready
otp-worker-2   worker          Ready
```

Node labels used for OTP Relay placement:

```text
debian         otp-relay/storage-node=true, otp-relay/monitor-node=true
otp-worker-1   otp-relay/storage-node=true
otp-worker-2   otp-relay/storage-node=true
```

The monitor remains pinned to the node with phone-network visibility. Redis-capable nodes are labelled with `otp-relay/storage-node=true`.

## Application storage

The app data PVC has been migrated from local-path/RWO storage to NFS-backed RWX storage.

Validated state:

```text
PVC:           otp-relay-data
PV:            otp-relay-data-nfs-pv
Access mode:   RWX
StorageClass:  otp-relay-nfs
NFS server:    172.31.11.108
NFS path:      /export/otp-relay-data
```

Validated app data files on `/app/data`:

```text
users.xlsx
admin_auth.json
admin_config.json
wizard_progress.json
audit.log
```

The monitor pod can also read `/app/data/audit.log`, confirming the shared app PVC is visible to both app and monitor components.

Result:

```text
Shared application storage: PASS
```

## Redis HA architecture

Redis was moved from a single Redis pod to a Sentinel-backed and HAProxy-fronted HA topology.

The app still uses the stable Redis URL:

```text
redis://otp-redis:6379/0
```

The `otp-redis` service now points to HAProxy. HAProxy routes Redis traffic to the current Redis master. Sentinel monitors Redis pods and performs master promotion when required.

Redis resources:

```text
StatefulSet:  otp-redis, 3 replicas
Service:      otp-redis, ClusterIP, HAProxy front door on 6379
Headless SVC: otp-redis-headless, Redis pod DNS
Sentinel:     otp-redis-sentinel, 3 replicas
HAProxy:      otp-redis-haproxy, 2 replicas
```

Redis runtime PVCs remain separate from app data:

```text
redis-data-otp-redis-0   RWO   local-path
redis-data-otp-redis-1   RWO   local-path
redis-data-otp-redis-2   RWO   local-path
```

The app data PVC `otp-relay-data` is not used for Redis.

Result:

```text
Redis HA/Sentinel/HAProxy topology: PASS
```

## Redis node spread

After adding Redis-capable labels to the worker nodes and adding preferred anti-affinity/topology spread rules, Redis components were spread across the 3-node K3s cluster.

Validated pod placement:

```text
otp-redis-0          debian
otp-redis-1          otp-worker-1
otp-redis-2          otp-worker-2

otp-redis-sentinel   debian
otp-redis-sentinel   otp-worker-1
otp-redis-sentinel   otp-worker-2

otp-redis-haproxy    debian
otp-redis-haproxy    otp-worker-2
```

Result:

```text
Redis/Sentinel/HAProxy node spread: PASS
```

## Redis failover validation

Initial Redis role check after node spread:

```text
otp-redis-0   role:master   connected_slaves:2
otp-redis-1   role:slave    master_host:otp-redis-0.otp-redis-headless.otp-relay.svc.cluster.local
otp-redis-2   role:slave    master_host:otp-redis-0.otp-redis-headless.otp-relay.svc.cluster.local
```

Sentinel initially reported:

```text
mymaster -> otp-redis-0.otp-redis-headless.otp-relay.svc.cluster.local:6379
```

A controlled failover test was performed by cordoning `debian` and deleting the current Redis master pod `otp-redis-0`. Sentinel promoted a worker-node Redis pod.

Validated post-failover state:

```text
otp-redis-2   role:master   connected_slaves:2
otp-redis-0   role:slave    master_host:otp-redis-2.otp-redis-headless.otp-relay.svc.cluster.local
otp-redis-1   role:slave    master_host:otp-redis-2.otp-redis-headless.otp-relay.svc.cluster.local
```

Sentinel reported:

```text
mymaster -> otp-redis-2.otp-redis-headless.otp-relay.svc.cluster.local:6379
```

Result:

```text
Redis cross-node Sentinel failover: PASS
```

## Application readiness validation

Readiness endpoint after NFS migration, Redis HA migration, node spread, and Redis failover:

```json
{"status":"ok","users_loaded":88,"redis":"ok","redis_required":true}
```

Result:

```text
Application readiness with Redis required: PASS
```

## TLS and ingress state

TLS remains enabled with a self-signed certificate. IT will distribute/trust the certificate through Group Policy.

Current ingress host:

```text
srvotptest26.init-db.lan
```

TLS secret:

```text
otp-relay-tls
```

Known pending item:

```text
DNS for srvotptest26.init-db.lan still needs to resolve to the ingress address from user/client networks.
```

Result:

```text
TLS enabled: PASS
DNS/client trust rollout: PENDING IT/DNS
```

## Monitor state

The monitor remains deployed as a required internal component.

Current behavior:

- no public Service or Ingress for monitor,
- uses `hostNetwork: true`,
- reads `/app/data/audit.log`,
- remains associated with the node that has phone-network visibility.

Validated monitor pod state:

```text
otp-monitor   1/1 Running   debian
```

Result:

```text
Monitor isolated from public ingress: PASS
```

## Current validation summary

| Area | Status |
|---|---|
| 3-node K3s cluster | PASS |
| NFS shared app storage | PASS |
| App PVC RWX migration | PASS |
| Redis HA topology | PASS |
| Redis Sentinel discovery | PASS |
| Redis HAProxy front door | PASS |
| Redis/Sentinel/HAProxy node spread | PASS |
| Redis cross-node failover | PASS |
| `/readyz` with Redis required | PASS |
| TLS enabled/self-signed | PASS |
| DNS/GPO trust rollout | PENDING |
| Application-level OTP flow test | PENDING |
| Full worker-node drain test | PENDING |

## Recommended next validation steps

### 1. Portal and OTP flow validation

Validate through the portal:

```text
admin login works
user list loads
OTP request flow works
OTP claim flow works
audit log updates
monitor reads audit log
WhatsApp alert behavior is still correct when triggered
```

### 2. DNS/TLS client validation

After IT/DNS updates:

```text
srvotptest26.init-db.lan resolves for users
self-signed certificate is trusted by managed clients via Group Policy
browser access works without certificate warning on managed clients
```

### 3. Controlled worker-node drain validation

Perform later, starting with a worker node, not the control-plane node.

Recommended order:

```text
1. Drain otp-worker-1.
2. Confirm app readiness remains OK.
3. Confirm Redis/Sentinel/HAProxy recover.
4. Uncordon otp-worker-1.
5. Repeat with otp-worker-2 if required.
```

Do not begin with the `debian` control-plane node.

## Useful commands

```bash
sudo k3s kubectl get nodes
sudo k3s kubectl get pods -n otp-relay -o wide
sudo k3s kubectl get pvc -n otp-relay
sudo k3s kubectl get pv
curl -k http://172.31.11.121/readyz
```

Check Redis roles:

```bash
for p in otp-redis-0 otp-redis-1 otp-redis-2; do
  echo "===== $p ====="
  sudo k3s kubectl exec -n otp-relay "$p" -- redis-cli info replication | grep -E 'role:|master_host:|connected_slaves:'
done
```

Check Sentinel master:

```bash
SENTINEL_POD="$(sudo k3s kubectl get pod -n otp-relay -l app=otp-redis-sentinel -o jsonpath='{.items[0].metadata.name}')"
sudo k3s kubectl exec -n otp-relay "$SENTINEL_POD" -- redis-cli -p 26379 sentinel get-master-addr-by-name mymaster
```

Check app data from app pod:

```bash
APP_POD="$(sudo k3s kubectl get pod -n otp-relay -l app=otp-relay -o jsonpath='{.items[0].metadata.name}')"
sudo k3s kubectl exec -n otp-relay "$APP_POD" -- ls -la /app/data
```

Check monitor audit-log access:

```bash
MONITOR_POD="$(sudo k3s kubectl get pod -n otp-relay -l app=otp-monitor -o jsonpath='{.items[0].metadata.name}')"
sudo k3s kubectl exec -n otp-relay "$MONITOR_POD" -- ls -la /app/data/audit.log
```
