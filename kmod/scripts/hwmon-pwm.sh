#!/usr/bin/env bash
# Manual fan smoke test. X2 Mini uses hwmon name oxp_wmi, not oxpec.
# Empty HWMON + echo > "$HWMON/pwm1" writes /pwm1 on the ostree root (EIO: read-only).
set -euo pipefail

PERCENT=40
HOLD=5

usage() {
  cat <<'EOF'
Usage:
  hwmon-pwm.sh [percent]        Set manual PWM, wait, restore auto
  hwmon-pwm.sh --hold SEC 40    Keep manual for SEC seconds (default 5)
  hwmon-pwm.sh --find           Print the hwmon directory and exit
  hwmon-pwm.sh --read           Print fan/pwm/temp and exit

Looks for name=oxp_wmi first (X2 Mini / Intel G3E), then name=oxpec (AMD).
On X2 Mini a write that does not stick (pwm1_enable stays 2) means WriteECReg
packing is still wrong; the script treats that as failure.
EOF
}

find_hwmon() {
  local want name
  for want in oxp_wmi oxpec; do
    for hw in /sys/class/hwmon/hwmon*; do
      [[ -e "$hw/name" ]] || continue
      name="$(tr -d '\n' < "$hw/name" 2>/dev/null || true)"
      if [[ "$name" == "$want" ]]; then
        echo "$hw"
        return 0
      fi
    done
  done
  return 1
}

dump() {
  local label="$1"
  echo "== ${label} =="
  for attr in fan1_input pwm1 pwm1_enable temp1_input; do
    if [[ -e "$HWMON/$attr" ]]; then
      echo "  $attr=$(cat "$HWMON/$attr")"
    fi
  done
}

if [[ "${1:-}" == -h || "${1:-}" == --help ]]; then
  usage
  exit 0
fi

args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --hold)
      HOLD="${2:?--hold needs seconds}"
      shift 2
      ;;
    --find|--read|-h|--help)
      args+=("$1")
      shift
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done
set -- "${args[@]+"${args[@]}"}"
if [[ "${1:-}" =~ ^[0-9]+$ ]]; then
  PERCENT="$1"
fi

HWMON="$(find_hwmon || true)"
if [[ -z "$HWMON" ]]; then
  echo "no oxp_wmi or oxpec hwmon under /sys/class/hwmon" >&2
  echo "loaded modules:" >&2
  lsmod | grep -E 'oxp_wmi|oxpec' || echo "  (neither oxp_wmi nor oxpec is loaded)" >&2
  echo "hwmon names:" >&2
  for hw in /sys/class/hwmon/hwmon*; do
    [[ -e "$hw/name" ]] && echo "  $hw $(cat "$hw/name")"
  done
  echo "X2 Mini: sudo kmod/scripts/test-oxp-wmi.sh && sudo $0" >&2
  echo "AMD:     sudo kmod/scripts/test-oxpec.sh && sudo $0" >&2
  exit 1
fi

NAME="$(tr -d '\n' < "$HWMON/name")"
echo "hwmon=$HWMON name=$NAME"

if [[ "${1:-}" == --find ]]; then
  exit 0
fi

if [[ "${1:-}" == --read ]]; then
  dump read
  exit 0
fi

if [[ "${EUID}" -ne 0 ]]; then
  echo "writes need root: sudo $0 ${PERCENT}" >&2
  exit 1
fi

if ! [[ "$PERCENT" =~ ^[0-9]+$ ]] || [[ "$PERCENT" -lt 1 || "$PERCENT" -gt 100 ]]; then
  echo "percent must be 1-100" >&2
  exit 2
fi

if ! [[ "$HOLD" =~ ^[0-9]+$ ]] || [[ "$HOLD" -lt 1 ]]; then
  echo "hold seconds must be >= 1" >&2
  exit 2
fi

# hwmon pwm1 is 0-255. oxp-wmi maps that onto EC 0-184 internally.
PWM=$((PERCENT * 255 / 100))
echo "manual ${PERCENT}% -> pwm1=${PWM} (hold ${HOLD}s)"

dump before

if ! echo 1 > "$HWMON/pwm1_enable"; then
  echo "pwm1_enable=1 write failed (WriteECReg packing or WMI type)." >&2
  echo "dmesg | grep oxp-wmi | tail; cat /sys/kernel/debug/oxp-wmi-*/last_info" >&2
  exit 3
fi
en="$(cat "$HWMON/pwm1_enable")"
echo "after enable write: pwm1_enable=${en}"
if [[ "$en" != 1 ]]; then
  echo "pwm1_enable did not stick (still ${en}). Fan stayed in auto; duty writes are ignored." >&2
  echo "dmesg | grep oxp-wmi | tail; cat /sys/kernel/debug/oxp-wmi-*/last_info" >&2
  exit 3
fi

if ! echo "$PWM" > "$HWMON/pwm1"; then
  echo "pwm1=${PWM} write failed" >&2
  echo 2 > "$HWMON/pwm1_enable" || true
  exit 3
fi
dump after-write

sleep "$HOLD"
dump after-hold

echo 2 > "$HWMON/pwm1_enable"
echo "restored pwm1_enable=2 (auto)"
dump after-restore
