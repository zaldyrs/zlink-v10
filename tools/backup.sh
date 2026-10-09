#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
require_base
for p in "${PATHS[@]}"; do [[ -e /$p ]] || { echo "Missing path: /$p"; exit 1; }; done
if [[ ! -d "$REPO" ]]; then git clone "$REMOTE" "$REPO"; fi
[[ $(git -C "$REPO" remote get-url origin) == "$REMOTE" ]] || { echo 'Unexpected Git origin'; exit 1; }
[[ -z $(git -C "$REPO" status --porcelain) ]] || { echo 'Repository has uncommitted changes. Resolve before backup.'; exit 1; }
git -C "$REPO" pull --ff-only
STAMP=$(date -u +%Y%m%dT%H%M%S)-$$
TMP=$(mktemp -d /var/tmp/zlink-backup.XXXXXXXX)
WAS_ACTIVE=0
cleanup() {
  result=$?
  trap - EXIT INT TERM
  if [[ $WAS_ACTIVE == 1 ]]; then systemctl start zlink-test || result=1; fi
  rm -rf -- "$TMP"
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if systemctl is-active --quiet zlink-test; then WAS_ACTIVE=1; systemctl stop zlink-test; fi
# Include SQLite DB, WAL/SHM, secrets and all active application files.
tar -C / -czf "$TMP/snapshot.tar.gz" -- "${PATHS[@]}"
if [[ $WAS_ACTIVE == 1 ]]; then systemctl start zlink-test; WAS_ACTIVE=0; fi
# Validate saved DB before publishing, without touching live DB.
python3 - "$TMP/snapshot.tar.gz" "$TMP" <<'PY'
import tarfile, pathlib, sqlite3, sys
root=pathlib.Path(sys.argv[2])/'dbcheck'; root.mkdir()
prefix='root/zlink-test/zlink-server-smoke-test/data/zlink.sqlite3'
with tarfile.open(sys.argv[1]) as t:
    for suffix in ('', '-wal', '-shm'):
        try: m=t.getmember(prefix+suffix)
        except KeyError:
            if not suffix: raise
            continue
        if not m.isfile(): raise RuntimeError('SQLite file must be regular')
        with t.extractfile(m) as f: (root/('zlink.sqlite3'+suffix)).write_bytes(f.read())
c=sqlite3.connect(str(root/'zlink.sqlite3'))
assert c.execute('PRAGMA quick_check').fetchall()==[('ok',)], 'SQLite quick_check failed'
c.close()
print('Saved SQLite quick_check: OK')
PY
gpg --batch --yes --pinentry-mode loopback --passphrase-file "$KEY" \
  --symmetric --cipher-algo AES256 --output "$TMP/snapshot.gpg" "$TMP/snapshot.tar.gz"
mkdir "$TMP/parts"
split -b 45M -d -a 5 "$TMP/snapshot.gpg" "$TMP/parts/snapshot.gpg.part-"
(cd "$TMP/parts"; sha256sum snapshot.gpg.part-* > SHA256SUMS)
OUT="$REPO/encrypted-snapshots/$STAMP"
mkdir -p "$REPO/encrypted-snapshots"
mv "$TMP/parts" "$OUT"
git -C "$REPO" add -- "encrypted-snapshots/$STAMP"
git -C "$REPO" commit -m "Encrypted Z-Link snapshot $STAMP"
git -C "$REPO" push origin HEAD
echo "BACKUP COMPLETE: $OUT"
