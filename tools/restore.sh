#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
require_base
[[ $# -ge 1 && $# -le 2 ]] || { echo 'Usage: restore.sh SNAPSHOT_DIRECTORY [--apply]'; exit 1; }
MODE=${2:-preview}
[[ $MODE == preview || $MODE == --apply ]] || { echo 'Unknown option'; exit 1; }
SNAPSHOT=$(realpath -- "$1")
[[ -d "$SNAPSHOT" ]] || { echo 'Snapshot directory missing'; exit 1; }
TMP=$(mktemp -d /var/tmp/zlink-restore.XXXXXXXX)
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
# Validate ordered parts and checksums, reject extra/missing files.
python3 - "$SNAPSHOT" "$TMP/snapshot.gpg" <<'PY'
import pathlib, sys, re, hashlib, shutil
p=pathlib.Path(sys.argv[1]); entries=[]
for line in (p/'SHA256SUMS').read_text().splitlines():
    m=re.fullmatch(r'([0-9a-f]{64})  (snapshot\.gpg\.part-\d{5})',line)
    if not m: raise RuntimeError('Invalid checksum manifest')
    entries.append(m.groups())
expected=[f'snapshot.gpg.part-{i:05d}' for i in range(len(entries))]
assert entries and [n for _,n in entries]==expected, 'Invalid part sequence'
assert sorted(f.name for f in p.glob('snapshot.gpg.part-*'))==expected, 'Missing/extra parts'
with open(sys.argv[2],'wb') as out:
    for digest,name in entries:
        f=p/name
        assert not f.is_symlink() and f.is_file(), 'Invalid part file'
        h=hashlib.sha256()
        with f.open('rb') as src:
            while chunk:=src.read(1024*1024): h.update(chunk)
        assert h.hexdigest()==digest, 'Checksum mismatch: '+name
        with f.open('rb') as src: shutil.copyfileobj(src,out)
PY
gpg --batch --yes --pinentry-mode loopback --passphrase-file "$KEY" \
  --output "$TMP/snapshot.tar.gz" --decrypt "$TMP/snapshot.gpg"
python3 - "$TMP/snapshot.tar.gz" "$TMP/stage" "${PATHS[@]}" <<'PY'
import pathlib, sys, tarfile
stage=pathlib.Path(sys.argv[2]); stage.mkdir(); allowed=sys.argv[3:]
with tarfile.open(sys.argv[1]) as t:
    for m in t.getmembers():
        name=m.name.rstrip('/')
        if not any(name==p or name.startswith(p+'/') for p in allowed):
            raise RuntimeError('Archive outside Z-Link scope: '+m.name)
    t.extractall(stage,filter='data')
for p in allowed:
    assert (stage/p).exists(), 'Missing required restore path: '+p
print('Archive scope and required paths: OK')
PY
printf 'Restore scope: /%s\n' "${PATHS[@]}"
if [[ $MODE == preview ]]; then echo 'Preview complete; add --apply to restore.'; exit 0; fi
command -v nginx >/dev/null || { echo 'Install nginx first'; exit 1; }
nginx -t
ROLLBACK=/var/backups/zlink-v10/$(date -u +%Y%m%dT%H%M%S)-$$
mkdir -p "$ROLLBACK"
if systemctl is-active --quiet zlink-test; then WAS_ACTIVE=1; systemctl stop zlink-test; fi
EXISTING=()
for p in "${PATHS[@]}"; do [[ ! -e /$p ]] || EXISTING+=("$p"); done
if [[ ${#EXISTING[@]} -gt 0 ]]; then tar -C / -czf "$ROLLBACK/before-restore.tar.gz" -- "${EXISTING[@]}"; fi
# Remove previous SQLite sidecars after rollback, before copying snapshot.
rm -f -- /root/zlink-test/zlink-server-smoke-test/data/zlink.sqlite3-wal /root/zlink-test/zlink-server-smoke-test/data/zlink.sqlite3-shm
for p in "${PATHS[@]}"; do
  if [[ -d "$TMP/stage/$p" ]]; then
    mkdir -p "/$p"
    rsync -aH -- "$TMP/stage/$p/" "/$p/"
  else
    mkdir -p -- "$(dirname -- "/$p")"
    rsync -aH -- "$TMP/stage/$p" "/$p"
  fi
done
systemctl daemon-reload
if ! nginx -t; then
  echo "Nginx validation failed. Restore is partial; previous files: $ROLLBACK"
  exit 1
fi
systemctl reload nginx
if [[ $WAS_ACTIVE == 1 ]]; then systemctl start zlink-test; WAS_ACTIVE=0; fi
echo "RESTORE COMPLETE. Previous files: $ROLLBACK"
echo 'On a new VPS: install application dependencies, then systemctl enable --now zlink-test.'
