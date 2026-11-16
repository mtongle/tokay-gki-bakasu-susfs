# Phase 1 上游调研报告 — BakaSU × susfs4ksu on Pixel 9 (tokay) / GKI android14-6.1

> 只读调研，未打补丁、未编译、未 repo init/sync。所有克隆均为 `--depth=1 --single-branch`。
> 调研时间：2026-11-16（CST）。本地路径统一以 `research/` 指代 `/opt/data/workspace/tokay-kernel/research/`。

---

## 0. 调研基线（可复现）

| 仓库 | 分支 | HEAD | 本地路径 | 体积 |
|---|---|---|---|---|
| Baka-SU/BakaSU | `main` | `5d6d1843c8937f5ff2a145dc89a0cf46030ae6f8` (2026-11-15 22:02 +0800) `kernel: fix return type and header_install path of preinit (#659)` | `research/BakaSU` | 35M |
| Baka-SU/BakaSU | `auto-hook` | `9d159b417210fdca88b4dbf4381fc1c618c102ba` (2026-08-07 20:36 +0800) `refactor arm64` | `research/BakaSU-auto-hook` | 30M |
| simonpunk/susfs4ksu (GitLab) | `gki-android14-6.1` | `f76b81f2a6bf98e4029cc0c823c054edbec29803` (2026-11-15 03:34 +0800) `kernel: selinux_hide: use dedicated handlers for inode_setxattr` | `research/susfs4ksu` | 988K |
| kernel/build (AOSP) | `main-kernel-build-2023` | `ccc31488bfbfe383b42a5538de70cebfddad693e` (2026-11-03) | `research/kernel-build` | 3.5M |
| kernel/common@android14-6.1 关键文件 | `android14-6.1` | 逐文件从 gitiles 拉取 | `research/kdry/` | ~1.5M |

GitLab 主仓可直连，**无需**回退到 GitHub 镜像 `ShirkNeko/susfs4ksu`。已额外核对 `gki-android14-6.1-dev`（HEAD `756abbf`）：其 `50_` 补丁与本分支**文件清单完全一致、总行数同为 3438**，关键 hunk（`fs/read_write.c` 的 `ksu_handle_sys_read` 调用）逐字相同；md5 不同仅因非关键行差异。本报告一律以 `gki-android14-6.1`（`f76b81f`）为准。

---

## A. 结论摘要

1. **BakaSU 侧补丁：一个都不要打。** BakaSU `main` 已经把 susfs 的 KSU 侧集成吞进去了（`kernel/core/init.c:123` 调 `susfs_init()`，`kernel/supercall/dispatch.c:1108` 起有完整 `ksu_handle_susfs_cmd` 分发，`kernel/feature/sucompat.h:43` 有 `#elif defined(CONFIG_KSU_SUSFS)` 分支）。`susfs4ksu/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch` 对 BakaSU 树 dry-run **28/32 文件 `patch does not apply`**。
2. **内核侧补丁：必须打，且目前对 android14-6.1 是干净可打的。** `50_add_susfs_in_gki-android14-6.1.patch` 的 27 个目标文件逐个对 `kernel/common@android14-6.1` HEAD 做 `git apply --check`，**27/27 全部通过**（`fs/exec.c` 有 +7 行偏移，其余零 offset）。
3. **Hook 模式：选 `CONFIG_KSU_SUSFS`（SUSFS Inline Hook），不要选 tracepoint，也不要选 manual hook。** 三者是 Kconfig `choice` 的互斥项（`kernel/Kconfig:80-113`），默认 `KSU_TRACEPOINT_HOOK`，但 SUSFS 场景必须切到 `KSU_SUSFS`。BakaSU 已彻底移除 kprobes 选项。
4. **CONFIG 组合：** `CONFIG_KSU=y` + `CONFIG_KSU_SUSFS=y`（+ 按需 `KSU_SUSFS_SUS_PATH/SUS_MOUNT/SUS_KSTAT/SPOOF_UNAME/OPEN_REDIRECT/SUS_MAP`）+ `CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y`。**不要**同时开 `KSU_TRACEPOINT_HOOK` / `KSU_MANUAL_HOOK`。
5. **版本锁定：** BakaSU 用 `main`（最新 tag 仅到 `v4.2.0-rc3`，GitHub 无 Release 记录）；SUSFS 用 `gki-android14-6.1` @ `f76b81f`（`SUSFS_VERSION "v2.4.0"`）。BakaSU 的 `Kbuild` 会硬校验 `$(srctree)/fs/susfs.c` 是否存在，缺了直接 `$(error)`。
6. **SUSFS 2.x 不再需要 `CONFIG_KPROBES` / `KRETPROBES` / `HAVE_SYSCALL_TRACEPOINTS`**（README:15），全部改成对 `fs/*.c`、`security/selinux/*` 的源码内联 hook。
7. **KMI 风险低但机制必须懂：** `50_` 补丁**不新增任何 `EXPORT_SYMBOL`**，所以 `kmi_symbol_list_strict_mode=True`（`//common:kernel_aarch64` 默认）不会因符号增删而红。真正要处理的是 `check_defconfig`（`build.config.gki` 的 `POST_DEFCONFIG_CMDS`）和 `trim_nonlisted_kmi=True`。
8. **Pixel 9 目标：** 官方表确认 tokay 走 `android-gs-caimito-6.1-android16` 设备分支 + GKI `android14-6.1`，Android 16 时代**仍是 6.1**。纯 GKI 路线用 manifest 分支 `common-android14-6.1`（对应 `kernel/common` 的 `android14-6.1`）。
9. **最大未知：** 设备分支 `android-gs-caimito-6.1-android16` 的 `kernel/common` 与纯 GKI `android14-6.1` 有差异，`50_` 补丁未在该分支上 dry-run 过；以及 Pixel 9 当前固件具体对应哪个 GKI release（SPL 对齐）。

---

## B. 证据表

### B1. BakaSU 版本、分支、Release

