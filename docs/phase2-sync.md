# Phase 2 — Pixel 9 (tokay) GKI 源码拉取与基线准备报告

- 生成时间：2026-11-16 12:2x CST（Asia/Shanghai）
- 源码根：`/opt/data/android/tokay/src`
- 本阶段**只拉源码、建基线、验证**：未打任何补丁、未运行 bazel、未编译。
- 结论：**全部通过**。18/18 project 同步成功，基线 tag 已建，BakaSU 注入成功并锁定到指定 commit，susfs `50_` 补丁在真实源码树上 **27/27 `git apply --check` 通过**（连带整包 check 也通过）。

---

## 1. 分支与 HEAD

| 项 | 值 |
|---|---|
| manifest 仓库 | `https://android.googlesource.com/kernel/manifest` |
| manifest 分支 | `common-android14-6.1-2026-09` |
| kernel/common revision | `android14-6.1-2026-09` |
| **kernel/common HEAD** | `47ef95e42b7521a3c886ff18d879361afc536ade` |
| HEAD 提交 | `UPSTREAM: ipv4: free inet_opt and ireq_opt after an RCU grace period`（2026-11-10 08:12:33 +0000） |
| 内核版本（common/Makefile） | `VERSION=6` `PATCHLEVEL=1` `SUBLEVEL=176` → **6.1.176** |
| 基线 tag | `baseline-pre-baka-su` → `47ef95e42b7521a3c886ff18d879361afc536ade`（轻量 tag，建在未改动的 clean tree 上） |
| repo 工作区状态 | init 时 HEAD 均为 detached；`repo status` 建基线时输出 `nothing to commit (working directory clean)` |

`repo init` 实际命令（关键差异见第 8 节）：

```bash
. /opt/data/tools/bin/android-env.sh
cd /opt/data/android/tokay/src
ulimit -n            # 262144
repo init -u https://android.googlesource.com/kernel/manifest \
  -b common-android14-6.1-2026-09 --depth=1 --no-tags
```

`repo init` 退出码 0，`repo has been initialized in /opt/data/android/tokay/src`。

---

## 2. 18 个项目清单（HEAD 快照）

`repo list | wc -l` → **18**（与预期一致）。完整清单同时存于
`patches/project-heads-pre-baka-su.txt`、`patches/manifest-2026-09-rev.xml`（`repo manifest -r`，逐项目 pin 到 SHA）。

| # | path | project | HEAD |
|---|---|---|---|
| 1 | `build/bazel_common_rules` | platform/build/bazel_common_rules | `62c496cd1d821948d2f4a7fcf702e54416e5a754` |
| 2 | `build/kernel` | kernel/build | `ccc31488bfbfe383b42a5538de70cebfddad693e` |
| 3 | `common` | kernel/common | `47ef95e42b7521a3c886ff18d879361afc536ade` |
| 4 | `common-modules/virtual-device` | kernel/common-modules/virtual-device | `529e4edbd01fb9d7c8ace1d006e0976145dcd728` |
| 5 | `common-modules/wonder` | kernel/common-modules/wonder | `71026f6078ca5c44e173d12151e767781a12beb5` |
| 6 | `external/bazel-skylib` | platform/external/bazel-skylib | `f998e5dc13c03f0eae9e373263d3afff0932c738` |
| 7 | `external/python/absl-py` | platform/external/python/absl-py | `2f199605a9875340569e039657f8b4c72d51b84d` |
| 8 | `external/stardoc` | platform/external/stardoc | `e83f522ee95419e55d2c5654aa6e0143beeef595` |
| 9 | `kernel/configs` | kernel/configs | `bd79f38685cf939ab836dd8ddd2e01506ccff47a` |
| 10 | `prebuilts/bazel/linux-x86_64` | platform/prebuilts/bazel/linux-x86_64 | `7bfbec9e829bbae6816d5f39aba345df76e627c1` |
| 11 | `prebuilts/build-tools` | platform/prebuilts/build-tools | `4649614b4030ad825f2e94401d04526651f44e88` |
| 12 | `prebuilts/clang-tools` | platform/prebuilts/clang-tools | `f08a96e4015aed7c0341b880ccd85500b1b44a26` |
| 13 | `prebuilts/clang/host/linux-x86` | platform/prebuilts/clang/host/linux-x86 | `382db94fa9597402b69e252c36bf9902cc283b82` |
| 14 | `prebuilts/gcc/linux-x86/host/x86_64-linux-glibc2.17-4.8` | platform/prebuilts/gcc/.../x86_64-linux-glibc2.17-4.8 | `f6d40532273c8bd628b960ecc0970c7294c8d891` |
| 15 | `prebuilts/jdk/jdk11` | platform/prebuilts/jdk/jdk11 | `649eec4416e2ed6298af49a56876772767a0e5ae` |
| 16 | `prebuilts/kernel-build-tools` | kernel/prebuilts/build-tools | `e905be252a53d20c52bd9e59df3ff8fdd46b9eab` |
| 17 | `prebuilts/ndk-r23` | toolchain/prebuilts/ndk/r23 | `19ac7e4eded12adb99d4f613490dde6dd0e72664` |
| 18 | `tools/mkbootimg` | platform/system/tools/mkbootimg | `615a1fced5f8e2755642d30357674d3bfa21b85e` |

