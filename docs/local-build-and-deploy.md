# Local fetch, build, test, and install without waiting for mainline

Do not rebuild the whole kernel just to add a DMI row. Both distros already ship the `oxpec` logic; a new AMD handheld usually only needs `board_name`. Procedure:

1. Fetch the current `oxpec.c`
2. Inject the same DMI block (identical C on both distros)
3. Build `oxpec.ko` against the **running** kernel headers
4. Load it from `/var/lib/oxp-kmod` (writable on Bazzite; `/usr` is not)
5. Overlay InputPlumber YAML for buttons. Do not touch HHD

Tools live in `kmod/`.

---

## 0. Pick a path before `make -j` on a full kernel

| Path | What it does | When to use it |
| --- | --- | --- |
| **A. Out-of-tree module (recommended)** | AMD: build `oxpec.ko`. **X2 Mini / Intel G3E: build `oxp-wmi.ko`** | New device only needs a DMI row (oxpec) or the in-repo OxpWMI driver. Works on Bazzite and CachyOS |
| B. Rebuild CachyOS deckify | `makepkg` with `0001-handheld.patch` | New EC register logic, or the out-of-tree module cannot match vermagic |
| C. Rebuild the Bazzite / OGC kernel | Fedora RPMs + ostree kernel swap | Almost never worth it for a DMI row; expensive and needs signing |

`hid-oxp` DMI quirks (hybrid MCU / RGB) can also be built out of tree, but they depend on HID/LED and are more fragile. Get fan hwmon working first.

---

## 1. Collect DMI on the handheld (repeatable; one file per model)

Each new machine adds one `kmod/devices/<slug>.env`. Inject and InputPlumber install apply **every** file in that directory. Do not reuse a single `local-device.env` and overwrite `BOARD_NAME` — that drops the previous model.

On the handheld:

```bash
cd /path/to/steamos-onexplayer
chmod +x kmod/scripts/*.sh
kmod/scripts/collect-dmi.sh --add          # writes kmod/devices/<slug>.env
# optional slug: kmod/scripts/collect-dmi.sh --add f1-oled-2026
```

`--add` creates or replaces **that one file** only. Use `--force` to overwrite an existing file.

Copy the new `.env` back into the repo (keep the old ones). On any machine:

```bash
kmod/scripts/apply-all.sh --list           # catalog
kmod/scripts/apply-all.sh --fetch ogc      # refetch oxpec.c, inject all models, build
```

`fetch-oxpec.sh` overwrites `oxpec.c` (injections are lost); inject again. `apply-all.sh --fetch` is “fetch upstream + put every catalogued DMI back”. Re-running inject is idempotent: existing `BOARD_NAME` rows are `skipped`.

`kmod/local-device.env` is an optional extra (legacy). Placeholder `ONEXPLAYER NEWMODEL` is skipped. So are `example.env` and `_*.env`.

Choose `OXP_BOARD_VARIANT` from the EC map, not the marketing name:

| Variant | Typical SKUs | Fan register | Turbo |
| --- | --- | --- | --- |
| `oxp_fly` | F1 / F1Pro / APEX | `0x76` | `0xF1` |
| `oxp_x1` | X1 series | `0x58` | `0xEB` |
| `oxp_2` | 2 series | `0x58` | `0xEB` |
| `oxp_g1_a` / `oxp_g1_i` | G1 / SUPER X | G1 logic | model-specific |
| `oxp_wmi` | **X2 Mini / X2 / OXP3 / Apex Air (Intel OxpWMI)** | `0x58`/`0x4A`/`0x4B` (PWM 0–184) | not oxpec |

`collect-dmi.sh` writes `OXP_EC_STACK=oxp-wmi` for `ONEXPLAYER X2Mini` (not `X2Mini PRO`). The repo already ships `kmod/devices/x2-mini.env`.

If the AMD variant is unknown: try `oxp_fly` first and check whether `fan1_input` looks like an RPM.

### X2 Mini: build oxp-wmi, not oxpec

Intel G3E has no ACPI EC for `oxpec`. Fan and charge go through WMI. After the scripts detect X2 Mini:

```bash
kmod/scripts/ec-stack.sh          # oxp-wmi
kmod/scripts/apply-all.sh         # make -C $KDIR M=linux/oxp-wmi
sudo kmod/scripts/test-oxp-wmi.sh
sudo kmod/scripts/install-oxp-wmi.sh
sudo kmod/scripts/install-inputplumber.sh
```

`install-cachyos.sh` / `install-bazzite.sh` / `ssh-handheld.sh … all` take this path automatically. Source is `linux/oxp-wmi/`; no `fetch-oxpec.sh`. See [ec/oxp-wmi.md](ec/oxp-wmi.md).

---

## 2. Fetch the source and apply the same edit

```bash
# Bazzite is closer to the OGC tree; CachyOS can use mainline. Same inject script.
kmod/scripts/fetch-oxpec.sh ogc        # or mainline / cachyos
kmod/scripts/inject-catalog.sh         # every kmod/devices/* model
# same as: kmod/scripts/apply-all.sh --fetch ogc --inject-only
```

Injection is equivalent to adding this to `dmi_table[]`:

```c
{
    .matches = {
        DMI_MATCH(DMI_BOARD_VENDOR, "ONE-NETBOOK"),
        DMI_EXACT_MATCH(DMI_BOARD_NAME, "ONEXPLAYER NEWMODEL"),
    },
    .driver_data = (void *)oxp_fly,
},
```

Replace `NEWMODEL` with the **`board_name`** from `collect-dmi.sh`. That is the shared change for both distros.

Source URLs:

| Argument | File |
| --- | --- |
| `mainline` | `https://raw.githubusercontent.com/torvalds/linux/master/drivers/platform/x86/oxpec.c` |
| `ogc` | same path on `OpenGamingCollective/linux` `features/onexplayer` |
| `cachyos` | same path on `CachyOS/linux` `master` |

---

## 3. Build against this machine’s `uname -r`

```bash
kmod/scripts/build.sh
```

The script:

- uses `/lib/modules/$(uname -r)/build`
- adds `LLVM=1` if `.config` has `CONFIG_CC_IS_CLANG=y` (common on default CachyOS; deckify is usually GCC)
- writes `kmod/oxpec/oxpec.ko` (or `linux/oxp-wmi/oxp-wmi.ko` on X2 Mini)

### CachyOS headers

```bash
sudo pacman -S --needed linux-cachyos-deckify-headers base-devel pahole
# confirm the handheld is actually running deckify
uname -r    # e.g. 7.1.8-1-cachyos-deckify
```

One-shot (root; at least one real `devices/*.env` in the catalog):

```bash
sudo kmod/scripts/install-cachyos.sh
```

### Bazzite headers (the usual blocker)

Images often **ship no** `kernel-devel`. Check:

```bash
ls -l /lib/modules/$(uname -r)/build
rpm -q kernel-devel kernel-devel-matched || true
uname -r
```

- If `build` is a real directory: run `kmod/scripts/build.sh`
- If not: install the OGC `kernel-devel` whose **vermagic matches exactly**. Do not layer stock Fedora `kernel-devel`

```bash
# example only: the version must be your uname -r
rpm-ostree install /path/to/kernel-devel-$(uname -r).rpm
sudo systemctl reboot
```

