#!/usr/bin/env bash
# OTP Relay K3s — preflight check
#
# Run this on the K3s control-plane node before deploying or validating OTP Relay.
#
# This script checks whether the cluster is ready for the OTP Relay Kubernetes
# deployment used by this repo:
#
# - K3s reachable
# - nodes Ready
# - namespace/manifests present
# - Traefik ingress controller present
# - Klipper servicelb disabled
# - MetalLB warning/validation depending on SERVICE_TYPE
# - NFS server reachable
# - OTP Relay app/monitor images available locally where possible
# - required Kubernetes workloads/manifests present
# - monitor configuration values present
# - phone network interface exists when PHONE_INTERFACE is configured
#
# Usage:
#   bash scripts/preflight-k3s.sh
#
# Optional env:
#   SERVICE_TYPE=ClusterIP
#   INGRESS_ENABLED=1
#   TLS_ENABLED=1
#   TLS_HOST=srvotptest26.init-db.lan
#   NFS_SERVER=172.31.11.108
#   NFS_PATH=/export/otp-relay-data
#   PHONE_INTERFACE=<interface-name>
#   PHONE_IP=<iphone-or-phone-ip>
#
# Notes:
# - The runtime monitor service is required. It checks phone/iPhone presence,
#   tails audit.log, and sends WhatsApp alerts when configured.
# - /usr/local/bin/otp-relayk3s-monitor.sh is a separate deployment health
#   check script and is not the same thing as the runtime monitor pod.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

pass() { echo -e "  ${GREEN}OK${NC}   $1"; }
fail() { echo -e "  ${RED}FAIL${NC} $1"; ERRORS=$((ERRORS + 1)); }
warn() { echo -e "  ${YELLOW}WARN${NC} $1"; WARNINGS=$((WARNINGS + 1)); }

KUBECTL="${KUBECTL:-sudo k3s kubectl}"

NAMESPACE="${NAMESPACE:-otp-relay}"
SERVICE_TYPE="${SERVICE_TYPE:-ClusterIP}"
INGRESS_ENABLED="${INGRESS_ENABLED:-1}"
TLS_ENABLED="${TLS_ENABLED:-1}"
TLS_HOST="${TLS_HOST:-srvotptest26.init-db.lan}"

NFS_ENABLED="${NFS_ENABLED:-1}"
NFS_SERVER="${NFS_SERVER:-172.31.11.108}"
NFS_PATH="${NFS_PATH:-/export/otp-relay-data}"
PVC_STORAGE_CLASS="${PVC_STORAGE_CLASS:-otp-relay-nfs}"

PHONE_INTERFACE="${PHONE_INTERFACE:-}"
PHONE_IP="${PHONE_IP:-}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd 2>/dev/null || pwd)"

echo "=== OTP Relay K3s Preflight Check ==="
echo ""
echo "Repo root: $REPO_ROOT"
echo "Namespace: $NAMESPACE"
echo "Service type: $SERVICE_TYPE"
echo "Ingress enabled: $INGRESS_ENABLED"
echo "TLS enabled: $TLS_ENABLED"
echo "TLS host: $TLS_HOST"
echo ""

# ── 1. K3s / kubectl reachability ────────────────────────────────────────────
echo "Cluster:"
if $KUBECTL get nodes >/dev/null 2>&1; then
    NODE_COUNT="$($KUBECTL get nodes --no-headers | wc -l | tr -d ' ')"
    READY_COUNT="$($KUBECTL get nodes --no-headers | awk '$2 == "Ready" {count++} END {print count+0}')"

    if [ "$NODE_COUNT" -gt 0 ] && [ "$READY_COUNT" -eq "$NODE_COUNT" ]; then
        pass "K3s cluster reachable ($READY_COUNT/$NODE_COUNT nodes Ready)"
    else
        fail "K3s cluster reachable but not all nodes are Ready ($READY_COUNT/$NODE_COUNT)"
        $KUBECTL get nodes -o wide || true
    fi
