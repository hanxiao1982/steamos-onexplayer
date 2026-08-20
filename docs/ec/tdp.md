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
      → com.steampowered.OxpRapl.Tdp → intel-rapl PL1 (+ PL2 = PL1+5 W)
```

Slider range for X2 Mini follows OneXConsole: **8–45 W**, default **25 W**
(the daemon reports the current PL1 if it already sits in range).

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

Live `ONEXPLAYER X2Mini` (Bazzite): package `long_term` `max_power_uw` is 25 W,
but `diag-tdp.sh --set 40` read back 40 W / 45 W PL1/PL2. That sysfs max is a
BIOS default, not a write ceiling. The daemon therefore clamps only to the
Steam slider range (8–45 W). `energy_uj` is `0400` root-only, so the overlay
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

## What this does not do

- GPU clock slider (`GpuPerformanceLevel1`) — X2 Mini Windows UI has no manual
  GPU clock; leave it hidden unless a later remote is added on a **second**
  bus name. Raising RAPL PL1 to 45 W does **not** by itself tell Xe GuC/PCODE
  to boost GT to the 2.3 GHz spec. Overlay stuck at ~1.5 GHz with package
  ~15 W is that gap, not a failed PL1 write.
- Fan (`FanControl1` is already on the bus on the live unit; wiring it to
  `oxp_wmi` pwm is a separate job).
- PL4 / adapter-class tables (`0xE3`). PL4 is interpolated 70–160 W from the
  TDP slider, not read from EC. 65 W adapter (OneXConsole key 8) is not applied.
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
| `max_freq` already = `rp0`, `act_freq` still ~1500, `throttle/reason_pl4=1` | **PL4 too low** (BIOS 55 W). At **45 W** TDP, PL4 should be ~160 W. Do not leave PL4 at 160 W for every slider position. |
| A **non-** `intel-rapl:0` powercap zone still at ~15 W | `processor_thermal_rapl` / DPTF, not our TdpLimit1 writer |
| Overlay 15 W but `diag-tdp.sh --measure` much higher | Overlay telemetry (often `energy_uj` 0400 or i915/xe), not package RAPL |

Windows OneXConsole writes MSR PL + Intel DTT/graphics policy (`intelTdpSetType=4`).
This remote only writes powercap sysfs. Overlay CPU watts are often 0 on this
unit because `energy_uj` is root-only.

Live X2 Mini (same game, PL1 already 45 W): BIOS PL4 55 W → `act_freq=1400`,
`reason_pl4=1`, package ~14.8 W. Writing `peak_power=160 W` cleared the clip
(`act_freq=2300`, ~32.6 W) but that is only the **top** of the slider — a
constant 160 W lets GuC sit at RP0. The remote now interpolates PL4 70–160 W
and GT0 `max_freq` RPe→RP0 with TDP, and **always** sets `min_freq=RPe`
(Xe `max<=min` would pin a single clock). At 45 W under load, 2.3 GHz is
boost; desktop/idle `act_freq` should fall toward ~1.0 GHz. Reboot restores
BIOS 55 W PL4 unless `oxp-tdp-rapl` is installed.
