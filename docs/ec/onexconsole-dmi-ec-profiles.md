# OneXConsole DMI four-tuples and EC profile matrix

This document converts the OneXConsole 0.10.2-fix8 model table into a Linux-oriented DMI/profile matrix. It intentionally records all four DMI identifiers used by Linux device matching: `board_vendor`, `board_name`, `sys_vendor`, and `product_name`.

## Evidence rules

- **Board pair is authoritative from OneXConsole** for the modern branch: `Win32_BaseBoard.Manufacturer` contains `ONE-NETBOOK` and `Win32_BaseBoard.Product` is compared against the exact strings below. In Linux terms these correspond to `board_vendor` and `board_name`.
- **System pair is a separate field set.** OneXConsole does not read it. Values below are filled from public Linux configs/quirks or project hardware evidence where available; otherwise the modern ONE-NETBOOK convention (`sys_vendor=ONE-NETBOOK`, `product_name≈board_name`) is recorded as an explicit inference and must be confirmed from a live machine before an exact kernel match depends on it.
- A particularly important counterexample is `ONEXPLAYER 2 PRO ARP23P EVA-01`: OneXConsole matches the **board name** with the `P`, while current public InputPlumber data uses system `product_name=ONEXPLAYER 2 PRO ARP23 EVA-01` without the `P`. This is why the four-tuple must be tracked instead of treating board and system names as interchangeable.

Recommended capture command for new hardware:

```bash
printf "board_vendor=%s\nboard_name=%s\nsys_vendor=%s\nproduct_name=%s\n" \
  "$(cat /sys/class/dmi/id/board_vendor)" \
  "$(cat /sys/class/dmi/id/board_name)" \
  "$(cat /sys/class/dmi/id/sys_vendor)" \
  "$(cat /sys/class/dmi/id/product_name)"
```

## Modern OneXPlayer matrix

