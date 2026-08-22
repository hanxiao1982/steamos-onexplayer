#!/usr/bin/env bash
# Install oxp-wmi.ko to a writable path and enable a boot service.
# Same /var + /etc layout as install-common.sh (oxpec).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
KO="${ROOT}/linux/oxp-wmi/oxp-wmi.ko"
LOADER_SRC="${ROOT}/kmod/scripts/load-oxp-wmi.sh"
DEST_DIR="${DEST_DIR:-/var/lib/oxp-kmod}"
LOADER_DEST="${LOADER_DEST:-/etc/oxp-kmod/load-oxp-wmi.sh}"
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
if [[ ! -f "${LOADER_SRC}" ]]; then
  echo "missing ${LOADER_SRC}" >&2
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
install -d "$(dirname "${LOADER_DEST}")"
install -m 0644 "${KO}" "${DEST_DIR}/oxp-wmi.ko"
install -m 0755 "${LOADER_SRC}" "${LOADER_DEST}"
# Old installer copied the loader next to the .ko and then labeled the
# whole tree modules_object_t. systemd cannot exec that type (203/EXEC).
rm -f "${DEST_DIR}/load-oxp-wmi.sh"

# systemd is init_t; /var/lib defaults to var_lib_t. insmod then returns
# EACCES ("Permission denied"). Login `sudo insmod` is unconfined and works.
# Only the .ko is a kernel-module object. The loader lives under /etc and
# is started as `/bin/bash …` so systemd never execs a modules_object_t file.
if command -v getenforce >/dev/null 2>&1 && [[ "$(getenforce)" != Disabled ]]; then
  if command -v semanage >/dev/null 2>&1; then
    semanage fcontext -d '/var/lib/oxp-kmod(/.*)?' 2>/dev/null || true
    if [[ "${DEST_DIR}" != /var/lib/oxp-kmod ]]; then
      semanage fcontext -d "${DEST_DIR}(/.*)?" 2>/dev/null || true
    fi
    if ! semanage fcontext -l -C 2>/dev/null | grep -qF "${DEST_DIR}(/.*)?\\.ko"; then
      semanage fcontext -a -t modules_object_t "${DEST_DIR}(/.*)?\\.ko" || true
    fi
    restorecon -Rv "${DEST_DIR}" || true
  fi
  chcon -t var_lib_t "${DEST_DIR}" 2>/dev/null || true
  chcon -t modules_object_t "${DEST_DIR}/oxp-wmi.ko" 2>/dev/null || true
  echo "SELinux dest: $(ls -Zd "${DEST_DIR}" 2>/dev/null || echo '?')"
  echo "SELinux ko:   $(ls -Z "${DEST_DIR}/oxp-wmi.ko" 2>/dev/null || echo '?')"
  echo "SELinux load: $(ls -Z "${LOADER_DEST}" 2>/dev/null || echo '?')"
fi

cat >"${UNIT}" <<EOF
[Unit]
Description=Load locally built oxp-wmi (OneXPlayer Intel OxpWMI EC)
After=systemd-modules-load.service
Before=inputplumber.service steamos-manager.service oxp-tdp-rapl.service

[Service]
Type=oneshot
RemainAfterExit=yes
Environment=DEST_DIR=${DEST_DIR}
Environment=OXP_WMI_FORCE=${FORCE}
ExecStart=/bin/bash ${LOADER_DEST}
ExecStop=-/sbin/rmmod oxp_wmi

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
if ! systemctl enable --now oxp-wmi-local.service; then
  echo "oxp-wmi-local.service failed. Last journal + dmesg:" >&2
  journalctl -u oxp-wmi-local.service -n 40 --no-pager || true
  echo "--- load script by hand ---" >&2
  DEST_DIR="${DEST_DIR}" OXP_WMI_FORCE="${FORCE}" /bin/bash "${LOADER_DEST}" || true
  dmesg | grep -iE 'oxp-wmi|oxp_wmi|loading out-of-tree|module verification|avc:' | tail -n 30 || true
  echo "Also: sudo kmod/scripts/test-oxp-wmi.sh" >&2
  echo "Bazzite 203/EXEC = loader labeled modules_object_t; insmod Permission denied = .ko still var_lib_t." >&2
  exit 1
fi
systemctl --no-pager --full status oxp-wmi-local.service || true
echo "installed ${DEST_DIR}/oxp-wmi.ko and ${LOADER_DEST} and ${UNIT}"