另有非 repo 项目（BakaSU 脚本克隆，不属于 manifest）：
`/opt/data/android/tokay/src/KernelSU` @ `5d6d1843c8937f5ff2a145dc89a0cf46030ae6f8`。

---

## 3. 磁盘占用

`du -sh --one-file-system /opt/data/android/tokay/src/*`：

```
0        src/WORKSPACE
4.0K     src/README.md
292K     src/tools
532K     src/kernel
1.4M     src/common-modules
3.0M     src/build
27M      src/external
1.5G     src/common
6.6G     src/prebuilts
```

补充：

```
11G      src（含 2.1G .repo，其中 project-objects：platform 1.3G / toolchain 463M / kernel 310M）
95M      src/KernelSU（含 66M .git —— Kbuild 硬要求）
df -h /opt/data → 207G 总，已用 70G，可用 127G（36%）
```

浅克隆生效：全量 11G（若全历史预计 30G+）。

---

## 4. 工具链冒烟结果

| 项 | 结果 |
|---|---|
| `tools/bazel` | 存在，`-> ../build/kernel/kleaf/bazel.sh`（34B 软链，非实体脚本）；`WORKSPACE` → `build/kernel/kleaf/bazel.WORKSPACE` |
| `build/kernel/kleaf/bazel.sh` | 存在（801B），内容为 `exec prebuilts/build-tools/path/linux-x86/python3 .../bazel.py "$ROOT_DIR" "$@"` |
| clang | `prebuilts/clang/host/linux-x86/` 下只有 `clang-r487747c` 与 `clang-stable` |
| clang 版本 | `clang-r487747c/bin/clang --version` → `Android (10087095, +pgo, +bolt, +lto, -mlgo, based on r487747c) clang version 17.0.2`，Target `x86_64-unknown-linux-gnu` |
| AVX2 主机兼容 | **正常执行，无 illegal instruction**；`ldd` 无 `not found` |
| clang 版本一致性 | `common/build.config.constants` → `CLANG_VERSION=r487747c`，与树内 prebuilt 完全对应 |
| `clang-stable` | 目录内只有 `clang-format`、`git-clang-format`（README 称其为 clang-r498229 的拷贝，但树内无 r498229 目录）——仅格式化工具，**不是可用工具链**，不要把它当编译器 |
| bazel 预编译 | `prebuilts/bazel/linux-x86_64/bazel` → `bazel_nojdk-43445b99...-linux-x86_64`（37MB），执行 `--version` 输出 `bazel no_version`（该 prebuilt 未打版本戳）；`build/kernel/kleaf/bazel.py` 不解析 `--version`，故无影响 |
| JDK | 宿主 `javac 21.0.13` / Temurin 21.0.13；树内另有 `prebuilts/jdk/jdk11` |
| python | 树内 `prebuilts/build-tools/path/linux-x86/python3`（kleaf 用） |

---

## 5. 基线（打补丁前）

```
cd common && git status --short      → 空（clean）
git rev-parse HEAD                   → 47ef95e42b7521a3c886ff18d879361afc536ade
git tag baseline-pre-baka-su         → OK
git rev-parse baseline-pre-baka-su^{} → 47ef95e42b7521a3c886ff18d879361afc536ade
repo status                          → nothing to commit (working directory clean)
```

