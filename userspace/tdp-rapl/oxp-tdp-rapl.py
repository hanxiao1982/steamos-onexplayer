#!/usr/bin/env python3
"""steamos-manager TdpLimit1 remote that writes Intel RAPL PL1/PL2.

Steam hides the TDP slider until TdpLimit1 exists on the session bus.
This process owns a system-bus name; remotes.d tells steamos-manager to
relay TdpLimit1 here. Watts go to powercap intel-rapl, not oxp-wmi / EC.

Not a production TDP controller. RAPL enforcement is not proven by this
file existing — use kmod/scripts/diag-tdp.sh under load.
"""
from __future__ import annotations

import argparse
import os
import sys
import time
from pathlib import Path

POWERCAP = Path("/sys/class/powercap")
DMI_PRODUCT = Path("/sys/class/dmi/id/product_name")
DMI_SYS_VENDOR = Path("/sys/class/dmi/id/sys_vendor")

# OneXConsole Intel G3E slider bounds (watts). X2 Mini is live-documented.
# min is a floor for the Steam slider, not a firmware measurement.
PRODUCT_WATTS = {
    "ONEXPLAYER X2Mini": (8, 45, 25),
    "ONEXPLAYER X2": (8, 40, 25),
    "ONEXPLAYER X2 EVA": (8, 40, 25),
    "ONEXPLAYER 3": (8, 40, 25),
    "ONEXPLAYER Apex Air": (8, 46, 25),
    "ONEXPLAYER Apex i": (8, 46, 25),
}

BUS_NAME = "com.steampowered.OxpRapl.Tdp"
OBJ_PATH = "/com/steampowered/OxpRapl"
IFACE = "com.steampowered.SteamOSManager1.TdpLimit1"
PROPS_IFACE = "org.freedesktop.DBus.Properties"
PL2_HEADROOM_W = 5

# dbus-python on Bazzite/Fedora has no dbus.service.property (added in 1.3).
# Advertise TdpLimit1 through Introspect + org.freedesktop.DBus.Properties.
INTROSPECT_XML = f"""<!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object Introspection 1.0//EN"
"http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd">
<node>
  <interface name="{IFACE}">
    <property name="TdpLimit" type="u" access="readwrite"/>
    <property name="TdpLimitMin" type="u" access="read"/>
    <property name="TdpLimitMax" type="u" access="read"/>
  </interface>
  <interface name="{PROPS_IFACE}">
    <method name="Get">
      <arg type="s" name="interface_name" direction="in"/>
      <arg type="s" name="property_name" direction="in"/>
      <arg type="v" name="value" direction="out"/>
    </method>
    <method name="Set">
      <arg type="s" name="interface_name" direction="in"/>
      <arg type="s" name="property_name" direction="in"/>
      <arg type="v" name="value" direction="in"/>
    </method>
    <method name="GetAll">
      <arg type="s" name="interface_name" direction="in"/>
      <arg type="a{{sv}}" name="properties" direction="out"/>
    </method>
    <signal name="PropertiesChanged">
      <arg type="s" name="interface_name"/>
      <arg type="a{{sv}}" name="changed_properties"/>
      <arg type="as" name="invalidated_properties"/>
    </signal>
  </interface>
  <interface name="org.freedesktop.DBus.Introspectable">
    <method name="Introspect">
      <arg type="s" name="xml_data" direction="out"/>
    </method>
  </interface>
  <interface name="org.freedesktop.DBus.Peer">
    <method name="Ping"/>
    <method name="GetMachineId">
      <arg type="s" name="machine_uuid" direction="out"/>
    </method>
  </interface>
</node>
"""


def _read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace").strip()


def dmi_product() -> str:
    try:
        return _read_text(DMI_PRODUCT)
    except OSError:
        return ""


def dmi_sys_vendor() -> str:
    try:
        return _read_text(DMI_SYS_VENDOR)
    except OSError:
        return ""


