#!/usr/bin/env bash
# Manual fan smoke test. X2 Mini uses hwmon name oxp_wmi, not oxpec.
# Empty HWMON + echo > "$HWMON/pwm1" writes /pwm1 on the ostree root (EIO: read-only).
set -euo pipefail

PERCENT="${1:-40}"

usage() {
  cat <<'EOF'
Usage:
  hwmon-pwm.sh [percent]     Set manual PWM (~percent), wait 3s, restore auto
  hwmon-pwm.sh --find        Print the hwmon directory and exit
  hwmon-pwm.sh --read        Print fan/pwm/temp and exit

Looks for name=oxp_wmi first (X2 Mini / Intel G3E), then name=oxpec (AMD).
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

if [[ "${1:-}" == -h || "${1:-}" == --help ]]; then
  usage
  exit 0
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
  for attr in fan1_input pwm1 pwm1_enable temp1_input; do
    if [[ -e "$HWMON/$attr" ]]; then
      echo "  $attr=$(cat "$HWMON/$attr")"
    fi
  done
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

# hwmon pwm1 is 0-255. oxp-wmi maps that onto EC 0-184 internally.
PWM=$((PERCENT * 255 / 100))
echo "manual ${PERCENT}% -> pwm1=${PWM}"

echo 1 > "$HWMON/pwm1_enable"
echo "$PWM" > "$HWMON/pwm1"
sleep 3
if [[ -e "$HWMON/fan1_input" ]]; then
  echo "fan1_input=$(cat "$HWMON/fan1_input")"
fi
echo 2 > "$HWMON/pwm1_enable"
echo "restored pwm1_enable=2 (auto)"
