#!/usr/bin/env bash
# Build oxpec.ko against the running kernel. Works on CachyOS and Bazzite
# once that kernel's build tree is present.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="${ROOT}/kmod/oxpec"
KREL="${KERNELRELEASE:-$(uname -r)}"
KDIR="${KDIR:-/lib/modules/${KREL}/build}"

if [[ ! -f "${SRC}/oxpec.c" ]]; then
  echo "oxpec.c missing; run kmod/scripts/fetch-oxpec.sh first" >&2
  exit 1
fi
if [[ ! -d "${KDIR}" ]]; then
  cat >&2 <<EOF
No kernel build tree at ${KDIR}
CachyOS:  sudo pacman -S --needed linux-cachyos-deckify-headers base-devel pahole
Bazzite:  see docs/local-build-and-deploy.md (need kernel-devel matching $(uname -r))
EOF
  exit 1
fi

MAKE_ARGS=()
if [[ -f "${KDIR}/.config" ]] && grep -q '^CONFIG_CC_IS_CLANG=y' "${KDIR}/.config"; then
  echo "Kernel was built with Clang; using LLVM=1"
  MAKE_ARGS+=(LLVM=1)
fi

echo "Building oxpec.ko for ${KREL}"
make -C "${KDIR}" M="${SRC}" KERNELRELEASE="${KREL}" "${MAKE_ARGS[@]}" modules
modinfo "${SRC}/oxpec.ko" | sed -n 's/^filename:\|^version:\|^vermagic:\|^description:/&/p'
echo "OK ${SRC}/oxpec.ko"