else
    fail "Cannot reach K3s cluster"
    echo "       Fix: check K3s service:"
    echo "       sudo systemctl status k3s"
    echo "       sudo systemctl start k3s"
    exit 1
fi

# ── 2. Node overview ─────────────────────────────────────────────────────────
echo ""
echo "Nodes:"
$KUBECTL get nodes -o wide || true

# ── 3. Klipper servicelb should be disabled ──────────────────────────────────
echo ""
echo "K3s service load balancer:"
SVCLB_PODS="$($KUBECTL get pods -A --no-headers 2>/dev/null | grep -c 'svclb-' || true)"
if [ "$SVCLB_PODS" -gt 0 ]; then
    fail "Klipper servicelb appears active ($SVCLB_PODS svclb pods found)"
    echo "       Expected for this repo: disable K3s servicelb and use Traefik/Ingress path."
    echo "       Fix in /etc/rancher/k3s/config.yaml:"
    echo "       disable:"
    echo "         - servicelb"
    echo "       then:"
    echo "       sudo systemctl restart k3s"
else
    pass "Klipper servicelb is disabled"
fi

# ── 4. Traefik / Ingress ─────────────────────────────────────────────────────
echo ""
echo "Ingress:"
if [ "$INGRESS_ENABLED" = "1" ]; then
    TRAEFIK_PODS="$($KUBECTL get pods -n kube-system --no-headers 2>/dev/null | grep -i traefik | grep -c Running || true)"
    if [ "$TRAEFIK_PODS" -gt 0 ]; then
        pass "Traefik appears to be running ($TRAEFIK_PODS running pod(s))"
    else
        fail "Ingress is enabled but Traefik is not running"
        echo "       Fix: check K3s Traefik installation or kube-system pods."
    fi
else
    warn "Ingress is disabled by env; portal exposure may use another path"
fi

# ── 5. MetalLB ────────────────────────────────────────────────────────────────
echo ""
echo "MetalLB:"
METALLB_PODS="$($KUBECTL get pods -n metallb-system --no-headers 2>/dev/null | grep -c Running || true)"
POOL_COUNT="$($KUBECTL get ipaddresspool -n metallb-system --no-headers 2>/dev/null | wc -l | tr -d ' ' || true)"

if [ "$SERVICE_TYPE" = "LoadBalancer" ]; then
    if [ "$METALLB_PODS" -ge 2 ]; then
        pass "MetalLB is running ($METALLB_PODS running pod(s))"
    else
        fail "SERVICE_TYPE=LoadBalancer but MetalLB is not running"
    fi

    if [ "$POOL_COUNT" -gt 0 ]; then
        POOL_ADDRS="$($KUBECTL get ipaddresspool -n metallb-system -o jsonpath='{.items[0].spec.addresses[0]}' 2>/dev/null || true)"
        pass "MetalLB IP pool configured (${POOL_ADDRS:-unknown})"
    else
        fail "SERVICE_TYPE=LoadBalancer but no MetalLB IP pool was found"
    fi
else
    if [ "$METALLB_PODS" -ge 2 ]; then
        pass "MetalLB is installed ($METALLB_PODS running pod(s)); not required for SERVICE_TYPE=$SERVICE_TYPE"
    else
        warn "MetalLB is not running; acceptable when SERVICE_TYPE=$SERVICE_TYPE"
    fi
fi

# ── 6. Repository files / manifests ──────────────────────────────────────────
echo ""
echo "Repository files:"

check_file() {
    local path="$1"
    local label="$2"

    if [ -f "$REPO_ROOT/$path" ]; then
        pass "$label exists: $path"
    else
        fail "$label missing: $path"
    fi
}

check_dir() {
    local path="$1"
    local label="$2"

    if [ -d "$REPO_ROOT/$path" ]; then
        pass "$label exists: $path"
    else
        fail "$label missing: $path"
    fi
}