| `board_vendor` | `board_name` | `sys_vendor` | `product_name` | Evidence for system pair | Access | Profile |
|---|---|---|---|---|---|---|
| `ONE-NETBOOK` | `ONEXPLAYER Mini Pro` | `ONE-NETBOOK` | `ONEXPLAYER Mini Pro` | public Linux system-pair corroborated | `WinRing0` | `DIRECT-F1-255-A3` |
| `ONE-NETBOOK` | `ONEXPLAYER 2 ARP23` | `ONE-NETBOOK` | `ONEXPLAYER 2 ARP23` | public Linux system-pair corroborated | `WinRing0` | `DIRECT-EB184-A3` |
| `ONE-NETBOOK` | `ONEXPLAYER 2 GA18` | `ONE-NETBOOK` | `ONEXPLAYER 2 GA18` | system pair inferred; live dump required | `WinRing0` | `DIRECT-EB255-A3` |
| `ONE-NETBOOK` | `ONEXPLAYER 2 GA72-R` | `ONE-NETBOOK` | `ONEXPLAYER 2 GA72-R` | system pair inferred; live dump required | `WinRing0` | `DIRECT-EB255-A3` |
| `ONE-NETBOOK` | `ONEXPLAYER 2 PRO ARP23P` | `ONE-NETBOOK` | `ONEXPLAYER 2 PRO ARP23P` | public Linux system-pair corroborated | `WinRing0` | `DIRECT-EB184-A3` |
| `ONE-NETBOOK` | `ONEXPLAYER 2 PRO ARP23P EVA-01` | `ONE-NETBOOK` | `ONEXPLAYER 2 PRO ARP23 EVA-01` | public Linux system-pair differs from board name | `WinRing0` | `DIRECT-EB184-A3` |
| `ONE-NETBOOK` | `ONEXPLAYER 1Pro` | `ONE-NETBOOK` | `ONEXPLAYER 1Pro` | system pair inferred; live dump required | `WinRing0` | `DIRECT-EB184-A3` |
| `ONE-NETBOOK` | `ONEXPLAYER F1` | `ONE-NETBOOK` | `ONEXPLAYER F1` | public Linux system-pair corroborated | `WinRing0` | `DIRECT-F1-255-A3` |
| `ONE-NETBOOK` | `ONEXPLAYER F1 EVA-01` | `ONE-NETBOOK` | `ONEXPLAYER F1 EVA-01` | public Linux system-pair corroborated | `WinRing0` | `DIRECT-F1-255-A3` |
| `ONE-NETBOOK` | `ONEXPLAYER X1 i` | `ONE-NETBOOK` | `ONEXPLAYER X1 i` | public Linux system-pair corroborated | `WinRing0` | `DIRECT-EB184-A3` |
| `ONE-NETBOOK` | `ONEXPLAYER X1 A` | `ONE-NETBOOK` | `ONEXPLAYER X1 A` | public Linux system-pair corroborated | `WinRing0` | `DIRECT-EB184-A3` |
| `ONE-NETBOOK` | `ONEXPLAYER X1 mini` | `ONE-NETBOOK` | `ONEXPLAYER X1 mini` | public Linux system-pair corroborated | `WinRing0` | `DIRECT-EB184-A3` |
| `ONE-NETBOOK` | `ONEXPLAYER M1` | `ONE-NETBOOK` | `ONEXPLAYER M1` | system pair inferred; live dump required | `WinRing0` | `DIRECT-EB184-A3` |
| `ONE-NETBOOK` | `ONEXPLAYER F1L` | `ONE-NETBOOK` | `ONEXPLAYER F1L` | system pair inferred; live dump required | `WinRing0` | `DIRECT-F1-255-A3` |
| `ONE-NETBOOK` | `ONEXPLAYER F1 OLED` | `ONE-NETBOOK` | `ONEXPLAYER F1 OLED` | public Linux system-pair corroborated | `WinRing0` | `DIRECT-F1-255-A3` |
| `ONE-NETBOOK` | `ONEXPLAYER F1 EVA-02` | `ONE-NETBOOK` | `ONEXPLAYER F1 EVA-02` | public Linux system-pair corroborated | `WinRing0` | `DIRECT-F1-255-A3` |
| `ONE-NETBOOK` | `ONEXPLAYER F1Pro` | `ONE-NETBOOK` | `ONEXPLAYER F1Pro` | public Linux system-pair corroborated | `WinRing0` | `DIRECT-F1-255-A3` |
| `ONE-NETBOOK` | `ONEXPLAYER X1Pro` | `ONE-NETBOOK` | `ONEXPLAYER X1Pro` | public Linux system-pair corroborated | `WinRing0` | `DIRECT-EB184-A3` |
| `ONE-NETBOOK` | `ONEXPLAYER X1Pro B` | `ONE-NETBOOK` | `ONEXPLAYER X1Pro B` | system pair inferred; live dump required | `WinRing0` | `DIRECT-EB184-A3` |
| `ONE-NETBOOK` | `ONEXPLAYER X1Mini Pro` | `ONE-NETBOOK` | `ONEXPLAYER X1Mini Pro` | system pair inferred; live dump required | `WinRing0` | `DIRECT-EB184-A3` |
| `ONE-NETBOOK` | `ONEXPLAYER X1z` | `ONE-NETBOOK` | `ONEXPLAYER X1z` | system pair inferred; live dump required | `WinRing0` | `DIRECT-EB184-A3` |
| `ONE-NETBOOK` | `ONEXPLAYER X1Pro i` | `ONE-NETBOOK` | `ONEXPLAYER X1Pro i` | system pair inferred; live dump required | `WinRing0` | `DIRECT-EB184-A3` |
| `ONE-NETBOOK` | `ONEXPLAYER X1Pro EVA-02` | `ONE-NETBOOK` | `ONEXPLAYER X1Pro EVA-02` | public Linux system-pair corroborated | `WinRing0` | `DIRECT-EB184-A3` |
| `ONE-NETBOOK` | `ONEXPLAYER G1 A` | `ONE-NETBOOK` | `ONEXPLAYER G1 A` | public Linux system-pair corroborated | `WinRing0` | `DIRECT-F1-255-A3` |
| `ONE-NETBOOK` | `ONEXPLAYER G1 i` | `ONE-NETBOOK` | `ONEXPLAYER G1 i` | public Linux system-pair corroborated | `WinRing0` | `DIRECT-EB184-A3` |
| `ONE-NETBOOK` | `ONEXPLAYER X1Pro A EVA-02` | `ONE-NETBOOK` | `ONEXPLAYER X1Pro A EVA-02` | system pair inferred; live dump required | `WinRing0` | `DIRECT-EB184-A3` |
| `ONE-NETBOOK` | `ONEXPLAYER X1Air` | `ONE-NETBOOK` | `ONEXPLAYER X1Air` | system pair inferred; live dump required | `WinRing0` | `DIRECT-EB184-A3` |
| `ONE-NETBOOK` | `ONEXPLAYER SUPER X` | `ONE-NETBOOK` | `ONEXPLAYER SUPER X` | system pair inferred; live dump required | `WinRing0` | `DIRECT-F1-255-A3` |
| `ONE-NETBOOK` | `ONEXPLAYER APEX` | `ONE-NETBOOK` | `ONEXPLAYER APEX` | public Linux system-pair corroborated | `WinRing0` | `DIRECT-F1-255-E5` |
| `ONE-NETBOOK` | `ONEXStation` | `ONE-NETBOOK` | `ONEXStation` | system pair inferred; live dump required | `WinRing0` | `DIRECT-EB255-A3` |
| `ONE-NETBOOK` | `ONEXPLAYER Apex i` | `ONE-NETBOOK` | `ONEXPLAYER Apex i` | system pair inferred; live dump required | `OxpWMI` | `WMI-EB184-A3` |
| `ONE-NETBOOK` | `ONEXPLAYER Apex Air` | `ONE-NETBOOK` | `ONEXPLAYER Apex Air` | system pair inferred; live dump required | `OxpWMI` | `WMI-EB184-A3` |
| `ONE-NETBOOK` | `ONEXPLAYER SUPER V` | `ONE-NETBOOK` | `ONEXPLAYER SUPER V` | system pair inferred; live dump required | `OxpWMI` | `WMI-EB184-A3` |
| `ONE-NETBOOK` | `ONEXPLAYER X2` | `ONE-NETBOOK` | `ONEXPLAYER X2` | system pair inferred; live dump required | `OxpWMI` | `WMI-EB184-A3` |
| `ONE-NETBOOK` | `ONEXPLAYER X2 EVA` | `ONE-NETBOOK` | `ONEXPLAYER X2 EVA` | system pair inferred; live dump required | `OxpWMI` | `WMI-EB184-A3` |
| `ONE-NETBOOK` | `ONEXPLAYER X2Mini` | `ONE-NETBOOK` | `ONEXPLAYER X2Mini` | public Linux system-pair corroborated | `OxpWMI` | `WMI-EB184-A3` |
| `ONE-NETBOOK` | `ONEXPLAYER 3` | `ONE-NETBOOK` | `ONEXPLAYER 3` | system pair inferred; live dump required | `OxpWMI` | `WMI-EB184-A3` |
| `ONE-NETBOOK` | `ONEXPLAYER X2Mini PRO` | `ONE-NETBOOK` | `ONEXPLAYER X2Mini PRO` | live/project corroborated | `WinRing0` | `DIRECT-F1-255-E5` |

