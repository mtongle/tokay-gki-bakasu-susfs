# Phase 1：环境与工具链预检报告（Pixel 9 / tokay / GKI android14-6.1）

- 生成时间：2026-11-16 12:0x CST（容器内 `date` 实测）
- 目标：为 `kernel/common` @ `android14-6.1`（Kleaf/Bazel）构建集成 BakaSU + susfs4ksu 的内核，做 Phase 1 环境就绪
- 约束：rootless（uid=10000，无 sudo / 无 docker socket），只能 tarball 或 `apt-get download` + `dpkg-deb -x`
- 本次**未执行** `repo init` / `repo sync`，未 clone 内核源码，单次下载均 <500MB

---

## 0. 结论速览

| 项目 | 结论 | 风险 |
|---|---|---|
| 磁盘 | `/opt/data` = **ext4**（非 overlay），207G 总 / **137G 可用** / inode 余 13.1M | 充足 |
| 文件系统与 Bazel | 硬链接/rename/symlink/3G ftruncate 全通过；**实跑 bazel 构建成功** | 无 |
| 用户命名空间 | `unshare -U/-m/-p` **全部 EPERM**（seccomp 限制）→ `linux-sandbox` 不可用，bazel 自动退到 `processwrapper-sandbox`（已验证可 build） | 中，需 `--config=local` |
| 内存 | 15.5Gi 总 / **available 9.9Gi**；swap 11.5G **已用 6.3G，仅剩 5.2G** | **高**（最主要瓶颈） |
| overcommit | `vm.overcommit_memory=0`，`max_map_count=1048576` | 无 |
| nofile | 软 4096 / 硬 **524288**；软限可提到 262144（1M 不允许） | 低，env 脚本已处理 |
| repo | launcher **2.71** 可用（python3 3.14.9 与 3.13.5 均可） | 低 |
| bazelisk | **v1.30.0**，成功拉取 bazel **9.3.2**（仅作连通性/应急，**不用于 Kleaf 构建**） | 无 |
| 网络 | googlesource **通**（4.25 MB/s）、GitHub **通**（44.6 MB/s）、GitLab **通**（较慢）、storage.googleapis.com **通**，**无需代理** | 低 |
| tokay 专属 manifest | `kernel/manifest` **无 tokay 分支**（0 命中），只有 akita/caimito/comet 等 | **中**，见 §7.6 |
| 预算 | 浅克隆 14–18G + 构建产物 15–30G + 其他 ~3G ≈ **32–51G**，对 137G 余量足够 | 低 |

---

## 1. 主机关键参数补测（命令 + 实测输出）

### 1.1 文件系统类型（决定 Bazel 是否安全）

```bash
$ findmnt -T /opt/data -o TARGET,SOURCE,FSTYPE,OPTIONS
TARGET    SOURCE                                                       FSTYPE OPTIONS
/opt/data /dev/sda2[/opt/1panel/apps/hermes-agent/Hermes-Agent/data]    ext4   rw,relatime,errors=remount-ro
```

`/` 报 overlay，但 **`/opt/data` 是宿主 ext4 的直接 bind mount**（不是 overlay 上层）。这一点很关键：Bazel 的 `output_base` 强依赖 **硬链接 + rename + 大文件 ftruncate**，在 overlayfs 上会退化甚至失败，在 ext4 上完全没有问题。

实测（`/opt/data/cache/scratch/fstest`）：

```
hardlink OK: 2 links
rename OK
symlink OK
O_RDWR OK
ftruncate 3G sparse OK 3221225472
```

### 1.2 内存 / overcommit / cgroup

```bash
$ cat /proc/sys/vm/overcommit_memory      → 0        # 启发式，非 strict
$ cat /proc/sys/vm/overcommit_ratio       → 50
$ cat /proc/sys/vm/max_map_count          → 1048576  # 充足（LLVM/lld 需要大 mmap 计数）
$ cat /sys/fs/cgroup/memory.max           → max      # 无 cgroup 内存上限，只有宿主 15Gi
$ cat /sys/fs/cgroup/memory.current       → 2215751680 (2.1G)
$ cat /sys/fs/cgroup/cpu.max              → max 100000  # 无 CPU quota，可用满 24 核
$ nproc                                   → 24
$ free -h
              total   used   free  shared buff/cache  available
Mem:           15Gi   5.6Gi  7.2Gi   16Mi      3.0Gi       9.9Gi
Swap:          11Gi   6.3Gi  5.2Gi
```

