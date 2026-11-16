#!/usr/bin/env bash
# 校验 dist 产物：符号、config、模块数、构建横幅。
# 用法：./verify.sh <dist 目录> [build.log] [.config]
set -uo pipefail
D=${1:?用法: verify.sh <dist> [build.log] [.config]}
LOG=${2:-}
CFG=${3:-}
rc=0

chk() { # chk <描述> <命令...>
  local d=$1; shift
  if "$@" >/dev/null 2>&1; then echo "  OK   $d"; else echo "  FAIL $d"; rc=1; fi
}

echo "== 内核版本 =="
strings -a "$D/vmlinux" 2>/dev/null | grep -m1 'Linux version' || { echo "  FAIL 读不到 vmlinux"; rc=1; }

echo "== 符号 =="
for s in susfs_init susfs_add_sus_path kernelsu_init; do
  chk "$s" bash -c "nm -n '$D/vmlinux' | grep -qE ' $s\$'"
done

echo "== 产物 =="
chk "Image.lz4 存在" test -f "$D/Image.lz4"
chk "模块 >=50" bash -c "[ \$(ls '$D'/*.ko 2>/dev/null | wc -l) -ge 50 ]"
echo "  模块数: $(ls "$D"/*.ko 2>/dev/null | wc -l)"

if [ -n "$CFG" ] && [ -f "$CFG" ]; then
  echo "== CONFIG =="
  chk "CONFIG_KSU=y"                    grep -q '^CONFIG_KSU=y' "$CFG"
  chk "CONFIG_KSU_SUSFS=y"              grep -q '^CONFIG_KSU_SUSFS=y' "$CFG"
  chk "CONFIG_KSU_MANUAL_HOOK 未开"     bash -c "! grep -q '^CONFIG_KSU_MANUAL_HOOK=y' '$CFG'"
  chk "CONFIG_KSU_TRACEPOINT_HOOK 未开" bash -c "! grep -q '^CONFIG_KSU_TRACEPOINT_HOOK=y' '$CFG'"
fi

if [ -n "$LOG" ] && [ -f "$LOG" ]; then
  echo "== 构建横幅 =="
  chk "using SuSFS Inline hook"  grep -q 'using SuSFS Inline hook' "$LOG"
  chk "SUSFS_VERSION"            grep -q 'SUSFS_VERSION' "$LOG"
  chk "selinux_hide 探测命中"    grep -q 'selinux_hide manual hook found' "$LOG"
  chk "8 个 ksu hook 落点"       bash -c "[ \$(grep -c 'susfs_inline: ksu_handle_' '$LOG') -ge 8 ]"
fi

echo
[ $rc -eq 0 ] && echo "全部通过" || echo "存在失败项"
exit $rc
