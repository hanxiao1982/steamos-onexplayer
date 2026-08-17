# Fan registers (read-only probe)

Intel G3E (X2 Mini) via OxpWMI. No `init*` needed for raw reads.

| Role | Reg | Expected |
|---|---|---|
| PWM auto / manual | `0x4A` | `0` auto (curve), `1` manual |
| PWM duty | `0x4B` | **0–184**. UI slider is 20–100%; HTTP `/fan/setFanSpeed/{n}` sends that percent; CompatLayerCT scales with `FAN_MAX_SPEED_VALUE=184` → duty ≈ `n * 184 / 100` |
| Fan RPM high | `0x58` | 16-bit **big-endian** with `0x59` |
| Fan RPM low | `0x59` | RPM = `(0x58 << 8) \| 0x59` |
| CPU temp (curve context) | `0x70` | °C, not a fan control byte |

What to change in OneXConsole:

1. **Auto / curve** — `0x4A` should stay `0`. `0x4B` and RPM should move with load/temp (EC applying the curve). `0x70` is the usual X axis.
2. **Manual fixed %** — `0x4A` becomes `1`. `0x4B` should track the slider (`20` → ~37, `50` → ~92, `100` → 184). RPM should rise with duty.
3. If `0x4A` never leaves `0` while you drag a “curve”, you are only editing auto points; duty/RPM still come from firmware.

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