**结论**：没有 cgroup 天花板，但**真实可用内存只有 ~9.9Gi，swap 只剩 5.2G**（另有进程已占用 6.3G swap）。这是整个 Phase 2 最硬的约束，直接决定 `--jobs`。

### 1.3 文件句柄 / inotify

```bash
$ ulimit -n        → 4096        # 软限，偏小
$ ulimit -Hn       → 524288      # 硬限，可提
$ ulimit -n 262144 → OK（生效）
$ ulimit -n 1048576→ cannot modify limit: Operation not permitted   # 超过硬限，正常
$ cat /proc/sys/fs/inotify/max_user_watches    → 124551
$ cat /proc/sys/fs/inotify/max_user_instances  → 128
```

内核树约 8 万文件，**124551 只够勉强**；bazel 的 `--watchfs` 可能报 "inotify watch limit reached"。无法提（需 root），缓解见 §8.3。

### 1.4 磁盘与 inode

```bash
$ df -h /opt/data   → /dev/sda2  207G  60G  137G  31%
$ df -i /opt/data   → 13836288 inodes, 709143 used (6%), 13127145 free
```

inode 余量 1310 万，内核树（~8 万文件）×多份 out 完全够。

### 1.5 CPU 指令集（影响 prebuilt clang/lld）

```bash
$ grep -m1 '^flags' /proc/cpuinfo | grep -E 'avx512|avx2'
avx avx2 bmi2 fma sse4_2        # 无 avx512f
$ grep -m1 'model name' /proc/cpuinfo → Intel(R) Xeon(R) CPU E5-2673 v3 @ 2.40GHz
$ cc --version → cc (Debian 14.2.0-19) 14.2.0
$ command -v ld ar as nm objcopy strip → 全部存在
```

AOSP prebuilt clang 以 x86-64 baseline 编译，**AVX2 足够**；仅失去 AVX512 加速（编译慢一些，不影响正确性）。低风险。

---

## 2. 关键限制：user namespace 被禁（已实证，且有可行绕过）

```bash
$ cat /proc/sys/user/max_user_namespaces     → 62708
$ cat /proc/sys/kernel/unprivileged_userns_clone → 1
$ unshare -U -r true      → unshare failed: Operation not permitted
$ unshare -U -r -m true   → unshare failed: Operation not permitted
$ unshare -U -r -p -f true→ unshare failed: Operation not permitted
```

sysctl 允许，但容器 **seccomp filter 拦截了 `unshare`/`clone(CLONE_NEWUSER)`** → Bazel 的 `linux-sandbox`（基于 userns + mount ns）**不可能工作**。

不过 **Bazel 会优雅降级**。我用 bazel 9.3.2 建了一个最小 genrule 工作区做真实验证：

```bash
$ cd /opt/data/cache/scratch/bazelprobe
$ cat MODULE.bazel  → module(name = "probe")
$ cat BUILD.bazel   → genrule(name="g", outs=["o.txt"], cmd="echo hi > $@ ...")
$ bazelisk build //:g
INFO: Elapsed time: 14.842s, Critical Path: 0.03s
INFO: 2 processes: 1 internal, 1 processwrapper-sandbox.
INFO: Build completed successfully, 2 total actions
```

**结论**：`processwrapper-sandbox` 可用（无需 userns），构建能跑通。但严格 hermetic 隔离失效；Kleaf 侧对应开关是已确认的源码事实：

```bash
# kernel/build/kleaf/bazelrc/local.bazelrc
build:local --//build/kernel/kleaf:config_local
build --strategy=KernelModuleProcessWrapperSandbox=processwrapper-sandbox
# kernel/build/kleaf/bazelrc/fast.bazelrc
build:fast --//build/kernel/kleaf:config_fast
build:fast --config=local
```

即 **`--config=fast` ⊃ `--config=local`**，两者都会把 module 类 action 从 sandbox 里挪出来，正好绕开本限制。→ **Phase 2 必须带 `--config=local` 或 `--config=fast`**。

