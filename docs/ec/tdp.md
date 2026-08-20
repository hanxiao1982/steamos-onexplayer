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
frequencies move with them. See the earlier RAPL checklist: counters ticking,
limit readback sticking, then the 15 W / 40 W load pair.

## Install (X2 Mini / Intel G3E)

Needs `python3-dbus` and `python3-gobject` (GLib main loop). Root writes RAPL.

```bash
sudo kmod/scripts/install-tdp-rapl.sh
kmod/scripts/test-tdp-rapl.sh
```

`on-device-install.sh` / `ssh-handheld.sh … all` also run this and **no-op** on
AMD / unknown DMI unless `OXP_TDP_FORCE=1`.

The daemon waits until session `steamos-manager` is up before taking the
system bus name (a remote already present at user-daemon start can deadlock
steamos-manager 26.3). Fully restart Steam after `TdpLimit1` shows on the
session bus.

```bash
busctl --user introspect com.steampowered.SteamOSManager1 \
  /com/steampowered/SteamOSManager1 | grep -E "TdpLimit1|RemoteInterfaces"
```

`RemoteInterfaces` should list `com.steampowered.SteamOSManager1.TdpLimit1`.

## What this does not do

- GPU clock slider (`GpuPerformanceLevel1`) — X2 Mini Windows UI has no manual
  GPU clock; leave it hidden unless a later remote is added on a **second**
  bus name.
- Fan (`FanControl1` is already on the bus on the live unit; wiring it to
  `oxp_wmi` pwm is a separate job).
- PL4 / adapter-class tables (`0xE3`).
- `oxp-wmi` / EC `0xED`.
