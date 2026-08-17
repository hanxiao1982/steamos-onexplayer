# “X2 Air” and related 2026 models

## Naming

OneXConsole **0.10.2-fix8** product table has **no** X2 Air SKU:

```
ONEXPLAYER X2
ONEXPLAYER X2 EVA
ONEXPLAYER X2Mini
ONEXPLAYER X2Mini PRO
ONEXPLAYER Apex Air      # the 2026 “Air” handheld
ONEXPLAYER Apex i
```

Official 2026 summer lineup is X2 (10.95" 3-in-1), X2 Mini, and **Apex Air** (ONEXFLY-class 8" Intel handheld). If “X2 Air” was meant as that Air model, use the Apex Air map below. If it was meant as the large X2 tablet, that map is listed as well.

Both are **Intel X2-class** and share the same EC offsets as [X2 Mini](x2-mini-series.md) (not X2 Mini PRO).

## ONEXPLAYER X2 / X2 EVA

| Item | Value |
|---|---|
| DMI `Product` | `ONEXPLAYER X2` or `ONEXPLAYER X2 EVA` |
| CPU | forced `Intel` |
| `ecAccessType` | 2 (OxpWMI) |
| Screen | `landscapeScreen=false` (portrait / kickstand 3-in-1) |
| TDP | max 35 W, boost 36 W, unlock 40/41 W, default 25 W |
| PWM max | 184 |
| Handle image key | `X1` (not X2Mini) |
| RGB | `rgbModeType=2`, `rgbPlace0304`, startup RGB off |

EC offsets: identical to X2 Mini.

| Function | Register | Values |
|---|---|---|
| Fan RPM | `0x58` / `0x59` | 16-bit BE |
| PWM enable | `0x4A` | `0` auto, `1` manual |
| PWM duty | `0x4B` | 0–184 |
| Turbo / app-fun | `0xEB` | Linux mask `0x40` |
| Handle power | `0x2D` | on=`1`, off=`0` |
| Charge limit % | `0xA3` | 0–100 |
| Charge bypass | `0xA4` | `0` / `1` / `3` |
| Force-charge min | `0xA5` | |
| Power-supply mode | `0xE3` | |
| TDP-able gate | `0xED` | |
| Board / CPU / battery sensors | `0x60`, `0x61`, `0x70`, `0xA0`, `0xA1`, `0xA2` | same as Mini |

JS overrides: `w=1259, k=1112, C=1113, A=184, N=3, E=1069, I=1, R=0`.

## ONEXPLAYER Apex Air

| Item | Value |
|---|---|
| DMI `Product` | `ONEXPLAYER Apex Air` (same branch as `ONEXPLAYER Apex i`) |
| CPU | forced `Intel` |
| `ecAccessType` | 2 (OxpWMI) |
| Screen | landscape |
| TDP | default slider 25 W; boost 46 W or 66 W depending on an internal SKU flag `v`; QC maps go up to 45/65 W |
| PWM max | 184 |
| Handle image key | `APEX` |

EC offsets: **same Intel X2-class table as X2 Mini / X2**.

JS overrides: `w=1259, k=1112, C=1113, A=184, N=3, E=1069, I=1, R=0`.

Apex Air does **not** use the AMD APEX / X2 Mini PRO charge registers `0xE5–0xE7`. Those belong to `ONEXPLAYER APEX` and `ONEXPLAYER X2Mini PRO` only.

## What is not EC on these machines

- TDP PL1/PL2/PL4: Intel MSR (`intelTdpSetType`, `/msr/setCpuPl`)
- RGB: HID `CommonHid` (`/programhandle/rgb/*`)
- Gyro / rumble: HID + ViGEm-style helper, not EC RAM
