#!/usr/bin/env bash
set -Eeuo pipefail

# Safe one-click installer/update script for psi1703/k8s OTP Relay.
# Installs/updates the portal app and the required monitor pod.
#
# Normal use:
#   sudo bash install-otp-relay-k8s.sh
#
# Installer controls:
#   REPO_URL, REPO_REF, INSTALL_DIR, NAMESPACE
#   APP_IMAGE, MONITOR_IMAGE, DEPLOY_MODE, GIT_CLEAN, NONINTERACTIVE
#   SKIP_HELP_DOCS_BUILD, RUNTIME_DATA_DIR
#
# Kubernetes topology/exposure controls:
#   SERVICE_TYPE=NodePort|LoadBalancer
#   SERVICE_NODE_PORT=30080
#   LOADBALANCER_IP=172.31.x.x
#   INGRESS_ENABLED=0|1
#   PVC_STORAGE_CLASS=<storage-class-name>
#   PVC_SIZE=1Gi
#   REPLICA_COUNT=1
#   APP_NODE_SELECTOR_KEY=kubernetes.io/hostname
#   APP_NODE_SELECTOR_VALUE=<node-name>
#   MONITOR_NODE_SELECTOR_KEY=kubernetes.io/hostname
#   MONITOR_NODE_SELECTOR_VALUE=<node-name>
#   REDIS_NODE_SELECTOR_KEY=kubernetes.io/hostname
#   REDIS_NODE_SELECTOR_VALUE=<node-name>
#   REQUIRE_METALLB=0|1
#   INSTALL_METALLB=0|1
#   METALLB_VERSION=v0.15.3
#   METALLB_IP_RANGE=172.31.11.120-172.31.11.130
#   METALLB_POOL_NAME=otp-relay-pool
#
# Runtime ConfigMap inputs:
#   PHONE_IP, PHONE_INTERFACE, PHONE_PING_INTERVAL, PHONE_OFFLINE_THRESHOLD
#   BATCH_WINDOW_SEC, ALERT_LEVEL, PORTAL_URL
#
# Runtime Secret inputs:
#   SMS_SECRET_TOKEN, WHATSAPP_API_KEY, WHATSAPP_RECIPIENT
#
# Optional GitHub runner setup:
#   INSTALL_GITHUB_RUNNER, GITHUB_RUNNER_URL, GITHUB_RUNNER_TOKEN,
#   GITHUB_RUNNER_DIR, RUNNER_ONLY

log() { printf '[otp-relay-k8s] %s\n' "$*"; }
warn() { printf '[otp-relay-k8s] WARNING: %s\n' "$*" >&2; }
fatal() { printf '[otp-relay-k8s] ERROR: %s\n' "$*" >&2; exit 1; }
cmd_exists() { command -v "$1" >/dev/null 2>&1; }
need_root() { [ "$(id -u)" -eq 0 ] || fatal "run as root: sudo bash $0"; }

need_root
export DEBIAN_FRONTEND=noninteractive
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

REPO_URL="${REPO_URL:-https://github.com/psi1703/k8s.git}"
REPO_REF="${REPO_REF:-main}"
INSTALL_DIR="${INSTALL_DIR:-/opt/otp-relay-k8s}"
NAMESPACE="${NAMESPACE:-otp-relay}"
APP_IMAGE="${APP_IMAGE:-otp-relay:latest}"
MONITOR_IMAGE="${MONITOR_IMAGE:-otp-monitor:latest}"
SERVICE_TYPE="${SERVICE_TYPE:-NodePort}"
SERVICE_NODE_PORT="${SERVICE_NODE_PORT:-30080}"
LOADBALANCER_IP="${LOADBALANCER_IP:-}"
INGRESS_ENABLED="${INGRESS_ENABLED:-1}"
PVC_STORAGE_CLASS="${PVC_STORAGE_CLASS:-}"
PVC_SIZE="${PVC_SIZE:-1Gi}"
REPLICA_COUNT="${REPLICA_COUNT:-1}"
APP_NODE_SELECTOR_KEY="${APP_NODE_SELECTOR_KEY:-}"
APP_NODE_SELECTOR_VALUE="${APP_NODE_SELECTOR_VALUE:-}"
MONITOR_NODE_SELECTOR_KEY="${MONITOR_NODE_SELECTOR_KEY:-}"
MONITOR_NODE_SELECTOR_VALUE="${MONITOR_NODE_SELECTOR_VALUE:-}"
REDIS_NODE_SELECTOR_KEY="${REDIS_NODE_SELECTOR_KEY:-}"
REDIS_NODE_SELECTOR_VALUE="${REDIS_NODE_SELECTOR_VALUE:-}"
REQUIRE_METALLB="${REQUIRE_METALLB:-0}"
INSTALL_METALLB="${INSTALL_METALLB:-0}"
METALLB_VERSION="${METALLB_VERSION:-v0.15.3}"
METALLB_MANIFEST_URL="${METALLB_MANIFEST_URL:-https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/config/manifests/metallb-native.yaml}"
METALLB_IP_RANGE="${METALLB_IP_RANGE:-}"
METALLB_POOL_NAME="${METALLB_POOL_NAME:-otp-relay-pool}"
SERVER_HOSTNAME="${SERVER_HOSTNAME:-$(hostname -f 2>/dev/null || hostname)}"
SERVER_IP="${SERVER_IP:-$(hostname -I 2>/dev/null | awk '{print $1}') }"
SERVER_IP="$(printf '%s' "$SERVER_IP" | xargs)"
SERVER_IP="${SERVER_IP:-127.0.0.1}"
PORTAL_URL_EXPLICIT=0
if [ -n "${PORTAL_URL:-}" ]; then
  PORTAL_URL_EXPLICIT=1
fi
PORTAL_URL="${PORTAL_URL:-http://$SERVER_IP}"
ASSIGNED_LOADBALANCER_ADDRESS=""
PHONE_IP="${PHONE_IP:-172.31.10.161}"
PHONE_INTERFACE="${PHONE_INTERFACE:-$(ip route show default 2>/dev/null | awk '{print $5; exit}') }"
PHONE_INTERFACE="$(printf '%s' "$PHONE_INTERFACE" | xargs)"
PHONE_INTERFACE="${PHONE_INTERFACE:-eth0}"
PHONE_PING_INTERVAL="${PHONE_PING_INTERVAL:-150}"
PHONE_OFFLINE_THRESHOLD="${PHONE_OFFLINE_THRESHOLD:-2}"
BATCH_WINDOW_SEC="${BATCH_WINDOW_SEC:-10}"
ALERT_LEVEL="${ALERT_LEVEL:-error}"
WHATSAPP_API_KEY="${WHATSAPP_API_KEY:-}"
WHATSAPP_RECIPIENT="${WHATSAPP_RECIPIENT:-}"
RUNTIME_DATA_DIR="${RUNTIME_DATA_DIR:-}"
SKIP_HELP_DOCS_BUILD="${SKIP_HELP_DOCS_BUILD:-0}"
GIT_CLEAN="${GIT_CLEAN:-1}"
NONINTERACTIVE="${NONINTERACTIVE:-0}"
INSTALL_GITHUB_RUNNER="${INSTALL_GITHUB_RUNNER:-}"
GITHUB_RUNNER_URL="${GITHUB_RUNNER_URL:-${REPO_URL%.git}}"
GITHUB_RUNNER_TOKEN="${GITHUB_RUNNER_TOKEN:-}"
GITHUB_RUNNER_DIR="${GITHUB_RUNNER_DIR:-/opt/actions-runner}"
GITHUB_RUNNER_USER="${GITHUB_RUNNER_USER:-actions-runner}"
RUNNER_ONLY="${RUNNER_ONLY:-0}"
DEPLOY_MODE="${DEPLOY_MODE:-full}"
DOCKER_BIN="${DOCKER_BIN:-}"
REDIS_ENABLED="${REDIS_ENABLED:-1}"
REDIS_URL="${REDIS_URL:-redis://otp-redis:6379/0}"
REDIS_REQUIRED="${REDIS_REQUIRED:-1}"
REDIS_STORAGE_CLASS="${REDIS_STORAGE_CLASS:-local-path}"
REDIS_SIZE="${REDIS_SIZE:-1Gi}"
RESTART_APP_REQUIRED=0
RESTART_MONITOR_REQUIRED=0