def watts_for_product(product: str) -> tuple[int, int, int] | None:
    return PRODUCT_WATTS.get(product)


def _zone_name(zone: Path) -> str:
    try:
        return _read_text(zone / "name")
    except OSError:
        return ""


def iter_rapl_zones(root: Path = POWERCAP) -> list[Path]:
    if not root.is_dir():
        return []
    zones = []
    for p in sorted(root.iterdir()):
        if p.name.startswith("intel-rapl:") and (p / "name").is_file():
            zones.append(p)
    return zones


def package_zone(root: Path = POWERCAP) -> Path | None:
    zones = iter_rapl_zones(root)
    if not zones:
        return None
    for z in zones:
        name = _zone_name(z).lower()
        if name.startswith("package"):
            return z
    # Kernel usually numbers the package as intel-rapl:0
    for z in zones:
        if z.name == "intel-rapl:0":
            return z
    return zones[0]


def constraint_indices(zone: Path) -> list[int]:
    found = []
    for p in zone.glob("constraint_*_name"):
        try:
            n = int(p.name.split("_")[1])
        except (IndexError, ValueError):
            continue
        found.append(n)
    return sorted(set(found))


def read_constraint(zone: Path, idx: int) -> dict:
    def maybe(suffix: str) -> str:
        f = zone / f"constraint_{idx}_{suffix}"
        try:
            return _read_text(f)
        except OSError:
            return ""

    name = maybe("name") or f"constraint_{idx}"
    limit = maybe("power_limit_uw")
    maximum = maybe("max_power_uw")
    window = maybe("time_window_us")
    return {
        "index": idx,
        "name": name,
        "limit_uw": int(limit) if limit.isdigit() else None,
        "max_uw": int(maximum) if maximum.isdigit() else None,
        "window_us": int(window) if window.isdigit() else None,
    }


def pick_pl1_pl2(zone: Path) -> tuple[dict, dict | None]:
    cons = [read_constraint(zone, i) for i in constraint_indices(zone)]
    if not cons:
        raise RuntimeError(f"no RAPL constraints under {zone}")
    by_name = {c["name"]: c for c in cons}
    pl1 = by_name.get("long_term") or cons[0]
    pl2 = by_name.get("short_term")
    if pl2 is pl1:
        pl2 = None
    return pl1, pl2


def uw_to_w(uw: int | None) -> int | None:
    if uw is None:
        return None
    return int(round(uw / 1_000_000))


def w_to_uw(watts: int) -> int:
    return int(watts) * 1_000_000


def clamp_w(watts: int, lo: int, hi: int) -> int:
    return max(lo, min(hi, int(watts)))


def zone_enabled(zone: Path) -> bool | None:
    f = zone / "enabled"
    if not f.is_file():
        return None
    try:
        return _read_text(f) not in ("0", "")
    except OSError:
        return None


def set_zone_enabled(zone: Path, on: bool) -> None:
    f = zone / "enabled"
    if not f.is_file():
        return
    f.write_text("1\n" if on else "0\n", encoding="utf-8")


def write_limit_uw(zone: Path, idx: int, uw: int) -> None:
    path = zone / f"constraint_{idx}_power_limit_uw"
    path.write_text(f"{uw}\n", encoding="utf-8")
    time.sleep(0.05)
    got = _read_text(path)
    if not got.lstrip("-").isdigit():
        return
    got_i = int(got)
    # RAPL units are often 1/8 W; treat >2 W drift as "did not stick".
    if abs(got_i - uw) > 2_000_000:
        raise RuntimeError(
            f"{path} wrote {uw} but reads back {got} (another daemon may be resetting RAPL)"
        )


