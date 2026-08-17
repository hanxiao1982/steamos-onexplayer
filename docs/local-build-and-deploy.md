# 不等主线：两边都能走通的本地拉取、编译、测试、安装

不要为加一条 DMI 重编整棵内核。两边都已经带了 `oxpec` 源码逻辑，缺的只是新机 `board_name`。做法是：

1. 拉取当前的 `oxpec.c`
2. 注入同一段 DMI（C 代码两边相同）
3. 对着**正在运行的内核**头文件编出 `oxpec.ko`
4. 从 `/var/lib/oxp-kmod` 加载（Bazzite 的 `/usr` 只读，这个路径两边都能写）
5. 按键再叠 InputPlumber YAML，不改 HHD

仓库里的工具在 `kmod/`。

---

## 0. 先选路，不要一上来 `make -j` 整核

| 路径 | 做什么 | 什么时候用 |
| --- | --- | --- |
| **A. 树外模块（推荐）** | 只编 `oxpec.ko` | 新机 EC 和已有变体相同，只缺 DMI。Bazzite / CachyOS 都走这条 |
| B. 重编 CachyOS deckify | `makepkg` 打进 `0001-handheld.patch` | 要改寄存器逻辑，或树外模块对不上 vermagic |
| C. 重编 Bazzite / OGC 整核 | Fedora RPM + ostree 换核 | 几乎不该为 DMI 这么做；成本高，还要签名 |

`hid-oxp` 的 DMI quirk（hybrid MCU / RGB）也可以树外编，但依赖 HID/LED，比 `oxpec` 脆。先把风扇 hwmon 跑通，再考虑它。

---

## 1. 真机采集 DMI（两边同一套命令）

在掌机上：

```bash
cd /path/to/steamos-onexplayer
chmod +x kmod/scripts/*.sh
kmod/scripts/collect-dmi.sh
```

把输出写进 `kmod/local-device.env`。

`OXP_BOARD_VARIANT` 按 EC 选，不要按商品名猜：

| 变体 | 适用 | 风扇寄存器 | Turbo |
| --- | --- | --- | --- |
| `oxp_fly` | F1 / F1Pro / APEX | `0x76` | `0xF1` |
| `oxp_x1` | X1 系列 | `0x58` | `0xEB` |
| `oxp_2` | 2 系列 | `0x58` | `0xEB` |
| `oxp_g1_a` / `oxp_g1_i` | G1 / SUPER X | G1 逻辑 | 机型相关 |

不确定时：先 `oxp_fly`，`insmod` 后看 `fan1_input` 是否像转速；明显不对再换变体。

---

## 2. 拉取源文件并写入同一段修改

```bash
# Bazzite 更接近 OGC 树；CachyOS 用 mainline 即可。两边注入脚本相同。
kmod/scripts/fetch-oxpec.sh ogc        # 或 mainline / cachyos
python3 kmod/scripts/inject-dmi.py \
  --env kmod/local-device.env \
  --oxpec kmod/oxpec/oxpec.c
```

注入结果等价于在 `dmi_table[]` 里加：

```c
{
    .matches = {
        DMI_MATCH(DMI_BOARD_VENDOR, "ONE-NETBOOK"),
        DMI_EXACT_MATCH(DMI_BOARD_NAME, "ONEXPLAYER NEWMODEL"),
    },
    .driver_data = (void *)oxp_fly,
},
```

`NEWMODEL` 必须换成 `collect-dmi.sh` 读到的 **`board_name`**。这就是两边共用的修改代码。

源码 URL：

| 参数 | 文件 |
| --- | --- |
| `mainline` | `https://raw.githubusercontent.com/torvalds/linux/master/drivers/platform/x86/oxpec.c` |
| `ogc` | `OpenGamingCollective/linux` 的 `features/onexplayer` 同一路径 |
| `cachyos` | `CachyOS/linux` 的 `master` 同一路径 |

---

## 3. 编译（对着本机 `uname -r`）

```bash
kmod/scripts/build.sh
```

脚本会：

- 使用 `/lib/modules/$(uname -r)/build`
- 若 `.config` 里有 `CONFIG_CC_IS_CLANG=y`，自动加 `LLVM=1`（CachyOS 默认核常见；deckify 多为 GCC）
- 在 `kmod/oxpec/oxpec.ko` 产出模块

### CachyOS 头文件

```bash
sudo pacman -S --needed linux-cachyos-deckify-headers base-devel pahole
# 确认掌机跑的就是 deckify
uname -r    # 应类似 7.1.8-1-cachyos-deckify
```

一键（root，已填好 `local-device.env`）：

```bash
sudo kmod/scripts/install-cachyos.sh
```

### Bazzite 头文件（最容易卡死的一步）

镜像经常**不带** `kernel-devel`。先看：

```bash
ls -l /lib/modules/$(uname -r)/build
rpm -q kernel-devel kernel-devel-matched || true
uname -r
```

- 若 `build` 是有效目录：直接 `kmod/scripts/build.sh`
- 若没有：必须装 **vermagic 完全一致** 的 OGC `kernel-devel`，不要 layer 官方 Fedora 的 `kernel-devel`

```bash
# 只示例：版本必须改成你的 uname -r
rpm-ostree install /path/to/kernel-devel-$(uname -r).rpm
sudo systemctl reboot
```