基线留档（均在 `patches/`）：
- `manifest-2026-09.xml` —— init 时的静态 manifest（18 project）
- `manifest-2026-09-rev.xml` —— `repo manifest -r` 修订快照，逐项目 pin 到 SHA（**权威回滚依据**）
- `project-heads-pre-baka-su.txt` / `project-heads-full.txt`
- `baseline-record.txt`
- `pre-injection-drivers-hashes.txt`（注入前 `drivers/Makefile` / `drivers/Kconfig` 的 sha256，用于检查注入内容是否只有官方那 3 行）

---

## 6. BakaSU 注入（官方 setup.sh，固定 commit）

```bash
cd /opt/data/android/tokay/src
bash /opt/data/workspace/tokay-kernel/research/BakaSU/kernel/setup.sh \
     5d6d1843c8937f5ff2a145dc89a0cf46030ae6f8
```

脚本输出要点：`Cloning into 'KernelSU'` → `Already up to date`（git pull 无更新）→ `HEAD is now at 5d6d1843 kernel: fix return type and header_install path of preinit (#659)` → `[+] Symlink created` / `[+] Modified Makefile` / `[+] Modified Kconfig` / `[+] Done.`，退出码 0。

验证：

| 检查 | 结果 |
|---|---|
| `git -C KernelSU log -1 --format=%H` | `5d6d1843c8937f5ff2a145dc89a0cf46030ae6f8` ✅（2026-11-15 22:02:44 +0800） |
| `test -d KernelSU/.git` | `has-git` ✅（Kbuild 硬要求） |
| `ls -l common/drivers/kernelsu` | `-> ../../KernelSU/kernel`，`readlink -f` = `/opt/data/android/tokay/src/KernelSU/kernel` ✅ |
| `common/drivers/kernelsu/Kconfig`、`Makefile` | 经软链可见（9117B / 1203B）✅ |
| `git -C common status --short` | ` M drivers/Kconfig`、` M drivers/Makefile`、`?? drivers/kernelsu` |

`git -C common diff --stat` → `2 files changed, 3 insertions(+)`，内容与预期完全一致：

```diff
--- a/drivers/Kconfig
+++ b/drivers/Kconfig
@@ -239,4 +239,5 @@ source "drivers/peci/Kconfig"
 source "drivers/hte/Kconfig"
 
+source "drivers/kernelsu/Kconfig"
 endmenu

--- a/drivers/Makefile
+++ b/drivers/Makefile
@@ -189,3 +189,5 @@ obj-$(CONFIG_HTE)      += hte/
+
+obj-$(CONFIG_KSU) += kernelsu/
```

> 说明：`?? drivers/kernelsu` 是 setup.sh 建的软链，属预期产物（setup.sh 不把它加进 index）。所以 `git status --short` 是 **3 行**而不是 2 行；两个 **被修改的受控文件** 确实只有 `drivers/Makefile` 与 `drivers/Kconfig`。

`repo status` 也确认只有 `common/` 有改动（`-m drivers/Kconfig`、`-m drivers/Makefile`、`-- drivers/kernelsu`）。

另外确认：BakaSU 自带 `KernelSU/kernel/Kconfig` 已定义 `config KSU_SUSFS` 及全部子项（`KSU_SUSFS_SUS_PATH/SUS_MOUNT/SUS_KSTAT/SPOOF_UNAME/ENABLE_LOG/...`，共 20 处命中），因此 **`10_enable_susfs_for_ksu.patch` 对 BakaSU 不需要**（那是给原版 KernelSU 用的），Phase 3 不要重复应用。

---

## 7. susfs `50_` 补丁在真实源码树上的 27/27 dry-run

对象：`research/susfs4ksu/kernel_patches/50_add_susfs_in_gki-android14-6.1.patch`
（106829B，132 个 `@@` hunk，27 个 `diff --git` 文件块）

方法：按 `diff --git` 切块 → 逐块写单文件临时 patch → 在 `common/` 内 `git apply --check -p1`（**只 check，不 apply**）。
脚本：`scripts/susfs-dryrun.py`；原始输出：`patches/susfs-dryrun-real-tree.txt`、`/opt/data/android/tokay/logs/susfs-dryrun.txt`。

