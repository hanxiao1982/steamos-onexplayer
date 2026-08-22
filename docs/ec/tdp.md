# Intel TDP on X2 Mini (RAPL, not EC)

Steam's TDP slider is `TdpLimit1` on the **session** bus
`com.steampowered.SteamOSManager1`. If that interface is missing, the client
hides the slider. Steam does not match DMI itself.

X2 Mini watts are **not** in `oxp-wmi`. EC `0xED` stays 0. Windows OneXConsole
writes Intel MSR (`/msr/setCpuPl/{pl1}/{pl2}/4`). On Linux the same package
limits are `/sys/class/powercap/intel-rapl:*`.

Live Bazzite (`ONEXPLAYER X2Mini`): no `X2Mini` file under
`/usr/share/steamos-manager/devices`, empty `remotes.d`, session introspect
had `FanControl1` but **no** `TdpLimit1` / `GpuPerformanceLevel1`. That is why
the slider is gone.

This repo fills the hole with a **system-bus remote**, not a device.toml and
not HHD:

```
Steam → steamos-manager TdpLimit1 → remotes.d oxp-rapl.toml
      → com.steampowered.OxpRapl.Tdp → intel-rapl PL1 (+ PL2 = PL1+1 W)
```

Slider range for X2 Mini: **3–45 W**, default **25 W** (live
`/tdp/init/3/45/46`). The daemon reports the current PL1 if it already
sits in range.

Installing the remote does **not** prove RAPL *enforcement*. Confirm that
separately under load (`diag-tdp.sh --set` 15 then 40). Overlay CPU watts are
RAPL `energy_uj` telemetry, not the PL1 cap, and are often 0 if `energy_uj` is
root-only.

## Diagnose (before or after install)

```bash
kmod/scripts/diag-tdp.sh
# under the same game/stress, as root:
sudo kmod/scripts/diag-tdp.sh --set 15 --measure 5
sudo kmod/scripts/diag-tdp.sh --set 40 --measure 5
```

Limits are working only if the two package-watt samples separate and
frequencies move with them. An idle SSH login sampling ~5 W at both 15 W and
40 W only proves the **cap files accept writes**, not that RAPL is throttling.

TDP is a **cap**, not a target: ~30 W at PL1=45 W is success. OneXConsole
does **not** write RAPL `long_term` tau (see below), so the BIOS ~28 s
window stays. A 10 s `energy_uj` sample right after `--set 25` can still
include the previous 45 W period (~27 W). That is averaging, not a failed
write. `diag-tdp.sh --set` runs `oxp-tdp-rapl --set` (MSR **and** MMIO PL1,
GT `max_freq`; firmware tau) and settles a few seconds for PCODE/GT, not
for the 28 s window to roll over. Check `intel-rapl-mmio:0` long_term and
GT0 `max_freq` after each set. Game Mode is not GPU-idle; 45 W +
`max=2300` can keep `act_freq` at RP0 while Steam composites.

## OneXConsole and `long_term` (tau)

RAPL `constraint_0` / `long_term` is two knobs: **watts** (`power_limit_uw`)
and **window** (`time_window_us`, Intel tau). Live X2 Mini BIOS encodes
about **28 s** (`27983872` µs). PL2 `short_term` stays ~1 ms.

Windows OneXConsole 0.10.2-fix8 never takes a tau argument:

| Call | What it writes |
|---|---|
| `/msr/setCpuPl/{pl1}/{pl2}/{type}` | PL1 = slider, PL2 = PL1+1 (45→46), type 4 = IntelPowerPlugin (MSR+MMIO). Live: `11/12`, `18/19`, `32/33`, `34/35`, `28/29`, `37/38`, `45/46`. |
| `/msr/setCpuPl4/{pl4}/{type}` | Adapter-class PL4, **before** each `setCpuPl` when `0xE3` maps. Battery pcap: **160** on 100 W (even at 11 W), **120** on 65 W+battery. Adapter-only 16/18: skipped. |
| `/tdp/init/{min}/{max}/{maxBoost}` | UI bounds only. Live boot: **`3/45/46`**. |
| `/func/getOXPSetTdpAble` | EC `0xED` gate read (stays 0; TDP is not EC) |
| `changePl4Func` keys | Adapter-class / PL4 table, not a time window |

CompatLayerCT type 4 is Intel DTT/IPF (or a raw MSR write of
`PKG_POWER_LIMIT` **watts + clamp-enable bits**). There is no public
`time_window` / `long_term` path. Firmware tau is left alone. Windows
“feels” like the slider matches because DTT/PCODE also steers GT, not
because they set a 2 s window.