| # | 结论 | 证据位置 | 原文片段 |
|---|---|---|---|
| 1.1 | **没有 GitHub Release**，只有 tag | `GET https://api.github.com/repos/Baka-SU/BakaSU/releases/latest` | `{"message": "Not Found", "status": "404"}` |
| 1.2 | 最新 tag 是 `v4.2.0-rc3`（RC，非正式版） | `GET .../tags?per_page=20` | `"name": "v4.2.0-rc3", "sha": "239e1e88..."`（其后为 v4.2.0-rc2/rc1、v4.1.0、v4.0.0…） |
| 1.3 | `main` 才是开发主线，且**领先于**最新 tag | 本地 `research/BakaSU` `git log -1` | `5d6d1843... 2026-11-15 22:02:44 +0800 kernel: fix return type and header_install path of preinit (#659)`；仓库 `pushed_at: 2026-11-16T03:33:50Z` |
| 1.4 | 分支全集（无 susfs 专分支） | `git ls-remote --heads origin` | `auto-hook, main, patch-2, sync-up, weblate-main, renovate/{cargo-group-in-ksud,cargo-group-in-ksuinit,gradle-9.x,maven-group-in-manager}` |
| 1.5 | `auto-hook` 是**更旧的独立重构分支**，不是"自动插桩 manual hook 的助手" | `research/BakaSU-auto-hook` `git log -1` + 与 main 的 `diff -rq` | HEAD `9d159b4 2026-08-07 refactor arm64`（比 main 早 3 个月）；新增 `hook/auto_hook.c`、`hook/inline_hook.c`、`hook/arm64/inline_hook.c`、`hook/{arm32,x86_64}/inline_hook_entry.S`；**删除** `preinit/`、`infra/btf_parser.c`、`selinux/inode.c`、`feature/module_blacklist.*`、`feature/shell_su_adb_only.*`、`hook/riscv64/` |
| 1.6 | `auto-hook` 还删掉了 `KSU_MANUAL_HOOK_AUTO_*` 整段 Kconfig | `diff research/BakaSU/kernel/Kconfig research/BakaSU-auto-hook/kernel/Kconfig` | `115,159d114` 删除 `menu "KernelSU - Manual Hook Auto hook"` … `config KSU_MANUAL_HOOK_AUTO_INPUT_HOOK` |
| 1.7 | `auto-hook` 的 hook choice 与 main 完全一致（仍是 tracepoint 默认） | `BakaSU-auto-hook/kernel/Kconfig:80-113` | `choice / prompt "KernelSU Hooking Method" / default KSU_TRACEPOINT_HOOK` |
| 1.8 | **GKI 6.1 用 `main`** | `kernel/setup.sh:62-66` | `if [ -z "${1-}" ]; then git checkout main` |
| 1.9 | 无 kprobes 选项 | `grep -n 'KPROBE' research/BakaSU/kernel/Kconfig` | 无任何匹配 |
| 1.10 | 官方 Hook 模式定义（三种，SUSFS 是其中之一） | `research/BakaSU/docs/README.md:37-40` | `## Hook Mode` / `- Tracepoint Syscall Redirect hook` **The default hook mode** … only support GKI2 kernel with arm64-v8a or x86_64 ABI` / `- Manual Hook` … `- SUSFS Inline Hook An hook from SuSFS …, like Manual Hook, but provide from SUSFS project, not this project` |
| 1.11 | 默认 hook 由 Kconfig 决定 | `research/BakaSU/kernel/Kconfig:80-113` | `choice / prompt "KernelSU Hooking Method" / default KSU_TRACEPOINT_HOOK` … `config KSU_SUSFS / bool "SUSFS Inline Hook" / depends on THREAD_INFO_IN_TASK && 64BIT` |
| 1.12 | SUSFS 的 Kconfig 描述明确甩锅内核侧 | `research/BakaSU/kernel/Kconfig:104-111` | `bool "SUSFS Inline Hook"` … `This KSU driver support it for 4.3+ in KSU side, But the kernel side susfs compatibility MUST completed by yourself.` |

### B2. BakaSU 官方集成指引（bakasu.org）

`https://bakasu.org/guide/` 返回 **404**；站点 `llms.txt` 列出的页面里**没有** GKI/Kleaf 专页，也没有 Pixel/设备专页。最相关的是 `/guide/build`（=`/guide/build.md`，103 行）。

| # | 结论 | 证据位置 | 原文片段 |
|---|---|---|---|
| 2.1 | 官方对 GKI 只给 Kleaf/Bazel 一条路，无 Pixel 说明 | `https://bakasu.org/guide/build.md:36-48` | `LTO=thin BUILD_CONFIG=common/build.config.gki.aarch64 build/build.sh` / `Starting from Android 13, the kernel is built by bazel:` / `tools/bazel build --config=fast //common:kernel_aarch64_dist` |
| 2.2 | 注入方式=官方脚本，落在 `$GKI_ROOT/KernelSU` | `build.md:52-56` + `research/BakaSU/kernel/setup.sh:52-55` | `curl -LSs ".../main/kernel/setup.sh" \| bash` / `git clone https://github.com/Baka-SU/BakaSU KernelSU` |
| 2.3 | 官方明说"二选一"：manual hook **或** SUSFS | `build.md:58` | `Then,choose **one of the following methods** to integrate BakaSU into your kernel:` |
| 2.4 | manual hook 的 CONFIG | `build.md:70-71` | `+CONFIG_KSU=y` / `+CONFIG_KSU_MANUAL_HOOK=y` |
| 2.5 | **SUSFS 的 CONFIG 只要两个** | `build.md:97-98` | `+CONFIG_KSU=y` / `+CONFIG_KSU_SUSFS=y` |
| 2.6 | **官方指引里 SUSFS 只提"打内核侧补丁"，完全没提 KSU 侧补丁** | `build.md:103` | `Then, in the SUSFS repository, **choose the branch that matches your kernel version** and apply the **kernel-side patches** as instructed; after making the changes, rebuild the kernel.` |
| 2.7 | 官方警告：SUSFS 代码来自 susfs 仓库，编译/启动问题先看 susfs 更新日志 | `build.md:85-87` | `BakaSU's SUSFS part of the kernel code is **updated from the SUSFS repository**. If you encounter build errors or boot problems, please CHECK the update log of the SUSFS repository FIRST.` |
| 2.8 | manual hook 页面存在但只管 manual，不是 SUSFS 的施工图 | `https://bakasu.org/guide/manual-integrate.html` HTTP 200 | 页面内全部 `#ifdef CONFIG_KSU_MANUAL_HOOK` |

### B3. susfs4ksu 版本与补丁清单

