# tokay-gki-bakasu-susfs

Google Pixel 9（`tokay`，Tensor G4 / zumapro）自编译 GKI 内核，内置 **BakaSU** 与 **SUSFS**，纯 GKI 路线（不改 vendor 分区）。

- 内核版本：`6.1.176-android14-11-g45bc826d05a2`
- 基线分支：`common-android14-6.1-2026-09`（AOSP `kernel/manifest`）
- 设备固件：`CP3A.261005.005`（SPL 2026-10-05，Android 17）
- 结果：可正常开机，`/proc/modules` 330 个模块（原厂 `vendor_dlkm` 全部加载），SUSFS 管理器 9 项特性全部「支持」

本仓库不含内核源码（AOSP GKI 源树 >10 GB，且 `repo` 浅克隆无法直接 push）。这里存放**完整可复现的配方**：补丁、defconfig fragment、构建/校验脚本、以及各阶段调研与施工报告。

---

## 1. 版本锁定

| 组件 | 版本 / 提交 | 来源 |
| --- | --- | --- |
| GKI 分支 | `common-android14-6.1-2026-09` | `android.googlesource.com/kernel/manifest` |
| `kernel/common` | `47ef95e42b7521a3c886ff18d879361afc536ade`（6.1.176） | manifest |
| BakaSU | `5d6d1843c8937f5ff2a145dc89a0cf46030ae6f8`（v4.2.0-rc3，`main`） | `github.com/Baka-SU/BakaSU` |
| susfs4ksu | `f76b81f2a6bf98e4029cc0c823c054edbec29803`（v2.4.0） | `gitlab.com/simonpunk/susfs4ksu`，分支 `gki-android14-6.1` |
| 工具链 | prebuilt clang `r487747c`（17.0.2）+ Bazel（Kleaf 自带） | manifest prebuilts |

## 2. 产物

| 文件 | SHA-256 |
| --- | --- |
| `boot-bakasu-susfs.img` | `542568ba7252d2872a7c24940e3c71efd35d959cdea17bfa7e1d6f6555596e02` |
| `AK3-bakasu-susfs-tokay-6.1.176-20261116-r2.zip` | `545bb3acd8f820f34be50c81087f1d1930643cdd2667fd4831d29cac0df4d629` |
| 内核 `Image.lz4` | `d19b0b91b13bcbe6841f45ea2b01885383765e355d3b2f2d37c39a24731309ef` |
| 解压后 `Image` | `c7426d3f27e444576e264a259f7bb99c9b520ecb53b74d085d5564d7cac3b365` |

二进制放在本仓库的 Release 里。

## 3. 已实测的验证结论

- `uname -r` → `6.1.176-android14-11-g45bc826d05a2`
- BakaSU 管理器：Manager `v4.2.0-rc3`、SuFS `v2.4.0`、**Hook type = Inline**（即 `CONFIG_KSU_SUSFS` 分支被选中）、SELinux `Enforcing`
- SUSFS 状态页：`SUS_PATH / SUS_MOUNT / SUS_KSTAT / SPOOF_UNAME / ENABLE_LOG / HIDE_KSU_SUSFS_SYMBOLS / SPOOF_CMDLINE_OR_BOOTCONFIG / OPEN_REDIRECT / SUS_MAP` 全部「支持」
- `/proc/modules` = 330 项，`syna_touch`、`wlan_ptracker`、`snd_soc_wm_adsp`、`fps_touch_handler`、`goog_touch_interface` 均加载成功 —— 6.1.162 原厂模块在 6.1.176 内核上 CRC 校验通过
- vmlinux 符号：`susfs_init`、`susfs_add_sus_path`、`susfs_show_version`、`kernelsu_init`、`ksu_handle_sys_read` 均在
- KMI strict mode 检查零违规（未使用 `--nokmi_symbol_list_strict_mode`）

## 4. 目录

