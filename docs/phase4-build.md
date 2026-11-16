# Phase 4 — defconfig 配置 + Kleaf 编译报告

项目：Pixel 9 (tokay) / GKI `android14-6.1-2026-09`（kernel 6.1.176）/ Kleaf-Bazel
阶段目标：defconfig fragment 打开 KernelSU(BakaSU) + SUSFS，编译 `//common:kernel_aarch64_dist` 并修复错误
结论：**一次编译通过，零编译错误**。产物已落盘。

---

## 0. 结论速览

| 项 | 结果 |
|---|---|
| fragment 回验 | 通过（Kleaf `KernelConfig` 动作成功） |
| 全量编译 | 成功，`Build completed successfully, 167 total actions`，355s |
| 编译错误修复轮次 | 0（3 个报错全部是容器/Kleaf 环境问题，非内核源码问题） |
| SUSFS banner | `-- SUSFS_VERSION: v2.4.0` / `-- BakaSU: using SuSFS Inline hook` / `selinux_hide manual hook found` 全部出现 |
| KMI strict mode | 通过，**未使用** `--nokmi_symbol_list_strict_mode` |
| dist 产物 | 96 个文件 / 743 MB |
| 内核 release | `6.1.176-android14-11-maybe-dirty` |
| 编译器 | `clang-r487747c`（预置 toolchain_version） |

---

## 1. defconfig fragment

### 1.1 文件：`common/bakasu_susfs.fragment`（新建）

```text
# BakaSU (KernelSU) + SUSFS defconfig fragment
# Applied via --defconfig_fragment=//common:bakasu_susfs.fragment
#
# Hook method = SUSFS inline hook (Kconfig choice "KernelSU Hooking Method").
# BakaSU driver/Kbuild evaluates in this order:
#   ifdef tracepoint hook -> else ifdef manual hook -> else ifdef susfs
# so the tracepoint and manual hook choice members must be explicitly off,
# otherwise the SUSFS branch becomes dead code.
#
# NOTE: do not write raw symbol names in comments here - Kleaf's fragment
# verifier greps the whole file for each symbol and would pick up the comment.
#
# NOTE: the priority-uid-filter knob does not exist in BakaSU's
# drivers/kernelsu/Kconfig (only 10 susfs symbols exist), so it is omitted.

CONFIG_KSU=y
CONFIG_KSU_SUSFS=y
# CONFIG_KSU_TRACEPOINT_HOOK is not set
# CONFIG_KSU_MANUAL_HOOK is not set

CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
```

### 1.2 每个符号的 Kconfig 存在性验证（`common/drivers/kernelsu/Kconfig`）

| 符号 | Kconfig 行 | 类型 / 依赖 | 存在 | 最终 .config |
|---|---|---|---|---|
| `CONFIG_KSU` | :3 | tristate, `default y`, `select KALLSYMS` | ✅ | `=y` |
| `CONFIG_KSU_SUSFS` | :104 | bool，choice 成员，`depends on THREAD_INFO_IN_TASK && 64BIT` | ✅ | `=y` |
| `CONFIG_KSU_TRACEPOINT_HOOK` | :88 | bool，choice 成员（default） | ✅ | `is not set` |
| `CONFIG_KSU_MANUAL_HOOK` | :96 | bool，choice 成员，`depends on KSU != m` | ✅ | `is not set` |
| `CONFIG_KSU_SUSFS_SUS_PATH` | :169 | bool, `depends on KSU_SUSFS`, default y | ✅ | `=y` |
| `CONFIG_KSU_SUSFS_SUS_MOUNT` | :180 | 同上 | ✅ | `=y` |
| `CONFIG_KSU_SUSFS_SUS_KSTAT` | :188 | 同上 | ✅ | `=y` |
| `CONFIG_KSU_SUSFS_SPOOF_UNAME` | :196 | 同上 | ✅ | `=y` |
| `CONFIG_KSU_SUSFS_ENABLE_LOG` | :204 | 同上 | ✅ | `=y` |
| `CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS` | :211 | 同上 | ✅ | `=y` |
| `CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG` | :219 | 同上 | ✅ | `=y` |
| `CONFIG_KSU_SUSFS_OPEN_REDIRECT` | :227 | 同上 | ✅ | `=y` |
| `CONFIG_KSU_SUSFS_SUS_MAP` | :236 | 同上 | ✅ | `=y` |
| `CONFIG_KSU_SUSFS_PRIORITY_UID_FILTER` | — | **不存在**（`grep -r PRIORITY_UID_FILTER drivers/kernelsu/` 无输出） | ❌ | — |