---

## 3. 已安装工具与验证证据

所有二进制落在 `/opt/data/tools`（不动系统前缀），一键环境脚本：`/opt/data/tools/bin/android-env.sh`。

```bash
$ . /opt/data/tools/bin/android-env.sh
$ python3 -V        → Python 3.13.5
$ repo --version    → repo launcher version 2.71 / git 2.47.3
$ bazelisk version  → Bazelisk v1.30.0 + Build label: 9.3.2
$ ulimit -n         → 262144
```

### 3.1 清单

| 工具 | 版本（实测输出） | 来源 | 依赖 debroot 库 |
|---|---|---|---|
| repo | `repo launcher version 2.71` | `storage.googleapis.com/git-repo-downloads/repo` | 否 |
| bazelisk | `Bazelisk version: v1.30.0` → `bazel 9.3.2` | GitHub releases `bazelisk-linux-amd64` | 否 |
| bc | `echo "scale=2;3+4" \| bc` → `7`（无 --version） | deb `bc 1.07.1-4` | 否 |
| bison | `bison (GNU Bison) 3.8.2` | deb `bison 3:3.8.2+dfsg-1+b2` | 否 |
| flex | `flex 2.6.4` | deb `flex 2.6.4-8.2+b4` | 否 |
| gperf | `GNU gperf 3.2.1` | deb `gperf 3.2.1-1` | 否 |
| rsync | `rsync  version 3.5.0  protocol version 32` | deb `rsync 3.5.0+ds1-0+deb13u1` | **是（libpopt）** |
| cpio | `cpio (GNU cpio) 2.15` | deb `cpio 2.15+dfsg-2` | 否 |
| unzip | `UnZip 6.00 of 20 April 2009` | deb `unzip 6.0-29+deb13u1` | 否 |
| zip | `This is Zip 3.0 (July 5th 2008)` | deb `zip 3.0-15+deb13u1` | 否 |
| lz4 | `*** lz4 v1.10.0 64-bit multithread ***` | deb `lz4 1.10.0-4` | 否 |
| zstd | `v1.5.7`（额外补，Image/dtbo 压缩常用） | deb `zstd 1.5.7+dfsg-1` | 否 |
| pahole | `v1.30`（BTF 生成，可选） | deb `pahole 1.30-1` + `dwarves` | **是（libelf/libdw）** |
| patch | `GNU patch 2.8`（打 susfs/BakaSU 补丁） | deb `patch 2.8-2` | 否 |
| wget | `GNU Wget 1.25.0` | deb `wget 1.25.0-2` | 否 |
| python3 | 系统 3.13.5（`/opt/data/tools/bin/python3` → `/usr/bin/python3.13`） | Debian 自带 | 否 |
| JDK | Temurin 21（`/opt/data/tools/jdk21`） | 既有 | 否 |

### 3.2 安装方法（可复现）

```bash
# apt 索引为空时，用可写目录重建（uid 10000 也可以）
apt-get -o Dir::State::lists=/opt/data/cache/scratch/aptlists \
        -o Dir::Cache=/opt/data/cache/scratch/aptcache \
        -o Debug::NoLocking=1 update
# 下载 + 解包（不 install）
apt-get <同上选项> download bc bison flex gperf rsync cpio unzip zip lz4 zstd patch wget pahole
for f in *.deb; do dpkg-deb -x "$f" /opt/data/tools/debroot; done
```

> 坑：`/var/lib/apt/lists` 为空 → 直接 `apt-get download` 报 `Unable to locate package`。必须用 `-o Dir::State::lists=` 指到可写目录并 `update`。`/var/cache/apt/archives` 的 `rm` 报 Permission denied 属正常噪音，忽略。

### 3.3 体积

```
7.6M  /opt/data/tools/bin        (repo 47K + bazelisk 7.8M)
166M  /opt/data/tools/debroot    (解包的 deb 前缀)
63M   /opt/data/home/.cache/bazelisk   (bazel 9.3.2 缓存)
```

---

## 4. 哪些必须系统层有，哪些由 prebuilts 提供

GKI/Kleaf 的 `common-android14-6.1` manifest 共 **18 个项目**（解析 `default.xml` 实测），其中 prebuilts 覆盖了绝大部分重工具链：

