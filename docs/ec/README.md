# OneXPlayer EC documentation

Source of truth: official OneXConsole **0.10.2-fix8** (`background.js` plus the vendor `CompatLayerCT.exe` backend), cross-checked with live X2 Mini WMI tests where noted.

The vendor backend exposes exactly two EC access types:

| OneXConsole | Value | Windows implementation | Linux ownership in this repo |
|---|---:|---|---|
| `ECAccessType.WinRing0` | 1 | Direct EC I/O through WinRing0 | [`oxpec`](oxpec.md) |
| `ECAccessType.OxpWMI` | 2 | `SuRwECRegInterface` WMI | [`oxp-wmi`](oxp-wmi.md) |

`WinRing0` is only the Windows mechanism; it is **not** a Linux abstraction or driver name. Linux `oxpec` uses the kernel ACPI EC path and should remain independent of WMI. `oxp-wmi` implements only the type-2 firmware protocol.

OneXConsole chooses one access type globally after DMI detection and then uses that backend for its EC services. In this build the device sets are disjoint: no product is assigned both types.

## Driver ownership rule

1. Match the exact DMI `Board Product` used by OneXConsole.
2. Map it to the vendor access type.
3. Load only the corresponding Linux module.

Do **not** decide that a machine belongs to `oxp-wmi` merely because `SuRwECRegInterface` exists. Some type-1 firmware also exposes that WMI provider while OneXConsole deliberately selects the direct EC backend.

Both modules should keep runtime DMI checks so explicitly loading the wrong module fails with `-ENODEV` rather than creating two EC owners.

## Canonical documents

- [oxpec.md](oxpec.md) — all type-1 exact DMI strings, register profiles and known profile differences.
- [oxp-wmi.md](oxp-wmi.md) — all type-2 exact DMI strings, shared WMI profile, transport ABI and X2 Mini live validation.
- [onexconsole-api.md](onexconsole-api.md) — retained OneXConsole/CompatLayerCT reverse-engineering and local API details for future refactors.
- [compatlayerct-uritemplates.md](compatlayerct-uritemplates.md) — raw CompatLayerCT WCF route inventory; kept as reverse-engineering reference.
- [tdp.md](tdp.md) — Intel/SteamOS TDP work; intentionally separate because TDP is not an EC register control on the validated X2 Mini.

The former per-feature/per-model EC notes (`access.md`, `fan.md`, `charge.md`, `x2-mini*.md`, `linux-wmi.md`, `ui-vs-ec.md`, `maps.yaml`) were consolidated into the two driver documents above to avoid duplicated or conflicting register tables.

## Important matching lessons from OneXConsole

Broad family matching is unsafe. Examples from the vendor application:

- `ONEXPLAYER 2 ARP23` uses PWM max 184, while `ONEXPLAYER 2 GA18` and `ONEXPLAYER 2 GA72-R` use 255.
- `ONEXPLAYER X2Mini` is type 2/WMI (`EB`, RPM `58/59`, PWM 184, charge `A3/A4/A5`), while `ONEXPLAYER X2Mini PRO` is type 1/direct EC (`F1`, RPM `76/77`, PWM 255, charge `E5/E6/E7`).
- `ONEXPLAYER APEX` is type 1, while `ONEXPLAYER Apex i` and `ONEXPLAYER Apex Air` are type 2.
- `ONEXPLAYER G1 A` and `ONEXPLAYER G1 i` use different register families.
- `ONEXPLAYER SUPER X` is type 1, while `ONEXPLAYER SUPER V` is type 2.

Prefer `DMI_EXACT_MATCH(DMI_BOARD_NAME, ...)` and attach a concrete register profile rather than using product-prefix matching.