| # | 结论 | 证据位置 | 原文片段 |
|---|---|---|---|
| 3.1 | 版本 **v2.4.0** | `research/susfs4ksu/kernel_patches/include/linux/susfs.h:12` | `#define SUSFS_VERSION "v2.4.0"` |
| 3.2 | 变体判断靠 kernel 版本 | 同上 `:13-17` | `#if LINUX_VERSION_CODE < KERNEL_VERSION(5,0,0)` / `#define SUSFS_VARIANT "NON-GKI"` / `#else` / `#define SUSFS_VARIANT "GKI"` |
| 3.3 | `kernel_patches/` 一共 5 个文件 | `find kernel_patches -type f` | `50_add_susfs_in_gki-android14-6.1.patch`(3438 行) / `KernelSU/10_enable_susfs_for_ksu.patch`(4411 行) / `fs/susfs.c`(2560 行) / `include/linux/susfs.h`(261 行) / `include/linux/susfs_def.h`(172 行) |
| 3.4 | `50_` 补丁规模：**27 个文件 / 132 个 hunk** | `grep -c '^diff --git'` = 27，`grep -c '^@@'` = 132 | — |
| 3.5 | **不新增任何 `EXPORT_SYMBOL`** | `grep -n 'EXPORT_SYMBOL' 50_*.patch` → 2 处，均为**上下文行**（无 `+` 前缀） | `274: EXPORT_SYMBOL(lookup_one_qstr_excl);`（fs/namei.c 上下文）、`2326:@@ -693,6 +693,9 @@ EXPORT_SYMBOL_GPL(kernel_power_off);`（hunk 头） |
| 3.6 | SUSFS 2.x 与 kprobes 彻底解耦 | `README.md:15` | `Since v2.0.0, SUSFS does not rely on kernel features like KPROBES, KRETPROBES and HAVE_SYSCALL_TRACEPOINTS, which means it will patch all the sucompat code in KernelSU, fs/exec.c, fs/open.c, and fs/stat.c.` |
| 3.7 | 禁止再叠 manual hook | `README.md:16` | `Do NOT apply custom manual hooks for sucompat unless you implement your own one instead of the susfs one.` |
| 3.8 | 官方要求删 `abi_gki_protected_exports_*` | `README.md:30` | `For gki kernel android14 or above, if you are building from google artifacts, it is necessary to delete the file $KERNEL_REPO/common/android/abi_gki_protected_exports_aarch64 and ..._x86_64, otherwise some modules like WiFi will not work.` |
| 3.9 | `fs/Makefile` 唯一新增编译单元 | `50_*.patch:83-88` | `+obj-$(CONFIG_KSU_SUSFS) += susfs.o` |
| 3.10 | `10_` 补丁是**针对 KernelSU 树**（路径前缀 `kernel/`，在 `KernelSU/` 目录下 `patch -p1`） | `README.md:22,27` | `cp ./kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch $KERNEL_REPO/KernelSU/` / `cd $KERNEL_REPO/KernelSU` then `patch -p1 < 10_enable_susfs_for_ksu.patch` |
| 3.11 | `10_` 规模：**32 个文件 / 106 hunk** | `grep -c` | 覆盖 `kernel/Kbuild`、`kernel/Kconfig`、`kernel/core/init.c`、`kernel/feature/{adb_root,selinux_hide,sucompat,kernel_umount}.c`、`kernel/supercall/{dispatch,supercall}.c`、`kernel/policy/*`、`kernel/preinit/*`、`kernel/runtime/ksud_integration.c`、`kernel/sulog/*`、`kernel/selinux/*` 等 |

### B4. 冲突面（Q3 核心）

| # | 结论 | 证据位置 | 原文片段 |
|---|---|---|---|
| 4.1 | BakaSU **已在源码里调用 `susfs_*` 接口**，共 39 个不同符号 | `grep -rhoP '\bsusfs_[a-z0-9_]+' research/BakaSU/kernel/ \| sort -u` = 39 条 | 含 `susfs_init` `susfs_is_current_proc_no_su` `susfs_set_current_proc_umounted` `susfs_add_sus_path` `susfs_show_version` `susfs_extra_works` 等 |
| 4.2 | init 阶段就调 `susfs_init()` | `research/BakaSU/kernel/core/init.c:13,123` | `#include <linux/susfs.h>` / `susfs_init();` |
| 4.3 | 完整 SUSFS 命令分发已实现 | `research/BakaSU/kernel/supercall/dispatch.c:1108-1185` | `int ksu_handle_susfs_cmd(unsigned int cmd, void __user **arg)` … `susfs_add_sus_path(arg)` … `susfs_show_version(arg)` |
| 4.4 | sucompat 在 SUSFS 下走 susfs 的 TIF 标记 | `research/BakaSU/kernel/feature/sucompat.h:43-51` | `#elif defined(CONFIG_KSU_SUSFS) // susfs` / `#define ksu_is_current_proc_unprivillege susfs_is_current_proc_no_su` / `#define ksu_set_current_proc_unprivillege susfs_set_current_proc_no_su` |
| 4.5 | **BakaSU 专门为 50_ 补丁写了 shim**（注释直说是给 susfs 用的） | `research/BakaSU/kernel/feature/sucompat.c:496-513` | `#ifdef CONFIG_KSU_SUSFS` / `int ksu_handle_execveat_sucompat(...)` / `// workaround susfs codes as below` / `int ksu_handle_post_execveat_sucompat(...)` |
| 4.6 | **`preinit.h` 在 `CONFIG_KSU_SUSFS` 下提供的签名与 50_ 补丁的 extern 逐字一致** | `research/BakaSU/kernel/preinit/preinit.h:18-21` vs `50_*.patch:120-123` | patch: `extern int ksu_preinit_handle_post_execveat(int *fd, struct filename **filename_ptr, void *argv_user, void *envp_user, int *flags, int *retval, int *preinit_fd);` ←→ BakaSU: `#elif defined(CONFIG_KSU_SUSFS)` + 同名同参声明 |
| 4.7 | 10_ 补丁 dry-run：**28/32 文件直接失败** | `git apply --check -p1 .../10_enable_susfs_for_ksu.patch`（cwd=`research/BakaSU`） | `error: patch failed: kernel/Kbuild:5` / `error: kernel/Kbuild: patch does not apply` / `error: patch failed: kernel/Kconfig:2` / `error: kernel/Kconfig: patch does not apply` / `error: patch failed: kernel/core/init.c:6` / `error: kernel/core/init.c: patch does not apply` …（仅 `kernel/Makefile` 报 `Hunk #1 succeeded at 38 (offset 2 lines)`，另 `kernel/policy/feature.h`、`kernel/selinux/selinux.c`、`kernel/supercall/supercall.h` 单行 hunk 偶然命中） |
| 4.8 | 50_ 补丁是**对着 BakaSU/SukiSU 谱系写的**（引用 `ksu_handle_execveat_sucompat`、`KSU_NO_PREINIT`、`ksu_setup_preinit_file`），不是纯 upstream KernelSU | `50_*.patch:113-124,136-140,157-165` | `extern int ksu_handle_execveat_sucompat(...)` / `#ifndef KSU_NO_PREINIT` / `extern int ksu_setup_preinit_file(struct filename **filename_ptr, struct user_arg_ptr *argv_user);` |
| 4.9 | BakaSU 的 `Kbuild` 是硬门禁：开了 `CONFIG_KSU_SUSFS` 却没 `fs/susfs.c` 就 `$(error)` | `research/BakaSU/kernel/Kbuild:189-201` | `else ifdef CONFIG_KSU_SUSFS` / `$(info -- $(REPO_NAME): using SuSFS Inline hook)` / `include $(KSU_SRC)/tools/inline_hook_check.mk` / `ifeq ($(shell test -e $(srctree)/fs/susfs.c; echo $$?),0)` / `$(error You should integrate susfs in your kernel.)` |
| 4.10 | BakaSU 会把 `SUSFS_VERSION` 打出来（不校验下限） | `research/BakaSU/kernel/Kbuild:193-196` | `$(eval SUSFS_VERSION=$(shell cat $(srctree)/include/linux/susfs.h \| grep -E '^#define SUSFS_VERSION' ...))` / `$(info -- SUSFS_VERSION: $(SUSFS_VERSION))` |
| 4.11 | **唯一签名偏差：`ksu_handle_sys_read`** | `50_*.patch:1701` vs `research/BakaSU/kernel/runtime/ksud_integration.c:764` | patch: `extern __attribute__((cold)) void ksu_handle_sys_read(unsigned int fd);` 且只传 `fd`；BakaSU: `int ksu_handle_sys_read(unsigned int fd, char __user **buf_ptr, size_t *count_ptr)`。**不同 TU 各自声明 → 编译期不报错**，链接期解析到 3 参版本，多余两参未使用（函数体只调 `ksu_handle_sys_read_fd(fd)`），故实际可跑但属隐患 |
| 4.12 | BakaSU 的兼容探测是 **grep 级**，抓不到签名不匹配 | `research/BakaSU/kernel/tools/inline_hook_check.mk:1-8` | `ifeq ($$(shell grep -q "$(1)" $(2); echo $$$$?),0)` / `$$(error You should integrate $$(REPO_NAME) in your kernel. $(3))` |
| 4.13 | 兼容探测还会主动拒绝"旧 hook" | `research/BakaSU/kernel/tools/inline_hook_check.mk:29-37` | 检查 `ksu_vfs_read_hook`(fs/read_write.c)、`ksu_input_hook`(drivers/input/input.c)、`ksu_execveat_hook`(fs/exec.c)、`ksu_init_rc_hook`(fs/read_write.c、fs/stat.c) 必须**不存在** |

