#!/usr/bin/env bash
# Inject every kmod/devices/*.env (plus optional local-device.env) into oxpec.c.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OXPEC="${ROOT}/kmod/oxpec/oxpec.c"
DEVICES_DIR="${OXP_DEVICES_DIR:-${ROOT}/kmod/devices}"

if [[ ! -f "${OXPEC}" ]]; then
  echo "oxpec.c missing; run kmod/scripts/fetch-oxpec.sh first" >&2
  exit 1
fi

args=(--oxpec "${OXPEC}" --devices-dir "${DEVICES_DIR}")
if [[ -f "${ROOT}/kmod/local-device.env" ]]; then
  args+=(--env "${ROOT}/kmod/local-device.env")
fi
# Extra --env paths from the caller
while [[ $# -gt 0 ]]; do
  case "$1" in
    --list)
      args+=(--list)
      shift
      ;;
    --env)
      args+=(--env "$2")
      shift 2
      ;;
    *)
      echo "usage: $0 [--list] [--env FILE]..." >&2
      exit 2
      ;;
  esac
done

exec python3 "${ROOT}/kmod/scripts/inject-dmi.py" "${args[@]}"