> 全树只有 10 个 `config KSU_SUSFS*`（`KSU_SUSFS` + 9 个子项），与预期一致。
> 已按任务要求把不存在的 `CONFIG_KSU_SUSFS_PRIORITY_UID_FILTER` **剔除**，未写入 fragment。

### 1.3 Bazel 导出

`common/BUILD.bazel` 在 `package()` 之后新增（原本没有 `exports_files`，无重复）：

```python
exports_files([
    "bakasu_susfs.fragment",
])
```

`--defconfig_fragment` 是 `//build/kernel/kleaf:defconfig_fragment` label_flag（`build/kernel/kleaf/BUILD.bazel:410`），无 `allow_files` 限制，任意已导出文件均可。文档 `build/kernel/kleaf/docs/kernel_config.md:97-130` 只要求文件被 `exports_files` 或 `filegroup` 导出；`X_defconfig` 命名只是约定，未强制。

### 1.4 按 SUSFS README 删除 protected exports

```bash
cp -a common/android/abi_gki_protected_exports_aarch64 /opt/data/android/tokay/patches/abi_gki_protected_exports_aarch64.orig
cp -a common/android/abi_gki_protected_exports_aarch64 common/android/abi_gki_protected_exports_aarch64.bak
: > common/android/abi_gki_protected_exports_aarch64        # 359 行 → 0 字节
```

保留空文件而非 `rm`：`common/BUILD.bazel:149` 的 `protected_exports_list = "android/abi_gki_protected_exports_aarch64"` 是 `attr.label(allow_single_file=True)`，文件缺失会让 Bazel 在 loading 阶段直接失败。空列表对本次 `kernel_aarch64_dist` 无影响（该列表只被 ABI 系列 target 消费）。备份：`/opt/data/android/tokay/patches/abi_gki_protected_exports_aarch64.orig`。

---

## 2. config target 与配置回验

```
$ tools/bazel query 'kind(".*config.*", //common:all)'   # 命中 kernel_aarch64_config
$ tools/bazel query '//common:kernel_aarch64_config'
//common:kernel_aarch64_config
```

配置生成命令（成功）：

```bash
tools/bazel build --config=fast --jobs=6 --local_ram_resources=9216 \
  --defconfig_fragment=//common:bakasu_susfs.fragment \
  //common:kernel_aarch64_config
# Target //common:kernel_aarch64_config up-to-date:
#   bazel-bin/common/kernel_aarch64_config/out_dir
# Build completed successfully, 7 total actions
```

产物 `.config`（`bazel-bin/common/kernel_aarch64_config/out_dir/.config`，以及实际构建目录 `out/cache/acb3ac36/common/.config`）：

```
6533:CONFIG_KSU=y
6534:# CONFIG_KSU_DEBUG is not set
6539:CONFIG_KSU_MULTI_MANAGER_SUPPORT=y
6540:# CONFIG_KSU_TRACEPOINT_HOOK is not set
6541:# CONFIG_KSU_MANUAL_HOOK is not set
6542:CONFIG_KSU_SUSFS=y
6571:CONFIG_KSU_SUSFS_SUS_PATH=y
6572:CONFIG_KSU_SUSFS_SUS_MOUNT=y
6573:CONFIG_KSU_SUSFS_SUS_KSTAT=y
6574:CONFIG_KSU_SUSFS_SPOOF_UNAME=y
6575:CONFIG_KSU_SUSFS_ENABLE_LOG=y
6576:CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
6577:CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
6578:CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
6579:CONFIG_KSU_SUSFS_SUS_MAP=y
```

---

## 3. 构建命令

```bash
cd /opt/data/android/tokay/src
. /opt/data/tools/bin/android-env.sh          # PATH / LD_LIBRARY_PATH / nofile=262144
tools/bazel build --config=fast --jobs=6 --local_ram_resources=9216 \
  --defconfig_fragment=//common:bakasu_susfs.fragment \
  //common:kernel_aarch64_dist > /opt/data/android/tokay/logs/build-1.log 2>&1
```

结果：

