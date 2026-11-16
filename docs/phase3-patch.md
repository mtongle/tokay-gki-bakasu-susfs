# Phase 3：SUSFS 内核侧打补丁与集成报告

- 目标树：`/opt/data/android/tokay/src/common`（GKI `android14-6.1`，`common-android14-6.1-2026-09`，Linux 6.1.176）
- 基线：`47ef95e4`（tag `baseline-pre-baka-su`）
- BakaSU：`/opt/data/android/tokay/src/KernelSU` @ `5d6d1843`
- SUSFS 版本：`#define SUSFS_VERSION "v2.4.0"`（`include/linux/susfs.h:12`）
- **结果：27/27 文件 apply 成功，0 reject，0 `.orig`，已提交为本地 commit `08cf5886`，打 tag `integration-v1`，工作区干净。未编译。**

---

## 1. 执行命令与顺序

顺序严格为「先放 3 个新文件 → 再打补丁」，因为补丁 hunk 需要 `linux/susfs.h` / `susfs_def.h` 存在才能在 Phase 4 通过编译期检查（且 `fs/Makefile` 的 `obj-$(CONFIG_KSU_SUSFS) += susfs.o` 需要 `fs/susfs.c` 落地）。

```bash
. /opt/data/tools/bin/android-env.sh
cd /opt/data/android/tokay/src/common

# 步骤 1：前置确认
ls fs/susfs.c            # -> No such file or directory（符合预期，未提前存在）

# 步骤 2：先放新文件
P=/opt/data/workspace/tokay-kernel/patches
cp -v "$P/fs_susfs.c"   fs/susfs.c
cp -v "$P/susfs.h"      include/linux/susfs.h
cp -v "$P/susfs_def.h"  include/linux/susfs_def.h

# 步骤 3：打补丁
git apply --verbose "$P/50_add_susfs_in_gki-android14-6.1.patch"
```

### 1.1 新文件落地与哈希校验

与 `patches/sha256sums.txt` 完全一致：

| 目标路径 | sha256 | 大小 |
|---|---|---|
| `fs/susfs.c` | `2a8bb10bca2ad5134cd65bf02ef56863795949b1d9cbed603c380b58d9bc61bf` | 86623 B |
| `include/linux/susfs.h` | `763a502a37c3ffa3807ba2cab46af31807b8bd87cccb86d12e552d0532a96573` | 8744 B |
| `include/linux/susfs_def.h` | `e8a1cee4b41bcdce43998ae337e60fca9888b2f8bea47074fe3b3377220794d8` | 5982 B |

---

## 2. `git apply` 实际输出（27/27 通过）

退出码 **0**。原文：

