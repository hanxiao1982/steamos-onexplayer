#!/usr/bin/env bash
# Load /var/lib/oxp-kmod/oxp-wmi.ko. Used by oxp-wmi-local.service.
# Bazzite SELinux: systemd (init_t) cannot insmod a var_lib_t .ko — that is
# EACCES "Permission denied". A login `sudo insmod` is unconfined and works.
# Relabel only the .ko to modules_object_t. Do not label this script (or the
# directory) as a kernel module — systemd then fails with 203/EXEC.
# Do not use `modprobe -r` here: the module is not in modules.dep.
set -euo pipefail

DEST_DIR="${DEST_DIR:-/var/lib/oxp-kmod}"
KO="${DEST_DIR}/oxp-wmi.ko"
FORCE="${OXP_WMI_FORCE:-0}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "run as root" >&2
  exit 1
fi
if [[ ! -f "${KO}" ]]; then
  echo "missing ${KO}" >&2
  exit 1
fi

if command -v getenforce >/dev/null 2>&1 && [[ "$(getenforce)" != Disabled ]]; then
  chcon -t modules_object_t "${KO}" 2>/dev/null || true
fi

rmmod oxp_wmi 2>/dev/null || true
extra=()
if [[ "${FORCE}" == 1 ]]; then
  extra+=(force=1)
fi
if ! insmod "${KO}" "${extra[@]+"${extra[@]}"}"; then
  echo "insmod ${KO} failed" >&2
  if command -v ausearch >/dev/null 2>&1; then
    echo "--- recent SELinux AVC (if any) ---" >&2
    ausearch -m avc -ts recent 2>/dev/null | tail -n 20 || true
  fi
  echo "If this is Permission denied on Bazzite: SELinux on /var/lib/*.ko." >&2
  echo "  sudo chcon -t modules_object_t ${KO}" >&2
  echo "  sudo semanage fcontext -d '/var/lib/oxp-kmod(/.*)?' || true" >&2
  echo "  sudo semanage fcontext -a -t modules_object_t '${DEST_DIR}(/.*)?\\.ko'" >&2
  echo "  sudo restorecon -Rv ${DEST_DIR}" >&2
  echo "Do not label ${DEST_DIR} or this script as modules_object_t (203/EXEC)." >&2
  exit 1
fi
lsmod | grep -E '^oxp_wmi'
