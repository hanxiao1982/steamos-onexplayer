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
u8 input[32] = { 0 };
u8 output[32];
struct acpi_buffer in = { .length = sizeof(input), .pointer = input };
struct acpi_buffer out = { ACPI_ALLOCATE_BUFFER, NULL };

mutex_lock(&data->wmi_lock);
status = wmidev_evaluate_method(data->wdev, 0x0, method, &in, &out);
mutex_unlock(&data->wmi_lock);

/* output must be ACPI_TYPE_BUFFER of length 32; byte[0] == 0 is failure */
```

That is the entire read/write path. There is no `_WDG` walk and no ACPI Integer Arg2. Fan RPM is `Get_Fan` (method 0x11) with a zeroed 32-byte input; register-style R/W on Claw patches is `Get_Data` / `Set_Data` (0x1b / 0x1c) with `input[0] = address`.

Firmware AML is not thread-safe; the driver takes its own mutex. Debugfs (`/sys/kernel/debug/msi-wmi-platform-<dev>/`) can poke any method with a raw 32-byte buffer.

`oxp-wmi` copies this evaluate/mutex/32-byte-input shape. It does **not** copy MSI's method table, 32-byte output requirement, or status polarity (`0x00` is success on OxpWMI).

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
| Address | UInt32 LE `04 reg 00 00` (JS still writes `0x400+reg`) | 8-bit `buffer[0]` (or fan subfeature) |
| Payload | hex string / 8-byte block in out-params | fixed 32-byte ACPI buffer |
| Fan | EC `0x58`/`0x59` (BE16 RPM) | `Get_Fan` raw, `480000/raw` |
| TDP | EC gate `0xED` + Intel MSR | WMI `0x50`/`0x51` watts |
| Charge | EC `0xA3`–`0xA5` | WMI `0xd7` |
| In-tree Linux client | **none** (out-of-tree [`oxp-wmi`](oxp-wmi.md)) | `msi-wmi-platform` |
| `oxpec` | ACPI `ec_read`/`ec_write` only | not used |

### GUID is not shared

Confirmed on X2 Mini (Windows `Get-CimClass` qualifier `guid`):

`43B5A593-AD62-4257-8546-91B0797BEC1B`

That is **not** the MSI/Microsoft sample `ABBC0F6E-…`. `msi-wmi-platform` must not bind to OneXPlayer. Linux `wmi_device_id` should use the 43B5… GUID (uppercase).

### Windows probe (X2 Mini)

Instance: `ACPI\PNP0C14\RWECREGWMI_0`.

| Method | `WmiMethodId` | In (`ID=0`) | Out (`ID=1`) |
|---|---|---|---|
| `ReadECReg` | **1** | `GroupOffset` `UInt32` | `uStringReturn` string (8 bytes) |
| `WriteECReg` | **2** | `GroupOffsetValue` `UInt32` | `uStringReturn` string |
| `WriteReadECReg` | **3** | `GroupOffsetValue` `UInt32` | `uStringReturn` string (“write one, return multi-register values”) |

`GroupOffset` packing that works:

```
uint32 LE:  [0x04] [reg] [0x00] [0x00]
value     =  0x04 | (reg << 8)     # 0x58 → 0x5804
```

JS `0x400+reg` (`0x458`) is the opposite 16-bit view and is **rejected** (`uStringReturn` all `0xFF,…`, status byte `0xFF`).

`uStringReturn` on a good read:

```
[0] = 0x00   status ok
[1] = value  EC RAM byte
[2..7] = 0
```

| Reg | `GroupOffset` | Byte[1] | Meaning |
|---|---|---|---|
| `0x58` | `0x5804` | `0x01` | fan RPM high |
| `0x59` | `0x5904` | `0x40` | fan RPM low → BE16 `0x0140` = **320 RPM** |
| `0x4A` | `0x4A04` | `0x00` | PWM auto |
| `0x4B` | `0x4B04` | `0x25` | PWM duty **37** (range 0–184) |
| `0x70` | `0x7004` | `0x31` | EC CPU temp **49 °C** |
| `0x60` | `0x6004` | `0x2A` | board sensor **42 °C** |
| `0xA0` | `0xA004` | `0x00` | battery temp; **ignore** (always 0 on X2 Mini) |

Fan 320 RPM + PWM 37/184 matches a quiet auto curve. CPU 49 °C > board 42 °C. The G3E map and OxpWMI **read** path are validated.

### Linux probe (X2 Mini, Bazzite 7.2 OGC)

`object_id=AC` → method `WMAC`. `wmidev_evaluate_method` with a **32-byte** input (first 4 bytes = LE `GroupOffset`) returns:

```
ACPI_TYPE_STRING len=39
"0x00,0x28,0x00,0x00,0x00,0x00,0x00,0x00"
```

`0x28` = CPU temp **40 °C**. Same load: `fan1_input=360`, `pwm1_enable=2` (auto). A 4-byte input succeeds with every EC byte 0 — the MSI `CreateByteField` 32-byte size is required on this AML, not optional.

`WriteECReg` / `WriteReadECReg` packing is not probed. Hypothesis (same LE layout, extra value byte):

```
GroupOffsetValue = 0x04 | (reg << 8) | (value << 16)
# bytes: 04, reg, value, 00
```

Do not write until that is confirmed. Method 3 may fill more of the 8-byte return (consecutive regs). `WmiMethodId` for Linux is **1 / 2 / 3**.

## What to reuse for an OxpWMI Linux backend

Copy the **call pattern** from `msi-wmi-platform`, not the method table.

1. `struct wmi_driver` + `wmi_device_id` GUID `43B5A593-AD62-4257-8546-91B0797BEC1B`.
2. Same call as `msi_wmi_platform_query()`: mutex + `wmidev_evaluate_method(wdev, 0x0, method_id, in, out)`. Method IDs: `ReadECReg=1`, `WriteECReg=2`, `WriteReadECReg=3`.
3. Input is a **32-byte** zeroed Buffer (MSI / Windows `CreateByteField()` quirk) with the LE `UInt32` in the first four bytes: read `0x04 | (reg << 8)`; write likely `0x04 | (reg << 8) | (value << 16)`. Do **not** pass JS `0x400+reg`. Output is an 8-byte block or hex `uStringReturn` (status `0x00` = ok, inverted vs MSI). Also accept a Package `{ ReturnValue, string }`.
4. Keep the Intel G3E register map from [x2-mini.md](x2-mini.md) (`0x58` fan, PWM 0–184, charge `0xA3`/`0xA4`). Skip `0xEB` / `0xA5` on X2 Mini (live unused).
5. Leave `oxpec`’s `ec_read`/`ec_write` path for AMD (WinRing0-equivalent).

`hid-msi` / `hid-msi-claw` is the wrong template for fans and charge. OneXConsole already treats RGB/rumble/gyro as HID (`CommonHid`), same split as Claw.

## How to identify the EC-access GUID

Garbled `bmfdec` output is **not** a reason to reject a GUID. Most `/sys/bus/wmi/devices/<GUID>/` nodes are not MOF; running a decoder on them only yields binary junk. Judge a GUID by **class name / method names / whether AML touches the EC**, not by whether a decoder prints pretty text.

Order: Windows class qualifier (X2 Mini already gave `43B5A593-…`) → decode only the BMOF GUID → ACPI `_WDG` + `WMxx` → read-only cross-check of several registers; do not trust a lone fan `0xFF`.

### 0. Two kinds of GUID

| GUID | What it is | Bind as OxpWMI? |
|---|---|---|
| `05901221-D566-11D1-B2F0-00A0C9062910` | Firmware **Binary MOF catalog** (`wmi-bmof`) | **No.** Catalog only. |
| Other GUIDs with `WMI_METHOD` (flag `0x02`) | Objects you can `evaluate_method` | **Candidates.** One of them should be `SuRwECRegInterface`. |
| flag `0x08` | Event (hotkeys, etc.) | No |
| Data block with no method | `WQxx` query block | Usually no |

Under `ls /sys/bus/wmi/devices/`, **only** the BMOF device’s `bmof` attribute is a real Binary MOF. Other directories may have a file named `bmof` that is not for `bmfdec`.

The kernel docs want **`bmf2mof`** ([pali/bmfdec](https://github.com/pali/bmfdec)), not `bmfdec`:

```
# may have a [-0] suffix
./bmf2mof /sys/bus/wmi/devices/05901221-D566-11D1-B2F0-00A0C9062910/bmof
```

`bmfdec` only does DS-01/LZ decompress and still emits a UTF-16 structure (looks like garbage in a terminal). `bmf2mof` produces readable MOF.

If it still does not look like text, check for a `FOMB` header (BMOF reversed):

```
hexdump -C /sys/bus/wmi/devices/05901221-D566-11D1-B2F0-00A0C9062910/bmof | head
strings -el /sys/bus/wmi/devices/05901221-D566-11D1-B2F0-00A0C9062910/bmof
```

`-el` is little-endian UTF-16. Finding `SuRwECRegInterface` / `ReadECReg` / `WriteECReg` / `GroupOffset` is enough; the class `guid("{...}")` is the GUID to bind.

### 1. Windows: use the known class name (most reliable)

OneXConsole already names the class. Admin PowerShell:

```powershell
Get-CimClass -Namespace root/wmi -ClassName SuRwECRegInterface |
  Select-Object -ExpandProperty CimClassQualifiers

