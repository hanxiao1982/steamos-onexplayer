# oxpec — OneXPlayer direct EC profiles

This document is the source of truth for OneXPlayer models that OneXConsole 0.10.2-fix8 assigns `ECAccessType.WinRing0 = 1`.

`WinRing0` is a Windows implementation detail. On Linux these devices belong to the `oxpec` driver family and should use the kernel ACPI EC path (`ec_read()` / `ec_write()`) with the ACPI global lock. The DMI table and register profile are the important parts; Linux must not depend on WinRing0.

See [README.md](README.md) for the access-type split and [onexconsole-api.md](onexconsole-api.md) for the OneXConsole/CompatLayerCT reverse-engineering details.

## Source and matching rules

OneXConsole reads `Win32_BaseBoard.Manufacturer` and `Win32_BaseBoard.Product`. For the modern branch the manufacturer contains `ONE-NETBOOK` and the product is compared as an **exact string**.

Linux should therefore prefer exact `DMI_BOARD_NAME` matches. Do not collapse products by prefix: OneXConsole contains several devices with similar names but different register profiles.

All addresses below are shown in the 16-bit form used by OneXConsole (`0x04xx`). Linux ACPI EC accesses use the low byte (`0xxx`) unless a future device proves that a banked/direct-ECRAM mechanism is required.

## Shared register semantics

| Function | OneXConsole address | Linux offset | Meaning |
|---|---:|---:|---|
| Fan auto/manual | `0x044A` | `0x4A` | `0` auto, `1` manual |
| Fan PWM | `0x044B` | `0x4B` | Scale depends on profile |
| CPU temperature | `0x0470` | `0x70` | Degrees C |
| Board sensor 1/2 | `0x0460` / `0x0461` | `0x60` / `0x61` | Optional sensors |
| Battery temperature | `0x04A0` | `0xA0` | Optional sensor |
| Charge current H/L | `0x04A1` / `0x04A2` | `0xA1` / `0xA2` | BE16, optional |
| Power-supply mode | usually `0x04E3` | `0xE3` | Optional status byte; `SUPER X` differs |

Fan RPM is 16-bit big-endian: `(rpm_hi << 8) | rpm_lo`.

Charge-limit UI range is 50–100 in steps of 5, while the EC byte is a percent. Bypass values used by the modern profiles are `0` = normal, `1` = inhibit while awake, `3` = inhibit always. Treat the third force-charge register as source-mapped but do not expose it unless hardware testing gives it a clear user-visible purpose.

## Profile families

These names are documentation labels, not OneXConsole enum values.

### Profile OXP-EB184

| Field | Value |
|---|---:|
| App-function | `0x04EB` |
| Fan RPM H/L | `0x0458` / `0x0459` |
| Fan mode / PWM | `0x044A` / `0x044B` |
| PWM max | **184** |
| Default charge registers | `0x04A3` / `0x04A4` / `0x04A5` |

Exact board products:

- `ONEXPLAYER 2 ARP23`
- `ONEXPLAYER 2 PRO ARP23P`
- `ONEXPLAYER 2 PRO ARP23P EVA-01`
- `ONEXPLAYER 1Pro`
- `ONEXPLAYER X1 i`
- `ONEXPLAYER X1 A`
- `ONEXPLAYER X1 mini`
- `ONEXPLAYER M1`
- `ONEXPLAYER X1Pro`
- `ONEXPLAYER X1Pro B`
- `ONEXPLAYER X1Mini Pro`
- `ONEXPLAYER X1z`
- `ONEXPLAYER X1Pro i`
- `ONEXPLAYER X1Pro EVA-02`
- `ONEXPLAYER G1 i`
- `ONEXPLAYER X1Pro A EVA-02`
- `ONEXPLAYER X1Air`

Handle-power overrides inside this family:

| Products | Address | On / off / restore |
|---|---:|---|
| `X1 i`, `X1Pro i`, `X1Pro EVA-02`, `G1 i`, `X1Air` | `0x044E` | `0x87 / 0x86 / 0x07` |
| `X1 A`, `X1 mini`, `X1Pro`, `X1Mini Pro`, `X1z`, `X1Pro A EVA-02` | `0x042D` | product branch uses the `0x00 / 0x01` pair |

Do not infer handle-power behavior for products not listed in these subgroups.

### Profile OXP-EB255

Same app-function and RPM offsets as OXP-EB184, but PWM max is **255**.

| Board product | Notable difference |
|---|---|
| `ONEXPLAYER 2 GA18` | PWM max 255 |
| `ONEXPLAYER 2 GA72-R` | PWM max 255 |
| `ONEXStation` | PWM max 255; PC-mode branch |

This is an important correction to broad upstream mappings: `ONEXPLAYER 2` devices cannot all be assigned a single 184-scale profile.

### Profile OXP-F1-255

| Field | Value |
|---|---:|
| App-function | `0x04F1` |
| Fan RPM H/L | `0x0476` / `0x0477` |
| Fan mode / PWM | `0x044A` / `0x044B` |
| PWM max | **255** |
| Default charge registers | `0x04A3` / `0x04A4` / `0x04A5` |

