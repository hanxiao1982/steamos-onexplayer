#!/usr/bin/env bash
# Install oxpec.ko to a writable path and enable a boot service.
# /var and /etc are writable on both CachyOS and Bazzite ostree.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
KO="${ROOT}/kmod/oxpec/oxpec.ko"
DEST_DIR="${DEST_DIR:-/var/lib/oxp-kmod}"
UNIT="/etc/systemd/system/oxpec-local.service"

if [[ "${EUID}" -ne 0 ]]; then
  echo "run as root" >&2
  exit 1
fi
if [[ ! -f "${KO}" ]]; then
  echo "missing ${KO}; build first" >&2
  exit 1
fi

install -d "${DEST_DIR}"
install -m 0644 "${KO}" "${DEST_DIR}/oxpec.ko"

cat >"${UNIT}" <<EOF
[Unit]
Description=Load locally built oxpec (OneXPlayer EC)
After=systemd-modules-load.service
Before=inputplumber.service steamos-manager.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=-/sbin/modprobe -r oxpec
ExecStart=/sbin/insmod ${DEST_DIR}/oxpec.ko
ExecStop=/sbin/modprobe -r oxpec

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now oxpec-local.service
systemctl --no-pager --full status oxpec-local.service || true
echo "installed ${DEST_DIR}/oxpec.ko and ${UNIT}"
