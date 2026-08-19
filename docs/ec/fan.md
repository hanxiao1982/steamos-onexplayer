# Fan registers (read-only probe)

Canonical live table: [x2-mini.md](x2-mini.md). Intel G3E (X2 Mini) via OxpWMI. No `init*` needed for raw reads.

**X2 Mini live:** `0x4A` is only 0/1; UI fan profiles 1 and 2 both leave it at **1**. `PwmPercent = 4B×100/184` matches the OneXConsole fan %. RPM (`0x58`/`0x59`) and CPU temp (`0x70`) match the UI. The UI never shows raw `0x4B`.

| Role | Reg | Live |
|---|---|---|
| PWM auto / manual | `0x4A` | **`0` auto, `1` manual.** Only these two values. |
| PWM duty | `0x4B` | Hardware units **0–184**. Not on the UI. Percent = `4B * 100 / 184`. |
| Fan RPM | `0x58`/`0x59` | BE16, matches UI RPM |
| CPU temp | `0x70` | °C, matches UI |

OneXConsole `fanMode` (JS, not an EC byte):

| `fanMode` | UI | `/fan/automate` | `0x4A` |
|---|---|---|---|
| `0` | Auto | `true` | `0` |
| `1` | Preset 1 (`qs_fan_presetting1`) | `false` | `1` |
| `2` | Preset 2 (`qs_fan_presetting2`) | `false` | `1` |

Profiles 1 and 2 are both manual. The curve lives in the app DB; JS interpolates a **percent** (clamped 20–100), POSTs `/fan/setFanSpeed/{n}`, and CompatLayerCT writes `0x4B = n * 184 / 100`. EC does not store “profile 1 vs 2”.

`0x4B` is the PWM compare register (same scale Linux `oxpec` uses on X1-class boards). Convert only when talking to the UI:

```
percent ≈ round(4B * 100 / 184)     # what OneXConsole shows
4B      ≈ round(percent * 184 / 100) # what to write for a target %
```

Examples: UI 20% → 37, 50% → 92, 100% → 184. After `0x4A=1`, **rewrite `0x4B`** even if the duty byte already matches — leftover `0x4B` from auto does not latch until `WriteECReg` runs again.

```powershell
# X2 Mini / Intel G3E — admin PowerShell, read only
$ErrorActionPreference = 'Stop'
$o = Get-CimInstance -Namespace root/wmi -ClassName SuRwECRegInterface | Select-Object -First 1
if (-not $o) { throw 'SuRwECRegInterface not found' }

function Read-OxpEc([int]$Reg) {
    $go = [uint32](0x04 -bor ($Reg -shl 8))   # LE: 04, reg, 00, 00
    $r = Invoke-CimMethod -InputObject $o -MethodName ReadECReg -Arguments @{ GroupOffset = $go }
    $b = ([string]$r.uStringReturn).Split(',') | ForEach-Object { [Convert]::ToInt32($_.Trim(), 16) }
    [pscustomobject]@{ Status = $b[0]; Value = $b[1]; Raw = $r.uStringReturn }
}

$auto = Read-OxpEc 0x4A
$pwm  = Read-OxpEc 0x4B
$hi   = Read-OxpEc 0x58
$lo   = Read-OxpEc 0x59
$cpu  = Read-OxpEc 0x70

if ($auto.Status -ne 0) { Write-Warning 'ReadECReg status != 0' }

$rpm = ($hi.Value -shl 8) + $lo.Value
$pct = if ($pwm.Value -le 184) { [math]::Round($pwm.Value * 100.0 / 184, 1) } else { $null }

[pscustomobject]@{
    AutoManual_4A = $auto.Value
    AutoManual    = switch ($auto.Value) { 0 { 'auto / curve' } 1 { 'manual' } default { 'unexpected' } }
    PwmDuty_4B    = $pwm.Value
    PwmPercent    = $pct          # 4B / 184 * 100; compare to UI 20-100
    FanRpm_BE16   = $rpm          # (0x58 << 8) | 0x59
    CpuTemp_70    = $cpu.Value
    StatusOk      = ($auto.Status -eq 0 -and $pwm.Status -eq 0 -and $hi.Status -eq 0)
}
```

Repeat after each curve / slider change. Note `4A`, `4B`, RPM, and whether `4B` is `round(ui% * 184 / 100)` or a different scale.
