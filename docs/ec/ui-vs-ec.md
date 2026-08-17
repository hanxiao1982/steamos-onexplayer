# OneXConsole UI vs EC (X2 Mini)

Canonical live table: [x2-mini.md](x2-mini.md). This page keeps the `0xE3` bit write-up and the read-only probe.

Live WMI reads on `ONEXPLAYER X2Mini`.

## Confirmed (use these)

| UI | EC | Values |
|---|---|---|
| Fan auto / preset 1 / preset 2 | `0x4A` | `0` auto, `1` manual. Profiles 1 and 2 are both manual. |
| Fan percent | `0x4B` | Raw 0–184; UI % = `4B×100/184` |
| Fan RPM | `0x58`/`0x59` | BE16 |
| CPU temperature | `0x70` | °C |
| Charge limit | `0xA3` | UI 50–100 step 5 |
| Charge bypass | `0xA4` | `0` / `1` / `3` |
| Power-supply mode label | `0xE3` | **Live bitfield** (see below). Status only, not a toggle. |

## Not EC (UI goes elsewhere)

| UI | Path |
|---|---|
| TDP / performance watts / PL4 | Intel MSR (`/msr/setCpuPl`, `setCpuPl4`). `0xED` stays `0`. |
| CPU turbo / clock | `/powerplan/…` — does not change `0xEB` |
| RGB / rumble / gyro / key mapping | HID |
| Brightness, refresh rate, volume | Windows |
| Handle plug/unplug | Not `0x2D` (that byte stays `0`). Presence is HID. |

## Ignore on X2 Mini

| Reg | Live | Why ignore |
|---|---|---|
| `0x2D` | always `0` | Plug/unplug handle does not change it. |
| `0xED` | always `0` | TDP slider never writes EC. |
| `0xEB` | always **66** (`0x42`) | No UI; Intel turbo/clock do not move it. `0x42 = 0x40\|0x02` (`oxpec` turbo mask is `0x40`). Treat as firmware default, not a control. |
| `0x60` / `0x61` | ~30–32 °C | Likely board temps; not useful. |
| `0xA0` | always `0` | Battery temp unused. |
| `0xA1` / `0xA2` | BE16 always `0` | Charge current unused. |
| `0xA5` | always `5` | Force-charge min; no UI. |

## `0xE3` power-supply mode (live)

`oxpec` does **not** read this register (only `0xA3`/`0xA4`). OneXConsole treats the raw byte as `adjustMaxTdpMap[mode]`. X2 Mini only remaps `500`/`501` → `1` (battery low / overheat). There are **no** map keys `16` or `18`; those live values log `powerSupplyMode … not found map`.

### OneXConsole designed bitfield

Default `adjustMaxTdpMap` keys (pairs share one icon / `msgKey`). Formula: `adapter_class | (battery ? 0x01 : 0)`:

| Bit | Mask | oxp meaning |
|---|---|---|
| 0 | `0x01` | Battery present |
| 1 | `0x02` | Type-C ≥100W (`icon_power_typec100`) |
| 2 | `0x04` | DC-in / Type-C ≥140W (`icon_power_dcin` or `icon_power_typec140`) |
| 3 | `0x08` | Type-C ≤65W (`icon_power_typec65`) |

| Key | Binary | oxp UI |
|---|---|---|
| 1 | `0000_0001` | Battery power |
| 2 | `0000_0010` | TypeC ≥100W, no battery |
| 3 | `0000_0011` | TypeC ≥100W + battery |
| 4 | `0000_0100` | DC-in / ≥140W, no battery |
| 5 | `0000_0101` | DC-in / ≥140W + battery |
| 8 | `0000_1000` | TypeC ≤65W, no battery |
| 9 | `0000_1001` | TypeC ≤65W + battery |
| 500 / 501 | — | battery low / overheat → remapped to `1` |

### X2 Mini live vs that map