def apply_watts(zone: Path, watts: int, max_w: int, pl2_headroom: int = PL2_HEADROOM_W) -> int:
    """Set package PL1 to watts and PL2 a little above. Returns the PL1 watts written."""
    if zone_enabled(zone) is False:
        set_zone_enabled(zone, True)
    pl1, pl2 = pick_pl1_pl2(zone)
    pl1_max_w = uw_to_w(pl1.get("max_uw"))
    cap = max_w
    if pl1_max_w and pl1_max_w > 0:
        cap = min(cap, pl1_max_w)
    if cap < 1:
        cap = max_w
    watts = clamp_w(watts, 1, cap)
    write_limit_uw(zone, pl1["index"], w_to_uw(watts))
    if pl2 is not None:
        pl2_max_w = uw_to_w(pl2.get("max_uw")) or cap
        if pl2_max_w <= 0:
            pl2_max_w = cap
        pl2_w = min(pl2_max_w, watts + max(0, pl2_headroom))
        if pl2_w < watts:
            pl2_w = watts
        try:
            write_limit_uw(zone, pl2["index"], w_to_uw(pl2_w))
        except OSError as e:
            print(f"PL2 write skipped: {e}", file=sys.stderr)
    return watts


def current_pl1_watts(zone: Path) -> int | None:
    pl1, _ = pick_pl1_pl2(zone)
    return uw_to_w(pl1.get("limit_uw"))


def dump_rapl(root: Path = POWERCAP) -> str:
    lines = []
    zones = iter_rapl_zones(root)
    if not zones:
        return f"no intel-rapl zones under {root}\n"
    for z in zones:
        enabled = zone_enabled(z)
        lines.append(f"{z}  name={_zone_name(z)!r}  enabled={enabled}")
        for i in constraint_indices(z):
            c = read_constraint(z, i)
            lines.append(
                f"  [{c['index']}] {c['name']}: limit={c['limit_uw']} uW "
                f"max={c['max_uw']} window={c['window_us']} us"
            )
    pkg = package_zone(root)
    if pkg is not None:
        lines.append(f"package zone: {pkg}")
    return "\n".join(lines) + "\n"


def energy_watts(zone: Path, seconds: float = 5.0) -> float:
    f = zone / "energy_uj"
    e1 = int(_read_text(f))
    time.sleep(seconds)
    e2 = int(_read_text(f))
    return (e2 - e1) / (seconds * 1_000_000.0)


def user_steamos_manager_running() -> bool:
    """True when a non-root steamos-manager exists.

    The root helper also named steamos-manager starts at boot. Claiming the
    TdpLimit1 remote before the *user* daemon is up deadlocks 26.3. Root
    usually cannot query the session bus (dbus-broker uid policy), so detect
    the user process via /proc instead.
    """
    proc = Path("/proc")
    try:
        ents = list(proc.iterdir())
    except OSError:
        return False
    for p in ents:
        if not p.name.isdigit():
            continue
        try:
            comm = (p / "comm").read_text(encoding="utf-8", errors="replace").strip()
        except OSError:
            continue
        # TASK_COMM_LEN is 16 bytes including NUL; "steamos-manager" is 15 chars.
        if comm != "steamos-manager":
            continue
        try:
            for line in (p / "status").read_text(encoding="utf-8", errors="replace").splitlines():
                if line.startswith("Uid:"):
                    parts = line.split()
                    euid = int(parts[2]) if len(parts) >= 3 else 0
                    if euid != 0:
                        return True
                    break
        except (OSError, ValueError, IndexError):
            continue
    return False


def wait_for_steamos_manager(timeout_s: float | None, extra_s: float) -> bool:
    """Avoid claiming TdpLimit1 before the user daemon is up (upstream deadlock)."""
    deadline = None if timeout_s is None else time.time() + timeout_s
    last_log = 0.0
    while deadline is None or time.time() < deadline:
        if user_steamos_manager_running():
            if extra_s > 0:
                time.sleep(extra_s)
            return True
        now = time.time()
        if now - last_log >= 15:
            print("still waiting for non-root steamos-manager...", flush=True)
            last_log = now
        time.sleep(0.5)
    return False


