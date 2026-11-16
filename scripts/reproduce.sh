#!/usr/bin/env bash
# 从零复现 tokay (Pixel 9) 的 BakaSU + SUSFS GKI 内核。
# 用法：./reproduce.sh /opt/data/android/tokay/src
# 依赖：repo git python3 bc bison flex gperf cpio zip unzip lz4 patch rsync
#       clang/llvm/lld/bazel 由 manifest 的 prebuilts 提供，不要另外安装。
set -euo pipefail

SRC=${1:?用法: reproduce.sh <工作目录>}
HERE=$(cd "$(dirname "$0")/.." && pwd)          # 仓库根
BRANCH=${BRANCH:-common-android14-6.1-2026-09}
KSU_COMMIT=${KSU_COMMIT:-5d6d1843c8937f5ff2a145dc89a0cf46030ae6f8}
JOBS=${JOBS:-6}
RAM_MB=${RAM_MB:-9216}

mkdir -p "$SRC" && cd "$SRC"

echo "== 1/7 repo init + sync ($BRANCH) =="
if [ ! -d .repo ]; then
  repo init -u https://android.googlesource.com/kernel/manifest -b "$BRANCH" --depth=1 --no-tags
fi
# repo sync 可重入：中断后重跑安全
while :; do
  timeout 540 repo sync -c --depth=1 --no-tags -j4 --fail-fast && break
  echo "-- sync 中断，重试"; sleep 5
done

echo "== 2/7 基线 tag =="
[ -z "$(git -C common status --short)" ] || { echo "ERROR: common/ 不干净，停止"; exit 1; }
git -C common tag -f baseline-pre-baka-su >/dev/null

echo "== 3/7 注入 BakaSU =="
if [ ! -d KernelSU ]; then
  git clone https://github.com/Baka-SU/BakaSU KernelSU
fi
git -C KernelSU fetch --all --tags
git -C KernelSU checkout "$KSU_COMMIT"
ln -sfn ../../KernelSU/kernel common/drivers/kernelsu
grep -q 'kernelsu' common/drivers/Makefile || printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> common/drivers/Makefile
grep -q 'drivers/kernelsu/Kconfig' common/drivers/Kconfig || sed -i '/endmenu/i source "drivers/kernelsu/Kconfig"' common/drivers/Kconfig

echo "== 4/7 内核侧 SUSFS =="
cp "$HERE/patches/fs_susfs.c"              common/fs/susfs.c
cp "$HERE/patches/susfs.h"                 common/include/linux/susfs.h
cp "$HERE/patches/susfs_def.h"             common/include/linux/susfs_def.h
python3 "$HERE/scripts/susfs-dryrun.py" "$HERE/patches/50_add_susfs_in_gki-android14-6.1.patch" common
git -C common apply "$HERE/patches/50_add_susfs_in_gki-android14-6.1.patch"
if find common -name '*.rej' -o -name '*.orig' | grep -q .; then
  echo "ERROR: 存在 .rej/.orig，需手工合入"; find common -name '*.rej' -o -name '*.orig'; exit 1
fi

echo "== 4b 修 ksu_handle_sys_read 3 参签名 =="
python3 - <<'PY'
import re,pathlib
p=pathlib.Path('common/fs/read_write.c'); s=p.read_text()
s=s.replace('extern __attribute__((cold)) void ksu_handle_sys_read(unsigned int fd);',
            'extern __attribute__((cold)) int ksu_handle_sys_read(unsigned int fd, char __user **buf_ptr, size_t *count_ptr);')
s=s.replace('\t\tksu_handle_sys_read(fd);','\t\tksu_handle_sys_read(fd, &buf, &count);')
p.write_text(s)
print("patched:", 'ksu_handle_sys_read(fd, &buf, &count)' in s)
PY

echo "== 5/7 defconfig fragment =="
cp "$HERE/config/bakasu_susfs.fragment" common/
grep -q 'exports_files(\["bakasu_susfs.fragment"\]' common/BUILD.bazel || \
  printf '\nexports_files(["bakasu_susfs.fragment"], visibility = ["//visibility:public"])\n' >> common/BUILD.bazel
: > common/android/abi_gki_protected_exports_aarch64

echo "== 6/7 构建 =="
tools/bazel build --config=fast --config=stamp --jobs="$JOBS" --local_ram_resources="$RAM_MB" \
  --defconfig_fragment=//common:bakasu_susfs.fragment //common:kernel_aarch64_dist

echo "== 7/7 校验 =="
bash "$HERE/scripts/verify.sh" out/kernel_aarch64/dist
echo "完成。产物：$SRC/out/kernel_aarch64/dist"
