#!/usr/bin/env bash
# Throwaway end-to-end test of the deployed /usr/local/bin/zfs-scrub repair path.
# Uses a file-backed pool "scrubtest" and a local restic repo; never touches
# pool "data" or B2. Run as root on the server, after deploying playbooks/zfs-scrub.yml:
#   scp scripts/zfs-scrub-test.sh strutserver:/tmp/ && ssh -t strutserver sudo bash /tmp/zfs-scrub-test.sh
# Re-run whenever playbooks/templates/zfs-scrub/zfs-scrub.sh.j2 changes.
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "run as root" >&2; exit 1; }

POOL=scrubtest
MNT=/$POOL
W=$(mktemp -d /var/tmp/zfs-scrub-test.XXXXXX)
cleanup() { zpool destroy -f "$POOL" 2>/dev/null || true; rm -rf "$W"; }
trap cleanup EXIT

zpool list "$POOL" &>/dev/null && { echo "pool $POOL already exists" >&2; exit 1; }

echo "== create pool and files"
truncate -s 256M "$W/vdev"
zpool create -O mountpoint="$MNT" -O compression=off "$POOL" "$W/vdev"
mkdir "$MNT/dir"
BAD1="$MNT/dir/a [1].bin"
BAD2="$MNT/dir/s*t?.bin"
OK="$MNT/dir/ok.bin"
for f in "$BAD1" "$BAD2" "$OK"; do head -c 4M /dev/urandom > "$f"; done
sha_before=$(sha256sum "$BAD1" "$BAD2" "$OK")
# 64-byte needles from 2 MiB into each bad file, to locate them in the vdev.
dd if="$BAD1" of="$W/needle1" bs=64 skip=32768 count=1 status=none
dd if="$BAD2" of="$W/needle2" bs=64 skip=32768 count=1 status=none

echo "== back up to a local restic repo (tag photos)"
export RESTIC_REPOSITORY="$W/repo" RESTIC_PASSWORD=test RESTIC_CACHE_DIR="$W/cache"
restic init -q
restic backup -q --tag photos "$MNT"
printf 'B2_ACCOUNT_ID=x\nB2_ACCOUNT_KEY=x\nRESTIC_REPOSITORY=%s\nRESTIC_PASSWORD=test\n' "$W/repo" > "$W/env"

echo "== corrupt the two bad files inside the vdev"
zpool export "$POOL"
python3 -I - "$W/vdev" "$W/needle1" "$W/needle2" <<'EOF'
import sys
vdev, *needles = sys.argv[1:]
data = open(vdev, "rb").read()
with open(vdev, "r+b") as v:
    for n in needles:
        needle = open(n, "rb").read()
        i = data.find(needle)
        assert i >= 0 and data.find(needle, i + 1) < 0, "needle not unique/found"
        v.seek(i)
        v.write(b"\xde\xad\xbe\xef" * 1024)
EOF
zpool import -d "$W" "$POOL"

echo "== precondition: a plain scrub must now report permanent errors"
zpool scrub -w "$POOL"
zpool status -v "$POOL" | grep -q 'Permanent errors' \
  || { echo "FAIL: corruption did not take, test invalid" >&2; exit 1; }
zpool status -v "$POOL" | sed -n '/^errors:/,$p'

echo "== run the deployed script against the test pool"
# Same script, pool/env swapped, healthchecks pings removed.
sed -e "s|^POOL=.*|POOL=$POOL|" -e "s|^ENV_FILE=.*|ENV_FILE=$W/env|" \
    -e '/^curl /d' -e '/^trap /d' /usr/local/bin/zfs-scrub > "$W/zfs-scrub-test"
set +e
bash "$W/zfs-scrub-test"
rc=$?
set -e

echo "== verify"
fail=0
[[ $rc -eq 2 ]] || { echo "FAIL: expected exit 2 (repaired), got $rc"; fail=1; }
[[ "$(sha256sum "$BAD1" "$BAD2" "$OK")" == "$sha_before" ]] \
  || { echo "FAIL: checksums differ after repair"; fail=1; }
ls -A "$MNT/dir" | grep -q '^\.zfs-repair' && { echo "FAIL: temp dir left behind"; fail=1; }
zpool status -x "$POOL" | grep -q 'is healthy' || { echo "FAIL: pool not healthy"; fail=1; }
(( fail )) && exit 1
echo "PASS: both files repaired (exit $rc), checksums match, pool healthy"