| 类别 | 系统层必须 | 由仓库 prebuilts 提供 |
|---|---|---|
| 源码同步 | **git 2.47.3 + repo 2.71 + python3** | — |
| 下载 | **curl / wget** | — |
| 编译驱动 | 无（bazel 由 `prebuilts/bazel/linux-x86_64/bazel` 启动器自带 `bazel_nojdk-<hash>`） | bazel 本体 |
| C/C++ 工具链 | 无 | `prebuilts/clang/host/linux-x86`（clang/llvm/lld，约 5–6G） |
| host binutils | 有系统 `ld/ar/as/nm/objcopy/strip`（gcc 14.2）作兜底 | `prebuilts/build-tools`、`kernel/prebuilts/build-tools` |
| kconfig | **bison / flex / bc**（Kleaf 也会用到 host 侧） | `prebuilts/build-tools` 内的 make/python |
| Python | **python3**（repo 与部分 host 脚本） | `prebuilts/build-tools/linux_musl-x86/bin/py3-cmd`（Kleaf 自己的 hermetic python，`bazel.sh` 就是用它 exec `bazel.py`） |
| JDK | 可无 | `prebuilts/jdk/jdk11` |
| 打包 | **cpio / zip / unzip / rsync / lz4 / zstd / patch** | mkbootimg（`tools/mkbootimg`） |
| DT/镜像 | 无 | `prebuilts/ndk-r23` 等 |

**一句话**：系统层只需 `git + repo + python3 + curl + 一堆小工具`；**clang/llvm/lld/ninja 级别的东西全部来自 prebuilts，不需要也不应该自己装**。

> 注意 `kernel/build/kleaf/bazel.sh` 实测内容：
> `exec "$KLEAF_REPO_DIR"/prebuilts/build-tools/linux_musl-x86/bin/py3-cmd "$MYDIR"/bazel.py "$@"`
> → Kleaf 用自带 musl python，**host python 版本不影响 Kleaf**（只影响 repo）。

---

## 5. 网络连通性预检（Phase 2 可行性）

环境无任何 `*_proxy` 变量，全部**直连**。

| 目标 | 方法 | 结果 | 耗时 / 带宽 |
|---|---|---|---|
| `android.googlesource.com/kernel/manifest` | `git ls-remote` | ✅ 通，HEAD=`f9957ec` | 1.3s |
| 同上（持续吞吐） | `curl` 拉 clang archive 25s | ✅ | **4.25 MB/s**（106MB/25s） |
| `github.com` | `git ls-remote torvalds/linux` | ✅ HEAD=`aebb727` | <2s |
| GitHub 持续吞吐 | codeload tar.gz 20s | ✅ | **44.6 MB/s** |
| `gitlab.com/simonpunk/susfs4ksu.git` | `git ls-remote` | ✅ 通，**含 `refs/heads/gki-android14-6.1`** 与 `-dev` | <3s |
| GitLab 吞吐 | archive 下载 | ✅ 可达但偏慢 | 0.23 MB/s（小文件，仅参考） |
| `storage.googleapis.com` | 下载 repo launcher / prebuilts 目录 | ✅ 通（`git-repo-downloads` 0.84s） | 正常 |
| bazel 下载源 | bazelisk 自取 9.3.2 | ✅ | 7.8M/2.9s |

**susfs4ksu 分支清单（实测节选）**：

```
refs/heads/gki-android14-6.1        f76b81f2
refs/heads/gki-android14-6.1-dev    756abbf2
refs/heads/gki-android14-5.15        a293ab19
refs/heads/gki-android13-5.15        c1d1da42
```

→ **与目标内核版本精确匹配，无需自己移植 susfs**。

**结论**：三条主通道全部直连可用，**Phase 2 不需要代理**。唯一体感问题是 googlesource 4.25 MB/s——30G 级别的全历史同步要 2 小时；按浅克隆 10–15G 算约 **40–60 分钟**。

**镜像结论（仅在需要时启用）**：本次主站可用，未强行切镜像；备选顺序为
`https://mirrors.tuna.tsinghua.edu.cn/git/AOSP/`（AOSP 镜像，路径需替换 remote 的 `..` 前缀）→ GitHub `aosp-mirror/kernel_common`（只覆盖 kernel/common 单仓，manifest 仍需 googlesource）。镜像会引入 manifest revision 不一致风险，**非必要不用**。