### B5. Kleaf / GKI-KMI 约束（android14-6.1）

| # | 结论 | 证据位置 | 原文片段 |
|---|---|---|---|
| 5.1 | 无任意 `--defconfig_fragment` 限制，**支持**该 flag | `kleaf/docs/kernel_config.md:97-107` | `You may specify a **single** target in the --defconfig_fragment flag … **NOTE**: If multiple --defconfig_fragment are supplied, only the last one takes effect.` |
| 5.2 | fragment 会被逐个回验（不匹配即失败） | `kernel_config.md:70-72` + `kleaf/impl/config_utils.bzl:55-90` | `After .config is built, .config is checked against each defconfig fragment to ensure that all defconfig fragments are properly applied.` / `"${config}: actual '${actual_value}', expected '${defconfig_value}' from ${defconfig_path}."` |
| 5.3 | `gki_defconfig` 的完整性校验就是 `check_defconfig` | `kernel/common@android14-6.1/build.config.gki`（全文 2 行） | `DEFCONFIG=gki_defconfig` / `POST_DEFCONFIG_CMDS="check_defconfig"` |
| 5.4 | `check_defconfig` 实现：`savedefconfig` 后与树内 defconfig `diff -u` | `kernel/build/_setup_env.sh:283-301` | `# verifies that defconfig matches the DEFCONFIG` / `make ${TOOL_ARGS} O=${OUT_DIR} savedefconfig` / `diff -u ${KERNEL_DIR}/arch/${ARCH}/configs/${DEFCONFIG} ${OUT_DIR}/defconfig >&2` / `echo ERROR: savedefconfig does not match ${KERNEL_DIR}/arch/${ARCH}/configs/${DEFCONFIG}` / `return ${RES}` |
| 5.5 | **能直接改 `gki_defconfig`，但必须过 `check_defconfig`；官方测试的做法是把它关掉** | `kleaf/tests/integration_test/integration_test.py:811-816` | `# Writing to defconfig directly requires us to disable check_defconfig, because the ordering is not correct.` / `f.write("POST_DEFCONFIG_CMDS=true\n")` |
| 5.6 | `trim_nonlisted_kmi` 是 `TRIM_NONLISTED_KMI` 的 Bazel 等价物 | `kleaf/impl/kernel_build.bzl:363-365` | `trim_nonlisted_kmi: If True, trim symbols not listed in kmi_symbol_list and additional_kmi_symbol_lists. This is the Bazel equivalent of TRIM_NONLISTED_KMI.` |
| 5.7 | `//common:kernel_aarch64` 上 `trim_nonlisted_kmi` **默认 True** | `kleaf/common_kernels.bzl:91,158-163` | `aarch64_trim_and_check = bool(aarch64_kmi_symbol_list) or len(aarch64_additional_kmi_symbol_lists) > 0` / `"trim_nonlisted_kmi": aarch64_trim_and_check, "kmi_symbol_list_strict_mode": aarch64_trim_and_check` |
| 5.8 | `kmi_symbol_list_strict_mode` **默认 True**（仅 release target） | `kernel/common@android14-6.1/BUILD.bazel:142-152` | `"kernel_aarch64": { "kmi_symbol_list_strict_mode": True, ... "kmi_symbol_list": "android/abi_gki_aarch64", "kmi_symbol_list_add_only": True, "additional_kmi_symbol_lists": [":aarch64_additional_kmi_symbol_lists"], "protected_exports_list": "android/abi_gki_protected_exports_aarch64", "protected_modules_list": "android/gki_aarch64_protected_modules", ... }`；`kernel_aarch64_debug` 为 `False`（:164-165） |
| 5.9 | 语义 = 符号表与构建出的 KMI 必须 1:1 | `kernel_build.bzl:374-377` | `kmi_symbol_list_strict_mode: If True, add a build-time check between [kmi_symbol_list] + additional_kmi_symbol_lists and the KMI resulting from the build, to ensure they match 1-1.` |
| 5.10 | **官方绕过开关：`--nokmi_symbol_list_strict_mode`** | `kernel_build.bzl:2025-2031` | `if not ctx.attr._use_kmi_symbol_list_strict_mode[BuildSettingInfo].value:` / `print("\nWARNING: {this_label}: Attribute kmi_symbol_list_strict_mode IGNORED because --nokmi_symbol_list_strict_mode is set!")` |
| 5.11 | ABI 定义文件就是 `abi_gki_aarch64.stg` | `kleaf/docs/abi.md:11-13` | `This compares the current ABI (abi_definition_stg of //common:kernel_aarch64, which is common/android/abi_gki_aarch64.stg) and the freshly-generated ABI` |
| 5.12 | 更新符号表/ABI 的官方 target | `abi.md:19-26,52-78` | `//common:kernel_aarch64_abi_update_symbol_list`（更新 `common/android/abi_gki_aarch64`）、`//common:kernel_aarch64_abi_update`（更新 `.stg`） |
| 5.13 | `protected_exports` 的定义（删它的副作用） | `kleaf/impl/common_providers.bzl:211` | `src_protected_exports_list: Source file for protected symbols which are restricted from being exported by unsigned modules` |
| 5.14 | `--config=fast` **只影响 LTO 与 sandbox，不关 KMI 检查** | `kleaf/docs/fast.md:22-27` | `This config implies: --lto=thin … --config=local` |
| 5.15 | `-` **50_ 补丁对 android14-6.1 HEAD 全部可打** | `research/kdry` 逐文件 `git apply --check -p1` | 27/27 `OK`；`fs/exec.c` 报 `Hunk #2 succeeded at 1914 (offset 7 lines)` / `Hunk #3 ... 1938 (offset 7)` / `Hunk #4 ... 2040 (offset 7)`，其余 0 offset |

