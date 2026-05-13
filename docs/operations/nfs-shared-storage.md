# NFS shared storage for OTP Relay app data

This project now supports the SCH target storage direction by using a static NFS `PersistentVolume` for the OTP Relay app data PVC.

## Scope

NFS is used for the app runtime data mounted at `/app/data`:

- `users.xlsx`
- `admin_auth.json`
- `admin_config.json`
- `wizard_progress.json`
- `audit.log`

Redis remains on the current single-instance Redis PVC until the separate Redis HA/Sentinel/approved Redis design is implemented. Do not treat NFS app storage as Redis HA.

## Required NFS export

Create an NFS export dedicated to the app data, for example:

```text
/export/otp-relay-data
```

The K3s nodes that may run the app pod must be able to mount this export. The export must allow read/write access from the cluster nodes.

## Deployment variables

Enable NFS app storage with:

```bash
NFS_ENABLED=1
NFS_SERVER=<nfs-server-ip-or-dns>
NFS_PATH=/export/otp-relay-data
NFS_STORAGE_CLASS=otp-relay-nfs
NFS_PV_NAME=otp-relay-data-nfs-pv
PVC_STORAGE_CLASS=otp-relay-nfs
PVC_SIZE=1Gi
```

`PVC_STORAGE_CLASS` may be left empty when `NFS_ENABLED=1`; the installer will set it to `NFS_STORAGE_CLASS`.

Default mount option:

```bash
NFS_MOUNT_OPTIONS=nfsvers=4.1
```

Use a comma-separated value for multiple options.

## GitHub Actions

For GitHub Actions deployment, either provide the workflow dispatch inputs or set repository/environment secrets:

```text
NFS_SERVER
NFS_PATH
```

Then run the deployment with:

```text
nfs_enabled=1
pvc_storage_class=otp-relay-nfs
```

## Existing local-path PVC migration

Kubernetes does not allow changing a PVC `storageClassName` in place. If `otp-relay-data` already exists on `local-path`, the installer will refuse to mutate it.

Safe migration order:

1. Export or copy current `/app/data` files from the running pod.
2. Stop app writes or schedule a maintenance window.
3. Copy the files into the NFS export.
4. Delete the old app deployment and old `otp-relay-data` PVC only after data is backed up.
5. Redeploy with `NFS_ENABLED=1` and `PVC_STORAGE_CLASS=otp-relay-nfs`.
6. Verify the new PVC is `ReadWriteMany` and bound to the NFS PV.
7. Start the app and verify `/readyz`, admin login, OTP flow, and audit logging.

## Verification

```bash
sudo k3s kubectl get pv otp-relay-data-nfs-pv
sudo k3s kubectl get pvc otp-relay-data -n otp-relay
sudo k3s kubectl describe pvc otp-relay-data -n otp-relay
sudo k3s kubectl get pods -n otp-relay -o wide
curl -k https://srvotptest26.init-db.lan/readyz
```

Expected PVC state:

```text
NAME             STATUS   VOLUME                  CAPACITY   ACCESS MODES   STORAGECLASS
otp-relay-data   Bound    otp-relay-data-nfs-pv   1Gi        RWX            otp-relay-nfs
```

## SCH alignment

This closes the first major SCH architecture gap for app persistent data: the app PVC can now use shared network storage instead of node-local `local-path`/`ReadWriteOnce` storage.

Remaining production gaps after NFS app storage:

- Redis is still single-instance until Redis HA/Sentinel/approved Redis is implemented.
- App replicas should remain at `1` until NFS migration, Redis behavior, and final multi-replica OTP validation are complete.
- Final LB/VIP design still needs confirmation if SCH wants company VIP/F5/HAProxy/Keepalived rather than MetalLB.