def run_self_test() -> int:
    import tempfile

    root = Path(tempfile.mkdtemp(prefix="oxp-rapl-"))
    z = root / "intel-rapl:0"
    z.mkdir()
    (z / "name").write_text("package-0\n")
    (z / "enabled").write_text("1\n")
    (z / "constraint_0_name").write_text("long_term\n")
    (z / "constraint_0_power_limit_uw").write_text("15000000\n")
    (z / "constraint_0_max_power_uw").write_text("45000000\n")
    (z / "constraint_1_name").write_text("short_term\n")
    (z / "constraint_1_power_limit_uw").write_text("20000000\n")
    (z / "constraint_1_max_power_uw").write_text("46000000\n")
    pkg = package_zone(root)
    assert pkg == z, pkg
    pl1, pl2 = pick_pl1_pl2(z)
    assert pl1["name"] == "long_term" and pl1["index"] == 0
    assert pl2 is not None and pl2["name"] == "short_term"
    wrote = apply_watts(z, 25, 45)
    assert wrote == 25
    assert _read_text(z / "constraint_0_power_limit_uw") == "25000000"
    assert _read_text(z / "constraint_1_power_limit_uw") == "30000000"
    for name in ("TdpLimit", "TdpLimitMin", "TdpLimitMax", PROPS_IFACE, IFACE):
        assert name in INTROSPECT_XML, name
    print("self-test ok")
    return 0