OS_ID="unknown"
OS_NAME="unknown"
OS_VERSION_ID="unknown"
OS_LIKE=""
if [ -r /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  OS_ID="${ID:-unknown}"
  OS_NAME="${PRETTY_NAME:-${NAME:-unknown}}"
  OS_VERSION_ID="${VERSION_ID:-unknown}"
  OS_LIKE="${ID_LIKE:-}"
fi

ARCH_RAW="$(uname -m)"
case "$ARCH_RAW" in
  x86_64|amd64) RUNNER_ARCH="x64" ;;
  aarch64|arm64) RUNNER_ARCH="arm64" ;;
  armv7l|armv6l|armhf) RUNNER_ARCH="arm" ;;
  *) RUNNER_ARCH="" ;;
esac

IS_RPI=0
if grep -qi 'raspberry pi' /proc/cpuinfo 2>/dev/null || grep -qi 'raspberry pi' /proc/device-tree/model 2>/dev/null; then
  IS_RPI=1
fi

is_debian_family() {
  case "$OS_ID $OS_LIKE" in
    *debian*|*ubuntu*|*raspbian*) return 0 ;;
    *) return 1 ;;
  esac
}

prompt_yes_no() {
  prompt="$1"
  default="${2:-N}"
  if [ "$NONINTERACTIVE" = "1" ]; then
    [ "$default" = "Y" ]
    return $?
  fi
  printf '%s ' "$prompt"
  read -r answer || answer=""
  answer="${answer:-$default}"
  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

make_secret() {
  python3 - <<'PY' 2>/dev/null || tr -dc 'A-Fa-f0-9' </dev/urandom | head -c 64
import secrets
print(secrets.token_hex(32))
PY
}
SMS_SECRET_TOKEN="${SMS_SECRET_TOKEN:-$(make_secret)}"

write_runner_sudoers() {
  id -u "$GITHUB_RUNNER_USER" >/dev/null 2>&1 || useradd --system --create-home --shell /bin/bash "$GITHUB_RUNNER_USER"

  sudoers_file="/etc/sudoers.d/otp-relay-actions-runner"
  log "granting $GITHUB_RUNNER_USER narrow passwordless sudo for the OTP Relay installer"
  cat > "$sudoers_file" <<EOF_SUDOERS
$GITHUB_RUNNER_USER ALL=(root) NOPASSWD:SETENV: /bin/bash $INSTALL_DIR/install-otp-relay-k8s.sh
$GITHUB_RUNNER_USER ALL=(root) NOPASSWD:SETENV: /usr/bin/bash $INSTALL_DIR/install-otp-relay-k8s.sh
$GITHUB_RUNNER_USER ALL=(root) NOPASSWD:SETENV: /bin/bash $GITHUB_RUNNER_DIR/_work/*/*/install-otp-relay-k8s.sh
$GITHUB_RUNNER_USER ALL=(root) NOPASSWD:SETENV: /usr/bin/bash $GITHUB_RUNNER_DIR/_work/*/*/install-otp-relay-k8s.sh
EOF_SUDOERS
  chmod 0440 "$sudoers_file"
  visudo -cf "$sudoers_file" >/dev/null
}

install_github_runner() {
  [ "$INSTALL_GITHUB_RUNNER" = "1" ] || return 0

  write_runner_sudoers

  if systemctl list-unit-files | grep -q 'actions.runner'; then
    warn "an actions.runner systemd unit already exists; leaving existing runner registration untouched"
    return 0
  fi

  [ -n "$RUNNER_ARCH" ] || fatal "unsupported architecture for GitHub runner: $ARCH_RAW"
  [ -n "$GITHUB_RUNNER_URL" ] || fatal "INSTALL_GITHUB_RUNNER=1 requires GITHUB_RUNNER_URL"
  [ -n "$GITHUB_RUNNER_TOKEN" ] || fatal "INSTALL_GITHUB_RUNNER=1 requires GITHUB_RUNNER_TOKEN"

  log "installing GitHub Actions self-hosted runner before Docker/K3s deployment work"
  mkdir -p "$GITHUB_RUNNER_DIR"
  chown -R "$GITHUB_RUNNER_USER:$GITHUB_RUNNER_USER" "$GITHUB_RUNNER_DIR"

  runner_version="${GITHUB_RUNNER_VERSION:-2.328.0}"
  runner_tar="actions-runner-linux-${RUNNER_ARCH}-${runner_version}.tar.gz"
  runner_url="https://github.com/actions/runner/releases/download/v${runner_version}/${runner_tar}"
  curl -fL "$runner_url" -o "/tmp/$runner_tar"
  tar -xzf "/tmp/$runner_tar" -C "$GITHUB_RUNNER_DIR"
  rm -f "/tmp/$runner_tar"
  chown -R "$GITHUB_RUNNER_USER:$GITHUB_RUNNER_USER" "$GITHUB_RUNNER_DIR"

  sudo -u "$GITHUB_RUNNER_USER" bash -lc "cd '$GITHUB_RUNNER_DIR' && ./config.sh --unattended --url '$GITHUB_RUNNER_URL' --token '$GITHUB_RUNNER_TOKEN' --work _work"
  bash -lc "cd '$GITHUB_RUNNER_DIR' && ./svc.sh install '$GITHUB_RUNNER_USER' && ./svc.sh start"
}

resolve_docker_bin() {
  if [ -n "$DOCKER_BIN" ] && [ -x "$DOCKER_BIN" ]; then
    return 0
  fi
  if cmd_exists docker; then
    DOCKER_BIN="$(command -v docker)"
    return 0
  fi
  for candidate in /usr/bin/docker /usr/local/bin/docker /snap/bin/docker; do
    if [ -x "$candidate" ]; then
      DOCKER_BIN="$candidate"
      return 0
    fi
  done
  return 1
}

install_package_if_available() {
  pkg="$1"
  if apt-cache show "$pkg" >/dev/null 2>&1; then
    apt-get install -y --no-install-recommends "$pkg"
  fi
}

ensure_docker() {
  if ! resolve_docker_bin; then
    log "installing Docker because it is required to build and import local images"
    apt-get install -y --no-install-recommends docker.io
    install_package_if_available docker-cli
  fi

  if ! resolve_docker_bin; then
    fatal "Docker CLI is still not available after installing docker.io/docker-cli. On Debian 13, confirm the package provides /usr/bin/docker or install Docker CE CLI."
  fi

  if ! systemctl is-active --quiet docker; then
    log "starting Docker because it is required to build local images"
    systemctl enable --now docker
  else
    log "Docker already active; no restart performed"
  fi

  log "using Docker CLI: $DOCKER_BIN"
}

requires_docker() {
  case "$DEPLOY_MODE" in
    full|app|monitor) return 0 ;;
    *) return 1 ;;
  esac
}

requires_app_image() {
  case "$DEPLOY_MODE" in
    full|app) return 0 ;;
    *) return 1 ;;
  esac
}