### B6. Pixel 9 (tokay) 目标分支

| # | 结论 | 证据位置 | 原文片段 |
|---|---|---|---|
| 6.1 | **tokay 属 caimito 家族，走 `android-gs-caimito-6.1-android16`，GKI = `android14-6.1`** | `https://source.android.com/docs/setup/build/building-pixel-kernels`（GKI supported Pixel kernel branches 表） | `\| Pixel 9 (tokay) Pixel 9 Pro (caiman) Pixel 9 Pro XL (komodo) \| android-gs-caimito-6.1-android16 \| android14-6.1 \|` |
| 6.2 | **Android 16 时代仍是 6.1**（同一张表全部 android16） | 同上 | 表内 Pixel 6…Pixel 9a 全为 `android-gs-*-6.1-android16` + `android14-6.1` |
| 6.3 | 设备 manifest 分支确实存在 | `https://android.googlesource.com/kernel/manifest/+refs` | `refs/heads/android-gs-caimito-6.1-android16`（另有 `-beta`、`-dp`、`android15-qpr1/qpr2-beta`、`android14-qpr3-d1`） |
| 6.4 | 该 manifest 里 `kernel/common` 与 `kernel/build` **都跟随 default revision**（即设备分支，不是裸 GKI 分支） | `.../manifest/+/refs/heads/android-gs-caimito-6.1-android16/default.xml:4-9,126` | `<default revision="android-gs-caimito-6.1-android16" .../>` / `<project path="aosp" name="kernel/common" groups="partner">` / `<project path="build/kernel" name="kernel/build" groups="partner">` |
| 6.5 | manifest 内含 Tensor G4 相关 project | 同上 `:59-66` | `<project path="private/devices/google/zumapro" ...>` / `<project path="private/devices/google/caimito" ...>` + `linkfile dest="build_caimito.sh"` |
| 6.6 | 构建入口 = `build_caimito.sh` / `build_DEVICE.sh` | `building-pixel-kernels`（Compile the kernel 节） | `you can run the build_DEVICE.sh script found at the KERNEL_REPO_ROOT … "caimito" which means Pixel 9 (tokay), Pixel 9 Pro (caiman), and Pixel 9 Pro XL (komodo)` |
| 6.7 | 改核心内核需 `BUILD_AOSP_KERNEL=1`（否则用预编译 GKI） | 同上 | `By default on the production kernel branches, the build_DEVICE.sh scripts use the prebuilt GKI kernel … set the environment variable BUILD_AOSP_KERNEL=1 to build the kernel from the local sources instead.` |
| 6.8 | 纯净 GKI 路线的 manifest 分支名 = `common-android14-6.1` | `kernel/manifest@common-android14-6.1/default.xml:6,14` | `<superproject name="kernel/superproject" remote="aosp" revision="common-android14-6.1" />` / `<project path="common" name="kernel/common" revision="android14-6.1" />` |
| 6.9 | 日期化分支最新到 `2026-09` | `kernel/manifest/+refs` | `common-android14-6.1-2025-12`、`-2026-03`、`-2026-06`、`-2026-09`（另有大量 `deprecated/common-android14-6.1-20xx-xx`） |
| 6.10 | 构建产物与尺寸约束 | `kernel/common@android14-6.1/build.config.gki.aarch64:5-17` | `FILES="... arch/arm64/boot/Image.lz4 arch/arm64/boot/Image.gz"` / `BUILD_SYSTEM_DLKM=1` / `BUILD_GKI_ARTIFACTS=1` / `BUILD_GKI_BOOT_IMG_SIZE=67108864` |
| 6.11 | 产物目录 | `building-pixel-kernels`（DIST_DIR 表） | `v5.15 and later \| out/DEVICE/dist` |
| 6.12 | tokay 需刷的分区 | 同上（Kernel Partitions 表） | `Pixel 9 (tokay) … \| boot dtbo vendor_kernel_boot vendor_dlkm (dynamic partition) system_dlkm (dynamic partition)` |

---

## C. 内核侧施工图（Phase 3 施工清单）

来源：`research/susfs4ksu/kernel_patches/50_add_susfs_in_gki-android14-6.1.patch`，按 hunk 头解析出的「文件 → 函数 → 插入调用」。
**全部 hunk 已在 `kernel/common@android14-6.1` HEAD 上 dry-run 通过（27/27 文件）。**

### C0. 三个新文件（直接拷贝，不改动）

