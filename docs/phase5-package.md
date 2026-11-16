# Phase 5：规范化重建 + 打包验证

日期：2026-11-16
项目：Pixel 9 (tokay) / GKI `android14-6.1-2026-09` / BakaSU + SUSFS
工作根：`/opt/data/android/tokay/src`

---

## 0. 结论

| 项 | 结果 |
| --- | --- |
| maybe-dirty | **已消除**。新 release 串 `6.1.176-android14-11-g45bc826d05a2` |
| 增量重建 | 成功（235.9s / 17 actions），dist 97 文件 778MB，60 个 `.ko` |
| 官方固件 | CP3A.261005.005 工厂包 4,308,239,754 B，**sha256 校验通过** |
| 重打包 boot.img | **16,838,656 B**，字段与 stock 逐项一致，内核载荷 = 我们的 `Image.lz4` |
| 管理器 APK | BakaSU `v4.2.0-rc3 (35277)` universal（官方 KernelSU `v3.3.1 (32680)` 作备份） |
| 刷机说明 | `artifacts/FLASHING.md`（未执行刷机） |

---

## 1. 任务 A：消除 maybe-dirty 并重建

### 1.1 提交

| 仓库 | commit | 内容 |
| --- | --- | --- |
| `src/common` | `45bc826d0` | `build: add BakaSU+SUSFS defconfig fragment, drop protected exports list`（3 files, +33/-359：新增 `bakasu_susfs.fragment`、`BUILD.bazel` 导出该文件、清空 `android/abi_gki_protected_exports_aarch64`） |
| `src/build/kernel` | `ea349a4` | `kleaf: fix HermeticToolsRsync PATH in container`（+3/-1，`kleaf/hermetic_tools.bzl`） |

> 注：`src/build/` 本身**不是** git 仓库，kleaf 代码在 `src/build/kernel/`（repo 工程的 project 是 `build/kernel`）。提交实际落在 `src/build/kernel`。
> 提交后 `common/` 与 `build/kernel/` 的 `git status --short` 均为空；顺带扫描 `common-modules/`、`external/`、`prebuilts/`、`tools/` 也无脏工作区。

### 1.2 maybe-dirty 的根因（不是内核源码问题）

第一次重建（仍带 `--config=fast`）只跑了 8 个 action，`vmlinux` 里依然是
`6.1.176-android14-11-maybe-dirty`。查证结果：

- `scripts/setlocalversion` 只会追加 `-dirty`（小写、无 maybe），所以字符串不是它产生的。
- 真正来源是 Kleaf：`build/kernel/kleaf/impl/stamp.bzl:57-62`

  ```python
  if ctx.attr._config_is_stamp[BuildSettingInfo].value:
      inputs = [ctx.info_file]
      stable_scmversion_cmd = _get_status_at_path(ctx, "STABLE_SCMVERSIONS", '"${KERNEL_DIR}"')
  else:
      inputs = []
      stable_scmversion_cmd = "echo '-maybe-dirty'"     # ← 写死
  ```

- 而 `build/kernel/kleaf/bazelrc/fast.bazelrc` 里 `build:fast` 只展开
  `config_fast` + `--lto=fast` + `--config=local`，**不包含** `--config=stamp`；
  `stamp.bazelrc` 才有 `--//build/kernel/kleaf:config_stamp` 和
  `--workspace_status_command=build/kernel/kleaf/workspace_status.sh`。

→ 只要用 `--config=fast` 构建，scmversion 就恒等于 `-maybe-dirty`，与仓库脏不脏无关。
（仓库脏只是"可能脏"，这正是这个字符串的语义。）

**处理**：在原有参数上追加 `--config=stamp`，不改任何内核源码。
先单独验证 `workspace_status.sh` 可用（`repo` 在 `/opt/data/tools/bin/repo`），输出中 `common` = `-g45bc826d05a2`，无 `-dirty` 后缀。

### 1.3 重建

