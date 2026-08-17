# AMD EC map (X2 Mini PRO)

Source: OneXConsole **0.10.2-fix8**.

X2 Mini PRO is the AMD (Strix Halo) SKU. It does **not** share the Intel G3E map used by X2 Mini: [x2-mini.md](x2-mini.md).

## Products on this map

| Marketing | DMI `Product` | Notes |
|---|---|---|
| X2 Mini PRO | `ONEXPLAYER X2Mini PRO` | CPU detected as AMD; handle key `X2Mini`; TDP 55/70 W, default 45 W, DC-in 80 W |
| APEX | `ONEXPLAYER APEX` | same charge/turbo/fan overrides; cooling dock 120 W when BIOS contains `onec1` |

`ecAccessType` stays at the default **1 (WinRing0)**. `openQCSetTdp=false` on X2 Mini PRO.

Kernel DMI board name for the Mini PRO patch: `ONEXPLAYER X2Mini PRO`. Linux `oxpec` uses `oxp_fly` for fan/turbo; official charge registers here are **`0xE5`/`0xE6`/`0xE7`**, not `oxpec`’s `0xA3`/`0xA4`.

## Register map

8-bit ACPI EC RAM. OneXConsole wire format is `0x400 + offset`.

| Function | CompatLayerCT field | Register | Values |
|---|---|---|---|
| Fan RPM high | `EC_ADDR_FAN_SPEED_H` | `0x76` | 16-bit BE with next byte |
| Fan RPM low | `EC_ADDR_FAN_SPEED_L` | `0x77` | |
| PWM enable / auto | `EC_ADDR_FAN_AUTOMATE` | `0x4A` | `0` auto, `1` manual |
| PWM duty | `EC_ADDR_FAN_SPEED` | `0x4B` | **0–255** (unscaled) |
| Turbo / app-fun | `EC_ADDR_APP_FUN_EN` | `0xF1` | Linux `oxpec` mask `0x40` |
| Handle power | `EC_ADDR_HANDLE_POWER` | `0x2D` | on=`1`, off=`0` (restore unused, `-1`) |
| Charge limit % | `EC_ADDR_CHARGE_LIMIT` | **`0xE5`** | 0–100 |
| Charge bypass | `EC_ADDR_BYPASS_POWER` | **`0xE6`** | `0` off, `1` awake, `3` always |
| Force-charge min | `EC_ADDR_FORCE_CHARGE_MIN` | **`0xE7`** | |
| Power-supply mode | `EC_ADDR_POWER_SUPPLY_MODE` | `0xE3` | |
| TDP-able gate | `EC_ADDR_OXP_SET_TDP_ABLE` | `0xED` | watts via ryzenadj |
| Board sensor 1 | `EC_ADDR_OXP_BOARD_SENSOR1` | `0x60` | |
| Board sensor 2 | `EC_ADDR_OXP_BOARD_SENSOR2` | `0x61` | |
| CPU temp | `EC_ADDR_OXP_CPU_TEMP` | `0x70` | `useEcCpuTemp=true` |
| Battery temp | `EC_ADDR_OXP_BATTERY_TEMP` | `0xA0` | |
| Charge current | `EC_ADDR_OXP_BATTERY_CHARGE_CURRENT_H/L` | `0xA1` / `0xA2` | 16-bit BE |

`fanMode` is `"common"`. BIOS version containing `onec1` enables the cooling-system 120 W path.

## Init (OneXConsole)

```
setECAccessType(1)
initBaseEc(0xF1, 0x76, 0x77)          # JS defaults: 1265, 1142, 1143
initPowerSupplyModeEC(0xE3)           # JS: 1251
fan/init(common, 0x4A, 0, 1, 0x4B, 255)
initHandleEc(0x2D, 1, 0, -1)          # JS: 1069, 1, 0, -1
initOXPSensorEc(0x60, 0x61, 0x70, 0xA0, 0xA1, 0xA2)
battery/initEc(0xE5, 0xE6, 0xE7, 0, 1, 3)   # JS: 1253, 1254, 1255, N=3
```

TDP PL1/PL2: `ryzenadj`. RGB / gyro / rumble: HID.