```
patches/
  50_add_susfs_in_gki-android14-6.1.patch   # 内核侧 SUSFS 补丁（27 文件 / 132 hunk）
  fs_susfs.c susfs.h susfs_def.h            # 补丁不创建、需先放入内核树的新文件
  susfs-kernel-side-integration.diff        # 打完补丁 + 修签名后的完整 git diff（含新增文件）
  bakasu-setup-changes.diff                 # BakaSU setup.sh 对内核树的两处改动
  BUILD.bazel.diff                          # exports_files(fragment)
  abi_gki_protected_exports_aarch64.diff    # 按 susfs README 要求清空该文件
  manifest-2026-09-rev.xml                  # 18 个 project 的精确修订快照
config/
  bakasu_susfs.fragment                     # Kleaf defconfig fragment
scripts/
  reproduce.sh                              # 从零复现（sync → 补丁 → 构建 → 校验）
  susfs-dryrun.py                           # 逐文件 git apply --check
  sync-loop.sh                              # 可重入的 repo sync 循环
docs/
  phase1-env.md phase1-upstream.md phase2-sync.md
  phase3-patch.md phase4-build.md phase5-package.md
  FLASHING.md                               # 刷机 / 备份 / 回滚
```

## 5. 从零复现

```bash
# 0) 环境：repo、git、python3、bc/bison/flex/gperf/cpio/zip/unzip/lz4/patch/rsync
#    clang/llvm/lld/bazel 全部来自 manifest 的 prebuilts，不要自己装

# 1) 同步（浅克隆，约 11 GB）
repo init -u https://android.googlesource.com/kernel/manifest -b common-android14-6.1-2026-09 --depth=1 --no-tags
repo sync -c --depth=1 --no-tags -j4 --fail-fast

# 2) 基线 tag（改动前）
git -C common status --short     # 必须为空
git -C common tag baseline-pre-baka-su

# 3) 注入 BakaSU（固定 commit；脚本会建 drivers/kernelsu 软链并改 drivers/{Makefile,Kconfig}）
bash BakaSU/kernel/setup.sh 5d6d1843c8937f5ff2a145dc89a0cf46030ae6f8

# 4) 内核侧 SUSFS（先放 3 个新文件，再打补丁；KSU 侧补丁一律不打）
cp patches/fs_susfs.c          common/fs/susfs.c
cp patches/susfs.h             common/include/linux/susfs.h
cp patches/susfs_def.h         common/include/linux/susfs_def.h
python3 scripts/susfs-dryrun.py patches/50_add_susfs_in_gki-android14-6.1.patch common   # 必须 27/27 OK
git -C common apply "$PWD/patches/50_add_susfs_in_gki-android14-6.1.patch"
find common -name '*.rej' -o -name '*.orig'     # 必须为空

# 5) 修 fs/read_write.c 的签名偏差（见 §6.1）
#    extern 改为 3 参；调用改为 ksu_handle_sys_read(fd, &buf, &count);

# 6) defconfig fragment + 删 protected exports
cp config/bakasu_susfs.fragment common/
# 在 common/BUILD.bazel 增加 exports_files(["bakasu_susfs.fragment"], visibility=["//visibility:public"])
: > common/android/abi_gki_protected_exports_aarch64

# 7) 构建（内存 <24 GB 时必须显式限并发）
tools/bazel build --config=fast --config=stamp --jobs=6 --local_ram_resources=9216 \
  --defconfig_fragment=//common:bakasu_susfs.fragment //common:kernel_aarch64_dist
```

产物在 `out/kernel_aarch64/dist/`（`Image.lz4`、60 个 `.ko`、`system_dlkm.img`、`boot.img`）。

## 6. 关键决策与踩坑（值得先读）

### 6.1 KSU 侧补丁一个都不能打
BakaSU `main` 已内置 SUSFS 的 KSU 侧：`kernel/core/init.c` 调 `susfs_init()`、`kernel/supercall/dispatch.c` 有 `ksu_handle_susfs_cmd`、`sucompat.h` 有 `CONFIG_KSU_SUSFS` 分支。susfs4ksu 的 `10_enable_susfs_for_ksu.patch` 对 BakaSU 树 dry-run **28/32 文件失败**——这个失败是**健康信号**，不是要修的问题。只需内核侧（`fs/`、`include/linux/`、`security/selinux/`、`mm/`、`block/`、`kernel/`）。

### 6.2 `ksu_handle_sys_read` 签名漂移（真 Bug）
susfs 补丁按 1 参调用并 `extern` 成 `void ksu_handle_sys_read(unsigned int fd)`，而 BakaSU 定义是 `int ksu_handle_sys_read(unsigned int fd, char __user **buf, size_t *count)`。分 TU 声明 → **编译不报错**，链接到 3 参实现，多余两参未初始化 = UB。必须把 `fs/read_write.c` 的调用改成 `ksu_handle_sys_read(fd, &buf, &count)`，`extern` 同步改成 3 参。

