#!/usr/bin/env python3
"""Per-file dry-run of the susfs 50_ patch against the real kernel tree.

Splits the patch on 'diff --git' boundaries, writes one chunk at a time to
ONE_PATCH and runs `git apply --check -p1` from the kernel root.  Nothing is
applied: --check only.  Exits non-zero if any chunk fails.
"""
import os
import re
import subprocess
import sys

PATCH = "/opt/data/workspace/tokay-kernel/research/susfs4ksu/kernel_patches/50_add_susfs_in_gki-android14-6.1.patch"
KROOT = "/opt/data/android/tokay/src/common"
ONE = "/opt/data/cache/scratch/one.patch"
OUT = "/opt/data/android/tokay/logs/susfs-dryrun.txt"

text = open(PATCH, encoding="utf-8", errors="replace").read()
parts = re.split(r"(?m)^(?=diff --git )", text)
chunks = [p for p in parts if p.strip()]

rows = []
ok = fail = 0
for idx, ch in enumerate(chunks, 1):
    head = ch.splitlines()[0]
    m = re.match(r"diff --git a/(\S+) b/(\S+)", head)
    path = m.group(2) if m else head
    with open(ONE, "w", encoding="utf-8") as fh:
        fh.write(ch if ch.endswith("\n") else ch + "\n")
    r = subprocess.run(["git", "apply", "--check", "-p1", ONE],
                       cwd=KROOT, capture_output=True, text=True)
    if r.returncode == 0:
        ok += 1
        rows.append((idx, path, "OK", ""))
    else:
        fail += 1
        rows.append((idx, path, "FAIL", (r.stderr or "").strip()))

lines = ["# susfs 50_ patch dry-run on real tree: %s" % PATCH,
         "# kernel root: %s" % KROOT,
         "# chunks: %d  OK: %d  FAIL: %d" % (len(chunks), ok, fail),
         ""]
for idx, path, st, err in rows:
    lines.append("%3d  %-4s %s" % (idx, st, path))
    if err:
        for ln in err.splitlines():
            lines.append("         | " + ln)
lines.append("")
lines.append("RESULT: %d/%d OK" % (ok, len(chunks)))
out = "\n".join(lines)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
open(OUT, "w", encoding="utf-8").write(out + "\n")
print(out)
sys.exit(0 if fail == 0 else 1)
