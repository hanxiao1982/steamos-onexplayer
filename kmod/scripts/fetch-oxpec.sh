#!/usr/bin/env bash
# Download oxpec.c. Default is mainline; use ogc for Bazzite-closer tree.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEST="${ROOT}/kmod/oxpec/oxpec.c"
STATE="${ROOT}/kmod/oxpec/.applied-patches"
SRC="${1:-mainline}"

case "$SRC" in
  mainline)
    URL="https://raw.githubusercontent.com/torvalds/linux/master/drivers/platform/x86/oxpec.c"
    ;;
  ogc)
    URL="https://raw.githubusercontent.com/OpenGamingCollective/linux/features/onexplayer/drivers/platform/x86/oxpec.c"
    ;;
  cachyos)
    URL="https://raw.githubusercontent.com/CachyOS/linux/master/drivers/platform/x86/oxpec.c"
    ;;
  *)
    echo "usage: $0 [mainline|ogc|cachyos]" >&2
    exit 2
    ;;
esac

echo "Fetching ${SRC} -> ${DEST}"
curl -fsSL -o "${DEST}" "${URL}"
rm -f "${STATE}"
wc -l "${DEST}"