```bash
tools/bazel build --config=fast --config=stamp --jobs=6 --local_ram_resources=9216 \
  --defconfig_fragment=//common:bakasu_susfs.fragment //common:kernel_aarch64_dist
# 日志：/opt/data/android/tokay/logs/build-3-stamp.log
# INFO: Elapsed time: 235.886s, Critical Path: 231.84s / 17 processes / Build completed successfully
```

```
Linux version 6.1.176-android14-11-g45bc826d05a2 (build-user@build-host) (Android (10087095, +pgo, +bolt, +lto, -mlgo, based on r487747c) clang version 17.0.2 ...) #1 SMP PREEMPT Mon Nov 16 13:06:29 CST 2026
```

- **无 `maybe-dirty`**；SBOM/时间戳也跟着变成真实提交时间（之前是 `Thu Jan 1 1970`，因为 stamp 关闭时 `SOURCE_DATE_EPOCH=0`）。
- 内核符号齐全：`susfs_init`、`ksu_handle_execveat`、`ksu_handle_setresuid`、`ksu_handle_sys_read` 均为 `T`。
- dist 重新导出（`bazel run //common:kernel_aarch64_dist -- --dist_dir=...`）：**97 个文件 778MB**，60 个 `.ko`。

> 注意：`--config=stamp` 会跑 `workspace_status.sh`（遍历全部 repo 工程算 SCMVERSION/SOURCE_DATE_EPOCH），
> 以后重建请**始终**带上这两个 config，否则又会退回 `-maybe-dirty`。

---

## 2. 任务 B：官方固件下载与校验

| 项 | 值 |
| --- | --- |
| 页面 | https://developers.google.com/android/images （设备表是 JS 渲染，curl 拿到的是空壳；不依赖它解析） |
| 直链 | `https://dl-ssl.google.com/dl/android/aosp/tokay-cp3a.261005.005-factory-e44505ee.zip` |
| 大小 | 4,308,239,754 B |
| SHA256 | `e44505eea2ec539be6b510c819ded8aa5f23893357b121a627f8c3e799c368b5` ✅ **与预期一致** |
| 落盘 | `/opt/data/android/tokay/downloads/`（含内层 `image-tokay-cp3a.261005.005.zip`） |

> `dl.google.com/dl/android/aosp/...` 在本机出口 IP 上返回 **429**（连不存在的文件名也 429，属于出口限流，不是链接错）。
> 换 `dl-ssl.google.com` 同一路径 206 正常，`redirector.gvt1.com` 302 也正常。内容 sha256 与预期完全吻合，证明链接正确。

内层 `image-tokay-cp3a.261005.005.zip` 提取（python zipfile，`artifacts/stock/`）：

| 文件 | 大小 (B) | SHA256 |
| --- | --- | --- |
| `boot.img` | 67,108,864 | `09b48c9a3ed022fe63d29965dfc540d39da8e2eb1a9f5021b823279823b7e6ef` |
| `init_boot.img` | 8,388,608 | `4dfb6ff7efeb98dc8bf40bdeb6f097a7808719775c84c423379984c11214bcdd` |
| `vbmeta.img` | 12,288 | `5d6efbb001864fc9364de958536fda73ccaa0a3d21961234503437d227a4820f` |
| `vendor_boot.img` | 67,108,864 | `0e601ee9a2b164583268ab75209e5cd90d411310e5060950ff0a2098912f7889` |
| `android-info.txt` | 173 | `ab0a5063ac34b7d487c240d8f5b5229102344f7b58118516f52191deacd77a2d` |

`android-info.txt` 要求：`version-bootloader=ripcurrentpro-17.0-15819938`、`version-baseband=g5400c-260604-260807-B-16035863`、`board=tokay` 等。

---

## 3. 任务 C：用 stock header 重打包 boot.img

工具：`/opt/data/android/tokay/tools/mkbootimg`（`git clone --depth=1 https://android.googlesource.com/platform/system/tools/mkbootimg`，纯 python）。

### 3.1 字段逐项对比

