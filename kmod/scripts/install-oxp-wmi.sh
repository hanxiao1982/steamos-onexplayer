#!/usr/bin/env bash
# Install oxp-wmi.ko to a writable path and enable a boot service.
# Same /var + /etc layout as install-common.sh (oxpec).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
KO="${ROOT}/linux/oxp-wmi/oxp-wmi.ko"
DEST_DIR="${DEST_DIR:-/var/lib/oxp-kmod}"
UNIT="/etc/systemd/system/oxp-wmi-local.service"
FORCE="${OXP_WMI_FORCE:-0}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "run as root" >&2
  exit 1
fi
if [[ ! -f "${KO}" ]]; then
  echo "missing ${KO}; run kmod/scripts/build.sh oxp-wmi first" >&2
  exit 1
fi

install -d "${DEST_DIR}"
install -m 0644 "${KO}" "${DEST_DIR}/oxp-wmi.ko"

INSMOD="/sbin/insmod ${DEST_DIR}/oxp-wmi.ko"
if [[ "$FORCE" == 1 ]]; then
  INSMOD="${INSMOD} force=1"
fi

cat >"${UNIT}" <<EOF
[Unit]
Description=Load locally built oxp-wmi (OneXPlayer Intel OxpWMI EC)
After=systemd-modules-load.service
Before=inputplumber.service steamos-manager.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=-/sbin/modprobe -r oxp_wmi
ExecStart=${INSMOD}
ExecStop=/sbin/modprobe -r oxp_wmi

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now oxp-wmi-local.service
systemctl --no-pager --full status oxp-wmi-local.service || true
echo "installed ${DEST_DIR}/oxp-wmi.ko and ${UNIT}"
