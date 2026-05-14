# OTP Relay Kubernetes

Kubernetes/K3s deployment for the OTP Relay Portal.

This repository contains the FastAPI portal, required monitor service, React frontend source, help-documentation source, Kubernetes manifests, Dockerfiles, and installer used by GitHub Actions to deploy onto a K3s server or cluster.

## Current status

The repository is at a Phase 3 SCH-alignment validation baseline.

Validated foundations:

- 3-node K3s cluster baseline.
- MetalLB LoadBalancer exposure.
- Traefik HTTPS ingress.
- Redis-required runtime state.
- Redis Sentinel and HAProxy topology validated for Redis failover.
- NFS/RWX application storage validated for `/app/data`.
- Monitor pod isolated from Service/Ingress.

Current conservative live posture:

```text
REPLICA_COUNT=1
REDIS_REQUIRED=1
NFS_ENABLED=1
PVC_STORAGE_CLASS=otp-relay-nfs
strategy: Recreate
TLS self-signed is enabled until IT distributes/trusts the certificate by Group Policy
```

The app remains at one live replica until final manager OTP validation, pending-OTP restart validation, two-replica OTP flow validation, DNS/TLS client validation, and worker-drain validation are complete.

## Documentation

All active documentation is under `docs/`:

```text
docs/
├── README.md
├── architecture/
│   ├── current-architecture-and-sch-gap-analysis.md
│   └── diagrams/
├── deployment/
│   └── deployment-and-storage-guide.md
├── development/
│   └── build-and-development-guide.md
├── help/
└── operations/
    └── operations-and-validation-runbook.md
```

Start here:

- [Documentation index](docs/README.md)
- [Current architecture and SCH gap analysis](docs/architecture/current-architecture-and-sch-gap-analysis.md)
- [Deployment and storage guide](docs/deployment/deployment-and-storage-guide.md)
- [Operations and validation runbook](docs/operations/operations-and-validation-runbook.md)
- [Build and development guide](docs/development/build-and-development-guide.md)

## Repository layout

```text
.
├── .github/
│   └── workflows/
│       └── deploy-k3s.yml        # GitHub Actions deployment workflow
├── docs/                         # Active documentation and portal help source
│   ├── README.md                 # Documentation index
│   ├── architecture/             # Architecture and SCH gap analysis
│   ├── deployment/               # Deployment and storage guide
│   ├── development/              # Build and development guide
│   ├── help/                     # Portal help source markdown/assets
│   └── operations/               # Operations and validation runbook
├── frontend/                     # Portal frontend source/static files
├── k8s/                          # Dockerfiles and Kubernetes manifests only
│   ├── Dockerfile
│   ├── Dockerfile.monitor
│   └── manifests/
├── scripts/                      # Help-doc and sample-user utilities
├── .dockerignore                 # Docker build-context exclusions
├── .gitignore                    # Git ignore rules
├── LICENSE
├── install-otp-relay-k8s.sh      # Main K3s installer/deployer
├── main.py                       # FastAPI portal
├── monitor.py                    # Required monitor service
├── package.json                  # Frontend/build tooling package metadata
├── package-lock.json             # Locked frontend/build dependencies
├── requirements.txt              # Python runtime dependencies
└── README.md                     # Project overview
```

`k8s/` must remain deployment assets only. Do not put documentation under `k8s/docs/`.

## Important operational rules

- Do not disable Redis in the validated Phase 3 posture.
- Do not raise `REPLICA_COUNT` above `1` until the remaining OTP and worker-drain validations pass.
- Do not expose the monitor with a Service or Ingress.
- Keep `/app/data` on shared NFS/RWX storage after migration.
- Keep secrets out of Git.
- Treat GitHub Actions and `install-otp-relay-k8s.sh` as the normal deployment path.
