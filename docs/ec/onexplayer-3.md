# OneXPlayer 3 EC map

Source: OneXConsole **0.10.2-fix8**. DMI / `Product` is `ONEXPLAYER 3` (no EVA / Pro / i variant string in this build).

## Identity

| Item | Value |
|---|---|
| DMI `Product` | `ONEXPLAYER 3` |
| CPU | forced `Intel` |
| `ecAccessType` | 2 (OxpWMI) |
| Screen | landscape |
| Handle image key | `OXP3` |
| Handle stack | `CommonHid`, RGB partition mode, HOME + G/M3 program-handle |
| PWM max | 184 |
| TDP | max 35 W, boost 36 W, unlock 40/41 W, default 25 W |
| PL2 | `tdp+1`, or 36 at cap |
| PL4 | modes 1–5 → 160; 8–9 → 120 |

EC offsets match Intel X2-class (X2 Mini / X2 / Apex Air), not X2 Mini PRO.

## Register map

Addresses are 8-bit ACPI EC RAM offsets (`encoded = 0x400 + offset` in OneXConsole).

| Function | CompatLayerCT field | Register | Values |
|---|---|---|---|
| Fan RPM high | `EC_ADDR_FAN_SPEED_H` | `0x58` | 16-bit BE with next byte |
| Fan RPM low | `EC_ADDR_FAN_SPEED_L` | `0x59` | |
| PWM enable / auto | `EC_ADDR_FAN_AUTOMATE` | `0x4A` | `0` auto, `1` manual |
| PWM duty | `EC_ADDR_FAN_SPEED` | `0x4B` | 0–184 |
| Turbo / app-fun | `EC_ADDR_APP_FUN_EN` | `0xEB` | Linux `oxpec` mask `0x40` |
| Handle power | `EC_ADDR_HANDLE_POWER` | `0x2D` | on=`1`, off=`0` |
| Charge limit % | `EC_ADDR_CHARGE_LIMIT` | `0xA3` | 0–100 |
| Charge bypass | `EC_ADDR_BYPASS_POWER` | `0xA4` | `0` / `1` / `3` |
| Force-charge min | `EC_ADDR_FORCE_CHARGE_MIN` | `0xA5` | |
| Power-supply mode | `EC_ADDR_POWER_SUPPLY_MODE` | `0xE3` | |
| TDP-able gate | `EC_ADDR_OXP_SET_TDP_ABLE` | `0xED` | watts via Intel MSR |
| Board sensor 1 | `EC_ADDR_OXP_BOARD_SENSOR1` | `0x60` | |
| Board sensor 2 | `EC_ADDR_OXP_BOARD_SENSOR2` | `0x61` | |
| CPU temp | `EC_ADDR_OXP_CPU_TEMP` | `0x70` | `useEcCpuTemp=true` |
| Battery temp | `EC_ADDR_OXP_BATTERY_TEMP` | `0xA0` | |
| Charge current | `EC_ADDR_OXP_BATTERY_CHARGE_CURRENT_H/L` | `0xA1` / `0xA2` | 16-bit BE |

JS overrides: `w=1259, k=1112, C=1113, A=184, N=3, E=1069, I=1, R=0`. Charge addresses stay at defaults (`0xA3/0xA4/0xA5`).

`adjustPowerSupplyModeFunc` remaps raw modes `500` and `501` to `1`.

## Not EC

- TDP PL1/PL2/PL4: Intel MSR (`/msr/setCpuPl`)
- RGB: HID partition mode (`rgbPartitionList`)
- Gyro / rumble: HID