| 目标路径（`$KERNEL_REPO/common/`） | 来源 | 行数 |
|---|---|---|
| `fs/susfs.c` | `kernel_patches/fs/susfs.c` | 2560 |
| `include/linux/susfs.h` | `kernel_patches/include/linux/susfs.h` | 261 |
| `include/linux/susfs_def.h` | `kernel_patches/include/linux/susfs_def.h` | 172 |

`fs/Makefile` 由补丁追加 `obj-$(CONFIG_KSU_SUSFS) += susfs.o`（patch:87）。

### C1. 主表

| 内核文件 | 函数 | 插入的调用 |
|---|---|---|
| `block/ioprio.c` | `ioprio_check_cap()` | `susfs_is_priority_uid_filtered()` |
| | `SYSCALL_DEFINE3(ioprio_set,…)` | `susfs_is_priority_uid_filtered()` |
| | `SYSCALL_DEFINE2(ioprio_get,…)` | `susfs_is_priority_uid_filtered()` |
| `drivers/input/input.c` | `input_event_dispose()` | `ksu_handle_input_handle_event()` |
| | `input_handle_event()` | `ksu_handle_input_handle_event()` |
| `fs/Makefile` | — | `obj-$(CONFIG_KSU_SUSFS) += susfs.o` |
| `fs/exec.c` | `bprm_execve()`（4 hunk 之一） | `ksu_handle_execveat` / `ksu_handle_execveat_sucompat` / `ksu_handle_post_execveat_sucompat` / `ksu_setup_preinit_file` / `ksu_preinit_handle_post_execveat` |
| | `do_execveat_common()` | `susfs_is_current_proc_no_su` / `ksu_handle_execveat*` / `ksu_setup_preinit_file` / `ksu_preinit_handle_post_execveat` |
| `fs/namei.c` | 文件级 | `susfs_is_inode_sus_path`、`susfs_open_redirect_spoof_do_sys_openat`（extern 声明） |
| | `lookup_dcache()` / `lookup_one_qstr_excl()` / `lookup_fast()` / `__lookup_slow()` / `link_path_walk()` / `lookup_open()` | `susfs_is_inode_sus_path()` |
| | `do_tmpfile()` / `path_openat()` | `susfs_open_redirect_spoof_do_sys_openat()` |
| | `readlink_copy()` / `vfs_readlink()` | `susfs_open_redirect_spoof_vfs_readlink()` |
| `fs/namespace.c` | `mnt_free_id()` / `mnt_get_count()` / `__lookup_mnt()` / `vfs_create_mount()` / `clone_mnt()` / `init_fs_namespace_sysctls()` | `susfs_is_current_ksu_domain` / `susfs_is_current_proc_umounted` / `susfs_alloc_{unshare,non_unshare}_ksu_vfsmnt` / `susfs_get_non_sus_mnt_id_from_mnt` / `susfs_get_non_sus_vfsmnt_from_vfsmnt` |
| `fs/notify/fdinfo.c` | `inotify_fdinfo()` | `susfs_is_current_app_uid` / `susfs_is_inode_sus_kstat` / `susfs_sus_kstat_spoof_inotify_fdinfo` / `susfs_is_current_proc_umounted` |
| `fs/open.c` | `access_override_creds()` / `do_faccessat()` | `ksu_handle_faccessat()` + `susfs_is_current_proc_no_su()` |
| `fs/proc/base.c` | `proc_pid_get_link()` / `do_proc_readlink()` | `susfs_open_redirect_spoof_do_proc_readlink()` |
| `fs/proc/bootconfig.c` | `boot_config_proc_show()` | `susfs_spoof_cmdline_or_bootconfig()`（`SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG`） |
| `fs/proc/fd.c` | `seq_show()` | `susfs_get_non_sus_mnt_id_from_mnt` / `susfs_is_inode_sus_kstat` / `susfs_sus_kstat_spoof_proc_fd_seq_show` |
| `fs/proc/task_mmu.c` | `show_vma_header_prefix()` / `show_map_vma()` | `susfs_sus_kstat_spoof_show_map_vma` / `susfs_open_redirect_spoof_show_map_vma_srcu`（配合 `susfs_srcu_open_redirect` 的 srcu_read_lock/unlock） |
| `fs/proc_namespace.c` | `show_vfsstat()` / `mounts_release()` | `susfs_show_vfsmnt` / `susfs_show_mountinfo` / `susfs_show_vfsstat` / `susfs_is_current_ksu_domain` |
| `fs/read_write.c` | `SYSCALL_DEFINE3(read,…)`（hunk 落在 `ksys_read` 上方） | `ksu_handle_sys_read(fd)` ← **签名隐患，见 D-1** |
| `fs/readdir.c` | `fillonedir` / `filldir` / `filldir64` / `compat_fillonedir` / `compat_filldir` | `susfs_is_inode_sus_path()` |
| `fs/stat.c` | `vfs_getattr_nosec()` | `susfs_is_current_app_uid` / `susfs_is_inode_sus_kstat` / `susfs_sus_kstat_spoof_generic_fillattr` |
| | `vfs_fstat()` | `ksu_handle_vfs_fstat()` |
| | `vfs_statx()` | `susfs_is_current_proc_no_su` / `ksu_handle_stat` |
| `fs/statfs.c` | `statfs_by_dentry()` / `vfs_statfs()` | `susfs_statfs_by_dentry` / `susfs_sus_kstat_spoof_vfs_statfs` / `susfs_get_non_sus_vfsmnt_from_vfsmnt` |
| `fs/super.c` | `emergency_thaw_all()` / `get_anon_bdev()` | `susfs_is_current_ksu_domain()` |
| `kernel/kallsyms.c` | `s_show()` | `susfs_starts_with()`（配合 `HIDE_KSU_SUSFS_SYMBOLS`） |
| `kernel/reboot.c` | `SYSCALL_DEFINE4(reboot,…)` | `ksu_handle_sys_reboot()` |
| `kernel/sys.c` | `set_one_prio()` / `SYSCALL_DEFINE3(setpriority)` / `SYSCALL_DEFINE2(getpriority)` | `susfs_is_priority_uid_filtered()` |
| | `SYSCALL_DEFINE1(setuid)` / `__sys_setresuid()` | `ksu_handle_setresuid()` |
| | `override_release()` | `susfs_spoof_uname()` |
| `mm/memory.c` | `__access_remote_vm()` | `SUSFS_IS_INODE_SUS_MAP(file_inode(vma->vm_file))` 宏判定后 `break`（`SUSFS_SUS_MAP`；不是函数调用） |
| `security/selinux/avc.c` | `avc_audit_post_callback()` | `susfs_is_avc_log_spoofing_enabled` 静态键 + `susfs_ksu_sid` / `susfs_priv_app_sid`（把 ksu 域伪装成 `u:r:priv_app:s0:c512,c768`） |
| `security/selinux/hooks.c` | `selinux_inode_post_setxattr()` | `susfs_selinux_inode_setxattr` / `susfs_selinux_inode_post_setxattr` / `susfs_security_context_to_sid[_force]` |
| | `selinux_setprocattr()` | `susfs_selinux_setprocattr()` |
| | `selinux_hooks[]` 初始化表 | 条件替换为 susfs 版本 |
| `security/selinux/selinuxfs.c` | `sel_write_context()` / `sel_write_access()` | `susfs_sel_write_context` / `susfs_sel_write_access` / `susfs_security_context_str_to_sid` / `susfs_security_compute_av_user` |
| `security/selinux/ss/services.c` | `selinux_policy_commit()` / `security_set_bools()` | `susfs_is_current_ksu_domain()` |
| | `security_read_state_kernel()` | `susfs_string_to_context_struct` / `susfs_security_context_to_sid*` 系列 / `susfs_spoof_avd_allowed_rcu` |
| `security/selinux/status.c` | `selinux_status_update_setenforce()` / `selinux_status_update_policyload()` | `susfs_is_current_ksu_domain()` |

