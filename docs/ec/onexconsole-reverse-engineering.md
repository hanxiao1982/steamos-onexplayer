# OneXConsole 0.10.2-fix8 EC reverse-engineering

This document records the OneXConsole EC implementation recovered from the user-supplied `app-64.zip` package and treats the vendor application as the source of truth for access-type and per-product register selection.

For the Linux-facing DMI four-tuple and profile matrix, see [onexconsole-dmi-ec-profiles.md](onexconsole-dmi-ec-profiles.md). For driver-specific implementation notes, see [oxpec.md](oxpec.md) and [oxp-wmi.md](oxp-wmi.md).

## Extraction

- `resources/app.asar`: 58,470,111 bytes
- Parsed and extracted 2,094 packed ASAR files (57,819,083 bytes)
- Merged 365 `app.asar.unpacked` entries
- `package.json` version: `0.10.2-fix8`
- Native/.NET backend: `resources/resources/CompatLayerCT.exe` (~6.4 MiB)

## Authoritative EC access enum

`CompatLayerCT.exe` .NET metadata contains `CompatLayerCT.ECAccessType` with exactly two constants:

- `WinRing0 = 1`
- `OxpWMI = 2`

The same assembly contains `ECWinRing0`, `ECOxpWMI`, `EC`, `ECRamDirectWrite`, `ECRamReadByte`, `OrginECRamReadByte`, and `OrginECRamWriteByte`.

`ECOxpWMI` contains the strings:

- `root\\WMI`
- `SELECT * FROM SuRwECRegInterface`
- `ReadECReg`
- `WriteECReg`
- `GroupOffset`
- `GroupOffsetValue`
- `ECOxpWMI not support OrginECRamReadByte:`
- `ECOxpWMI not support OrginECRamWriteByte:`

OneXConsole initializes `ecAccessType: 1` by default. Only explicitly listed new models set `ecAccessType=2`.

When packaged, OneXConsole extracts `wr0_build.7z` only when `ecAccessType == 1`, after calling `/func/setECAccessType/{type}`.

## Common EC parameters in `background.js`

Default parameters before model-specific overrides:

| Symbol | Dec | Hex | Backend route semantics |
|---|---:|---:|---|
| `w` | 1265 | `0x04F1` | app-function EC address |
| `k` | 1142 | `0x0476` | fan RPM high byte |
| `C` | 1143 | `0x0477` | fan RPM low byte |
| `x` | 1098 | `0x044A` | fan automate/control address |
| `S` | 0 | `0x00` | fan automate on value |
| `L` | 1 | `0x01` | fan automate off value |
| `T` | 1099 | `0x044B` | fan PWM address |
| `A` | 255 | `0xFF` | fan max value |
| `E` | 1069 | `0x042D` | handle power address |
| `I` | 3 | `0x03` | handle power on |
| `R` | 2 | `0x02` | handle power off |
| `P` | -1 | — | handle restore value |
| `O` | 1187 | `0x04A3` | charge-limit address |
| `M` | 1188 | `0x04A4` | bypass-power address |
| `z` | 1189 | `0x04A5` | force-charge-min address |
| `N` | 11 | `0x0B` | bypass mode2 value |
| `D` | 1251 | `0x04E3` | power-supply-mode EC address |

Fixed OXP sensor init:

- `0x0460` board sensor 1
- `0x0461` board sensor 2
- `0x0470` CPU temperature
- `0x04A0` battery temperature
- `0x04A1` battery charge-current high byte
- `0x04A2` battery charge-current low byte

The common modern override is `w=0x04EB`, `k=0x0458`, `C=0x0459`; many such models also use fan max `184 (0xB8)`.

## Exact OneXPlayer baseboard recognition

OneXConsole obtains board data through `Win32_BaseBoard` (`Manufacturer`, `Product`, `Version`). The modern OneXPlayer branch accepts a board manufacturer containing `ONE-NETBOOK` and then compares exact `Product` strings.

This is an important boundary: the vendor application is matching the SMBIOS **baseboard** pair (`board_vendor` / `board_name` on Linux), not `sys_vendor` / `product_name`. The complete four-tuple is maintained separately in [onexconsole-dmi-ec-profiles.md](onexconsole-dmi-ec-profiles.md); system-level names are corroborated independently where possible.

