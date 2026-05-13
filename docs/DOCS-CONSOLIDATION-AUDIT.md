# Documentation Consolidation Audit

## Result

The documentation tree has been consolidated under the root `docs/` directory.

`k8s/` now contains only Kubernetes runtime assets:

```text
k8s/
├── Dockerfile
├── Dockerfile.monitor
└── manifests/
```

## Verified documentation layout

```text
docs/
├── README.md
├── DOCS-CONSOLIDATION-AUDIT.md
├── architecture/
├── archive/
├── deployment/
├── development/
├── help/
├── operations/
└── validation/
```

## Corrections applied

- Moved old `docs/dev/` content into `docs/development/`.
- Removed duplicate old `docs/diagrams/` after confirming diagrams exist under `docs/architecture/diagrams/`.
- Removed duplicate old operation filenames after canonical deployment/operation files were present.
- Added the missing `docs/validation/phase-2-loadbalancer-and-redis-alignment-report.md` file.
- Moved old plan material into `docs/archive/historical-phase-notes/`.
- Updated current-state docs to reflect NFS/RWX app storage validation and Redis Sentinel/HAProxy validation.
- Updated stale wording that still described Redis as single-instance in active docs.
- Validated relative Markdown links in `.md` files.

## Active source-of-truth docs

- `docs/README.md`
- `docs/architecture/kubernetes-architecture-plan.md`
- `docs/architecture/sch-target-architecture-gap-analysis.md`
- `docs/deployment/k3s-setup-and-operations-guide.md`
- `docs/deployment/github-actions-deployment-guide.md`
- `docs/deployment/nfs-shared-storage-migration-guide.md`
- `docs/operations/phase-3-resilience-validation-report.md`
- `docs/validation/phase-2-loadbalancer-and-redis-alignment-report.md`

## Archived docs

The files under `docs/archive/historical-phase-notes/` are retained for reference only. They contain old assumptions and should not be used as deployment guidance.
