#!/usr/bin/env bash
# Raw WMAC method poke. Does not go through hwmon scaling.
# eval payload: method (1/2/3) + 4-byte LE GroupOffsetValue.
set -euo pipefail

EVAL="$(echo /sys/kernel/debug/oxp-wmi-*/eval)"
INFO="$(echo /sys/kernel/debug/oxp-wmi-*/last_info)"
HWMON=""

for hw in /sys/class/hwmon/hwmon*; do
  [[ -e "$hw/name" ]] || continue
  if [[ "$(tr -d '\n' <"$hw/name")" == oxp_wmi ]]; then
    HWMON="$hw"
    break
  fi
done

if [[ ! -e "${EVAL}" ]]; then
  echo "missing ${EVAL}. mount debugfs and load oxp-wmi 0.4+" >&2
  exit 1
fi

read_fan() {
  if [[ -n "$HWMON" ]]; then
    echo "fan1=$(cat "$HWMON/fan1_input") pwm1=$(cat "$HWMON/pwm1") enable=$(cat "$HWMON/pwm1_enable")"
  fi
}

poke() {
  local label="$1"
  shift
  printf '%s' "$@" >"${EVAL}"
  echo "== ${label} =="
  cat "${INFO}"
  read_fan
}

echo "before:"
read_fan

# method 2: 0x4A=1  (04 4a 01 00)
poke "m2 0x4A=1" $'\x02\x04\x4a\x01\x00'
# method 3: 0x4B=184 (04 4b b8 00)
poke "m3 0x4B=184" $'\x03\x04\x4b\xb8\x00'
sleep 0.3
echo "after 300ms:"
read_fan
cat "${INFO}"

# method 3: 0x4A=1 then 0x4B=184 again
poke "m3 0x4A=1" $'\x03\x04\x4a\x01\x00'
poke "m3 0x4B=184" $'\x03\x04\x4b\xb8\x00'
sleep 1
echo "after 1s:"
read_fan

echo "restore m2 0x4A=0"
poke "m2 0x4A=0" $'\x02\x04\x4a\x00\x00'
read_fan
