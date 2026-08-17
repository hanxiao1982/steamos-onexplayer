# Linux kernel WMI vs OneXPlayer OxpWMI (Intel G3E)

OneXConsole talks to Intel Arc G3 Extreme ECs through WMI (`SuRwECRegInterface`), not ACPI EC ports. The kernel already has that *shape* of access: ACPI-WMI method invoke, with firmware talking to the EC underneath.

The closest in-tree handheld that also ships Intel G3E is **MSI Claw 8 EX AI+**. Its EC/fan/TDP/charge path is `msi-wmi-platform`, not `oxpec` and not HID.

This page is a file map plus a protocol comparison. Register offsets for OneXPlayer stay in [README.md](README.md). OneXConsole backends stay in [access.md](access.md).

## Kernel files (WMI stack)

| File | Role |
|---|---|
| `drivers/platform/wmi/core.c` | WMI bus. Older trees still have this as `drivers/platform/x86/wmi.c`. Discovers `PNP0C14` `_WDG` GUIDs and implements `wmidev_evaluate_method()`. |
| `include/linux/wmi.h` | `struct wmi_driver`, `wmi_device_id`, evaluate/query APIs. |
| `drivers/platform/x86/wmi-bmof.c` (or `drivers/platform/wmi/wmi-bmof.c`) | Exposes the **BMOF catalog** GUID `05901221-D566-11D1-B2F0-00A0C9062910`. Decode with `bmf2mof`, not `bmfdec`. |
| `Documentation/wmi/acpi-interface.rst` | ACPI-WMI wire format (`WMxx` method id + instance + buffer). |
| `Documentation/wmi/driver-development-guide.rst` | How to write a `wmi_driver`. Points at Intel WMI samples for the call pattern. |
| `drivers/acpi/ec.c` | ACPI Embedded Controller (`ec_read` / `ec_write`, ports 0x66/0x62). Used by `oxpec` and by AML if a WMI method’s OperationRegion is `EmbeddedControl`. |

Generic Intel WMI drivers (`drivers/platform/x86/intel/wmi/thunderbolt.c`, `sbl-fw-update.c`) show `wmidev_evaluate_method` / query-block usage. They are **not** EC register interfaces.

## MSI Claw files (same G3E generation)

Claw splits gamepad and EC. Only the WMI platform driver is the analog of OxpWMI.

| File | What it does | EC / WMI? |
|---|---|---|
| `drivers/platform/x86/msi-wmi-platform.c` | Fan RPM, and (in the Claw patch series) shift mode, PL1/PL2, charge threshold | **Yes** — ACPI-WMI over the EC |
| `Documentation/wmi/devices/msi-wmi-platform.rst` | MOF for class `MSI_ACPI`, method IDs, 32-byte package layout | Docs for the file above |
| `drivers/platform/x86/msi-ec.c` | Older MSI *laptops*: DMI-whitelisted `ec_read` / `ec_write` | ACPI EC, **not** Claw G3E |
| `drivers/hid/hid-msi.c` (earlier name `hid-msi-claw.c`) | Gamepad mode, M-keys, RGB, rumble | HID only |