| # | 状态 | 文件 |
|---|---|---|
| 1 | OK | block/ioprio.c |
| 2 | OK | drivers/input/input.c |
| 3 | OK | fs/Makefile |
| 4 | OK | fs/exec.c |
| 5 | OK | fs/namei.c |
| 6 | OK | fs/namespace.c |
| 7 | OK | fs/notify/fdinfo.c |
| 8 | OK | fs/open.c |
| 9 | OK | fs/proc/base.c |
| 10 | OK | fs/proc/bootconfig.c |
| 11 | OK | fs/proc/fd.c |
| 12 | OK | fs/proc/task_mmu.c |
| 13 | OK | fs/proc_namespace.c |
| 14 | OK | fs/read_write.c |
| 15 | OK | fs/readdir.c |
| 16 | OK | fs/stat.c |
| 17 | OK | fs/statfs.c |
| 18 | OK | fs/super.c |
| 19 | OK | kernel/kallsyms.c |
| 20 | OK | kernel/reboot.c |
| 21 | OK | kernel/sys.c |
| 22 | OK | mm/memory.c |
| 23 | OK | security/selinux/avc.c |
| 24 | OK | security/selinux/hooks.c |
| 25 | OK | security/selinux/selinuxfs.c |
| 26 | OK | security/selinux/ss/services.c |
| 27 | OK | security/selinux/status.c |

**RESULT: 27/27 OK，FAIL: 0**（脚本退出码 0）

附加交叉验证：整包一次性 `git apply --check -p1 --verbose <50_.patch>` 也返回 **0**（`Checking patch ... status.c` 全部无错）。即 27 个分块与整包两种粒度都通过，D-3（补丁与真实树上下文不匹配）风险已排除。

> 重要：该补丁 **不创建** 三个新文件。`fs/Makefile` hunk 里加的是 `obj-$(CONFIG_KSU_SUSFS) += susfs.o`，所以 Phase 3 必须手动放入：
> - `fs/susfs.c`（源 `kernel_patches/fs/susfs.c`，86623B）
> - `include/linux/susfs.h`
> - `include/linux/susfs_def.h`
> 这三个文件**不在** 27/27 的 check 覆盖范围内（`git apply --check` 只管已存在文件的 hunk），必须先放文件再打补丁，否则 `fs/Makefile` 引用 `susfs.o` 会编译失败。

---

## 8. 归档产物（`/opt/data/workspace/tokay-kernel/patches/`）

| 文件 | 说明 |
|---|---|
| `50_add_susfs_in_gki-android14-6.1.patch` | susfs 主补丁（27 文件 / 132 hunk） |
| `fs_susfs.c` | 新文件 → 目标 `fs/susfs.c` |
| `susfs.h` | 新文件 → 目标 `include/linux/susfs.h` |
| `susfs_def.h` | 新文件 → 目标 `include/linux/susfs_def.h` |
| `10_enable_susfs_for_ksu.patch` | （备用，BakaSU 不需要） |
| `manifest-2026-09.xml` / `manifest-2026-09-rev.xml` / `manifest-2026-09-shallow-local.xml` | 静态 / 修订 / 本次浅克隆用的 manifest |
| `project-heads-pre-baka-su.txt`、`baseline-record.txt`、`pre-injection-drivers-hashes.txt` | 基线留档 |
| `bakasu-setup.log`、`bakasu-injection.diff`、`repo-sync.log`、`susfs-dryrun-real-tree.txt` | 证据链 |
| `sha256sums.txt` | 上述补丁/新文件/manifest 的 sha256 |

`sha256sums.txt`：

```
adaed18bfa298d83c2d768f0433b7c87f418d157e88df0006d2d962dfb8f3144  50_add_susfs_in_gki-android14-6.1.patch
2a8bb10bca2ad5134cd65bf02ef56863795949b1d9cbed603c380b58d9bc61bf  fs_susfs.c
763a502a37c3ffa3807ba2cab46af31807b8bd87cccb86d12e552d0532a96573  susfs.h
e8a1cee4b41bcdce43998ae337e60fca9888b2f8bea47074fe3b3377220794d8  susfs_def.h
601de796e5e63d4a87808e5199738c6623c4190004baafa904338b5d837b2837  10_enable_susfs_for_ksu.patch
cc6b9faa54a774b0e2f50b310ccb38ff3f075d54134f5aa63fba55e1049d37c2  manifest-2026-09.xml
2367d3d59b4ac498338a22e6f235b8184c3061e0b62d056c022ac753fc187585  manifest-2026-09-rev.xml
04a8d47a3f9397500d1f0b9b2a7bda95ec8681f102aaaca7887cc67cb1b36a53  manifest-2026-09-shallow-local.xml
```