| 字段 | stock `boot.img` | `dist/boot.img`（Kleaf 出的，用 `Image`） | **`boot-bakasu-susfs.img`（最终）** |
| --- | --- | --- | --- |
| file_size (B) | 67,108,864（补零到整个分区） | 67,108,864 | **16,838,656** |
| magic | `ANDROID!` | `ANDROID!` | `ANDROID!` |
| header_version | 4 | 4 | **4** |
| header_size | 1584 | 1584 | **1584** |
| pagesize | 4096（kernel 起始偏移实测 4096） | 4096 | **4096** |
| kernel_size | 16,637,222 | 36,039,168 | **16,831,884** |
| ramdisk_size | 0 | 0 | **0** |
| os_version | 0（未设置） | 0 | **0** |
| os_patch_level | 0（未设置） | 0 | **0** |
| cmdline | `""` | `""` | **`""`** |
| board | 空 | 空 | **空** |
| signature_size | 0 | 0 | **0** |
| kernel 载荷前 4 字节 | `02214c18`（lz4 legacy magic 0x184C2102） | `4d5a40fa`（未压缩 arm64 Image） | **`02214c18`（lz4）** |

除 `kernel_size` 与文件大小（我们不出 AVB 尾巴，不补零）外，**所有 header 字段与 stock 完全一致**。

### 3.2 打包命令

```bash
python3 tools/mkbootimg/mkbootimg.py \
  --header_version 4 --pagesize 4096 \
  --kernel out/kernel_aarch64/dist/Image.lz4 \
  --ramdisk <stock 的 0 字节 ramdisk> \
  --cmdline '' \
  -o artifacts/boot-bakasu-susfs.img
```

- stock 是 **lz4 legacy**内核（`0x184C2102`），我们的 `Image.lz4` 也是同一格式 → **不需要二次压缩**，直接把 `Image.lz4` 当 `--kernel` 传入。
- stock `boot.img` 的 ramdisk_size = 0（header v4 下 ramdisk 在 `init_boot`）→ 传 0 字节 ramdisk，保持 `ramdisk_size=0`。
- **未加 AVB footer**（无签名，靠 `--disable-verification` 关校验）。stock 那份 64MB 镜像里在 offset 16,642,048 有 `AVB0` vbmeta blob、末尾 offset 67,108,800 有 `AVBf` footer，我们都不复制。

### 3.3 验证（三层）

1. **header 回读**：对新镜像跑 `unpack_bootimg.py`，输出
   `header version 4 / kernel_size 16831884 / ramdisk 0 / cmdline '' / signature size 0`，与 stock 一致。
2. **kernel 载荷**：解出的 `kernel` sha256 = `d19b0b91b13bcbe6841f45ea2b01885383765e355d3b2f2d37c39a24731309ef`
   = `dist/Image.lz4` 的 sha256，**逐字节相同**。
3. **可解压性**：`lz4 -d` 解包 kernel 载荷 → 36,039,168 B，sha256 = `c7426d3f27e444576e264a259f7bb99c9b520ecb53b74d085d5564d7cac3b365`
   = `dist/Image`，说明镜像里的内核能被正常自解压（不是坏包）。

### 3.4 分区容量

| 项 | 值 |
| --- | --- |
| boot 分区大小（stock 镜像恰好填满） | 67,108,864 B = 64 MiB |
| 我们的镜像 | 16,838,656 B = 16.06 MiB |
| 占用 | 25.1%，**不超过 64MB** ✅ |

> 不带 AVB footer 的镜像比分区小是正常的；fastboot 只校验"镜像 ≤ 分区"。

---

## 4. 任务 D：管理器 APK 与刷机说明

### 4.1 APK

BakaSU 仓库（`Baka-SU/BakaSU`）**没有 GitHub Release**，但有 `Build Manager` workflow，最近一次成功运行是
`sync-up` 分支 `2026-11-16T03:33Z`（sha `252b1520`）。通过 nightly.link 取最新产物：

