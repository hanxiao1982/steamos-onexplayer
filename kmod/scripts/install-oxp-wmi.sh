#!/usr/bin/env bash
# Build oxp-wmi.ko and print how to load it by hand.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
KO="${ROOT}/linux/oxp-wmi/oxp-wmi.ko"

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
echo "Load for this boot:"
echo "  sudo ${ROOT}/kmod/scripts/test-oxp-wmi.sh ${KO}"
echo "or:"
echo "  sudo insmod ${KO}"
echo "Unload:"
echo "  sudo rmmod oxp_wmi"