check_file "main.py" "FastAPI app"
check_file "monitor.py" "Runtime monitor service"
check_file "install-otp-relay-k8s.sh" "Installer"
check_file "requirements.txt" "Python requirements"
check_dir "frontend" "Frontend directory"
check_dir "docs" "Docs directory"

# Manifest locations can differ by repo revision. Detect both common layouts.
MANIFEST_DIR=""
if [ -d "$REPO_ROOT/k8s/manifests" ]; then
    MANIFEST_DIR="k8s/manifests"
elif [ -d "$REPO_ROOT/k8s" ]; then
    MANIFEST_DIR="k8s"
else
    fail "Kubernetes manifest directory missing: expected k8s/ or k8s/manifests/"
fi

if [ -n "$MANIFEST_DIR" ]; then
    pass "Kubernetes manifest directory detected: $MANIFEST_DIR"

    for pattern in \
        "*namespace*.yaml" \
        "*deployment*.yaml" \
        "*service*.yaml" \
        "*ingress*.yaml" \
        "*redis*.yaml" \
        "*sentinel*.yaml" \
        "*haproxy*.yaml" \
        "*monitor*.yaml" \
        "*pvc*.yaml"
    do
        if find "$REPO_ROOT/$MANIFEST_DIR" -maxdepth 2 -type f -name "$pattern" | grep -q .; then
            pass "Manifest pattern found: $pattern"
        else
            warn "Manifest pattern not found under $MANIFEST_DIR: $pattern"
        fi
    done
fi

# ── 7. Namespace ─────────────────────────────────────────────────────────────
echo ""
echo "Namespace:"
if $KUBECTL get namespace "$NAMESPACE" >/dev/null 2>&1; then
    pass "Namespace $NAMESPACE exists"
else
    warn "Namespace $NAMESPACE does not exist yet; it should be created by namespace manifest"
fi

# ── 8. Runtime workloads if already deployed ─────────────────────────────────
echo ""
echo "Existing OTP Relay workloads:"

if $KUBECTL get namespace "$NAMESPACE" >/dev/null 2>&1; then
    check_workload() {
        local kind="$1"
        local name="$2"
        local required="$3"

        if $KUBECTL -n "$NAMESPACE" get "$kind" "$name" >/dev/null 2>&1; then
            pass "$kind/$name exists"
        else
            if [ "$required" = "required" ]; then
                warn "$kind/$name does not exist yet; expected after deployment"
            else
                warn "$kind/$name not found"
            fi
        fi
    }

    check_workload deployment otp-relay required
    check_workload deployment otp-monitor required
    check_workload statefulset otp-redis required
    check_workload deployment otp-redis-sentinel required
    check_workload deployment otp-redis-haproxy required
    check_workload service otp-relay required
    check_workload service otp-redis required
    check_workload service otp-redis-haproxy required
    check_workload service otp-redis-sentinel required

    if [ "$TLS_ENABLED" = "1" ]; then
        if $KUBECTL -n "$NAMESPACE" get ingress otp-relay >/dev/null 2>&1; then
            pass "Ingress otp-relay exists"
        else
            warn "TLS/Ingress expected but ingress otp-relay was not found yet"
        fi
    fi
else
    warn "Skipping workload checks because namespace $NAMESPACE does not exist"
fi

