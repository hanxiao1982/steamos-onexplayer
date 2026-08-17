# OneXConsole EC access vs Linux oxpec

Source: OneXConsole **0.10.2-fix8** (`CompatLayerCT.exe`, `background.js`, `WinRing0x64.dll`) compared with upstream `drivers/platform/x86/oxpec.c`.

Register offsets are in [README.md](README.md). This page is only **how** bytes are read and written.

## Two backends

`CompatLayerCT.ECAccessType`:

| Enum | JS `ecAccessType` | Class | Used on |
|---|---|---|---|
| `WinRing0` | `1` (default) | `ECWinRing0` | AMD map (X2 Mini PRO, APEX) |
| `OxpWMI` | `2` | `ECOxpWMI` | Intel G3E map (X2 Mini, X2, OneXPlayer 3, Apex Air, Apex i) |

JS calls `POST http://localhost:1013/func/setECAccessType/{type}` after DMI detect (or the same path on named pipe `\\.\pipe\CompatLayerCT`; default is pipe). Type `1` also unpacks `wr0_build.7z` (`WinRing0x64.dll` + `.sys`). Type `2` does not load WinRing0. Full route list: [onexconsole-api.md](onexconsole-api.md).

Facade `CompatLayerCT.EC` exposes:

| Method | Meaning |
|---|---|
| `ECRamReadByte(address)` | Read one RAM byte (address may be encoded) |
| `ECRamDirectWrite(address, data)` | Write one RAM byte |
| `OrginECRamReadByte` / `OrginECRamWriteByte` | Raw 8-bit path (WinRing0 only) |
| `InitEC` / `FreeEC` | Load / unload backend |

OxpWMI **rejects** the Origin methods (`ECOxpWMI not support OrginECRamReadByte/WriteByte`).

Shared userspace lock: `ECLocker`. WinRing0 also keeps `openLibSys` and a `readCache`.

## Address encoding

JS and most `CompatLayerCT` APIs pass:

```
encoded = 0x400 + ec_reg    # example: PWM 0x4A → 1098 (0x44A)
```

| Backend | How the encoded value is used |
|---|---|
| WinRing0 Origin | Strip to 8-bit (`encoded & 0xFF`) and talk ACPI EC ports |
| OxpWMI (JS / CompatLayerCT) | Logical `0x400 + reg` (group `0x04` in the high byte of a 16-bit view) |
| OxpWMI (actual WMI UInt32, X2 Mini) | Little-endian **byte0 = group `0x04`, byte1 = reg**: `GroupOffset = 0x04 \| (reg << 8)` (fan `0x58` → `0x5804`). Passing `0x458` is rejected (AML sees group `0x58`). |

Range checks next to the WMI strings: `N` (group) max `0x0F`, `OFFR` (offset) range-checked. That matches a banked EC window, not a flat 256-byte space.

## WinRing0 (type 1)

Userspace P/Invoke into `WinRing0x64.dll`:

- `InitializeOls` / `DeinitializeOls` / `GetDllStatus`
- `ReadIoPortByte` / `WriteIoPortByte` (and Ex/Word/Dword variants)

Kernel helper: `WinRing0x64.sys` (`openLibSys`).

Port names in `CompatLayerCT`:

- `EC_ADDR_STATUS_COMMAND_PORT` — ACPI EC status/command **0x66**
- `EC_ADDR_DATA_PORT` — ACPI EC data **0x62**

This is the standard ACPI Embedded Controller protocol (same bytes the Linux ACPI EC driver uses):

```
status 0x66: OBF=bit0, IBF=bit1
cmd    0x66: RD_EC=0x80, WR_EC=0x81

read:  wait IBF=0 → cmd 0x80 → wait IBF=0 → data=addr → wait OBF=1 → read data
write: wait IBF=0 → cmd 0x81 → wait IBF=0 → data=addr → wait IBF=0 → data=value
```

