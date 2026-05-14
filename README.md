# OTP Relay Kubernetes

Kubernetes/K3s deployment for the OTP Relay Portal.

This repository contains the FastAPI portal, required monitor service, React frontend source, help-documentation source, Kubernetes manifests, Dockerfiles, and installer used by GitHub Actions to deploy onto a K3s server or cluster.

## Current status

The repository is at a Phase 3 SCH-alignment validation baseline.

Validated foundations:

- 3-node K3s cluster baseline.
- Official HTTPS exposure through Traefik Ingress.
- Internal `otp-relay` app Service using `ClusterIP`.
- Redis-required runtime state.
- Redis Sentinel and HAProxy topology validated for Redis failover.
- NFS/RWX application storage validated for `/app/data`.
- Monitor pod isolated from Service/Ingress.

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
