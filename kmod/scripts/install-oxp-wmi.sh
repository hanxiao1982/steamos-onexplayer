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

running="$(uname -r)"
vermagic="$(modinfo -F vermagic "${KO}" 2>/dev/null | awk '{print $1}')"
echo "running kernel: ${running}"
echo "oxp-wmi.ko vermagic: ${vermagic:-unknown}"
if [[ -n "${vermagic}" && "${vermagic}" != "${running}" ]]; then
  echo "vermagic mismatch — rebuild on this kernel:" >&2
  echo "  sudo kmod/scripts/build.sh oxp-wmi" >&2
  echo "  sudo $0" >&2
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
if ! systemctl enable --now oxp-wmi-local.service; then
  echo "oxp-wmi-local.service failed. Last journal + dmesg:" >&2
  journalctl -u oxp-wmi-local.service -n 40 --no-pager || true
  echo "--- insmod by hand ---" >&2
  /sbin/modprobe -r oxp_wmi 2>/dev/null || true
  if ! ${INSMOD}; then
    echo "insmod failed. Common causes:" >&2
    echo "  - vermagic mismatch (rebuild: sudo kmod/scripts/build.sh oxp-wmi)" >&2
    echo "  - Secure Boot / MODULE_SIG_FORCE: sign the .ko or disable SB" >&2
    echo "  - DMI deny: OXP_WMI_FORCE=1 sudo $0" >&2
    echo "  - probe ReadECReg failed: same FORCE=1, then check dmesg" >&2
  fi
  dmesg | grep -iE 'oxp-wmi|oxp_wmi|loading out-of-tree|module verification' | tail -n 30 || true
  echo "Also: sudo kmod/scripts/test-oxp-wmi.sh" >&2
  exit 1
fi
systemctl --no-pager --full status oxp-wmi-local.service || true
echo "installed ${DEST_DIR}/oxp-wmi.ko and ${UNIT}"
