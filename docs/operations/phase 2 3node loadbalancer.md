# Phase 2: 3-node and LoadBalancer alignment

Phase 2 keeps the Phase 1 source-of-truth model:

```text
GitHub main → GitHub Actions → installer → K3s
```

It adds cluster options without moving deployment logic out of the installer.

## Supported Phase 2 options

```text
SERVICE_TYPE=NodePort|LoadBalancer
LOADBALANCER_IP=
INSTALL_METALLB=0|1
REQUIRE_METALLB=0|1
METALLB_IP_RANGE=
PVC_STORAGE_CLASS=
PVC_SIZE=1Gi
APP_NODE_SELECTOR_KEY=
APP_NODE_SELECTOR_VALUE=
MONITOR_NODE_SELECTOR_KEY=
MONITOR_NODE_SELECTOR_VALUE=
REPLICA_COUNT=1
```

## Why replicas remain 1

The app currently keeps these in process memory:

```text
claim_queue
pending_otps
ADMIN_SESSIONS
```

Multiple replicas would create multiple independent queues. True high availability requires moving shared state to Redis, a database, or another shared backend. That is outside Phase 2.

## Recommended 3-node values

```text
SERVICE_TYPE=LoadBalancer
INGRESS_ENABLED=0
INSTALL_METALLB=1
REQUIRE_METALLB=1
METALLB_IP_RANGE=172.31.11.120-172.31.11.130
LOADBALANCER_IP=
APP_NODE_SELECTOR_KEY=kubernetes.io/hostname
APP_NODE_SELECTOR_VALUE=<app-node>
MONITOR_NODE_SELECTOR_KEY=kubernetes.io/hostname
MONITOR_NODE_SELECTOR_VALUE=<phone-network-node>
PVC_STORAGE_CLASS=local-path
PVC_SIZE=1Gi
REPLICA_COUNT=1
```

Choose a MetalLB IP range that is outside DHCP and unused on the LAN.

## GitHub source of truth

Phase 2 deployments use the committed Dockerfiles and manifests as source. The installer only stages and renders runtime values before applying them to K3s. For MetalLB auto-assignment, keep `LOADBALANCER_IP=` blank and read the assigned IP from the `otp-relay` Service.