requires_monitor_image() {
  case "$DEPLOY_MODE" in
    full|monitor) return 0 ;;
    *) return 1 ;;
  esac
}

requires_manifests_apply() {
  case "$DEPLOY_MODE" in
    full|app|monitor|manifests) return 0 ;;
    *) return 1 ;;
  esac
}

validate_k8s_topology_settings() {
  case "$SERVICE_TYPE" in
    NodePort|LoadBalancer) ;;
    *) fatal "unsupported SERVICE_TYPE=$SERVICE_TYPE. Use NodePort or LoadBalancer." ;;
  esac

  case "$REDIS_ENABLED" in
    0|1) ;;
    *) fatal "unsupported REDIS_ENABLED=$REDIS_ENABLED. Use 0 or 1." ;;
  esac

  case "$REDIS_REQUIRED" in
    0|1) ;;
    *) fatal "unsupported REDIS_REQUIRED=$REDIS_REQUIRED. Use 0 or 1." ;;
  esac

  if [ "$SERVICE_TYPE" = "NodePort" ]; then
    case "$SERVICE_NODE_PORT" in
      ''|*[!0-9]*) fatal "SERVICE_NODE_PORT must be numeric for SERVICE_TYPE=NodePort" ;;
    esac
    if [ "$SERVICE_NODE_PORT" -lt 30000 ] || [ "$SERVICE_NODE_PORT" -gt 32767 ]; then
      fatal "SERVICE_NODE_PORT must be between 30000 and 32767"
    fi
  fi

  if [ "$SERVICE_TYPE" = "LoadBalancer" ] && [ "$INGRESS_ENABLED" = "1" ]; then
    warn "SERVICE_TYPE=LoadBalancer and INGRESS_ENABLED=1 are both enabled. Usually one exposure path is enough."
  fi

  if [ "$REPLICA_COUNT" != "1" ]; then
    fatal "REPLICA_COUNT must remain 1 until the manager OTP trigger test and final two-replica OTP validation are complete."
  fi

  if { [ -n "$APP_NODE_SELECTOR_KEY" ] && [ -z "$APP_NODE_SELECTOR_VALUE" ]; } || { [ -z "$APP_NODE_SELECTOR_KEY" ] && [ -n "$APP_NODE_SELECTOR_VALUE" ]; }; then
    fatal "APP_NODE_SELECTOR_KEY and APP_NODE_SELECTOR_VALUE must be set together"
  fi

  if { [ -n "$MONITOR_NODE_SELECTOR_KEY" ] && [ -z "$MONITOR_NODE_SELECTOR_VALUE" ]; } || { [ -z "$MONITOR_NODE_SELECTOR_KEY" ] && [ -n "$MONITOR_NODE_SELECTOR_VALUE" ]; }; then
    fatal "MONITOR_NODE_SELECTOR_KEY and MONITOR_NODE_SELECTOR_VALUE must be set together"
  fi

  if { [ -n "$REDIS_NODE_SELECTOR_KEY" ] && [ -z "$REDIS_NODE_SELECTOR_VALUE" ]; } || { [ -z "$REDIS_NODE_SELECTOR_KEY" ] && [ -n "$REDIS_NODE_SELECTOR_VALUE" ]; }; then
    fatal "REDIS_NODE_SELECTOR_KEY and REDIS_NODE_SELECTOR_VALUE must be set together"
  fi
}

validate_selected_node() {
  label_key="$1"
  label_value="$2"
  label_name="$3"

  [ -n "$label_key" ] || return 0

  if ! k3s kubectl get node -l "$label_key=$label_value" -o name | grep -q .; then
    fatal "$label_name node selector did not match any node: $label_key=$label_value"
  fi
}

install_metallb_if_requested() {
  [ "$INSTALL_METALLB" = "1" ] || return 0

  [ "$SERVICE_TYPE" = "LoadBalancer" ] || fatal "INSTALL_METALLB=1 requires SERVICE_TYPE=LoadBalancer"
  [ -n "$METALLB_IP_RANGE" ] || fatal "INSTALL_METALLB=1 requires METALLB_IP_RANGE, for example 172.31.11.120-172.31.11.130"

  log "installing MetalLB $METALLB_VERSION from $METALLB_MANIFEST_URL"
  k3s kubectl apply -f "$METALLB_MANIFEST_URL"

  log "waiting for MetalLB namespace and CRDs"
  for i in $(seq 1 60); do
    if k3s kubectl get namespace metallb-system >/dev/null 2>&1 \
      && k3s kubectl get crd ipaddresspools.metallb.io >/dev/null 2>&1 \
      && k3s kubectl get crd l2advertisements.metallb.io >/dev/null 2>&1; then
      break
    fi
    sleep 2
    [ "$i" -lt 60 ] || fatal "MetalLB CRDs were not ready after install"
  done

  k3s kubectl wait --for=condition=Established crd/ipaddresspools.metallb.io --timeout=120s
  k3s kubectl wait --for=condition=Established crd/l2advertisements.metallb.io --timeout=120s

  log "waiting for MetalLB controller and speaker"
  k3s kubectl rollout status deployment/controller -n metallb-system --timeout=180s
  k3s kubectl rollout status daemonset/speaker -n metallb-system --timeout=180s

  log "configuring MetalLB L2 address pool $METALLB_POOL_NAME=$METALLB_IP_RANGE"
  cat <<EOF_METALLB | k3s kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: $METALLB_POOL_NAME
  namespace: metallb-system
spec:
  addresses:
    - $METALLB_IP_RANGE
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: ${METALLB_POOL_NAME}-l2
  namespace: metallb-system
spec:
  ipAddressPools:
    - $METALLB_POOL_NAME
EOF_METALLB
}

check_loadbalancer_prereqs() {
  [ "$SERVICE_TYPE" = "LoadBalancer" ] || return 0

  log "SERVICE_TYPE=LoadBalancer selected"
  if [ -n "$LOADBALANCER_IP" ]; then
    log "requested LoadBalancer IP: $LOADBALANCER_IP"
  else
    warn "LOADBALANCER_IP is not set. The cluster load balancer must allocate an address automatically."
  fi

  if k3s kubectl get namespace metallb-system >/dev/null 2>&1; then
    log "MetalLB namespace found"
    k3s kubectl get pods -n metallb-system --no-headers 2>/dev/null || true
  elif [ "$REQUIRE_METALLB" = "1" ]; then
    fatal "SERVICE_TYPE=LoadBalancer requires MetalLB, but namespace metallb-system was not found"
  else
    warn "MetalLB namespace was not found. LoadBalancer service may stay pending unless another load balancer is installed."
  fi
}

