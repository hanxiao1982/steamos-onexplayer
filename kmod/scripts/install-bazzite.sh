#!/usr/bin/env bash
# Bazzite: do not rpm-ostree a whole custom kernel for a DMI tweak.
# Build against matching kernel-devel if present, then load from /var.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
KREL="$(uname -r)"
KDIR="/lib/modules/${KREL}/build"

if [[ "${EUID}" -ne 0 ]]; then
  echo "run as root on the handheld" >&2
  exit 1
fi

if [[ ! -d "${KDIR}" ]]; then
  cat >&2 <<EOF
${KDIR} is missing. On Bazzite the image often ships no kernel-devel.

Try, in order:
  1) rpm -q kernel-devel kernel-devel-matched
  2) Find the OGC/Bazzite kernel-devel RPM that exactly matches:
       ${KREL}
     then:  rpm-ostree install /path/to/kernel-devel-${KREL}.rpm
     reboot, and re-run this script.
  3) Or build the .ko on another Fedora machine with that same
     kernel-devel, copy oxpec.ko here, and run install-common.sh

Do not layer stock Fedora kernel-devel; the OGC vermagic will not match.
EOF
  exit 1
fi

if mokutil --sb-state 2>/dev/null | grep -qi 'SecureBoot enabled'; then
  cat >&2 <<EOF
Secure Boot is enabled. An unsigned local .ko will be rejected.
Disable Secure Boot in firmware for local testing, or sign the
module with a MOK and enroll it (ujust enroll-secure-boot-key
only enrolls Universal Blue's key, not yours).
EOF
  exit 1
fi

STACK="$("${ROOT}/kmod/scripts/ec-stack.sh" detect)"
echo "ec-stack=${STACK}"

if [[ "$STACK" == oxp-wmi ]]; then
  "${ROOT}/kmod/scripts/build.sh" oxp-wmi
  "${ROOT}/kmod/scripts/install-oxp-wmi.sh"
  "${ROOT}/kmod/scripts/test-oxp-wmi.sh" "${ROOT}/linux/oxp-wmi/oxp-wmi.ko"
  exit 0
fi

if [[ ! -f "${ROOT}/kmod/oxpec/oxpec.c" ]]; then
  "${ROOT}/kmod/scripts/fetch-oxpec.sh" ogc
fi
"${ROOT}/kmod/scripts/inject-catalog.sh"

"${ROOT}/kmod/scripts/build.sh" oxpec
"${ROOT}/kmod/scripts/install-common.sh"
"${ROOT}/kmod/scripts/test-oxpec.sh" "${ROOT}/kmod/oxpec/oxpec.ko"
