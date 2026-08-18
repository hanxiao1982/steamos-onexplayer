#!/usr/bin/env bash
# Probe this machine for DMI collection and out-of-tree oxpec builds.
# Safe to run as a normal user. Exit 1 if anything required is missing.
set -u

COLLECT_ONLY=0
STRICT=0
FAIL=0
WARN=0

usage() {
  cat <<'EOF'
Usage:
  check-env.sh                 Full build/install readiness
  check-env.sh --collect-only  Only DMI + python (for collect-dmi.sh)
  check-env.sh --strict        Treat auto-fixable gaps as failures

Run on the handheld. ssh-handheld.sh check pipes this over SSH.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --collect-only) COLLECT_ONLY=1; shift ;;
    --strict) STRICT=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

ROOT=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

ok()   { printf '[OK]   %-18s %s\n' "$1" "$2"; }
warn() { printf '[WARN] %-18s %s\n' "$1" "$2"; WARN=$((WARN + 1)); }
fail() { printf '[FAIL] %-18s %s\n' "$1" "$2"; FAIL=$((FAIL + 1)); }
note() { printf '       %-18s %s\n' "" "$1"; }

auto_or_fail() {
  # $1 title $2 detail $3 hint — WARN unless --strict
  if [[ "$STRICT" -eq 1 ]]; then
    fail "$1" "$2"
  else
    warn "$1" "$2"
  fi
  note "$3"
}

read_os() {
  if [[ -r /usr/lib/os-release ]]; then
    # shellcheck disable=SC1091
    . /usr/lib/os-release
  elif [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
  else
    ID=""
    NAME=""
    PRETTY_NAME=""
    ID_LIKE=""
  fi
}

detect_flavor() {
  local blob
  blob="$(printf '%s' "${ID:-} ${ID_LIKE:-} ${NAME:-}" | tr '[:upper:]' '[:lower:]')"
  if [[ "$blob" == *bazzite* ]] || [[ -f /usr/share/ublue-os/image-info.json ]]; then
    echo bazzite
  elif [[ "$blob" == *cachyos* ]]; then
    echo cachyos
  else
    echo unknown
  fi
}

has_cmd() { command -v "$1" >/dev/null 2>&1; }

echo "== oxp build-environment check ($(hostname)) =="

read_os
FLAVOR="$(detect_flavor)"
KREL="$(uname -r)"
KDIR="/lib/modules/${KREL}/build"

case "$FLAVOR" in
  bazzite) ok "distro" "${PRETTY_NAME:-Bazzite} (bazzite)" ;;
  cachyos) ok "distro" "${PRETTY_NAME:-CachyOS} (cachyos)" ;;
  *)
    if [[ "$COLLECT_ONLY" -eq 1 ]]; then
      warn "distro" "${PRETTY_NAME:-unknown} ID=${ID:-} (DMI collect does not require a distro)"
    else
      fail "distro" "${PRETTY_NAME:-unknown} ID=${ID:-} (install supports Bazzite / CachyOS only)"
      note "you can still run install-bazzite.sh or install-cachyos.sh by hand"
    fi
    ;;
esac
ok "kernel" "$KREL"

EC_STACK="oxpec"
if [[ -n "${OXP_EC_STACK:-}" ]]; then
  EC_STACK="$OXP_EC_STACK"
elif [[ -n "$ROOT" && -x "${ROOT}/kmod/scripts/ec-stack.sh" ]]; then
  EC_STACK="$("${ROOT}/kmod/scripts/ec-stack.sh" detect)"
else
  _pn="$(tr -d '\n' < /sys/class/dmi/id/product_name 2>/dev/null || true)"
  _bn="$(tr -d '\n' < /sys/class/dmi/id/board_name 2>/dev/null || true)"
  case "$_pn" in
    "ONEXPLAYER X2Mini PRO"|"ONEXPLAYER APEX") EC_STACK=oxpec ;;
    "ONEXPLAYER X2Mini"|"ONEXPLAYER X2"|"ONEXPLAYER X2 EVA"|"ONEXPLAYER 3"|"ONEXPLAYER Apex Air"|"ONEXPLAYER Apex i")
      EC_STACK=oxp-wmi ;;
  esac
  if [[ "$EC_STACK" == oxpec ]]; then
    case "$_bn" in
      "ONEXPLAYER X2Mini"|"ONEXPLAYER X2"|"ONEXPLAYER X2 EVA"|"ONEXPLAYER 3"|"ONEXPLAYER Apex Air"|"ONEXPLAYER Apex i")
        EC_STACK=oxp-wmi ;;
    esac
  fi
