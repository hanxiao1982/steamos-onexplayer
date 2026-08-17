# OneXConsole UI vs EC (X2 Mini)

Live WMI reads on this machine.

## Confirmed (use these)

| UI | EC | Values |
|---|---|---|
| 风扇自动 / 预设 1 / 预设 2 | `0x4A` | `0` auto, `1` manual. Profiles 1 and 2 are both manual. |
| 风扇百分比 | `0x4B` | Raw 0–184; UI % = `4B×100/184` |
| 风扇 RPM | `0x58`/`0x59` | BE16 |
| CPU 温度 | `0x70` | °C |
| 充电上限 | `0xA3` | UI 50–100 step 5 |
| 旁路供电 | `0xA4` | `0` / `1` / `3` |
| 供电模式文案 | `0xE3` | Status only (adapter class). Not a toggle. Still useful to read. |

## Not EC (UI goes elsewhere)

| UI | Path |
|---|---|
| TDP / 性能瓦数 / PL4 | Intel MSR (`/msr/setCpuPl`, `setCpuPl4`). `0xED` stays `0`. |
| CPU 睿频 / 频率 | `/powerplan/…` — does not change `0xEB` |
| RGB / 震动 / 陀螺仪 / 键位 | HID |
| 亮度、刷新率、音量 | Windows |
| 手柄插拔 | Not `0x2D` (that byte stays `0`). Presence is HID. |

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
[pscustomobject]@{
    PowerSupply_E3 = $e3
    PowerSupply    = switch ($e3) {
        1 { 'battery' }
        2 { 'TypeC >=100W' }
        4 { 'TypeC >=140W / DCIn' }
        5 { 'TypeC >=140W' }
        8 { 'TypeC <=65W' }
        default { "raw $e3" }
    }
}
```
