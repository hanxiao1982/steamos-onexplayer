#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OXP_DIR="${ROOT}/kmod/oxpec"
SERIES="${OXP_DIR}/patches/series"
SOURCE="${OXP_DIR}/oxpec.c"

if [[ ! -f "${SOURCE}" ]]; then
  echo "${SOURCE} missing; run kmod/scripts/fetch-oxpec.sh mainline first" >&2
  exit 1
fi

if [[ ! -f "${SERIES}" ]]; then
  echo "patch series missing: ${SERIES}" >&2
  exit 1
fi

while IFS= read -r patch_name; do
  [[ -z "${patch_name}" || "${patch_name}" == \#* ]] && continue
  patch_file="${OXP_DIR}/patches/${patch_name}"
  if [[ ! -f "${patch_file}" ]]; then
    echo "missing patch: ${patch_file}" >&2
    exit 1
  fi

  echo "Applying ${patch_name}"
  # The repository stores mail-style patches for a kernel-tree path
  # (drivers/platform/x86/oxpec.c), while the fetched test source lives at
  # kmod/oxpec/oxpec.c.  -p4 removes a/drivers/platform/x86/ and --directory
  # redirects the result to the local out-of-tree test directory.
  #
  # --recount deliberately derives hunk sizes from the actual patch body.
  # This also makes the local test runner robust against stale hunk line-count
  # metadata while retaining normal context validation.
  git -C "${ROOT}" apply --recount --verbose --whitespace=nowarn \
    -p4 --directory=kmod/oxpec "${patch_file}"
done < "${SERIES}"

echo "Applied oxpec patch series to ${SOURCE}"