fi
ok "EC stack" "$EC_STACK (oxp-wmi=Intel X2 Mini / G3E; oxpec=AMD ACPI EC)"

# --- DMI (needed to add a model) ---
if [[ -r /sys/class/dmi/id/board_vendor && -r /sys/class/dmi/id/board_name ]]; then
  bv="$(tr -d '\n' < /sys/class/dmi/id/board_vendor)"
  bn="$(tr -d '\n' < /sys/class/dmi/id/board_name)"
  if [[ -z "$bv" || -z "$bn" || "$bv" == UNKNOWN || "$bn" == UNKNOWN ]]; then
    fail "DMI" "board_vendor/board_name empty or UNKNOWN"
    note "collect on the handheld; do not --add in a VM without DMI"
  else
    ok "DMI" "${bv} / ${bn}"
  fi
else
  fail "DMI" "/sys/class/dmi/id/{board_vendor,board_name} not readable"
  note "collect on the handheld"
fi

if has_cmd python3; then
  ok "python3" "$(python3 --version 2>&1)"
else
  fail "python3" "not installed (needed by inject-dmi.py / collect-dmi.sh)"
  if [[ "$FLAVOR" == cachyos ]]; then
    note "sudo pacman -S --needed python"
  elif [[ "$FLAVOR" == bazzite ]]; then
    note "the image usually ships python3; if missing outside toolbox, check the environment"
  fi
fi

if [[ "$COLLECT_ONLY" -eq 1 ]]; then
  echo
  echo "mode: --collect-only (toolchain not checked)"
  if [[ "$FAIL" -gt 0 ]]; then
    echo "result: FAIL=${FAIL} WARN=${WARN}  — cannot collect DMI yet"
    exit 1
  fi
  echo "result: OK WARN=${WARN}  — collect-dmi.sh --add is ready"
  exit 0
fi

# --- sources ---
if [[ "$EC_STACK" == oxp-wmi ]]; then
  if [[ -n "$ROOT" && -f "${ROOT}/linux/oxp-wmi/oxp-wmi.c" ]]; then
    ok "oxp-wmi.c" "${ROOT}/linux/oxp-wmi/oxp-wmi.c (in-repo source; no fetch)"
  else
    fail "oxp-wmi.c" "missing linux/oxp-wmi/oxp-wmi.c; push the full repo first"
  fi
else
  oxpec=""
  if [[ -n "$ROOT" && -f "${ROOT}/kmod/oxpec/oxpec.c" ]]; then
    oxpec="${ROOT}/kmod/oxpec/oxpec.c"
  fi
  if [[ -n "$oxpec" ]]; then
    ok "oxpec.c" "present at ${oxpec} (no GitHub needed)"
  else
    if has_cmd curl; then
      ok "curl" "$(command -v curl)"
      if curl -fsI --connect-timeout 5 --max-time 8 \
        https://raw.githubusercontent.com/torvalds/linux/master/README >/dev/null 2>&1; then
        ok "GitHub" "raw.githubusercontent.com reachable; fetch-oxpec.sh can pull source"
      else
        auto_or_fail "GitHub" "cannot reach raw.githubusercontent.com" \
          "install when online, or fetch+inject on a PC then OXP_PUSH_SOURCE=1 push"
      fi
    else
      auto_or_fail "curl" "not installed and oxpec.c is missing" \
        "CachyOS: sudo pacman -S curl; or OXP_PUSH_SOURCE=1 push from a PC"
    fi
  fi
fi

# --- toolchain ---
if has_cmd make; then
  ok "make" "$(command -v make)"
else
  if [[ "$FLAVOR" == cachyos ]]; then
    auto_or_fail "make" "not installed" "install-cachyos.sh will install base-devel"
  else
    fail "make" "not installed (needed to build the module)"
    note "Bazzite needs make next to matching kernel-devel; do not use stock Fedora devel alone"
  fi
fi

need_clang=0
if [[ -f "${KDIR}/.config" ]] && grep -q '^CONFIG_CC_IS_CLANG=y' "${KDIR}/.config"; then
  need_clang=1
fi

if [[ "$need_clang" -eq 1 ]]; then
  if has_cmd clang; then
    ok "compiler" "clang $(clang --version 2>/dev/null | head -n1) (LLVM kernel)"
  else
    fail "compiler" "kernel is CONFIG_CC_IS_CLANG=y but clang is missing"
    note "CachyOS: pacman -S clang llvm; or use deckify (usually GCC)"
  fi
