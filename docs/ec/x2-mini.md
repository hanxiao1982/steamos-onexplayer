# Intel Arc G3 Extreme EC map (X2 Mini)

Source: OneXConsole **0.10.2-fix8**, plus live WMI `ReadECReg` on `ONEXPLAYER X2Mini`.

X2 Mini is the Intel G3E SKU. Other G3E products below share the **same offsets** in the app; only X2 Mini has been live-read. X2 Mini PRO is a different (AMD) platform: [x2-mini-pro.md](x2-mini-pro.md).

Access: `deviceCpu=Intel`, `ecAccessType=2` (OxpWMI `SuRwECRegInterface`). Wire: `GroupOffset = 0x04 | (reg << 8)`. Init is address-table only; raw WMI does not need it. See [access.md](access.md), [onexconsole-api.md](onexconsole-api.md).

## Products on this map

| Marketing | DMI `Product` | Notes |
|---|---|---|
| X2 Mini | `ONEXPLAYER X2Mini` | **Live-verified.** landscape; handle key `X2Mini`; TDP 45/46 W, default 25 W |
| X2 | `ONEXPLAYER X2` | same EC init; `landscapeScreen=false`; handle key `X1`; TDP 35/36 W, unlock 40 W |
| X2 EVA | `ONEXPLAYER X2 EVA` | same branch as X2 |
| OneXPlayer 3 | `ONEXPLAYER 3` | handle key `OXP3`; TDP 35/36 W, unlock 40 W |
| Apex Air | `ONEXPLAYER Apex Air` | handle key `APEX`; default 25 W, boost 46 or 66 W by SKU flag |
| Apex i | `ONEXPLAYER Apex i` | same EC init as Apex Air |

All force `useEcCpuTemp`, `powerSupplyMode`, `enableBatteryProtection`, `programHandleType=CommonHid`, PWM max **184**.

## Live results vs OneXConsole (X2 Mini)

Every row is: app address table → live WMI on this machine. `encoded = 0x400 + reg`.

### Implement these (EC)

| UI | CompatLayerCT | Reg | Encoded | OneXConsole | Live |
|---|---|---|---|---|---|
| Fan auto / preset 1 / preset 2 | `EC_ADDR_FAN_AUTOMATE` | `0x4A` | 1098 | `0` auto, `1` manual | **Same.** JS `fanMode` 0/1/2; profiles 1 and 2 both write `1`. Profile id is not in EC. |
| Fan percent | `EC_ADDR_FAN_SPEED` | `0x4B` | 1099 | 0–184; UI % = `4B×100/184`; write `n×184/100` | **Same.** UI never shows raw `4B`. |
| Fan RPM | `EC_ADDR_FAN_SPEED_H/L` | `0x58`/`0x59` | 1112/1113 | BE16 | **Matches UI RPM.** |
| CPU temperature | `EC_ADDR_OXP_CPU_TEMP` | `0x70` | 1136 | °C | **Matches UI.** |
| Charge limit | `EC_ADDR_CHARGE_LIMIT` | `0xA3` | 1187 | UI 50–100 step 5 | **Tracks slider.** |
| Charge bypass | `EC_ADDR_BYPASS_POWER` | `0xA4` | 1188 | HTTP 0/1/2 → EC **0 / 1 / 3** (`N=3`) | **Confirmed 0 / 1 / 3.** |
| Power-supply mode (read-only) | `EC_ADDR_POWER_SUPPLY_MODE` | `0xE3` | 1251 | oxp keys `1/2/3/4/5/8/9` | **Bitfield + firmware bit4.** See below. |

Fan probe: [fan.md](fan.md). Charge probe: [charge.md](charge.md). UI vs EC: [ui-vs-ec.md](ui-vs-ec.md).

### Ignore on X2 Mini (inited, unused)

| CompatLayerCT | Reg | OneXConsole intent | Live |
|---|---|---|---|
| `EC_ADDR_APP_FUN_EN` | `0xEB` | old turbo / app-fun (`oxpec` mask `0x40`) | always **66** (`0x42`). Turbo/clock UI do not write it. `funcButtonMode` off. |
| `EC_ADDR_HANDLE_POWER` | `0x2D` | handle on=`1` / off=`0` / restore=`-1` | always **0**. Plug/unplug does not change it (HID). |
| `EC_ADDR_OXP_SET_TDP_ABLE` | `0xED` | TDP gate (`getOXPSetTdpAble`) | always **0**. TDP is MSR. |
| `EC_ADDR_OXP_BOARD_SENSOR1/2` | `0x60`/`0x61` | board temps | ~30–32 °C, not useful. |
| `EC_ADDR_OXP_BATTERY_TEMP` | `0xA0` | battery °C | always **0**. |
| `EC_ADDR_OXP_BATTERY_CHARGE_CURRENT_H/L` | `0xA1`/`0xA2` | BE16 current | always **0**. |
| `EC_ADDR_FORCE_CHARGE_MIN` | `0xA5` | no HTTP setter | stuck at **5**. |

