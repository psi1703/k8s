# Phase 3 Resilience Checkpoint

## Completed

- K3s ServiceLB/Klipper disabled.
- MetalLB is the active LoadBalancer implementation.
- OTP Relay service is exposed at `http://172.31.11.121/`.
- `/readyz` reports:
  - `status=ok`
  - `users_loaded=88`
  - `redis=ok`
  - `redis_required=true`
- `debian` is labeled:
  - `otp-relay/storage-node=true`
  - `otp-relay/monitor-node=true`
- `otp-relay` deployment is pinned to `otp-relay/storage-node=true`.
- `otp-redis` StatefulSet is pinned to `otp-relay/storage-node=true`.
- `otp-monitor` deployment is pinned to `otp-relay/monitor-node=true`.
- App pod restart test passed.
- Redis pod restart test passed.
- Monitor pod restart test passed.

## Storage note

Both persistent volumes use `local-path` storage and have node affinity to `debian`.

Do not move the app or Redis workloads to worker nodes unless storage is intentionally migrated to a shared or replicated storage backend.

## Current safe topology

- `debian`: control-plane, storage anchor, monitor node.
- Future worker nodes may be added, but storage-bound workloads should remain pinned until storage migration is planned.