```
Checking patch block/ioprio.c...
Checking patch drivers/input/input.c...
Checking patch fs/Makefile...
Checking patch fs/exec.c...
Hunk #2 succeeded at 1914 (offset 7 lines).
Hunk #3 succeeded at 1938 (offset 7 lines).
Hunk #4 succeeded at 2040 (offset 7 lines).
Checking patch fs/namei.c...
Checking patch fs/namespace.c...
Checking patch fs/notify/fdinfo.c...
Checking patch fs/open.c...
Checking patch fs/proc/base.c...
Checking patch fs/proc/bootconfig.c...
Checking patch fs/proc/fd.c...
Checking patch fs/proc/task_mmu.c...
Checking patch fs/proc_namespace.c...
Checking patch fs/read_write.c...
Checking patch fs/readdir.c...
Checking patch fs/stat.c...
Checking patch fs/statfs.c...
Checking patch fs/super.c...
Checking patch kernel/kallsyms.c...
Checking patch kernel/reboot.c...
Checking patch kernel/sys.c...
Checking patch mm/memory.c...
Checking patch security/selinux/avc.c...
Checking patch security/selinux/hooks.c...
Checking patch security/selinux/selinuxfs.c...
Checking patch security/selinux/ss/services.c...
Checking patch security/selinux/status.c...
Applied patch block/ioprio.c cleanly.
Applied patch drivers/input/input.c cleanly.
Applied patch fs/Makefile cleanly.
Applied patch fs/exec.c cleanly.
Applied patch fs/namei.c cleanly.
Applied patch fs/namespace.c cleanly.
Applied patch fs/notify/fdinfo.c cleanly.
Applied patch fs/open.c cleanly.
Applied patch fs/proc/base.c cleanly.
Applied patch fs/proc/bootconfig.c cleanly.
Applied patch fs/proc/fd.c cleanly.
Applied patch fs/proc/task_mmu.c cleanly.
Applied patch fs/proc_namespace.c cleanly.
Applied patch fs/read_write.c cleanly.
Applied patch fs/readdir.c cleanly.
Applied patch fs/stat.c cleanly.
Applied patch fs/statfs.c cleanly.
Applied patch fs/super.c cleanly.
Applied patch kernel/kallsyms.c cleanly.
Applied patch kernel/reboot.c cleanly.
Applied patch kernel/sys.c cleanly.
Applied patch mm/memory.c cleanly.
Applied patch security/selinux/avc.c cleanly.
Applied patch security/selinux/hooks.c cleanly.
Applied patch security/selinux/selinuxfs.c cleanly.
Applied patch security/selinux/ss/services.c cleanly.
Applied patch security/selinux/status.c cleanly.
```

唯一需要记录的是 `fs/exec.c` 的 Hunk #2/#3/#4 有 **+7 行偏移**（同时带 fuzz 0，因为 `git apply` 只做精确上下文匹配，偏移是允许的），其余 26 个文件 0 偏移、全 clean。

---

## 3. reject / orig 扫描（必须为空 → 确实为空）

```bash
$ find . -name '*.rej' -o -name '*.orig'
（无输出）
$ find . -name '*.rej' -o -name '*.orig' | wc -l
0
```

**0 个 `.rej`，0 个 `.orig`。**

---

## 4. `git status` / `git diff --stat`

打补丁后、提交前：

```bash
$ git status --short
 M block/ioprio.c
 M drivers/Kconfig
 M drivers/Makefile
 M drivers/input/input.c
 M fs/Makefile
 M fs/exec.c
 M fs/namei.c
 M fs/namespace.c
 M fs/notify/fdinfo.c
 M fs/open.c
 M fs/proc/base.c
 M fs/proc/bootconfig.c
 M fs/proc/fd.c
 M fs/proc/task_mmu.c
 M fs/proc_namespace.c
 M fs/read_write.c
 M fs/readdir.c
 M fs/stat.c
 M fs/statfs.c
 M fs/super.c
 M kernel/kallsyms.c
 M kernel/reboot.c
 M kernel/sys.c
 M mm/memory.c
 M security/selinux/avc.c
 M security/selinux/hooks.c
 M security/selinux/selinuxfs.c
 M security/selinux/ss/services.c
 M security/selinux/status.c
?? drivers/kernelsu
?? fs/susfs.c
?? include/linux/susfs.h
?? include/linux/susfs_def.h
```

33 条 = 29 个已跟踪修改（**27 个来自 50_ 补丁** + `drivers/Kconfig` + `drivers/Makefile`，后两者是 Phase 2 的 BakaSU 注入）+ 4 个未跟踪（3 个新文件 + `drivers/kernelsu` 软链）。

```bash
$ git diff --stat | tail -5
 security/selinux/hooks.c       | 329 ++++++++++++++++++++++++++++++++++++++++-
 security/selinux/selinuxfs.c   | 149 +++++++++++++++++++
 security/selinux/ss/services.c | 276 ++++++++++++++++++++++++++++++++++
 security/selinux/status.c      |  24 +++
 29 files changed, 2245 insertions(+), 5 deletions(-)
```

提交后（含新文件）相对基线的完整 diffstat：