### Not EC (UI goes elsewhere)

Cross-checked against `background.js` routes. None of these write the G3E EC map.

| UI | OneXConsole path | Notes |
|---|---|---|
| TDP / PL1 / PL2 / PL4 | `/msr/setCpuPl/{pl1}/{pl2}/4`, `/msr/setCpuPl4/{pl4}/4` | Package watts. `{type}=4` is DTT/IPF, not raw RAPL. No tau. `0xED` stays 0. |
| CPU turbo switch | `/powerplan/setCpuBoostMode/{0\|2}` | Windows CPU Boost. Shifts package share toward IA. Not `0xEB`. |
| CPU max clock | `/powerplan/setCpuMaxClock/{MHz}` | Caps IA MHz so GT can keep watts. Off → `0`. |
| Intel dynamic performance / Adaptive TDP | **not captured** | UI exists; HTTP path unknown. This is the CPU↔GPU allocator. |
| GPU clock | — | X2 Mini does **not** enable `manualGpuClk` / `gpuClk`. |
| RGB / LED | `/rgbPartition/setColor\|setOpen\|setPreset` | `rgbPartitionMode`, `CommonHid`. No `EC_ADDR_RGB`. |
| Rumble / gyro / key mapping | `/programhandle/…`, `/gyro/…`, `/motor/…` | HID. |
| Brightness, refresh rate, volume | Windows | `screenRefreshRate=120` is a capability flag. |
| Handle present | HID `handledHID` / `programhandle` | not `0x2D`. |

## `0xE3` live vs oxp keys

OneXConsole formula: `adapter_class | (battery ? 0x01 : 0)` — bits 0 battery, 1 ≥100W, 2 ≥140W/DC, 3 ≤65W. Map keys `1/2/3/4/5/8/9` only (`500`/`501` remapped to `1`). **No keys `16`/`18`.**

| Condition | Live | oxp expected | Notes |
|---|---|---|---|
| Battery only | **1** | 1 | match |
| ≥100W + battery | **3** | 3 | match |
| ≥100W, no battery | **18** (`0x12`) | **2** | live = `2 \| 0x10` |
| ≤65W + battery | **9** | 9 | match |
| ≤65W, no battery | **16** (`0x10`) | **8** | only bit4; not `8` or `24` |
| ≥140W / DC-in | not measured | 4 / 5 | X2 Mini `dcin=false`; keys 4/5 still exist as TypeC ≥140W icons |

Firmware adds **bit4 (`0x10`)** = adapter-only. Normalize for oxp lookup: `16→8`, `18→2`. X2 Mini `changePl4Func` handles `1|2|3|4|5→160`, `9→120`, `8→65` — live **16/18** are missing. Full bit table: [ui-vs-ec.md](ui-vs-ec.md).

## Init (OneXConsole)

Address-table only. Raw `ReadECReg` does not need these.

```
setECAccessType(2)
initBaseEc(0xEB, 0x58, 0x59)          # JS: 1259, 1112, 1113
initPowerSupplyModeEC(0xE3)           # JS: 1251
fan/init(common, 0x4A, 0, 1, 0x4B, 184)
initHandleEc(0x2D, 1, 0, -1)          # JS: 1069, 1, 0, -1
initOXPSensorEc(0x60, 0x61, 0x70, 0xA0, 0xA1, 0xA2)
battery/initEc(0xA3, 0xA4, 0xA5, 0, 1, 3)
```

`fanMode` is `"common"`. Closest Linux `oxpec` profile: `oxp_x1` / `oxp_2` (fan/charge offsets), **not** `oxp_fly`. Skip `0xEB` on this SKU.

## SteamOS / Linux

WMI driver (Intel / OxpWMI): [oxp-wmi.md](oxp-wmi.md) (`linux/oxp-wmi/`). Deploy on Bazzite/CachyOS with the same `kmod/scripts` path as AMD boards: `ec-stack.sh` prints `oxp-wmi`, then `apply-all.sh` / `install-oxp-wmi.sh` (or `ssh-handheld.sh user@host all`). Use fan `0x4A`/`0x4B`/`0x58`/`0x59` (PWM 0–184), charge `0xA3`/`0xA4` (bypass 0/1/3), CPU temp `0x70`, optional decode of `0xE3`.

Do not implement: `0x2D`, `0x60`/`0x61`, `0xA0`–`0xA2`, `0xA5`, `0xEB`, `0xED`.

TDP = Intel RAPL (`TdpLimit1` remote), not EC. See [tdp.md](tdp.md). RGB / rumble / gyro = HID. CPU turbo / clock = host power policy, not EC. `oxpec` remains ACPI-EC only (AMD / fallback).