**Replicable on Linux:** write PL1/PL2 and adapter-class PL4 on
`intel-rapl:0` **and** `intel-rapl-mmio:0`; do **not** write
`constraint_*_time_window_us`. The daemon only restores ~28 s if a
previous build left a 2 s leftover. `OXP_TDP_PL1_WINDOW_US` is an
explicit diag override, not the default.

**Not a OneXConsole clone:** shortening tau, or interpolating GT
`max_freq`, only changes how Linux *looks*. Windows split is DTT, not RAPL
tau. See [CPU vs GPU split](#cpu-vs-gpu-split-not-pl1) below.

To judge a lower TDP, wait longer than the printed `window=` (about 28 s)
or use `--measure 30`. A 10 s sample after dropping 45 → 25 W can still
read above 25 W.

## CPU vs GPU split (not PL1)

Writing the same PL1/PL2/PL4 watts as Windows and still seeing a different
CPU/GPU split is expected. Package RAPL is the **shared ceiling**. Who
eats that ceiling is a second policy layer.

### Already in the 0.10.2-fix8 route list (under-used)

| Interface | What it actually does to the split |
|---|---|
| `/msr/setCpuPl/{pl1}/{pl2}/{type}` **`type`** | Live `/37/38/4`: slider=PL1, PL2=PL1+1, **4 = IntelPowerPlugin / CCHWApiExt** (SetPL1MSR+MMIO). Default type is 3 (raw `msr-cmd` 0x610). Not a watt. |
| `/msr/setCpuPl4/{pl4}/{type}` | Adapter-class peak clamp (160 / 120 / 65), not a CPU/GPU ratio. Sent on every TDP apply when `0xE3` maps; skipped for adapter-only 16/18. |
| `/powerplan/setCpuBoostMode/{0\|2}` | Windows CPU Boost (OEM “Turbo On”). Boost on → IA takes more of the package; Boost off → leftover goes to GT. Community X1 notes: GPU-bound games want Turbo **off**. |
| `/powerplan/setCpuMaxClock/{MHz}` | Caps IA max MHz (0 = off). Same idea: clip CPU so GPU can keep the watts. |
| `/intelpnp/setOEMVarWithPowerScheme/{oemVar}` | Intel PnP OEM variable via the power scheme. DTT/Adaptive-Performance-shaped; not package watts. **JS does call this.** |
| `/power/setCpuMaxStatusPercent/{n}` | In the **exe** UriTemplates, **not** in 0.10.2-fix8 `background.js` invokes. Windows processor-maximum-state (%). Best named CPU↔GPU share knob in the binary. |
| `/power/setCpuBoostMode/{n}` | Exe-only alias of the powerplan boost write. |
| `/battery/setMaxTdpLimit/{true\|false}` | Boot sent `true`; slider still moved 11–45 W. Not “pin PL1 to max”. |
| `changePl4Func` via EC `0xE3` | Adapter-class PL4 (65 / 120 / 160 W). Burst headroom, not a ratio. |

X2 Mini has **no** `/ryzenadj/setGpuClock` / `manualGpuClk`. There is no
OneXConsole GPU-MHz slider to copy.

### UI vs named templates

No `/dtt/` or `/xtu/` string in the exe. Candidates for “Intel dynamic
performance” are the named writes above (`intelpnp/…`,
`power/setCpuMaxStatusPercent`). Follow FPS / Adaptive TDP is still
time-varying PL1 (and maybe those same writes). How to confirm which
POST the slider actually sends:
[onexconsole-api.md — capture](onexconsole-api.md#how-to-capture-posts-windows).
Adapter-only slider pcap: only `/msr/setCpuPl/…/4`. Battery + adapter-swap
pcap: `setCpuPl4` + `setCpuPl` pairs, boot `/powerplan/setCpuBoostMode/2`
and `/tdp/init/3/45/46`. Still no `intelpnp` / `setCpuMaxStatusPercent`
on TDP or 65↔100 W swaps. Full table:
[compatlayerct-uritemplates.md](compatlayerct-uritemplates.md).

### Behind `type=4` (not an HTTP route)

CompatLayerCT type 4 talks to OEM Intel DTT / IPF. That stack, not RAPL
sysfs, does Power Share:

- DTT policy tables (OEM, not a public watt argument)
- Windows power plan / EPP (community notes: DTT “high perform” can force
  Windows “best power efficiency” — counter-intuitive, do not copy Linux
  `performance` governor blindly)
- Intel Graphics / IGCL GPU power policy (no X2 Mini clock slider)

Linux `intel-rapl` PL1/PL2/PL4 does **none** of that. PCODE still shares
the package, but the OEM DTT bias is missing.

### Linux knobs that *are* the split (dump, do not guess)

On this SKU (Arc B390 / Xe3 / Panther Lake class) the allocator lives
under the processor thermal device and GuC, not under `oxp-wmi`:

| Sysfs | Role |
|---|---|
| `intel-rapl:0:*` child zones (`core` / `uncore` / …) | PP0/PP1-style plane energy. Package PL does not set these. |
| `intel-rapl-mmio:0` | PCODE-visible package copy (we already write this). |
| `/sys/bus/pci/devices/0000:00:04.0/power_limits/` | DPTF RAPL legal range (min/max/step), not the share. |
| `…/workload_request/workload_type` | Hint: idle / bursty / sustained. Changes how firmware spends the package. |
| `…/workload_hint/` | Firmware’s own classification (Panther Lake adds power vs performance bit). |
| `processor_thermal_soc_slider` (`slider_balance` / `slider_offset`) | SoC-wide energy-perf hint (0=perf … 6=efficiency). Closest public Linux stand-in for DTT “dynamic performance”. |
| `/sys/class/platform-profile/*/profile` | Often wired to the same slider. |
| `intel_pstate` `no_turbo` + `energy_performance_preference` | Linux side of `/powerplan/setCpuBoostMode` + EPP. |
| Xe `gt*/freq0/power_profile` and `min_freq`/`max_freq` | GuC clock request. Our GT lerp is a **Linux-only** substitute for missing DTT, not an OneXConsole clone. |

`sudo kmod/scripts/diag-gpu.sh` dumps these. Compare a Windows capture of
the DTT / powerplan POSTs against that dump before writing any of them.

Live `ONEXPLAYER X2Mini` (Bazzite): package `long_term` `max_power_uw` is 25 W,
but `diag-tdp.sh --set 40` read back 40 W / 45 W PL1/PL2. That sysfs max is a
BIOS default, not a write ceiling. The daemon therefore clamps only to the
Steam slider range (3–45 W on X2 Mini). `energy_uj` is `0400` root-only, so the overlay
often shows 0 W.

`diag-tdp.sh` over SSH cannot see session `SteamOSManager1` (no user bus).
Check `TdpLimit1` / `RemoteInterfaces` from Game Mode or a desktop login, then
fully restart Steam.

## Install (X2 Mini / Intel G3E)

Needs `python3-dbus` and `python3-gobject` (GLib main loop). Root writes RAPL.
Fedora/Bazzite `python3-dbus` has no `dbus.service.property`; the daemon uses
`org.freedesktop.DBus.Properties` instead.

```bash
sudo kmod/scripts/install-tdp-rapl.sh
kmod/scripts/test-tdp-rapl.sh
```

`on-device-install.sh` / `ssh-handheld.sh … all` also run this and **no-op** on
AMD / unknown DMI unless `OXP_TDP_FORCE=1`.

A new `remotes.d` file is **not** picked up by an already-running user
`steamos-manager`. `RemoteInterfaces` staying `0` after install is that, not
a missing DMI match. 26.3 also deadlocks if `OxpRapl.Tdp` is already owned
when the user daemon starts. `install-tdp-rapl.sh` therefore runs
`reload-tdp-rapl.sh`: stop remote → restart user manager → start remote.

If the slider is still missing, as the **session user**:

```bash
ls -l /etc/steamos-manager/remotes.d/
systemctl --no-pager --full status oxp-tdp-rapl.service
journalctl -u oxp-tdp-rapl -n 40 --no-pager
busctl --system status com.steampowered.OxpRapl.Tdp

# if oxp-rapl.toml is present, attach it (pull this repo first so the
# daemon waits via /proc, not session busctl as root):
sudo kmod/scripts/reload-tdp-rapl.sh

# same sequence by hand:
sudo systemctl stop oxp-tdp-rapl.service
systemctl --user restart steamos-manager.service
sleep 4
sudo systemctl start oxp-tdp-rapl.service
sleep 2
busctl --system status com.steampowered.OxpRapl.Tdp
busctl --user introspect com.steampowered.SteamOSManager1 \
  /com/steampowered/SteamOSManager1 | grep -E "TdpLimit1|RemoteInterfaces"
```

`RemoteInterfaces` should list `com.steampowered.SteamOSManager1.TdpLimit1`.
Then fully restart Steam. Do not `sudo busctl --user` — that is a different
bus.

If `oxp-tdp-rapl` stays in `waiting for session steamos-manager` in the
journal, it is the old binary (root `busctl` against the session bus). Pull
and reinstall, or start once with `OXP_TDP_WAIT_MANAGER=0` **after** the
user manager is already up (do not leave that env on across reboot — 26.3
deadlock).

## Linux TDP policy (OneXConsole clone)

`oxp-tdp-rapl` now follows the live battery + 65/100 W POST sequence, not
an interpolated PL4.

| Step | OneXConsole | Linux remote |
|---|---|---|
| PL1 | slider W | same |
| PL2 | PL1+1 (`11/12` … `45/46`) | same (`PL2_HEADROOM_W=1`) |
| PL4 | `changePl4Func(0xE3)` **before** PL1/PL2: keys `1–5` → 160, `9` → 120, `8` → 65. Independent of the slider (11 W still 160 on 100 W) | same table. Read `0xE3` from oxp-wmi `power_supply_mode` (or `debugfs` `ec0/io`). `OXP_TDP_PL4` / `OXP_TDP_E3` override |
| Unmapped 16/18 | JS HTTP skips `setCpuPl4` | same **table** after firmware normalize `16→8` (65 W), `18→2` (160 W). Leaving BIOS 55 W clips GT |
| Key 8 clamp | slider 25/26 | writes clamp to 25 W. Steam `TdpLimitMax` stays 45 |
| Key 9 | PL4 120, slider still 3–45 | same |
| tau | not written | not written (restore ~28 s if a previous daemon left 2 s) |
| GT `max_freq` | none (DTT / type 4) | still a Linux-only RPe→RP0 lerp |

`diag-tdp.sh` prints the `power_supply_mode` line next to RAPL so PL4
class is visible. If `oxp_wmi` is not loaded, `e3=None` and PL4 falls
back to 160 W (100 W class) — load the module before judging 65 W.

## What this does not do

- GPU clock slider (`GpuPerformanceLevel1`) — X2 Mini Windows UI has no manual
  GPU clock; leave it hidden unless a later remote is added on a **second**
  bus name. Raising RAPL PL1 to 45 W does **not** by itself tell Xe GuC/PCODE
  to boost GT to the 2.3 GHz spec. Overlay stuck at ~1.5 GHz with package
  ~15 W is that gap, not a failed PL1 write.
- Fan (`FanControl1` is already on the bus on the live unit; wiring it to
  `oxp_wmi` pwm is a separate job).
- CPU vs GPU **share** (DTT Power Share, `/powerplan/*` after boot, SoC
  slider). Package PL1 is only the ceiling. See
  [CPU vs GPU split](#cpu-vs-gpu-split-not-pl1).
- `oxp-wmi` / EC `0xED`.

## If games stay ~15 W with GPU ≤ 1.5 GHz

Arc G3 Extreme (B390) spec boost is **2.3 GHz**. RAPL PL1 is a *ceiling*,
not a floor: if GT never asks for more clocks, package power stays around
15 W even when `constraint_0` reads 45 W.

During the same game, as root:

```bash
sudo kmod/scripts/diag-tdp.sh --measure 5
sudo kmod/scripts/diag-gpu.sh
```

| What you see | Meaning |
|---|---|
| `max_freq` (or `gt_max_freq_mhz`) ≈ 1500, `rp0` ≈ 2300 | Linux GT max request is capped; try `sudo kmod/scripts/diag-gpu.sh --raise-max` |
| `max_freq` already = `rp0`, `act_freq` still ~1500, `throttle/reason_pl4=1` | **PL4 too low** (BIOS 55 W). Windows on 100 W writes PL4 **160 at every slider** (`setCpuPl4/160` + `setCpuPl/11/12`). The remote now does the same from `0xE3`. |
| A **non-** `intel-rapl:0` powercap zone still at ~15 W | `processor_thermal_rapl` / DPTF, not our TdpLimit1 writer |
| Overlay 15 W but `diag-tdp.sh --measure` much higher | Overlay telemetry (often `energy_uj` 0400 or i915/xe), not package RAPL |

Windows OneXConsole writes MSR PL + Intel DTT/graphics policy (`intelTdpSetType=4`).
This remote only writes powercap sysfs. Overlay CPU watts are often 0 on this
unit because `energy_uj` is root-only.

Live X2 Mini (same game, PL1 already 45 W): BIOS PL4 55 W → `act_freq=1400`,
`reason_pl4=1`, package ~14.8 W. Writing `peak_power=160 W` cleared the clip
(`act_freq=2300`, ~32.6 W). OneXConsole keeps that 160 W (or 120 W on
65 W+battery) at every slider position. GT0 `max_freq` is still a Linux-only
RPe→RP0 lerp; `min_freq` is always RPe (Xe `max<=min` would pin a clock).
At 45 W under load, 2.3 GHz is boost; desktop/idle `act_freq` should fall
toward ~1.0 GHz. Reboot restores BIOS 55 W PL4 unless `oxp-tdp-rapl` is
running.
