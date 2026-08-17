# AMD EC map (X2 Mini PRO)

Source: OneXConsole **0.10.2-fix8** only. **No live EC reads on this SKU yet.**

X2 Mini PRO is the AMD (Strix Halo) SKU. It does **not** share the Intel G3E map: [x2-mini.md](x2-mini.md). Do not copy X2 Mini live values here. Do **not** load [`oxp-wmi`](oxp-wmi.md) (that module is OxpWMI / X2 Mini only).

## Products on this map

| Marketing | DMI `Product` | Notes |
|---|---|---|
| X2 Mini PRO | `ONEXPLAYER X2Mini PRO` | CPU model string contains `amd` → `deviceCpu=AMD`; handle key `X2Mini`; TDP 55/70 W, default 45 W, DC-in 80 W |
| APEX | `ONEXPLAYER APEX` | same charge/fan/turbo defaults; cooling dock 120 W when BIOS contains `onec1` |

`ecAccessType` stays at the JS default **1 (WinRing0)**. `openQCSetTdp=false`. `programHandleType=CommonHid`, `rgbPartitionMode` on.

Kernel DMI board name for the Mini PRO patch: `ONEXPLAYER X2Mini PRO`. Linux `oxpec` uses `oxp_fly` for fan/turbo, but still programs charge **`0xA3`/`0xA4`**. Official charge registers here are **`0xE5`/`0xE6`/`0xE7`**.

## Confirmed from OneXConsole (not live)

These are the addresses and routes the app actually inits / calls. Values in RAM are unverified.

| Function | CompatLayerCT | Reg | Encoded | Source fact | Live |
|---|---|---|---|---|---|
| Access | `setECAccessType` | — | — | default **1** WinRing0 (ports 0x66/0x62) | untested |
| Fan RPM | `EC_ADDR_FAN_SPEED_H/L` | `0x76`/`0x77` | 1142/1143 | JS defaults; Mini PRO does not override | untested |
| PWM auto / manual | `EC_ADDR_FAN_AUTOMATE` | `0x4A` | 1098 | `0` auto, `1` manual | untested |
| PWM duty | `EC_ADDR_FAN_SPEED` | `0x4B` | 1099 | max **255** (JS default `A=255`; Mini PRO does not set 184) | untested |
| Turbo / app-fun | `EC_ADDR_APP_FUN_EN` | `0xF1` | 1265 | JS default; `oxpec` `oxp_fly` mask `0x40` | untested whether UI writes it |
| Charge limit | `EC_ADDR_CHARGE_LIMIT` | **`0xE5`** | 1253 | Mini PRO sets `O=1253`. UI 50–100 step 5 | untested |
| Charge bypass | `EC_ADDR_BYPASS_POWER` | **`0xE6`** | 1254 | `N=3` → HTTP 0/1/2 → EC 0/1/3 | untested |
| Force-charge min | `EC_ADDR_FORCE_CHARGE_MIN` | **`0xE7`** | 1255 | no UI setter (same as G3E) | untested |
| Power-supply mode | `EC_ADDR_POWER_SUPPLY_MODE` | `0xE3` | 1251 | `powerSupplyMode=true`; same oxp key table | encodings untested (do not assume X2 Mini `16`/`18`) |
| Handle power | `EC_ADDR_HANDLE_POWER` | `0x2D` | 1069 | on=`1`, off=`0`, restore=`-1` | untested (X2 Mini live was unused) |
| CPU temp | `EC_ADDR_OXP_CPU_TEMP` | `0x70` | 1136 | `useEcCpuTemp=true` | untested |
| Board / bat / current | `0x60`/`0x61`/`0xA0`/`0xA1`/`0xA2` | | same init as G3E | untested |
| TDP-able gate | `EC_ADDR_OXP_SET_TDP_ABLE` | `0xED` | — | not in init URL; TDP is `ryzenadj` | untested |

### Not EC (same split as X2 Mini, AMD backends)

| UI | Path |
|---|---|
| TDP PL1/PL2 | `/ryzenadj/setCpuPl/{pl1}/{pl2}` |
| GPU 频率 | `/ryzenadj/setGpuClock/{clk}` (AMD `gpuClk` on) |
| Combined | `/ryzenadj/setCpuPlAndGpuClock/{pl}/{clock}` |
| RGB / LED | `/rgbPartition/…` + `CommonHid` |
| 震动 / 陀螺仪 / 键位 | HID |

`presetDCInMaxTdp=80`. BIOS `onec1` enables cooling-system 120 W (`power_dcin_cooling_effect`). Whether DC-in shows as oxp keys `4`/`5` is untested.

## Init (OneXConsole)

Address-table only (plus WinRing0 `InitEC`). Not required for raw ACPI EC R/W.

```
setECAccessType(1)
initBaseEc(0xF1, 0x76, 0x77)          # JS defaults: 1265, 1142, 1143
initPowerSupplyModeEC(0xE3)           # JS: 1251
fan/init(common, 0x4A, 0, 1, 0x4B, 255)
initHandleEc(0x2D, 1, 0, -1)          # JS: 1069, 1, 0, -1
initOXPSensorEc(0x60, 0x61, 0x70, 0xA0, 0xA1, 0xA2)
battery/initEc(0xE5, 0xE6, 0xE7, 0, 1, 3)   # JS: 1253, 1254, 1255, N=3
```

## Later live checks

Leave these until a Mini PRO is on the bench:

1. Fan `0x4A`/`0x4B`/`0x76`/`0x77` vs UI % (scale 255, not 184).
2. Charge `0xE5`/`0xE6` follow slider / bypass; what `0xE7` holds.
3. `0xE3` encodings with/without battery and 65W/100W/DC-in.
4. Whether `0xF1` moves with any UI (or is firmware-only like X2 Mini `0xEB`).
5. `0x2D` / sensors — implement only if they change.

Value ranges for charge (from the shared UI, not Mini PRO live): [charge.md](charge.md).