---

## 6. 目录规划

```
/opt/data/android/tokay/
├── src/      # repo 工作区根（manifest + common/ + build/ + prebuilts/）  预计 14–18G（浅）/ 30–45G（全历史）
├── out/      # bazel output_user_root 指定位置（可选，默认在 src/out）     预计 15–30G
└── logs/     # repo sync 日志、bazel 日志、构建 stdout                      <1G

/opt/data/workspace/tokay-kernel/
├── research/ # manifest 快照、Kleaf 文档、BakaSU/susfs 说明、版本矩阵       <100M
├── patches/  # susfs4ksu / BakaSU 补丁与 quilt 序列（含 qemu 前的本地改动）  <50M
└── artifacts/# Image.lz4、boot.img、AnyKernel3 zip、modules、校验和         1–2G
```

> 现状（其它并行工作的 agent 已落内容）：`research/` 已存在 `BakaSU`(35M)、`BakaSU-auto-hook`(30M)、`susfs4ksu`(1.1M)、`kernel-build`(3.5M，即 `kernel/build` 仓库)、`kdry`(1.1M)；其中 `susfs4ksu` 已在 **`gki-android14-6.1` 分支、HEAD `f76b81f`**（与 §5 的 `git ls-remote` 结果一致），且已带 `kernel_patches/50_add_susfs_in_gki-android14-6.1.patch`。故 §9 第 5 步无需重复 clone。`patches/`、`artifacts/` 仍为空。

**关于 `--output_user_root`**（源码实证，`kernel/build/kleaf/bazel.py` L275/L509）：

```python
self.absolute_user_root = self.known_startup_options.output_user_root or \
    self.absolute_out_dir / "bazel/output_user_root"
```

即 **Kleaf 默认就把 bazel 的 `output_user_root` 放在 `<out_dir>/bazel/output_user_root`，不会污染 `~/.cache/bazel`，也不需要迁移**。默认 `out_dir` 就是仓库根的 `out/`。

因此 `/opt/data/android/tokay/out` 的定位是**可选重定向目标**：

- **建议：不迁移**。让 `src/out` 留在原地，Kleaf 的所有产物、symlink（`bazel-bin` 等）自洽，`tools/bazel clean` 行为正常，路径短、少一层心智负担。
- 若确实要分离（例如 src 想放别的盘），用 bazel 标准启动参数透传：
  `tools/bazel --output_user_root=/opt/data/android/tokay/out/bazel build ...`
  同盘（都是 `/opt/data` ext4）时收益仅是可读性，**不带来空间隔离**，所以 Phase 1 只建空目录备用。

---

## 7. 资源预算与并发参数

### 7.1 repo sync 体积（manifest 实测 18 个项目）

| 项目（path） | 浅克隆预估 |
|---|---|
| `prebuilts/clang/host/linux-x86` | **5–6 GB** |
| `common`（kernel/common @ android14-6.1） | 1.5–2.0 GB |
| `prebuilts/kernel-build-tools` | 0.6–0.8 GB |
| `prebuilts/ndk-r23` | 0.6–0.8 GB |
| `prebuilts/build-tools` | 0.3–0.5 GB |
| `prebuilts/gcc/.../x86_64-linux-glibc2.17-4.8` | ~0.2 GB |
| `prebuilts/jdk/jdk11` | ~0.2 GB |
| 其余 11 个（build/kernel、clang-tools、bazel、skylib、stardoc、mkbootimg、configs…） | ~0.2 GB |
| **下载合计** | **9–11 GB** |
| **落盘（含 .git 与工作树）** | **14–18 GB** |

全历史（不加 `--depth=1`）落盘 30–45 GB。

### 7.2 构建产物

单次 `//common:kernel_aarch64` + `dist`：8–15 GB；含多目标（`kernel_aarch64_dist`、modules、`--config=fast` 缓存的 `$OUT_DIR`）与增量：**15–30 GB**。

### 7.3 总预算 vs 137G 余量

