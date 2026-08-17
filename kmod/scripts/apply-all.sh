#!/usr/bin/env bash
# Re-apply the whole device catalog onto oxpec.c, then build.
# Safe after adding another model, and after a fresh fetch (which wipes injections).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FETCH=""
LIST=0
INJECT_ONLY=0

usage() {
  cat <<'EOF'
Usage:
  apply-all.sh                 Inject every kmod/devices/*.env, then build
  apply-all.sh --fetch [src]   Refetch oxpec.c first (mainline|ogc|cachyos), then inject all
  apply-all.sh --list          Show the catalog without writing oxpec.c
  apply-all.sh --inject-only   Inject only (skip build; useful after --fetch)

Adding a second (or Nth) handheld:
  1. On that machine:  kmod/scripts/collect-dmi.sh --add
  2. Copy the new kmod/devices/<slug>.env back into this repo (keep the old ones)
  3. Run this script. Do not edit a single local-device.env in place.

--fetch is the safe way to update the upstream source: fetch wipes oxpec.c,
then this script puts every catalogued DMI back.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fetch)
      if [[ $# -ge 2 && "$2" != --* ]]; then
        FETCH="$2"
        shift 2
      else
        FETCH="mainline"
        shift
      fi
      ;;
    --list)
      LIST=1
      shift
      ;;
    --inject-only)
      INJECT_ONLY=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$LIST" -eq 1 ]]; then
  "${ROOT}/kmod/scripts/inject-catalog.sh" --list
  exit 0
fi

if [[ -n "$FETCH" ]]; then
  "${ROOT}/kmod/scripts/fetch-oxpec.sh" "$FETCH"
fi

if [[ ! -f "${ROOT}/kmod/oxpec/oxpec.c" ]]; then
  echo "oxpec.c missing; pass --fetch mainline|ogc|cachyos" >&2
  exit 1
fi

"${ROOT}/kmod/scripts/inject-catalog.sh"

if [[ "$INJECT_ONLY" -eq 1 ]]; then
  echo "inject-only: skip build"
  exit 0
fi

"${ROOT}/kmod/scripts/build.sh"
echo
echo "Next: sudo kmod/scripts/test-oxpec.sh kmod/oxpec/oxpec.ko"
echo "      sudo kmod/scripts/install-common.sh"
echo "      sudo kmod/scripts/install-inputplumber.sh"
