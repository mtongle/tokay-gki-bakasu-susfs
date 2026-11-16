# tokay (Pixel 9) BakaSU+SUSFS 内核刷机说明

> 内核：`6.1.176-android14-11-g45bc826d05a2`（GKI android14-6.1-2026-09 + BakaSU v4.2.0-rc3(5d6d1843) + SUSFS v2.4.0，inline hook）
> 目标固件：CP3A.261005.005 / SPL 2026-10-05 / bootloader `ripcurrentpro-17.0-15819938`
> 镜像：`boot-bakasu-susfs.img`（16,838,656 B，SHA256 `542568ba7252d2872a7c24940e3c71efd35d959cdea17bfa7e1d6f6555596e02`）

**本文档只描述步骤，未在真机上执行过。刷机前请先完成第 1 节备份。**

---

## 0. 前提

- bootloader 已解锁（`fastboot flashing unlock` 已做，OEM 解锁开关保持打开）。
- 主机装好 platform-tools（`fastboot` / `adb`），设备能进 bootloader：`adb reboot bootloader`。
- 以下文件都在 `artifacts/` 下：
  - `boot-bakasu-susfs.img` —— 本次要刷的内核
  - `stock/boot.img`、`stock/init_boot.img`、`stock/vbmeta.img` —— 官方 CP3A.261005.005 原厂镜像（回滚用；vbmeta 本次不刷，仅留档）
  - `BakaSU_v4.2.0-rc3_35277-universal-release.apk` —— 管理器（与内核同版本线）

## 1. 备份（设备上，需要现有 root）

```bash
adb shell su -c 'ls -l /dev/block/by-name/ | grep -E "boot|init_boot|vbmeta"'
adb shell su -c 'mkdir -p /sdcard/kbackup'
# 备份两个槽位的四个分区（Pixel 9 均为 A/B）
for p in boot_a boot_b init_boot_a init_boot_b vendor_boot_a vendor_boot_b vbmeta_a vbmeta_b; do
  adb shell su -c "dd if=/dev/block/by-name/$p of=/sdcard/kbackup/$p.img"
done
adb pull /sdcard/kbackup ./kbackup
```

校验备份完整性（可选但推荐）：

```bash
adb shell su -c 'sha256sum /sdcard/kbackup/*.img'
sha256sum kbackup/*.img
```

> **A/B 设备没有 `/dev/block/by-name/boot` 这个节点**，真实节点是 `boot_a` / `boot_b`。
> 只备当前槽位可以用：
> ```bash
> adb shell su -c 'S=$(getprop ro.boot.slot_suffix); dd if=/dev/block/by-name/boot$S of=/sdcard/boot$S.img; dd if=/dev/block/by-name/init_boot$S of=/sdcard/init_boot$S.img'
> adb pull /sdcard/boot_a.img . 2>/dev/null || adb pull /sdcard/boot_b.img .
> ```

> 如果当前 root 是 init_boot LKM 方式（SukiSU/KernelSU LKM），`init_boot_a.img` 备份里含 `kernelsu.ko`，
> 回滚到「原有 root 状态」就靠它。

## 2. 确认槽位

```bash
adb shell getprop ro.boot.slot_suffix      # 例：_a
fastboot getvar current-slot               # 例：a
```

下文用 `$SLOT` 表示当前槽位（`a` 或 `b`）。**只刷当前槽位即可**，另一槽保持原样作为回退。

## 2.5 先判断当前 root 是 GKI 还是 LKM

```bash
adb shell su -c 'lsmod | grep -i kernelsu'      # 有输出 = LKM 模式
adb shell getprop ro.boot.slot_suffix
```
更可靠的是看 SukiSU 管理器首页显示的模式（GKI / LKM）。

- **GKI（内置内核）**：`init_boot` 本来干净，SukiSU 在 `boot` 里 → 直接刷 AK3 包/刷 boot 即可，
  不用碰 `init_boot`；开机后卸载 SukiSU 管理器、装 BakaSU 管理器。
- **LKM（`init_boot` 里有 kernelsu.ko）**：必须同时把 `init_boot` 还原成原厂，否则内核里的 BakaSU
  与 LKM 两套 root 会在开机时同时初始化并冲突。建议直接 fastboot 两个一起刷，不要在管理器里刷完就重启。

## 3. 刷入顺序