| 项 | 保守 | 激进 |
|---|---|---|
| src（浅） | 14G | 18G |
| out | 15G | 30G |
| artifacts + logs + patches | 2G | 3G |
| **合计** | **31G** | **51G** |
| 剩余 | 106G | 86G |

**够，且余量健康**。若误用全历史（45G）+ 30G = 75G，仍可承受但只剩 62G，不建议。

### 7.4 并发参数（15G RAM 是唯一硬约束）

依据：available 9.9Gi、swap 仅剩 5.2G、24 核、单个 arm64 clang 编译 action RSS 约 0.6–1.0G、ThinLTO `ld.lld` 链接 vmlinux 单 action 峰值 4–8G。

| 档位 | 命令 | 预估峰值 RSS | 用途 |
|---|---|---|---|
| **保守（推荐首轮）** | `tools/bazel build --config=fast --jobs=6 --local_ram_resources=9216 //common:kernel_aarch64` | 6–8G | 首次全量、含 LTO 的 dist |
| 中等 | `--config=fast --jobs=10` | 9–11G | 已 warm 的增量构建 |
| 激进 | `--config=local --jobs=12` | 12–14G | **会压 swap，仅在不跑 LTO 时试** |
| 发布打包 | `--config=fast --jobs=4`（LTO 链接串行） | 5–7G | 出 `dist` 前的收尾 |

**必须加 `--config=fast`（或至少 `--config=local`）**，三个理由：① 绕开 userns 缺失导致的 sandbox 问题（§2）；② 缓存 `$OUT_DIR`，二次构建快数倍；③ 少一层 sandbox 开销，减少并发时的内存/IO 压力。已知源码事实：`--config=fast` = `config_fast` + `--config=local`。

> ⚠️ **swap 警告（最高优先级）**：现在 swap 已用 **6.3G / 11G**，只剩 5.2G。上表"激进档 12–14G"在 available 9.9G 的情况下**必然触发 swap**，一旦把 swap 打满会触发全局 OOM killer（可能连带杀掉 Hermes 自身进程）。构建期间请另开窗口
> `watch -n 5 'free -h; grep -E "^(SwapFree|MemAvailable)" /proc/meminfo'`
> 看到 `SwapFree < 2G` 或 `MemAvailable < 1.5G` 立刻 `Ctrl-C` 并降到 `--jobs=4`。

### 7.5 `--jobs` 默认值风险

Kleaf **不覆盖** bazel 的 `--jobs`，bazel 默认取 `nproc=24` → 首轮就可能 20G+ 峰值 RSS → 直接 OOM。**Phase 2 每条命令都必须显式带 `--jobs`**。

### 7.6 架构风险：没有 tokay 专属 manifest

```bash
$ git ls-remote --heads .../kernel/manifest | grep -ci tokay          → 0
$ git ls-remote --heads .../kernel/manifest | grep -oE 'android-gs-[a-z]+-6\.1' | sort -u
android-gs-akita-6.1  android-gs-bluejay-6.1  android-gs-caimito-6.1  android-gs-comet-6.1
android-gs-felix-6.1  android-gs-lynx-6.1     android-gs-pantah-6.1   android-gs-raviole-6.1
android-gs-shusky-6.1 android-gs-tangorpro-6.1 android-gs-tegu-6.1
```

有 caimito（Pixel 9 Pro）/ comet（9 Pro Fold），**没有 tokay（Pixel 9）**。含义：

- 主线只能走 **GKI `common-android14-6.1`** 构 `//common:kernel_aarch64`，这与 Pixel 9 的 GKI 6.1 基线一致，可行；
- tokay 的 vendor modules / DTB 不公开 → 刷机路径应走 **AnyKernel3 复用 stock `vendor_boot`/`vendor_dlkm`**，而不是整包替换（否则 vendor 分区不匹配会 bootloop）；
- 这条属于 Phase 2 的方案约束，不影响 Phase 1 结论。

---

## 8. 风险清单与缓解

