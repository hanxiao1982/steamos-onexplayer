#!/usr/bin/env bash
# Print DMI from this machine, or --add a devices/*.env without touching other models.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVICES_DIR="${OXP_DEVICES_DIR:-$(cd "$SCRIPT_DIR/../devices" && pwd)}"
FORCE=0
ADD=0
SLUG=""

usage() {
  cat <<'EOF'
Usage:
  collect-dmi.sh              Print DMI + suggested env fields
  collect-dmi.sh --add [slug] Write kmod/devices/<slug>.env (does not overwrite others)
  collect-dmi.sh --add [slug] --force   Overwrite that one file only

Environment:
  OXP_DEVICES_DIR   Override catalog directory (default: kmod/devices)
  OXP_BOARD_VARIANT Default oxp_fly (override if this is X1 / G1 / …)
  OXP_CAP_MAP       Default oxp8
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --add)
      ADD=1
      if [[ $# -ge 2 && "$2" != --* ]]; then
        SLUG="$2"
        shift 2
      else
        shift
      fi
      ;;
    --force)
      FORCE=1
      shift
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
  local f="$1"
  if [[ -r "/sys/class/dmi/id/$f" ]]; then
    tr -d '\n' < "/sys/class/dmi/id/$f"
  else
    echo "UNKNOWN"
  fi
}

BOARD_VENDOR="$(read_dmi board_vendor)"
BOARD_NAME="$(read_dmi board_name)"
SYS_VENDOR="$(read_dmi sys_vendor)"
PRODUCT_NAME="$(read_dmi product_name)"
PRODUCT_VERSION="$(read_dmi product_version)"
BOARD_VERSION="$(read_dmi board_version)"
EC_STACK="${OXP_EC_STACK:-$("$SCRIPT_DIR/ec-stack.sh" from-names "$PRODUCT_NAME" "$BOARD_NAME")}"
if [[ -n "${OXP_BOARD_VARIANT:-}" ]]; then
  VARIANT="$OXP_BOARD_VARIANT"
elif [[ "$EC_STACK" == oxp-wmi ]]; then
  VARIANT="oxp_wmi"
else
  VARIANT="oxp_fly"
fi
if [[ "$EC_STACK" == oxp-wmi ]]; then
  CAP_MAP="${OXP_CAP_MAP:-oxp5}"
else
  CAP_MAP="${OXP_CAP_MAP:-oxp8}"
fi

if [[ "$BOARD_VENDOR" == UNKNOWN || "$BOARD_NAME" == UNKNOWN ]]; then
  echo "error: /sys/class/dmi/id/{board_vendor,board_name} missing or unreadable" >&2
  echo "       run this on the handheld, not in a VM without DMI passthrough" >&2
  exit 1
fi

if [[ -z "$SLUG" ]]; then
  SLUG="$(
    OXP_SLUG_SRC="$BOARD_NAME" python3 -c \
      "import os, sys; sys.path.insert(0, '$SCRIPT_DIR'); from device_lib import slugify; print(slugify(os.environ['OXP_SLUG_SRC']))"
  )"
fi

print_fields() {
  cat <<EOF
# /sys/class/dmi/id (this machine)
board_vendor=$BOARD_VENDOR
board_name=$BOARD_NAME
board_version=$BOARD_VERSION
sys_vendor=$SYS_VENDOR
product_name=$PRODUCT_NAME
product_version=$PRODUCT_VERSION

# --- paste into kmod/devices/<slug>.env ---
OXP_BOARD_VENDOR=$BOARD_VENDOR
OXP_BOARD_NAME=$BOARD_NAME
OXP_BOARD_VARIANT=$VARIANT
OXP_EC_STACK=$EC_STACK
OXP_SYS_VENDOR=$SYS_VENDOR
OXP_PRODUCT_NAME=$PRODUCT_NAME
OXP_CAP_MAP=$CAP_MAP
OXP_SLUG=$SLUG
EOF
}

if [[ "$ADD" -eq 0 ]]; then
  print_fields
  echo
  echo "# To accumulate this model without wiping others:"
  echo "#   $0 --add $SLUG"
  exit 0
fi

mkdir -p "$DEVICES_DIR"
OUT="$DEVICES_DIR/${SLUG}.env"
if [[ -e "$OUT" && "$FORCE" -eq 0 ]]; then
  echo "error: $OUT already exists (use --force to replace this file only)" >&2
  exit 1
fi

{
  echo "# Auto-collected $(date -u +%Y-%m-%dT%H:%M:%SZ) on $(hostname)"
  echo "OXP_BOARD_VENDOR=$BOARD_VENDOR"
  echo "OXP_BOARD_NAME=$BOARD_NAME"
  echo "OXP_BOARD_VARIANT=$VARIANT"
  echo "OXP_EC_STACK=$EC_STACK"
  echo "OXP_SYS_VENDOR=$SYS_VENDOR"
  echo "OXP_PRODUCT_NAME=$PRODUCT_NAME"
  echo "OXP_CAP_MAP=$CAP_MAP"
  echo "OXP_SLUG=$SLUG"
} > "$OUT"

echo "wrote $OUT"
echo "catalog now:"
# shellcheck disable=SC2012
ls -1 "$DEVICES_DIR"/*.env 2>/dev/null | sed 's|.*/||' || true
