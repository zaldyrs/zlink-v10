# Z-Link v10 — Backup and Restore

Encrypted backups of the Z-Link application, SQLite database, secrets,
firmware, dashboard, systemd service and Z-Link Nginx configuration.

Moodle files and configuration are outside the restore scope.

## Backup

```bash
/root/zlink-v10-tools/backup.sh
```

## Restore preview

Replace TIMESTAMP with the selected snapshot folder:

```bash
/root/zlink-v10-tools/restore.sh \
  /root/zlink-v10-backup/encrypted-snapshots/TIMESTAMP
```

## Apply restore

```bash
/root/zlink-v10-tools/restore.sh \
  /root/zlink-v10-backup/encrypted-snapshots/TIMESTAMP --apply
```

Restore overwrites Z-Link files and saves previous files locally.
Rollback is not automatic.

## Recovery requirements

Keep the original encryption key securely outside the VPS:

`/root/.config/zlink-backup/passphrase`

Never commit this key or a private SSH key to GitHub.

On a replacement VPS, install compatible application dependencies,
configure Nginx/TLS, restore the original key, then preview and apply
the snapshot. This backup is not a complete VPS image.

## Verified initial snapshot

- Snapshot: `20261009T132313-1561935`
- Commit: `ba3713a`
- SQLite quick_check passed.
- Backup uploaded to GitHub and restore preview completed.
- Live recovery on a replacement VPS has not yet been tested.

See [BACKUP_RESTORE_GUIDE.md](BACKUP_RESTORE_GUIDE.md)
for setup, SSH access, recovery steps and limitations.

Scripts are available in [tools/](tools/).