Get-CimClass -Namespace root/wmi -ClassName SuRwECRegInterface |
  Select-Object -ExpandProperty CimClassMethods
```

Look for qualifier **`guid`** (`{xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx}`). Methods should include `ReadECReg` / `WriteECReg` with `GroupOffset` / `GroupOffsetValue`.

If the class name is unknown:

```powershell
Get-CimClass -Namespace root/wmi -MethodName ReadECReg
Get-CimClass -Namespace root/wmi | Where-Object { $_.CimClassName -match 'EC' }
```

`Get-CimInstance … SuRwECRegInterface` `InstanceName` only says which `PNP0C14` it hangs off; it is **not** the GUID.

Read-only check (fan high byte; encoded address `0x400+0x58 = 0x458` — note this JS form is **rejected** on the live X2 Mini wire; use `0x5804`):

```powershell
$o = Get-CimInstance -Namespace root/wmi -ClassName SuRwECRegInterface
Invoke-CimMethod -InputObject $o -MethodName ReadECReg -Arguments @{ GroupOffset = 0x5804 }
```

If the return looks like an RPM byte, that `guid` is the EC access interface. Do not `WriteECReg` yet.

### 2. Linux: find the method GUID in `_WDG`, then the matching `WMxx`

```
acpidump -b
iasl -d *.dat
```

Each `PNP0C14` `_WDG` entry is 20 bytes:

| Offset | Content |
|---|---|
| 0–15 | GUID (Windows GUID byte order, not raw u8 print order) |
| 16–17 | object id (two ASCII chars, e.g. `BA`) |
| 18 | instance count |
| 19 | flags: `0x02` = has WMI method |

Keep only `flags & 0x02`. Object id `XX` maps to ACPI method **`WMXX`** on the same device (`BA` → `WMBA`).

Disassemble each `WMxx`. **That** is the “is this the EC?” test:

- Touches `OperationRegion (…, EmbeddedControl, …)`, or calls `ECRD` / `ECWR` / `\_SB.PCI0.LPCB.EC0.`-style paths
- Uses `0x0400`, `And 0xFF` / `ShiftRight 8` (group + offset, i.e. `0x400+reg`)
- Mentions known Intel OxpWMI offsets: `0x58` fan, `0x4A`/`0x4B` PWM, `0xA3`/`0xA4` charge (`0xEB`/`0xA5` unused on X2 Mini live)

The object that is both a method GUID and AML that hits the EC / `0x400` is OxpWMI. Drop event GUIDs and the BMOF GUID.

`lswmi` (if the distro has it) prints GUID, object id, flags, and ACPI path so you do not have to parse `_WDG` by hand.

### 3. These are not a match

- Running `bmfdec` on every sysfs directory and scoring “garbled / not garbled”
- GUID happens to be `ABBC0F6E-8EA1-11D1-00A0-C90629100000` (MSI / Microsoft sample). Confirm with class name or AML on OneXPlayer; do not treat it as Claw `Get_Data`
- `oxpec` `ec_read` works: that only means ACPI EC is also present. It does **not** replace the WMI GUID. OneXConsole still uses WMI on Intel OxpWMI SKUs

### 4. What is still needed to bind a driver

The GUID is only `wmi_device_id`. You also need **`WmiMethodId`** from MOF / Windows method qualifiers (`ReadECReg` / `WriteECReg` each have an integer), and whether the input is a 16-bit `GroupOffset` or a buffer. Garbled `bmfdec` output does not have that; use `CimClassMethods` in section 1 or `[WmiMethodId(n)]` after `bmf2mof` in section 0.

GUID, method IDs (1/2/3), `GroupOffset` packing, and `uStringReturn` layout are known on X2 Mini. Write packing `04,reg,val,00` is live-confirmed (`0x4A` sticks; method 3 echoes `0x4B`). The remaining gap is apply: `0x4B` is cleared in ~200ms and RPM never changes on Linux Buffer/`wmidev` writes. `oxpec`’s `ec_read` remains a separate check: if ACPI EC exists, the low 8 bits may work without WMI.