```
 block/ioprio.c                 |   22 +-
 drivers/Kconfig                |    1 +
 drivers/Makefile               |    2 +
 drivers/input/input.c          |   10 +
 drivers/kernelsu               |    1 +
 fs/Makefile                    |    2 +
 fs/exec.c                      |   68 ++
 fs/namei.c                     |  238 ++++
 fs/namespace.c                 |  255 ++++
 fs/notify/fdinfo.c             |   78 ++
 fs/open.c                      |   28 +
 fs/proc/base.c                 |   24 +
 fs/proc/bootconfig.c           |   13 +
 fs/proc/fd.c                   |   71 ++
 fs/proc/task_mmu.c             |   70 ++
 fs/proc_namespace.c            |  178 ++++
 fs/read_write.c                |   10 +
 fs/readdir.c                   |  114 ++
 fs/stat.c                      |   83 +-
 fs/statfs.c                    |   81 ++
 fs/super.c                     |   24 +
 fs/susfs.c                     | 2560 ++++++++++++++++++++++++++++++++++++++++
 include/linux/susfs.h          |  261 ++++
 include/linux/susfs_def.h      |  172 +++
 kernel/kallsyms.c              |   31 +
 kernel/reboot.c                |   12 +
 kernel/sys.c                   |   28 +
 mm/memory.c                    |    8 +
 security/selinux/avc.c         |   21 +-
 security/selinux/hooks.c       |  329 +++++-
 security/selinux/selinuxfs.c   |  149 +++
 security/selinux/ss/services.c |  276 +++++
 security/selinux/status.c      |   24 +
 33 files changed, 5239 insertions(+), 5 deletions(-)
```

---

## 5. `ksu_handle_sys_read` 3 参签名修复

### 5.1 缺陷确认

- 补丁插入的调用是 1 参：`ksu_handle_sys_read(fd);`
- 补丁插入的 extern 声明是 `void`、1 参
- BakaSU 的真实定义是 3 参、返回 `int`：

```c
// KernelSU/kernel/runtime/ksud_integration.c:764
int ksu_handle_sys_read(unsigned int fd, char __user **buf_ptr, size_t *count_ptr)
{
#ifdef CONFIG_KSU_MANUAL_HOOK_AUTO_INITRC_HOOK
    return 0; // dummy hook here
#else
    ksu_handle_sys_read_fd(fd);
    return 0;
#endif
}
```

跨 TU 不报错（C 无强制原型匹配），但属未定义行为（UB），必须修正。

### 5.2 作用域判定：`buf` / `count` 在作用域内 ✅

插入点位于 `SYSCALL_DEFINE3` 宏体内。`SYSCALL_DEFINE3(read, unsigned int, fd, char __user *, buf, size_t, count)` 展开为 `__se_sys_read(unsigned int fd, char __user *buf, size_t count)`，三个形参在函数体内均为真实局部变量：

- `buf` 类型 `char __user *` → `&buf` 为 `char __user **`，与 `char __user **buf_ptr` 匹配
- `count` 类型 `size_t` → `&count` 为 `size_t *`，与 `size_t *count_ptr` 匹配

因此按 3 参调用，**未做任何硬编/权宜写法**。

### 5.3 修改前（`fs/read_write.c` 620–634）

```c
   620	
   621	#ifdef CONFIG_KSU_SUSFS
   622	extern struct static_key_true ksu_is_init_rc_hook_enabled;
   623	extern __attribute__((cold)) void ksu_handle_sys_read(unsigned int fd);
   624	#endif
   625	
   626	SYSCALL_DEFINE3(read, unsigned int, fd, char __user *, buf, size_t, count)
   627	{
   628	#ifdef CONFIG_KSU_SUSFS
   629		if (static_branch_unlikely(&ksu_is_init_rc_hook_enabled))
   630			ksu_handle_sys_read(fd);
   631	#endif
   632	
   633		return ksys_read(fd, buf, count);
   634	}
```

