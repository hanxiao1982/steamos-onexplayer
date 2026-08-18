#!/usr/bin/env bash
# Raw OxpWMI method poke. Does not go through hwmon scaling.
#
# eval payload: method (1/2/3) + 4-byte LE GroupOffsetValue.
# 0.5+ also accepts hex text. 0.6+ accepts "i …" for ACPI Integer Arg2.
#
# Do not write the 5-byte payload with `printf '%s'`. The last byte is often
# NUL, and %s stops there → 4-byte write → EINVAL ("无效的参数") on 0.4.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  poke-oxp-wmi.sh                 Register bank scan around a 0x4B write
  poke-oxp-wmi.sh --watch         Write duty, poll 0x4B + RPM every 20ms
  poke-oxp-wmi.sh --strobe        After duty, pulse 0x48/0x49/0x4C/0x4D
  poke-oxp-wmi.sh --old           Previous method2/3 0x4A + 0x4B sequence
  poke-oxp-wmi.sh --int …         Same as one-shot but Integer Arg2 (0.6+)
  poke-oxp-wmi.sh 2 0x04 0x4b 0xb8 0x00
EOF
}

shopt -s nullglob
evals=(/sys/kernel/debug/oxp-wmi-*/eval)
if ((${#evals[@]} != 1)); then
  echo "need exactly one debugfs eval node (got ${#evals[@]})." >&2
  echo "mount debugfs and load oxp-wmi 0.4+ (0.6+ for Integer Arg2)." >&2
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
VER=""
[[ -r /sys/module/oxp_wmi/version ]] && VER="$(tr -d '\n' </sys/module/oxp_wmi/version)"

for hw in /sys/class/hwmon/hwmon*; do
  [[ -e "$hw/name" ]] || continue
  if [[ "$(tr -d '\n' <"$hw/name")" == oxp_wmi ]]; then
    HWMON="$hw"
    break
  fi
done

echo "oxp_wmi ${VER:-unknown} eval=${EVAL}"

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

# ReadECReg via method 1. Prints the EC byte as two hex digits, or FF on fail.
eval_read() {
  local reg="$1"
  write_eval 1 0x04 "$reg" 0 0
  awk '/^out=/{sub(/^out=/,""); print $2; exit}' "${INFO}"
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

dump_ec_sys() {
  local io=/sys/kernel/debug/ec/ec0/io
  local label="$1"

  if [[ ! -r "$io" ]]; then
    return 0
  fi
  echo "-- acpi ec0 ${label} 0x40-0x5F --"
  od -An -tx1 -v -w16 -j 64 -N 32 "$io" | sed 's/^/  /'
}

# regs: 0x40-0x5F, plus a few known outliers (read only)
scan_reg_list() {
  local r
  for r in $(seq 64 95); do
    printf '0x%02x\n' "$r"
  done
  printf '0x%02x\n' 0x70 0xA3 0xA4 0xE3 0xEB 0xED
}

snapshot_bank() {
  local name="$1"
  local r val

  echo "== bank ${name} =="
  read_fan
  dump_ec_sys "$name"
  printf '%-6s %s\n' reg val
  for r in $(scan_reg_list); do
    val="$(eval_read "$r")"
    printf '%-6s %s\n' "$r" "$val"
  done
}

diff_banks() {
  local a="$1" b="$2"
  echo "== diff ${a} -> ${b} (changed only) =="
  awk -v afile="$a" -v bfile="$b" '
    FNR == NR && $1 ~ /^0x/ { old[$1] = $2; next }
    $1 ~ /^0x/ && old[$1] != $2 { printf "  %s %s -> %s\n", $1, old[$1], $2 }
  ' "$a" "$b"
}

cmd_scan() {
  local tmp dir
  dir="$(mktemp -d)"
  trap 'rm -rf "$dir"' EXIT

  snapshot_bank baseline | tee "$dir/0"
  poke "m2 0x4A=1" 0x02 0x04 0x4a 0x01 0x00
  snapshot_bank after_4a | tee "$dir/1"
  poke "m3 0x4B=184" 0x03 0x04 0x4b 0xb8 0x00
  snapshot_bank after_4b | tee "$dir/2"
  sleep 0.05
  snapshot_bank plus_50ms | tee "$dir/3"
  sleep 0.25
  snapshot_bank plus_300ms | tee "$dir/4"

  echo
  diff_banks "$dir/0" "$dir/1"
  diff_banks "$dir/1" "$dir/2"
  diff_banks "$dir/2" "$dir/3"
  diff_banks "$dir/3" "$dir/4"

  echo "restore m2 0x4A=0"
  poke "m2 0x4A=0" 0x02 0x04 0x4a 0x00 0x00
  echo
  echo "Paste the == diff == blocks. A second register changing with 0x4B"
  echo "is the latch. If only 0x4B flips then clears, the write is a mailbox."
}

cmd_watch() {
  local i val rpm
  echo "write 0x4A=1, 0x4B=184, then poll method-1 for 1s"
  poke "m2 0x4A=1" 0x02 0x04 0x4a 0x01 0x00
  poke "m3 0x4B=184" 0x03 0x04 0x4b 0xb8 0x00
  printf '%-8s %-6s %-6s %s\n' ms 4B 4A rpm
  for i in $(seq 0 50); do
    val="$(eval_read 0x4B)"
    printf '%-8s %-6s %-6s %s\n' "$((i * 20))" "$val" "$(eval_read 0x4A)" \
      "$(cat "$HWMON/fan1_input" 2>/dev/null || echo -)"
    sleep 0.02
  done
  poke "m2 0x4A=0" 0x02 0x04 0x4a 0x00 0x00
}

cmd_strobe() {
  local r saved
  echo "manual + duty, then pulse neighbor regs 1→saved"
  poke "m2 0x4A=1" 0x02 0x04 0x4a 0x01 0x00
  poke "m3 0x4B=184" 0x03 0x04 0x4b 0xb8 0x00
  for r in 0x48 0x49 0x4c 0x4d; do
    saved="$(eval_read "$r")"
    echo "-- strobe ${r} saved=${saved} write 1 --"
    write_eval 3 0x04 "$r" 1 0
    cat "${INFO}"
    sleep 0.2
    read_fan
    echo "  ${r} now=$(eval_read "$r") 4B=$(eval_read 0x4B)"
    write_eval 3 0x04 "$r" "0x${saved}" 0
  done
  poke "m2 0x4A=0" 0x02 0x04 0x4a 0x00 0x00
}

cmd_old() {
  echo "before:"
  read_fan
  poke "m2 0x4A=1" 0x02 0x04 0x4a 0x01 0x00
  poke "m3 0x4B=184" 0x03 0x04 0x4b 0xb8 0x00
  sleep 0.3
  echo "after 300ms:"
  read_fan
  cat "${INFO}"
  poke "m3 0x4A=1" 0x03 0x04 0x4a 0x01 0x00
  poke "m3 0x4B=184" 0x03 0x04 0x4b 0xb8 0x00
  sleep 1
  echo "after 1s:"
  read_fan
  echo "restore m2 0x4A=0"
  poke "m2 0x4A=0" 0x02 0x04 0x4a 0x00 0x00
  read_fan
}

write_eval_int() {
  if [[ -n "$VER" ]] && awk "BEGIN{exit !($VER + 0 >= 0.6)}"; then
    echo "i $(printf '%x %x %x %x %x' "$(($1))" "$((${2:-0}))" "$((${3:-0}))" \
      "$((${4:-0}))" "$((${5:-0}))")" >"${EVAL}"
  else
    echo "Integer Arg2 needs oxp-wmi 0.6+ (loaded ${VER:-none})" >&2
    exit 1
  fi
}

if (($# == 0)); then
  cmd_scan
  exit 0
fi

case "$1" in
  -h|--help)
    usage
    exit 0
    ;;
  --scan)
    cmd_scan
    ;;
  --watch)
    cmd_watch
    ;;
  --strobe)
    cmd_strobe
    ;;
  --old)
    cmd_old
    ;;
  --int)
    shift
    write_eval_int "$@"
    echo "== int $* =="
    cat "${INFO}"
    read_fan
    ;;
  *)
    poke "eval $*" "$@"
    ;;
esac
