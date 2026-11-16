#!/bin/bash
# Re-entrant repo sync loop.
# NOTE: repo 2.71 has no `repo sync --depth`; shallow clones come from the
# manifest `clone-depth` attribute instead (.repo/manifests/shallow.xml, a copy
# of default.xml with clone-depth="1" on all 18 projects).
set -u
. /opt/data/tools/bin/android-env.sh >/dev/null 2>&1
cd /opt/data/android/tokay/src || exit 2
LOG=/opt/data/android/tokay/logs/repo-sync.log
echo "############ sync loop start $(date -Is) ############" >> "$LOG"
for i in $(seq 1 24); do
  echo "=== attempt $i/24 start $(date -Is) ===" >> "$LOG"
  timeout 540 repo sync -c --no-tags -j4 --fail-fast --no-clone-bundle \
      --retry-fetches=3 -m shallow.xml >> "$LOG" 2>&1
  rc=$?
  echo "=== attempt $i/24 exit=$rc $(date -Is) ===" >> "$LOG"
  if [ "$rc" -eq 0 ]; then
    echo "############ SYNC_OK after $i attempt(s) $(date -Is) ############" >> "$LOG"
    echo "SYNC_OK attempts=$i"
    exit 0
  fi
  sleep 3
done
echo "############ SYNC_FAILED after 24 attempts $(date -Is) ############" >> "$LOG"
echo "SYNC_FAILED"
exit 1
