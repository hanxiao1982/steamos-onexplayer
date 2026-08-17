# Intel Arc G3 Extreme EC map (X2 Mini)

Source: OneXConsole **0.10.2-fix8**.

X2 Mini is the Intel G3E SKU. The same EC offsets are used by the other G3E products below. X2 Mini PRO is a different (AMD) platform: [x2-mini-pro.md](x2-mini-pro.md).

## Products on this map

| Marketing | DMI `Product` | Notes |
|---|---|---|
| X2 Mini | `ONEXPLAYER X2Mini` | landscape; handle key `X2Mini`; TDP 45/46 W, default 25 W |
| X2 | `ONEXPLAYER X2` | 10.95" 3-in-1, `landscapeScreen=false`; handle key `X1`; TDP 35/36 W, unlock 40 W |
| X2 EVA | `ONEXPLAYER X2 EVA` | same branch as X2 |
| OneXPlayer 3 | `ONEXPLAYER 3` | handle key `OXP3`; RGB partition; TDP 35/36 W, unlock 40 W |
| Apex Air | `ONEXPLAYER Apex Air` | same branch as Apex i; handle key `APEX`; default 25 W, boost 46 or 66 W by SKU flag |
| Apex i | `ONEXPLAYER Apex i` | same EC init as Apex Air |

All of these force `deviceCpu=Intel`, `ecAccessType=2` (OxpWMI), `useEcCpuTemp`, `powerSupplyMode`, `enableBatteryProtection`, `programHandleType=CommonHid`.

## Register map

8-bit ACPI EC RAM. OneXConsole wire format is `0x400 + offset`.

| Function | CompatLayerCT field | Register | Values |
|---|---|---|---|
| Fan RPM high | `EC_ADDR_FAN_SPEED_H` | `0x58` | 16-bit BE with next byte |
| Fan RPM low | `EC_ADDR_FAN_SPEED_L` | `0x59` | |
| PWM enable / auto | `EC_ADDR_FAN_AUTOMATE` | `0x4A` | `0` auto, `1` manual |
| PWM duty | `EC_ADDR_FAN_SPEED` | `0x4B` | **0–184** |
| Turbo / app-fun | `EC_ADDR_APP_FUN_EN` | `0xEB` | Linux `oxpec` mask `0x40` |
| Handle power | `EC_ADDR_HANDLE_POWER` | `0x2D` | on=`1`, off=`0` (restore unused, `-1`) |
| Charge limit % | `EC_ADDR_CHARGE_LIMIT` | `0xA3` | **Live:** UI 50–100 step 5 writes this byte |
| Charge bypass | `EC_ADDR_BYPASS_POWER` | `0xA4` | **Live:** EC **0 / 1 / 3** (HTTP 0 / 1 / 2) |
| Force-charge min | `EC_ADDR_FORCE_CHARGE_MIN` | `0xA5` | **Ignore:** live value stuck at `5`, no UI |
| Power-supply mode | `EC_ADDR_POWER_SUPPLY_MODE` | `0xE3` | |
| TDP-able gate | `EC_ADDR_OXP_SET_TDP_ABLE` | `0xED` | watts via Intel MSR |
| Board sensor 1 | `EC_ADDR_OXP_BOARD_SENSOR1` | `0x60` | |
| Board sensor 2 | `EC_ADDR_OXP_BOARD_SENSOR2` | `0x61` | |
| CPU temp | `EC_ADDR_OXP_CPU_TEMP` | `0x70` | |
| Battery temp | `EC_ADDR_OXP_BATTERY_TEMP` | `0xA0` | |
| Charge current | `EC_ADDR_OXP_BATTERY_CHARGE_CURRENT_H/L` | `0xA1` / `0xA2` | **Ignore:** live BE16 always `0` |

`fanMode` is `"common"`. Closest Linux `oxpec` profile: `oxp_x1` / `oxp_2`. Read-only WMI probe: [fan.md](fan.md).

## Init (OneXConsole)

These calls only fill CompatLayerCT’s `EC_ADDR_*` table (plus `setECAccessType` opens OxpWMI). They are not an EC handshake. Raw `ReadECReg` does not need them. See [onexconsole-api.md](onexconsole-api.md#what-init-actually-does).

```
setECAccessType(2)
initBaseEc(0xEB, 0x58, 0x59)          # JS: 1259, 1112, 1113
initPowerSupplyModeEC(0xE3)           # JS: 1251
fan/init(common, 0x4A, 0, 1, 0x4B, 184)
initHandleEc(0x2D, 1, 0, -1)          # JS: 1069, 1, 0, -1
initOXPSensorEc(0x60, 0x61, 0x70, 0xA0, 0xA1, 0xA2)
battery/initEc(0xA3, 0xA4, 0xA5, 0, 1, 3)
```

Value ranges and a read-only WMI probe: [charge.md](charge.md).

TDP PL1/PL2/PL4: Intel MSR (`/msr/setCpuPl`). RGB / gyro / rumble: HID.