apply_runtime_configmap() {
  if [ -n "${MANIFEST_DIR:-}" ] && [ -f "$MANIFEST_DIR/configmap.yaml" ]; then
    MANIFEST_DIR="$MANIFEST_DIR" \
    NAMESPACE="$NAMESPACE" \
    PHONE_IP="$PHONE_IP" \
    PHONE_INTERFACE="$PHONE_INTERFACE" \
    PHONE_PING_INTERVAL="$PHONE_PING_INTERVAL" \
    PHONE_OFFLINE_THRESHOLD="$PHONE_OFFLINE_THRESHOLD" \
    BATCH_WINDOW_SEC="$BATCH_WINDOW_SEC" \
    ALERT_LEVEL="$ALERT_LEVEL" \
    SERVER_HOSTNAME="$SERVER_HOSTNAME" \
    SERVER_IP="$SERVER_IP" \
    PORTAL_URL="$PORTAL_URL" \
    python3 - <<'PY_RUNTIME_CONFIGMAP'
import os
import re
from pathlib import Path

path = Path(os.environ["MANIFEST_DIR"]) / "configmap.yaml"
text = path.read_text(encoding="utf-8")
text = re.sub(r"(\n  namespace: )otp-relay(\n)", rf"\g<1>{os.environ['NAMESPACE']}\2", text)

def set_data_value(payload: str, key: str, value: str) -> str:
    escaped = value.replace('"', '\\"')
    line = f'  {key}: "{escaped}"'
    pattern = rf"^  {re.escape(key)}: .*?$"
    if re.search(pattern, payload, flags=re.MULTILINE):
        return re.sub(pattern, line, payload, flags=re.MULTILINE)
    if not payload.endswith("\n"):
        payload += "\n"
    return payload + line + "\n"

for key, value in {
    "CLAIM_EXPIRY_SEC": "90",
    "OTP_DISPLAY_SEC": "285",
    "CONCURRENT_RISK_SEC": "30",
    "OTP_RELAY_DATA_DIR": "/app/data",
    "USERS_EXCEL_PATH": "/app/data/users.xlsx",
    "AUDIT_LOG_PATH": "/app/data/audit.log",
    "PHONE_IP": os.environ["PHONE_IP"],
    "PHONE_INTERFACE": os.environ["PHONE_INTERFACE"],
    "PHONE_PING_INTERVAL": os.environ["PHONE_PING_INTERVAL"],
    "PHONE_OFFLINE_THRESHOLD": os.environ["PHONE_OFFLINE_THRESHOLD"],
    "BATCH_WINDOW_SEC": os.environ["BATCH_WINDOW_SEC"],
    "ALERT_LEVEL": os.environ["ALERT_LEVEL"],
    "SERVER_HOSTNAME": os.environ["SERVER_HOSTNAME"],
    "SERVER_IP": os.environ["SERVER_IP"],
    "PORTAL_URL": os.environ["PORTAL_URL"],
}.items():
    text = set_data_value(text, key, value)

path.write_text(text if text.endswith("\n") else text + "\n", encoding="utf-8")
PY_RUNTIME_CONFIGMAP
    k3s kubectl apply -f "$MANIFEST_DIR/configmap.yaml"
    return 0
  fi

  k3s kubectl create configmap otp-relay-config \
    --namespace "$NAMESPACE" \
    --from-literal=CLAIM_EXPIRY_SEC="90" \
    --from-literal=OTP_DISPLAY_SEC="285" \
    --from-literal=CONCURRENT_RISK_SEC="30" \
    --from-literal=OTP_RELAY_DATA_DIR="/app/data" \
    --from-literal=USERS_EXCEL_PATH="/app/data/users.xlsx" \
    --from-literal=AUDIT_LOG_PATH="/app/data/audit.log" \
    --from-literal=PHONE_IP="$PHONE_IP" \
    --from-literal=PHONE_INTERFACE="$PHONE_INTERFACE" \
    --from-literal=PHONE_PING_INTERVAL="$PHONE_PING_INTERVAL" \
    --from-literal=PHONE_OFFLINE_THRESHOLD="$PHONE_OFFLINE_THRESHOLD" \
    --from-literal=BATCH_WINDOW_SEC="$BATCH_WINDOW_SEC" \
    --from-literal=ALERT_LEVEL="$ALERT_LEVEL" \
    --from-literal=SERVER_HOSTNAME="$SERVER_HOSTNAME" \
    --from-literal=SERVER_IP="$SERVER_IP" \
    --from-literal=PORTAL_URL="$PORTAL_URL" \
    --dry-run=client -o yaml | k3s kubectl apply -f -
}
mark_deployment_restart_required() {
  deployment_name="$1"
  case "$deployment_name" in
    otp-relay) RESTART_APP_REQUIRED=1 ;;
    otp-monitor) RESTART_MONITOR_REQUIRED=1 ;;
    *) fatal "unknown deployment restart request: $deployment_name" ;;
  esac
}

rollout_restart_deployment_if_exists() {
  deployment_name="$1"

  if ! k3s kubectl get deployment "$deployment_name" -n "$NAMESPACE" >/dev/null 2>&1; then
    warn "deployment/$deployment_name does not exist yet; skipping rollout restart"
    return 0
  fi

  for attempt in 1 2 3; do
    if k3s kubectl rollout restart "deployment/$deployment_name" -n "$NAMESPACE"; then
      return 0
    fi

    if [ "$attempt" -lt 3 ]; then
      warn "rollout restart for deployment/$deployment_name was rejected or raced; retrying"
      sleep 2
    fi
  done

  fatal "failed to trigger rollout restart for deployment/$deployment_name"
}

perform_pending_rollout_restarts() {
  if [ "$RESTART_APP_REQUIRED" = "1" ]; then
    log "restarting app deployment"
    rollout_restart_deployment_if_exists otp-relay
    log "waiting for app rollout"
    k3s kubectl rollout status deployment/otp-relay -n "$NAMESPACE" --timeout=180s
    RESTART_APP_REQUIRED=0
  fi

  if [ "$RESTART_MONITOR_REQUIRED" = "1" ]; then
    log "restarting monitor deployment"
    rollout_restart_deployment_if_exists otp-monitor
    log "waiting for monitor rollout"
    k3s kubectl rollout status deployment/otp-monitor -n "$NAMESPACE" --timeout=180s
    RESTART_MONITOR_REQUIRED=0
  fi
}

resolve_portal_url_from_service() {
  PORTAL_URL_CONFIG_REFRESHED=0

  [ "$SERVICE_TYPE" = "LoadBalancer" ] || return 0

  if [ "$PORTAL_URL_EXPLICIT" = "1" ]; then
    log "PORTAL_URL was explicitly provided; leaving it as $PORTAL_URL"
    return 0
  fi

  if [ -n "$LOADBALANCER_IP" ]; then
    ASSIGNED_LOADBALANCER_ADDRESS="$LOADBALANCER_IP"
    PORTAL_URL="http://$LOADBALANCER_IP"
    SERVER_IP="$LOADBALANCER_IP"
    log "using requested LoadBalancer IP for PORTAL_URL: $PORTAL_URL"
    apply_runtime_configmap
    PORTAL_URL_CONFIG_REFRESHED=1
    return 0
  fi

  log "waiting for LoadBalancer address assignment for service otp-relay"
  for i in $(seq 1 60); do
    assigned_address="$({
      k3s kubectl get svc otp-relay \
        -n "$NAMESPACE" \
        -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true
    })"
    assigned_address="$(printf '%s' "$assigned_address" | xargs)"

    if [ -z "$assigned_address" ]; then
      assigned_address="$({
        k3s kubectl get svc otp-relay \
          -n "$NAMESPACE" \
          -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true
      })"
      assigned_address="$(printf '%s' "$assigned_address" | xargs)"
    fi

    if [ -n "$assigned_address" ]; then
      ASSIGNED_LOADBALANCER_ADDRESS="$assigned_address"
      PORTAL_URL="http://$assigned_address"
      SERVER_IP="$assigned_address"
      log "using assigned LoadBalancer address for PORTAL_URL: $PORTAL_URL"
      apply_runtime_configmap
      PORTAL_URL_CONFIG_REFRESHED=1
      return 0
    fi

    sleep 2
  done

  warn "LoadBalancer address was not assigned within timeout; keeping PORTAL_URL=$PORTAL_URL"
}

if [ -z "$INSTALL_GITHUB_RUNNER" ]; then
  if prompt_yes_no "Install a GitHub Actions self-hosted runner for CI/CD deployments from GitHub? [y/N]" "N"; then
    INSTALL_GITHUB_RUNNER=1
  else
    INSTALL_GITHUB_RUNNER=0
  fi
