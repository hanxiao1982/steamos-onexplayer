#!/usr/bin/env bash
# Make TdpLimit1 appear on the *session* bus.
#
# steamos-manager 26.3:
#   - new remotes.d files are ignored until the user daemon restarts
#   - if OxpRapl.Tdp is already owned during that restart, the user daemon
#     deadlocks before READY=1
#   - once READY, a later NameOwnerChanged *does* attach TdpLimit1
#
# So: stop remote → restart user steamos-manager → start remote.
set -euo pipefail

REMOTE_TOML="/etc/steamos-manager/remotes.d/oxp-rapl.toml"

if [[ "${EUID}" -ne 0 ]]; then
  echo "run as root (sudo $0)" >&2
  exit 1
fi

if [[ ! -f "$REMOTE_TOML" ]]; then
  echo "missing $REMOTE_TOML — run kmod/scripts/install-tdp-rapl.sh first" >&2
  exit 2
fi

nonroot_steamos_manager() {
  local pid uid
  for pid in $(pidof steamos-manager 2>/dev/null || true); do
    uid="$(awk '/^Uid:/{print $3}' "/proc/${pid}/status" 2>/dev/null || echo 0)"
    if [[ -n "$uid" && "$uid" != 0 ]]; then
      return 0
    fi
  done
  return 1
}

try_restart_uid() {
  local uid="$1" user dir
  user="$(getent passwd "$uid" | cut -d: -f1 || true)"
  dir="/run/user/${uid}"
  [[ -n "$user" ]] || return 1

  echo "restarting steamos-manager for ${user} (uid ${uid})"
  if systemctl --machine="${user}@" --user restart steamos-manager.service; then
    return 0
  fi
  if [[ -S "${dir}/bus" ]] && runuser -u "$user" -- env \
      XDG_RUNTIME_DIR="$dir" \
      DBUS_SESSION_BUS_ADDRESS="unix:path=${dir}/bus" \
      systemctl --user restart steamos-manager.service; then
    return 0
  fi
  return 1
}

echo "stopping oxp-tdp-rapl (must not hold the name during manager restart)"
systemctl stop oxp-tdp-rapl.service 2>/dev/null || true
# Also drop a leftover manual run.
pkill -x oxp-tdp-rapl 2>/dev/null || true
sleep 1
if busctl --system status com.steampowered.OxpRapl.Tdp >/dev/null 2>&1; then
  echo "OxpRapl.Tdp still on the system bus; wait and retry stop" >&2
  sleep 2
  systemctl stop oxp-tdp-rapl.service 2>/dev/null || true
fi

restarted=0
seen_uids=""
if command -v loginctl >/dev/null 2>&1; then
  while read -r _session uid _user _rest; do
    [[ "$uid" =~ ^[0-9]+$ ]] || continue
    [[ "$uid" == 0 ]] && continue
    case " $seen_uids " in
      *" $uid "*) continue ;;
    esac
    seen_uids+=" $uid"
    if try_restart_uid "$uid"; then
      restarted=1
    fi
  done < <(loginctl list-sessions --no-legend 2>/dev/null || true)
fi

for dir in /run/user/*; do
  [[ -d "$dir" ]] || continue
  uid="${dir##*/}"
  [[ "$uid" =~ ^[0-9]+$ ]] || continue
  [[ "$uid" == 0 ]] && continue
  case " $seen_uids " in
    *" $uid "*) continue ;;
  esac
  seen_uids+=" $uid"
  if try_restart_uid "$uid"; then
    restarted=1
  fi
done

if [[ "$restarted" -eq 0 ]]; then
  cat >&2 <<EOF
could not restart user steamos-manager from root.
In the Game Mode / desktop session (user, not sudo) run:

  systemctl --user restart steamos-manager.service
  sleep 4
  sudo systemctl start oxp-tdp-rapl.service
  busctl --user introspect com.steampowered.SteamOSManager1 \\
    /com/steampowered/SteamOSManager1 | grep -E "TdpLimit1|RemoteInterfaces"
EOF
  exit 3
fi

echo "waiting for non-root steamos-manager..."
ok=0
for _ in $(seq 1 40); do
  if nonroot_steamos_manager; then
    ok=1
    break
  fi
  sleep 0.25
done
if [[ "$ok" -ne 1 ]]; then
  echo "user steamos-manager did not come back; not starting oxp-tdp-rapl" >&2
  echo "check: systemctl --user --no-pager status steamos-manager" >&2
  exit 4
fi
# Let TdpManagerService start consuming its channel (26.3 deadlock window).
sleep 3

echo "starting oxp-tdp-rapl"
systemctl start oxp-tdp-rapl.service

name_ok=0
for _ in $(seq 1 20); do
  if busctl --system status com.steampowered.OxpRapl.Tdp >/dev/null 2>&1; then
    name_ok=1
    break
  fi
  sleep 0.5
done

echo
systemctl --no-pager --full status oxp-tdp-rapl.service || true
echo
if [[ "$name_ok" -eq 1 ]]; then
  echo "system remote: com.steampowered.OxpRapl.Tdp is on the system bus"
  busctl --system introspect com.steampowered.OxpRapl.Tdp /com/steampowered/OxpRapl \
    com.steampowered.SteamOSManager1.TdpLimit1 || true
else
  echo "OxpRapl.Tdp is NOT on the system bus. journal:" >&2
  journalctl -u oxp-tdp-rapl -n 40 --no-pager >&2 || true
  exit 5
fi

echo
echo "As the session user (not sudo) run:"
echo "  busctl --user introspect com.steampowered.SteamOSManager1 /com/steampowered/SteamOSManager1 | grep -E 'TdpLimit1|RemoteInterfaces'"
echo "RemoteInterfaces should list TdpLimit1. Then fully restart Steam."
