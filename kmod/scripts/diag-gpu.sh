#!/usr/bin/env bash
# Dump Intel GT clocks / RAPL / thermal caps that keep package power ~15 W
# even when TdpLimit1 is 45 W. Run as root *during* the same game load.
#
# Overlay GPU MHz is a hint, not the SoC request. Compare act_freq vs
# max_freq vs rp0_freq (spec boost for Arc B390 / G3E is 2.3 GHz).
set -euo pipefail

RAISE=0
if [[ "${1:-}" == "--raise-max" ]]; then
  RAISE=1
  shift
fi
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
Usage:
  diag-gpu.sh              Dump GT freq, RAPL, platform_profile, thermal
  diag-gpu.sh --raise-max  Also set GT max_freq := rp0 (root, experimental)

Run during the game that shows ~15 W / 1.5 GHz, not at the SSH idle prompt.
EOF
  exit 0
fi

dump_file() {
  local f="$1"
  if [[ -r "$f" ]]; then
    printf '%s=%s\n' "$f" "$(tr -d '\n' <"$f" 2>/dev/null || echo '?')"
  fi
}

echo "=== drm devices ==="
ls -d /sys/class/drm/card* 2>/dev/null || echo "(no drm)"
lsmod | grep -E '^(xe|i915|intel_rapl|processor_thermal)' || true

echo
echo "=== xe GT freq (tile*/gt*/freq0) ==="
found_xe=0
shopt -s nullglob
for d in /sys/class/drm/card*/device/tile*/gt*/freq0 \
         /sys/class/drm/card*/device/gt*/freq0; do
  [[ -d "$d" ]] || continue
  found_xe=1
  echo "-- $d"
  for n in act_freq cur_freq min_freq max_freq rp0_freq rpa_freq rpe_freq rpn_freq power_profile; do
    [[ -e "$d/$n" ]] && printf '  %s=%s' "$n" "$(tr -d '\n' <"$d/$n")"
    echo
  done
  if [[ -d "$d/throttle" ]]; then
    echo "  throttle:"
    for t in "$d"/throttle/*; do
      [[ -f "$t" ]] || continue
      printf '    %s=%s\n' "${t##*/}" "$(tr -d '\n' <"$t")"
    done
  fi
  if [[ "$RAISE" -eq 1 ]]; then
    if [[ "${EUID}" -ne 0 ]]; then
      echo "  --raise-max needs root" >&2
    elif [[ -w "$d/max_freq" && -r "$d/rp0_freq" ]]; then
      rp0="$(tr -d '\n' <"$d/rp0_freq")"
      echo "  writing max_freq=$rp0 (was $(tr -d '\n' <"$d/max_freq"))"
      printf '%s\n' "$rp0" >"$d/max_freq" || echo "  max_freq write failed" >&2
      printf '  max_freq now=%s\n' "$(tr -d '\n' <"$d/max_freq")"
    fi
  fi
done
if [[ "$found_xe" -eq 0 ]]; then
  echo "(no xe freq0 sysfs)"
fi

echo
echo "=== i915 GT freq ==="
found_i915=0
for d in /sys/class/drm/card*/gt /sys/class/drm/card*/device; do
  [[ -e "$d/gt_act_freq_mhz" || -e "$d/gt_max_freq_mhz" ]] || continue
  found_i915=1
  echo "-- $d"
  for n in gt_act_freq_mhz gt_cur_freq_mhz gt_min_freq_mhz gt_max_freq_mhz \
           gt_boost_freq_mhz gt_RP0_freq_mhz gt_RP1_freq_mhz gt_RPn_freq_mhz; do
    [[ -e "$d/$n" ]] && printf '  %s=%s\n' "$n" "$(tr -d '\n' <"$d/$n")"
  done
  if [[ "$RAISE" -eq 1 && -w "$d/gt_max_freq_mhz" && -r "$d/gt_RP0_freq_mhz" ]]; then
    rp0="$(tr -d '\n' <"$d/gt_RP0_freq_mhz")"
    echo "  writing gt_max_freq_mhz=$rp0"
    printf '%s\n' "$rp0" >"$d/gt_max_freq_mhz" || true
    if [[ -w "$d/gt_boost_freq_mhz" ]]; then
      printf '%s\n' "$rp0" >"$d/gt_boost_freq_mhz" || true
    fi
  fi
done
if [[ "$found_i915" -eq 0 ]]; then
  echo "(no i915 gt_*_freq_mhz)"
fi
shopt -u nullglob

echo
echo "=== all powercap zones (not just intel-rapl) ==="
shopt -s nullglob
for d in /sys/class/powercap/*; do
  [[ -d "$d" ]] || continue
  [[ -e "$d/name" ]] || continue
  printf '%s  name=%s  enabled=%s\n' "$d" "$(tr -d '\n' <"$d/name" 2>/dev/null || echo '?')" \
    "$(tr -d '\n' <"$d/enabled" 2>/dev/null || echo '?')"
  for c in "$d"/constraint_*_name; do
    [[ -e "$c" ]] || continue
    i="${c##*/}"; i="${i#constraint_}"; i="${i%_name}"
    printf '  [%s] %s  limit=%s uW  max=%s\n' "$i" "$(tr -d '\n' <"$c")" \
      "$(tr -d '\n' <"$d/constraint_${i}_power_limit_uw" 2>/dev/null || echo '?')" \
      "$(tr -d '\n' <"$d/constraint_${i}_max_power_uw" 2>/dev/null || echo '?')"
  done
done
shopt -u nullglob

echo
echo "=== platform_profile / pstate ==="
dump_file /sys/firmware/acpi/platform_profile
dump_file /sys/firmware/acpi/platform_profile_choices
dump_file /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
dump_file /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference
dump_file /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq
dump_file /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq
dump_file /sys/devices/system/cpu/intel_pstate/no_turbo
dump_file /sys/devices/system/cpu/intel_pstate/status

echo
echo "=== thermal (first few) ==="
n=0
shopt -s nullglob
for z in /sys/class/thermal/thermal_zone*; do
  [[ -d "$z" ]] || continue
  n=$((n + 1))
  [[ "$n" -le 8 ]] || break
  printf '%s type=%s temp=%s\n' "$z" "$(tr -d '\n' <"$z/type" 2>/dev/null || echo '?')" \
    "$(tr -d '\n' <"$z/temp" 2>/dev/null || echo '?')"
done
shopt -u nullglob

echo
echo "=== TdpLimit1 system remote ==="
if busctl --system status com.steampowered.OxpRapl.Tdp >/dev/null 2>&1; then
  busctl --system introspect com.steampowered.OxpRapl.Tdp /com/steampowered/OxpRapl \
    com.steampowered.SteamOSManager1.TdpLimit1 2>/dev/null | grep TdpLimit || true
else
  echo "(OxpRapl.Tdp not on system bus)"
fi

echo
echo "Read: act/cur vs max vs rp0. If max<<rp0, software is capping GT."
echo "If max==rp0 but act stays ~1500, PCODE/DPTF/throttle is capping."
echo "If another powercap zone still has ~15 W, that zone (not intel-rapl:0) is the floor."
