# X2 Mini series EC map

Source: OneXConsole **0.10.2-fix8** device-detect table and `CompatLayerCT` EC defaults.

The installer only knows two X2 Mini SKUs. There is no extra “X2 Mini Air / EVA / i” product string in this build.

## Models

| Marketing | DMI `Product` | CPU in OneXConsole | `ecAccessType` | Linux `oxpec` analogue |
|---|---|---|---|---|
| X2 Mini | `ONEXPLAYER X2Mini` | forced `Intel` | 2 (OxpWMI) | closest: `oxp_x1` / `oxp_2` (fan `0x58`, turbo `0xEB`, PWM 0–184) |
| X2 Mini PRO | `ONEXPLAYER X2Mini PRO` | detected AMD (Strix Halo) | 1 (WinRing0, default) | `oxp_fly` for fan/turbo; **charge regs differ** |

Shared UI flags for both: landscape, `useEcCpuTemp`, `powerSupplyMode`, `enableBatteryProtection`, `programHandleType=CommonHid`, `phImageSrcKey=X2Mini`, RGB partition mode, 120 Hz.

## Register map

Addresses are 8-bit ACPI EC RAM offsets. OneXConsole encoding is `0x400 + offset` (see [README.md](README.md)).

### Fan

| Function | CompatLayerCT field | X2 Mini | X2 Mini PRO | Notes |
|---|---|---|---|---|
| Fan RPM high | `EC_ADDR_FAN_SPEED_H` | `0x58` | `0x76` | 16-bit BE with next byte |
| Fan RPM low | `EC_ADDR_FAN_SPEED_L` | `0x59` | `0x77` | |
| PWM enable / auto | `EC_ADDR_FAN_AUTOMATE` | `0x4A` | `0x4A` | `0` = EC auto, `1` = manual |
| PWM duty | `EC_ADDR_FAN_SPEED` | `0x4B` | `0x4B` | |
| PWM max written by app | `valueFanSpeedValue` | **184** | **255** | Intel family is scaled 0–184 |

`fanMode` stays `"common"` (not the ZA01 path).

### Turbo / app-function enable

Passed as `initBaseEc(appFunEN, fanH, fanL)`.

| Function | Field | X2 Mini | X2 Mini PRO |
|---|---|---|---|
| App-fun / turbo takeover | `EC_ADDR_APP_FUN_EN` | `0xEB` | `0xF1` |

Linux `oxpec` uses mask `0x40` on these registers (`tt_toggle`). OneXConsole also exposes `/func/takeOverTurboButton/{on}`.

### Handle power (detachable controllers)

`initHandleEc(addr, on, off, restore)`

| Function | Field | X2 Mini | X2 Mini PRO |
|---|---|---|---|
| Handle power | `EC_ADDR_HANDLE_POWER` | `0x2D` | `0x2D` |
| Power on | `EC_VALUE_HANDLE_POWER_ON` | `1` | `1` |
| Power off | `EC_VALUE_HANDLE_POWER_OFF` | `0` | `0` |
| Restore | `EC_VALUE_HANDLE_POWER_ON_RESTORE` | `-1` (unused) | `-1` |

Firmware default in `CompatLayerCT` is on=`3`, off=`2`. Both X2 Mini SKUs override to 1/0.

### Battery / charge

`battery/initEc` arguments: `(addrChargeLimit, addrBypassPower, addrForceChargeMin, off=0, mode1=1, mode2=N)`

| Function | Field | X2 Mini | X2 Mini PRO |
|---|---|---|---|
| Charge limit % | `EC_ADDR_CHARGE_LIMIT` | `0xA3` | **`0xE5`** |
| Bypass / inhibit | `EC_ADDR_BYPASS_POWER` | `0xA4` | **`0xE6`** |
| Force-charge minimum | `EC_ADDR_FORCE_CHARGE_MIN` | `0xA5` | **`0xE7`** |
| Bypass off | | `0` | `0` |
| Bypass mode 1 (awake) | | `1` | `1` |
| Bypass mode 2 (always) | `N` | `3` | `3` |
| Power-supply mode | `EC_ADDR_POWER_SUPPLY_MODE` | `0xE3` | `0xE3` |

