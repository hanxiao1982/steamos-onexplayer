#!/usr/bin/env bash
# Raw WMAC method poke. Does not go through hwmon scaling.
#
# debugfs eval payload: method (1/2/3) + 4-byte LE GroupOffsetValue.
# 0.5+ also accepts hex text:  echo 2 04 4a 01 00 > eval
#
# Do not write the 5-byte payload with `printf '%s'`. The last byte is often
# NUL, and %s stops there → 4-byte write → EINVAL ("无效的参数") on 0.4.
set -euo pipefail

shopt -s nullglob
evals=(/sys/kernel/debug/oxp-wmi-*/eval)
if ((${#evals[@]} != 1)); then
  echo "need exactly one debugfs eval node (got ${#evals[@]})." >&2
  echo "mount debugfs and load oxp-wmi 0.4+ (0.5+ accepts hex text)." >&2
  ls -d /sys/kernel/debug/oxp-wmi-* 2>/dev/null || true
  if [[ -r /sys/module/oxp_wmi/version ]]; then
    echo "loaded oxp_wmi $(cat /sys/module/oxp_wmi/version)" >&2
  else
    echo "oxp_wmi is not loaded" >&2
  fi
  exit 1
fi

EVAL="${evals[0]}"
INFO="${EVAL%/eval}/last_info"
HWMON=""

for hw in /sys/class/hwmon/hwmon*; do
  [[ -e "$hw/name" ]] || continue
  if [[ "$(tr -d '\n' <"$hw/name")" == oxp_wmi ]]; then
    HWMON="$hw"
    break
  fi
done

if [[ -r /sys/module/oxp_wmi/version ]]; then
  echo "oxp_wmi $(cat /sys/module/oxp_wmi/version) eval=${EVAL}"
fi

# Write method + 4 LE bytes. Args are integers (0x4a or 74).
# Uses a printf FORMAT so a trailing 0x00 is actually written.
write_eval() {
  local m="$1" b0="${2:-0}" b1="${3:-0}" b2="${4:-0}" b3="${5:-0}"
  local fmt

  fmt="$(printf '\\x%02x\\x%02x\\x%02x\\x%02x\\x%02x' \
    "$((m))" "$((b0))" "$((b1))" "$((b2))" "$((b3))")"
  # shellcheck disable=SC2059
  printf "${fmt}" >"${EVAL}"
}

read_fan() {
  if [[ -n "$HWMON" ]]; then
    echo "fan1=$(cat "$HWMON/fan1_input") pwm1=$(cat "$HWMON/pwm1") enable=$(cat "$HWMON/pwm1_enable")"
  fi
}

poke() {
  local label="$1"
  shift
  write_eval "$@"
  echo "== ${label} =="
  cat "${INFO}"
  read_fan
}

# One-shot: poke-oxp-wmi.sh 2 0x04 0x4b 0xff 0x00
if (($# >= 1)); then
  poke "eval $*" "$@"
  exit 0
fi

echo "before:"
read_fan

# method 2: 0x4A=1  (04 4a 01 00)
poke "m2 0x4A=1" 0x02 0x04 0x4a 0x01 0x00
# method 3: 0x4B=184 (04 4b b8 00)
poke "m3 0x4B=184" 0x03 0x04 0x4b 0xb8 0x00
sleep 0.3
echo "after 300ms:"
read_fan
cat "${INFO}"

# method 3: 0x4A=1 then 0x4B=184 again
poke "m3 0x4A=1" 0x03 0x04 0x4a 0x01 0x00
poke "m3 0x4B=184" 0x03 0x04 0x4b 0xb8 0x00
sleep 1
echo "after 1s:"
read_fan

echo "restore m2 0x4A=0"
poke "m2 0x4A=0" 0x02 0x04 0x4a 0x00 0x00
read_fan