Exact board products:

- `ONEXPLAYER Mini Pro`
- `ONEXPLAYER F1`
- `ONEXPLAYER F1 EVA-01`
- `ONEXPLAYER F1L`
- `ONEXPLAYER F1 OLED`
- `ONEXPLAYER F1 EVA-02`
- `ONEXPLAYER F1Pro`
- `ONEXPLAYER G1 A`
- `ONEXPLAYER SUPER X`

Notes:

- `ONEXPLAYER F1` and `ONEXPLAYER F1 EVA-01` gate battery-protection support on EC firmware version in OneXConsole.
- `ONEXPLAYER G1 A` is not the same register family as `ONEXPLAYER G1 i`.
- `ONEXPLAYER SUPER X` uses **`0x04FE`** for the power-supply-mode address rather than the common `0x04E3`.
- `ONEXPLAYER G1 A` has a product-specific handle-power on value (`7`) in OneXConsole; do not merge its handle profile with X1 Intel/AMD variants.

### Profile OXP-F1-E5-255

This is the modern AMD APEX / X2 Mini PRO profile.

| Field | Value |
|---|---:|
| App-function | `0x04F1` |
| Fan RPM H/L | `0x0476` / `0x0477` |
| Fan mode / PWM | `0x044A` / `0x044B` |
| PWM max | **255** |
| Charge limit | **`0x04E5`** |
| Charge bypass | **`0x04E6`** |
| Force-charge minimum | **`0x04E7`** |
| Handle power | `0x042D`, branch uses `1 / 0` |

Exact board products:

- `ONEXPLAYER APEX`
- `ONEXPLAYER X2Mini PRO`

This profile is confirmed from OneXConsole. `ONEXPLAYER X2Mini PRO` must not be matched as `ONEXPLAYER X2Mini`; they use different access types and different register maps.

The in-tree `oxpec` mapping that treats Fly-family charge as `0xA3/0xA4` should not be considered authoritative for these two products. Live hardware validation is still required before changing user-visible charge controls.

## Legacy/OEM branches

These are outside the modern `Manufacturer contains ONE-NETBOOK` branch but are still recognized by OneXConsole:

| Board Manufacturer | Board Product | Access | Profile facts recovered |
|---|---|---|---|
| `IP3 Technology CO.,Ltd.` | `ARP26` | type 1 | `0x04EB`, RPM `0x0458/0x0459`, PWM max 184 |
| `ONE-NETBOOK TECHNOLOGY CO., LTD.` | `ONE XPLAYER` | type 1 | Intel variant uses fan-control `0x04C4` with off value `0x88`; AMD variant uses PWM max 100 |

Keep these as explicit legacy profiles rather than forcing them into a modern family until their complete per-branch register initialization is extracted and/or live-tested.

## DMI corrections relative to community tables

The current OneXConsole build uses these exact strings:

- `ONEXPLAYER 2 PRO ARP23P`
- `ONEXPLAYER 2 PRO ARP23P EVA-01`
- `ONEXPLAYER 2 GA72-R`

The missing-`P` `ARP23` Pro strings seen in some community tables are not the strings matched by this OneXConsole build.

Other pairs that must stay distinct:

- `ONEXPLAYER X2Mini` (OxpWMI) vs `ONEXPLAYER X2Mini PRO` (oxpec)
- `ONEXPLAYER APEX` (oxpec) vs `ONEXPLAYER Apex i` / `Apex Air` (OxpWMI)
- `ONEXPLAYER G1 A` (`F1/76-77/255`) vs `ONEXPLAYER G1 i` (`EB/58-59/184`)
- `ONEXPLAYER SUPER X` (oxpec) vs `ONEXPLAYER SUPER V` (OxpWMI)

## Linux driver design notes

`oxpec` should own only the exact DMI entries in this document. The `oxp-wmi` module owns the type-2 devices in [oxp-wmi.md](oxp-wmi.md).

A useful refactor is a profile-driven table rather than a coarse board-family enum. At minimum the profile needs per-device fields for app-function, RPM pair, PWM scale, charge registers, handle-power values, and power-supply register.

Do not load both drivers for one DMI. The presence of `SuRwECRegInterface` in firmware does **not** mean that a product belongs to `oxp-wmi`; some type-1 machines expose the WMI class but OneXConsole deliberately uses the direct EC backend.

## Validation status

- Register/address selection: **confirmed from OneXConsole 0.10.2-fix8**.
- Existing Linux `oxpec` behavior: useful as implementation evidence, but not the source of truth for model grouping.
- `ONEXPLAYER X2Mini PRO` / APEX E5/E6/E7: source-confirmed; live validation still desirable before changing charge sysfs behavior.
- Legacy `ONE XPLAYER` / `ARP26`: only the recovered branch-specific facts above should be relied on until the full legacy initialization is reconstructed.