| Board Product string | Access | App / RPM | Fan max | Battery / notable EC overrides |
|---|---|---|---:|---|
| `ONEXPLAYER Mini Pro` | WinRing0 | `F1 / 76-77` | 255 | defaults |
| `ONEXPLAYER 2 ARP23` | WinRing0 | `EB / 58-59` | 184 | — |
| `ONEXPLAYER 2 GA18` | WinRing0 | `EB / 58-59` | **255** | — |
| `ONEXPLAYER 2 GA72-R` | WinRing0 | `EB / 58-59` | **255** | — |
| `ONEXPLAYER 2 PRO ARP23P` | WinRing0 | `EB / 58-59` | 184 | — |
| `ONEXPLAYER 2 PRO ARP23P EVA-01` | WinRing0 | `EB / 58-59` | 184 | — |
| `ONEXPLAYER 1Pro` | WinRing0 | `EB / 58-59` | 184 | — |
| `ONEXPLAYER F1` | WinRing0 | `F1 / 76-77` | 255 | modern battery support conditional on EC version |
| `ONEXPLAYER F1 EVA-01` | WinRing0 | `F1 / 76-77` | 255 | modern battery support conditional on EC version |
| `ONEXPLAYER X1 i` | WinRing0 | `EB / 58-59` | 184 | handle `44E`, values `87/86/07`; battery mode2=3 |
| `ONEXPLAYER X1 A` | WinRing0 | `EB / 58-59` | 184 | handle `42D`, values `00/01`; battery mode2=3 |
| `ONEXPLAYER X1 mini` | WinRing0 | `EB / 58-59` | 184 | handle `42D`, values `00/01` |
| `ONEXPLAYER M1` | WinRing0 | `EB / 58-59` | 184 | — |
| `ONEXPLAYER F1L` | WinRing0 | `F1 / 76-77` | 255 | battery mode2=3 |
| `ONEXPLAYER F1 OLED` | WinRing0 | `F1 / 76-77` | 255 | battery mode2=3 |
| `ONEXPLAYER F1 EVA-02` | WinRing0 | `F1 / 76-77` | 255 | battery mode2=3 |
| `ONEXPLAYER F1Pro` | WinRing0 | `F1 / 76-77` | 255 | battery mode2=3 |
| `ONEXPLAYER X1Pro` | WinRing0 | `EB / 58-59` | 184 | handle `42D 00/01`; battery mode2=3 |
| `ONEXPLAYER X1Pro B` | WinRing0 | `EB / 58-59` | 184 | same branch as X1Pro |
| `ONEXPLAYER X1Mini Pro` | WinRing0 | `EB / 58-59` | 184 | handle `42D 00/01`; battery mode2=3 |
| `ONEXPLAYER X1z` | WinRing0 | `EB / 58-59` | 184 | handle `42D 00/01`; battery mode2=3 |
| `ONEXPLAYER X1Pro i` | WinRing0 | `EB / 58-59` | 184 | handle `44E 87/86/07`; battery mode2=3 |
| `ONEXPLAYER X1Pro EVA-02` | WinRing0 | `EB / 58-59` | 184 | handle `44E 87/86/07`; battery mode2=3 |
| `ONEXPLAYER G1 A` | WinRing0 | `F1 / 76-77` | 255 | handle on value=7; battery mode2=3 |
| `ONEXPLAYER G1 i` | WinRing0 | `EB / 58-59` | 184 | handle `44E 87/86/07`; battery mode2=3 |
| `ONEXPLAYER X1Pro A EVA-02` | WinRing0 | `EB / 58-59` | 184 | handle `42D 00/01`; battery mode2=3 |
| `ONEXPLAYER X1Air` | WinRing0 | `EB / 58-59` | 184 | handle `44E 87/86/07`; battery mode2=3 |
| `ONEXPLAYER SUPER X` | WinRing0 | `F1 / 76-77` | 255 | power-supply addr **`0x04FE`**; battery mode2=3 |
| `ONEXPLAYER APEX` | WinRing0 | `F1 / 76-77` | 255 | battery **`E5/E6/E7`**, handle `42D 01/00` |
| `ONEXStation` | WinRing0 | `EB / 58-59` | 255 | PC-mode device |
| `ONEXPLAYER Apex i` | **OxpWMI** | `EB / 58-59` | 184 | battery `A3/A4/A5`; handle `42D 01/00` |
| `ONEXPLAYER Apex Air` | **OxpWMI** | `EB / 58-59` | 184 | same branch as Apex i |
| `ONEXPLAYER SUPER V` | **OxpWMI** | `EB / 58-59` | 184 | battery `A3/A4/A5`; battery mode2=3 |
| `ONEXPLAYER X2` | **OxpWMI** | `EB / 58-59` | 184 | battery `A3/A4/A5`; handle `42D 01/00` |
| `ONEXPLAYER X2 EVA` | **OxpWMI** | `EB / 58-59` | 184 | same branch as X2 |
| `ONEXPLAYER X2Mini` | **OxpWMI** | `EB / 58-59` | 184 | battery `A3/A4/A5`; handle `42D 01/00` |
| `ONEXPLAYER 3` | **OxpWMI** | `EB / 58-59` | 184 | battery `A3/A4/A5`; handle `42D 01/00` |
| `ONEXPLAYER X2Mini PRO` | **WinRing0** | `F1 / 76-77` | 255 | battery **`E5/E6/E7`**, handle `42D 01/00` |

