#!/usr/bin/env bash
# Check that the RAPL TdpLimit1 remote is installed and talking.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0

echo "=== python self-test ==="
python3 "${ROOT}/userspace/tdp-rapl/oxp-tdp-rapl.py" --self-test

if [[ -x /usr/local/sbin/oxp-tdp-rapl ]]; then
  echo "=== installed binary --dump ==="
  /usr/local/sbin/oxp-tdp-rapl --dump || true
elif [[ "${EUID}" -eq 0 ]]; then
  echo "oxp-tdp-rapl is not installed; run kmod/scripts/install-tdp-rapl.sh" >&2
fi

echo "=== systemd ==="
if systemctl cat oxp-tdp-rapl.service >/dev/null 2>&1; then
  systemctl is-enabled oxp-tdp-rapl.service || true
  systemctl is-active oxp-tdp-rapl.service || true
else
  echo "(unit not installed)"
fi

echo "=== system bus ==="
if busctl --system status com.steampowered.OxpRapl.Tdp >/dev/null 2>&1; then
  busctl --system introspect com.steampowered.OxpRapl.Tdp /com/steampowered/OxpRapl \
    com.steampowered.SteamOSManager1.TdpLimit1
else
  echo "OxpRapl.Tdp not on the system bus (service waiting, failed, or not installed)"
  echo "  journalctl -u oxp-tdp-rapl -n 40 --no-pager"
fi

echo "=== session TdpLimit1 ==="
if busctl --user status com.steampowered.SteamOSManager1 >/dev/null 2>&1; then
  if busctl --user introspect com.steampowered.SteamOSManager1 \
      /com/steampowered/SteamOSManager1 | grep -q TdpLimit1; then
    echo "TdpLimit1 is on the session bus"
    busctl --user introspect com.steampowered.SteamOSManager1 \
      /com/steampowered/SteamOSManager1 | grep -E "TdpLimit|RemoteInterfaces"
  else
    echo "SteamOSManager1 is up but TdpLimit1 is still missing" >&2
    echo "If RemoteInterfaces is 0: sudo ${ROOT}/kmod/scripts/reload-tdp-rapl.sh" >&2
    echo "Then: busctl --system status com.steampowered.OxpRapl.Tdp" >&2
    fail=1
  fi
else
  echo "session SteamOSManager1 not running in this login"
fi

if [[ -f /etc/steamos-manager/remotes.d/oxp-rapl.toml ]]; then
  echo "remotes.d/oxp-rapl.toml present"
else
  echo "missing /etc/steamos-manager/remotes.d/oxp-rapl.toml (install-tdp-rapl.sh not run)"
  if [[ "${OXP_TDP_STRICT:-0}" == 1 ]]; then
    fail=1
  fi
fi

exit "$fail"
