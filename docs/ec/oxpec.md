# oxpec — OneXPlayer direct EC profiles

This document is the source of truth for OneXPlayer models that OneXConsole 0.10.2-fix8 assigns `ECAccessType.WinRing0 = 1`.

`WinRing0` is a Windows implementation detail. On Linux these devices belong to the `oxpec` driver family and use the kernel ACPI EC path (`ec_read()` / `ec_write()`) with the ACPI global lock. The DMI table and register profile are the important parts; Linux must not depend on WinRing0.

See [README.md](README.md) for the access-type split and [onexconsole-api.md](onexconsole-api.md) for OneXConsole/CompatLayerCT reverse-engineering details.

## Source and matching rules

OneXConsole reads `Win32_BaseBoard.Manufacturer` and `Win32_BaseBoard.Product`. For the modern branch the manufacturer contains `ONE-NETBOOK` and the product is compared as an **exact string**.

Linux should therefore prefer exact `DMI_BOARD_NAME` matches. Do not collapse products by prefix: OneXConsole contains devices with similar names but different register profiles.

All addresses below are shown in the 16-bit form used by OneXConsole (`0x04xx`). Linux ACPI EC accesses use the low byte (`0xxx`) unless a future device proves that a banked/direct-ECRAM mechanism is required.

## Kernel profile naming

Profile names intentionally follow the short names already present in mainline `enum oxp_board`. This keeps the first profile-driven refactor close to the existing switch cases and avoids a large mechanical diff.

The initial refactor keeps these existing names unchanged:

- `aok_zoe_a1`
- `orange_pi_neo`
- `oxp_mini_amd`
- `oxp_mini_amd_a07`
- `oxp_mini_amd_pro`
- `oxp_2`
- `oxp_x1`
- `oxp_g1_i`
- `oxp_fly`
- `oxp_g1_a`

Two additional profiles are required by the vendor mapping and are introduced only in the later correctness patches:

- `oxp_2_ga18` — OXP2 GA18/GA72-R variant with PWM max 255.
- `oxp_apex` — APEX/X2 Mini PRO profile with the Fly fan/turbo layout but charge registers `0xE5/0xE6/0xE7`.

`oxp_g1_a` currently has the same fields consumed by mainline as `oxp_fly`, but it remains a separate profile during the refactor to preserve existing upstream semantics and keep the change reviewable.

## Shared register semantics

| Function | OneXConsole address | Linux offset | Meaning |
|---|---:|---:|---|
| Fan auto/manual | `0x044A` | `0x4A` | `0` auto, `1` manual |
| Fan PWM | `0x044B` | `0x4B` | Scale depends on profile |
| CPU temperature | `0x0470` | `0x70` | Degrees C |
| Board sensor 1/2 | `0x0460` / `0x0461` | `0x60` / `0x61` | Optional sensors |
| Battery temperature | `0x04A0` | `0xA0` | Optional sensor |
| Charge current H/L | `0x04A1` / `0x04A2` | `0xA1` / `0xA2` | BE16, optional |
| Power-supply mode | usually `0x04E3` | `0xE3` | Optional status; `SUPER X` differs |

Fan RPM is 16-bit big-endian: `(rpm_hi << 8) | rpm_lo`.

Charge-limit UI range is 50–100 in steps of 5, while the EC byte is a percent. Modern bypass values are `0` = normal, `1` = inhibit while awake, `3` = inhibit always. The force-charge register is source-mapped but should not be exposed without a verified user-visible purpose.

## `oxp_2` — EB / 58 / PWM 184

Mainline already uses `oxp_2` as the representative short name for the `0xEB`, `0x58/0x59`, PWM-184 layout.

| Field | Value |
|---|---:|
| App-function / turbo takeover | `0x04EB` |
| Fan RPM H/L | `0x0458` / `0x0459` |
| Fan mode / PWM | `0x044A` / `0x044B` |
| PWM max | **184** |
| Default charge registers where supported | `0x04A3` / `0x04A4` / `0x04A5` |