OGC ships devel RPMs next to the kernel RPMs. See Fedora artifacts on [OpenGamingCollective/kernel-packages](https://github.com/OpenGamingCollective/kernel-packages), or `kernel-devel` in the current Bazzite image build log. A mismatch yields `Invalid module format`.

Fallback without matching devel: build `oxpec.ko` on another Fedora box with that same `kernel-devel`, copy it to the handheld, run `install-common.sh`. The Apex community plugin does the same with prebuilt `.ko` files.

One-shot (root, `build` present, Secure Boot off):

```bash
sudo kmod/scripts/install-bazzite.sh
```

---

## 4. Local test

Without loading (normal user):

```bash
kmod/scripts/test-oxpec.sh
```

Load and probe hwmon (root):

```bash
# X2 Mini / Intel G3E
sudo kmod/scripts/test-oxp-wmi.sh linux/oxp-wmi/oxp-wmi.ko
# AMD / oxpec
sudo kmod/scripts/test-oxpec.sh kmod/oxpec/oxpec.ko
```

Success looks like `name=oxp_wmi` (X2 Mini) or `name=oxpec` (AMD).

Manual fan smoke test (restores auto afterwards). **Do not** copy the old `name == oxpec` loop onto X2 Mini: an empty `$HWMON` writes `/pwm1` on the ostree root and Bazzite reports “Read-only file system”.

```bash
# finds oxp_wmi first, then oxpec
sudo kmod/scripts/hwmon-pwm.sh 40
sudo kmod/scripts/hwmon-pwm.sh --read
```

Or by hand on X2 Mini:

```bash
HWMON=$(ls -d /sys/class/hwmon/hwmon* | while read d; do
  [[ $(cat "$d/name") == oxp_wmi ]] && echo "$d"
done)
# abort if empty — otherwise you write /pwm1 on the read-only root
[[ -n "$HWMON" ]]
echo 1 > "$HWMON/pwm1_enable"
echo 102 > "$HWMON/pwm1"          # 102/255 ≈ 40% → EC ≈ 74/184
sleep 3
echo 2 > "$HWMON/pwm1_enable"     # 2 = auto
```

Failure table:

| Symptom | Cause | Fix |
| --- | --- | --- |
| `Invalid module format` | vermagic ≠ `uname -r` | rebuild against matching headers |
| `Key was rejected by service` / `Required key not available` | Secure Boot | disable SB, or sign with a MOK |
| `insmod` succeeds but no hwmon | `board_name` mismatch, or looking for `oxpec` on X2 Mini | X2 Mini hwmon name is `oxp_wmi`; rerun `collect-dmi.sh` on AMD |
| `Read-only file system` on `/pwm1` | `$HWMON` was empty; the shell wrote `/pwm1` on ostree `/` | use `hwmon-pwm.sh` or match `oxp_wmi` |
| `modprobe: FATAL: Module oxpec is in use` | userspace holds hwmon | stop InputPlumber / fan services, then `-r` |
| cannot `modprobe -r oxpec` | `CONFIG_OXPEC=y` built-in | path B/C only (rebuild the kernel) |

Check built-in vs module:

```bash
grep OXPEC /lib/modules/$(uname -r)/config
# or
zgrep CONFIG_OXPEC /proc/config.gz
```

Only `=m` can be replaced.

### Can signing block an out-of-tree module on the running kernel?

**Yes, but that is not because you only built one module.** A local `oxpec.ko` is unsigned by default. The running kernel accepts it only if two independent gates pass:

| Gate | What it checks | Typical error | Relation to “module-only build” |
| --- | --- | --- | --- |
| **vermagic** | `.ko` must be built against **this** `uname -r` | `Invalid module format` | Building only the module is correct; do not reuse another machine’s `kernel-devel` |
| **Signature** | Secure Boot on, or `CONFIG_MODULE_SIG_FORCE=y` | `Key was rejected by service` / `Required key not available` | Distro `oxpec.ko` is signed with the kernel RPM; your `make` output is not |

Typical combinations:

- **CachyOS, Secure Boot off, no FORCE:** unsigned local `.ko` can `insmod`. Easiest path.
- **Bazzite with Secure Boot on (default):** unsigned modules are rejected. `ujust enroll-secure-boot-key` enrolls Universal Blue’s key only and **does not** sign your `.ko`.
- **`CONFIG_MODULE_SIG=y`, FORCE off, SB off:** official modules are signed; unsigned out-of-tree modules are still allowed.
- **`CONFIG_MODULE_SIG_FORCE=y`:** disabling SB is not enough; sign the `.ko` with a key the kernel trusts.

`check-env.sh` / `ssh-handheld.sh check` read `CONFIG_MODULE_SIG*` and `mokutil --sb-state`. Bazzite with SB on is a hard `[FAIL]`.

To pass the signature gate (easiest first):

1. Disable Secure Boot in firmware (recommended for local bring-up)
2. Create a MOK, sign with the kernel tree’s `scripts/sign-file`, enroll with `mokutil --import` (not the ujust distro key)
3. Land the DMI in the official OGC / CachyOS kernel and use their signed module

Rebuilding the whole kernel does **not** fix signing by itself — those RPMs still follow the distro signing process.

---

## 5. Local deploy (load at boot)

`install-common.sh` is the same on both distros:

- copy `oxpec.ko` to `/var/lib/oxp-kmod/oxpec.ko`
- write `/etc/systemd/system/oxpec-local.service` (unload in-tree `oxpec`, then `insmod`)
- `systemctl enable --now oxpec-local.service`

```bash
sudo kmod/scripts/install-common.sh
```

On Bazzite do not drop an unsigned module into `/usr/lib/modules`; the next ostree update removes it. `/var` + `/etc` survive routine updates; **rebuild after every kernel ABI bump**.

CachyOS auto-rebuild after kernel upgrades:

```bash
sudo pacman -S --needed dkms
sudo dkms add /path/to/steamos-onexplayer/kmod/oxpec
sudo dkms install oxpec-local/1.0.0
```

---

## 6. Buttons: local InputPlumber overlay (still no HHD)

```bash
# one 50-onexplayer-local-<slug>.yaml per kmod/devices/*.env
# plus /etc/udev/hwdb.d/61-oxp-local.hwdb with every DMI line
sudo kmod/scripts/install-inputplumber.sh
journalctl -u inputplumber -b --no-pager | tail -n 50
```

Template: `kmod/inputplumber/50-onexplayer_local.yaml`. `phys_path` varies by USB port; start with wide `name` + `handler` matches, then tighten with `evtest` / `udevadm info`.

`OXP_CAP_MAP`: APEX-class `oxp8`, X1-class try `oxp5`. Each `.env` can differ.

A fresh CachyOS install also needs the `product_name` in chwd `handhelds/profiles.toml`, or the next machine will not pull InputPlumber automatically. For a one-off test: `sudo pacman -S inputplumber`.

---

## 7. Path B: fold the patch into CachyOS deckify (optional)

After the out-of-tree module works, turn it into a distro patch:

```bash
git clone https://github.com/CachyOS/linux-cachyos.git
cd linux-cachyos/linux-cachyos-deckify
# save the oxpec.c diff as 0002-oxp-local.patch
# add it to PKGBUILD source=()
makepkg -s
sudo pacman -U linux-cachyos-deckify-*.pkg.tar.zst \
               linux-cachyos-deckify-headers-*.pkg.tar.zst
```

`prepare()` runs `patch -Np1` on every `*.patch`. Upstream inclusion is a PR to `CachyOS/kernel-patches`.

A full kernel build takes a long time; skip it for a DMI-only change.

---

## 8. Path C: why not rebuild the Bazzite kernel

Bazzite is an ostree image; the kernel is a signed OGC RPM. A local full rebuild needs:

1. Apply `monolithic.patch` via `OpenGamingCollective/kernel-packages`
2. Produce kernel / kernel-core / kernel-modules RPMs
3. `rpm-ostree override replace` the set
4. Sign again if Secure Boot is on

For one DMI row, out-of-tree `oxpec.ko` plus SB off is enough. The Apex community does the same.

`ujust enroll-secure-boot-key` only enrolls Universal Blue’s key. It will **not** accept your unsigned `.ko`.

---

## 9. Copy the repo to the handheld over SSH

If the handheld has SSH, you do not need its on-screen keyboard. From a PC:

```bash
kmod/scripts/ssh-handheld.sh bazzite@192.168.1.50 all
```

That rsync/tar-copies the repo, runs `check-env.sh` (headers, gcc/clang, Secure Boot, DMI, GitHub), then remote `collect-dmi.sh --add`, detects Bazzite vs CachyOS, builds and installs, and pulls the new `devices/*.env` back. A `[FAIL]` stops the run. Full commands, raw ssh/scp, and offline handhelds: [ssh-deploy.md](ssh-deploy.md).

---

## 10. Suggested order

```
On the handheld: collect-dmi.sh --add          # this model only
    -> commit the new devices/<slug>.env (keep old ones)
    -> apply-all.sh --fetch ogc                # fetch + inject all + build
    -> sudo test-oxpec.sh                      # hwmon present
    -> sudo install-common.sh
    -> sudo install-inputplumber.sh
    -> send the same DMI diff to LKML / OGC / CachyOS
Next machine: --add again; do not overwrite the previous .env
```

Kernel module source: `kmod/oxpec/oxpec.c` (fetched then injected; do not commit).  
Model catalog: `kmod/devices/*.env`.  
Userspace buttons: one `50-onexplayer-local-<slug>.yaml` per model.  
Do not write HHD.