Additional legacy/OEM recognition outside the modern `contains("ONE-NETBOOK")` branch:

- Board Manufacturer exact `IP3 Technology CO.,Ltd.`, Product `ARP26`: WinRing0; `EB / 58-59`; fan max 184.
- Board Manufacturer exact `ONE-NETBOOK TECHNOLOGY CO., LTD.`, Product `ONE XPLAYER`: WinRing0. Intel variant changes fan-control address to `0x04C4` and off-value to `0x88`; AMD variant changes fan max to 100.

## Models using OxpWMI (complete set in this build)

Only these exact board products assign `ecAccessType = 2`:

1. `ONEXPLAYER Apex i`
2. `ONEXPLAYER Apex Air`
3. `ONEXPLAYER SUPER V`
4. `ONEXPLAYER X2`
5. `ONEXPLAYER X2 EVA`
6. `ONEXPLAYER X2Mini`
7. `ONEXPLAYER 3`

All other OneXPlayer branches in this build use the default `ECAccessType.WinRing0 = 1`.

## Important corrections vs broad upstream family mappings

- `ONEXPLAYER 2 GA18` and `ONEXPLAYER 2 GA72-R` use fan max **255**, while ARP23/ARP23P use **184**. A single substring `ONEXPLAYER 2 -> oxp_2 -> 184` mapping is too coarse.
- Current OneXConsole exact strings are `ONEXPLAYER 2 PRO ARP23P` and `ONEXPLAYER 2 PRO ARP23P EVA-01`; the missing-`P` variants seen in some community tables are not the strings this build matches.
- `ONEXPLAYER X2Mini` and `ONEXPLAYER X2Mini PRO` are radically different EC profiles despite the shared prefix: WMI + `EB/58-59/184/A3-A5` vs WinRing0 + `F1/76-77/255/E5-E7`.
- `ONEXPLAYER APEX` (AMD) and `ONEXPLAYER Apex i`/`Apex Air` likewise use different transports and register families.
- `ONEXPLAYER G1 A` and `ONEXPLAYER G1 i` are different register families (`F1/76-77/255` vs `EB/58-59/184`).
- `ONEXPLAYER SUPER X` stays WinRing0/F1-family, while `SUPER V` is WMI/EB-family.

## Architecture implications

OneXConsole does not expose a many-valued model `ECType` enum in the code found. The authoritative backend enum is the two-valued `ECAccessType`; per-model EC layouts are driven by register parameters passed from `background.js` into `CompatLayerCT` routes (`initBaseEc`, fan init, `initHandleEc`, `initOXPSensorEc`, battery init).

A clean reimplementation should therefore separate:

- transport: WinRing0 vs OxpWMI
- register profile: app/turbo address, fan RPM addresses, fan max/scaling, battery addresses, handle-power address/values, power-supply address

rather than forcing all models into a small set of coarse `oxp_board` families.

## Linux porting cautions

- `ECAccessType.WinRing0` names the **Windows transport implementation**, not a Linux driver API. OneXConsole passes full `0x04xx` addresses to that backend. A Linux port must verify how those banked addresses map to the ACPI EC path instead of blindly assuming that the high byte can always be discarded.
- `ECAccessType.OxpWMI` is the OXP `SuRwECRegInterface` path. Firmware-provider presence alone is not sufficient to select it; OneXConsole explicitly assigns only a finite product set to type 2.
- Access type and register layout are orthogonal. Several type-1 models use the same `0x04EB`/`0x0458` family that newer type-2 models use through WMI.
- Battery register defaults in the model table are not necessarily exposed for every product. OneXConsole initializes the battery service only when the corresponding feature flag is enabled.
- Similar product prefixes are unsafe DMI keys: `X2Mini` vs `X2Mini PRO`, `APEX` vs `Apex i/Air`, `SUPER X` vs `SUPER V`, and the OXP2 GA/ARP variants are concrete counterexamples.

## Recovered backend surface

The extracted package contains the OEM .NET backend `CompatLayerCT.exe` and its PDB. Relevant type names include `CompatLayerCT.EC`, `ECWinRing0`, `ECOxpWMI`, `ECAccessType`, `HardwareService`, `FanService`, and `BatteryService`. PDB paths identify the vendor source layout (`common/EC.cs`, `services/HardwareService.cs`, `services/FanService.cs`, `services/BatteryService.cs`), although source text is not embedded in the PDB.

Useful application routes recovered from the Electron side include:

- `/func/setECAccessType/{type}`
- `/func/initBaseEc/{app}/{rpmHigh}/{rpmLow}`
- `/func/initHandleEc/{addr}/{on}/{off}/{restore}`
- `/func/initOXPSensorEc/...`
- battery initialization parameters for charge-limit, bypass-power, force-charge-minimum and mode values

The OneXConsole global default is access type 1. Only explicit product branches change it to type 2, and packaged startup extracts the WinRing0 support archive only for type 1.