`https://nightly.link/Baka-SU/BakaSU/workflows/build-manager/sync-up/Manager-release.zip`
→ 内含 `BakaSU_v4.2.0-rc3_35277-universal-release.apk`

| APK | 版本 | 大小 (B) | SHA256 |
| --- | --- | --- | --- |
| `BakaSU_v4.2.0-rc3_35277-universal-release.apk`（主用） | 4.2.0-rc3 / 35277 | 21,316,980 | `aba0e48740a8b3c68e960f4ec3e7c65918574777e6964f2f9d74b8c49fc57628` |
| `KernelSU_v3.3.1_32680-release.apk`（备用） | 3.3.1 / 32680 | 13,637,206 | `b4a059ace71de2fa65cc7f12b1c58d55fc23ab25e057ee4230ce779742abe450` |

内核侧 BakaSU 版本是 `v4.2.0-rc3-5d6d1843`（version code 35261），管理器 35277 同版本线，来自同一仓库的更新提交，兼容。
BakaSU 驱动日志也写明 `Supported Managers: KernelSU Official, KOWSU, BakaSU`，官方 KernelSU 管理器同样可用。

### 4.2 刷机说明

`artifacts/FLASHING.md`（中文，**未实际刷机**），要点：

1. **备份**：`dd` 两个槽位的 `boot_a/b`、`init_boot_a/b`、`vendor_boot_a/b`、`vbmeta_a/b` 到 `/sdcard/kbackup` 并 `adb pull`。
2. **确认槽位**：`fastboot getvar current-slot`。
3. **刷入顺序**：`fastboot flash boot boot-bakasu-susfs.img`
   → `fastboot --disable-verity --disable-verification flash vbmeta stock/vbmeta.img`
   → 若现有 root 是 init_boot LKM，`fastboot flash init_boot stock/init_boot.img`（避免双 KSU）→ `fastboot reboot`。
4. **回滚**：把备份的 `boot`/`init_boot`/`vbmeta` 刷回；无法进 bootloader 则用 factory image 的 `flash-all.sh`。
5. **验证**：`uname -r` 应为 `6.1.176-android14-11-g45bc826d05a2`；`su -c 'ksu_susfs show version'`、`su -c 'ksu_susfs show enabled_features'`。
6. 明确禁止：不要 `fastboot flashing lock`。

---

## 5. 产物清单

### 5.1 交付物 `/opt/data/workspace/tokay-kernel/artifacts/`

| 文件 | 大小 (B) | SHA256 |
| --- | --- | --- |
| `boot-bakasu-susfs.img` | 16,838,656 | `542568ba7252d2872a7c24940e3c71efd35d959cdea17bfa7e1d6f6555596e02` |
| `BakaSU_v4.2.0-rc3_35277-universal-release.apk` | 21,316,980 | `aba0e48740a8b3c68e960f4ec3e7c65918574777e6964f2f9d74b8c49fc57628` |
| `KernelSU_v3.3.1_32680-release.apk` | 13,637,206 | `b4a059ace71de2fa65cc7f12b1c58d55fc23ab25e057ee4230ce779742abe450` |
| `FLASHING.md` | 5,787 | — |
| `stock/boot.img` | 67,108,864 | `09b48c9a3ed022fe63d29965dfc540d39da8e2eb1a9f5021b823279823b7e6ef` |
| `stock/init_boot.img` | 8,388,608 | `4dfb6ff7efeb98dc8bf40bdeb6f097a7808719775c84c423379984c11214bcdd` |
| `stock/vbmeta.img` | 12,288 | `5d6efbb001864fc9364de958536fda73ccaa0a3d21961234503437d227a4820f` |
| `stock/vendor_boot.img` | 67,108,864 | `0e601ee9a2b164583268ab75209e5cd90d411310e5060950ff0a2098912f7889` |

### 5.2 内核构建输出 `/opt/data/android/tokay/out/kernel_aarch64/dist/`（97 文件 778MB）