else
  if has_cmd gcc; then
    ok "compiler" "gcc $(gcc -dumpversion 2>/dev/null)"
  elif [[ "$FLAVOR" == cachyos ]]; then
    auto_or_fail "compiler" "gcc not found" "install-cachyos.sh will install base-devel"
  else
    fail "compiler" "gcc not found"
    note "Bazzite hosts often lack a full toolchain; kernel-devel usually brings it"
  fi
fi

if [[ -d "$KDIR" && -e "${KDIR}/Makefile" ]]; then
  ok "kernel headers" "$KDIR"
  if [[ -f "${KDIR}/include/config/auto.conf" || -f "${KDIR}/.config" ]]; then
    ok "headers complete" "build tree has .config / auto.conf"
  else
    warn "headers complete" "directory exists but .config is missing (broken symlink?)"
    note "reinstall headers / kernel-devel that match uname -r exactly"
  fi
else
  if [[ "$FLAVOR" == cachyos ]]; then
    auto_or_fail "kernel headers" "missing $KDIR" \
      "install-cachyos.sh will pacman -S linux-cachyos-deckify-headers; uname -r should contain deckify"
  elif [[ "$FLAVOR" == bazzite ]]; then
    fail "kernel headers" "missing $KDIR"
    note "Bazzite images often omit kernel-devel. Install the OGC kernel-devel for ${KREL}; do not layer stock Fedora"
    note "rpm -q kernel-devel kernel-devel-matched || true"
  else
    fail "kernel headers" "missing $KDIR"
  fi
fi

if has_cmd pahole; then
  ok "pahole" "$(command -v pahole)"
else
  if [[ "$FLAVOR" == cachyos ]]; then
    auto_or_fail "pahole" "not installed (some kernels need BTF)" "install-cachyos.sh will install pahole"
  else
    warn "pahole" "not installed; add it if make complains about BTF / pahole"
  fi
fi

kconfig_val() {
  local key="$1" line=""
  if [[ -r "/lib/modules/${KREL}/config" ]]; then
    line="$(grep -E "^${key}=" "/lib/modules/${KREL}/config" || true)"
  elif [[ -r /proc/config.gz ]]; then
    line="$(zgrep -E "^${key}=" /proc/config.gz || true)"
  elif [[ -r "${KDIR}/.config" ]]; then
    line="$(grep -E "^${key}=" "${KDIR}/.config" || true)"
  fi
  printf '%s' "${line#${key}=}"
}

# --- signing: unsigned out-of-tree .ko vs running kernel ---
# Compiling only oxpec.ko does not inherit the distro kernel's signature.
sig="$(kconfig_val CONFIG_MODULE_SIG)"
sig_force="$(kconfig_val CONFIG_MODULE_SIG_FORCE)"
sig_all="$(kconfig_val CONFIG_MODULE_SIG_ALL)"
if [[ -n "$sig" || -n "$sig_force" ]]; then
  ok "MODULE_SIG" "CONFIG_MODULE_SIG=${sig:-n} FORCE=${sig_force:-n} ALL=${sig_all:-n}"
fi
if [[ "$sig_force" == y ]]; then
  fail "forced module sig" "CONFIG_MODULE_SIG_FORCE=y: unsigned .ko is rejected even with Secure Boot off"
  note "sign oxpec.ko with a key the kernel trusts, or use a kernel without FORCE"
fi

sb_on=0
if has_cmd mokutil; then
  sb="$(mokutil --sb-state 2>/dev/null | head -n1 || true)"
  if printf '%s' "$sb" | grep -qi 'SecureBoot enabled'; then
    sb_on=1
    fail "Secure Boot" "${sb}"
    note "a local oxpec.ko is not distro-signed. With SB on, insmod reports Key was rejected / Required key not available"
    note "fix: disable SB in firmware, or sign with your own MOK (ujust enroll-secure-boot-key only enrolls the distro key)"
  else
    ok "Secure Boot" "${sb:-disabled / unknown}"
    if [[ "$sig" == y && "$sig_force" != y ]]; then
      ok "unsigned module" "SB off and FORCE off; local oxpec.ko can insmod"
    fi
  fi
else
  warn "Secure Boot" "mokutil missing; if firmware has SB on, unsigned .ko will be rejected"
fi

