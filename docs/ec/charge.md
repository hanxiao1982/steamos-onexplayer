# Charge limit / bypass / force-charge min

Source: OneXConsole **0.10.2-fix8** UI + `battery/initEc` / `setChargeLimit` / `setByPassPowerMode`. Linux `oxpec` treats the same bytes as `charge_control_end_threshold` and `charge_behaviour`.

These are ordinary EC RAM bytes. No `init*` is required to **read** them.

| Role | CompatLayerCT field | Intel G3E (X2 Mini, …) | AMD (X2 Mini PRO, APEX) | G3E live (X2 Mini) |
|---|---|---|---|---|
| Charge limit % | `EC_ADDR_CHARGE_LIMIT` | `0xA3` | `0xE5` | **Confirmed** — tracks the UI slider |
| Bypass / inhibit | `EC_ADDR_BYPASS_POWER` | `0xA4` | `0xE6` | **Confirmed** — 0 / 1 / 3 as inferred |
| Force-charge min | `EC_ADDR_FORCE_CHARGE_MIN` | `0xA5` | `0xE7` | **Ignore for now** — stuck at `5`, no UI |
| Charge current | `EC_ADDR_OXP_BATTERY_CHARGE_CURRENT_H/L` | `0xA1`/`0xA2` | same | **Ignore for now** — BE16 always `0` |

## Ranges

### Charge limit (`0xA3` / `0xE5`)

| Layer | Range |
|---|---|
| EC byte / `oxpec` | **0–100** (percent). Other values are invalid to `oxpec`. |
| OneXConsole slider | **50–100**, **step 5**. Marks 50 / 75 / 100. Default in the UI is **100**. |
| HTTP | `POST /battery/setChargeLimit/{percent}` — the slider value is sent as-is (50, 55, …, 100). |

`0` can appear if the EC was never programmed or protection is off. The official UI will not write below 50.

### Bypass (`0xA4` / `0xE6`)

UI has a switch plus two sub-modes. HTTP sends a **mode index**; CompatLayerCT maps it through the values from `battery/initEc`:

```
initEc(..., valueBypassPowerModeOff=0, valueBypassPowerMode1=1, valueBypassPowerMode2=N)
```

On X2 Mini / X2 Mini PRO / APEX, `N=3`.

| UI | HTTP `{mode}` | EC byte written | Meaning |
|---|---|---|---|
| 正常供电 (switch off) | `0` | **0** | Charge normally |
| 旁路 · 睡眠与关机无效 | `1` | **1** | Inhibit while awake (`oxpec` `INHIBIT_CHARGE_AWAKE`) |
| 旁路 · 始终生效 | `2` | **3** (`0x01\|0x02`) | Inhibit always (`oxpec` `INHIBIT_CHARGE`) |

Read the **EC byte** (0 / 1 / 3), not the HTTP index. `2` on the wire is the UI’s second sub-mode, not the value stored in RAM.

`oxpec` treats this register as a bit mask (`0x01` awake, `0x02` extra, both = always). A raw `3` is expected for “always”. Factory default on this generation is `N=3`; older JS defaults used `N=11` (`0x0B`) on products that never override it.

### Force-charge min (`0xA5` / `0xE7`) — ignore for now

Address is passed into `battery/initEc` as `addrForceChargeMin`. There is **no** HTTP setter and no slider.

X2 Mini live: byte stays **`5`** while limit/bypass are changed. Treat as unused until a writer shows up. Do not implement it in `oxpec` / SteamOS yet.

### Charge current (`0xA1` / `0xA2`) — ignore for now

`initOXPSensorEc` still registers these as a 16-bit BE pair. X2 Mini live: both bytes stay **0** (BE16 = 0) under the same UI changes. Ignore for mapping work; battery current if needed should come from the OS fuel gauge, not this pair.

`0xA0` (battery temp) is the same: live always **0**, ignore. Use the OS fuel-gauge temp if needed.

## Read-only checks

Admin PowerShell. Intel G3E (OxpWMI) — X2 Mini and the other G3E SKUs:

```powershell
# docs/ec/read-charge.ps1  — read only
$ErrorActionPreference = 'Stop'
$o = Get-CimInstance -Namespace root/wmi -ClassName SuRwECRegInterface | Select-Object -First 1
if (-not $o) { throw 'SuRwECRegInterface not found' }

function Read-OxpEc([int]$Reg) {
    $go = [uint32](0x04 -bor ($Reg -shl 8))   # LE bytes: 04, reg, 00, 00
    $r = Invoke-CimMethod -InputObject $o -MethodName ReadECReg -Arguments @{ GroupOffset = $go }
    $hex = [string]$r.uStringReturn
    $bytes = $hex.Split(',') | ForEach-Object { [Convert]::ToInt32($_.Trim(), 16) }
    [pscustomobject]@{
        Reg    = '0x{0:X2}' -f $Reg
        Status = $bytes[0]
        Value  = $bytes[1]
        Raw    = $hex
    }
}

function Decode-Bypass([int]$v) {
    switch ($v) {
        0 { 'off / auto charge' }
        1 { 'inhibit awake (HTTP mode 1)' }
        3 { 'inhibit always (HTTP mode 2 → EC 3)' }
        default { 'unexpected (oxpec also accepts bit0=awake, bit1=extra)' }
    }
}

# Intel G3E. Confirmed pair is A3/A4. A5 and A1/A2 are unused on X2 Mini.
$limit  = Read-OxpEc 0xA3
$bypass = Read-OxpEc 0xA4

if ($limit.Status -ne 0) { Write-Warning 'ReadECReg status != 0 (packing or WMI failed)' }

[pscustomobject]@{
    ChargeLimit_A3   = $limit.Value
    ChargeLimit_note = if ($limit.Value -ge 50 -and $limit.Value -le 100) { 'in UI range 50-100' } elseif ($limit.Value -le 100) { 'in EC range 0-100, below UI min 50' } else { 'out of 0-100' }
    Bypass_A4        = $bypass.Value
    Bypass_note      = Decode-Bypass $bypass.Value
}
```

Change the slider / bypass in OneXConsole and run again. Limit should follow 50–100 in steps of 5; bypass should jump **0 ↔ 1 ↔ 3**.

Linux (ACPI EC present; `ec_sys` with `write_support` not required):

```bash
# Intel G3E: A3 A4 A5.  AMD map: E5 E6 E7
sudo modprobe ec_sys
sudo hexdump -C -s 0xA3 -n 3 /sys/kernel/debug/ec/ec0/io
```