### 6.3 hook 模式是互斥 choice
`drivers/kernelsu/Kconfig` 里 tracepoint / manual / susfs 三选一，默认 tracepoint；且 `Kbuild` 的 else-if 顺序是 `manual` 先于 `susfs`，**同时开 manual 会让 SUSFS 变死代码**。所以 fragment 里显式 `# CONFIG_KSU_TRACEPOINT_HOOK is not set` + `# CONFIG_KSU_MANUAL_HOOK is not set`。

### 6.4 Kleaf 相关
- fragment 里**不要**在注释中出现 `CONFIG_*` 符号名：Kleaf 用整文件 word-grep 取期望值，注释里的符号会被当成期望项而失败。
- `--config=fast` 不含 `--config=stamp`，`impl/stamp.bzl` 在无 stamp 时硬写 `-maybe-dirty`；要干净版本串必须加 `--config=stamp`。
- `--jobs` 默认取 `nproc`，24 核 / 15 GB 机器上会 OOM；`--local_ram_resources` 同值。
- susfs 不新增任何 `EXPORT_SYMBOL`，因此 KMI strict mode 不会红；**不要**用 `--nokmi_symbol_list_strict_mode` 回避编译错误。

### 6.5 模块兼容的真实机制
`CONFIG_MODVERSIONS=y` 时 `same_magic()` 只比较 vermagic 第一个空格之后的部分（`SMP preempt mod_unload modversions aarch64`），**忽略内核版本号**；真正会拦的是符号 CRC。因此 6.1.162 的原厂 `vendor_dlkm` / `system_dlkm` 可直接用，不必重刷 vendor 分区（实测 330 模块全部加载）。

### 6.6 不要动 vbmeta
`ro.boot.verifiedbootstate=orange` 只代表 bootloader 已解锁；解锁状态下 bootloader 本来容忍 boot 签名不符。**改 vbmeta 的 verity 标志才是风险**（可能触发 `/data` 挂载校验变化）。全程只写 `boot`（必要时 `init_boot`）。

### 6.7 AK3 包的工具必须是 aarch64
AnyKernel3 模板自带的是 arm（32 位）/ x86 工具；Pixel 9 上要用 Magisk APK 里 `lib/arm64-v8a/libmagiskboot.so`、`libbusybox.so`（静态）。批量解包时**必须按 ABI 分目录**，否则同名文件互相覆盖，手机会在 `Busybox setup failed. Aborting...` 处中止（此时尚未写任何分区，安全）。

## 7. 刷机 / 回滚

见 `docs/FLASHING.md`。要点：

1. 先备份 `boot`/`init_boot`（A/B 设备节点是 `boot_a`/`boot_b`，没有 `boot`），并拉到电脑。
2. 若原 root 是 init_boot LKM（SukiSU/KernelSU LKM），刷内核后必须把 `init_boot` 还原成原厂，否则两套 root 冲突。
3. 不刷 vbmeta、不 `fastboot flashing lock`。
4. 回滚 = 刷回备份的 `boot`/`init_boot`。

## 8. 已知缺口

- `CONFIG_KSU_SUSFS_PRIORITY_UID_FILTER` 在 BakaSU 的 Kconfig 中**不存在**，`ioprio_set` / `setpriority` / `getpriority` 的 uid 过滤因此不可用（不影响 SUS_PATH/SUS_MOUNT/SUS_KSTAT/OPEN_REDIRECT 等主要隐藏能力）。
- 本配方只验证了 Pixel 9（`tokay`）+ `CP3A.261005.005`；换固件需重新对齐分支与 SPL。
- 设备分支 `android-gs-caimito-6.1-android16` 依赖 partner-only 的 `private/devices/google/*`，外部无法同步，故走纯 GKI 路线。

## 9. 许可与来源

- 内核源码：GPL-2.0（AOSP `kernel/common`）
- BakaSU：GPL-2.0 / GPL-3.0（见上游仓库）
- susfs4ksu：见上游仓库
- 本仓库内的脚本与文档：与原项目同许可，仅供个人设备使用
