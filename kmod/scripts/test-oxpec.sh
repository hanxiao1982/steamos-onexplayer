#!/usr/bin/env bash
# Hardware checks after insmod. Safe to run before install; fails clearly.
set -euo pipefail

KO="${1:-}"
if [[ -z "${KO}" ]]; then
  ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  KO="${ROOT}/kmod/oxpec/oxpec.ko"
fi

echo "== module file =="
if [[ ! -f "${KO}" ]]; then
  echo "missing ${KO}; build first" >&2
  exit 1
fi
modinfo "${KO}"

echo
echo "== running kernel =="
echo "uname -r = $(uname -r)"
if command -v modinfo >/dev/null; then
  running_magic="$(modinfo -F vermagic "${KO}" 2>/dev/null || true)"
  echo "ko vermagic = ${running_magic}"
fi

echo
echo "== DMI =="
for f in board_vendor board_name sys_vendor product_name; do
  printf '%-14s %s\n' "${f}" "$(tr -d '\n' <"/sys/class/dmi/id/${f}" 2>/dev/null || echo missing)"
done

echo
echo "== currently loaded oxpec =="
lsmod | grep -E '^oxpec' || echo "(not loaded)"

if [[ "${EUID}" -ne 0 ]]; then
  echo
  echo "Re-run as root to load and probe hwmon:"
  echo "  sudo $0 ${KO}"
  exit 0
fi

echo
echo "== load =="
modprobe -r oxpec 2>/dev/null || true
if ! insmod "${KO}"; then
  echo "insmod failed. Common causes:" >&2
  echo "  - vermagic mismatch (rebuild against THIS kernel's headers; not a signing issue)" >&2
  echo "  - unsigned .ko rejected: Secure Boot on, or CONFIG_MODULE_SIG_FORCE=y" >&2
  echo "  - in-tree oxpec is built-in (=y), cannot replace without a full kernel" >&2
  dmesg | tail -n 30
  exit 1
fi
lsmod | grep -E '^oxpec'

echo
echo "== dmesg (oxpec) =="
dmesg | grep -iE 'oxp|oxpec' | tail -n 20 || true

echo
echo "== hwmon =="
found=0
for hw in /sys/class/hwmon/hwmon*; do
  name="$(cat "${hw}/name" 2>/dev/null || true)"
  if [[ "${name}" == oxpec ]]; then
    found=1
    echo "found ${hw} (name=${name})"
    for attr in fan1_input pwm1 pwm1_enable; do
      if [[ -e "${hw}/${attr}" ]]; then
        echo "  ${attr}=$(cat "${hw}/${attr}")"
      fi
    done
  fi
done
if [[ "${found}" -eq 0 ]]; then
  echo "oxpec loaded but no hwmon. DMI did not match; check board_name vs local-device.env" >&2
  exit 1
fi

echo
echo "oxpec probe OK"