```
INFO: Elapsed time: 355.098s, Critical Path: 351.48s
INFO: 167 processes: 150 internal, 2 local, 15 processwrapper-sandbox.
INFO: Build completed successfully, 167 total actions
```

内存全程安全：构建中 `MemAvailable` 最低 7.3G、`SwapFree` 恒为 5.1G，未触发降 `--jobs` 的条件。

dist 落盘（`kernel_aarch64_dist` 是 dist runner 脚本，必须 `bazel run` 才会真正拷贝）：

```bash
tools/bazel run --config=fast --jobs=6 --local_ram_resources=9216 \
  --defconfig_fragment=//common:bakasu_susfs.fragment \
  //common:kernel_aarch64_dist -- --dist_dir=/opt/data/android/tokay/out/kernel_aarch64/dist
# [dist] INFO: Copying to /opt/data/android/tokay/out/kernel_aarch64/dist
# EXIT=0
```

---

## 4. banner grep 结果（集成生效的直接证据）

`grep -n "SUSFS_VERSION\|using SuSFS\|selinux_hide\|BakaSU" logs/build-1.log`（日志第 21-45 行，Bazel 打印的 `INFO: From Building kernel ...`）：

```
INFO: From Building kernel (bakasu_susfs.fragment;lto=fast;trim) @//common:kernel_aarch64:
-- BakaSU version code: 35261
-- BakaSU version name: v4.2.0-rc3-5d6d1843
-- Supported Managers: KernelSU Official, KOWSU, BakaSU
-- KERNEL_VERSION: 6.1
-- KERNEL_TYPE: GKI 2.0
-- BakaSU: using SuSFS Inline hook
-- You are using SUSFS, if you face any issues, please MAKE SURE you are using LATEST SUSFS KERNEL SIDE before submit issue to BakaSU.
-- BakaSU/susfs_inline: ksu_handle_setresuid found
-- BakaSU/susfs_inline: ksu_handle_execveat found
-- BakaSU/susfs_inline: ksu_handle_faccessat found
-- BakaSU/susfs_inline: ksu_handle_sys_read found
-- BakaSU/susfs_inline: ksu_handle_stat found
-- BakaSU/susfs_inline: ksu_handle_vfs_fstat found
-- BakaSU/susfs_inline: ksu_handle_sys_reboot found
-- BakaSU/susfs_inline: ksu_handle_input_handle_event found
-- BakaSU/susfs_feature_check: selinux_hide manual hook found

-- SUSFS_VERSION: v2.4.0
-- BakaSU/compat: current_sid found
...
```

三项必须的证据全部命中：

| 期望 banner | 实际 |
|---|---|
| `SUSFS_VERSION: v2.4.0` | ✅ 第 40 行 |
| `using SuSFS Inline hook` | ✅ 第 27 行 |
| `selinux_hide manual hook found` | ✅ 第 38 行 |

补充：`KERNEL_TYPE: GKI 2.0` 说明没走 tracepoint 分支的 `$(error TP hooks are incompatible with Non-GKI)` 保护；8 个 `susfs_inline: ... found` 说明 inline hook 落点检查全过；`-- __flush_dcache_area not found` 是正常的 6.1 兼容探测（6.1 无该符号），非错误。

---

## 5. 每轮错误摘要与修复

### 轮 0 — `HermeticToolsRsync` 失败：`realpath: missing operand`（环境问题，非内核）

```
ERROR: build/kernel/BUILD.bazel:31:15: Creating wrapper for rsync: @//build/kernel:hermetic-tools failed
realpath: missing operand
```

归因（sandbox/工具链类）：`build/kernel/kleaf/hermetic_tools.bzl:181` 的 wrapper 生成动作用 `realpath $(hermetic-tools/which rsync)` 定位宿主机 rsync。该动作的执行环境是被完全清空的（`--verbose_failures` 显示 `exec env -`，连 `PATH` 都没有），而容器里 rsync 只在 `/opt/data/tools/debroot/usr/bin`，不在 Bazel 的默认 `/bin:/usr/bin`。
试过但**无效**的方案（记录以免重走）：`--action_env=PATH=...`、`--host_action_env=PATH=...`、`--noexperimental_strict_action_env`、`--noincompatible_strict_action_env` —— 动作 env 始终是空的，因为该 action 不继承 shell env。

