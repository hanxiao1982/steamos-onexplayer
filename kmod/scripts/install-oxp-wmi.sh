#!/usr/bin/env bash
# Build oxp-wmi.ko and print how to load it by hand.
# Does not copy into /var, does not install a systemd unit.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
KO="${ROOT}/linux/oxp-wmi/oxp-wmi.ko"
UNIT="/etc/systemd/system/oxp-wmi-local.service"

"${ROOT}/kmod/scripts/build.sh" oxp-wmi

running="$(uname -r)"
vermagic="$(modinfo -F vermagic "${KO}" 2>/dev/null | awk '{print $1}')"
echo "running kernel: ${running}"
echo "oxp-wmi.ko vermagic: ${vermagic:-unknown}"
if [[ -n "${vermagic}" && "${vermagic}" != "${running}" ]]; then
  echo "vermagic mismatch — rebuild on this kernel:" >&2
  echo "  sudo kmod/scripts/build.sh oxp-wmi" >&2
  exit 1
fi

echo
echo "oxp-wmi is not installed as a boot service (manual load only)."
echo "Bazzite: systemd (init_t) cannot insmod a var_lib_t .ko, and cannot"
echo "exec a script labeled modules_object_t. Login sudo insmod is unconfined."
echo
echo "Load for this boot:"
echo "  sudo ${ROOT}/kmod/scripts/test-oxp-wmi.sh ${KO}"
echo "or:"
echo "  sudo insmod ${KO}"
echo "Unload:"
echo "  sudo rmmod oxp_wmi"

if [[ -f "${UNIT}" ]]; then
  echo
  echo "Leftover oxp-wmi-local.service from an earlier persist attempt."
  if [[ "${EUID}" -eq 0 ]]; then
    systemctl disable --now oxp-wmi-local.service 2>/dev/null || true
    rm -f "${UNIT}" /etc/oxp-kmod/load-oxp-wmi.sh /var/lib/oxp-kmod/load-oxp-wmi.sh
    systemctl daemon-reload 2>/dev/null || true
    echo "disabled and removed ${UNIT}"
  else
    echo "  sudo systemctl disable --now oxp-wmi-local.service"
    echo "  sudo rm -f ${UNIT}"
    echo "  sudo systemctl daemon-reload"
  fi
fi