# ── 9. NFS / RWX app data ────────────────────────────────────────────────────
echo ""
echo "NFS / shared app data:"
if [ "$NFS_ENABLED" = "1" ]; then
    if command -v nc >/dev/null 2>&1; then
        if nc -z -w 3 "$NFS_SERVER" 2049 >/dev/null 2>&1; then
            pass "NFS server reachable on TCP/2049: $NFS_SERVER"
        else
            fail "NFS server not reachable on TCP/2049: $NFS_SERVER"
            echo "       Fix: check NFS server, firewall, export, and routing."
        fi
    else
        warn "nc is not installed; cannot test NFS TCP/2049 reachability"
        echo "       Optional install: sudo apt-get install -y netcat-openbsd"
    fi

    if $KUBECTL get storageclass "$PVC_STORAGE_CLASS" >/dev/null 2>&1; then
        pass "StorageClass exists: $PVC_STORAGE_CLASS"
    else
        warn "StorageClass not found: $PVC_STORAGE_CLASS"
    fi

    if $KUBECTL -n "$NAMESPACE" get pvc otp-relay-data >/dev/null 2>&1; then
        PVC_STATUS="$($KUBECTL -n "$NAMESPACE" get pvc otp-relay-data -o jsonpath='{.status.phase}' 2>/dev/null || true)"
        if [ "$PVC_STATUS" = "Bound" ]; then
            pass "PVC otp-relay-data is Bound"
        else
            fail "PVC otp-relay-data exists but is not Bound: ${PVC_STATUS:-unknown}"
        fi
    else
        warn "PVC otp-relay-data does not exist yet; expected after deployment"
    fi

    echo "       Reminder: NFS export $NFS_PATH should be writable by UID/GID 999:999."
else
    warn "NFS_ENABLED is not 1; this does not match current Phase 3 shared /app/data design"
fi

# ── 10. Local container images ───────────────────────────────────────────────
echo ""
echo "Local container images:"
if command -v sudo >/dev/null 2>&1 && sudo k3s ctr images list >/dev/null 2>&1; then
    for IMG in otp-relay:latest otp-monitor:latest; do
        if sudo k3s ctr images list | grep -q "$IMG"; then
            pass "Image present on this node: $IMG"
        else
            warn "Image not found on this node: $IMG"
            echo "       If pods can schedule here, import/build the image through the installer or workflow."
        fi
    done
else
    warn "Could not inspect local containerd images using sudo k3s ctr images list"
fi

echo "       Note: otp-relay and otp-monitor images must be available on nodes where those pods may schedule."

# ── 11. Monitor service requirements ─────────────────────────────────────────
echo ""
echo "Runtime monitor service:"
if [ -f "$REPO_ROOT/monitor.py" ]; then
    pass "monitor.py exists"
else
    fail "monitor.py missing"
fi

if [ -n "$MANIFEST_DIR" ] && find "$REPO_ROOT/$MANIFEST_DIR" -maxdepth 2 -type f -iname '*monitor*.yaml' | grep -q .; then
    MONITOR_FILES="$(find "$REPO_ROOT/$MANIFEST_DIR" -maxdepth 2 -type f -iname '*monitor*.yaml' | tr '\n' ' ')"
    pass "Monitor manifest found: $MONITOR_FILES"
else
    warn "Monitor manifest not found by filename pattern"
fi

if $KUBECTL -n "$NAMESPACE" get deployment otp-monitor >/dev/null 2>&1; then
    HOST_NETWORK="$($KUBECTL -n "$NAMESPACE" get deployment otp-monitor -o jsonpath='{.spec.template.spec.hostNetwork}' 2>/dev/null || true)"
    DNS_POLICY="$($KUBECTL -n "$NAMESPACE" get deployment otp-monitor -o jsonpath='{.spec.template.spec.dnsPolicy}' 2>/dev/null || true)"

    if [ "$HOST_NETWORK" = "true" ]; then
        pass "otp-monitor hostNetwork=true"
    else
        fail "otp-monitor should use hostNetwork=true for phone presence checks"
    fi

    if [ "$DNS_POLICY" = "ClusterFirstWithHostNet" ]; then
        pass "otp-monitor dnsPolicy=ClusterFirstWithHostNet"
    else
        warn "otp-monitor dnsPolicy is ${DNS_POLICY:-unset}; expected ClusterFirstWithHostNet"
    fi

    MONITOR_SVC_COUNT="$($KUBECTL -n "$NAMESPACE" get svc --no-headers 2>/dev/null | awk '$1 ~ /monitor/ {count++} END {print count+0}')"
    if [ "$MONITOR_SVC_COUNT" -eq 0 ]; then
        pass "No monitor Service found"
    else
        fail "Monitor should not be exposed with a Service"
    fi