### C2. 需要在 BakaSU 侧确认存在的入口（已全部确认存在，见 B4）

`ksu_handle_execveat`、`ksu_handle_execveat_sucompat`、`ksu_handle_post_execveat_sucompat`、`ksu_handle_faccessat`、`ksu_handle_sys_read`、`ksu_handle_stat`、`ksu_handle_vfs_fstat`、`ksu_handle_sys_reboot`、`ksu_handle_setresuid`、`ksu_handle_input_handle_event`、`ksu_setup_preinit_file`、`ksu_preinit_handle_post_execveat`、`ksu_su_compat_enabled`、`ksu_is_init_rc_hook_enabled`、`ksu_is_input_hook_enabled`、`__ksu_is_allow_uid_for_current`、`ksu_selinux_hide_running`、`ksu_selinux_hide_enabled`、`susfs_ksu_sid`。

---

## D. 风险与未知项清单

| ID | 风险/未知 | 等级 | 依据与应对 |
|---|---|---|---|
| **D-1** | `ksu_handle_sys_read` 参数个数不一致：patch 传 1 参，BakaSU 定义 3 参 | 中 | B4-4.11。编译不报错（分 TU 声明）、运行时多余两参未被解引用，但属 UB。**应对：Phase 3 打完补丁后，把 `fs/read_write.c` 那行改成 `ksu_handle_sys_read(fd, &buf, &count)`，或保留原样并在验证清单里标注。** 需在真机上验证 initrc 挂钩（音量键 + init rc 注入）是否正常。 |
| **D-2** | BakaSU 的 hook 自检是 `grep` 级，无法发现签名/语义不匹配 | 中 | B4-4.12。应对：把 C2 的入口清单做成 Phase 3 的自查脚本（编译前 grep + 编译后 nm）。 |
| **D-3** | `50_` 补丁只对**纯 GKI `android14-6.1`** 验证过 | 高 | B5-5.15。若走设备分支 `android-gs-caimito-6.1-android16`（其 `kernel/common` 是合并了 zumapro/caimito 的分支），offset 与上下文可能不同。**Phase 2 必须在选定分支上重做 27/27 文件 dry-run。** |
| **D-4** | Pixel 9 当前固件对应的 GKI release / SPL 未知 | 高 | 报告只确认了「tokay → android14-6.1」。具体 `common-android14-6.1-2026-XX` 与设备 `ro.build.version.security_patch` 的对齐，需 Phase 2 用 `uname -r` + GKI release builds 页 + `build_gki_boot_images()` 的 `spl_date` 核对。**若 SPL 不匹配，boot.img 可能无法启动。** |
| **D-5** | `check_defconfig` 会在改 `gki_defconfig` 时炸 | 中 | B5-5.3~5.5。**应对：不要改 `arch/arm64/configs/gki_defconfig`，用 `--defconfig_fragment` 或 `kernel_build.defconfig_fragments`。** |
| **D-6** | `trim_nonlisted_kmi=True` + `kmi_symbol_list_strict_mode=True` 双开 | 低（当前） | B5-5.6~5.10。SUSFS **不新增 EXPORT_SYMBOL**，符号表不变，故不会红。但若将来给 susfs 加导出，会被 trim **静默裁掉**且 strict 检查仍通过 → 表现为"模块 undefined symbol"。应对：任何新导出必须同步进 `android/abi_gki_aarch64` 并跑 `_abi_update_symbol_list`。 |
| **D-7** | 必须删 `android/abi_gki_protected_exports_aarch64` | 中 | B3-3.8 / B5-5.13。不删则 WiFi 等 vendor 模块可能加载失败。副作用：失去"unsigned modules 不得再导出受保护符号"的护栏（对自编译内核可接受）。 |
| **D-8** | `KSU_SUSFS` 与 tracepoint/manual 互斥，误开组合会撞 | 低 | B1-1.11（`choice` 块）。Kbuild:202-206 对未识别组合直接 `$(error Unsupported hook method)`。 |
| **D-9** | BakaSU `main` 无正式 Release，只有 rc tag，接口可能随时变 | 中 | B1-1.1/1.2。应对：Phase 3 固定 commit `5d6d1843` 写入构建脚本，不用浮动 `main`。 |
| **D-10** | `auto-hook` 分支曾被误认为"自动插桩"，实为旧的重构实验分支（缺 preinit） | 低 | B1-1.5/1.6。**不要用 auto-hook。** |
| **D-11** | GKI-only 路线下 `vendor_dlkm` 仍是 stock，KMI 必须严格匹配 | 中 | tokay 需刷 boot + vendor_kernel_boot + vendor_dlkm + system_dlkm（B6-6.12）。只换 boot 而 KMI 不符会导致 vendor 模块加载失败。应对：优先走设备 manifest 路线（Route B）或严格对齐 SPL。 |
| **D-12** | 未验证：`fs/susfs.c` 与 BakaSU `kernel/selinux/inode.c` 的交互 | 低 | BakaSU main 有 `kernel/selinux/inode.c`，`susfs_compat.mk` 用 `ksu_selinux_hide_running` 探测是否启用 `KSU_COMPAT_HAS_SUSFS_FEATURE_SELINUX_HIDE`。Phase 3 编译日志里应能看到 `susfs_feature_check: selinux_hide manual hook found`。 |