### 5.4 修改后（`fs/read_write.c` 620–634）

```c
   620	
   621	#ifdef CONFIG_KSU_SUSFS
   622	extern struct static_key_true ksu_is_init_rc_hook_enabled;
   623	extern __attribute__((cold)) int ksu_handle_sys_read(unsigned int fd, char __user **buf_ptr, size_t *count_ptr);
   624	#endif
   625	
   626	SYSCALL_DEFINE3(read, unsigned int, fd, char __user *, buf, size_t, count)
   627	{
   628	#ifdef CONFIG_KSU_SUSFS
   629		if (static_branch_unlikely(&ksu_is_init_rc_hook_enabled))
   630			ksu_handle_sys_read(fd, &buf, &count);
   631	#endif
   632	
   633		return ksys_read(fd, buf, count);
   634	}
```

改动仅两行（623、630）。`git show HEAD -- fs/read_write.c` 复核：

```
+extern __attribute__((cold)) int ksu_handle_sys_read(unsigned int fd, char __user **buf_ptr, size_t *count_ptr);
+		ksu_handle_sys_read(fd, &buf, &count);
```

全树已无 1 参残留（`grep -n ksu_handle_sys_read fs/read_write.c` 仅 623/630 两处，均为新签名）。

---

## 6. 完整性静态检查

### (a) `fs/Makefile` 挂载 ✅

```bash
$ grep -n 'susfs.o' fs/Makefile
20:obj-$(CONFIG_KSU_SUSFS) += susfs.o
```

上下文：

```
18-		kernel_read_file.o remap_range.o
19-
20:obj-$(CONFIG_KSU_SUSFS) += susfs.o
21-
22-ifeq ($(CONFIG_BLOCK),y)
```

### (b) `CONFIG_KSU_SUSFS_*` 全量比对 —— **发现 1 个缺失**

引用来源：`fs/susfs.c` + `include/linux/susfs.h` + `include/linux/susfs_def.h` + 补丁改动的其他 C 文件（共 11 个符号）；对照 `KernelSU/kernel/Kconfig`（BakaSU 定义 23 个 KSU* 符号）。

| # | 符号 | BakaSU Kconfig | 判定 |
|---|---|---|---|
| 1 | `CONFIG_KSU_SUSFS` | ✅ L104 | OK |
| 2 | `CONFIG_KSU_SUSFS_SUS_PATH` | ✅ L169 | OK |
| 3 | `CONFIG_KSU_SUSFS_SUS_MOUNT` | ✅ L180 | OK |
| 4 | `CONFIG_KSU_SUSFS_SUS_KSTAT` | ✅ L188 | OK |
| 5 | `CONFIG_KSU_SUSFS_SPOOF_UNAME` | ✅ L196 | OK |
| 6 | `CONFIG_KSU_SUSFS_ENABLE_LOG` | ✅ L204 | OK |
| 7 | `CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS` | ✅ L211 | OK |
| 8 | `CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG` | ✅ L219 | OK |
| 9 | `CONFIG_KSU_SUSFS_OPEN_REDIRECT` | ✅ L227 | OK |
| 10 | `CONFIG_KSU_SUSFS_SUS_MAP` | ✅ L236 | OK |
| 11 | **`CONFIG_KSU_SUSFS_PRIORITY_UID_FILTER`** | ❌ **未定义** | **缺失** |

**缺失清单（1 项）：`CONFIG_KSU_SUSFS_PRIORITY_UID_FILTER`**

影响判定（已逐处核实，**不是编译错误，是功能静默关闭**）：该符号的全部使用点都在 `#ifdef` 内，因此未定义时只是整块被裁掉，不会编译报错、也不会链接失败：

