#!/usr/bin/env bash
# Install the Intel RAPL TdpLimit1 remote for steamos-manager.
# No-op on AMD / unknown DMI unless OXP_TDP_FORCE=1.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="${ROOT}/userspace/tdp-rapl"
BIN_DEST="${OXP_TDP_BIN:-/usr/local/sbin/oxp-tdp-rapl}"
UNIT="/etc/systemd/system/oxp-tdp-rapl.service"
DBUS_CONF="/etc/dbus-1/system.d/com.steampowered.OxpRapl.Tdp.conf"
REMOTE_DIR="/etc/steamos-manager/remotes.d"
REMOTE_TOML="${REMOTE_DIR}/oxp-rapl.toml"
PRODUCT="$(tr -d '\n' < /sys/class/dmi/id/product_name 2>/dev/null || true)"

if [[ "${EUID}" -ne 0 ]]; then
  echo "run as root" >&2
  exit 1
fi

if [[ "${OXP_TDP_FORCE:-0}" != 1 ]]; then
  case "$PRODUCT" in
    "ONEXPLAYER X2Mini"|"ONEXPLAYER X2"|"ONEXPLAYER X2 EVA"|"ONEXPLAYER 3"|"ONEXPLAYER Apex Air"|"ONEXPLAYER Apex i")
      ;;
    *)
      echo "skip TdpLimit1 RAPL: product ${PRODUCT:-unknown} (set OXP_TDP_FORCE=1 to install anyway)"
      exit 0
      ;;
  esac
fi

if [[ ! -d /sys/class/powercap/intel-rapl:0 ]]; then
  echo "no /sys/class/powercap/intel-rapl:0; load intel_rapl_common / intel_rapl_msr first" >&2
  exit 3
fi

if ! python3 -c 'import dbus, dbus.service, dbus.mainloop.glib; from gi.repository import GLib' 2>/dev/null; then
  cat >&2 <<EOF
python3 dbus + GLib bindings missing.
On Bazzite (layer, then reboot):  rpm-ostree install python3-dbus python3-gobject
On CachyOS:                       pacman -S --needed python-dbus python-gobject
EOF
  exit 4
fi

install -d "$(dirname "$BIN_DEST")"
install -m 0755 "${SRC}/oxp-tdp-rapl.py" "$BIN_DEST"

install -d /etc/systemd/system
# Rewrite ExecStart to the installed path (BIN_DEST may be under /var).
sed "s|^ExecStart=.*|ExecStart=${BIN_DEST}|" "${SRC}/oxp-tdp-rapl.service" >"$UNIT"

install -d /etc/dbus-1/system.d
install -m 0644 "${SRC}/com.steampowered.OxpRapl.Tdp.conf" "$DBUS_CONF"

install -d "$REMOTE_DIR"
install -m 0644 "${SRC}/oxp-rapl.toml" "$REMOTE_TOML"

if systemctl reload dbus 2>/dev/null; then
  :
elif systemctl reload dbus-broker 2>/dev/null; then
  :
else
  echo "reload dbus yourself if the name cannot be owned" >&2
fi

systemctl daemon-reload
systemctl enable oxp-tdp-rapl.service
# Do not enable --now: a new remotes.d file is ignored until the *user*
# steamos-manager restarts, and owning the name during that restart deadlocks
# 26.3. reload-tdp-rapl.sh does: stop remote → restart manager → start remote.
if [[ "${OXP_TDP_SKIP_RELOAD:-0}" == 1 ]]; then
  echo "installed files only (OXP_TDP_SKIP_RELOAD=1). Run:"
  echo "  sudo ${ROOT}/kmod/scripts/reload-tdp-rapl.sh"
else
  "${ROOT}/kmod/scripts/reload-tdp-rapl.sh" || {
    echo "files are installed; finish with: sudo ${ROOT}/kmod/scripts/reload-tdp-rapl.sh" >&2
    exit 0
  }
fi

echo "installed TdpLimit1 RAPL remote:"
echo "  $BIN_DEST"
echo "  $UNIT"
echo "  $REMOTE_TOML"
echo "If RemoteInterfaces is still empty, run: sudo ${ROOT}/kmod/scripts/reload-tdp-rapl.sh"
echo "Then fully restart Steam."
