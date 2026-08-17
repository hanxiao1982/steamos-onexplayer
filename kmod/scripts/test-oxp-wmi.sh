#!/usr/bin/env bash
# Hardware checks after insmod oxp-wmi. Safe to run before install.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
KO="${1:-${ROOT}/linux/oxp-wmi/oxp-wmi.ko}"
GUID="43B5A593-AD62-4257-8546-91B0797BEC1B"

echo "== module file =="
if [[ ! -f "${KO}" ]]; then
  echo "missing ${KO}; build first (kmod/scripts/build.sh oxp-wmi)" >&2
  exit 1
fi
modinfo "${KO}"

echo
echo "== running kernel =="
echo "uname -r = $(uname -r)"
echo "ko vermagic = $(modinfo -F vermagic "${KO}" 2>/dev/null || true)"
echo "ec-stack = $("${ROOT}/kmod/scripts/ec-stack.sh" detect)"

echo
echo "== DMI =="
for f in board_vendor board_name sys_vendor product_name; do
  printf '%-14s %s\n' "${f}" "$(tr -d '\n' <"/sys/class/dmi/id/${f}" 2>/dev/null || echo missing)"
done

echo
echo "== WMI GUID =="
shopt -s nullglob
wmi_devs=(/sys/bus/wmi/devices/${GUID}*)
shopt -u nullglob
if [[ ${#wmi_devs[@]} -eq 0 ]]; then
  echo "no ${GUID} under /sys/bus/wmi/devices (not an OxpWMI firmware, or WMI not up)"
else
  printf '%s\n' "${wmi_devs[@]}"
fi

echo
echo "== currently loaded oxp_wmi =="
lsmod | grep -E '^oxp_wmi' || echo "(not loaded)"

if [[ "${EUID}" -ne 0 ]]; then
  echo
  echo "Re-run as root to load and probe hwmon:"
  echo "  sudo $0 ${KO}"
  exit 0
fi

echo
echo "== load =="
modprobe -r oxp_wmi 2>/dev/null || true
extra=()
if [[ "${OXP_WMI_FORCE:-0}" == 1 ]]; then
  extra+=(force=1)
fi
if ! insmod "${KO}" "${extra[@]+"${extra[@]}"}"; then
  echo "insmod failed. Common causes:" >&2
  echo "  - vermagic mismatch (rebuild against THIS kernel's headers)" >&2
  echo "  - unsigned .ko rejected: Secure Boot on, or CONFIG_MODULE_SIG_FORCE=y" >&2
  echo "  - CONFIG_ACPI_WMI=n, or this SKU is AMD (use oxpec, not oxp-wmi)" >&2
  echo "  - DMI deny (X2Mini PRO / APEX): OXP_WMI_FORCE=1 to override" >&2
  dmesg | tail -n 30
  exit 1
fi
lsmod | grep -E '^oxp_wmi'

echo
echo "== dmesg (oxp-wmi) =="
dmesg | grep -iE 'oxp-wmi|oxp_wmi' | tail -n 20 || true

echo
echo "== hwmon =="
found=0
for hw in /sys/class/hwmon/hwmon*; do
  name="$(cat "${hw}/name" 2>/dev/null || true)"
  if [[ "${name}" == oxp_wmi ]]; then
    found=1
    echo "found ${hw} (name=${name})"
    for attr in fan1_input pwm1 pwm1_enable temp1_input; do
      if [[ -e "${hw}/${attr}" ]]; then
        echo "  ${attr}=$(cat "${hw}/${attr}")"
      fi
    done
  fi
done
if [[ "${found}" -eq 0 ]]; then
  echo "oxp-wmi loaded but no hwmon. Probe failed; check dmesg / WMI GUID" >&2
  exit 1
fi

echo
echo "oxp-wmi probe OK"