OXP2 products using this scale:

- `ONEXPLAYER 2 ARP23`
- `ONEXPLAYER 2 PRO ARP23P`
- `ONEXPLAYER 2 PRO ARP23P EVA-01`

Other OneXConsole products share the same base register family, but mainline keeps capability-specific profiles such as `oxp_x1` and `oxp_g1_i` because they differ in exposed LED/charge functionality.

## `oxp_2_ga18` — EB / 58 / PWM 255

This is a required new profile. It shares the OXP2 app-function and RPM offsets but **does not use the 184 PWM scale**.

| Field | Value |
|---|---:|
| App-function / turbo takeover | `0x04EB` |
| Fan RPM H/L | `0x0458` / `0x0459` |
| Fan mode / PWM | `0x044A` / `0x044B` |
| PWM max | **255** |

Exact board products:

- `ONEXPLAYER 2 GA18`
- `ONEXPLAYER 2 GA72-R`

`ONEXStation` also uses EB/58 with PWM 255 in OneXConsole, but it should be added separately when its complete Linux-facing capability set is reviewed.

The current broad mainline `DMI_MATCH(DMI_BOARD_NAME, "ONEXPLAYER 2") -> oxp_2` therefore cannot represent every OXP2 board correctly.

## `oxp_x1` — EB / 58 / PWM 184 + charge + turbo LED

Mainline `oxp_x1` retains its own profile because it adds the turbo LED at `0x57` and exposes charge control at `0xA3/0xA4`.

Representative exact products include `ONEXPLAYER X1 A`, `X1 i`, `X1 mini`, `X1Mini Pro`, `X1Pro`, `X1Pro EVA-02`, `X1z`, and `X1Air`.

OneXConsole also reveals handle-power differences inside the X1 family; those registers are not currently consumed by mainline `oxpec` and therefore are intentionally not part of the first refactor profile structure.

## `oxp_g1_i` — X1 layout without turbo LED

Mainline already separated this from `oxp_x1`. For the fields currently consumed by the driver it uses:

- turbo `0xEB`, mask `0x40`
- RPM `0x58/0x59`
- PWM `0x4A/0x4B`, max 184
- charge `0xA3/0xA4`
- no turbo LED

Exact board product: `ONEXPLAYER G1 i`.

## `oxp_fly` — F1 / 76 / PWM 255 + charge A3/A4

Mainline `oxp_fly` is the representative short name for the newer Fly/F1 style fan and turbo layout.

| Field | Value |
|---|---:|
| App-function / turbo takeover | `0x04F1` |
| Fan RPM H/L | `0x0476` / `0x0477` |
| Fan mode / PWM | `0x044A` / `0x044B` |
| PWM max | **255** |
| Charge registers where supported | `0x04A3` / `0x04A4` / `0x04A5` |

OneXConsole products in this register family include the F1 variants and `ONEXPLAYER Mini Pro`. Mainline also reuses the same fan/turbo behavior for AOKZOE A1X.

## `oxp_g1_a` — keep separate during refactor

For all features currently consumed by mainline, `oxp_g1_a` has the same F1/76/255 + A3/A4 behavior as `oxp_fly`. It remains separately named because mainline deliberately introduced a distinct G1 AMD quirk and `SUPER X` later reused it.

Relevant products:

- `ONEXPLAYER G1 A`
- `ONEXPLAYER SUPER X`

OneXConsole additionally shows that `SUPER X` uses `0x04FE` for power-supply mode and that G1 A has a product-specific handle-power value. Neither field is currently consumed by mainline `oxpec`, so these differences do not justify extra refactor churn yet.

## `oxp_apex` — F1 / 76 / PWM 255 + charge E5/E6

This is the second required new profile. Fan and turbo behavior match `oxp_fly`, but charge control does not.

