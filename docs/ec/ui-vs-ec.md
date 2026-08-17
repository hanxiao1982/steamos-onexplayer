# OneXConsole UI vs EC (X2 Mini)

What the official UI shows or lets you change, and whether that value lives in EC RAM. Live column is from this machine’s WMI reads unless marked inferred.

## Already confirmed (adjustable + EC)

| UI | EC | Values |
|---|---|---|
| 风扇自动 / 预设 1 / 预设 2 | `0x4A` | `0` auto, `1` manual. Profiles 1 and 2 are both manual; profile id is not in EC. |
| 风扇百分比 | `0x4B` | Raw 0–184; UI % = `4B×100/184` |
| 充电上限 | `0xA3` | UI 50–100 step 5 |
| 旁路供电 | `0xA4` | `0` / `1` / `3` |

## Shown in UI, readable from EC, not a user control

These update the OSD / QC panel. Changing them in software is not a “setting”.

| UI | EC | Notes |
|---|---|---|
| 风扇 RPM | `0x58`/`0x59` | BE16, confirmed |
| CPU 温度 | `0x70` | °C, confirmed |
| 板温（若显示） | `0x60` / `0x61` | `getOXPSensorInfo`; not live-checked yet |
| 电池温度（若显示） | `0xA0` | same |
| 供电模式文案 | `0xE3` | **Status only.** JS `getPowerSupplyMode` → `adjustMaxTdpMap[mode]`. Labels: `1` 电池, `2` TypeC≥100W, `4`/`5` TypeC≥140W, `8` TypeC≤65W. `500`/`501` remapped to `1`. Not a toggle. |

## Adjustable in UI, EC-backed, not live-confirmed

| UI | EC | How OneXConsole uses it |
|---|---|---|
| 手柄电源 / 重置手柄 | `0x2D` | `initHandleEc(0x2D, on=1, off=0)`. IPC `setHandlePower` / `resetHandlePower` → `/handle/setPower/{0\|1}`. X2 Mini has a detachable handle. |
| （无独立开关）TDP 是否允许设置 | `0xED` | `getOXPSetTdpAble` before MSR writes. Not a slider. |

Worth a read while you click 重置手柄 / 手柄供电, and once while moving the TDP slider (`0xED` may flip 0/1).

## Adjustable in UI, **not** EC

Do not look for these in `ReadECReg`.

| UI | Actual path |
|---|---|
| TDP / 性能瓦数 / PL4 | Intel MSR `/msr/setCpuPl` / `setCpuPl4` (`intelTdpSetType=4` on G3). `0xED` is only the gate. |
| RGB / 分区灯 | HID `CommonHid` / `rgbPartition` |
| 震动、扳机、摇杆、按键映射 | HID |
| 陀螺仪 | HID + ViGEm |
| 亮度、刷新率、分辨率、HDR | Windows `/screen/…` |
| 音量、触摸板、休眠 | Windows |
| CPU boost / 超线程 / 最大频率 | `/powerplan/…` |
| 显存 | `/hardware/setVideoMemory…` |
| Turbo 键接管 | `/func/takeOverTurboButton` → `0xEB` on some SKUs (`funcButtonMode`). **X2 Mini leaves `funcButtonMode` off**, so no UI for `0xEB`. |

## Ignore (init only / dead)

| Reg | Why |
|---|---|
| `0xA5` | Force-charge min; live stuck at `5`, no UI |
| `0xA1`/`0xA2` | Charge current; live BE16 always `0` |

## Remaining read-only probe

Admin PowerShell. Toggle 手柄电源 and TDP, then run again.

```powershell
$o = Get-CimInstance -Namespace root/wmi -ClassName SuRwECRegInterface | Select-Object -First 1
function Read-OxpEc([int]$Reg) {
    $go = [uint32](0x04 -bor ($Reg -shl 8))
    $r = Invoke-CimMethod -InputObject $o -MethodName ReadECReg -Arguments @{ GroupOffset = $go }
    $b = ([string]$r.uStringReturn).Split(',') | ForEach-Object { [Convert]::ToInt32($_.Trim(), 16) }
    [pscustomobject]@{ Reg = '0x{0:X2}' -f $Reg; Status = $b[0]; Value = $b[1] }
}

function Mode-E3([int]$v) {
    switch ($v) {
        1 { 'battery' }
        2 { 'TypeC >=100W' }
        4 { 'TypeC >=140W / DCIn (map 4)' }
        5 { 'TypeC >=140W (map 5)' }
        8 { 'TypeC <=65W' }
        9 { 'map 9 (PL4 120)' }
        default { "raw $v" }
    }
}

[pscustomobject]@{
    HandlePower_2D = (Read-OxpEc 0x2D).Value          # expect 0/1 if UI hits EC
    PowerSupply_E3 = (Read-OxpEc 0xE3).Value
    PowerSupply    = Mode-E3 ((Read-OxpEc 0xE3).Value)
    TdpAble_ED     = (Read-OxpEc 0xED).Value          # gate, not watts
    TurboAppFun_EB = (Read-OxpEc 0xEB).Value          # no X2 Mini UI; just a baseline
    BoardTemp_60   = (Read-OxpEc 0x60).Value
    BoardTemp_61   = (Read-OxpEc 0x61).Value
    BattTemp_A0    = (Read-OxpEc 0xA0).Value
}
```
