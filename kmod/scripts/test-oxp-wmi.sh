#!/usr/bin/env bash
# Hardware checks after insmod oxp-wmi. Safe to run before install.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
KO="${1:-${ROOT}/linux/oxp-wmi/oxp-wmi.ko}"
GUID="43B5A593-AD62-4257-8546-91B0797BEC1B"

echo "== source / module version =="
if [[ -d "${ROOT}/.git" ]]; then
  echo "git = $(git -C "${ROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown) $(git -C "${ROOT}" log -1 --pretty=%s 2>/dev/null || true)"
fi
if [[ -f "${ROOT}/linux/oxp-wmi/oxp-wmi.c" ]]; then
  if grep -q 'in_len_param' "${ROOT}/linux/oxp-wmi/oxp-wmi.c"; then
    echo "oxp-wmi.c has 32-byte in_len probe (0.2+)"
  else
    echo "oxp-wmi.c is the old 4-byte-only driver. git pull the PR branch and rebuild." >&2
    exit 1
  fi
fi

echo
echo "== module file =="
if [[ ! -f "${KO}" ]]; then
  echo "missing ${KO}; build first (kmod/scripts/build.sh oxp-wmi)" >&2
  exit 1
fi
modinfo "${KO}"
ver="$(modinfo -F version "${KO}" 2>/dev/null || true)"
parms="$(modinfo -F parm "${KO}" 2>/dev/null || true)"
echo "ko version = ${ver:-"(none)"}"
if ! grep -q '^in_len:' <<<"${parms}"; then
  echo >&2
  echo "This .ko is older than the 32-byte buffer patch (no in_len parm)." >&2
  echo "You are still testing the original driver. Rebuild after updating the tree:" >&2
  echo "  git fetch origin && git checkout cursor/oxp-kernel-module-research-0b45 && git pull" >&2
  echo "  kmod/scripts/build.sh oxp-wmi" >&2
  echo "  sudo rmmod oxp_wmi 2>/dev/null; sudo $0 ${KO}" >&2
  exit 1
fi

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
  for d in "${wmi_devs[@]}"; do
    echo "${d}"
    for f in object_id instance_count guid; do
      if [[ -e "${d}/${f}" ]]; then
        printf '  %-15s %s\n' "${f}" "$(tr -d '\n' <"${d}/${f}")"
      fi
    done
  done
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
if [[ -n "${OXP_WMI_IN_LEN:-}" ]]; then
  extra+=("in_len=${OXP_WMI_IN_LEN}")
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
zeros=0
for hw in /sys/class/hwmon/hwmon*; do
  name="$(cat "${hw}/name" 2>/dev/null || true)"
  if [[ "${name}" == oxp_wmi ]]; then
    found=1
    echo "found ${hw} (name=${name})"
    for attr in fan1_input pwm1 pwm1_enable temp1_input; do
      if [[ -e "${hw}/${attr}" ]]; then
        val="$(cat "${hw}/${attr}")"
        echo "  ${attr}=${val}"
        if [[ "${attr}" == temp1_input && "${val}" == 0 ]]; then
          zeros=1
        fi
      fi
    done
  fi
done
if [[ "${found}" -eq 0 ]]; then
  echo "oxp-wmi loaded but no hwmon. Probe failed; check dmesg / WMI GUID" >&2
  exit 1
fi

echo
echo "== debugfs last_info =="
shopt -s nullglob
infos=(/sys/kernel/debug/oxp-wmi-*/last_info)
shopt -u nullglob
if [[ ${#infos[@]} -eq 0 ]]; then
  echo "(no /sys/kernel/debug/oxp-wmi-*/last_info — is debugfs mounted?)"
else
  cat "${infos[0]}"
fi

if [[ "${zeros}" -eq 1 ]]; then
  echo
  echo "WARNING: temp1_input is 0. WMI succeeded but the EC payload is empty." >&2
  echo "Check dmesg for 'ReadECReg in=32/8/4' and last_info (ACPI type + raw bytes)." >&2
  echo "Override: sudo insmod ${KO} in_len=32   # MSI CreateByteField size" >&2
  exit 2
fi

echo
echo "oxp-wmi probe OK"