- `fs/susfs.c:1785`–`2209`：整段 priority uid filter 实现（bitmap、`susfs_set_priority_uid_filter`、`susfs_parse_priority_app_strings`、`susfs_is_priority_uid_filtered`）被裁掉
- `fs/susfs.c:2317`：`SHOW_ENABLED_FEATURES` 不再上报该特性
- `include/linux/susfs.h:165`（`struct st_susfs_priority_uid_filter`）、`:245`（两个函数原型）被裁掉
- 4 个 syscall 拦截点全部失效（均在 `#ifdef` 内，成对带 `#else` 回退分支）：
  - `block/ioprio.c:68` 声明 / `:118` `ioprio_set`
  - `kernel/sys.c:213` 声明 / `:262` `setpriority`、`:333` `getpriority`

结论：**该特性在本配置下永远不会开启**（`getpriority/setpriority/ioprio_get/ioprio_set` 对 uid 的隐藏能力不可用）。参考实现（`10_enable_susfs_for_ksu.patch:151-158`，**未应用**，仅作对照）中该 Kconfig 条目为 `bool` + `depends on KSU_SUSFS` + `default y`。是否补进 Kconfig 属 Phase 4 决策，本阶段按「不改 Kconfig/defconfig」的约束**未擅自添加**。

### (c) Hook 标记矩阵 —— 全部 PASS ✅

依据 BakaSU 真实检查逻辑 `KernelSU/kernel/tools/inline_hook_check.mk`（`check_ksu_hook` 用 `grep -q`，缺失即 `$(error)` 中断构建；`check_ksu_hook_incompatible` 用 `grep -wq`，命中即 `$(error)`）。**实测 0 缺失、0 误判。**

**C-1 必须不存在（旧 hook 标记，`grep -wq`，命中即构建失败）**

| 标记 | 文件 | `grep -c` | rc | 判定 |
|---|---|---|---|---|
| `ksu_vfs_read_hook` | `fs/read_write.c` | 0 | 1 | PASS（不存在） |
| `ksu_input_hook` | `drivers/input/input.c` | 0 | 1 | PASS（不存在） |
| `ksu_execveat_hook` | `fs/exec.c` | 0 | 1 | PASS（不存在） |
| `ksu_init_rc_hook` | `fs/read_write.c` | 0 | 1 | PASS（不存在） |
| `ksu_init_rc_hook` | `fs/stat.c` | 0 | 1 | PASS（不存在） |

**C-2 必须存在（`grep -q`，缺失即 `$(error)` 中断构建）**

| 标记 | 文件 | `grep -c` | rc | 判定 |
|---|---|---|---|---|
| `ksu_handle_setresuid` | `kernel/sys.c` | 2 | 0 | PASS |
| `ksu_handle_execveat` | `fs/exec.c` | 4 | 0 | PASS |
| `ksu_handle_faccessat` | `fs/open.c` | 2 | 0 | PASS |
| `ksu_handle_sys_read` | `fs/read_write.c` | 2 | 0 | PASS |
| `ksu_handle_stat` | `fs/stat.c` | 2 | 0 | PASS |
| `ksu_handle_vfs_fstat` | `fs/stat.c` | 2 | 0 | PASS |
| `ksu_handle_sys_reboot` | `kernel/reboot.c` | 2 | 0 | PASS |
| `ksu_handle_input_handle_event` | `drivers/input/input.c` | 2 | 0 | PASS |

**C-3 `check_ksu_manual_guard`（`CONFIG_KSU_MANUAL_HOOK` 残留，仅告警）**

`kernel/sys.c`、`fs/exec.c`、`fs/open.c`、`fs/read_write.c`、`fs/stat.c`、`kernel/reboot.c`、`drivers/input/input.c` 全部 `rc=1` → **7/7 clean，无手动钩子残留**。

**C-4 `susfs_compat.mk` 两个 compat 开关（决定 Phase 4 编译宏）**

`KernelSU/kernel/tools/susfs_compat.mk` 按文件内容探测并注入 `ccflags-y`：

