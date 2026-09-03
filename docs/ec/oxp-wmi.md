# oxp-wmi — OneXPlayer WMI EC profiles

This document is the source of truth for OneXPlayer models that OneXConsole 0.10.2-fix8 assigns `ECAccessType.OxpWMI = 2`.

These devices should be handled by the Linux `oxp-wmi` module and **not** by `oxpec`. The transport is the firmware WMI class `SuRwECRegInterface`; register semantics remain ordinary OneXPlayer EC bytes in group `0x04`.

See [README.md](README.md) for the two-driver split and [onexconsole-api.md](onexconsole-api.md) for the OneXConsole/CompatLayerCT reverse-engineering details.

## Exact device list

Only the following exact `Win32_BaseBoard.Product` strings set `ecAccessType = 2` in this OneXConsole build:

- `ONEXPLAYER Apex i`
- `ONEXPLAYER Apex Air`
- `ONEXPLAYER SUPER V`
- `ONEXPLAYER X2`
- `ONEXPLAYER X2 EVA`
- `ONEXPLAYER X2Mini`
- `ONEXPLAYER 3`

No other OneXPlayer branch in this build sets type 2.

Linux should use an exact DMI allowlist for these products. Do **not** bind merely because the WMI GUID exists: older/type-1 OneXPlayer firmware may also expose `SuRwECRegInterface` while OneXConsole still selects its direct EC backend.

## Shared profile

All seven type-2 products use the same core EC register profile in OneXConsole:

| Function | OneXConsole address | EC offset | Value / semantics |
|---|---:|---:|---|
| App-function | `0x04EB` | `0xEB` | Source-mapped; X2 Mini live shows firmware value `0x42`, not a useful user control |
| Fan RPM high | `0x0458` | `0x58` | BE16 high byte |
| Fan RPM low | `0x0459` | `0x59` | BE16 low byte |
| Fan auto/manual | `0x044A` | `0x4A` | `0` auto, `1` manual |
| Fan PWM | `0x044B` | `0x4B` | Raw range **0–184** |
| CPU temperature | `0x0470` | `0x70` | Degrees C |
| Board sensor 1/2 | `0x0460` / `0x0461` | `0x60` / `0x61` | Optional; not required by current Linux driver |
| Battery temperature | `0x04A0` | `0xA0` | X2 Mini live: unused/0 |
| Charge current H/L | `0x04A1` / `0x04A2` | `0xA1` / `0xA2` | X2 Mini live: unused/0 |
| Charge limit | `0x04A3` | `0xA3` | EC percent; OneXConsole UI 50–100 step 5 |
| Charge bypass | `0x04A4` | `0xA4` | `0` normal, `1` awake inhibit, `3` always inhibit |
| Force-charge minimum | `0x04A5` | `0xA5` | Source-mapped; X2 Mini live stuck at 5, no UI setter |
| Handle power | usually `0x042D` | `0x2D` | Product branch uses `1 / 0`; X2 Mini live did not use it |
| Power-supply mode | `0x04E3` | `0xE3` | Optional status byte |

OneXConsole initialization for this profile is equivalent to:

```
setECAccessType(2)
initBaseEc(0x04EB, 0x0458, 0x0459)
fan/init(common, 0x044A, 0, 1, 0x044B, 184)
initHandleEc(0x042D, 1, 0, -1)        # products that enable this path
initOXPSensorEc(0x0460, 0x0461, 0x0470, 0x04A0, 0x04A1, 0x04A2)
battery/initEc(0x04A3, 0x04A4, 0x04A5, 0, 1, 3)
initPowerSupplyModeEC(0x04E3)
```

These `init*` calls populate CompatLayerCT address fields; they are not firmware handshakes and are not required when a Linux driver already knows the register map.

## WMI transport

OneXConsole backend: `CompatLayerCT.ECOxpWMI`.

| Item | Value |
|---|---|
| Namespace | `root\\WMI` |
| Class | `SuRwECRegInterface` |
| GUID | `43B5A593-AD62-4257-8546-91B0797BEC1B` |
| Read method | `ReadECReg`, method id 1 |
| Write method | `WriteECReg`, method id 2 |
| Optional write+read | `WriteReadECReg`, method id 3 |
| Input | ACPI **Integer** (`UInt32`) |
| Output | `uStringReturn`, 8-byte status/value string |