## Register profiles

| Profile | Access | App function | RPM H/L | Fan mode/PWM | PWM max | Charge registers |
|---|---|---:|---:|---:|---:|---|
| `DIRECT-EB184-A3` | WinRing0 in OneXConsole / direct EC family on Linux | `0x04EB` | `0x0458/0x0459` | `0x044A/0x044B` | 184 | `0x04A3/0x04A4/0x04A5` defaults |
| `DIRECT-EB255-A3` | WinRing0 / direct EC | `0x04EB` | `0x0458/0x0459` | `0x044A/0x044B` | 255 | `0x04A3/0x04A4/0x04A5` defaults |
| `DIRECT-F1-255-A3` | WinRing0 / direct EC | `0x04F1` | `0x0476/0x0477` | `0x044A/0x044B` | 255 | `0x04A3/0x04A4/0x04A5` defaults |
| `DIRECT-F1-255-E5` | WinRing0 / direct EC | `0x04F1` | `0x0476/0x0477` | `0x044A/0x044B` | 255 | `0x04E5/0x04E6/0x04E7` |
| `WMI-EB184-A3` | OxpWMI (`SuRwECRegInterface`) | `0x04EB` | `0x0458/0x0459` | `0x044A/0x044B` | 184 | `0x04A3/0x04A4/0x04A5` |

### Per-model notable overrides