修复：
1. `build/kernel/kleaf/hermetic_tools.bzl`（备份 `patches/hermetic_tools.bzl.orig`）把 `export PATH` 改为显式 PATH：
   ```python
   export PATH=/opt/data/tools/bin:/opt/data/tools/debroot/usr/bin:/usr/local/bin:/usr/bin:/bin:$PATH
   ```
2. 轮 1 暴露第二个坑：`/opt/data/tools/debroot/usr/bin/rsync` 动态链 `libpopt.so.0`，空 env 下 `cannot open shared object file`。新增宿主 shim `/opt/data/tools/bin/rsync`（`chmod +x`），内部设 `LD_LIBRARY_PATH=$DEBROOT/usr/lib/x86_64-linux-gnu:...` 后 `exec` 真 rsync；`realpath` 会固化 shim 路径，因此后续所有 dist/rsync 动作都走它。

> 这是**容器环境适配**，不涉及内核源码；换到有 `/usr/bin/rsync` 的机器应把这 1 行回滚。

### 轮 1 — fragment 回验失败：actual/expected 不匹配（Kleaf 语义）

```
ERROR: @//common:kernel_aarch64_config:
    CONFIG_KSU_SUSFS: actual 'CONFIG_KSU_SUSFS=y', expected '#     -> else ifdef CONFIG_KSU_SUSFS.
CONFIG_KSU_SUSFS=y
    CONFIG_KSU_TRACEPOINT_HOOK: actual '', expected '# Kbuild order is: ifdef CONFIG_KSU_TRACEPOINT_HOOK ...'
    CONFIG_KSU_MANUAL_HOOK: actual '', expected ...
    Are they declared in Kconfig?
```

归因（Kleaf fragment 校验，非依赖缺失）：`config_utils.bzl:74` 用 `grep -w -e "$config" $fragment` 取"期望值"，而我的注释里写了符号名（`else ifdef CONFIG_KSU_SUSFS`、`ifdef CONFIG_KSU_TRACEPOINT_HOOK`），grep 命中多行，期望值变成整段注释文本。
注意 `actual` 一侧证明配置本身是对的：`CONFIG_KSU_SUSFS=y` 已生效、两个 choice 成员已是 `is not set`。

修复：重写 fragment 注释，**注释中不出现任何 `CONFIG_*` 原始符号名**（用 "tracepoint hook / manual hook" 之类的自然语言描述）。
修复后 `KernelConfig` 动作 25.9s 成功，`.config` 全部取值符合预期。

### 轮 2 — 全量构建：**无错误**

`//common:kernel_aarch64_dist` 第一次跑就成功（355s / 167 actions）。SUSFS 与 BakaSU 的内核侧接口零偏差：`fs/susfs.c` 与 40 个 `drivers/kernelsu/*.o` 全部编译通过，inline hook 落点检查 8/8 命中。

### 轮 3 — dist 拷贝：成功

`bazel run ..._dist -- --dist_dir=...` → `EXIT=0`，96 个文件。

---

## 6. 验证

### 6.1 KMI 未被绕过

dist 内含 `kmi_symbol_list_strict_mode_checked` 与 `kernel_aarch64_kmi_symbol_list_violations_checked`，两者均为**空文件**（内容 0 字节），说明 `kmi_symbol_list_strict_mode=True` + `kmi_symbol_list_add_only=True` 的检查跑过且零违规。**全程未使用** `--nokmi_symbol_list_strict_mode` 或任何关闭检查的开关。

### 6.2 符号与对象

```
$ grep -c susfs System.map                 -> 104
$ grep -c ksu_   System.map                -> 290
$ grep -E " T susfs_(init|add_sus_path|set_uname|enable_log|show_variant)$" System.map
ffffffc0083f6e6c T susfs_add_sus_path
ffffffc0083f9a88 T susfs_set_uname
ffffffc0083f9fa4 T susfs_enable_log
ffffffc0083fc73c T susfs_show_variant
ffffffc0083fd0a4 T susfs_init
$ ls out/cache/acb3ac36/common/fs/susfs.o           -> 982K
$ find out/cache/acb3ac36 -path "*drivers/kernelsu*" -name "*.o" | wc -l  -> 40
```

`out/cache/last_build -> acb3ac36` 是本次真实构建目录。

### 6.3 镜像格式

