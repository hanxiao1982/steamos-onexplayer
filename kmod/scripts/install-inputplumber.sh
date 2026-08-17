#!/usr/bin/env bash
# Overlay a local InputPlumber device profile. Does not modify HHD.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENV_FILE="${ROOT}/kmod/local-device.env"
SRC="${ROOT}/kmod/inputplumber/50-onexplayer_local.yaml"
NAME="50-onexplayer_local.yaml"

if [[ "${EUID}" -ne 0 ]]; then
  echo "run as root" >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a
# shellcheck source=/dev/null
source "${ENV_FILE}"
set +a

tmp="$(mktemp)"
sed \
  -e "s/ONEXPLAYER NEWMODEL/${OXP_PRODUCT_NAME}/g" \
  -e "s/ONE-NETBOOK/${OXP_SYS_VENDOR}/g" \
  "${SRC}" >"${tmp}"

if [[ -d /etc/inputplumber/devices ]]; then
  dest="/etc/inputplumber/devices/${NAME}"
elif [[ -d /usr/share/inputplumber/devices ]]; then
  dest="/usr/share/inputplumber/devices/${NAME}"
  if [[ ! -w /usr/share/inputplumber/devices ]]; then
    if command -v ostree >/dev/null; then
      echo "unlocking ostree hotfix so /usr is writable"
      ostree admin unlock --hotfix
    else
      echo "cannot write ${dest}" >&2
      exit 1
    fi
  fi
else
  echo "InputPlumber device dir not found" >&2
  exit 1
fi

install -m 0644 "${tmp}" "${dest}"
rm -f "${tmp}"

hwdb_extra="/etc/udev/hwdb.d/61-oxp-local.hwdb"
# hwdb DMI matches strip spaces from product_name.
pn_compact="${OXP_PRODUCT_NAME// /}"
cat >"${hwdb_extra}" <<EOF
# Local OneXPlayer overlay
dmi:*svn${OXP_SYS_VENDOR// /}:*pn${pn_compact}:*
 USE_INPUTPLUMBER=1
EOF
systemd-hwdb update
udevadm trigger -s dmi || true

systemctl restart inputplumber.service
echo "installed ${dest}"
echo "installed ${hwdb_extra}"
echo "check: journalctl -u inputplumber -b --no-pager | tail"