| Condition | Live `0xE3` | Binary | oxp expected | Match? |
|---|---|---|---|---|
| Battery only | **1** | `0000_0001` | 1 | yes |
| ≥100W + battery | **3** | `0000_0011` | 3 | yes |
| ≥100W, no battery | **18** | `0001_0010` | **2** | no — `2 \| 0x10` |
| ≤65W + battery | **9** | `0000_1001` | 9 | yes |
| ≤65W, no battery | **16** | `0001_0000` | **8** | no — only `0x10`, not `8` or `8\|0x10` (24) |
| ≥140W / DC-in | not measured | | 4 / 5 | |

Battery-present cases (`1` / `3` / `9`) are the oxp keys. Adapter-only cases set **bit4 (`0x10`)** instead of using the even oxp key.

### Live bit correspondence

| Bit | Mask | oxp | Live on X2 Mini |
|---|---|---|---|
| 0 | `0x01` | battery | same (`1`, `3`, `9`) |
| 1 | `0x02` | ≥100W | same, **kept when battery is removed** (`3` → `18`) |
| 2 | `0x04` | ≥140W / DC-in | unused in these five samples |
| 3 | `0x08` | ≤65W | only with battery (`9`). **Cleared** on adapter-only 65W |
| 4 | `0x10` | (not in oxp map) | **no battery / adapter-only** (`16`, `18`) |

≥100W no-battery follows `oxp_even | 0x10` (`2|0x10 = 18`). ≤65W no-battery does **not** (`8|0x10` would be 24); firmware emits bare `0x10`, so 65W is implied when bit4 is set and bit1 is clear.

X2 Mini `changePl4Func`: `1|2|3|4|5` → PL4 160; `9` → 120; `8` → 65. Live **16** and **18** are missing, so PL4 is undefined for adapter-only.

Decode / normalize to oxp keys:

```
battery = E3 & 0x01
pd_100  = E3 & 0x02
pd_65   = (E3 & 0x08) || (E3 == 0x10)
ac_only = E3 & 0x10

# oxp-equivalent key for icon / TDP table lookup
if   E3 in (500, 501): oxp = 1
elif E3 == 16:         oxp = 8
elif E3 == 18:         oxp = 2   # == E3 & ~0x10
else:                  oxp = E3
```

## Remaining optional read

Only `0xE3` is still worth watching (battery vs Type-C watt class) if the UI power-mode icon is being mapped.

```powershell
$o = Get-CimInstance -Namespace root/wmi -ClassName SuRwECRegInterface | Select-Object -First 1
function Read-OxpEc([int]$Reg) {
    $go = [uint32](0x04 -bor ($Reg -shl 8))
    $r = Invoke-CimMethod -InputObject $o -MethodName ReadECReg -Arguments @{ GroupOffset = $go }
    $b = ([string]$r.uStringReturn).Split(',') | ForEach-Object { [Convert]::ToInt32($_.Trim(), 16) }
    $b[1]
}
$e3 = Read-OxpEc 0xE3
$oxp = switch ($e3) { 16 { 8 } 18 { 2 } 500 { 1 } 501 { 1 } default { $e3 } }
[pscustomobject]@{
    PowerSupply_E3 = $e3
    Bits           = 'batt={0} 100W={1} 65W={2} ac_only={3}' -f `
        [int]($e3 -band 1), [int]($e3 -band 2), [int]($e3 -band 8), [int]($e3 -band 16)
    OxpKey         = $oxp
    PowerSupply    = switch ($oxp) {
        1 { 'battery' }
        2 { 'TypeC >=100W (no battery)' }
        3 { 'TypeC >=100W + battery' }
        4 { 'TypeC >=140W / DCIn' }
        5 { 'TypeC >=140W + battery' }
        8 { 'TypeC <=65W (no battery)' }
        9 { 'TypeC <=65W + battery' }
        default { "raw $e3" }
    }
}
```