The firmware packs the integer little-endian as group, offset, value:

```
read:  GroupOffset      = 0x04 | (reg << 8)
write: GroupOffsetValue = 0x04 | (reg << 8) | (value << 16)
```

Examples:

```
read  0x58      -> 0x00005804
write 0x4A = 1  -> 0x00014A04
write 0x4B =184 -> 0x00B84B04
```

Do not pass OneXConsole's display/storage form `0x400 + reg` directly as the ACPI Integer. For X2 Mini, `0x458` is rejected because AML interprets the bytes in the opposite order.

`uStringReturn` on a successful single-byte read:

```
byte 0 = 0x00   success
byte 1 = EC value
byte 2..7 = 0
```

`0xFF` in status indicates failure.

## X2 Mini live validation

`ONEXPLAYER X2Mini` is the type-2 SKU with the strongest live validation so far.

Confirmed on Windows WMI and Linux `oxp-wmi`:

- `0x4A`: `0` auto / `1` manual.
- `0x4B`: raw PWM scale 0–184; OneXConsole percent is `raw * 100 / 184`.
- After switching `0x4A` to manual, **rewrite `0x4B`** even if the readback already contains the desired value; the write is needed to latch manual PWM.
- `0x58/0x59`: BE16 fan RPM and matches OneXConsole.
- `0x70`: CPU temperature and matches OneXConsole.
- `0xA3`: tracks charge-limit UI.
- `0xA4`: values 0 / 1 / 3 correspond to normal / inhibit-awake / inhibit-always.
- `0xA5`: remains 5 and has no current UI control; do not expose it yet.
- `0xA0`, `0xA1/0xA2`: unused/zero on this SKU; prefer the normal battery subsystem for telemetry.
- `0x2D`: did not track detachable-controller presence on X2 Mini; HID owns that function.
- `0xEB`: live value `0x42`; CPU turbo/clock UI uses host power-policy APIs instead of this byte.
- `0xED`: not part of this profile initialization; X2 Mini TDP is Intel power control, not EC.

The current Linux module should therefore focus on fan, CPU temperature, charge limit/bypass and optional power-supply status rather than exposing every initialized address.

## Power-supply status (`0xE3`)

OneXConsole models an OXP power-source key using bits for battery and adapter class. X2 Mini live values additionally set bit 4 when the battery is absent.

Useful observed values:

| Condition | Raw `0xE3` | OXP-equivalent key |
|---|---:|---:|
| Battery only | 1 | 1 |
| >=100 W + battery | 3 | 3 |
| >=100 W, no battery | 18 (`0x12`) | 2 |
| <=65 W + battery | 9 | 9 |
| <=65 W, no battery | 16 (`0x10`) | 8 |

For OneXConsole-compatible policy lookup, normalize `16 -> 8` and `18 -> 2`. This status register is not itself a TDP control.

## Linux driver binding and ownership

`oxp-wmi` should bind only to the seven exact DMI products listed above and the OneXPlayer WMI GUID. Both checks are useful; neither should be replaced by a generic "GUID exists" rule.

`oxpec` should return `-ENODEV` for these products. Conversely `oxp-wmi` should return `-ENODEV` for every type-1 product even if that firmware exposes the same WMI provider. This guarantees one EC owner per device and keeps `oxpec` free of WMI dependencies.

The Linux WMI implementation should call `WMAC` with Integer Arg2. A generic Buffer-Arg2 `wmidev_evaluate_method()` path is not equivalent on the validated X2 Mini firmware and should not be the primary protocol.

## Not EC

For the validated X2 Mini generation:

- TDP / PL1 / PL2 / PL4: Intel power-control path; see [tdp.md](tdp.md).
- CPU boost/max clock: host power policy.
- RGB, rumble, gyro, controller remapping and detachable-controller presence: HID.

Do not grow `oxp-wmi` into those unrelated subsystems solely because OneXConsole exposes them in the same UI.

## Validation status

- Seven-device type-2 allowlist and register profile: **confirmed directly from OneXConsole 0.10.2-fix8**.
- WMI class/GUID/methods/Integer packing: **confirmed from CompatLayerCT/firmware and X2 Mini tests**.
- X2 Mini fan/temp/charge behavior: **live verified**.
- Other six type-2 products: register/profile selection is source-confirmed; live hardware validation is still desirable.
