#!/usr/bin/env bash
# CachyOS: headers, build, install, optional DKMS.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

if [[ "${EUID}" -ne 0 ]]; then
  echo "run as root on the handheld" >&2
  exit 1
fi

pacman -S --needed --noconfirm \
  linux-cachyos-deckify-headers base-devel pahole curl python

STACK="$("${ROOT}/kmod/scripts/ec-stack.sh" detect)"
echo "ec-stack=${STACK}"

if [[ "$STACK" == oxp-wmi ]]; then
  "${ROOT}/kmod/scripts/build.sh" oxp-wmi
  "${ROOT}/kmod/scripts/install-oxp-wmi.sh"
  "${ROOT}/kmod/scripts/test-oxp-wmi.sh" "${ROOT}/linux/oxp-wmi/oxp-wmi.ko"
  echo
  echo "Optional persist via DKMS (rebuilds after kernel updates):"
  echo "  sudo dkms add ${ROOT}/linux/oxp-wmi"
  echo "  sudo dkms install oxp-wmi/0.1.0"
  exit 0
fi

if [[ ! -f "${ROOT}/kmod/oxpec/oxpec.c" ]]; then
  "${ROOT}/kmod/scripts/fetch-oxpec.sh" mainline
fi
"${ROOT}/kmod/scripts/inject-catalog.sh"

"${ROOT}/kmod/scripts/build.sh" oxpec
"${ROOT}/kmod/scripts/install-common.sh"
"${ROOT}/kmod/scripts/test-oxpec.sh" "${ROOT}/kmod/oxpec/oxpec.ko"

echo
echo "Optional persist via DKMS (rebuilds after kernel updates):"
echo "  sudo dkms add ${ROOT}/kmod/oxpec"
echo "  sudo dkms install oxpec-local/1.0.0"