Failures surface as `OlsStatus ERROR` / `OlsDllStatus ERROR`.

This path is **direct I/O**. It does not go through Windows ACPI or WMI. It can race firmware ACPI EC transactions if the global ACPI lock is not taken (OneXConsole only shows a process-local `ECLocker`).

## OxpWMI (type 2)

WMI, not port I/O.

| Item | Value |
|---|---|
| Scope | `root\WMI` (`\\.\root\wmi`) |
| Class | `SuRwECRegInterface` (`SELECT * FROM SuRwECRegInterface`) |
| GUID | `43B5A593-AD62-4257-8546-91B0797BEC1B` (X2 Mini class qualifier) |
| Read | `ReadECReg` (`WmiMethodId=1`), in `GroupOffset` `UInt32` |
| Write | `WriteECReg` (`WmiMethodId=2`), in `GroupOffsetValue` `UInt32` |
| Write+read | `WriteReadECReg` (`WmiMethodId=3`), same in-param as write; MOF: write one, return several regs |
| Out | `uStringReturn` (8 bytes); CIM also adds `ReturnValue` |

`GroupOffset` is `UInt32`. On the wire it is little-endian; firmware uses **byte0 = group, byte1 = offset**. CompatLayerCT’s JS `0x400+reg` must be byteswapped before the WMI call (`0x458` → `0x5804`).

`uStringReturn` is 8 bytes (OneXConsole also accepts `^[0-9A-F]{16}$`):

| Byte | Meaning (X2 Mini) |
|---|---|
| 0 | Status: `0x00` ok, `0xFF` fail (bad group / unused) |
| 1 | EC RAM byte |
| 2–7 | `0x00` on single-byte reads |