fi

log "detected OS/arch: $OS_NAME / $ARCH_RAW"
[ "$IS_RPI" = "1" ] && log "detected Raspberry Pi hardware"
is_debian_family || fatal "this installer currently supports Debian-family systems only"

log "running non-invasive preflight checks"
if ! ss -lnt 2>/dev/null | grep -qE '(^|[[:space:]]|:)22[[:space:]]'; then
  warn "SSH does not appear to be listening on TCP/22. I will not change SSH, but confirm console access before continuing."
fi
if grep -qi '[[:space:]]cifs[[:space:]]' /etc/fstab 2>/dev/null; then
  warn "CIFS entries detected in /etc/fstab. This installer will not mount, unmount, or edit them."
fi
if mount | grep -qi ' type cifs '; then
  warn "An active CIFS mount is present. It will be left untouched."
fi
if systemctl is-active --quiet docker 2>/dev/null; then
  log "Docker is already running; installer will not restart it"
fi
if systemctl is-active --quiet k3s 2>/dev/null; then
  log "K3s is already running; installer will not restart it"
fi

mkdir -p /var/backups/otp-relay-k8s
ip route > /var/backups/otp-relay-k8s/ip-route.before 2>/dev/null || true
ip addr > /var/backups/otp-relay-k8s/ip-addr.before 2>/dev/null || true
iptables-save > /var/backups/otp-relay-k8s/iptables.before 2>/dev/null || true
nft list ruleset > /var/backups/otp-relay-k8s/nft.before 2>/dev/null || true

if [ "$IS_RPI" = "1" ]; then
  if ! grep -qw cgroup_memory /proc/cmdline 2>/dev/null || ! grep -qw cgroup_enable=memory /proc/cmdline 2>/dev/null; then
    warn "Raspberry Pi memory cgroup flags are not active. K3s may fail without them."
    warn "This installer will not edit boot files automatically. Add cgroup_memory=1 cgroup_enable=memory and reboot if K3s fails."
  fi
fi

log "installing base OS packages required for repository sync and optional runner setup with apt-get"
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl git tar gzip sudo python3

install_github_runner

if [ "$RUNNER_ONLY" = "1" ]; then
  log "RUNNER_ONLY=1 set; GitHub runner setup complete. Skipping Docker, K3s, image build, and deployment."
  exit 0
fi

case "$DEPLOY_MODE" in
  full|app|monitor|manifests|none) ;;
  *) fatal "unsupported DEPLOY_MODE=$DEPLOY_MODE. Use full, app, monitor, manifests, or none." ;;
esac
log "deployment mode: $DEPLOY_MODE"
validate_k8s_topology_settings

if [ "$DEPLOY_MODE" = "none" ]; then
  log "DEPLOY_MODE=none; no deployment changes required. Exiting before Docker/K3s work."
  exit 0
fi

log "installing Kubernetes/deployment OS packages with apt-get"
apt-get install -y --no-install-recommends \
  iproute2 iptables nftables python3-venv jq nodejs npm

if requires_docker; then
  ensure_docker
else
  log "DEPLOY_MODE=$DEPLOY_MODE does not require Docker image build; skipping Docker check/install"
fi

if ! cmd_exists k3s; then
  log "installing K3s server. This installs Kubernetes networking, but does not stop unrelated services."
  curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='server --write-kubeconfig-mode 644' sh -
else
  log "K3s already installed; no reinstall performed"
fi

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
log "waiting for Kubernetes node readiness"
for i in $(seq 1 60); do
  if k3s kubectl get nodes >/dev/null 2>&1 && k3s kubectl wait --for=condition=Ready node --all --timeout=10s >/dev/null 2>&1; then
    break
  fi
  sleep 2
  [ "$i" -lt 60 ] || fatal "K3s node did not become Ready"
done

log "cluster nodes"
k3s kubectl get nodes -o wide
log "cluster storage classes"
k3s kubectl get storageclass 2>/dev/null || true
validate_selected_node "$APP_NODE_SELECTOR_KEY" "$APP_NODE_SELECTOR_VALUE" "app"
validate_selected_node "$MONITOR_NODE_SELECTOR_KEY" "$MONITOR_NODE_SELECTOR_VALUE" "monitor"
validate_selected_node "$REDIS_NODE_SELECTOR_KEY" "$REDIS_NODE_SELECTOR_VALUE" "redis"
install_metallb_if_requested
check_loadbalancer_prereqs

log "syncing repository into $INSTALL_DIR"
if [ -d "$INSTALL_DIR/.git" ]; then
  git -C "$INSTALL_DIR" remote set-url origin "$REPO_URL" || true
  git -C "$INSTALL_DIR" fetch --prune origin "$REPO_REF"
  git -C "$INSTALL_DIR" reset --hard "origin/$REPO_REF"
  if [ "$GIT_CLEAN" = "1" ]; then
    log "cleaning untracked files in repo working tree, preserving common local data/secret files"
    git -C "$INSTALL_DIR" clean -ffd \
      -e data/ \
      -e .env \
      -e k8s/manifests/secret.env \
      -e '*.log'
  fi
elif [ -e "$INSTALL_DIR" ]; then
  fatal "$INSTALL_DIR exists but is not a git repo. Move it away or set INSTALL_DIR to another path."
else
  git clone --branch "$REPO_REF" "$REPO_URL" "$INSTALL_DIR"
fi
cd "$INSTALL_DIR"
log "repo synced to $(git rev-parse --short HEAD): $(git log -1 --pretty=%s)"

log "checking required source files"
[ -f main.py ] || fatal "main.py is missing in repo root"
[ -f monitor.py ] || fatal "monitor.py is required and missing in repo root"
[ -f requirements.txt ] || fatal "requirements.txt is missing in repo root"
[ -d frontend ] || fatal "frontend/ directory is missing"
[ -f frontend/index.html ] || fatal "frontend/index.html is missing"
[ -f frontend/app.jsx ] || fatal "frontend/app.jsx source is missing"
[ -f frontend/style.css ] || fatal "frontend/style.css is missing"
[ -f k8s/Dockerfile ] || fatal "k8s/Dockerfile is missing"
[ -f k8s/Dockerfile.monitor ] || fatal "k8s/Dockerfile.monitor is missing"
[ -d k8s/manifests ] || fatal "k8s/manifests directory is missing"
for required_manifest in namespace.yaml pvc.yaml deployment.yaml service.yaml deployment-monitor.yaml; do
  [ -f "k8s/manifests/$required_manifest" ] || fatal "k8s/manifests/$required_manifest is missing"
done
if [ "$REDIS_ENABLED" = "1" ]; then
  for required_manifest in redis-service.yaml redis-statefulset.yaml redis-pdb.yaml; do
    [ -f "k8s/manifests/$required_manifest" ] || fatal "k8s/manifests/$required_manifest is missing"
  done
fi
[ -f scripts/build_help_docs.py ] || fatal "required help-doc builder is missing: scripts/build_help_docs.py"
[ -d docs/help ] || fatal "required help-doc input directory is missing: docs/help"

if [ -z "$PHONE_IP" ]; then
  fatal "PHONE_IP is required because monitor.py is a core component"
fi
if [ -z "$WHATSAPP_API_KEY" ] || [ -z "$WHATSAPP_RECIPIENT" ]; then
  warn "WhatsApp alert credentials are not set. monitor.py will still run, but WhatsApp alerts will be skipped."
fi