OGC 的 devel RPM 跟内核 RPM 一起出，看 [OpenGamingCollective/kernel-packages](https://github.com/OpenGamingCollective/kernel-packages) 的 Fedora 构建产物，或当前 Bazzite 镜像构建日志里的 `kernel-devel`。对不上就 `Invalid module format`。

没有匹配 devel 时的退路：在另一台已装同一 `kernel-devel` 的 Fedora 上编好 `oxpec.ko`，拷到掌机再 `install-common.sh`。Apex 社区插件就是预编译多版本 `.ko`。

一键（root，且 `build` 已存在、Secure Boot 已关）：

```bash
sudo kmod/scripts/install-bazzite.sh
```

---

## 4. 本地测试

未加载（普通用户）：

```bash
kmod/scripts/test-oxpec.sh
```

加载并探 hwmon（root）：

```bash
sudo kmod/scripts/test-oxpec.sh kmod/oxpec/oxpec.ko
```

成功时会看到类似：

```
found /sys/class/hwmon/hwmonN (name=oxpec)
  fan1_input=....
  pwm1=...
  pwm1_enable=...
```

手动风扇冒烟（确认后再交回自动，避免一直狂转）：

```bash
HWMON=$(ls -d /sys/class/hwmon/hwmon* | while read d; do
  [[ $(cat "$d/name") == oxpec ]] && echo "$d"
done)
echo 1 > "$HWMON/pwm1_enable"
echo 80 > "$HWMON/pwm1"
sleep 3
echo 2 > "$HWMON/pwm1_enable"   # 2=自动；老 ABI 则写 0
```

失败对照：

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| `Invalid module format` | vermagic ≠ `uname -r` | 换匹配的 headers 重编 |
| `Key was rejected by service` / `Required key not available` | Secure Boot | 关 SB，或自签 MOK |
| `insmod` 成功但无 hwmon | `board_name` 不匹配 | 重跑 `collect-dmi.sh`，注意空格/大小写 |
| `modprobe: FATAL: Module oxpec is in use` | 用户态占着 hwmon | 先停 InputPlumber/风扇服务再 `-r` |
| 无法 `modprobe -r oxpec` | `CONFIG_OXPEC=y` 编进内核 | 只能走路径 B/C 重编内核 |

看是否内建：

```bash
grep OXPEC /lib/modules/$(uname -r)/config
# 或
zgrep CONFIG_OXPEC /proc/config.gz
```

`=m` 才能替换。

---

## 5. 本地部署（开机自动加载）

`install-common.sh` 做的事情两边一样：

- 把 `oxpec.ko` 放到 `/var/lib/oxp-kmod/oxpec.ko`
- 写入 `/etc/systemd/system/oxpec-local.service`（先卸 in-tree `oxpec` 再 `insmod`）
- `systemctl enable --now oxpec-local.service`

```bash
sudo kmod/scripts/install-common.sh
```

Bazzite 不要往 `/usr/lib/modules` 里塞未签名模块，更新一次 ostree 就没了。`/var` + `/etc` 能活过日常更新；**内核小版本一变就要重编**。

CachyOS 若希望内核升级后自动重编：

```bash
sudo pacman -S --needed dkms
sudo dkms add /path/to/steamos-onexplayer/kmod/oxpec
sudo dkms install oxpec-local/1.0.0
```

---

## 6. 按键：InputPlumber 本地叠加（仍然不改 HHD）

```bash
# 先改 kmod/local-device.env 里的 OXP_PRODUCT_NAME / OXP_SYS_VENDOR
sudo kmod/scripts/install-inputplumber.sh
journalctl -u inputplumber -b --no-pager | tail -n 50
```

模板：`kmod/inputplumber/50-onexplayer_local.yaml`。`phys_path` 因主板 USB 口而异，先用 `name` + `handler` 宽匹配，再在 `evtest` / `udevadm info` 里收紧。

`capability_map_id`：APEX 类用 `oxp8`，X1 类试 `oxp5`。

CachyOS 新装还要把 `product_name` 加进 chwd `handhelds/profiles.toml` 的正则，否则下一台机器不会自动装 InputPlumber。本机手工 `pacman -S inputplumber` 即可先测。

---

## 7. 路径 B：CachyOS 把补丁打进 deckify（可选）

树外模块验证通过后，再做成发行版补丁：

```bash
git clone https://github.com/CachyOS/linux-cachyos.git
cd linux-cachyos/linux-cachyos-deckify
# 把针对 oxpec.c 的 diff 存成 0002-oxp-local.patch
# 写入 PKGBUILD 的 source=()
makepkg -s
sudo pacman -U linux-cachyos-deckify-*.pkg.tar.zst \
               linux-cachyos-deckify-headers-*.pkg.tar.zst
```

`prepare()` 会对所有 `*.patch` 执行 `patch -Np1`。合入官方则 PR 到 `CachyOS/kernel-patches`。

整核编译要很久，只为 DMI 时不必走这条。

---

## 8. 路径 C：Bazzite 为什么不建议整核

Bazzite 是 ostree 镜像，内核来自 OGC 签名 RPM。本地重编整核需要：

1. 按 `OpenGamingCollective/kernel-packages` 打 `monolithic.patch`
2. 出 kernel / kernel-core / kernel-modules RPM
3. `rpm-ostree override replace` 整组包
4. Secure Boot 下还要签名

只为一条 DMI，用树外 `oxpec.ko` + 关 SB 即可。Apex 社区也是这么做的。

`ujust enroll-secure-boot-key` 只登记 Universal Blue 的密钥，**不会**让你的未签名 `.ko` 通过。

---

## 9. 推荐工作顺序

```
真机 collect-dmi.sh
    -> 填 local-device.env
    -> fetch-oxpec.sh + inject-dmi.py
    -> 装匹配 headers
    -> build.sh
    -> sudo test-oxpec.sh   # 看到 hwmon
    -> sudo install-common.sh
    -> sudo install-inputplumber.sh
    -> 再把同一份 DMI diff 送 LKML / OGC / CachyOS
```

内核模块文件：`kmod/oxpec/oxpec.c`（拉取后注入）。  
用户态按键：`kmod/inputplumber/50-onexplayer_local.yaml`。  
不要写 HHD。