| 探测标记 | 文件 | 实测 | 注入的宏 | 语义 |
|---|---|---|---|---|
| `ksu_selinux_hide_running` | `security/selinux/hooks.c` | **4 处存在** | `-DKSU_COMPAT_HAS_SUSFS_FEATURE_SELINUX_HIDE` **已启用** | 走手工钩子，selinux_hide 走真实特性而非回退实现 |
| `ksu_install_su_fd` | `fs/exec.c` | **0 处，不存在** | `-DKSU_COMPAT_HAS_SUSFS_INSTALL_SU_FD_DIRECT_CALL` **未启用** | 走 post-execve 钩子路径 |

这两项**都不是错误**，属预期分支：

- `ksu_selinux_hide_running` 存在 → 特性生效。符号定义在 `KernelSU/kernel/feature/selinux_hide.c:58`（`__maybe_static bool ksu_selinux_hide_running __read_mostly = false;`），补丁在 `hooks.c:3465/3474/6906` 三处消费。
- `ksu_install_su_fd` 缺失 → 走回退。该函数本身存在于 BakaSU（`KernelSU/kernel/supercall/supercall.c:94`），只是 `fs/exec.c` 里没有直接调用点；`sucompat.c:378` 的 `#ifndef KSU_COMPAT_HAS_SUSFS_INSTALL_SU_FD_DIRECT_CALL` 分支即为回退实现，而本树已具备 post-execve 钩子（`fs/exec.c:2050` `ksu_preinit_handle_post_execveat(...)`），故路径完整。

### (d) KMI 安全：补丁未新增任何导出符号 ✅

```bash
$ grep -c '^+.*EXPORT_SYMBOL' patches/50_add_susfs_in_gki-android14-6.1.patch
0
$ grep -c 'EXPORT_SYMBOL' fs/susfs.c
0
$ grep -c 'EXPORT_SYMBOL' include/linux/susfs.h include/linux/susfs_def.h
include/linux/susfs.h:0
include/linux/susfs_def.h:0
```

（`EXPORT_SYMBOL` 正则同时覆盖 `EXPORT_SYMBOL_GPL`。）新增符号全部为树内静态/非导出符号，不触碰 GKI KMI symbol list。

### (e) 附加检查：extern 符号可解析性（防 Phase 4 链接失败）

对补丁引入的全部 49 个 `extern ksu_*` / `extern susfs_*` / `extern __ksu_*` 声明逐个回溯定义（`DEFINE_STATIC_KEY_*`、`DEFINE_SRCU`、带函数体的定义）。**49/49 全部可解析，0 个悬空。**

关键几项：

| 符号 | 定义位置 | 形式 |
|---|---|---|
| `ksu_is_init_rc_hook_enabled` | `KernelSU/kernel/runtime/ksud_integration.c:108` | `DEFINE_STATIC_KEY_TRUE` |
| `ksu_is_input_hook_enabled` | `KernelSU/kernel/runtime/ksud_integration.c:109` | `DEFINE_STATIC_KEY_TRUE` |
| `ksu_su_compat_enabled` | `KernelSU/kernel/feature/sucompat.c:55` | `DEFINE_STATIC_KEY_TRUE` |
| `ksu_cred` | `KernelSU/kernel/core/init.c:90` | `struct cred *ksu_cred;` |
| `susfs_is_current_ksu_domain` | `KernelSU/kernel/selinux/selinux.c:311` | 实体函数 |
| `susfs_srcu_open_redirect` | `common/fs/susfs.c:1463` | `DEFINE_SRCU` |
| `susfs_get_non_sus_mnt_id_from_mnt` / `..._vfsmnt_from_vfsmnt` | `common/fs/namespace.c:4986/5001` | 补丁自带实体 |
| `susfs_ksu_sid` / `susfs_priv_app_sid` | `KernelSU/kernel/selinux/selinux.c:126/125` | 全局变量 |

### (f) 附加检查：`susfs_init()` 有调用点 ✅

