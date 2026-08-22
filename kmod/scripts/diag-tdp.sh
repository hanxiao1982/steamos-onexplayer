#!/usr/bin/env bash
# Dump Intel RAPL + TdpLimit1 state. Optional --set / --measure for the load test.
# --set applies the same policy as oxp-tdp-rapl (MSR+MMIO PL1/PL2, adapter-class
# PL4 from 0xE3, GT range; firmware PL1 tau). Do not tee only intel-rapl:0 —
# PCODE/GPU follow MMIO.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SET_W=""
MEASURE=""
PKG=""

usage() {
  cat <<'EOF'
Usage:
  diag-tdp.sh                 Print RAPL zones, DMI, TdpLimit1, governors
  diag-tdp.sh --set W         Full TDP policy (PL1/PL2/PL4 + GT), then dump
  diag-tdp.sh --measure SEC   Sample package energy_uj for SEC seconds

TDP is a cap, not a target. 30 W at PL1=45 W is fine. OneXConsole does not
rewrite long_term tau; BIOS window is ~28 s. A 10 s --measure after dropping
45→25 W can still include the old period. Wait for window= or use --measure 30.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --set)
      SET_W="${2:?--set needs watts}"
      shift 2
      ;;
    --measure)
      MEASURE="${2:?--measure needs seconds}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

read_dmi() {
  local f="/sys/class/dmi/id/$1"
  if [[ -r "$f" ]]; then
    tr -d '\n' <"$f"
  else
    printf 'UNKNOWN'
  fi
}

dump_rapl() {
  PKG=""
  echo "=== RAPL ==="
  shopt -s nullglob
  local d c i
  for d in /sys/class/powercap/intel-rapl:* /sys/class/powercap/intel-rapl-mmio:*; do
    [[ -d "$d" ]] || continue
    echo -n "$d  name="
    cat "$d/name" 2>/dev/null || echo "?"
    echo -n "  enabled="
    cat "$d/enabled" 2>/dev/null || echo "?"
    for c in "$d"/constraint_*_name; do
      [[ -e "$c" ]] || continue
      i="${c##*/}"
      i="${i#constraint_}"
      i="${i%_name}"
      printf "  [%s] %s  limit=%s uW  max=%s  window=%s us\n" \
        "$i" "$(cat "$c")" \
        "$(cat "$d/constraint_${i}_power_limit_uw" 2>/dev/null || echo ?)" \
        "$(cat "$d/constraint_${i}_max_power_uw" 2>/dev/null || echo ?)" \
        "$(cat "$d/constraint_${i}_time_window_us" 2>/dev/null || echo ?)"
    done
    if [[ -z "$PKG" ]] && grep -qi '^package' "$d/name" 2>/dev/null && [[ "$d" == *intel-rapl:0 ]]; then
      PKG="$d"
    fi
  done
  shopt -u nullglob
  if [[ -z "$PKG" && -d /sys/class/powercap/intel-rapl:0 ]]; then
    PKG=/sys/class/powercap/intel-rapl:0
  fi
  echo "package zone: ${PKG:-none}"
  if [[ -n "$PKG" ]]; then
    echo -n "energy_uj perms: "
    ls -l "$PKG/energy_uj" 2>/dev/null || true
  fi
}