```
Image.lz4  头 4 字节 = 02 21 4c 18   (LZ4 legacy frame，Android boot-lz4 正确格式)
Image.gz   头 3 字节 = 1f 8b 08      (gzip)
Image      offset 0x38 = "ARMd"      (ARM64 Image magic 0x644d5241)
gki-info.txt: kernel_release=6.1.176-android14-11-maybe-dirty
toolchain_version: r487747c
```

---

## 7. 改动文件清单

| 文件 | 类型 | 说明 |
|---|---|---|
| `common/bakasu_susfs.fragment` | 新增 | defconfig fragment（13 行有效配置 + 注释） |
| `common/BUILD.bazel` | 修改 | `package()` 后加 `exports_files(["bakasu_susfs.fragment"])`，+4 行 |
| `common/android/abi_gki_protected_exports_aarch64` | 清空 | 359 行 → 0 字节（SUSFS README 要求）；原文件备份 `patches/abi_gki_protected_exports_aarch64.orig` |
| `build/kernel/kleaf/hermetic_tools.bzl` | 修改 | rsync wrapper 生成动作补显式 PATH（容器适配，+2 行） |
| `/opt/data/tools/bin/rsync` | 新增 | 宿主 rsync shim（设 LD_LIBRARY_PATH 解决 libpopt） |

未改动：`KernelSU/` 源码、`common/arch/arm64/configs/gki_defconfig`、`fs/susfs.c`、`include/linux/susfs*.h`（Phase 3 已定型）。未执行 `repo sync`。

---

## 8. 产物路径

dist 目录：`/opt/data/android/tokay/out/kernel_aarch64/dist`（96 文件 / 743 MB）

| 产物 | 路径 | 大小 |
|---|---|---|
| 内核镜像（lz4） | `/opt/data/android/tokay/out/kernel_aarch64/dist/Image.lz4` | 17 MB |
| 内核镜像（裸） | `.../dist/Image` | 35 MB |
| 内核镜像（gz） | `.../dist/Image.gz` | 14 MB |
| vmlinux（带符号） | `.../dist/vmlinux` | 338 MB |
| System.map | `.../dist/System.map` | 4.5 MB |
| boot.img | `.../dist/boot.img` | 64 MB |
| boot-lz4.img | `.../dist/boot-lz4.img` | 51 MB |
| boot-gz.img / boot-img.tar.gz | `.../dist/` | — |
| 模块（60 个 .ko） | `/opt/data/android/tokay/out/kernel_aarch64/dist/*.ko` | — |
| 模块打包 | `.../dist/kernel_aarch64_modules`、`modules_staging_dir.tar.gz`、`unstripped_modules.tar.gz` | — |
| system_dlkm 镜像 | `.../dist/system_dlkm.img`（+ `.erofs.img` / `.flatten.*`） | — |
| Module.symvers | `.../dist/kernel_aarch64_Module.symvers`、`vmlinux.symvers` | — |
| headers | `.../dist/kernel-headers.tar.gz`、`kernel-uapi-headers.tar.gz` | — |
| 构建日志 | `/opt/data/android/tokay/logs/build-1.log`（168 行） | — |

`kernel_aarch64_dist` 是 runner 脚本，不带 `--dist_dir` 时的默认目标是 `<workspace>/out/kernel_aarch64/dist`。

---

## 9. 遗留与注意

1. **Bazel 动作环境为空**是这台容器的固有特性（`exec env -`），`--action_env` / `--host_action_env` 对它无效。若后续还有别的动作依赖宿主工具，同样会以 "missing operand / command not found" 形式失败 —— 先怀疑动作 env，而不是内核代码。
2. `build/kernel/kleaf/hermetic_tools.bzl` 里的 PATH 补丁是本地环境适配，**不属于产品改动**，提交前应回滚或改造成可配置项。
3. `CONFIG_KSU_SUSFS_PRIORITY_UID_FILTER` 在 BakaSU 侧不存在，管理器若需要该能力得先上游补 Kconfig，本阶段无法开启。
4. `abi_gki_protected_exports_aarch64` 现在是空文件；将来跑 `kernel_aarch64_abi_update` 之类的 ABI target 会得到空保护列表，需要时从 `patches/*.orig` 恢复。
5. 增量重编直接用同一条命令 + 同一个 output_base（`out/bazel/output_user_root`），不要 clean。