| 文件 | 大小 (B) | SHA256 |
| --- | --- | --- |
| `Image` | 36,039,168 | `c7426d3f27e444576e264a259f7bb99c9b520ecb53b74d085d5564d7cac3b365` |
| `Image.lz4` | 16,831,884 | `d19b0b91b13bcbe6841f45ea2b01885383765e355d3b2f2d37c39a24731309ef` |
| `Image.gz` | 14,283,653 | `d1c352d061a28c586ada3af1f876c618700183a88f6748ee094f3e6032ee466c` |
| `boot.img`（Kleaf 出的，未压缩内核，仅参考） | 67,108,864 | `54d05380b9a1174ff24d17ea3284df501742e07fa34eb2eb58406cd38952df8b` |
| `system_dlkm.img` | 12,234,752 | `68f87e7f5fac4c1995736bc1d512e3d69c4ed549d78a16167c2ca4c0cbf832ba` |
| `System.map` | 4,659,519 | `3928563f27084fb607697385d3f8f91347cdee8804e41ff50c55847604334000` |
| `vmlinux` | 353,613,560 | — |

---

## 6. 风险与遗留

1. **AVB 无签名**：`boot-bakasu-susfs.img` 不带 AVB footer/vbmeta。刷机必须同时关闭校验（`--disable-verity --disable-verification`），否则直接启动失败。这是设计选择，不是缺陷。
2. **模块兼容性**：内核 vermagic = `6.1.176-android14-11-g45bc826d05a2`；原厂 `system_dlkm` 模块是 `6.1.162-android14-11-g9dd05ae3a1de-ab16261587`、`vendor_dlkm` 是 `6.1.162-android14-11-gd7a0a08e0e15-ab16261946`。
   - `CONFIG_MODVERSIONS=y` 且模块带 CRC，`kernel/module/version.c:same_magic()` 在 `has_crcs` 为真时**跳过版本号那一段**，只比较 ` SMP preempt mod_unload modversions aarch64` → 版本号不同不会导致拒绝加载（原厂两个分区的版本号本来就互不相同，也印证了这一点）。
   - 真正的风险是 GKI 符号 CRC 不一致（dmesg 会出现 `disagrees about version of symbol`）。我们只加了 KSU/SUSFS，未改 GKI 公共符号，风险低但未在实机验证。
3. **SPL 的实际载体不是 boot header**：stock `boot.img` 的 `os_version/os_patch_level` 都是 0；SPL 2026-10 在 `init_boot.img`（`os version 17.0.0`，`os patch level 2026-10`）。本次不修改 init_boot，因此防回滚计数与 SPL 不受影响。想让 boot 头携带 SPL 是不可能的（stock 本身就没有），也不需要。
4. **设备当前是 init_boot LKM root**：刷内核态 KSU 后必须恢复官方 `init_boot`，否则两套 KSU 并存。已在 FLASHING.md 里写成第 3 步。
5. **未实机验证**：本次只做打包与静态验证（header/载荷/解压三重校验），没有刷机。首次上机建议留好备份、准备好 factory image。
6. **16K 页变体**：factory 包内 `kernel_16k` / `ramdisk_16k.img` 是 16KB 页测试件，本内核是 4KB 页，不可混用。

## 7. 复现命令

```bash
. /opt/data/tools/bin/android-env.sh
cd /opt/data/android/tokay/src
tools/bazel build --config=fast --config=stamp --jobs=6 --local_ram_resources=9216 \
  --defconfig_fragment=//common:bakasu_susfs.fragment //common:kernel_aarch64_dist
tools/bazel run  --config=fast --config=stamp --jobs=6 --local_ram_resources=9216 \
  --defconfig_fragment=//common:bakasu_susfs.fragment //common:kernel_aarch64_dist -- \
  --dist_dir=/opt/data/android/tokay/out/kernel_aarch64/dist
python3 /opt/data/android/tokay/tools/mkbootimg/mkbootimg.py \
  --header_version 4 --pagesize 4096 --kernel Image.lz4 \
  --ramdisk <0-byte file> --cmdline '' -o boot-bakasu-susfs.img
```
