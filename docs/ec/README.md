# OneXPlayer EC register maps

Research notes extracted from official **OneXConsole 0.10.2-fix8** (Windows control software, download API `https://app.onexconsole.com/web/agg/app:download`).

This directory contains only reconstructed maps and analysis. The installer, `app.asar`, `CompatLayerCT.exe`, WinRing0, and other unpacked binaries are **not** stored in the repo.

## Scope

| Model | DMI / OneXConsole `Product` | Status |
|---|---|---|
| X2 Mini (Intel) | `ONEXPLAYER X2Mini` | [x2-mini-series.md](x2-mini-series.md) |
| X2 Mini PRO (AMD) | `ONEXPLAYER X2Mini PRO` | [x2-mini-series.md](x2-mini-series.md) |
| Apex Air (Intel) | `ONEXPLAYER Apex Air` | [apex-air.md](apex-air.md) |
| OneXPlayer 3 (Intel) | `ONEXPLAYER 3` | [onexplayer-3.md](onexplayer-3.md) |
| X2 / X2 EVA | `ONEXPLAYER X2`, `ONEXPLAYER X2 EVA` | [x2-air.md](x2-air.md) |

There is no `X2 Air` / `X2Air` product string. The 2026 Air handheld is **Apex Air**.

Manufacturer match is `Manufacturer` contains `ONE-NETBOOK`.

## How OneXConsole talks to the EC

1. Electron app (`background.js`) picks a per-model address table.
2. Native helper `CompatLayerCT.exe` performs the actual read/write.
3. Two access backends (`ecAccessType`):
   - **1 = WinRing0** (default, used by X2 Mini PRO / AMD): `WinRing0x64.sys` port I/O.
   - **2 = OxpWMI** (Intel X2 / X2 Mini / Apex Air / OneXPlayer 3): `ECOxpWMI`.
4. Standard ACPI EC ports (field names in `CompatLayerCT`):
   - command/status: `EC_ADDR_STATUS_COMMAND_PORT` (0x66)
   - data: `EC_ADDR_DATA_PORT` (0x62)

TDP watts are **not** written as EC registers. Intel models use MSR (`/msr/setCpuPl`); AMD models use `ryzenadj`. The EC only exposes a “TDP-able” gate and the turbo-button takeover bit.

RGB / rumble / gyro on these models go through HID (`programHandleType: CommonHid`), not the EC RAM map below.

## Address encoding

OneXConsole passes **encoded** addresses to `CompatLayerCT`:

```
encoded = 0x400 + ec_reg     # 1024 + register
ec_reg  = encoded & 0xFF     # also encoded - 1024
```

Example: PWM enable `0x4A` is sent as `1098` (`0x44A`).

Fan RPM is a 16-bit big-endian pair: first register is the high byte (same convention as Linux `oxpec`).

## Two EC families in this generation

| Family | Models | Fan RPM | Turbo / app-fun | PWM range | Charge limit |
|---|---|---|---|---|---|
| Intel X2-class | X2 Mini, X2, X2 EVA, OneXPlayer 3, Apex i, Apex Air | `0x58`/`0x59` | `0xEB` | 0–184 | `0xA3`/`0xA4`/`0xA5` |
| AMD Fly-class | X2 Mini PRO (same board family as APEX) | `0x76`/`0x77` | `0xF1` | 0–255 | `0xE5`/`0xE6`/`0xE7` |

Linux `oxpec` already treats X2 Mini PRO as `oxp_fly` for fan/turbo, but still uses charge registers `0xA3`/`0xA4`. Official OneXConsole uses **`0xE5`/`0xE6`/`0xE7`** for X2 Mini PRO (and APEX). That difference matters for SteamOS charge-limit support.

## Files

- [x2-mini-series.md](x2-mini-series.md) — X2 Mini + X2 Mini PRO
- [apex-air.md](apex-air.md) — Apex Air (and Apex i)
- [onexplayer-3.md](onexplayer-3.md) — OneXPlayer 3
- [x2-air.md](x2-air.md) — X2 / X2 EVA; note that “X2 Air” is not a SKU
- [maps.yaml](maps.yaml) — machine-readable tables

## Sources inside the installer (not committed)

| Artifact | Role |
|---|---|
| `resources/app.asar` → `background.js` | Per-model DMI match and encoded address overrides |
| `resources/resources/CompatLayerCT.exe` | EC field names, defaults, `/func/*` `/fan/*` `/battery/*` APIs |
| `resources/resources/wr0_build.7z` | WinRing0 backend (access type 1) |
| `resources/resources/base_build.7z` | `inpoutx64.dll`, `ryzenadj`, HID helpers |
