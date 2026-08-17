#!/usr/bin/env bash
# Run on the handheld (usually via ssh -t … sudo). Detects Bazzite vs CachyOS.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

if [[ "${EUID}" -ne 0 ]]; then
  echo "run as root on the handheld (sudo $0)" >&2
  exit 1
fi

if [[ -r /usr/lib/os-release ]]; then
  # shellcheck disable=SC1091
  . /usr/lib/os-release
elif [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
else
  echo "cannot read os-release" >&2
  exit 1
fi

id_lc="$(printf '%s' "${ID:-} ${ID_LIKE:-} ${NAME:-}" | tr '[:upper:]' '[:lower:]')"

if [[ "$id_lc" == *bazzite* ]] || [[ -f /usr/share/ublue-os/image-info.json ]]; then
  echo "detected Bazzite (${PRETTY_NAME:-unknown})"
  "${ROOT}/kmod/scripts/install-bazzite.sh"
elif [[ "$id_lc" == *cachyos* ]]; then
  echo "detected CachyOS (${PRETTY_NAME:-unknown})"
  "${ROOT}/kmod/scripts/install-cachyos.sh"
  pacman -S --needed --noconfirm inputplumber
else
  echo "unknown distro: ID=${ID:-} NAME=${NAME:-}" >&2
  echo "run install-bazzite.sh or install-cachyos.sh yourself" >&2
  exit 1
fi

"${ROOT}/kmod/scripts/install-inputplumber.sh"
echo "on-device install finished"
