# Linux kernel WMI vs OneXPlayer OxpWMI (Intel G3E)

OneXConsole talks to Intel Arc G3 Extreme ECs through WMI (`SuRwECRegInterface`), not ACPI EC ports. The kernel already has that *shape* of access: ACPI-WMI method invoke, with firmware talking to the EC underneath.

The closest in-tree handheld that also ships Intel G3E is **MSI Claw 8 EX AI+**. Its EC/fan/TDP/charge path is `msi-wmi-platform`, not `oxpec` and not HID.

This page is a file map plus a protocol comparison. Register offsets for OneXPlayer stay in [README.md](README.md). OneXConsole backends stay in [access.md](access.md).

## Kernel files (WMI stack)

| File | Role |
|---|---|
| `drivers/platform/wmi/core.c` | WMI bus. Older trees still have this as `drivers/platform/x86/wmi.c`. Discovers `PNP0C14` `_WDG` GUIDs and implements `wmidev_evaluate_method()`. |
| `include/linux/wmi.h` | `struct wmi_driver`, `wmi_device_id`, evaluate/query APIs. |
| `drivers/platform/x86/wmi-bmof.c` (or `drivers/platform/wmi/wmi-bmof.c`) | Exposes Binary MOF so userspace (`bmfdec`) can dump class/method names. This is how `SuRwECRegInterface` would be found on a G3E unit. |
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
| GUID | **unknown** (not in OneXConsole strings; dump bmof on device) | `ABBC0F6E-8EA1-11D1-00A0-C90629100000` |
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

`msi-wmi-platform` DMI-whitelists Micro-Star only, because that Microsoft sample GUID is not unique. OneXConsole never mentions `ABBC0F6E` or `MSI_ACPI`. Until a G3E OneXPlayer dumps `_WDG` / bmof, assume a **different** GUID and method IDs even though the Windows class is also under `root\WMI`.

If a dump ever shows `ABBC0F6E` plus `ReadECReg`, that would be the sample GUID with a different MOF. Still a new driver (or a carefully isolated quirk), not a DMI row in the MSI module.

## What to reuse for an OxpWMI Linux backend

Copy the **call pattern** from `msi-wmi-platform`, not the method table.

1. `struct wmi_driver` + `wmi_device_id` GUID from the OneXPlayer bmof.
2. `wmidev_evaluate_method(wdev, instance, method_id, in, out)` with a driver mutex.
3. Map OneXConsole `ReadECReg` / `WriteECReg` onto those method IDs and the 16-bit `GroupOffset` (`0x400 + reg`).
4. Keep the Intel G3E register map from [x2-mini.md](x2-mini.md) (`0x58` fan, `0xEB` turbo, PWM 0–184, charge `0xA3`–`0xA5`).
5. Leave `oxpec`’s `ec_read`/`ec_write` path for AMD (WinRing0-equivalent).

`hid-msi` / `hid-msi-claw` is the wrong template for fans and charge. OneXConsole already treats RGB/rumble/gyro as HID (`CommonHid`), same split as Claw.

## How to get the missing OneXPlayer GUID

On a G3E unit (X2 Mini, X2, OneXPlayer 3, Apex Air, Apex i):

```
ls /sys/bus/wmi/devices/
# for each GUID that has a bmof attribute:
cat /sys/bus/wmi/devices/<GUID>/bmof | bmfdec
```

Look for `SuRwECRegInterface`, `ReadECReg`, `WriteECReg`, `GroupOffset`. `acpidump` + `iasl -d` on the WMI `PNP0C14` device shows the same GUID in `_WDG` and which AML method implements it.

Until that dump exists, Linux cannot bind a WMI client. `oxpec` can only work if that firmware also exposes a standard ACPI EC (then `ec_read` of the low 8 bits may still work, which is the first check in [access.md](access.md)).
