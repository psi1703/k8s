# OTP Relay Kubernetes Documentation

This directory is the single source for project documentation. Kubernetes manifests and Dockerfiles stay under `k8s/`; explanations, guides, runbooks, validation reports, and historical notes stay under `docs/`.

## Architecture

- [Kubernetes Architecture Plan](architecture/kubernetes-architecture-plan.md) - phased architecture and design direction for the OTP Relay Kubernetes deployment.
- [SCH Target Architecture Gap Analysis](architecture/sch-target-architecture-gap-analysis.md) - current validated implementation compared with the SCH production target.
- [Architecture Diagrams](architecture/diagrams/) - SVG diagrams used to explain the deployment phases and topology.

## Deployment

- [K3s Setup and Operations Guide](deployment/k3s-setup-and-operations-guide.md) - beginner-friendly setup and operating guide for the K3s deployment.
- [GitHub Actions Deployment Guide](deployment/github-actions-deployment-guide.md) - recommended deployment path using the self-hosted GitHub Actions runner.
- [NFS Shared Storage Migration Guide](deployment/nfs-shared-storage-migration-guide.md) - how to move app data from local-path storage to the NFS/RWX app storage path.
- [Manual Image Build and Deployment Fallback](deployment/manual-image-build-and-deployment-fallback.md) - manual build/deploy process retained as a fallback to GitHub Actions.

## Development

- [Docker Image Build Guide](development/docker-image-build-guide.md) - current app and monitor Docker image build model.
- [Dockerfile Design Background Notes](development/dockerfile-design-background-notes.md) - historical/background design notes for Dockerfile decisions.

## Operations

- [Phase 3 Resilience Validation Report](operations/phase-3-resilience-validation-report.md) - validated Phase 3 state, including NFS app storage and Redis HA/Sentinel/HAProxy checks.

## Validation

- [Phase 2 LoadBalancer and Redis Alignment Report](validation/phase-2-loadbalancer-and-redis-alignment-report.md) - historical Phase 2 and early Phase 3 validation notes.

## User Help Source

- [Help Documentation Source](help/) - markdown used by `scripts/build_help_docs.py` to generate the portal help pages under `frontend/help/`.
- [Help Asset Guide](help/assets/README.md) - explains how screenshots and images used by the help docs are stored.

## Archive

- [Historical Phase Notes](archive/historical-phase-notes/) - old planning notes kept for reference only. Do not use archived docs as the active deployment source of truth.
