#!/usr/bin/env bash
# Decide which EC kernel module this handheld needs.
#   oxp-wmi — Intel G3E / OxpWMI (X2 Mini, X2, OneXPlayer 3, Apex Air, …)
#   oxpec   — AMD / ACPI EC (X2 Mini PRO, APEX, F1, X1, …)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage:
  ec-stack.sh              Print oxpec or oxp-wmi for this machine
  ec-stack.sh detect       Same
  ec-stack.sh from-env FILE
  ec-stack.sh from-names PRODUCT BOARD

Override: OXP_EC_STACK=oxp-wmi|oxpec
EOF
}

stack_from_names() {
  local product="${1:-}" board="${2:-}"
  # AMD first: "X2Mini PRO" must not match "X2Mini"
  case "$product" in
    "ONEXPLAYER X2Mini PRO"|"ONEXPLAYER APEX") echo oxpec; return ;;
  esac
  case "$board" in
    "ONEXPLAYER X2Mini PRO"|"ONEXPLAYER APEX") echo oxpec; return ;;
  esac
  case "$product" in
    "ONEXPLAYER X2Mini"|"ONEXPLAYER X2"|"ONEXPLAYER X2 EVA"|"ONEXPLAYER 3"|"ONEXPLAYER Apex Air"|"ONEXPLAYER Apex i")
      echo oxp-wmi
      return
      ;;
  esac
  case "$board" in
    "ONEXPLAYER X2Mini"|"ONEXPLAYER X2"|"ONEXPLAYER X2 EVA"|"ONEXPLAYER 3"|"ONEXPLAYER Apex Air"|"ONEXPLAYER Apex i")
      echo oxp-wmi
      return
      ;;
  esac
  echo oxpec
}

stack_from_env_file() {
  local file="$1"
  local key value stack="" variant="" product="" board=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z "$line" || "$line" != *=* ]] && continue
    key="${line%%=*}"
    value="${line#*=}"
    case "$key" in
      OXP_EC_STACK) stack="$value" ;;
      OXP_BOARD_VARIANT) variant="$value" ;;
      OXP_PRODUCT_NAME) product="$value" ;;
      OXP_BOARD_NAME) board="$value" ;;
    esac
  done < "$file"
  if [[ -n "${OXP_EC_STACK:-}" ]]; then
    echo "$OXP_EC_STACK"
    return
  fi
  if [[ "$stack" == oxp-wmi || "$stack" == oxpec ]]; then
    echo "$stack"
    return
  fi
  if [[ "$variant" == oxp_wmi ]]; then
    echo oxp-wmi
    return
  fi
  stack_from_names "$product" "$board"
}

detect_machine() {
  if [[ -n "${OXP_EC_STACK:-}" ]]; then
    echo "$OXP_EC_STACK"
    return
  fi
  local product="UNKNOWN" board="UNKNOWN"
  if [[ -r /sys/class/dmi/id/product_name ]]; then
    product="$(tr -d '\n' < /sys/class/dmi/id/product_name)"
  fi
  if [[ -r /sys/class/dmi/id/board_name ]]; then
    board="$(tr -d '\n' < /sys/class/dmi/id/board_name)"
  fi
  stack_from_names "$product" "$board"
}

cmd="${1:-detect}"
case "$cmd" in
  detect|"")
    detect_machine
    ;;
  from-env)
    [[ $# -ge 2 ]] || { usage >&2; exit 2; }
    stack_from_env_file "$2"
    ;;
  from-names)
    stack_from_names "${2:-}" "${3:-}"
    ;;
  -h|--help)
    usage
    ;;
  *)
    echo "unknown argument: $cmd" >&2
    usage >&2
    exit 2
    ;;
esac
