# X2 (and the “X2 Air” name)

OneXConsole **0.10.2-fix8** has no `X2 Air` / `X2Air` product string. The 2026 Air handheld is documented separately as [Apex Air](apex-air.md). OneXPlayer 3 is [onexplayer-3.md](onexplayer-3.md).

This page is only the large 10.95" 3-in-1: `ONEXPLAYER X2` / `ONEXPLAYER X2 EVA`. It uses the same Intel X2-class EC offsets as X2 Mini / Apex Air / OneXPlayer 3 (not X2 Mini PRO).

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

## What is not EC on this machine

- TDP PL1/PL2/PL4: Intel MSR (`intelTdpSetType`, `/msr/setCpuPl`)
- RGB: HID `CommonHid` (`/programhandle/rgb/*`)
- Gyro / rumble: HID + ViGEm-style helper, not EC RAM
