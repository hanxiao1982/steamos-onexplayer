# Bazzite / CachyOS OneXPlayer kernel enablement notes

This document records where OXP-related kernel modules live in both distros, and how each one builds and lands kernel patches. New handheld support usually needs both kernel DMI/EC mapping and userspace device config.

## Read this first

Neither side maintains a standalone `oxp.ko` source tree. AMD fans / EC go through mainline `oxpec`. Intel G3E (X2 Mini) fans / charge go through out-of-tree [`oxp-wmi`](ec/oxp-wmi.md), not `oxpec`. Buttons / RGB / gamepad config go through mainline `hid-oxp`. Distros only:

1. Backport DMI entries or quirks that are newer than mainline
2. Layer userspace on top for key mapping, TDP, and fan curves

**When targeting only the latest versions of these two systems, HHD does not need to be changed.** Key mapping is InputPlumber only. TDP / fans are not in InputPlumber; they go through PowerStation + steamos-manager, plus kernel hwmon (`oxpec` on AMD, `oxp-wmi` on Intel G3E). See [section 4](#4-userspace-latest-images-do-not-need-hhd).

| Function | Kernel module | Mainline source | Latest userspace (do not write HHD) |
| --- | --- | --- | --- |
| Fans, EC PWM, turbo takeover, charge limit | AMD: `oxpec`. Intel G3E: `oxp-wmi` | `oxpec`: `drivers/platform/x86/oxpec.c`. `oxp-wmi`: this repo `linux/oxp-wmi/` | hwmon (`oxpec` or `oxp_wmi`); Steam UI via steamos-manager `FanControl1` |
| RGB, gamepad mode, hardware key mapping | `hid-oxp` | `drivers/hid/hid-oxp.c` | InputPlumber + optional `hid-oxp` sysfs |
| TDP | Generally not in `oxpec` | AMD: `amd_pstate` / SMU; some models `acpi_call` | PowerStation + steamos-manager `TdpLimit1` |
| Gamepad / shortcut mapping | `hid-oxp` + evdev | Same as above | InputPlumber `50-onexplayer_*.yaml` |

The most common kernel change for a new machine is: add a `DMI_BOARD_NAME` row to `dmi_table[]` in `oxpec.c` and bind it to an existing board variant (`oxp_fly` / `oxp_x1` / `oxp_2`, etc.). APEX is bound to `oxp_fly` this way.

**Do not wait for mainline.** The same DMI block can be built as an out-of-tree `oxpec.ko` and installed against the running kernel on Bazzite and CachyOS. Procedure: [local-build-and-deploy.md](local-build-and-deploy.md); tools live in `kmod/`. Multiple models: one `kmod/devices/<slug>.env` per machine. `apply-all.sh` / `inject-catalog.sh` can be re-run and accumulate; they do not wipe existing entries. When the handheld already has SSH, copy the repo from a PC and run remotely: [ssh-deploy.md](ssh-deploy.md).

---

## 1. Mainline kernel: the real OXP module sources

Both distros ultimately compile this mainline driver (or the same file with a small backport).

### 1.1 `oxpec`: EC / fans / turbo / charge

- Source: <https://github.com/torvalds/linux/blob/master/drivers/platform/x86/oxpec.c>
- Kconfig: `drivers/platform/x86/Kconfig` → `CONFIG_OXPEC` (formerly `CONFIG_SENSORS_OXP`)
- Makefile: `drivers/platform/x86/Makefile` → `oxpec.o`
- Docs: historically `Documentation/hwmon/oxp-sensors.rst`; after the driver moved from `drivers/hwmon/oxp-sensors.c` to `platform/x86`, the module is still often called `oxp-sensors` / `oxpec`
- sysfs after load:
  - Fans: `/sys/class/hwmon/hwmon*/{fan1_input,pwm1,pwm1_enable}`
  - Turbo toggle: `/sys/devices/platform/oxp-platform/tt_toggle` (or under the `oxpec` platform device)

The driver picks a board variant from DMI `BOARD_VENDOR` + `BOARD_NAME`, then reads and writes different EC registers per variant.

OneXPlayer / AOKZOE board variants currently recognized by mainline:

| `enum oxp_board` | Representative models | Fan RPM | PWM enable / duty | Turbo register |
| --- | --- | --- | --- | --- |
| `oxp_mini_amd` / `oxp_mini_amd_a07` / `oxp_mini_amd_pro` | ONE XPLAYER, mini A07, Mini Pro | `0x76` | `0x4A` / `0x4B` | Mini A07: `0x1E`; Pro: `0xF1` |
| `oxp_2` | ONEXPLAYER 2 series | `0x58` | Same as above | `0xEB` |
| `oxp_fly` | F1 / F1Pro / APEX, etc. | `0x76` | Same as above | `0xF1` |
| `oxp_x1` | X1 / X1Pro / X1 mini, etc. | `0x58` | Same as above | `0xEB`, LED `0x57`, charge `0xA3`/`0xA4` |
| `oxp_g1_a` / `oxp_g1_i` | G1 A, SUPER X, G1 i | G1 logic | Same as above | Model-specific |

OXP board names already in mainline `dmi_table[]` (`DMI_BOARD_NAME`; vendor is `ONE-NETBOOK` for all):

- `ONE XPLAYER`
- `ONEXPLAYER 2` (prefix match)
- `ONEXPLAYER APEX`
- `ONEXPLAYER F1` / `F1 EVA-01` / `F1 OLED` / `F1L` / `F1Pro` / `F1 EVA-02`
- `ONEXPLAYER G1 A` / `G1 i` / `SUPER X`
- `ONEXPLAYER mini A07` / `Mini Pro`
- `ONEXPLAYER X1z` / `X1 A` / `X1 i` / `X1Air` / `X1 mini` / `X1Mini Pro` / `X1Pro` / `X1Pro EVA-02`

OGC's `features/onexplayer` branch also has `ONEXPLAYER X2Mini PRO`, plus tablet mode for X1 / Super X (pogo keyboard hotplug).

Typical new-device patch (APEX, already in stable 6.18/6.19):

```c
{
    .matches = {
        DMI_MATCH(DMI_BOARD_VENDOR, "ONE-NETBOOK"),
        DMI_EXACT_MATCH(DMI_BOARD_NAME, "ONEXPLAYER APEX"),
    },
    .driver_data = (void *)oxp_fly,
},
```

Only add a new `enum oxp_board` and register constants if the new machine's EC layout differs from existing variants — not just a DMI row.

### 1.2 `hid-oxp`: RGB / gamepad mode / hardware key mapping

- Source: <https://github.com/torvalds/linux/blob/master/drivers/hid/hid-oxp.c>
- Kconfig: `drivers/hid/Kconfig` → `CONFIG_HID_OXP`
- Makefile: `drivers/hid/Makefile` → `hid-oxp.o`
- HID IDs: `drivers/hid/hid-ids.h`
- Maintainer: Derek J. Clark, mailing list `linux-input@vger.kernel.org`
- Landed in mainline: Linux 7.2 cycle (Valve copyright)

Two HID protocol generations:

- Gen1 (F1 series): RGB only
- Gen2 (X1 mini, G1, AOKZOE A1X): RGB + hardware key mapping + gamepad mode + rumble intensity
- Hybrid MCU (G1, APEX): skip Gen2 RGB via DMI to avoid conflicts

`hid-oxp.c` also has DMI quirks, e.g. `oxp_hybrid_mcu_list[]` for APEX / G1 A / G1 i.

### 1.3 Old paths (do not edit)

- `drivers/hwmon/oxp-sensors.c`: introduced in 6.2, later moved wholesale to `oxpec.c`
- HHD README may still link the old path; treat `oxpec.c` as canonical

---

## 2. Bazzite: where the modules come from and how patches land

Bazzite is an immutable Fedora / Universal Blue image. The handheld kernel moved from in-house `kernel-bazzite` to Open Gaming Collective (OGC).

### 2.1 Current repositories

| Role | Repo | Notes |
| --- | --- | --- |
| Kernel source (including OXP topic branch) | [OpenGamingCollective/linux](https://github.com/OpenGamingCollective/linux) | stable mirror + topic branches; the OXP branch is `features/onexplayer` |
| Packaging / signed OCI | [OpenGamingCollective/kernel-packages](https://github.com/OpenGamingCollective/kernel-packages) | Fedora spec + apply `monolithic.patch` onto the kernel.org tarball |
| Distro image | [ublue-os/bazzite](https://github.com/ublue-os/bazzite) | Consumes OGC kernel RPM/OCI; does not edit `oxpec.c` directly |
| Archived old kernel | [bazzite-org/kernel-bazzite](https://github.com/bazzite-org/kernel-bazzite) | Used `patch-handheld.patch`; **do not open PRs against it** |

OGC requires **upstream-first**: patches merged into OGC must at least have been posted to LKML for review.

### 2.2 OXP source locations on the Bazzite side

Same as mainline inside the OGC tree:

```
OpenGamingCollective/linux
├── drivers/platform/x86/oxpec.c      # EC / fans
├── drivers/platform/x86/Kconfig      # CONFIG_OXPEC
├── drivers/hid/hid-oxp.c             # RGB / key mapping
├── drivers/hid/hid-ids.h
└── drivers/hid/Kconfig               # CONFIG_HID_OXP
```

Development branch:

```
https://github.com/OpenGamingCollective/linux/tree/features/onexplayer
```

What that branch has beyond mainline:

- `ONEXPLAYER X2Mini PRO` DMI
- `SW_TABLET_MODE` for X1 / Super X (pogo keyboard VID/PID: `1a86:1305`, `258a:001e`)

At packaging time, OGC folds topic branches into one `monolithic.patch` published on [OpenGamingCollective/linux releases](https://github.com/OpenGamingCollective/linux/releases). The `kernel-packages` Fedora flow is:

1. Download kernel.org `linux-<ver>.tar.xz`
2. `patch -Np1 < monolithic.patch`
3. Build RPM / OCI with `fedora/kernel.spec` + `fedora/config`

Bazzite then installs that kernel into the image. April 2026 testing already showed version strings like `6.19.10 OGC`.

### 2.3 Historical flow (for comparison only)

The old `kernel-bazzite` README was explicit:

1. Patches rebase against Fedora ARK first in [hhd-dev/patchwork](https://github.com/hhd-dev/patchwork)
2. Auto-generate `patch-handheld.patch` / `handheld.patch`
3. **Do not edit the generated patch files, and do not open PRs against that repo**
4. If a patch is missing, open an issue with a lore.kernel.org or patch link

That repo is archived. New work goes through OGC + LKML.

### 2.4 Current flow for an OXP kernel patch on Bazzite

Recommended order: mainline → OGC → Bazzite picks it up naturally.

#### A. DMI-only (most common)

1. Read DMI on the real device; do not guess:

   ```bash
   cat /sys/class/dmi/id/board_vendor
   cat /sys/class/dmi/id/board_name
   cat /sys/class/dmi/id/sys_vendor
   cat /sys/class/dmi/id/product_name
   ```

2. Compare against existing variants in `oxpec.c` and confirm fan / PWM / turbo registers match. Use `ec_sys` or a vendor EC dump.
3. Add a row to `dmi_table[]` in `oxpec.c`; if hybrid MCU is needed, update the DMI table in `hid-oxp.c` as well.
4. Make a kernel-style patch:

   ```bash
   git clone https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git
   cd linux
   git checkout -b oxp-<model>
   # Edit drivers/platform/x86/oxpec.c (and hid-oxp.c)
   git add -A
   git commit -s
   git format-patch -1
   ```

5. Send to LKML:

   - `oxpec`: `platform-driver-x86@vger.kernel.org`, Cc `lkml@antheas.dev`, `derekjohn.clark@gmail.com`
   - `hid-oxp`: `linux-input@vger.kernel.org`, Cc Derek J. Clark
   - Subject example: `[PATCH] platform/x86: oxpec: Add support for OneXPlayer <MODEL>`

6. Also give OGC a trackable path (either):
   - Open a PR against [OpenGamingCollective/linux](https://github.com/OpenGamingCollective/linux) `features/onexplayer` (commit messages often include `[FROM-ML]`, meaning from the mailing list)
   - Or open an issue on OGC / Bazzite with a lore link

7. Do not open PRs against archived `kernel-bazzite` that edit `handheld.patch`.

#### B. Local verification (immutable Bazzite)

Bazzite cannot `make modules` into `/usr` and expect it to survive the next update. Options:

- Build a patched kernel RPM the OGC / Fedora way, then `rpm-ostree override replace`
- Or a temporary DKMS / self-built `.ko` (Secure Boot blocks unsigned modules; the APEX community plugin does this)

Community reference: <https://github.com/srsholmes/onexplayer-apex-bazzite-fixes> (uses a bundled `oxpec.ko` as a stopgap until upstream DMI lands in the Bazzite kernel).

---

## 3. CachyOS: where the modules come from and how patches land

CachyOS is Arch-based. The official handheld kernel is `linux-cachyos-deckify`, not the default `linux-cachyos`. The wiki says: do not switch handhelds to another flavor.

### 3.1 Current repositories

| Role | Repo | Notes |
| --- | --- | --- |
| Kernel git tree | [CachyOS/linux](https://github.com/CachyOS/linux) | Based on upstream stable, merges Cachy topic branches |
| PKGBUILD | [CachyOS/linux-cachyos](https://github.com/CachyOS/linux-cachyos) | Packaging scripts per flavor |
| Patch repo | [CachyOS/kernel-patches](https://github.com/CachyOS/kernel-patches) | Directories by major version |
| Handheld flavor | `linux-cachyos/linux-cachyos-deckify/PKGBUILD` | Also applies `0001-handheld.patch` |

Wiki: <https://wiki.cachyos.org/features/kernel/>

### 3.2 OXP source locations on the CachyOS side

**Default already includes mainline `oxpec` / (and, on new enough versions) `hid-oxp`.** Sources live in the kernel tree used for the build, same paths as mainline:

```
CachyOS/linux  (or unpacked linux-<ver>/)
├── drivers/platform/x86/oxpec.c
└── drivers/hid/hid-oxp.c
```

Handheld extra patches are not split out as `oxp-*.patch`; they are folded into:

```
https://github.com/CachyOS/kernel-patches/blob/master/<MAJOR>/misc/0001-handheld.patch
```

Examples:

- `6.19/misc/0001-handheld.patch`
- `7.0/misc/0001-handheld.patch`
- `7.1/misc/0001-handheld.patch`

`7.2/misc/` currently has no `0001-handheld.patch` (as of the 2026-08 survey). New work should target the `<MAJOR>` that current deckify actually uses.

Key fragment of `linux-cachyos-deckify/PKGBUILD`:

```bash
_patchsource="https://raw.githubusercontent.com/cachyos/kernel-patches/master/${_major}"
source=(
    "https://github.com/CachyOS/linux/releases/download/${_srcname}/${_srcname}.tar.gz"{,.asc}
    "config"
    "${_patchsource}/misc/0001-acpi-call.patch"
    "${_patchsource}/misc/0001-handheld.patch"
)
```

`prepare()` runs `patch -Np1` on every `*.patch` in `source`. The same file also enables handheld-related Kconfig (Steam Deck, Ally, MSI Claw, `ACPI_CALL`, etc.). `oxpec` / `HID_OXP` are usually already in the base config; no need to set them again.

### 3.3 Flow for an OXP kernel patch on CachyOS

CachyOS accepts GitHub PRs; more direct than Bazzite/OGC.

#### A. Land in the official kernel (recommended)

1. Confirm DMI on the real device first, and prefer sending the patch upstream (Cachy also prefers taking mainline).
2. Fork [CachyOS/kernel-patches](https://github.com/CachyOS/kernel-patches).
3. Edit or add a patch in the matching version directory:
   - Small change (DMI only): edit `<MAJOR>/misc/0001-handheld.patch` directly, or add `misc/0002-oxp-<model>.patch`
   - A new file is cleaner, but deckify `source=()` **must include that URL**, or `makepkg` will neither download nor apply it
4. If you only edit the existing `0001-handheld.patch` in `kernel-patches`, the deckify PKGBUILD does not need changes (it already references that file).
5. Open a PR describing the model DMI, EC variant, and testing. README wording: fork + PR, and state what the patch does.
6. Also open an issue on [CachyOS/linux-cachyos](https://github.com/CachyOS/linux-cachyos) so deckify maintainers see the handheld need. The wiki also says to open an issue for default-kernel improvements.

#### B. Local rebuild of deckify for verification

```bash
git clone https://github.com/CachyOS/linux-cachyos.git
cd linux-cachyos/linux-cachyos-deckify

# Drop your own patch in the directory and add it to PKGBUILD source=()
# e.g. 0002-oxp-new-model.patch

updpkgsums          # or try --skipchecksums with makepkg
makepkg -s
sudo pacman -U linux-cachyos-deckify-*.pkg.tar.zst
```

`prepare()` applies every `*.patch` automatically. Notes:

- Patches are relative to the kernel tree root, `patch -Np1`
- They must apply on the tree after CachyOS has already applied base / handheld
- After a major kernel bump, rebase onto the new `<MAJOR>/misc/`

#### C. User-built patch (standard forum answer)

[CachyOS forum: How to rebuild a kernel with an additional patch](https://discuss.cachyos.org/t/how-to-rebuild-a-kernel-with-an-additional-patch/16495)

1. Copy the official PKGBUILD + `config`
2. Put the `.patch` in the same directory and add it to `source`
3. `makepkg`

This is only for local experiments. For all Cachy handheld users to benefit, still PR into `kernel-patches`.

---

## 4. Userspace: latest images do not need HHD

Kernel `oxpec` only exposes hwmon PWM and a few EC attributes. Buttons, TDP, and fan curves still need userspace. The latest official stacks on both sides no longer use HHD.

### 4.1 Conclusion: skip HHD, but InputPlumber alone is not enough

| Question | Answer |
| --- | --- |
| Do latest Bazzite / CachyOS Handheld still install HHD by default? | **No.** You do not need to write HHD `const.py` for these two systems. |
| Are buttons / back buttons / shortcuts / gamepad emulation enough with InputPlumber only? | **Yes.** That is the official input stack. |
| Are TDP / fan curves enough with InputPlumber only? | **No.** InputPlumber does not handle power or fans. |

HHD is now an optional fallback: the CachyOS repos still have an `hhd` package, and it fights InputPlumber for the gamepad. Official images do not enable it automatically. Old docs (`docs.bazzite.gg` handheld page; Legion still listed as HHD in the `CachyOS-Handheld` README) are stale. Trust the packages the image and chwd actually install.

### 4.2 Verification: what the latest images install

**Bazzite**

- 2026-01 official announcement ([A brighter future for Bazzite](https://universal-blue.discourse.group/t/a-brighter-future-for-bazzite/11575)): HHD is no longer updated; switch to InputPlumber, aligning with SteamOS / ChimeraOS / Nobara / CachyOS Handheld. Reasons include the HHD maintainer leaving the project; Bazzite was then the only distro still shipping HHD.
- 2026-03-16 merge [ublue-os/bazzite `ce953e4`](https://github.com/ublue-os/bazzite/commit/ce953e4306f2effa58f2fbb8a833081685aa5424): removed HHD service, polkit, and COPR from the image; switched to InputPlumber / OpenGamepadUI / PowerStation.
- Current `main` `Containerfile` handheld packages are `inputplumber`, `steamos-manager-powerstation`, `steamos-manager-powerstation-gamescope-session-plus`, and `systemctl enable inputplumber.service` plus `steamos-manager.service`. No `hhd`.
- Testing images (e.g. `testing-44.20260807`) list InputPlumber 0.78 + PowerStation, no HHD.

**CachyOS Handheld**

- 2026-01 release notes: hardware detection moved from HHD to `steamos-manager` + `inputplumber`.
- Current [chwd `profiles/pci/handhelds/profiles.toml`](https://github.com/CachyOS/chwd/blob/master/profiles/pci/handhelds/profiles.toml) generic handheld profile:

  ```toml
  packages = 'steamos-manager inputplumber steamos-powerbuttond'
  ```

  No `hhd`. `hwd_product_name_pattern` already covers a set of OXP / AOKZOE `product_name` values (`ONE XPLAYER`, `ONEXPLAYER F1*`, `X1*`, `G1*`, etc.). If a new machine is not in that regex, the installer will not pull this package set automatically.
- The `CachyOS-Handheld` README still says Legion defaults to HHD; that does not match current chwd. Trust chwd.
- Repos still have an `hhd` package (e.g. 4.1.8) for manual install; mutually exclusive with InputPlumber.

### 4.3 Key mapping: InputPlumber only

Repo: <https://github.com/ShadowBlip/InputPlumber>

```
rootfs/usr/share/inputplumber/devices/50-onexplayer_*.yaml
rootfs/usr/share/inputplumber/capability_maps/onexplayer_type*.yaml
rootfs/usr/lib/udev/hwdb.d/60-inputplumber-autostart.hwdb
src/drivers/oxp_hid/          # HID vendor reports (back buttons M1/M2, etc.)
src/drivers/oxp_tty/          # serial protocol
src/input/source/hidraw/oxp_hid.rs
```

Existing device YAML:

- `50-onexplayer_amd.yaml` / `50-onexplayer_intel.yaml`
- `50-onexplayer_mini_a07.yaml` / `50-onexplayer_mini_pro.yaml`
- `50-onexplayer_2.yaml` / `50-onexplayer_onexfly.yaml`
- `50-onexplayer_x1.yaml` / `50-onexplayer_g1.yaml` / `50-onexplayer_apex.yaml`
- `50-aokzoe_a1.yaml`

Typical new machine: copy the closest YAML → change DMI `product_name` → pick or create a capability map → add the DMI to `60-inputplumber-autostart.hwdb`. Models with vendor HID like X1 / APEX (`1a86:fe00`) may also need `src/drivers/oxp_hid/`.

Detection uses `product_name`, which can differ from the `board_name` used by kernel `oxpec`. Collect both.

CachyOS also needs the new `product_name` in chwd `hwd_product_name_pattern`, or a fresh install will not pull InputPlumber.

### 4.4 TDP / fans: not InputPlumber; PowerStation + steamos-manager

| Component | Repo | Role |
| --- | --- | --- |
| PowerStation | [ShadowBlip/PowerStation](https://github.com/ShadowBlip/PowerStation) | Generic CPU/GPU TDP D-Bus; Bazzite may use it as a Steam slider backend |
| steamos-manager | [OpenGamingCollective/steamos-manager](https://github.com/OpenGamingCollective/steamos-manager) (CachyOS uses the same family of packages) | Steam client's `TdpLimit1` / `FanControl1` / GPU clocks, etc. |
| `oxpec` / `oxp_wmi` hwmon | Kernel | Fan PWM. **Not TDP.** |
| `oxp-tdp-rapl` | this repo `userspace/tdp-rapl/` | Intel G3E: `remotes.d` `TdpLimit1` → RAPL PL1/PL2 |

PowerStation is mainly generic AMD/Intel sysfs, not HHD-style per-model EC tables. A DMI row in `/usr/share/steamos-manager/devices` without `[tdp_limit]` still hides the Steam slider. Live X2 Mini Bazzite had no `X2Mini` device file, empty `remotes.d`, and session `TdpLimit1` missing — see [ec/tdp.md](ec/tdp.md).

Fan curves: first make sure hwmon is up (`oxpec` on AMD, `oxp_wmi` on Intel G3E) and `pwm1` appears. Steam UI fans need steamos-manager implementing `FanControl1` (local or `remotes.d` remote). That is not InputPlumber's job. `FanControl1` already present ≠ it writes `oxp_wmi`.

Intel OXP TDP is RAPL/MSR, not EC. HHD also marked many Intel units `w/o TDP`. The RAPL remote is the fill until a distro device.toml / PowerStation path actually advertises `TdpLimit1`.

### 4.5 HHD as historical reference only (latest images do not need changes)

Repo: <https://github.com/hhd-dev/hhd>, path `src/hhd/device/oxp/const.py`.

Touch it only for old Bazzite / CachyOS users who installed HHD by hand, or to compare old-device protocols (`hid_v1` / `serial` / `mixed`). Official latest images do not load this config. Adjustor was merged into hhd v4; that repo is archived.

---

## 5. New handheld checklist

Do these in dependency order so you do not change only one side.

1. **Collect DMI and EC**
   - `board_vendor` / `board_name` / `product_name` / `sys_vendor`
   - Whether EC fan, PWM, and turbo registers match `oxp_fly` / `oxp_x1` / `oxp_2`
   - HID: `lsusb` / `hidraw`; check for an OXP MCU like `1a86:fe00`
2. **Kernel `oxpec`**
   - Same EC: DMI only → existing variant
   - Different EC: new `oxp_board` + register macros + read/write branches
3. **Kernel `hid-oxp`**
   - Add HID ID or DMI quirk when RGB / hardware mapping / hybrid MCU is needed
4. **Land the patch in the distro**
   - Bazzite: LKML + OGC `features/onexplayer` (do not edit archived kernel-bazzite)
   - CachyOS: `kernel-patches/<MAJOR>/misc/` + deckify `source` (if adding a new file)
5. **Userspace keys (latest images: InputPlumber only, not HHD)**
   - `50-onexplayer_<model>.yaml` + capability map + `60-inputplumber-autostart.hwdb`
   - Vendor HID models: `src/drivers/oxp_hid/`
   - CachyOS: add `product_name` to the regex in chwd `handhelds/profiles.toml`
6. **TDP / fans (not InputPlumber)**
   - Fans: get hwmon first (`oxpec` or `oxp_wmi`); then confirm steamos-manager `FanControl1`
   - TDP: Steam slider is `TdpLimit1`. AMD: SMU / PowerStation. Intel G3E: this repo's RAPL remote (`install-tdp-rapl.sh`), not EC

---

## 6. Side-by-side flows

```
                         mainline Linux
                    oxpec.c    hid-oxp.c
                         |          |
          ---------------+----------+---------------
          |                                     |
          v                                     v
  OpenGamingCollective/linux              CachyOS/linux
  branch: features/onexplayer             + kernel-patches
  -> monolithic.patch                     <MAJOR>/misc/0001-handheld.patch
  -> kernel-packages                      -> linux-cachyos-deckify PKGBUILD
  -> Bazzite ostree
          |                                     |
          v                                     v
  InputPlumber + PowerStation             InputPlumber + steamos-manager
  50-onexplayer_*.yaml                    same YAML; chwd profiles.toml
```

| Step | Bazzite / OGC | CachyOS |
| --- | --- | --- |
| Source edit point | `oxpec.c` / `hid-oxp.c` in `OpenGamingCollective/linux` | Same mainline files; distro delta in `CachyOS/kernel-patches` |
| Patch form | Topic-branch commit + published `monolithic.patch` | `<MAJOR>/misc/*.patch`, `patch -Np1` |
| Landing path | **LKML first**, then OGC PR/issue; do not edit archived `handheld.patch` | **GitHub PR** to `kernel-patches`; new files also need a deckify `source` change |
| Local verification | Self-built module / rpm-ostree kernel swap | Edit deckify PKGBUILD then `makepkg` |
| Handheld target kernel | OGC kernel (ships in the Bazzite image) | `linux-cachyos-deckify` |

---

## 7. References

- Mainline `oxpec`: <https://github.com/torvalds/linux/blob/master/drivers/platform/x86/oxpec.c>
- Mainline `hid-oxp`: <https://github.com/torvalds/linux/blob/master/drivers/hid/hid-oxp.c>
- APEX DMI patch (lore): <https://lists.openwall.net/linux-kernel/2026/02/23/1626>
- OGC kernel: <https://github.com/OpenGamingCollective/linux/tree/features/onexplayer>
- OGC packaging: <https://github.com/OpenGamingCollective/kernel-packages>
- Old Bazzite kernel (archived): <https://github.com/bazzite-org/kernel-bazzite>
- CachyOS patch repo: <https://github.com/CachyOS/kernel-patches>
- CachyOS deckify PKGBUILD: <https://github.com/CachyOS/linux-cachyos/blob/master/linux-cachyos-deckify/PKGBUILD>
- InputPlumber: <https://github.com/ShadowBlip/InputPlumber>
- PowerStation: <https://github.com/ShadowBlip/PowerStation>
- steamos-manager: <https://github.com/OpenGamingCollective/steamos-manager>
- CachyOS chwd handheld profile: <https://github.com/CachyOS/chwd/blob/master/profiles/pci/handhelds/profiles.toml>
- Bazzite drops HHD: <https://github.com/ublue-os/bazzite/commit/ce953e4306f2effa58f2fbb8a833081685aa5424>
- HHD OXP (old systems only): <https://github.com/hhd-dev/hhd/tree/master/src/hhd/device/oxp>