`msi-wmi-platform` comment in-tree: MSI reused the **Microsoft WMI-ACPI sample GUID**, so other OEMs can appear with the same GUID and a different AML payload. That is *not* proven for OneXPlayer; see [GUID](#guid-is-not-shared) below.

### Claw 8 EX AI+ (Intel G3E)

Antheas Kapenekakis’s `msi-wmi-platform` series (lkml, 2025-05, plus Gen4 in 2026-08) treats all Claw models as this WMI interface. The G3E SKU is quirked as Gen4:

| Field | Value |
|---|---|
| Ident | `MSI Claw 8 EX AI+ CG3EM` |
| DMI board | `MS-1T91` |
| Vendor match | `Micro-Star International Co., Ltd.` |
| Quirk | `quirk_gen4`: shift mode, charge threshold, dual fans, restore curves |
| Custom shift | `MSI_PLATFORM_SHIFT_MANUAL` (not the older `USER` value) |
| PL1 | 8–35 W |
| PL2 | 9–45 W |

Mainline `msi-wmi-platform` today is the smaller driver (Get_WMI + Get_EC probe, Get_Fan hwmon, debugfs for every method). Claw feature parity (profiles / PPT / charge / fan tables) lives in that patch series and is the reference for “how a G3E handheld does EC-over-WMI in Linux”.

## MSI WMI protocol (what the kernel actually calls)

Windows class (from the in-tree MOF dump):

```
root\WMI / MSI_ACPI
GUID  ABBC0F6E-8EA1-11D1-00A0-C90629100000
```

| WmiMethodId | Name | Use on Claw |
|---|---|---|
| 3 / 4 | `Get_EC` / `Set_EC` | Probe: EC flags + 28-byte FW string. Bit7 = “Tiger Lake-style” interface (Claw still sets this). |
| 17 / 18 | `Get_Fan` / `Set_Fan` | RPM (subfeature `0x00`, up to four BE16, `RPM = 480000 / raw`). Fan tables are subfeatures `0x01`/`0x02`. |
| 27 / 28 | `Get_Data` / `Set_Data` | **Register-addressed** R/W used for shift / PL / charge |
| 29 | `Get_WMI` | Interface version; driver wants major `2` |

Every call is a **32-byte** buffer (Windows `CreateByteField()` quirk). Layout:

```
in[0]  = subfeature or EC address
in[1…] = payload
out[0] = 0x00 failure, non-zero success
out[1…] = payload
```

`Get_Data` / `Set_Data` addresses used by the Claw series:

| Address | Meaning |
|---|---|
| `0xd2` | Shift mode (sport / comfort / green / eco / user or manual) |
| `0x50` | PL1 / SPL (LE32 watts) |
| `0x51` | PL2 / SPPT (LE32 watts) |
| `0xd7` | Charge end threshold (0–100) |

Kernel call site (the piece to copy, not the MSI GUID):

```c
status = wmidev_evaluate_method(data->wdev, 0x0, method, &in, &out);
```

Firmware AML is not thread-safe; the driver takes its own mutex. Debugfs (`/sys/kernel/debug/msi-wmi-platform-<dev>/`) can poke any method with a raw 32-byte buffer.

## Side-by-side with OneXPlayer OxpWMI

Same idea: userspace/kernel never opens 0x66/0x62; a WMI method names a register and firmware does the EC cycle.

Not the same ABI. Do **not** bind `msi-wmi-platform` to a OneXPlayer DMI id.

| | OneXConsole OxpWMI | MSI Claw (`msi-wmi-platform`) |
|---|---|---|
| Windows class | `SuRwECRegInterface` | `MSI_ACPI` |
| Scope | `root\WMI` | `root\WMI` |
| GUID | `43B5A593-AD62-4257-8546-91B0797BEC1B` (X2 Mini Windows `guid` qualifier) | `ABBC0F6E-8EA1-11D1-00A0-C90629100000` |
| Read | `ReadECReg(GroupOffset)` | `Get_Data` / `Get_Fan` / … |
| Write | `WriteECReg(GroupOffsetValue)` | `Set_Data` / `Set_Fan` / … |
| Address | 16-bit `0x400 + reg` (group `0x04`) | 8-bit `buffer[0]` (or fan subfeature) |
| Payload | hex string / 8-byte block in out-params | fixed 32-byte ACPI buffer |
| Fan | EC `0x58`/`0x59` (BE16 RPM) | `Get_Fan` raw, `480000/raw` |
| TDP | EC gate `0xED` + Intel MSR | WMI `0x50`/`0x51` watts |
| Charge | EC `0xA3`–`0xA5` | WMI `0xd7` |
| In-tree Linux client | **none** | `msi-wmi-platform` |
| `oxpec` | ACPI `ec_read`/`ec_write` only | not used |

### GUID is not shared

Confirmed on X2 Mini (Windows `Get-CimClass` qualifier `guid`):

`43B5A593-AD62-4257-8546-91B0797BEC1B`

That is **not** the MSI/Microsoft sample `ABBC0F6E-…`. `msi-wmi-platform` must not bind to OneXPlayer. Linux `wmi_device_id` should use the 43B5… GUID (uppercase). Still need `WmiMethodId` for `ReadECReg` / `WriteECReg` from `CimClassMethods` or `bmf2mof`.

### Windows probe (X2 Mini)

`ReadECReg` with `GroupOffset = 0x458` (`0x400 + 0x58` fan high) returned `ReturnValue = True` and

```
uStringReturn = 0xFF,0x00,0x00,0x00,0x00,0x00,0x00,0x00
```

That matches the 8-byte block OneXConsole parses. **`ReturnValue True` only means the WMI method ran**, not that `0xFF` is a real RPM. `0xFF00` is not a plausible fan speed; `0xFF` is also the usual “empty / unused / not updating” EC value.

Treat the first byte as a candidate for register `0x58` until more offsets are sampled. Cross-check with values that should not be `0xFF` on a running unit: `0x470` (CPU temp), `0x44A`/`0x44B` (PWM), `0x459` (fan low). If those are also all `0xFF`, the bank/offset packing is wrong; if they look like °C / 0–184, the path is good and fan high is just idle/invalid.

## What to reuse for an OxpWMI Linux backend

Copy the **call pattern** from `msi-wmi-platform`, not the method table.

1. `struct wmi_driver` + `wmi_device_id` GUID `43B5A593-AD62-4257-8546-91B0797BEC1B`.
2. `wmidev_evaluate_method(wdev, instance, method_id, in, out)` with a driver mutex.
3. Map OneXConsole `ReadECReg` / `WriteECReg` onto those method IDs and the 16-bit `GroupOffset` (`0x400 + reg`).
4. Keep the Intel G3E register map from [x2-mini.md](x2-mini.md) (`0x58` fan, `0xEB` turbo, PWM 0–184, charge `0xA3`–`0xA5`).
5. Leave `oxpec`’s `ec_read`/`ec_write` path for AMD (WinRing0-equivalent).

`hid-msi` / `hid-msi-claw` is the wrong template for fans and charge. OneXConsole already treats RGB/rumble/gyro as HID (`CommonHid`), same split as Claw.

## How to identify the EC-access GUID

`bmfdec` 输出乱码**不能**用来排除某个 GUID。多数 `/sys/bus/wmi/devices/<GUID>/` 根本不是 MOF：对它们跑解码器只会得到二进制垃圾。GUID 对不对，看 **类名 / 方法名 / AML 是否碰 EC**，不看解码器是否漂亮。

判定顺序：Windows 类限定符（X2 Mini 已得到 `43B5A593-…`）→ 只解码 BMOF 那个 GUID → ACPI `_WDG` + `WMxx` → 只读交叉验证多个寄存器，不要只看风扇 `0xFF`。

### 0. 先分清两种 GUID

| GUID | 是什么 | 能不能当 OxpWMI 绑定目标 |
|---|---|---|
| `05901221-D566-11D1-B2F0-00A0C9062910` | 固件里的 **Binary MOF 目录**（`wmi-bmof`） | **否**。只用来查表。 |
| 带 `WMI_METHOD`（flag `0x02`）的其它 GUID | 真正可 `evaluate_method` 的对象 | **候选**。其中一个应是 `SuRwECRegInterface`。 |
| flag `0x08` | 事件（热键等） | 否 |
| 无 method 的 data block | `WQxx` 查询块 | 一般否 |

`ls /sys/bus/wmi/devices/` 里，**只有** BMOF 那个设备的 `bmof` 属性是合法 Binary MOF。其它目录即使有个叫 `bmof` 的文件，也不是给 `bmfdec` 用的。

内核文档的正确命令是 **`bmf2mof`**（[pali/bmfdec](https://github.com/pali/bmfdec)），不是 `bmfdec`：

```
# 可能带 [-0] 后缀
./bmf2mof /sys/bus/wmi/devices/05901221-D566-11D1-B2F0-00A0C9062910/bmof
```

`bmfdec` 只做 DS-01/LZ 解压，吐出来仍是 UTF-16 结构体，终端里就是乱码。`bmf2mof` 才生成可读 MOF。

解压后仍不像文本时，先看文件头是不是 `FOMB`（BMOF 倒序）：

```
hexdump -C /sys/bus/wmi/devices/05901221-D566-11D1-B2F0-00A0C9062910/bmof | head
strings -el /sys/bus/wmi/devices/05901221-D566-11D1-B2F0-00A0C9062910/bmof
```

`-el` 是 little-endian UTF-16。能直接搜到 `SuRwECRegInterface` / `ReadECReg` / `WriteECReg` / `GroupOffset` 就够了；类上面的 `guid("{...}")` 就是要绑的 GUID。

### 1. Windows：用已经知道的类名（最稳）

OneXConsole 已经给出类名，不必猜。管理员 PowerShell：

```powershell
Get-CimClass -Namespace root/wmi -ClassName SuRwECRegInterface |
  Select-Object -ExpandProperty CimClassQualifiers

Get-CimClass -Namespace root/wmi -ClassName SuRwECRegInterface |
  Select-Object -ExpandProperty CimClassMethods
```

要找的是 qualifier **`guid`**（形如 `{xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx}`）。方法列表里应有 `ReadECReg` / `WriteECReg`，参数名 `GroupOffset` / `GroupOffsetValue`。

类名不确定时：

```powershell
Get-CimClass -Namespace root/wmi -MethodName ReadECReg
Get-CimClass -Namespace root/wmi | Where-Object { $_.CimClassName -match 'EC' }
```

`Get-CimInstance -Namespace root/wmi -ClassName SuRwECRegInterface` 的 `InstanceName` 只说明挂在哪个 `PNP0C14` 上，**不是** GUID。

只读确认（风扇高字节，编码地址 `0x400+0x58 = 0x458`）：

```powershell
$o = Get-CimInstance -Namespace root/wmi -ClassName SuRwECRegInterface
Invoke-CimMethod -InputObject $o -MethodName ReadECReg -Arguments @{ GroupOffset = 0x458 }
```

能回来且数值像转速，这个 `guid` 就是 EC 访问接口。先不要 `WriteECReg`。

### 2. Linux：从 `_WDG` 找到 method GUID，再看对应 `WMxx`

```
acpidump -b
iasl -d *.dat
```

每个 `PNP0C14` 的 `_WDG` 是 20 字节一条：

| 偏移 | 内容 |
|---|---|
| 0–15 | GUID（Windows GUID 字节序，不是按 u8 顺序打印的） |
| 16–17 | object id（两个 ASCII 字符，例如 `BA`） |
| 18 | instance count |
| 19 | flags：`0x02` = 有 WMI method |

只保留 `flags & 0x02`。object id `XX` 对应同设备下的 ACPI 方法 **`WMXX`**（例如 id `BA` → `WMBA`）。

反汇编每个 `WMxx`，**这才是“是不是 EC”的判据**：

- 访问 `OperationRegion (…, EmbeddedControl, …)`，或调用 `ECRD` / `ECWR` / `\_SB.PCI0.LPCB.EC0.` 一类路径
- 出现 `0x0400`、对参数做 `And 0xFF` / `ShiftRight 8`（group + offset，对应 `0x400+reg`）
- 出现已知 G3E 偏移：`0x58` 风扇、`0x4A`/`0x4B` PWM、`0xEB` turbo、`0xA3`–`0xA5` 充电

同时满足「method GUID」+「AML 碰 EC / 0x400」的那条，就是 OxpWMI。事件 GUID 和 BMOF GUID 直接丢掉。

`lswmi`（若发行版有）会把 GUID、object id、flags、对应 ACPI 路径打成一张表，省得手拆 `_WDG`。

### 3. 不要用这些当“找到了”

- 对每个 sysfs 目录跑 `bmfdec` 出乱码 / 不出乱码
- GUID 碰巧是 `ABBC0F6E-8EA1-11D1-00A0-C90629100000`（MSI / 微软示例）。OneXPlayer 要用类名或 AML 再确认，不能因为常见就当是 Claw 那套 `Get_Data`
- `oxpec` 的 `ec_read` 能读通：那只说明 ACPI EC 也在，**不能**代替 WMI GUID。G3E 上 OneXConsole 仍走 WMI

### 4. 绑到驱动上还缺什么

GUID 只是 `wmi_device_id`。还要 MOF / Windows 方法限定符里的 **`WmiMethodId`**（`ReadECReg` / `WriteECReg` 各一个整数），以及入参是 16 位 `GroupOffset` 还是包在 buffer 里。这些在乱码的 `bmfdec` 输出里没有；用第 1 节的 `CimClassMethods` 或第 0 节 `bmf2mof` 后的 `[WmiMethodId(n)]`。

Until that dump exists, Linux cannot bind a WMI client. `oxpec` can only work if that firmware also exposes a standard ACPI EC (then `ec_read` of the low 8 bits may still work, which is the first check in [access.md](access.md)).
