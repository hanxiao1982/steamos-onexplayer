# OneXPlayer EC register maps

Research notes from official **OneXConsole 0.10.2-fix8** (download API `https://app.onexconsole.com/web/agg/app:download`).

Installer and unpacked binaries are **not** in this repo.

Manufacturer match: `Manufacturer` contains `ONE-NETBOOK`.

## Platforms

Two EC maps in this generation. Products that share a map are listed together.

| Platform | Products (DMI `Product`) | Access | Fan RPM | Turbo | PWM | Charge | Doc |
|---|---|---|---|---|---|---|---|
| Intel Arc G3 Extreme | `ONEXPLAYER X2Mini`, `ONEXPLAYER X2`, `ONEXPLAYER X2 EVA`, `ONEXPLAYER 3`, `ONEXPLAYER Apex Air`, `ONEXPLAYER Apex i` | OxpWMI (`ecAccessType=2`) | `0x58`/`0x59` | — (`0xEB` unused) | `0x4A`/`0x4B`, 0–184 | `0xA3`/`0xA4` | [x2-mini.md](x2-mini.md) |
| AMD (Strix Halo / Fly) | `ONEXPLAYER X2Mini PRO`, `ONEXPLAYER APEX` | WinRing0 (`ecAccessType=1`) | `0x76`/`0x77` | `0xF1` | `0x4A`/`0x4B`, 0–255 | `0xE5`/`0xE6`/`0xE7` | [x2-mini-pro.md](x2-mini-pro.md) |

**X2 Mini live is complete** for the EC subset SteamOS needs: [x2-mini.md](x2-mini.md). Use fan `0x4A`/`0x4B`/`0x58`/`0x59`, charge `0xA3`/`0xA4`, CPU temp `0x70`, optional `0xE3`. Ignore `0x2D`, `0x60`/`0x61`, `0xA0`–`0xA2`, `0xA5`, `0xEB` (stuck at 66 / `0x42`), `0xED` (always 0). TDP is Intel RAPL (`TdpLimit1` remote), not EC — [tdp.md](tdp.md). CPU turbo/clock is host power policy. RGB/rumble/gyro is HID.

**X2 Mini PRO** is source-mapped only (no live reads): [x2-mini-pro.md](x2-mini-pro.md). WinRing0, fan `0x76`/`0x77` PWM 0–255, charge **`0xE5`/`0xE6`/`0xE7`**, turbo addr `0xF1`. Linux `oxpec` `oxp_fly` still uses charge `0xA3`/`0xA4` — that is a mismatch to fix after live check.

## How OneXConsole talks to the EC

See [access.md](access.md) for the two backends and the Linux `oxpec` comparison. Intel G3E WMI vs in-tree MSI Claw (`msi-wmi-platform`): [linux-wmi.md](linux-wmi.md). Local HTTP/pipe API (port **1013**): [onexconsole-api.md](onexconsole-api.md).

Short version:

1. Electron app (`background.js`) selects the per-model address table and POSTs to CompatLayerCT (`http://localhost:1013` or named pipe `\\.\pipe\CompatLayerCT`).
2. `CompatLayerCT.exe` performs the read/write.
3. Backends:
   - **1 = WinRing0** (AMD): `ReadIoPortByte` / `WriteIoPortByte` on 0x66/0x62
   - **2 = OxpWMI** (Intel G3E): WMI `SuRwECRegInterface` (`ReadECReg` / `WriteECReg`)
4. App addresses are `0x400 + ec_reg`. WinRing0 uses the low 8 bits. OxpWMI CIM/Linux packing is `0x04 | (reg << 8)` (JS `0x400+reg` is rejected).

Fan RPM is 16-bit big-endian (first register is the high byte), same as Linux `oxpec`.

## Files

- [x2-mini.md](x2-mini.md) — Intel G3E map + X2 Mini live vs OneXConsole
- [x2-mini-pro.md](x2-mini-pro.md) — AMD map, source-only (live later)
- [access.md](access.md) — WinRing0 vs OxpWMI vs Linux oxpec
- [onexconsole-api.md](onexconsole-api.md) — localhost:1013 / named-pipe routes (F12 / proxy)
- [compatlayerct-uritemplates.md](compatlayerct-uritemplates.md) — full WCF UriTemplate scan of CompatLayerCT.exe 0.10.2-fix8
- [linux-wmi.md](linux-wmi.md) — kernel WMI files and MSI Claw G3E comparison
- [oxp-wmi.md](oxp-wmi.md) — Linux `oxp-wmi` module (OneXPlayer Intel / OxpWMI)
- [tdp.md](tdp.md) — Steam `TdpLimit1` / Intel RAPL (not EC)
- [../../linux/oxp-wmi/](../../linux/oxp-wmi/) — driver sources
- [maps.yaml](maps.yaml) — machine-readable tables
- [charge.md](charge.md) — charge-limit / bypass / force-min ranges and read-only probe
- [fan.md](fan.md) — fan PWM / RPM (X2 Mini; Linux `oxp-wmi` writes live)
- [ui-vs-ec.md](ui-vs-ec.md) — which OneXConsole controls are EC vs MSR/HID
