# OTP Relay Kubernetes Documentation

This directory is the single source for project documentation. Kubernetes manifests and Dockerfiles stay under `k8s/`; explanations, guides, runbooks, validation notes, and help source stay under `docs/`.

## Active documents

| Area | Document | Purpose |
|---|---|---|
| Architecture | [Current Architecture and SCH Gap Analysis](architecture/current-architecture-and-sch-gap-analysis.md) | Current validated topology, SCH target, current gaps, and safe design rules. |
| Deployment | [Deployment and Storage Guide](deployment/deployment-and-storage-guide.md) | GitHub Actions deployment path, storage settings, NFS/RWX migration, and manual fallback. |
| Operations | [Operations and Validation Runbook](operations/operations-and-validation-runbook.md) | Health checks, Redis/NFS/TLS/monitor validation, OTP checks, and useful commands. |
| Development | [Build and Development Guide](development/build-and-development-guide.md) | App/monitor image build model, frontend build model, help-doc build model, and local build commands. |
| User help | [Help Documentation Source](help/) | Markdown and screenshots used by `scripts/build_help_docs.py` to generate portal help pages. |

## Documentation rules

- Keep active docs compact and current.
- Avoid duplicate Phase 1/2/3 explanations across multiple files.
- Do not restore `docs/k8s-plan.md`, `docs/dev/`, `docs/diagrams/`, or `k8s/docs/`.
- Keep diagrams under `docs/architecture/diagrams/`.
- Keep portal user-help source under `docs/help/`.
- Do not use archived or old planning notes as deployment source of truth.