for ko in "${ROOT:+${ROOT}/kmod/oxpec/oxpec.ko}" /var/lib/oxp-kmod/oxpec.ko; do
  [[ -n "$ko" && -f "$ko" ]] || continue
  signer="$(modinfo -F signer "$ko" 2>/dev/null || true)"
  if [[ -n "$signer" ]]; then
    ok "existing .ko sig" "$(basename "$ko"): signer=${signer}"
  else
    if [[ "$sb_on" -eq 1 || "$sig_force" == y ]]; then
      warn "existing .ko sig" "$(basename "$ko"): no signer (current policy will reject it)"
    else
      ok "existing .ko sig" "$(basename "$ko"): unsigned (current policy allows it)"
    fi
  fi
  break
done

# --- sudo ---
if [[ "${EUID}" -eq 0 ]]; then
  ok "sudo" "already root"
elif has_cmd sudo; then
  if sudo -n true >/dev/null 2>&1; then
    ok "sudo" "passwordless"
  else
    warn "sudo" "needs a password (ssh-handheld.sh uses -t for interactive input)"
  fi
else
  fail "sudo" "sudo missing; install / insmod need root"
fi

# --- InputPlumber ---
if [[ -d /etc/inputplumber/devices || -d /usr/share/inputplumber/devices ]]; then
  ok "InputPlumber" "devices directory present"
else
  if [[ "$FLAVOR" == cachyos ]]; then
    auto_or_fail "InputPlumber" "devices directory not found" \
      "on-device-install.sh will pacman -S inputplumber"
  else
    warn "InputPlumber" "no devices dir under /etc or /usr/share"
    note "Bazzite images usually ship it; reinstall inputplumber if it was removed"
  fi
fi

# --- in-tree oxpec ---
if [[ "$EC_STACK" == oxp-wmi ]]; then
  wmi_cfg="$(kconfig_val CONFIG_ACPI_WMI)"
  if [[ "$wmi_cfg" == n ]]; then
    fail "CONFIG_ACPI_WMI" "n (oxp-wmi needs ACPI WMI)"
  elif [[ -n "$wmi_cfg" ]]; then
    ok "CONFIG_ACPI_WMI" "CONFIG_ACPI_WMI=${wmi_cfg}"
  else
    warn "CONFIG_ACPI_WMI" "cannot read kernel config"
  fi
  shopt -s nullglob
  wmi_devs=(/sys/bus/wmi/devices/43B5A593-AD62-4257-8546-91B0797BEC1B*)
  shopt -u nullglob
  if [[ ${#wmi_devs[@]} -gt 0 ]]; then
    ok "OxpWMI GUID" "${wmi_devs[0]}"
  else
    warn "OxpWMI GUID" "no 43B5A593-AD62-4257-8546-91B0797BEC1B (not X2 Mini firmware, or WMI is down)"
  fi
  if [[ -e /var/lib/oxp-kmod/oxp-wmi.ko ]]; then
    ok "installed module" "/var/lib/oxp-kmod/oxp-wmi.ko"
  fi
else
  oxpec_cfg="$(kconfig_val CONFIG_OXPEC)"
  if [[ "$oxpec_cfg" == y ]]; then
    warn "CONFIG_OXPEC" "CONFIG_OXPEC=y (built-in; out-of-tree .ko cannot replace it)"
    note "only a distro kernel rebuild can replace it; DMI-only SKUs are usually =m"
  elif [[ -n "$oxpec_cfg" ]]; then
    ok "CONFIG_OXPEC" "CONFIG_OXPEC=${oxpec_cfg}"
  fi
  if [[ -e /var/lib/oxp-kmod/oxpec.ko ]]; then
    ok "installed module" "/var/lib/oxp-kmod/oxpec.ko"
  fi
fi

if [[ -n "$ROOT" && -d "${ROOT}/kmod/devices" ]]; then
  echo "catalog ${ROOT}/kmod/devices:"
  ls -1 "${ROOT}/kmod/devices/"*.env 2>/dev/null | sed 's|.*/|  |' || echo "  (no model .env yet)"
fi

echo
if [[ "$FAIL" -gt 0 ]]; then
  echo "result: FAIL=${FAIL} WARN=${WARN}  — fix [FAIL] items before install"
  echo "note: CachyOS [WARN] headers/make/gcc can be installed by install-cachyos.sh; Bazzite kernel-devel must be layered by hand."
  exit 1
fi
echo "result: OK WARN=${WARN}  — collect / install can continue"
if [[ "$WARN" -gt 0 ]]; then
  echo "note: [WARN] does not block; --strict treats auto-fixable gaps as failures."
fi
exit 0