```bash
adb reboot bootloader
fastboot devices                            # 确认能看到设备

# (1) 内核本体
fastboot flash boot boot-bakasu-susfs.img

# (2) 不要刷 vbmeta！
#     解锁后 verifiedbootstate=orange 只说明 bootloader 已解锁，bootloader 在解锁状态下
#     本来就容忍 boot/init_boot 签名不符，换 boot 不需要关 verity/verification。
#     反过来，在原本正常的系统上改 vbmeta 的 verity 标志，才容易触发
#     「Cannot load Android system. Your data may be corrupt」那条恢复出厂提示。

# (3) 若当前 root 是 init_boot LKM 方式，刷回官方 init_boot，避免内核内 KSU 与 LKM KSU 并存
fastboot flash init_boot stock/init_boot.img

fastboot reboot
```

- A/B 设备上 `fastboot flash boot` / `flash init_boot` 默认写入**当前槽位**。
  想两个槽位都写：`fastboot --slot=all flash boot boot-bakasu-susfs.img`（但请确认另一槽的 boot 也一并替换，否则回退时会踩到未签名的旧槽）。
- **本次全程不碰 vbmeta**：只在 boot（必要时 init_boot）上动手，`/data` 的加密链（fileencryption + metadata_encryption，密钥在 Titan M2 Weaver + `/metadata`）完全不受影响。
- 不要 `fastboot flashing lock`（重新上锁会校验失败，直接把设备变砖）。

## 4. 刷后验证

```bash
adb wait-for-device
adb shell uname -r
# 期望：6.1.176-android14-11-g45bc826d05a2

adb shell su -c 'cat /proc/version'
adb shell su -c 'ksu_susfs show version'
adb shell su -c 'ksu_susfs show enabled_features'
```

- `su` 能拿到 root → 内核态 KernelSU 生效。
- `ksu_susfs` 是 SUSFS 的**用户态 CLI**（来自 susfs4ksu 仓库，不随内核打包）。
  若提示 `command not found`，先安装对应 SUSFS 用户态工具/模块，再用 `dmesg | grep -i susfs` 兜底确认。
- 管理器首次启动应显示「已授权 / LKM 未安装」以外的**内核态工作模式**（不是 LKM 模式）。

## 5. 回滚

任一情况（无法开机、卡 logo、频繁重启）：

```bash
adb reboot bootloader   # 或 长按电源+音量减 进 bootloader

fastboot flash boot       kbackup/boot_a.img        # 换成自己的槽位文件名
fastboot flash init_boot  kbackup/init_boot_a.img
fastboot reboot
```

- 本次全程没动 vbmeta，所以回滚也不需要恢复 vbmeta（除非你之前手动改过它）。

- 如果连 bootloader 都进不去，用官方 factory image 的 `flash-all.sh` 全量恢复（会清数据）。
- 回滚顺序建议：只回 `boot`（和需要时的 `init_boot`）；vbmeta 本次没动过，不需要回。

## 6. 已知风险 / 注意

| 项 | 说明 |
| --- | --- |
| 无 AVB 签名 | 镜像里没有 AVB footer。bootloader 已解锁（orange）时本来就容忍签名不符，**不需要也不应该**改 vbmeta 的 verity 标志 |
| 分区容量 | boot 分区 64 MiB（67,108,864 B），本镜像 16.06 MiB，占比 25%，余量充足 |
| 模块兼容 | 本内核 vermagic = `6.1.176-android14-11-g45bc826d05a2`；原厂 system_dlkm / vendor_dlkm 模块是 `6.1.162-...`。因 `CONFIG_MODVERSIONS=y` 且模块带 CRC，`same_magic()` 只比较版本号之后的字段，版本号不同**不会**被拒；真正的风险是 GKI 符号 CRC 不一致（dmesg 会出现 `disagrees about version of symbol`） |
| system_dlkm | 不强制刷新；若要统一，可刷 `dist/system_dlkm.img`（12,234,752 B，来自本次构建），但需先确认分区容量 |
| SPL / 防回滚 | boot.img 头里 `os_version=0`，SPL 实际由 `init_boot`（`17.0.0 / 2026-10`）承载；本次不改 init_boot，防回滚计数不受影响 |
| 16K 页 | factory zip 里的 `kernel_16k` / `ramdisk_16k.img` 是 16KB 页测试用；本内核按 4KB 页构建（header pagesize=4096），**不要**混用 |
| 数据 | 刷 `boot` / `init_boot` 不清数据；本次不动 verity 与 vbmeta，不存在「首次关闭 verity 要求恢复出厂」那类风险 |
