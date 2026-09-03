#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OXP_DIR="${ROOT}/kmod/oxpec"
SERIES="${OXP_DIR}/patches/series"
SOURCE="${OXP_DIR}/oxpec.c"
STATE="${OXP_DIR}/.applied-patches"
LIMIT="${1:-all}"

usage() {
  cat >&2 <<EOF
usage: $0 [N|all]

Apply the oxpec patch series through patch N.
With no argument (or 'all'), apply the complete series.

Examples:
  $0       # apply all patches
  $0 1     # apply through patch 1
  $0 2     # apply through patch 2
  $0 3     # apply through patch 3
EOF
}

if [[ $# -gt 1 ]]; then
  usage
  exit 2
fi

if [[ ! -f "${SOURCE}" ]]; then
  echo "${SOURCE} missing; run kmod/scripts/fetch-oxpec.sh mainline first" >&2
  exit 1
fi

if [[ ! -f "${SERIES}" ]]; then
  echo "patch series missing: ${SERIES}" >&2
  exit 1
fi

mapfile -t PATCHES < <(grep -Ev '^[[:space:]]*(#|$)' "${SERIES}")
TOTAL="${#PATCHES[@]}"

if [[ "${TOTAL}" -eq 0 ]]; then
  echo "patch series is empty: ${SERIES}" >&2
  exit 1
fi

if [[ "${LIMIT}" == "all" ]]; then
  STOP="${TOTAL}"
elif [[ "${LIMIT}" =~ ^[0-9]+$ ]] && (( LIMIT >= 1 && LIMIT <= TOTAL )); then
  STOP="${LIMIT}"
else
  echo "invalid patch limit '${LIMIT}'; expected 1-${TOTAL} or all" >&2
  usage
  exit 2
fi

apply_args=(
  --recount
  --whitespace=nowarn
  -p4
  --directory=kmod/oxpec
)

touch "${STATE}"

for ((i = 0; i < STOP; i++)); do
  patch_name="${PATCHES[$i]}"
  patch_file="${OXP_DIR}/patches/${patch_name}"

  if [[ ! -f "${patch_file}" ]]; then
    echo "missing patch: ${patch_file}" >&2
    exit 1
  fi

  printf 'Patch %d/%d: %s\n' "$((i + 1))" "${TOTAL}" "${patch_name}"

  if grep -Fxq "${patch_name}" "${STATE}"; then
    echo "  already applied; skipping"
    continue
  fi

  # Backward-compatible detection for a source patched before the state file
  # existed. This only needs to recognize the immediately current patch;
  # once recognized it is recorded so later patches can modify overlapping
  # context without breaking staged re-entry.
  if git -C "${ROOT}" apply "${apply_args[@]}" --reverse --check "${patch_file}" \
      >/dev/null 2>&1; then
    echo "  already applied; recording state"
    printf '%s\n' "${patch_name}" >> "${STATE}"
    continue
  fi

  # The repository stores mail-style patches for the kernel-tree path
  # drivers/platform/x86/oxpec.c, while the fetched test source lives at
  # kmod/oxpec/oxpec.c. -p4 removes a/drivers/platform/x86/ and --directory
  # redirects the result to the local out-of-tree test directory.
  git -C "${ROOT}" apply "${apply_args[@]}" --verbose "${patch_file}"
  printf '%s\n' "${patch_name}" >> "${STATE}"
done

if (( STOP < TOTAL )); then
  echo "Applied oxpec patch series through patch ${STOP}/${TOTAL}; stopping for staged testing."
else
  echo "Applied complete oxpec patch series (${TOTAL}/${TOTAL}) to ${SOURCE}"
fi
