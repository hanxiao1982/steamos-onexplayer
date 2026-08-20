#!/usr/bin/env bash
# Dump Intel RAPL + TdpLimit1 state. Optional --set / --measure for the load test.
# Does not need the oxp-tdp-rapl daemon. Run as root to write limits.
set -euo pipefail

SET_W=""
MEASURE=""
PKG=""

usage() {
  cat <<'EOF'
Usage:
  diag-tdp.sh                 Print RAPL zones, DMI, TdpLimit1, governors
  diag-tdp.sh --set W         Write package PL1/PL2 to W watts (root)
  diag-tdp.sh --measure SEC   Sample package energy_uj for SEC seconds

Same load, two --set values (15 then 40) is what proves RAPL *limits* work.
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

echo "=== DMI ==="
echo "sys_vendor=$(read_dmi sys_vendor)"
echo "product_name=$(read_dmi product_name)"
echo "board_name=$(read_dmi board_name)"

echo "=== modules ==="
lsmod | grep -E 'intel_rapl|rapl' || echo "(no intel_rapl* in lsmod)"

echo "=== RAPL ==="
shopt -s nullglob
for d in /sys/class/powercap/intel-rapl:*; do
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
  if [[ -z "$PKG" ]] && grep -qi '^package' "$d/name" 2>/dev/null; then
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

if [[ -n "$SET_W" ]]; then
  if [[ "${EUID}" -ne 0 ]]; then
    echo "--set needs root" >&2
    exit 1
  fi
  if [[ -z "$PKG" ]]; then
    echo "no package RAPL zone" >&2
    exit 3
  fi
  pl1=""
  pl2=""
  for c in "$PKG"/constraint_*_name; do
    [[ -e "$c" ]] || continue
    i="${c##*/}"; i="${i#constraint_}"; i="${i%_name}"
    n="$(cat "$c")"
    case "$n" in
      long_term) pl1="$PKG/constraint_${i}_power_limit_uw" ;;
      short_term) pl2="$PKG/constraint_${i}_power_limit_uw" ;;
    esac
  done
  if [[ -z "$pl1" && -e "$PKG/constraint_0_power_limit_uw" ]]; then
    pl1="$PKG/constraint_0_power_limit_uw"
  fi
  uw=$((SET_W * 1000000))
  echo "=== write PL1=${SET_W} W ==="
  printf '%s\n' "$uw" | tee "$pl1" >/dev/null
  if [[ -n "$pl2" ]]; then
    pl2w=$((SET_W + 5))
    printf '%s\n' $((pl2w * 1000000)) | tee "$pl2" >/dev/null || echo "PL2 write failed"
  fi
  sleep 0.2
  echo -n "readback PL1="; cat "$pl1"
  [[ -n "$pl2" ]] && { echo -n "readback PL2="; cat "$pl2"; }
fi

if [[ -n "$MEASURE" ]]; then
  if [[ -z "$PKG" ]]; then
    echo "no package RAPL zone" >&2
    exit 3
  fi
  e1="$(cat "$PKG/energy_uj")"
  sleep "$MEASURE"
  e2="$(cat "$PKG/energy_uj")"
  # integer watts: (e2-e1) / (sec * 1e6)
  awk -v e1="$e1" -v e2="$e2" -v s="$MEASURE" 'BEGIN {
    if (s <= 0) { print "bad interval"; exit 1 }
    printf "package ~ %.1f W over %ss\n", (e2-e1)/(s*1000000.0), s
  }'
fi