```
common/fs/susfs.c:2552          void susfs_init(void) {   ← 定义
common/include/linux/susfs.h:259 void susfs_init(void);    ← 原型
KernelSU/kernel/core/init.c:123     susfs_init();         ← 调用（BakaSU 已内置）
```

`susfs_start_sdcard_monitor_fn()` 亦已在 `KernelSU/kernel/supercall/dispatch.c:185` 被调用。

### (g) 附加发现：10 个 `CMD_SUSFS_*` 已定义但 BakaSU 未派发

`susfs_def.h` 定义 25 个 `CMD_SUSFS_*`，`KernelSU/kernel/supercall/dispatch.c` 仅 `case` 15 个。以下 10 个**无用户态入口**（命令号已定义、内核无处理分支）：

```
CMD_SUSFS_ADD_SUS_MOUNT                CMD_SUSFS_SET_PRIORITY_UID_FILTER
CMD_SUSFS_ADD_TRY_UMOUNT               CMD_SUSFS_SET_SDCARD_ROOT_PATH
CMD_SUSFS_IS_SUS_SU_READY              CMD_SUSFS_SET_SUS_PATH_UID_FILTER
CMD_SUSFS_SET_ANDROID_DATA_ROOT_PATH   CMD_SUSFS_SHOW_SUS_SU_WORKING_MODE
CMD_SUSFS_SUS_SU                       CMD_SUSFS_UMOUNT_FOR_ZYGOTE_ISO_SERVICE
```

不阻断编译（全部为 `switch` 之外的独立命令号），但意味着这些能力无法经 BakaSU 的 supercall 通道下发；其中 `CMD_SUSFS_SET_PRIORITY_UID_FILTER` 与 (b) 的缺失配置相互印证。**记录供 Phase 4 评估，本阶段不改动。**

### (h) 附加发现（无害）：`fs/susfs.c:2552` 行尾反斜杠

```
void susfs_init(void) {\
	SUSFS_LOGI("Initializing susfs_extra_works\n");
```