---

## E. Phase 2 / Phase 3 命令草案（未执行）

### E1. Phase 2-A：纯 GKI 路线（推荐先做，风险最低）

```bash
# 1) 选分支：优先与设备 SPL 对齐的日期化 release 分支
#    先用 `adb shell uname -r` / `getprop ro.build.version.security_patch` 确认
export KBRANCH=common-android14-6.1-2026-09      # 备选：common-android14-6.1（滚动）
mkdir -p ~/tokay-gki && cd ~/tokay-gki
repo init -u https://android.googlesource.com/kernel/manifest -b "$KBRANCH"
repo sync -c --no-tags -j"$(nproc)"

# 2) 注入 BakaSU（官方脚本，固定在 $PWD/KernelSU）
curl -LSs "https://raw.githubusercontent.com/Baka-SU/BakaSU/main/kernel/setup.sh" | bash -s 5d6d1843c8937f5ff2a145dc89a0cf46030ae6f8

# 3) 内核侧 SUSFS（只打 50_ 与三个新文件，绝不碰 KernelSU/ 目录）
cd ~/tokay-gki/common
cp ~/tokay-kernel/research/susfs4ksu/kernel_patches/50_add_susfs_in_gki-android14-6.1.patch .
cp ~/tokay-kernel/research/susfs4ksu/kernel_patches/fs/susfs.c            fs/
cp ~/tokay-kernel/research/susfs4ksu/kernel_patches/include/linux/susfs.h     include/linux/
cp ~/tokay-kernel/research/susfs4ksu/kernel_patches/include/linux/susfs_def.h include/linux/
git apply --check -v 50_add_susfs_in_gki-android14-6.1.patch   # 先 dry-run，全绿再 apply
git apply -v 50_add_susfs_in_gki-android14-6.1.patch

# 4) KMI 护栏按需放开（susfs 不新增导出，理论上不需要；仅在报错时启用）
rm -f android/abi_gki_protected_exports_aarch64   # susfs README 要求

# 5) defconfig 片段（不改 gki_defconfig）
cat > ~/tokay-gki/bakasu_susfs_defconfig <<'EOF'
CONFIG_KSU=y
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
EOF

# 6) 构建（fragment 需要在 BUILD.bazel 里 exports_files，或直接放在 //common 已有 filegroup）
tools/bazel build --config=fast \
  --defconfig_fragment=//common:bakasu_susfs_defconfig \
  //common:kernel_aarch64_dist
# 若 fragment 机制不顺，退化为：tools/bazel run //common:kernel_aarch64_config -- savedefconfig
```

### E2. Phase 2-B：设备内核路线（Route B，换 vendor_dlkm 一起时用）

```bash
export KBRANCH=android-gs-caimito-6.1-android16
repo init -u https://android.googlesource.com/kernel/manifest -b "$KBRANCH"
repo sync -c --no-tags -j"$(nproc)"
# 此路线 kernel/common 在 aosp/，需确认 patch 相对路径后再 dry-run
BUILD_AOSP_KERNEL=1 ./build_caimito.sh          # 产物: out/caimito/dist
```

### E3. Phase 3：打补丁前的强制校验

```bash
cd ~/tokay-gki/common
# (a) 27 个文件逐个 dry-run（复用本报告的 kdry 方法）
python3 - <<'PY'
import re,subprocess
p="50_add_susfs_in_gki-android14-6.1.patch"
t=open(p).read()
for blk in re.split(r'(?m)^(?=diff --git )',t):
    if not blk.startswith("diff --git"): continue
    f=re.match(r'diff --git a/(\S+) b/',blk).group(1)
    open("/tmp/one.patch","w").write(blk)
    r=subprocess.run(["git","apply","--check","-p1","/tmp/one.patch"],capture_output=True,text=True)
    print(("OK  " if r.returncode==0 else "FAIL"),f,(r.stderr.strip().splitlines() or [""])[0])
PY

# (b) KSU 侧：确认 10_ 补丁应当失败（失败=已内置，符合预期）
cd ../KernelSU && git apply --check -p1 \
  ~/tokay-kernel/research/susfs4ksu/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch \
  ; echo "expected: fails (already integrated)"

# (c) 入口符号存在性（对应 inline_hook_check.mk 的 grep 级检查）
cd ../common
for s in ksu_handle_execveat ksu_handle_faccessat ksu_handle_sys_read \
         ksu_handle_stat ksu_handle_vfs_fstat ksu_handle_sys_reboot \
         ksu_handle_setresuid ksu_handle_input_handle_event; do
  echo "--- $s"; grep -rn "\b$s\b" fs/ kernel/ drivers/input/ 2>/dev/null | head -3
done
grep -q ksu_selinux_hide_running security/selinux/hooks.c && echo "selinux_hide hook: FOUND"
grep -q ksu_install_su_fd        fs/exec.c                  && echo "install_su_fd direct call: FOUND"
```

### E4. Phase 3：编译后验证点

```bash
# 1) Kbuild 应打印
#    -- BakaSU: using SuSFS Inline hook
#    -- SUSFS_VERSION: v2.4.0
#    -- <repo>/susfs_feature_check: selinux_hide manual hook found
#    -- <repo>/susfs_inline: ksu_handle_* found   (逐个 hook)
# 2) 符号存在但未导出（trim 未误裁）
nm -n out/.../vmlinux | grep -E ' (susfs_init|susfs_add_sus_path)$'
# 3) KMI 未被改动
grep -c '^' android/abi_gki_aarch64   # 与打补丁前一致
# 4) 真机
adb shell su -c 'ksu_susfs show version'   # 期望 v2.4.0
adb shell su -c 'ksu_susfs show enabled_features'
```

---

## F. 一句话路线结论

**只在 `main` 分支的 BakaSU 上打 `susfs4ksu/gki-android14-6.1` 的「内核侧」(`50_` + `fs/susfs.c` + 两个头文件)，KSU 侧 `10_` 一律不打；hook 模式取 `CONFIG_KSU_SUSFS`（inline hook），禁用 tracepoint 与 manual；defconfig 走 fragment 不改 `gki_defconfig`；删 `abi_gki_protected_exports_aarch64`；Pixel 9 对齐 `android14-6.1`（设备分支 `android-gs-caimito-6.1-android16`）。**