if requires_app_image; then
  log "preparing installer Python environment for app validation/help docs"
  python3 -m venv .installer-venv
  .installer-venv/bin/python -m pip install --upgrade pip setuptools wheel
  .installer-venv/bin/python -m pip install -r requirements.txt

  if [ "$SKIP_HELP_DOCS_BUILD" = "1" ]; then
    log "skipping help docs build because SKIP_HELP_DOCS_BUILD=1"
  else
    log "building help docs with scripts/build_help_docs.py"
    .installer-venv/bin/python scripts/build_help_docs.py
  fi

  [ -f package.json ] || fatal "package.json is missing in repo root"
  [ -f package-lock.json ] || fatal "package-lock.json is missing in repo root"

  log "installing frontend build dependencies from committed package-lock.json"
  npm ci

  log "building production frontend bundle frontend/app.js"
  npm run build:frontend
  [ -f frontend/app.js ] || fatal "frontend/app.js was not produced by npm run build:frontend"
else
  log "DEPLOY_MODE=$DEPLOY_MODE does not require app help-doc build; skipping installer venv"
fi

log "staging repository Dockerfiles and Kubernetes manifests for deployment"
GENERATED_DIR="$(mktemp -d /tmp/otp-relay-k8s.XXXXXX)"
SOURCE_MANIFEST_DIR="k8s/manifests"
MANIFEST_DIR="$GENERATED_DIR/manifests"
APP_DOCKERFILE="k8s/Dockerfile"
MONITOR_DOCKERFILE="k8s/Dockerfile.monitor"

cleanup_generated_assets() {
  rm -rf "$GENERATED_DIR"
}
trap cleanup_generated_assets EXIT