| Field | Value |
|---|---:|
| App-function / turbo takeover | `0x04F1` |
| Fan RPM H/L | `0x0476` / `0x0477` |
| Fan mode / PWM | `0x044A` / `0x044B` |
| PWM max | **255** |
| Charge limit | **`0x04E5`** |
| Charge bypass | **`0x04E6`** |
| Force-charge minimum | **`0x04E7`** |

Exact board products:

- `ONEXPLAYER APEX`
- `ONEXPLAYER X2Mini PRO`

Current mainline maps both to Fly behavior. That is correct for fan/PWM/turbo but incomplete for charge control. The profile correction should be a separate patch after the no-functional-change refactor.

## Older profiles retained from mainline

### `oxp_mini_amd`

Legacy `ONE XPLAYER` AMD path. Mainline uses RPM `0x76/0x77`, PWM 0–100 and no turbo takeover. The CPU-vendor guard remains necessary because old Intel and AMD boards share DMI strings.

### `oxp_mini_amd_a07`

Uses RPM `0x76/0x77`, PWM 0–100, turbo register `0x1E`, mask `0x01`.

### `oxp_mini_amd_pro`

Uses RPM `0x76/0x77`, PWM 0–255, turbo `0xF1`/`0x40`. It remains separate from `oxp_fly` because that is how the current mainline capability grouping is expressed.

### `aok_zoe_a1` and `orange_pi_neo`

These non-OneXPlayer profiles stay exactly as mainline currently defines them. `orange_pi_neo` has its own fan/PWM registers and 1–244 scale.

## DMI corrections relative to community tables

The current OneXConsole build uses these exact strings:

- `ONEXPLAYER 2 PRO ARP23P`
- `ONEXPLAYER 2 PRO ARP23P EVA-01`
- `ONEXPLAYER 2 GA72-R`

The missing-final-`P` Pro strings found in some community tables are not the strings matched by this OneXConsole build.

Other pairs that must stay distinct:

- `ONEXPLAYER X2Mini` (OxpWMI) vs `ONEXPLAYER X2Mini PRO` (`oxpec` / `oxp_apex`)
- `ONEXPLAYER APEX` (`oxp_apex`) vs `ONEXPLAYER Apex i` / `Apex Air` (OxpWMI)
- `ONEXPLAYER G1 A` (`oxp_g1_a`) vs `ONEXPLAYER G1 i` (`oxp_g1_i`)
- `ONEXPLAYER SUPER X` (`oxp_g1_a`) vs `ONEXPLAYER SUPER V` (OxpWMI)

## Refactor patch order

The code work intentionally separates structural changes from vendor-profile corrections:

1. **Profile-driven refactor, no functional change.** Keep the current enum/DMI values and create an `oxp_ec_profiles[]` table indexed by the existing `enum oxp_board`. Replace repeated switch cases with profile fields.
2. **OXP2 correction.** Add `oxp_2_ga18`, replace the broad OXP2 DMI prefix match with exact OneXConsole board strings, and select PWM 184 vs 255 correctly.
3. **APEX correction.** Add `oxp_apex` and move `ONEXPLAYER APEX` plus `ONEXPLAYER X2Mini PRO` to E5/E6 charge registers while preserving their existing fan/turbo behavior.

Only fields already consumed by mainline belong in the first profile structure: fan/RPM, PWM scale, turbo takeover, optional turbo LED and optional charge control. OneXConsole-only handle/sensor/power-supply fields can be added later when Linux actually implements them.

Do not load both EC drivers for one DMI. The presence of `SuRwECRegInterface` does **not** imply that a type-1 product belongs to `oxp-wmi`.

## Validation status

- Register/address selection: **confirmed from OneXConsole 0.10.2-fix8**.
- Existing Linux `oxpec` behavior: implementation evidence, not the source of truth for model grouping.
- OXP2 184/255 split: vendor-source confirmed; hardware validation per variant is still useful.
- APEX/X2 Mini PRO E5/E6/E7: vendor-source confirmed; live validation remains desirable before relying on user-visible charge controls.