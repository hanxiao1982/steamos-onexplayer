# OneXPlayer EC register maps

Research notes from official **OneXConsole 0.10.2-fix8** (download API `https://app.onexconsole.com/web/agg/app:download`).

Installer and unpacked binaries are **not** in this repo.

Manufacturer match: `Manufacturer` contains `ONE-NETBOOK`.

## Platforms

Two EC maps in this generation. Products that share a map are listed together.

| Platform | Products (DMI `Product`) | Access | Fan RPM | Turbo | PWM | Charge | Doc |
|---|---|---|---|---|---|---|---|
| Intel Arc G3 Extreme | `ONEXPLAYER X2Mini`, `ONEXPLAYER X2`, `ONEXPLAYER X2 EVA`, `ONEXPLAYER 3`, `ONEXPLAYER Apex Air`, `ONEXPLAYER Apex i` | OxpWMI (`ecAccessType=2`) | `0x58`/`0x59` | `0xEB` | `0x4A`/`0x4B`, 0–184 | `0xA3`/`0xA4` (`0xA5` unused) | [x2-mini.md](x2-mini.md) |
| AMD (Strix Halo / Fly) | `ONEXPLAYER X2Mini PRO`, `ONEXPLAYER APEX` | WinRing0 (`ecAccessType=1`) | `0x76`/`0x77` | `0xF1` | `0x4A`/`0x4B`, 0–255 | `0xE5`/`0xE6`/`0xE7` | [x2-mini-pro.md](x2-mini-pro.md) |

Shared on both maps: handle power `0x2D` (on=`1`, off=`0`), power-supply mode `0xE3`, TDP-able gate `0xED`, sensors `0x60`/`0x61`/`0x70`/`0xA0`. On X2 Mini, `0xA1`/`0xA2` (charge current) and `0xA5` (force-charge min) are present in OneXConsole init but unused in live reads.

TDP watts are not EC registers (Intel MSR / AMD ryzenadj). RGB, rumble, and gyro are HID (`CommonHid`).

Linux `oxpec` treats X2 Mini PRO as `oxp_fly` for fan/turbo, but still uses charge `0xA3`/`0xA4`. OneXConsole uses **`0xE5`/`0xE6`/`0xE7`** on the AMD map.

## How OneXConsole talks to the EC

See [access.md](access.md) for the two backends and the Linux `oxpec` comparison. Intel G3E WMI vs in-tree MSI Claw (`msi-wmi-platform`): [linux-wmi.md](linux-wmi.md). Local HTTP/pipe API (port **1013**): [onexconsole-api.md](onexconsole-api.md).

Short version:

1. Electron app (`background.js`) selects the per-model address table and POSTs to CompatLayerCT (`http://localhost:1013` or named pipe `\\.\pipe\CompatLayerCT`).
2. `CompatLayerCT.exe` performs the read/write.
3. Backends:
   - **1 = WinRing0** (AMD): `ReadIoPortByte` / `WriteIoPortByte` on 0x66/0x62
   - **2 = OxpWMI** (Intel G3E): WMI `SuRwECRegInterface` (`ReadECReg` / `WriteECReg`)
4. App addresses are `0x400 + ec_reg`. WinRing0 uses the low 8 bits; WMI uses the full 16-bit `GroupOffset`.

Fan RPM is 16-bit big-endian (first register is the high byte), same as Linux `oxpec`.

## Files

- [x2-mini.md](x2-mini.md) — Intel G3E map (X2 Mini and other G3E products)
- [x2-mini-pro.md](x2-mini-pro.md) — AMD map (X2 Mini PRO / APEX)
- [access.md](access.md) — WinRing0 vs OxpWMI vs Linux oxpec
- [onexconsole-api.md](onexconsole-api.md) — localhost:1013 / named-pipe routes (F12 / proxy)
- [linux-wmi.md](linux-wmi.md) — kernel WMI files and MSI Claw G3E comparison
- [maps.yaml](maps.yaml) — machine-readable tables
- [charge.md](charge.md) — charge-limit / bypass / force-min ranges and read-only probe