else
    warn "otp-monitor deployment not present yet; runtime monitor checks will apply after deployment"
fi

# ── 12. Phone network interface / phone IP ───────────────────────────────────
echo ""
echo "Phone presence configuration:"
if [ -n "$PHONE_INTERFACE" ]; then
    if [ -e "/sys/class/net/$PHONE_INTERFACE" ]; then
        pass "PHONE_INTERFACE exists on this node: $PHONE_INTERFACE"
    else
        fail "PHONE_INTERFACE not found on this node: $PHONE_INTERFACE"
        echo "       Available interfaces:"
        ls /sys/class/net/ | grep -v '^lo$' | sed 's/^/       - /' || true
    fi
else
    warn "PHONE_INTERFACE is not set for preflight; skipping interface existence check"
    echo "       Run with: PHONE_INTERFACE=<interface> bash scripts/preflight-k3s.sh"
fi

if [ -n "$PHONE_IP" ]; then
    pass "PHONE_IP is set: $PHONE_IP"
else
    warn "PHONE_IP is not set for preflight"
fi

# ── 13. Portal URL / DNS / TLS ───────────────────────────────────────────────
echo ""
echo "Portal URL / DNS:"
if [ "$INGRESS_ENABLED" = "1" ]; then
    if getent hosts "$TLS_HOST" >/dev/null 2>&1; then
        HOST_IP="$(getent hosts "$TLS_HOST" | awk '{print $1}' | head -1)"
        pass "TLS_HOST resolves: $TLS_HOST -> $HOST_IP"
    else
        warn "TLS_HOST does not resolve from this node: $TLS_HOST"
        echo "       Fix: DNS should point $TLS_HOST to the ingress/load-balancer IP."
    fi

    if command -v curl >/dev/null 2>&1; then
        URL_SCHEME="http"
        CURL_TLS_FLAG=""
        if [ "$TLS_ENABLED" = "1" ]; then
            URL_SCHEME="https"
            CURL_TLS_FLAG="-k"
        fi

        READYZ_URL="${URL_SCHEME}://${TLS_HOST}/readyz"
        HTTP_CODE="$(curl $CURL_TLS_FLAG -sS -m 5 -o /tmp/otp-relay-preflight-readyz.out -w '%{http_code}' "$READYZ_URL" 2>/tmp/otp-relay-preflight-readyz.err || true)"

        if [ "$HTTP_CODE" = "200" ]; then
            pass "Portal readyz returned 200: $READYZ_URL"
        else
            warn "Portal readyz did not return 200: $READYZ_URL HTTP_CODE=${HTTP_CODE:-000}"
            if [ -s /tmp/otp-relay-preflight-readyz.err ]; then
                sed 's/^/       /' /tmp/otp-relay-preflight-readyz.err || true
            fi
        fi
    else
        warn "curl is not installed; cannot test portal /readyz"
    fi
else
    warn "Ingress disabled; skipping TLS_HOST readyz check"
fi

# ── 14. Optional deployment health script ────────────────────────────────────
echo ""
echo "Deployment health-check script:"
if [ -x /usr/local/bin/otp-relayk3s-monitor.sh ]; then
    pass "/usr/local/bin/otp-relayk3s-monitor.sh exists and is executable"
else
    warn "/usr/local/bin/otp-relayk3s-monitor.sh not found or not executable"
fi

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "=== Summary ==="
if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
    echo -e "${GREEN}All checks passed. Ready to deploy or validate OTP Relay.${NC}"
elif [ "$ERRORS" -eq 0 ]; then
    echo -e "${YELLOW}$WARNINGS warning(s), 0 errors. Review warnings before deploying.${NC}"
else
    echo -e "${RED}$ERRORS error(s), $WARNINGS warning(s). Fix errors before deploying.${NC}"
    exit 1
fi