dump_gt() {
  echo "=== GT0 freq ==="
  shopt -s nullglob
  local d
  for d in /sys/class/drm/card*/device/tile*/gt0/freq0 /sys/class/drm/card*/device/gt0/freq0; do
    [[ -d "$d" ]] || continue
    case "$d" in
      */card*[!0-9]/*) continue ;;
    esac
    echo "-- $d"
    for n in act_freq cur_freq min_freq max_freq rp0_freq rpe_freq; do
      [[ -e "$d/$n" ]] && printf '  %s=%s\n' "$n" "$(tr -d '\n' <"$d/$n")"
    done
  done
  shopt -u nullglob
}

echo "=== DMI ==="
echo "sys_vendor=$(read_dmi sys_vendor)"
echo "product_name=$(read_dmi product_name)"
echo "board_name=$(read_dmi board_name)"

echo "=== 0xE3 power_supply_mode (PL4 class) ==="
shopt -s nullglob
e3_files=(/sys/bus/wmi/devices/*/power_supply_mode)
shopt -u nullglob
if ((${#e3_files[@]})); then
  for f in "${e3_files[@]}"; do
    echo -n "$f: "
    tr -d '\n' <"$f"; echo
  done
else
  echo "(oxp-wmi power_supply_mode not present)"
fi

echo "=== modules ==="
lsmod | grep -E 'intel_rapl|rapl|oxp_wmi' || echo "(no intel_rapl*/oxp_wmi in lsmod)"

if [[ -n "$SET_W" ]]; then
  if [[ "${EUID}" -ne 0 ]]; then
    echo "--set needs root" >&2
    exit 1
  fi
  echo "=== apply TDP policy ${SET_W} W (MSR+MMIO+GT) ==="
  if [[ -x /usr/local/sbin/oxp-tdp-rapl ]]; then
    /usr/local/sbin/oxp-tdp-rapl --set "$SET_W"
  else
    python3 "${ROOT}/userspace/tdp-rapl/oxp-tdp-rapl.py" --set "$SET_W"
  fi
fi

dump_rapl
dump_gt

echo "=== TdpLimit1 (session) ==="
if busctl --user status com.steampowered.SteamOSManager1 >/dev/null 2>&1; then
  busctl --user introspect com.steampowered.SteamOSManager1 \
    /com/steampowered/SteamOSManager1 | grep -E "TdpLimit1|GpuPerformanceLevel1|FanControl1|RemoteInterfaces" || true
else
  echo "session SteamOSManager1 not running (normal in a plain SSH login)"
fi

echo "=== TdpLimit1 (system remote) ==="
if busctl --system status com.steampowered.OxpRapl.Tdp >/dev/null 2>&1; then
  busctl --system introspect com.steampowered.OxpRapl.Tdp /com/steampowered/OxpRapl \
    com.steampowered.SteamOSManager1.TdpLimit1 || true
else
  echo "com.steampowered.OxpRapl.Tdp not on the system bus"
fi

echo "=== CPU policy ==="
cpu0=/sys/devices/system/cpu/cpu0/cpufreq
if [[ -d "$cpu0" ]]; then
  echo -n "governor="; cat "$cpu0/scaling_governor" 2>/dev/null || echo "?"
  echo -n "epp="; cat "$cpu0/energy_performance_preference" 2>/dev/null || echo "?"
  echo -n "min/max="; cat "$cpu0/scaling_min_freq" 2>/dev/null; echo -n /; cat "$cpu0/scaling_max_freq" 2>/dev/null
fi
echo -n "no_turbo="; cat /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null || echo "?"

echo "=== remotes.d ==="
for d in /usr/share/steamos-manager/remotes.d /etc/steamos-manager/remotes.d; do
  if [[ -d "$d" ]]; then
    echo "$d:"
    ls -l "$d"
  else
    echo "(missing $d)"
  fi
done

if [[ -n "$MEASURE" ]]; then
  if [[ -z "$PKG" ]]; then
    echo "no package RAPL zone" >&2
    exit 3
  fi
  if [[ -n "$SET_W" ]]; then
    win="?"
    if [[ -n "$PKG" && -r "$PKG/constraint_0_time_window_us" ]]; then
      win="$(tr -d '\n' <"$PKG/constraint_0_time_window_us")"
    fi
    echo "settling 5s for PCODE/GT (PL1 window=${win} us; energy_uj still averages that window)"
    sleep 5
  fi
  e1="$(cat "$PKG/energy_uj")"
  sleep "$MEASURE"
  e2="$(cat "$PKG/energy_uj")"
  awk -v e1="$e1" -v e2="$e2" -v s="$MEASURE" 'BEGIN {
    if (s <= 0) { print "bad interval"; exit 1 }
    printf "package ~ %.1f W over %ss (cap, not a target)\n", (e2-e1)/(s*1000000.0), s
  }'
fi
