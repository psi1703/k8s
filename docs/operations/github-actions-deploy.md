# GitHub Actions deployment for OTP Relay K3s

This is the recommended deployment path for the OTP Relay Kubernetes repository.

```text
git push to main
  ↓
GitHub Actions job starts
  ↓
self-hosted runner checks out the repo
  ↓
installer syncs /opt/otp-relay-k8s to origin/main
  ↓
installer builds app.js, help docs, images, generated manifests
  ↓
installer imports images into K3s
  ↓
installer applies resources and waits for rollouts
```

The workflow intentionally calls `install-otp-relay-k8s.sh` from the checked-out commit instead of duplicating deployment logic in YAML.

---

## Required secrets

Create these in GitHub Actions secrets:

```text
PHONE_IP
PHONE_INTERFACE
WHATSAPP_API_KEY
WHATSAPP_RECIPIENT
PORTAL_URL
```

Do not commit WhatsApp credentials or runtime secrets.

---

## Default single-server mode

Default workflow values preserve the current Debian server deployment:

```yaml
SERVICE_TYPE: NodePort
SERVICE_NODE_PORT: "30080"
INGRESS_ENABLED: "1"
INSTALL_METALLB: "0"
REQUIRE_METALLB: "0"
REPLICA_COUNT: "1"
```

---

## 3-node / LoadBalancer mode

Manual workflow dispatch can use:

```yaml
SERVICE_TYPE: LoadBalancer
INGRESS_ENABLED: "0"
INSTALL_METALLB: "1"
REQUIRE_METALLB: "1"
METALLB_IP_RANGE: 172.31.11.120-172.31.11.130
LOADBALANCER_IP: 172.31.11.120
APP_NODE_SELECTOR_KEY: kubernetes.io/hostname
APP_NODE_SELECTOR_VALUE: <app-node-name>
MONITOR_NODE_SELECTOR_KEY: kubernetes.io/hostname
MONITOR_NODE_SELECTOR_VALUE: <phone-network-node-name>
PVC_STORAGE_CLASS: local-path
PVC_SIZE: 1Gi
```

`REPLICA_COUNT` remains `1` because the queue, pending OTPs, and admin sessions are in process memory.

---

## MetalLB behavior

If `INSTALL_METALLB=1`, the installer:

1. applies the MetalLB native manifest
2. waits for CRDs
3. waits for controller and speaker readiness
4. creates an `IPAddressPool`
5. creates an `L2Advertisement`

If `INSTALL_METALLB=0` and `SERVICE_TYPE=LoadBalancer`, the installer only checks whether MetalLB is already present.

Set `REQUIRE_METALLB=1` to fail fast if MetalLB is not installed.

---

## Operational checks

```bash
sudo k3s kubectl get nodes -o wide
sudo k3s kubectl get storageclass
sudo k3s kubectl get pods -n metallb-system
sudo k3s kubectl get pods,svc,ingress -n otp-relay
sudo k3s kubectl logs -n otp-relay deployment/otp-relay --tail=100
sudo k3s kubectl logs -n otp-relay deployment/otp-monitor --tail=100
```

After each deploy:

```bash
cd /opt/otp-relay-k8s
git status
```

Expected:

```text
nothing to commit, working tree clean
```