| # | 风险 | 严重度 | 缓解 |
|---|---|---|---|
| 1 | swap 仅剩 5.2G，24 核默认并发必 OOM | **高** | 显式 `--jobs=6`；构建期监控 `SwapFree`；必要时 `--jobs=4` |
| 2 | `linux-sandbox` 不可用（seccomp 禁 userns） | 中 | 一律 `--config=fast`/`--config=local`；已验证 `processwrapper-sandbox` 可跑 |
| 3 | `max_user_watches=124551` 可能不够内核树 | 中 | 在 `src/user.bazelrc` 加 `common --watchfs=false`；警告出现即加 |
| 4 | 误用 host `bazelisk`（9.3.2）构 Kleaf | 中 | 只用 `tools/bazel`（Kleaf 绑定 `prebuilts/bazel` 的固定版本）；bazelisk 仅作连通性验证/应急 |
| 5 | shallow clone 让 `setlocalversion` 拿不到版本串 | 中 | Kleaf 用 `--config=stamp`/workspace_status 注入；异常时对 `common` 单独 `git fetch --unshallow` |
| 6 | `tools/bazel` 入口在 sync 后才存在 | 低 | `default.xml` 无 `<linkfile>`，sync 后确认；若无则直接用 `build/kernel/kleaf/bazel.sh` |
| 7 | prebuilt clang 在仅 AVX2 的 E5 v3 上异常 | 低 | Phase 2 先跑 `prebuilts/clang/host/linux-x86/clang-*/bin/clang --version` 冒烟；报 illegal instruction 则回退上一版 clang |
| 8 | 无 tokay manifest，vendor 分区不匹配 | 中 | 走 AnyKernel3 + 保留 stock vendor_boot；见 §7.6 |
| 9 | 全历史同步 40G+/2h | 低 | 用 `--depth=1`，见 §9 |
| 10 | `/opt/data` 若是 overlay 的假设错误 | 已排除 | 实测 ext4 bind mount，Bazel 安全 |

---

## 9. Phase 2 建议命令（本次未执行，仅备用）

```bash
. /opt/data/tools/bin/android-env.sh
cd /opt/data/android/tokay/src

# 1) repo 初始化（浅克隆，只取目标分支）
repo init -u https://android.googlesource.com/kernel/manifest \
          -b common-android14-6.1 --depth=1 --no-tags
# 2) 同步（分批、限并发、失败可重入；日志落 logs/）
repo sync -c --no-tags --depth=1 -j4 --fail-fast 2>&1 | tee ../logs/repo-sync-$(date +%F-%H%M).log

# 3) 首次构建（保守并发）
tools/bazel build --config=fast --jobs=6 --local_ram_resources=9216 \
                  //common:kernel_aarch64 2>&1 | tee ../logs/build-1.log
# 4) 出产物
tools/bazel run --config=fast --jobs=6 //common:kernel_aarch64_dist -- --destdir=../out/dist

# 5) susfs 补丁源（已在 research/susfs4ksu，分支 gki-android14-6.1 / f76b81f，勿重复 clone）
#    补丁文件：research/susfs4ksu/kernel_patches/50_add_susfs_in_gki-android14-6.1.patch
#    如需重新拉取：
# git clone --depth=1 -b gki-android14-6.1 https://gitlab.com/simonpunk/susfs4ksu.git \
#           /opt/data/workspace/tokay-kernel/research/susfs4ksu
```

体积/时间预期：sync 9–11G 下载、40–60 分钟；首轮构建 40–90 分钟（24 核 @2.4GHz，`--jobs=6`）。

---

## 10. 复现清单（本报告的全部证据命令）

```bash
findmnt -T /opt/data; df -hT /opt/data; df -i /opt/data
cat /proc/sys/vm/overcommit_memory /proc/sys/vm/max_map_count
cat /sys/fs/cgroup/memory.max /sys/fs/cgroup/cpu.max
bash -c 'ulimit -n; ulimit -Hn'; nproc; free -h
unshare -U -r true            # 预期 EPERM
git ls-remote https://android.googlesource.com/kernel/manifest | head
git ls-remote https://gitlab.com/simonpunk/susfs4ksu.git | grep 6.1
curl -w '%{speed_download}' -o /dev/null --max-time 25 \
     'https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main.tar.gz'
/opt/data/tools/bin/repo --version; /opt/data/tools/bin/bazelisk version
. /opt/data/tools/bin/android-env.sh; bc/bison/flex/gperf/rsync/cpio/unzip/zip/lz4 --version
```