Mode `3` matches Linux `oxpec` “inhibit always” (`0x01 | 0x02`). Global `CompatLayerCT` default for mode 2 is `11`; both Mini SKUs override to `3`.

X2 Mini PRO / APEX using `0xE5–0xE7` is the main discrepancy versus current `oxpec` fly/X1 charge hooks (`0xA3`/`0xA4`).

### Sensors (same for every OneXConsole device)

Hardcoded: `initOXPSensorEc(1120, 1121, 1136, 1184, 1185, 1186)`.

| Function | Field | Register | Width |
|---|---|---|---|
| Board sensor 1 | `EC_ADDR_OXP_BOARD_SENSOR1` | `0x60` | 1 |
| Board sensor 2 | `EC_ADDR_OXP_BOARD_SENSOR2` | `0x61` | 1 |
| CPU temp (°C) | `EC_ADDR_OXP_CPU_TEMP` | `0x70` | 1 |
| Battery temp | `EC_ADDR_OXP_BATTERY_TEMP` | `0xA0` | 1 |
| Charge current high | `EC_ADDR_OXP_BATTERY_CHARGE_CURRENT_H` | `0xA1` | BE 16-bit with next |
| Charge current low | `EC_ADDR_OXP_BATTERY_CHARGE_CURRENT_L` | `0xA2` | |

X2 Mini sets `useEcCpuTemp=true` and reads CPU temp from `0x70` via `/func/getOXPSensorCpuTemp`.

### TDP-able gate (not TDP watts)

| Function | Field | Both Mini SKUs |
|---|---|---|
| QC / “set TDP allowed” | `EC_ADDR_OXP_SET_TDP_ABLE` | `0xED` (never overridden in JS) |

Polled by `/func/getOXPSetTdpAble` before MSR/ryzenadj writes when `openQCSetTdpCheck` is on. X2 Mini PRO sets `openQCSetTdp=false`.

Actual PL1/PL2:

- X2 Mini: Intel MSR, `adjustMaxTdpType=oxp`, max 45 W / boost 46 W, default slider 25 W. `pl2 = tdp+1` (or 46 at cap).
- X2 Mini PRO: ryzenadj, max 55 W / boost 70 W, default 45 W, DC-in cap 80 W, optional cooling dock 120 W when BIOS version contains `onec1`.

## OneXConsole init sequence (both SKUs)

```
setECAccessType(type)
initBaseEc(appFunEN, fanH, fanL)
initPowerSupplyModeEC(0xE3)          # if powerSupplyMode or coolingSystem
fan/init(fanMode, 0x4A, 0, 1, 0x4B, pwmMax)
initHandleEc(0x2D, 1, 0, -1)
initOXPSensorEc(0x60, 0x61, 0x70, 0xA0, 0xA1, 0xA2)
battery/initEc(charge, bypass, forceMin, 0, 1, 3)
```

## Encoded values as they appear in JS

Defaults before per-model override: `w=1265, k=1142, C=1143, x=1098, S=0, L=1, T=1099, A=255, E=1069, I=3, R=2, P=-1, O=1187, M=1188, z=1189, N=11, D=1251`.

| JS variable | API | X2 Mini | X2 Mini PRO |
|---|---|---|---|
| `w,k,C` | `initBaseEc` | `1259, 1112, 1113` | default `1265, 1142, 1143` |
| `x,S,L,T,A` | `fan/init` | `1098, 0, 1, 1099, 184` | default + `A=255` |
| `E,I,R,P` | `initHandleEc` | `1069, 1, 0, -1` | `1069, 1, 0, -1` |
| `O,M,z,N` | `battery/initEc` | default `1187,1188,1189` + `N=3` | `1253, 1254, 1255, N=3` |
| `D` | `initPowerSupplyModeEC` | `1251` | `1251` |