def serve_dbus(zone: Path, min_w: int, max_w: int, current_w: int) -> None:
    import dbus
    import dbus.exceptions
    import dbus.mainloop.glib
    import dbus.service
    from gi.repository import GLib

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()

    def err(name: str, msg: str) -> dbus.exceptions.DBusException:
        return dbus.exceptions.DBusException(msg, name=name)

    class TdpLimit1(dbus.service.Object):
        def __init__(self):
            super().__init__(bus, OBJ_PATH)
            self.min_w = min_w
            self.max_w = max_w
            self.cur_w = current_w

        def _set_tdp(self, watts: int) -> None:
            watts = clamp_w(int(watts), self.min_w, self.max_w)
            self.cur_w = apply_watts(zone, watts, self.max_w)
            print(f"TDP -> {self.cur_w} W (PL1)", flush=True)

        def _props(self) -> dict:
            return {
                "TdpLimit": dbus.UInt32(self.cur_w),
                "TdpLimitMin": dbus.UInt32(self.min_w),
                "TdpLimitMax": dbus.UInt32(self.max_w),
            }

        def _check_iface(self, interface: str) -> None:
            if interface not in ("", IFACE):
                raise err(
                    "org.freedesktop.DBus.Error.UnknownInterface",
                    f"unknown interface {interface}",
                )

        @dbus.service.method(PROPS_IFACE, in_signature="ss", out_signature="v")
        def Get(self, interface, prop):
            self._check_iface(str(interface))
            props = self._props()
            key = str(prop)
            if key not in props:
                raise err(
                    "org.freedesktop.DBus.Error.UnknownProperty",
                    f"unknown property {key}",
                )
            return props[key]

        @dbus.service.method(PROPS_IFACE, in_signature="s", out_signature="a{sv}")
        def GetAll(self, interface):
            self._check_iface(str(interface))
            return self._props()

        @dbus.service.method(PROPS_IFACE, in_signature="ssv", out_signature="")
        def Set(self, interface, prop, value):
            self._check_iface(str(interface))
            key = str(prop)
            if key != "TdpLimit":
                raise err(
                    "org.freedesktop.DBus.Error.PropertyReadOnly",
                    f"property {key} is not writable",
                )
            self._set_tdp(int(value))
            self.PropertiesChanged(IFACE, {"TdpLimit": dbus.UInt32(self.cur_w)}, [])

        @dbus.service.signal(PROPS_IFACE, signature="sa{sv}as")
        def PropertiesChanged(self, interface, changed, invalidated):
            pass

        @dbus.service.method(
            "org.freedesktop.DBus.Introspectable",
            in_signature="",
            out_signature="s",
        )
        def Introspect(self):
            return INTROSPECT_XML

        @dbus.service.method("org.freedesktop.DBus.Peer", in_signature="", out_signature="")
        def Ping(self):
            return

        @dbus.service.method("org.freedesktop.DBus.Peer", in_signature="", out_signature="s")
        def GetMachineId(self):
            mid = Path("/etc/machine-id")
            try:
                return mid.read_text(encoding="utf-8").strip()
            except OSError:
                return "00000000000000000000000000000000"

    TdpLimit1()
    # 1 = PRIMARY_OWNER, 4 = ALREADY_OWNER
    reply = int(bus.request_name(BUS_NAME))
    if reply not in (1, 4):
        raise RuntimeError(f"could not own {BUS_NAME} (request_name={reply})")
    print(
        f"TdpLimit1 on {BUS_NAME} {OBJ_PATH} "
        f"min={min_w} max={max_w} current={current_w}",
        flush=True,
    )
    GLib.MainLoop().run()


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    p.add_argument("--dump", action="store_true", help="print RAPL sysfs and exit")
    p.add_argument("--set", type=int, metavar="W", help="write package PL1/PL2 (watts) and exit")
    p.add_argument("--measure", type=float, metavar="SEC", help="with --dump, also sample energy_uj")
    p.add_argument("--self-test", action="store_true", help="fake sysfs unit check")
    p.add_argument(
        "--no-wait-manager",
        action="store_true",
        help="do not wait for steamos-manager before taking the bus name",
    )
    args = p.parse_args(argv)

    if args.self_test:
        return run_self_test()

    product = dmi_product()
    vendor = dmi_sys_vendor()
    force = os.environ.get("OXP_TDP_FORCE", "0") == "1"
    bounds = watts_for_product(product)
    if bounds is None and not force:
        print(
            f"refusing: product {product!r} is not an Intel G3E row "
            f"(vendor={vendor!r}). Set OXP_TDP_FORCE=1 to override.",
            file=sys.stderr,
        )
        return 2
    if bounds is None:
        bounds = (8, 45, 25)
        print(f"OXP_TDP_FORCE: using generic Intel bounds {bounds} for {product!r}", flush=True)

    min_w, max_w, default_w = bounds
    print(dump_rapl(), end="")
    if args.dump and not args.set:
        zone = package_zone()
        if args.measure and zone is not None:
            try:
                w = energy_watts(zone, args.measure)
                print(f"package ~ {w:.1f} W over {args.measure}s")
            except OSError as e:
                print(f"energy_uj: {e}", file=sys.stderr)
        return 0

    zone = package_zone()
    if zone is None:
        print("no intel-rapl package zone", file=sys.stderr)
        return 3

    if args.set is not None:
        w = clamp_w(args.set, min_w, max_w)
        wrote = apply_watts(zone, w, max_w)
        print(f"wrote PL1={wrote} W")
        print(dump_rapl(), end="")
        return 0

    cur = current_pl1_watts(zone)
    if cur is None or cur < min_w or cur > max_w:
        current_w = default_w
    else:
        current_w = cur

    wait = not args.no_wait_manager and os.environ.get("OXP_TDP_WAIT_MANAGER", "1") != "0"
    # 0 = wait forever so a boot-time start cannot own the name before login.
    timeout_env = os.environ.get("OXP_TDP_WAIT_TIMEOUT", "0")
    try:
        t = float(timeout_env)
        timeout: float | None = None if t <= 0 else t
    except ValueError:
        timeout = None
    extra = float(os.environ.get("OXP_TDP_WAIT_EXTRA", "3"))
    if wait:
        print("waiting for non-root steamos-manager (/proc) before claiming TdpLimit1...", flush=True)
        if not wait_for_steamos_manager(timeout, extra):
            print(
                f"steamos-manager not seen after {timeout}s; claiming the name anyway",
                flush=True,
            )

    try:
        serve_dbus(zone, min_w, max_w, current_w)
    except KeyboardInterrupt:
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