Confirmed reads: [linux-wmi.md](linux-wmi.md#windows-probe-x2-mini). `WriteECReg` / `WriteReadECReg` likely `04, reg, value, 00` (`value` in byte2). Not probed; do not write blindly.

Generic WMI helper errors mention `outParams["Data"]`, `dataOut["Bytes"]`, `iDataBlockIndex`, `fullPackage` — a shared ACPI-WMI invoker, not a second EC protocol.

Firmware owns serialization on this path. That is why Intel G3E models force type 2: OneXConsole never opens WinRing0 on those SKUs.

## Linux oxpec

Single path: ACPI EC address space.

```c
acpi_acquire_global_lock(500ms);
ec_read(reg, &byte);   /* or ec_write */
acpi_release_global_lock();
```

`ec_read` / `ec_write` are the in-kernel ACPI EC driver (`drivers/acpi/ec.c`). They use the same 0x66/0x62 handshake as WinRing0, plus the **ACPI global lock**, and they accept **8-bit** addresses only.

There is **no** `SuRwECRegInterface` client in `oxpec`. If a G3E firmware hides Embedded Control from ACPI and only exposes WMI, `oxpec` cannot talk to that EC until a WMI backend exists.

The kernel *does* already have a G3E handheld that speaks EC-over-WMI: MSI Claw 8 EX AI+ via `msi-wmi-platform`. Same transport (`wmidev_evaluate_method` on `PNP0C14`), different class/GUID/method ABI than `SuRwECRegInterface`. File map and comparison: [linux-wmi.md](linux-wmi.md).

Userspace on Linux (not used by `oxpec`):

- `/sys/kernel/debug/ec/ec0/io` when `CONFIG_ACPI_EC_DEBUGFS` / `ec_sys` is enabled
- Still 8-bit ACPI EC, not WMI
- Only `05901221-D566-11D1-B2F0-00A0C9062910/bmof` is Binary MOF (`bmf2mof`, not `bmfdec`). How to pick the EC GUID: [linux-wmi.md](linux-wmi.md#how-to-identify-the-ec-access-guid)

## Side-by-side

| | OneXConsole WinRing0 | OneXConsole OxpWMI | Linux oxpec |
|---|---|---|---|
| Transport | Ring-0 port I/O | WMI `SuRwECRegInterface` | ACPI EC (`ec_read`/`ec_write`) |
| Ports | 0x66 / 0x62 | none | 0x66 / 0x62 (inside ACPI EC) |
| Address | 8-bit | 16-bit `GroupOffset` (`0x400+reg`) | 8-bit |
| Lock | process `ECLocker` | firmware WMI | ACPI global lock, 500 ms |
| Read cache | `readCache` | not indicated | none |
| Privilege | signed `.sys` | normal WMI | kernel module |
| Platform in this repo | AMD | Intel G3E | whatever DMI table matches |

## Functional gaps vs OneXConsole

`oxpec` (upstream snapshot used for this note) is a subset of what OneXConsole programs.

**Access**

- No WMI backend → Intel G3E may need ACPI EC to be present, or a new `SuRwECRegInterface` driver.
- No `0x400` group encoding; Linux always uses the low 8 bits.

**DMI**

- Present as `oxp_fly` (recent): `ONEXPLAYER X2Mini PRO` (fan/turbo only in that profile).
- Not in the table: `ONEXPLAYER X2Mini`, `ONEXPLAYER X2`, `ONEXPLAYER X2 EVA`, `ONEXPLAYER 3`, `ONEXPLAYER Apex Air`, `ONEXPLAYER Apex i`.
- Those Intel SKUs match the X1/OXP2 register set (fan `0x58`, turbo `0xEB`, PWM 0–184), not `oxp_fly`.

**Registers OneXConsole uses that oxpec does not**

| Register | Role |
|---|---|
| `0x60` / `0x61` | board sensors |
| `0x70` | CPU temp (`useEcCpuTemp`) |
| `0xA0` | battery temp |
| `0xA1` / `0xA2` | charge current (16-bit BE) |
| `0xA5` or `0xE7` | force-charge minimum |
| `0xE3` | power-supply mode |
| `0x2D` | detachable-handle power |
| `0xED` | “set TDP allowed” gate |

**Registers oxpec has, with mismatches**

| Feature | oxpec | OneXConsole |
|---|---|---|
| Fan / PWM / turbo | yes, per-board | yes, two maps |
| Charge limit / inhibit | `0xA3` / `0xA4` on fly/X1/G1 | Intel G3E: `0xA3`–`0xA5`; **AMD map: `0xE5`–`0xE7`** |
| Turbo LED | X1 `0x57` | not used on G3E / Mini PRO in this build |
| PWM scale | 0–184 (x1/2), 0–255 (fly), 0–100 (old mini) | 0–184 G3E, 0–255 AMD |

TDP watts stay out of the EC on both sides (MSR / `ryzenadj` vs `oxpec` which does not set TDP).

## Implications for SteamOS

1. **AMD (X2 Mini PRO)** — `oxpec` + ACPI EC is the right shape. Add DMI if missing; switch charge to `0xE5`/`0xE6`/`0xE7`; optionally expose `0xE3` / `0x2D` / sensors.
2. **Intel G3E** — first confirm `/sys/kernel/debug/ec/ec0/io` or `ec_read` works. If it does, add DMI as an X1-like board (fan `0x58`, turbo `0xEB`, PWM 0–184, charge `0xA3`–`0xA5`). If ACPI EC is absent, add a WMI client modeled on `msi-wmi-platform`’s `wmidev_evaluate_method` loop, bound to the OneXPlayer GUID from `SuRwECRegInterface`’s `guid` qualifier or from `_WDG`+`WMxx` AML (do not reuse `ABBC0F6E` / `MSI_ACPI`). Methods stay `ReadECReg` / `WriteECReg` with `GroupOffset = 0x400 + reg`. See [linux-wmi.md](linux-wmi.md).
3. Do not use WinRing0-style port I/O from Linux userspace; use ACPI EC or WMI.