辅助脚本（可重跑）：`/opt/data/workspace/tokay-kernel/scripts/sync-loop.sh`、`scripts/susfs-dryrun.py`。

---

## 9. 遇到的问题与解决

1. **`repo sync --depth` 在 repo 2.71 上不存在**
   首次按指令跑 `repo sync -c --depth=1 ...` → `main.py: error: no such option: --depth`（退出码 2），循环重试 20 次全部失败（每次 <1s，`repo-sync.log` 有完整记录）。
   原因：`--depth` 是旧版 repo 的 sync 选项；2.x 里浅克隆改由 manifest 的 `clone-depth` 属性控制。而 `repo init --depth=1` 只把 `depth = 1` 写进 `.repo/manifests.git/config`（只影响 manifest 仓库本身，**不影响 project**）。
   解决：复制 `default.xml` → `.repo/manifests/shallow.xml`，给全部 18 个 project 补 `clone-depth="1"`（原本已有 8 个自带），用 `repo sync -m shallow.xml` 同步。等效达成"不拉全历史"，实际 11G。
   该浅克隆 manifest 也留档为 `patches/manifest-2026-09-shallow-local.xml`，便于复现。

2. **`repo manifest -r` 在 sync 前会失败**
   sync 前执行报 `rev-parse: No such file or directory: .../build/kernel`（project 还没 checkout）。改为 sync 完成后再 `repo manifest -r`，成功产出 18 project 的修订快照。

3. **同步实际耗时远低于预估**
   首轮 116 秒（12:21:03 → 12:23:01）即 `repo sync has finished successfully`，落地 11G。为此额外核对了 `repo list`（18）、逐项目 HEAD、`common/Makefile` 版本、文件存在性，确认不是"空壳 checkout"；`.repo` 2.1G + 工作树 11G 与浅克隆预期一致。

4. **`prebuilts/clang/host/linux-x86/clang-stable/` 不是工具链**
   里面只有 `clang-format`、`git-clang-format`，`clang-stable/bin/clang` 不存在。真正的编译器是 `clang-r487747c`（与 `CLANG_VERSION=r487747c` 一致）。若后续脚本写死 `clang-stable/bin/clang` 会 `No such file or directory`。

5. **`bazel --version` 输出 `bazel no_version`**
   该 prebuilt 未打版本戳。核查 `build/kernel/kleaf/bazel.py` 无版本解析逻辑，不影响 kleaf；二进制本身可正常执行（无 illegal instruction）。

6. **`git status --short` 比预期多一条 `?? drivers/kernelsu`**
   setup.sh 只建软链不入 index，属官方行为。受控文件改动仍严格是 `drivers/Makefile` + `drivers/Kconfig` 两处。

7. **`git pull` 需要 github 网络**
   setup.sh 内部有 `git pull`。事先 `git ls-remote` 验证 github 可达且 `refs/heads/main` = `5d6d1843...`，脚本里的 `Already up to date` 说明拉取正常，未出现因网络导致的 checkout 失败。

---

## 10. 给 Phase 3（打补丁 + 构建）的注意事项

1. **回滚路径**：`git -C common checkout -- drivers/Makefile drivers/Kconfig && rm -f common/drivers/kernelsu`，或 `bash research/BakaSU/kernel/setup.sh --cleanup`（会连带删 `KernelSU/`）。**不要** `git clean -fdx common/` 之外乱来——`git clean -fdx` 会删掉软链导致 Kbuild 找不到 `drivers/kernelsu`。基线 tag `baseline-pre-baka-su` 是 `common` 干净状态的唯一锚点。
2. 打 susfs 补丁顺序：先放 3 个新文件（`fs/susfs.c`、`include/linux/susfs.h`、`include/linux/susfs_def.h`），再 `git apply -p1 50_.patch`；`10_enable_susfs_for_ksu.patch` **不要**用在 BakaSU 上。
3. 配置层面需要 `CONFIG_KSU=y` + `CONFIG_KSU_SUSFS=y`（及子项），符号由 `drivers/kernelsu/Kconfig`（= BakaSU）提供，已确认存在。
4. 构建必须 `--config=fast`（容器禁 user namespace）；`tools/bazel` 软链与 `WORKSPACE` 就绪，bazel 预编译可用。
5. 磁盘余量 127G，`out/` 仍未使用；内存 15.5G（available ~9.8G）、swap ~5.2G，构建并发别开太高。
