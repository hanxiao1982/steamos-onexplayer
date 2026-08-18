#!/usr/bin/env bash
# Build oxpec.ko and/or oxp-wmi.ko against the running kernel.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
KREL="${KERNELRELEASE:-$(uname -r)}"
KDIR="${KDIR:-/lib/modules/${KREL}/build}"
STACK="${1:-auto}"

if [[ "$STACK" == auto ]]; then
  STACK="$("${ROOT}/kmod/scripts/ec-stack.sh" detect)"
fi

case "$STACK" in
  oxpec|oxp-wmi|all) ;;
  *)
    echo "usage: $0 [auto|oxpec|oxp-wmi|all]" >&2
    exit 2
    ;;
esac

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

build_one() {
  local src="$1" ko="$2" label="$3"
  if [[ ! -f "${src}/$(basename "${ko}" .ko).c" && ! -f "${src}/${label}.c" ]]; then
    echo "missing source in ${src}" >&2
    exit 1
  fi
  echo "Building ${label}.ko for ${KREL} from ${src}"
  make -C "${KDIR}" M="${src}" KERNELRELEASE="${KREL}" "${MAKE_ARGS[@]}" modules
  modinfo "${src}/${label}.ko" | sed -n 's/^filename:\|^version:\|^vermagic:\|^description:/&/p'
  echo "OK ${src}/${label}.ko"
}

if [[ "$STACK" == oxpec || "$STACK" == all ]]; then
  if [[ ! -f "${ROOT}/kmod/oxpec/oxpec.c" ]]; then
    echo "oxpec.c missing; run kmod/scripts/fetch-oxpec.sh first" >&2
    exit 1
  fi
  build_one "${ROOT}/kmod/oxpec" oxpec.ko oxpec
fi

if [[ "$STACK" == oxp-wmi || "$STACK" == all ]]; then
  if [[ ! -f "${ROOT}/linux/oxp-wmi/oxp-wmi.c" ]]; then
    echo "linux/oxp-wmi/oxp-wmi.c missing" >&2
    exit 1
  fi
  build_one "${ROOT}/linux/oxp-wmi" oxp-wmi.ko oxp-wmi
fi
