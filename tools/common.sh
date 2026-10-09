#!/usr/bin/env bash
set -euo pipefail
umask 077
REPO=/root/zlink-v10-backup
REMOTE=git@github.com:zaldyrs/zlink-v10.git
KEY=/root/.config/zlink-backup/passphrase
PATHS=(root/zlink-test/zlink-server-smoke-test var/www/zlink-dashboard etc/systemd/system/zlink-test.service etc/nginx/sites-available/zlink-dashboard etc/nginx/sites-enabled/zlink-dashboard)
require_base() {
  [[ $EUID -eq 0 ]] || { echo 'Run as root'; exit 1; }
  for cmd in git gpg tar python3 rsync systemctl flock sha256sum split; do command -v "$cmd" >/dev/null || { echo "Missing: $cmd"; exit 1; }; done
  exec 9>/run/zlink-v10-backup.lock
  flock -n 9 || { echo 'Another backup/restore is running'; exit 1; }
  [[ -s "$KEY" ]] || { echo 'Encryption key missing. See README.'; exit 1; }
  python3 - "$KEY" <<'PY'
import os, sys
s=os.stat(sys.argv[1])
assert s.st_uid == 0 and not s.st_mode & 0o077, 'Key must be owned by root, permission 600'
PY
}
