#!/usr/bin/env bash
# Overlay one InputPlumber YAML per catalogued model. Does not modify HHD.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEVICES_DIR="${OXP_DEVICES_DIR:-${ROOT}/kmod/devices}"
TEMPLATE="${ROOT}/kmod/inputplumber/50-onexplayer_local.yaml"
PREFIX="50-onexplayer-local-"
LEGACY_NAME="50-onexplayer_local.yaml"

if [[ "${EUID}" -ne 0 ]]; then
  echo "run as root" >&2
  exit 1
fi

if [[ -d /etc/inputplumber/devices ]]; then
  dest_dir="/etc/inputplumber/devices"
elif [[ -d /usr/share/inputplumber/devices ]]; then
  dest_dir="/usr/share/inputplumber/devices"
  if [[ ! -w "${dest_dir}" ]]; then
    if command -v ostree >/dev/null; then
      echo "unlocking ostree hotfix so /usr is writable"
      ostree admin unlock --hotfix
    else
      echo "cannot write ${dest_dir}" >&2
      exit 1
    fi
  fi
else
  echo "InputPlumber device dir not found" >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

render_args=(
  --template "${TEMPLATE}"
  --devices-dir "${DEVICES_DIR}"
  --out-dir "${tmp}"
)
if [[ -f "${ROOT}/kmod/local-device.env" ]]; then
  render_args+=(--env "${ROOT}/kmod/local-device.env")
fi
python3 "${ROOT}/kmod/scripts/render-inputplumber.py" "${render_args[@]}"

# Drop previous local overlays only (never official 50-onexplayer_*.yaml).
shopt -s nullglob
for stale in "${dest_dir}/${PREFIX}"*.yaml "${dest_dir}/${LEGACY_NAME}"; do
  rm -f "${stale}"
done
shopt -u nullglob

installed=()
for yaml in "${tmp}/${PREFIX}"*.yaml; do
  install -m 0644 "${yaml}" "${dest_dir}/$(basename "${yaml}")"
  installed+=("${dest_dir}/$(basename "${yaml}")")
done

hwdb_extra="/etc/udev/hwdb.d/61-oxp-local.hwdb"
install -m 0644 "${tmp}/61-oxp-local.hwdb" "${hwdb_extra}"
systemd-hwdb update
udevadm trigger -s dmi || true

systemctl restart inputplumber.service
for path in "${installed[@]}"; do
  echo "installed ${path}"
done
echo "installed ${hwdb_extra}"
echo "check: journalctl -u inputplumber -b --no-pager | tail"