- `ONEXPLAYER Mini Pro` — defaults.
- `ONEXPLAYER 2 GA18` — important difference from ARP23.
- `ONEXPLAYER 2 GA72-R` — important difference from ARP23.
- `ONEXPLAYER F1` — battery support EC-version gated.
- `ONEXPLAYER F1 EVA-01` — battery support EC-version gated.
- `ONEXPLAYER X1 i` — handle 0x044E 87/86/07.
- `ONEXPLAYER X1 A` — handle 0x042D 00/01.
- `ONEXPLAYER X1 mini` — handle 0x042D 00/01.
- `ONEXPLAYER X1Pro` — handle 0x042D 00/01.
- `ONEXPLAYER X1Pro B` — same branch as X1Pro.
- `ONEXPLAYER X1Mini Pro` — handle 0x042D 00/01.
- `ONEXPLAYER X1z` — handle 0x042D 00/01.
- `ONEXPLAYER X1Pro i` — handle 0x044E 87/86/07.
- `ONEXPLAYER X1Pro EVA-02` — handle 0x044E 87/86/07.
- `ONEXPLAYER G1 A` — handle on value 7.
- `ONEXPLAYER G1 i` — handle 0x044E 87/86/07.
- `ONEXPLAYER X1Pro A EVA-02` — handle 0x042D 00/01.
- `ONEXPLAYER X1Air` — handle 0x044E 87/86/07.
- `ONEXPLAYER SUPER X` — power supply addr 0x04FE.
- `ONEXPLAYER APEX` — handle 0x042D 01/00.
- `ONEXStation` — PC mode.
- `ONEXPLAYER Apex i` — handle 0x042D 01/00.
- `ONEXPLAYER Apex Air` — same branch as Apex i.
- `ONEXPLAYER X2` — handle 0x042D 01/00.
- `ONEXPLAYER X2 EVA` — same branch as X2.
- `ONEXPLAYER X2Mini` — handle 0x042D 01/00.
- `ONEXPLAYER 3` — handle 0x042D 01/00.
- `ONEXPLAYER X2Mini PRO` — handle 0x042D 01/00.

## Legacy/OEM branches

These branches sit outside the modern `Manufacturer contains ONE-NETBOOK` path and need separate treatment. The four fields are therefore not force-filled from the modern convention.

| `board_vendor` | `board_name` | `sys_vendor` | `product_name` | Access/profile | Evidence status |
|---|---|---|---|---|---|
| `ONE-NETBOOK TECHNOLOGY CO., LTD.` | `ONE XPLAYER` | `ONE-NETBOOK TECHNOLOGY CO., LTD.` | `ONE XPLAYER` | WinRing0/direct; Intel fan-control `0x04C4`/off `0x88`, AMD fan max 100 | system pair corroborated by Linux panel-orientation/InputPlumber data |
| `IP3 Technology CO.,Ltd.` | `ARP26` | **unknown** | **unknown** | WinRing0/direct; `0x04EB`, RPM `0x0458/0x0459`, max 184 | OneXConsole only exposes the board pair; no reliable public system-pair capture found |

Do not invent the two missing ARP26 system fields merely to make a four-field kernel match. Capture them from hardware first.

## Matching implications

1. Prefer exact `DMI_BOARD_NAME` for the OneXConsole access/profile split because that is the field the vendor application actually compares.
2. Keep the four-tuple in documentation and test fixtures so system-level consumers (InputPlumber, SteamOS Manager, panel quirks, HHD) can use their native DMI fields without assuming they equal the baseboard fields.
3. Do not use a broad `ONEXPLAYER 2` prefix: `GA18`/`GA72-R` use PWM 255 while ARP23/ARP23P use 184.
4. Do not prefix-match `ONEXPLAYER X2Mini`: X2Mini is WMI/EB184/A3 while X2Mini PRO is direct/F1-255/E5.
5. Treat `ONEXPLAYER APEX` separately from `ONEXPLAYER Apex i`/`Apex Air`, and `SUPER X` separately from `SUPER V`.

## Source notes

- Vendor ground truth: user-supplied OneXConsole 0.10.2-fix8 package (`background.js` + `CompatLayerCT.exe`).
- Board-name cross-check: upstream Linux `drivers/platform/x86/oxpec.c`.
- System-pair cross-checks: ShadowBlip/InputPlumber OneXPlayer device configs, Linux panel-orientation quirks, and project X2 Mini Pro hardware findings.
- A system pair marked **inferred** is documentation scaffolding, not permission to add an exact kernel match without a live DMI dump.