`\` + 换行在翻译阶段 2 做行拼接，逻辑行变为 `void susfs_init(void) {	SUSFS_LOGI(...);`，仍是**合法 C**，可正常编译。属上游补丁的笔误级瑕疵，仅记录，不建议改动（改则偏离上游）。文件末无 `\r`，UTF-8/LF 正常，`wc -l` = 2560。

---

## 7. 归档

```bash
$ git diff > /opt/data/workspace/tokay-kernel/patches/integration.diff
$ wc -l integration.diff
3457        # 107442 字节（仅已跟踪文件的改动，不含 3 个新文件全文）
$ git status --porcelain | grep '^??' | sed 's/^?? //' > integration-files.txt
$ cat integration-files.txt
drivers/kernelsu
fs/susfs.c
include/linux/susfs.h
include/linux/susfs_def.h
```

产出文件：

| 文件 | 说明 |
|---|---|
| `/opt/data/workspace/tokay-kernel/patches/integration.diff` | 已跟踪文件的完整改动（3457 行 / 107442 B） |
| `/opt/data/workspace/tokay-kernel/patches/integration-files.txt` | 4 个未跟踪路径清单（3 新文件 + kernelsu 软链） |
| `/opt/data/workspace/tokay-kernel/phase3-patch.md` | 本报告 |

> 注：`integration.diff` 在 `git add` **之前**生成，因此只含 diff 内容；3 个新文件的全文已随 commit 一并入库，回滚用 `git checkout baseline-pre-baka-su` 或 `git reset --hard` 即可，不依赖该 diff。

---

## 8. 提交与 tag

```bash
$ git add -A
$ git diff --cached --stat | tail -3
 security/selinux/ss/services.c |  276 +++++
 security/selinux/status.c      |   24 +
 33 files changed, 5239 insertions(+), 5 deletions(-)

$ git -c user.email=hermes@local -c user.name=hermes commit -m \
    "Integrate BakaSU 5d6d1843 + SUSFS v2.4.0 (kernel-side only; sysread 3-arg fix)"

$ git rev-parse HEAD
08cf58862809f0d94df76bd0af6db5c1eb2c1e01

$ git log -1 --format='%H%n%s%n%an <%ae>%n%ad'
08cf58862809f0d94df76bd0af6db5c1eb2c1e01
Integrate BakaSU 5d6d1843 + SUSFS v2.4.0 (kernel-side only; sysread 3-arg fix)
hermes <hermes@local>
Mon Nov 16 12:32:07 2026 +0800

$ git tag -f integration-v1 && git tag -l
baseline-pre-baka-su
integration-v1

$ git describe --tags --exact-match HEAD
integration-v1

$ git status --short
（空 —— 工作区干净）
```

| 项 | 值 |
|---|---|
| commit | `08cf58862809f0d94df76bd0af6db5c1eb2c1e01` |
| 父提交 / 基线 | `47ef95e4`（tag `baseline-pre-baka-su`） |
| tag | `integration-v1`（exact-match 于 HEAD） |
| 变更规模 | 33 files, +5239 / −5 |
| 工作区 | clean |

回滚方式（Phase 4 迭代用）：

```bash
cd /opt/data/android/tokay/src/common
git reset --hard baseline-pre-baka-su   # 完全回到 Phase 2 之后 / 注入前的时间点
# 或只回滚 SUSFS 集成：
git reset --hard integration-v1         # 回到本次集成完成态
```

---

## 9. Phase 4 交接要点（未执行，仅供参考）

1. **必须显式 `CONFIG_KSU_SUSFS=y`**。BakaSU `kernel/Kconfig:79` 是 `choice "KernelSU Hooking Method"`，`default KSU_TRACEPOINT_HOOK`。三者互斥（`KSU_TRACEPOINT_HOOK` / `KSU_MANUAL_HOOK` / `KSU_SUSFS`）。若不显式选 `KSU_SUSFS`，默认落到 tracepoint，`Kbuild:188` 的 `else ifdef CONFIG_KSU_SUSFS` 分支不会进入，本次全部集成变成死代码。
2. **不要设 `CONFIG_KSU_MANUAL_HOOK`**。`Kbuild:186` 的 `else ifdef CONFIG_KSU_MANUAL_HOOK` 会短路后面的 SUSFS 分支，转而走 `manual_hook_check.mk`，与本次 inline hook 集成不兼容。
3. `KSU_SUSFS` 依赖 `THREAD_INFO_IN_TASK && 64BIT`（`Kconfig:106`），arm64 + GKI 6.1 满足。
4. 建议一并开启（否则对应代码白编）：`KSU_SUSFS_SUS_PATH`、`KSU_SUSFS_SUS_MOUNT`、`KSU_SUSFS_SUS_KSTAT`、`KSU_SUSFS_SPOOF_UNAME`、`KSU_SUSFS_ENABLE_LOG`、`KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS`、`KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG`、`KSU_SUSFS_OPEN_REDIRECT`、`KSU_SUSFS_SUS_MAP`。
5. `CONFIG_KSU_SUSFS_PRIORITY_UID_FILTER` 在 BakaSU Kconfig 中不存在，无法开启（见 6.b）。若需要该特性，Phase 4 需参照 `10_enable_susfs_for_ksu.patch:151-158` 补 Kconfig 条目（本阶段按约束未改）。
6. `fs/exec.c` Hunk #2/#3/#4 有 +7 行偏移，说明该文件基线行号与补丁制作时相差 7 行；已 clean 应用，无需额外处理，但若 Phase 4 出现上下文冲突应优先怀疑此处。
7. 编译期会由 `inline_hook_check.mk` 打印 `SUSFS_VERSION: v2.4.0` 与 8 条 `hook found`；若看到 `You lost ... hook` 即表示某个钩子被误删。`susfs_compat.mk` 应打印 `selinux_hide manual hook found`，**不应**打印 `ksu_install_su_fd direct call found`。