mkdir -p "$MANIFEST_DIR"
cp "$SOURCE_MANIFEST_DIR"/*.yaml "$MANIFEST_DIR"/
rm -f "$MANIFEST_DIR/secret-example.env"

existing_pvc_storage_class="$(
  k3s kubectl get pvc otp-relay-data \
    -n "$NAMESPACE" \
    -o jsonpath='{.spec.storageClassName}' 2>/dev/null || true
)"
existing_pvc_storage_class="$(printf '%s' "$existing_pvc_storage_class" | xargs)"

if [ -n "$existing_pvc_storage_class" ] && [ -z "$PVC_STORAGE_CLASS" ]; then
  warn "PVC otp-relay-data already exists with storageClassName=$existing_pvc_storage_class; preserving it"
  PVC_STORAGE_CLASS="$existing_pvc_storage_class"
fi

if [ -n "$existing_pvc_storage_class" ] \
  && [ -n "$PVC_STORAGE_CLASS" ] \
  && [ "$PVC_STORAGE_CLASS" != "$existing_pvc_storage_class" ]; then
  fatal "PVC otp-relay-data already exists with storageClassName=$existing_pvc_storage_class; refusing to change immutable storageClassName to $PVC_STORAGE_CLASS"
fi

log "rendering runtime values into staged repository manifests"
MANIFEST_DIR="$MANIFEST_DIR" \
NAMESPACE="$NAMESPACE" \
APP_IMAGE="$APP_IMAGE" \
MONITOR_IMAGE="$MONITOR_IMAGE" \
SERVICE_TYPE="$SERVICE_TYPE" \
SERVICE_NODE_PORT="$SERVICE_NODE_PORT" \
LOADBALANCER_IP="$LOADBALANCER_IP" \
PVC_STORAGE_CLASS="$PVC_STORAGE_CLASS" \
PVC_SIZE="$PVC_SIZE" \
REPLICA_COUNT="$REPLICA_COUNT" \
APP_NODE_SELECTOR_KEY="$APP_NODE_SELECTOR_KEY" \
APP_NODE_SELECTOR_VALUE="$APP_NODE_SELECTOR_VALUE" \
MONITOR_NODE_SELECTOR_KEY="$MONITOR_NODE_SELECTOR_KEY" \
MONITOR_NODE_SELECTOR_VALUE="$MONITOR_NODE_SELECTOR_VALUE" \
REDIS_NODE_SELECTOR_KEY="$REDIS_NODE_SELECTOR_KEY" \
REDIS_NODE_SELECTOR_VALUE="$REDIS_NODE_SELECTOR_VALUE" \
PHONE_IP="$PHONE_IP" \
PHONE_INTERFACE="$PHONE_INTERFACE" \
PHONE_PING_INTERVAL="$PHONE_PING_INTERVAL" \
PHONE_OFFLINE_THRESHOLD="$PHONE_OFFLINE_THRESHOLD" \
BATCH_WINDOW_SEC="$BATCH_WINDOW_SEC" \
ALERT_LEVEL="$ALERT_LEVEL" \
SERVER_HOSTNAME="$SERVER_HOSTNAME" \
SERVER_IP="$SERVER_IP" \
PORTAL_URL="$PORTAL_URL" \
REDIS_ENABLED="$REDIS_ENABLED" \
REDIS_URL="$REDIS_URL" \
REDIS_REQUIRED="$REDIS_REQUIRED" \
REDIS_STORAGE_CLASS="$REDIS_STORAGE_CLASS" \
REDIS_SIZE="$REDIS_SIZE" \
python3 - <<'PY_RENDER_MANIFESTS'
import os
import re
from pathlib import Path

manifest_dir = Path(os.environ["MANIFEST_DIR"])
namespace = os.environ["NAMESPACE"]


def read(name: str) -> str:
    return (manifest_dir / name).read_text(encoding="utf-8")


def write(name: str, text: str) -> None:
    (manifest_dir / name).write_text(text if text.endswith("\n") else text + "\n", encoding="utf-8")


def replace_namespace(text: str) -> str:
    text = re.sub(r"(\n  namespace: )otp-relay(\n)", rf"\g<1>{namespace}\2", text)
    return text


def set_data_value(text: str, key: str, value: str) -> str:
    escaped = value.replace('"', '\\"')
    line = f'  {key}: "{escaped}"'
    pattern = rf"^  {re.escape(key)}: .*?$"
    if re.search(pattern, text, flags=re.MULTILINE):
        return re.sub(pattern, line, text, flags=re.MULTILINE)
    if not text.endswith("\n"):
        text += "\n"
    return text + line + "\n"


def set_replicas(text: str) -> str:
    return re.sub(r"^  replicas: .*$", f"  replicas: {os.environ['REPLICA_COUNT']}", text, flags=re.MULTILINE)


def set_recreate_strategy(text: str) -> str:
    return re.sub(r"  strategy:\n(?:    .*\n)+?  template:", "  strategy:\n    type: Recreate\n  template:", text)


def set_first_image(text: str, image: str) -> str:
    return re.sub(r"(\n\s*image: ).*", rf"\g<1>{image}", text, count=1)


def remove_nodesel(text: str) -> str:
    return re.sub(r"\n      nodeSelector:\n(?:        .+\n)+", "\n", text)


def add_nodesel(text: str, key: str, value: str) -> str:
    text = remove_nodesel(text)
    if not key:
        return text
    block = f"      nodeSelector:\n        {key}: \"{value}\"\n"
    return text.replace("    spec:\n", "    spec:\n" + block, 1)

# Namespace
if (manifest_dir / "namespace.yaml").exists():
    write("namespace.yaml", f"apiVersion: v1\nkind: Namespace\nmetadata:\n  name: {namespace}\n")

# ConfigMap remains a repo manifest, rendered here for dry-run/reference. Live ConfigMap is applied by apply_runtime_configmap.
if (manifest_dir / "configmap.yaml").exists():
    text = replace_namespace(read("configmap.yaml"))
    for key in [
        "CLAIM_EXPIRY_SEC", "OTP_DISPLAY_SEC", "CONCURRENT_RISK_SEC",
        "OTP_RELAY_DATA_DIR", "USERS_EXCEL_PATH", "AUDIT_LOG_PATH",
        "PHONE_IP", "PHONE_INTERFACE", "PHONE_PING_INTERVAL", "PHONE_OFFLINE_THRESHOLD",
        "BATCH_WINDOW_SEC", "ALERT_LEVEL", "SERVER_HOSTNAME", "SERVER_IP", "PORTAL_URL",
    ]:
        defaults = {
            "CLAIM_EXPIRY_SEC": "90",
            "OTP_DISPLAY_SEC": "285",
            "CONCURRENT_RISK_SEC": "30",
            "OTP_RELAY_DATA_DIR": "/app/data",
            "USERS_EXCEL_PATH": "/app/data/users.xlsx",
            "AUDIT_LOG_PATH": "/app/data/audit.log",
        }
        text = set_data_value(text, key, os.environ.get(key, defaults.get(key, "")))
    write("configmap.yaml", text)

# PVC
if (manifest_dir / "pvc.yaml").exists():
    text = replace_namespace(read("pvc.yaml"))
    text = re.sub(r"\n  storageClassName: .*", "", text)
    storage_class = os.environ.get("PVC_STORAGE_CLASS", "")
    if storage_class:
        text = text.replace("  accessModes:\n", f"  storageClassName: {storage_class}\n  accessModes:\n", 1)
    text = re.sub(r"(\n      storage: ).*", rf"\g<1>{os.environ['PVC_SIZE']}", text)
    write("pvc.yaml", text)

# App deployment
if (manifest_dir / "deployment.yaml").exists():
    text = replace_namespace(read("deployment.yaml"))
    text = set_replicas(text)
    text = set_recreate_strategy(text)
    text = set_first_image(text, os.environ["APP_IMAGE"])
    text = add_nodesel(text, os.environ.get("APP_NODE_SELECTOR_KEY", ""), os.environ.get("APP_NODE_SELECTOR_VALUE", ""))

    # Redis is the Phase 2 shared-state service for OTP queue, pending OTPs,
    # admin sessions, and admin login-attempt tracking.
    text = re.sub(
        r"\n            - name: REDIS_URL\n              value: .*",
        "",
        text,
    )
    text = re.sub(
        r"\n            - name: REDIS_REQUIRED\n              value: .*",
        "",
        text,
    )
    if os.environ.get("REDIS_ENABLED") == "1":
        redis_env = (
            f"            - name: REDIS_URL\n"
            f"              value: {os.environ['REDIS_URL']}\n"
            f"            - name: REDIS_REQUIRED\n"
            f"              value: \"{os.environ['REDIS_REQUIRED']}\"\n"
        )
        text = text.replace(
            "            - name: SMS_SECRET_TOKEN\n",
            redis_env + "            - name: SMS_SECRET_TOKEN\n",
            1,
        )

    write("deployment.yaml", text)

# Monitor deployment
if (manifest_dir / "deployment-monitor.yaml").exists():
    text = replace_namespace(read("deployment-monitor.yaml"))
    text = set_replicas(text)
    text = set_recreate_strategy(text)
    text = set_first_image(text, os.environ["MONITOR_IMAGE"])
    text = add_nodesel(text, os.environ.get("MONITOR_NODE_SELECTOR_KEY", ""), os.environ.get("MONITOR_NODE_SELECTOR_VALUE", ""))
    write("deployment-monitor.yaml", text)

# Service
if (manifest_dir / "service.yaml").exists():
    text = replace_namespace(read("service.yaml"))
    text = re.sub(r"^  type: .*$", f"  type: {os.environ['SERVICE_TYPE']}", text, flags=re.MULTILINE)
    text = re.sub(r"\n  loadBalancerIP: .*", "", text)
    text = re.sub(r"\n      nodePort: .*", "", text)
    if os.environ["SERVICE_TYPE"] == "LoadBalancer" and os.environ.get("LOADBALANCER_IP"):
        text = text.replace(f"  type: {os.environ['SERVICE_TYPE']}\n", f"  type: {os.environ['SERVICE_TYPE']}\n  loadBalancerIP: {os.environ['LOADBALANCER_IP']}\n", 1)
    if os.environ["SERVICE_TYPE"] == "NodePort":
        text = text.replace("      targetPort: 8000\n", f"      targetPort: 8000\n      nodePort: {os.environ['SERVICE_NODE_PORT']}\n", 1)
    write("service.yaml", text)

# Redis manifests
for name in ["redis-service.yaml", "redis-statefulset.yaml", "redis-pdb.yaml"]:
    path = manifest_dir / name
    if path.exists():
        text = replace_namespace(read(name))
        if name == "redis-statefulset.yaml":
            text = add_nodesel(text, os.environ.get("REDIS_NODE_SELECTOR_KEY", ""), os.environ.get("REDIS_NODE_SELECTOR_VALUE", ""))
            text = re.sub(r"\n        storageClassName: .*", "", text)
            redis_storage_class = os.environ.get("REDIS_STORAGE_CLASS", "")
            if redis_storage_class:
                text = text.replace(
                    "        accessModes:\n",
                    f"        storageClassName: {redis_storage_class}\n        accessModes:\n",
                    1,
                )
            text = re.sub(r"(\n            storage: ).*", rf"\g<1>{os.environ['REDIS_SIZE']}", text)
        write(name, text)

# Ingress
if (manifest_dir / "ingress.yaml").exists():
    text = replace_namespace(read("ingress.yaml"))
    write("ingress.yaml", text)
PY_RENDER_MANIFESTS

log "validating Python syntax and Kubernetes manifests"
if requires_app_image; then
  python3 -m py_compile main.py
fi
if requires_monitor_image; then
  python3 -m py_compile monitor.py
fi
k3s kubectl apply --dry-run=client -f "$MANIFEST_DIR/namespace.yaml" >/dev/null
k3s kubectl apply -f "$MANIFEST_DIR/namespace.yaml"
k3s kubectl apply --dry-run=client \
  -f "$MANIFEST_DIR/configmap.yaml" \
  -f "$MANIFEST_DIR/pvc.yaml" \
  -f "$MANIFEST_DIR/deployment.yaml" \
  -f "$MANIFEST_DIR/service.yaml" \
  -f "$MANIFEST_DIR/deployment-monitor.yaml" >/dev/null
if [ "$INGRESS_ENABLED" = "1" ] && [ -f "$MANIFEST_DIR/ingress.yaml" ]; then
  k3s kubectl apply --dry-run=client -f "$MANIFEST_DIR/ingress.yaml" >/dev/null
fi
if [ "$REDIS_ENABLED" = "1" ]; then
  k3s kubectl apply --dry-run=client \
    -f "$MANIFEST_DIR/redis-service.yaml" \
    -f "$MANIFEST_DIR/redis-statefulset.yaml" \
    -f "$MANIFEST_DIR/redis-pdb.yaml" >/dev/null
fi

if requires_manifests_apply; then
  log "creating/updating Kubernetes secret"
  k3s kubectl create secret generic otp-relay-secrets \
    --namespace "$NAMESPACE" \
    --from-literal=SMS_SECRET_TOKEN="$SMS_SECRET_TOKEN" \
    --from-literal=WHATSAPP_API_KEY="$WHATSAPP_API_KEY" \
    --from-literal=WHATSAPP_RECIPIENT="$WHATSAPP_RECIPIENT" \
    --dry-run=client -o yaml | k3s kubectl apply -f -
fi

if requires_app_image; then
  log "building app image with Docker"
  "$DOCKER_BIN" build -t "$APP_IMAGE" -f "$APP_DOCKERFILE" .
  log "importing app image into K3s containerd"
  tmp_app_tar="$(mktemp --suffix=.tar)"
  "$DOCKER_BIN" save "$APP_IMAGE" -o "$tmp_app_tar"
  k3s ctr images import "$tmp_app_tar"
  rm -f "$tmp_app_tar"
else
  log "DEPLOY_MODE=$DEPLOY_MODE skips app image build/import"
fi

if requires_monitor_image; then
  log "building required monitor image with Docker"
  "$DOCKER_BIN" build -t "$MONITOR_IMAGE" -f "$MONITOR_DOCKERFILE" .
  log "importing required monitor image into K3s containerd"
  tmp_monitor_tar="$(mktemp --suffix=.tar)"
  "$DOCKER_BIN" save "$MONITOR_IMAGE" -o "$tmp_monitor_tar"
  k3s ctr images import "$tmp_monitor_tar"
  rm -f "$tmp_monitor_tar"
else
  log "DEPLOY_MODE=$DEPLOY_MODE skips monitor image build/import"
fi

if requires_manifests_apply; then
  log "applying Kubernetes resources"
  apply_runtime_configmap
  k3s kubectl apply -f "$MANIFEST_DIR/pvc.yaml"

  if [ "$REDIS_ENABLED" = "1" ]; then
    log "applying Redis shared-state resources"
    k3s kubectl apply -f "$MANIFEST_DIR/redis-service.yaml"
    k3s kubectl apply -f "$MANIFEST_DIR/redis-statefulset.yaml"
    k3s kubectl apply -f "$MANIFEST_DIR/redis-pdb.yaml"
    k3s kubectl rollout status statefulset/otp-redis -n "$NAMESPACE" --timeout=180s
  fi

  if [ "$DEPLOY_MODE" = "full" ] || [ "$DEPLOY_MODE" = "app" ] || [ "$DEPLOY_MODE" = "manifests" ]; then
    k3s kubectl apply -f "$MANIFEST_DIR/deployment.yaml"
    k3s kubectl apply -f "$MANIFEST_DIR/service.yaml"
    resolve_portal_url_from_service
    if [ "$INGRESS_ENABLED" = "1" ] && [ -f "$MANIFEST_DIR/ingress.yaml" ]; then
      k3s kubectl apply -f "$MANIFEST_DIR/ingress.yaml"
    else
      k3s kubectl delete ingress otp-relay -n "$NAMESPACE" --ignore-not-found=true
    fi
  fi

  if [ "$DEPLOY_MODE" = "full" ] || [ "$DEPLOY_MODE" = "monitor" ] || [ "$DEPLOY_MODE" = "manifests" ]; then
    k3s kubectl apply -f "$MANIFEST_DIR/deployment-monitor.yaml"
  fi

  if [ "${PORTAL_URL_CONFIG_REFRESHED:-0}" = "1" ]; then
    log "marking deployments for restart to pick up refreshed PORTAL_URL ConfigMap"
    mark_deployment_restart_required otp-relay
    mark_deployment_restart_required otp-monitor
  fi
fi

if requires_app_image; then
  log "marking app deployment for restart to pick up freshly imported local app image"
  mark_deployment_restart_required otp-relay
fi

if requires_monitor_image; then
  log "marking monitor deployment for restart to pick up freshly imported local monitor image"
  mark_deployment_restart_required otp-monitor
fi

perform_pending_rollout_restarts

if [ "$DEPLOY_MODE" = "manifests" ]; then
  log "manifest-only apply complete; checking rollout status for existing deployments"
  k3s kubectl rollout status deployment/otp-relay -n "$NAMESPACE" --timeout=180s || true
  k3s kubectl rollout status deployment/otp-monitor -n "$NAMESPACE" --timeout=180s || true
fi

if [ -n "$RUNTIME_DATA_DIR" ] && { [ "$DEPLOY_MODE" = "full" ] || [ "$DEPLOY_MODE" = "app" ]; }; then
  [ -d "$RUNTIME_DATA_DIR" ] || fatal "RUNTIME_DATA_DIR does not exist: $RUNTIME_DATA_DIR"
  pod="$(k3s kubectl get pod -n "$NAMESPACE" -l app=otp-relay -o jsonpath='{.items[0].metadata.name}')"
  for f in users.xlsx admin_auth.json admin_config.json wizard_progress.json audit.log; do
    if [ -f "$RUNTIME_DATA_DIR/$f" ]; then
      log "copying $f into PVC"
      k3s kubectl cp "$RUNTIME_DATA_DIR/$f" "$NAMESPACE/$pod:/app/data/$f" -n "$NAMESPACE"
    fi
  done
  mark_deployment_restart_required otp-relay
  mark_deployment_restart_required otp-monitor
  perform_pending_rollout_restarts
fi


log "checking deployment working tree cleanliness"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  dirty_status="$(git status --porcelain)"
  if [ -n "$dirty_status" ]; then
    warn "deployment working tree has uncommitted/generated files:"
    printf '%s\n' "$dirty_status" >&2
    warn "tracked modifications should now be unexpected; generated frontend files should be covered by .gitignore"
  else
    log "deployment working tree is clean"
  fi
fi


cat <<EOF_DONE

OTP Relay Kubernetes deployment complete.

Portal URL:   $PORTAL_URL/
NodePort URL: http://$SERVER_IP:$SERVICE_NODE_PORT/
Service type: $SERVICE_TYPE
LoadBalancer: ${ASSIGNED_LOADBALANCER_ADDRESS:-${LOADBALANCER_IP:-auto/none}}
MetalLB:      install=$INSTALL_METALLB range=${METALLB_IP_RANGE:-none}
Namespace:    $NAMESPACE
Repo path:    $INSTALL_DIR
OS/arch:      $OS_NAME / $ARCH_RAW
Monitor:      installed as required component
Runner:       $INSTALL_GITHUB_RUNNER
Runner only:  $RUNNER_ONLY
Deploy mode:  $DEPLOY_MODE
App node selector:     ${APP_NODE_SELECTOR_KEY:-none}=${APP_NODE_SELECTOR_VALUE:-}
Monitor node selector: ${MONITOR_NODE_SELECTOR_KEY:-none}=${MONITOR_NODE_SELECTOR_VALUE:-}
Redis node selector:   ${REDIS_NODE_SELECTOR_KEY:-none}=${REDIS_NODE_SELECTOR_VALUE:-}
PVC storage:           ${PVC_STORAGE_CLASS:-default} / $PVC_SIZE
Redis:                enabled=$REDIS_ENABLED required=$REDIS_REQUIRED url=${REDIS_URL:-none} storage=${REDIS_STORAGE_CLASS:-default}/$REDIS_SIZE

Useful commands:
  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
  k3s kubectl get pods -n $NAMESPACE
  k3s kubectl logs -n $NAMESPACE deployment/otp-relay
  k3s kubectl logs -n $NAMESPACE deployment/otp-monitor
  k3s kubectl get svc,ingress -n $NAMESPACE
  curl -i http://127.0.0.1/
  curl -i http://127.0.0.1:$SERVICE_NODE_PORT/

Monitor config is in ConfigMap otp-relay-config:
  PHONE_IP=$PHONE_IP
  PHONE_INTERFACE=$PHONE_INTERFACE
  PHONE_PING_INTERVAL=$PHONE_PING_INTERVAL
  PHONE_OFFLINE_THRESHOLD=$PHONE_OFFLINE_THRESHOLD
  PORTAL_URL=$PORTAL_URL

SMS webhook secret token was generated/stored in Kubernetes secret otp-relay-secrets.
To print it on this server:
  k3s kubectl get secret otp-relay-secrets -n $NAMESPACE -o jsonpath='{.data.SMS_SECRET_TOKEN}' | base64 -d; echo
EOF_DONE
