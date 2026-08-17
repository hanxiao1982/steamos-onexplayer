# Bazzite / CachyOS 的 OneXPlayer 内核适配调研

本文记录两个发行版里 OXP 相关内核模块的源文件位置，以及各自制作、合入内核 patch 的流程。新掌机适配通常要同时改内核 DMI/EC 映射和用户态设备配置。

## 结论先看

两边都不是自己维护一份独立的 `oxp.ko` 源码树。风扇 / EC 走主线 `oxpec`，按键 / RGB / 手柄配置走主线 `hid-oxp`。发行版只是：

1. 用比主线更新的 DMI 条目或 quirk 做 backport
2. 再叠一层用户态做按键映射、TDP、风扇曲线

**只适配这两个系统的最新版本时，可以不改 HHD。** 按键映射只走 InputPlumber。TDP / 风扇不在 InputPlumber 里，走 PowerStation + steamos-manager，外加内核 `oxpec` 的 hwmon。详见 [第 4 节](#4-用户态只适配最新版可以不改-hhd)。

| 功能 | 内核模块 | 主线源文件 | 最新版用户态（不要再写 HHD） |
| --- | --- | --- | --- |
| 风扇、EC PWM、Turbo 接管、充电限制 | `oxpec`（旧名 `oxp-sensors`） | `drivers/platform/x86/oxpec.c` | `oxpec` hwmon；Steam UI 经 steamos-manager `FanControl1` |
| RGB、手柄模式、硬件级按键映射 | `hid-oxp` | `drivers/hid/hid-oxp.c` | InputPlumber + 可选 `hid-oxp` sysfs |
| TDP | 一般不在 `oxpec` 里 | AMD: `amd_pstate` / SMU；部分机型 `acpi_call` | PowerStation + steamos-manager `TdpLimit1` |
| 手柄/快捷键映射 | `hid-oxp` + evdev | 同上 | InputPlumber `50-onexplayer_*.yaml` |

新机最常见的内核改动就是：在 `oxpec.c` 的 `dmi_table[]` 里加一条 `DMI_BOARD_NAME`，并把它绑到已有 board 变体（`oxp_fly` / `oxp_x1` / `oxp_2` 等）。APEX 就是这样绑到 `oxp_fly` 的。

---

## 1. 主线内核：真正的 OXP 模块源码

两个发行版最终都编译这份主线驱动（或带少量 backport 的同一份文件）。

### 1.1 `oxpec`：EC / 风扇 / Turbo / 充电

- 源文件：<https://github.com/torvalds/linux/blob/master/drivers/platform/x86/oxpec.c>
- Kconfig：`drivers/platform/x86/Kconfig` → `CONFIG_OXPEC`（旧名 `CONFIG_SENSORS_OXP`）
- Makefile：`drivers/platform/x86/Makefile` → `oxpec.o`
- 文档：历史上是 `Documentation/hwmon/oxp-sensors.rst`；驱动从 `drivers/hwmon/oxp-sensors.c` 迁到 `platform/x86` 后，模块名仍常被叫 `oxp-sensors` / `oxpec`
- 加载后的 sysfs：
  - 风扇：`/sys/class/hwmon/hwmon*/{fan1_input,pwm1,pwm1_enable}`
  - Turbo 开关：`/sys/devices/platform/oxp-platform/tt_toggle`（或 `oxpec` 平台设备下）

驱动用 DMI `BOARD_VENDOR` + `BOARD_NAME` 选 board 变体，再按变体读写不同 EC 寄存器。

当前主线已识别的 OneXPlayer / AOKZOE board 变体：

| `enum oxp_board` | 代表机型 | 风扇 RPM | PWM enable / duty | Turbo 寄存器 |
| --- | --- | --- | --- | --- |
| `oxp_mini_amd` / `oxp_mini_amd_a07` / `oxp_mini_amd_pro` | ONE XPLAYER、mini A07、Mini Pro | `0x76` | `0x4A` / `0x4B` | Mini A07: `0x1E`；Pro: `0xF1` |
| `oxp_2` | ONEXPLAYER 2 系列 | `0x58` | 同上 | `0xEB` |
| `oxp_fly` | F1 / F1Pro / APEX 等 | `0x76` | 同上 | `0xF1` |
| `oxp_x1` | X1 / X1Pro / X1 mini 等 | `0x58` | 同上 | `0xEB`，LED `0x57`，充电 `0xA3`/`0xA4` |
| `oxp_g1_a` / `oxp_g1_i` | G1 A、SUPER X、G1 i | 按 G1 逻辑 | 同上 | 机型相关 |

主线 `dmi_table[]` 里已经有的 OXP 板名（`DMI_BOARD_NAME`，vendor 均为 `ONE-NETBOOK`）：

- `ONE XPLAYER`
- `ONEXPLAYER 2`（前缀匹配）
- `ONEXPLAYER APEX`
- `ONEXPLAYER F1` / `F1 EVA-01` / `F1 OLED` / `F1L` / `F1Pro` / `F1 EVA-02`
- `ONEXPLAYER G1 A` / `G1 i` / `SUPER X`
- `ONEXPLAYER mini A07` / `Mini Pro`
- `ONEXPLAYER X1z` / `X1 A` / `X1 i` / `X1Air` / `X1 mini` / `X1Mini Pro` / `X1Pro` / `X1Pro EVA-02`

OGC 的 `features/onexplayer` 分支还多了 `ONEXPLAYER X2Mini PRO`，以及 X1 / Super X 的平板模式（pogo 键盘热插拔）。

典型新机 patch（APEX，已进 stable 6.18/6.19）：

```c
{
    .matches = {
        DMI_MATCH(DMI_BOARD_VENDOR, "ONE-NETBOOK"),
        DMI_EXACT_MATCH(DMI_BOARD_NAME, "ONEXPLAYER APEX"),
    },
    .driver_data = (void *)oxp_fly,
},
```

如果新机 EC 布局和现有变体不同，才需要加新的 `enum oxp_board` 和寄存器常量，而不是只加 DMI。

### 1.2 `hid-oxp`：RGB / 手柄模式 / 硬件按键映射

- 源文件：<https://github.com/torvalds/linux/blob/master/drivers/hid/hid-oxp.c>
- Kconfig：`drivers/hid/Kconfig` → `CONFIG_HID_OXP`
- Makefile：`drivers/hid/Makefile` → `hid-oxp.o`
- HID ID：`drivers/hid/hid-ids.h`
- 维护者：Derek J. Clark，邮件列表 `linux-input@vger.kernel.org`
- 进入主线时间：Linux 7.2 周期（Valve 版权）

两代 HID 协议：

- Gen1（F1 系列）：只做 RGB
- Gen2（X1 mini、G1、AOKZOE A1X）：RGB + 硬件按键映射 + 手柄模式 + 震动强度
- 混合 MCU（G1、APEX）：用 DMI 跳过 Gen2 RGB，避免冲突

`hid-oxp.c` 里也有 DMI quirk，例如 APEX / G1 A / G1 i 的 `oxp_hybrid_mcu_list[]`。

### 1.3 旧路径（不要再改）

- `drivers/hwmon/oxp-sensors.c`：6.2 引入，后来整文件迁到 `oxpec.c`
- HHD README 仍可能链到旧路径，以 `oxpec.c` 为准

---

## 2. Bazzite：模块从哪来、patch 怎么做

Bazzite 是 Fedora / Universal Blue 的不可变镜像。掌机内核已经从自建 `kernel-bazzite` 迁到 Open Gaming Collective（OGC）。

### 2.1 当前有效仓库

| 角色 | 仓库 | 说明 |
| --- | --- | --- |
| 内核源码（含 OXP 主题分支） | [OpenGamingCollective/linux](https://github.com/OpenGamingCollective/linux) | stable 镜像 + 主题分支；OXP 分支是 `features/onexplayer` |
| 打包 / 签名 OCI | [OpenGamingCollective/kernel-packages](https://github.com/OpenGamingCollective/kernel-packages) | Fedora spec + 把 `monolithic.patch` 打进 kernel.org tarball |
| 发行版镜像 | [ublue-os/bazzite](https://github.com/ublue-os/bazzite) | 消费 OGC 内核 RPM/OCI，不直接改 `oxpec.c` |
| 已归档旧内核 | [bazzite-org/kernel-bazzite](https://github.com/bazzite-org/kernel-bazzite) | 曾用 `patch-handheld.patch`；**不要再对它提 PR** |

OGC 明确要求 **upstream-first**：合进 OGC 的补丁至少要已经发到 LKML 评审。

### 2.2 Bazzite 侧 OXP 源文件位置

在 OGC 树里和主线相同：

```
OpenGamingCollective/linux
├── drivers/platform/x86/oxpec.c      # EC / 风扇
├── drivers/platform/x86/Kconfig      # CONFIG_OXPEC
├── drivers/hid/hid-oxp.c             # RGB / 按键映射
├── drivers/hid/hid-ids.h
└── drivers/hid/Kconfig               # CONFIG_HID_OXP
```

开发分支：

```
https://github.com/OpenGamingCollective/linux/tree/features/onexplayer
```

该分支比主线多的内容包括：

- `ONEXPLAYER X2Mini PRO` DMI
- X1 / Super X 的 `SW_TABLET_MODE`（pogo 键盘 VID/PID：`1a86:1305`、`258a:001e`）

打包时，OGC 把主题分支收成一份 `monolithic.patch`，挂在 [OpenGamingCollective/linux releases](https://github.com/OpenGamingCollective/linux/releases)。`kernel-packages` 的 Fedora 流程是：

1. 下载 kernel.org `linux-<ver>.tar.xz`
2. `patch -Np1 < monolithic.patch`
3. 用 `fedora/kernel.spec` + `fedora/config` 打 RPM / OCI

Bazzite 再把这份内核装进镜像。2026 年 4 月 testing 已经出现 `6.19.10 OGC` 这类版本号。

### 2.3 历史流程（仅作对照）

旧 `kernel-bazzite` README 写得很清楚：

1. 补丁先在 [hhd-dev/patchwork](https://github.com/hhd-dev/patchwork) 相对 Fedora ARK 变基
2. 自动生成 `patch-handheld.patch` / `handheld.patch`
3. **不要直接改生成出来的 patch 文件，也不要对该仓提 PR**
4. 缺补丁时开 issue，附 lore.kernel.org 或 patch 链接

这个仓已归档。新工作走 OGC + LKML。

### 2.4 现在给 Bazzite 做 OXP 内核 patch 的流程

推荐顺序：主线 → OGC → Bazzite 自然吃到。

#### A. 只加 DMI（最常见）

1. 在真机上读 DMI，不要猜：

   ```bash
   cat /sys/class/dmi/id/board_vendor
   cat /sys/class/dmi/id/board_name
   cat /sys/class/dmi/id/sys_vendor
   cat /sys/class/dmi/id/product_name
   ```

2. 对照 `oxpec.c` 里已有变体，确认风扇 / PWM / Turbo 寄存器是否相同。可用 `ec_sys` 或厂商 EC dump 对比。
3. 在 `oxpec.c` 的 `dmi_table[]` 加条目；如需 hybrid MCU，同步改 `hid-oxp.c` 的 DMI 表。
4. 按 kernel 规范做 patch：

   ```bash
   git clone https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git
   cd linux
   git checkout -b oxp-<model>
   # 编辑 drivers/platform/x86/oxpec.c （以及 hid-oxp.c）
   git add -A
   git commit -s
   git format-patch -1
   ```

5. 发到 LKML：

   - `oxpec`：`platform-driver-x86@vger.kernel.org`，抄送 `lkml@antheas.dev`、`derekjohn.clark@gmail.com`
   - `hid-oxp`：`linux-input@vger.kernel.org`，抄送 Derek J. Clark
   - 标题示例：`[PATCH] platform/x86: oxpec: Add support for OneXPlayer <MODEL>`

6. 同时给 OGC 一条可跟踪的路径（任选）：
   - 对 [OpenGamingCollective/linux](https://github.com/OpenGamingCollective/linux) 的 `features/onexplayer` 开 PR（commit 信息常带 `[FROM-ML]`，表示来自邮件列表）
   - 或在 OGC / Bazzite 开 issue，附 lore 链接

7. 不要向已归档的 `kernel-bazzite` 提改 `handheld.patch` 的 PR。

#### B. 本地验证（Bazzite 不可变系统）

Bazzite 不能直接 `make modules` 装进 `/usr` 后指望下次更新还在。可选：

- 用 OGC / Fedora 方式打带补丁的内核 RPM，再 `rpm-ostree override replace`
- 或临时 DKMS / 自编译 `.ko`（Secure Boot 会拦未签名模块；APEX 社区插件就是这么做的）

社区参考：<https://github.com/srsholmes/onexplayer-apex-bazzite-fixes>（在上游 DMI 进 Bazzite 内核之前，用捆绑 `oxpec.ko` 顶一下）。

---

## 3. CachyOS：模块从哪来、patch 怎么做

CachyOS 是 Arch 系。掌机官方内核是 `linux-cachyos-deckify`，不是默认的 `linux-cachyos`。Wiki 写明：掌机不要换别的 flavor。

### 3.1 当前有效仓库

| 角色 | 仓库 | 说明 |
| --- | --- | --- |
| 内核 git 树 | [CachyOS/linux](https://github.com/CachyOS/linux) | 基于上游 stable，合并 Cachy 主题分支 |
| PKGBUILD | [CachyOS/linux-cachyos](https://github.com/CachyOS/linux-cachyos) | 各 flavor 的打包脚本 |
| 补丁仓 | [CachyOS/kernel-patches](https://github.com/CachyOS/kernel-patches) | 按主版本号分目录 |
| 掌机 flavor | `linux-cachyos/linux-cachyos-deckify/PKGBUILD` | 额外打 `0001-handheld.patch` |

Wiki：<https://wiki.cachyos.org/features/kernel/>

### 3.2 CachyOS 侧 OXP 源文件位置

**默认就已经有主线 `oxpec` /（足够新的版本还有）`hid-oxp`。** 源码在编译用的内核树里，路径与主线相同：

```
CachyOS/linux  （或解包后的 linux-<ver>/）
├── drivers/platform/x86/oxpec.c
└── drivers/hid/hid-oxp.c
```

掌机额外补丁不单独拆 `oxp-*.patch`，而是揉进：

```
https://github.com/CachyOS/kernel-patches/blob/master/<MAJOR>/misc/0001-handheld.patch
```

例如：

- `6.19/misc/0001-handheld.patch`
- `7.0/misc/0001-handheld.patch`
- `7.1/misc/0001-handheld.patch`

`7.2/misc/` 目前没有 `0001-handheld.patch`（2026-08 调研时）。新工作应对准当前 deckify 实际使用的 `<MAJOR>`。

`linux-cachyos-deckify/PKGBUILD` 关键片段：

```bash
_patchsource="https://raw.githubusercontent.com/cachyos/kernel-patches/master/${_major}"
source=(
    "https://github.com/CachyOS/linux/releases/download/${_srcname}/${_srcname}.tar.gz"{,.asc}
    "config"
    "${_patchsource}/misc/0001-acpi-call.patch"
    "${_patchsource}/misc/0001-handheld.patch"
)
```

`prepare()` 对 `source` 里所有 `*.patch` 执行 `patch -Np1`。同文件还会打开掌机相关 Kconfig（Steam Deck、Ally、MSI Claw、`ACPI_CALL` 等）。`oxpec` / `HID_OXP` 一般已在 base config 里，不必再写一遍。

### 3.3 给 CachyOS 做 OXP 内核 patch 的流程

CachyOS 接受 GitHub PR，比 Bazzite/OGC 更直接。

#### A. 合进官方内核（推荐）

1. 同样先在真机确认 DMI，并尽量先向上游发 patch（Cachy 也倾向吃主线）。
2. Fork [CachyOS/kernel-patches](https://github.com/CachyOS/kernel-patches)。
3. 在对应版本目录改或追加补丁：
   - 小改（只加 DMI）：直接改 `<MAJOR>/misc/0001-handheld.patch`，或再放一个 `misc/0002-oxp-<model>.patch`
   - 新文件更干净，但 deckify 的 `source=()` **必须加上这个 URL**，否则 `makepkg` 不会下载、也不会 apply
4. 若只改 `kernel-patches` 里已有的 `0001-handheld.patch`，deckify PKGBUILD 不用动（它已经引用该文件）。
5. 提 PR，说明机型 DMI、EC 变体、测试情况。README 原文：fork + PR，并写清补丁做什么。
6. 建议同步在 [CachyOS/linux-cachyos](https://github.com/CachyOS/linux-cachyos) 开 issue，让 deckify 维护者知道掌机需求。Wiki 也说改进默认内核请开 issue。

#### B. 本地重建 deckify 做验证

```bash
git clone https://github.com/CachyOS/linux-cachyos.git
cd linux-cachyos/linux-cachyos-deckify

# 把自有 patch 放进目录，并加入 PKGBUILD 的 source=()
# 例如：0002-oxp-new-model.patch

updpkgsums          # 或 makepkg 时用 --skipchecksums 做试验
makepkg -s
sudo pacman -U linux-cachyos-deckify-*.pkg.tar.zst
```

`prepare()` 会自动 apply 所有 `*.patch`。注意：

- 补丁相对内核树根，`patch -Np1`
- 必须能打在 CachyOS 已经打过 base / handheld 之后的树上
- 内核大版本升级后要 rebase 到新的 `<MAJOR>/misc/`

#### C. 用户自己打补丁（论坛标准答法）

[CachyOS 论坛：How to rebuild a kernel with an additional patch](https://discuss.cachyos.org/t/how-to-rebuild-a-kernel-with-an-additional-patch/16495)

1. 复制官方 PKGBUILD + `config`
2. 把 `.patch` 放进同目录并写入 `source`
3. `makepkg`

这只适合本机试验，要让所有 Cachy 掌机用户受益，仍需 PR 进 `kernel-patches`。

---

## 4. 用户态：只适配最新版可以不改 HHD

内核 `oxpec` 只提供 hwmon PWM 和少量 EC 属性。按键、TDP、风扇曲线仍要用户态。两边最新官方栈已经不用 HHD。

### 4.1 结论：可以跳过 HHD，但不能只改 InputPlumber

| 问题 | 答案 |
| --- | --- |
| 最新 Bazzite / CachyOS Handheld 还默认装 HHD 吗？ | **不装。** 可以不为这两个系统写 HHD `const.py`。 |
| 按键 / 背键 / 快捷键 / 手柄模拟只改 InputPlumber 够吗？ | **够。** 这是官方输入栈。 |
| TDP / 风扇曲线只改 InputPlumber 够吗？ | **不够。** InputPlumber 不管功耗和风扇。 |

HHD 现在只是可选回退：CachyOS 仓库里还有 `hhd` 包，和 InputPlumber 会抢手柄，官方镜像不会自动启用。旧文档（`docs.bazzite.gg` 掌机页、`CachyOS-Handheld` README 里 Legion 仍写 HHD）已经过时，以镜像和 chwd 实际安装的包为准。

### 4.2 查证：两边最新镜像装的是什么

**Bazzite**

- 2026-01 官方公告（[A brighter future for Bazzite](https://universal-blue.discourse.group/t/a-brighter-future-for-bazzite/11575)）：HHD 不再更新，改用 InputPlumber，与 SteamOS / ChimeraOS / Nobara / CachyOS Handheld 对齐。原因包括 HHD 维护者已离开项目，Bazzite 当时是唯一还在发 HHD 的发行版。
- 2026-03-16 合入 [ublue-os/bazzite `ce953e4`](https://github.com/ublue-os/bazzite/commit/ce953e4306f2effa58f2fbb8a833081685aa5424)：从镜像去掉 HHD 服务、polkit、COPR，改装 InputPlumber / OpenGamepadUI / PowerStation。
- 当前 `main` 的 `Containerfile` 掌机包是 `inputplumber`、`steamos-manager-powerstation`、`steamos-manager-powerstation-gamescope-session-plus`，并 `systemctl enable inputplumber.service` 与 `steamos-manager.service`。没有 `hhd`。
- testing 镜像（例如 `testing-44.20260807`）包列表是 InputPlumber 0.78 + PowerStation，没有 HHD。

**CachyOS Handheld**

- 2026-01 发行说明：硬件探测从 HHD 换成 `steamos-manager` + `inputplumber`。
- 当前 [chwd `profiles/pci/handhelds/profiles.toml`](https://github.com/CachyOS/chwd/blob/master/profiles/pci/handhelds/profiles.toml) 通用掌机配置：

  ```toml
  packages = 'steamos-manager inputplumber steamos-powerbuttond'
  ```

  没有 `hhd`。`hwd_product_name_pattern` 已覆盖一批 OXP / AOKZOE 的 `product_name`（`ONE XPLAYER`、`ONEXPLAYER F1*`、`X1*`、`G1*` 等）。新机若不在这个正则里，安装器不会自动装这组包。
- `CachyOS-Handheld` README 仍写 Legion 默认 HHD，与当前 chwd 不符，以 chwd 为准。
- 仓库里仍有 `hhd` 包（例如 4.1.8），只供用户手动装；和 InputPlumber 互斥。

### 4.3 按键映射：只走 InputPlumber

仓库：<https://github.com/ShadowBlip/InputPlumber>

```
rootfs/usr/share/inputplumber/devices/50-onexplayer_*.yaml
rootfs/usr/share/inputplumber/capability_maps/onexplayer_type*.yaml
rootfs/usr/lib/udev/hwdb.d/60-inputplumber-autostart.hwdb
src/drivers/oxp_hid/          # HID 厂商报告（背键 M1/M2 等）
src/drivers/oxp_tty/          # 串口协议
src/input/source/hidraw/oxp_hid.rs
```

已有设备 YAML：

- `50-onexplayer_amd.yaml` / `50-onexplayer_intel.yaml`
- `50-onexplayer_mini_a07.yaml` / `50-onexplayer_mini_pro.yaml`
- `50-onexplayer_2.yaml` / `50-onexplayer_onexfly.yaml`
- `50-onexplayer_x1.yaml` / `50-onexplayer_g1.yaml` / `50-onexplayer_apex.yaml`
- `50-aokzoe_a1.yaml`

新机通常：复制最接近的 YAML → 改 DMI `product_name` → 选或新建 capability map → 把 DMI 加进 `60-inputplumber-autostart.hwdb`。X1 / APEX 这类带厂商 HID（`1a86:fe00`）的机型，还可能要动 `src/drivers/oxp_hid/`。

探测用的是 `product_name`，和内核 `oxpec` 用的 `board_name` 可能不同，两边都要采。

CachyOS 还要把新 `product_name` 写进 chwd `hwd_product_name_pattern`，否则新装不会拉 InputPlumber。

### 4.4 TDP / 风扇：InputPlumber 不管，走 PowerStation + steamos-manager

| 组件 | 仓库 | 职责 |
| --- | --- | --- |
| PowerStation | [ShadowBlip/PowerStation](https://github.com/ShadowBlip/PowerStation) | 通用 CPU/GPU TDP D-Bus；Bazzite 用它给 Steam 滑条垫底 |
| steamos-manager | [OpenGamingCollective/steamos-manager](https://github.com/OpenGamingCollective/steamos-manager)（CachyOS 也用同系包） | Steam 客户端的 `TdpLimit1` / `FanControl1` / GPU 时钟等 |
| `oxpec` hwmon | 内核 | 风扇 PWM 实际写入点 |

PowerStation 主要是通用 AMD/Intel sysfs，不是 HHD 那种按机型写 EC 的表。新机 TDP 往往不用新 YAML，只要 SMU / `amd_pstate` 能写；若 Steam 滑条范围不对，再查 PowerStation 的 DMI platform override，或 steamos-manager 的设备/remote 配置。

风扇曲线：先保证 `oxpec` 认出 DMI 并出现 `pwm1`。Steam UI 风扇要 steamos-manager 实现 `FanControl1`（本机或 `remotes.d` 远程）。这不是 InputPlumber 的活。

Intel OXP 很多本来就没有可靠的 Linux TDP 接口，HHD 当年也标 `w/o TDP`。换栈不会 magically 补上。

### 4.5 HHD 仅作历史对照（最新版不必改）

仓库：<https://github.com/hhd-dev/hhd>，路径 `src/hhd/device/oxp/const.py`。

只有这些情况才需要碰它：给旧 Bazzite / 手动装 HHD 的 CachyOS 用户、或对照旧机协议（`hid_v1` / `serial` / `mixed`）。官方最新镜像不会加载这份配置。Adjustor 已并入 hhd v4，仓已归档。

---

## 5. 新掌机适配清单

按依赖顺序做，避免只改一边。

1. **采集 DMI 和 EC**
   - `board_vendor` / `board_name` / `product_name` / `sys_vendor`
   - EC 风扇、PWM、Turbo 寄存器是否与 `oxp_fly` / `oxp_x1` / `oxp_2` 相同
   - HID：`lsusb` / `hidraw`，看是否为 `1a86:fe00` 这类 OXP MCU
2. **内核 `oxpec`**
   - 相同 EC：只加 DMI → 已有变体
   - 不同 EC：新 `oxp_board` + 寄存器宏 + read/write 分支
3. **内核 `hid-oxp`**
   - 需要 RGB / 硬件映射 / hybrid MCU 时加 HID ID 或 DMI quirk
4. **把补丁送进发行版**
   - Bazzite：LKML + OGC `features/onexplayer`（不要改已归档 kernel-bazzite）
   - CachyOS：`kernel-patches/<MAJOR>/misc/` + deckify `source`（如新增文件）
5. **用户态按键（最新版只改 InputPlumber，不改 HHD）**
   - `50-onexplayer_<model>.yaml` + capability map + `60-inputplumber-autostart.hwdb`
   - 厂商 HID 机型：`src/drivers/oxp_hid/`
   - CachyOS：把 `product_name` 加进 chwd `handhelds/profiles.toml` 的正则
6. **TDP / 风扇（不是 InputPlumber）**
   - 风扇：先让 `oxpec` 出 hwmon；再确认 steamos-manager `FanControl1`
   - TDP：PowerStation + steamos-manager；AMD 确认 SMU 可写。Intel 多数仍无 TDP

---

## 6. 两边流程对照

```
                         主线 Linux
                    oxpec.c    hid-oxp.c
                         |          |
          ---------------+----------+---------------
          |                                     |
          v                                     v
  OpenGamingCollective/linux              CachyOS/linux
  branch: features/onexplayer             + kernel-patches
  -> monolithic.patch                     <MAJOR>/misc/0001-handheld.patch
  -> kernel-packages                      -> linux-cachyos-deckify PKGBUILD
  -> Bazzite ostree
          |                                     |
          v                                     v
  InputPlumber + PowerStation             InputPlumber + steamos-manager
  50-onexplayer_*.yaml                    同上 YAML；chwd profiles.toml
```

| 步骤 | Bazzite / OGC | CachyOS |
| --- | --- | --- |
| 源码编辑点 | `OpenGamingCollective/linux` 的 `oxpec.c` / `hid-oxp.c` | 同上主线文件；发行版增量在 `CachyOS/kernel-patches` |
| 补丁形态 | 主题分支 commit + 发布 `monolithic.patch` | `<MAJOR>/misc/*.patch`，`patch -Np1` |
| 合入方式 | **先 LKML**，再 OGC PR/issue；禁止改归档 `handheld.patch` | **GitHub PR** 到 `kernel-patches`；新文件还要改 deckify `source` |
| 本地验证 | 自编译模块 / rpm-ostree 换核 | 改 deckify PKGBUILD 后 `makepkg` |
| 掌机目标内核 | OGC 内核（Bazzite 镜像自带） | `linux-cachyos-deckify` |

---

## 7. 参考链接

- 主线 `oxpec`：<https://github.com/torvalds/linux/blob/master/drivers/platform/x86/oxpec.c>
- 主线 `hid-oxp`：<https://github.com/torvalds/linux/blob/master/drivers/hid/hid-oxp.c>
- APEX DMI 补丁（lore）：<https://lists.openwall.net/linux-kernel/2026/02/23/1626>
- OGC 内核：<https://github.com/OpenGamingCollective/linux/tree/features/onexplayer>
- OGC 打包：<https://github.com/OpenGamingCollective/kernel-packages>
- 旧 Bazzite 内核（归档）：<https://github.com/bazzite-org/kernel-bazzite>
- CachyOS 补丁仓：<https://github.com/CachyOS/kernel-patches>
- CachyOS deckify PKGBUILD：<https://github.com/CachyOS/linux-cachyos/blob/master/linux-cachyos-deckify/PKGBUILD>
- InputPlumber：<https://github.com/ShadowBlip/InputPlumber>
- PowerStation：<https://github.com/ShadowBlip/PowerStation>
- steamos-manager：<https://github.com/OpenGamingCollective/steamos-manager>
- CachyOS chwd 掌机配置：<https://github.com/CachyOS/chwd/blob/master/profiles/pci/handhelds/profiles.toml>
- Bazzite 弃用 HHD：<https://github.com/ublue-os/bazzite/commit/ce953e4306f2effa58f2fbb8a833081685aa5424>
- HHD OXP（仅旧系统对照）：<https://github.com/hhd-dev/hhd/tree/master/src/hhd/device/oxp>
