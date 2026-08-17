#!/usr/bin/env bash
# Run on the handheld. Prints DMI fields and a ready local-device.env snippet.
set -euo pipefail

read_id() {
  local f="/sys/class/dmi/id/$1"
  if [[ -r "$f" ]]; then
    tr -d '\n' <"$f"
  else
    echo "UNKNOWN"
  fi
}

board_vendor=$(read_id board_vendor)
board_name=$(read_id board_name)
sys_vendor=$(read_id sys_vendor)
product_name=$(read_id product_name)
product_version=$(read_id product_version)

echo "board_vendor   = ${board_vendor}"
echo "board_name     = ${board_name}"
echo "sys_vendor     = ${sys_vendor}"
echo "product_name   = ${product_name}"
echo "product_version= ${product_version}"
echo
echo "Paste into kmod/local-device.env:"
echo
cat <<EOF
OXP_BOARD_VENDOR=${board_vendor}
OXP_BOARD_NAME=${board_name}
OXP_BOARD_VARIANT=oxp_fly
OXP_SYS_VENDOR=${sys_vendor}
OXP_PRODUCT_NAME=${product_name}
EOF
