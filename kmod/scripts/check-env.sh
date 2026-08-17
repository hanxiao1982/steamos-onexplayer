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

echo "== oxp 开发环境检查 ($(hostname)) =="

read_os
FLAVOR="$(detect_flavor)"
KREL="$(uname -r)"
KDIR="/lib/modules/${KREL}/build"

case "$FLAVOR" in
  bazzite) ok "发行版" "${PRETTY_NAME:-Bazzite} (bazzite)" ;;
  cachyos) ok "发行版" "${PRETTY_NAME:-CachyOS} (cachyos)" ;;
  *)
    if [[ "$COLLECT_ONLY" -eq 1 ]]; then
      warn "发行版" "${PRETTY_NAME:-unknown} ID=${ID:-}（采集 DMI 不依赖发行版）"
    else
      fail "发行版" "${PRETTY_NAME:-unknown} ID=${ID:-}（安装只支持 Bazzite / CachyOS）"
      note "可仍手动跑 install-bazzite.sh 或 install-cachyos.sh"
    fi
    ;;
esac
ok "内核" "$KREL"

# --- DMI (needed to add a model) ---
if [[ -r /sys/class/dmi/id/board_vendor && -r /sys/class/dmi/id/board_name ]]; then
  bv="$(tr -d '\n' < /sys/class/dmi/id/board_vendor)"
  bn="$(tr -d '\n' < /sys/class/dmi/id/board_name)"
  if [[ -z "$bv" || -z "$bn" || "$bv" == UNKNOWN || "$bn" == UNKNOWN ]]; then
    fail "DMI" "board_vendor/board_name 为空或 UNKNOWN"
    note "必须在真机上采集，不要在无 DMI 的虚拟机里 --add"
  else
    ok "DMI" "${bv} / ${bn}"
  fi
else
  fail "DMI" "/sys/class/dmi/id/{board_vendor,board_name} 不可读"
  note "必须在真机上采集"
fi

if has_cmd python3; then
  ok "python3" "$(python3 --version 2>&1)"
else
  fail "python3" "未安装（inject-dmi.py / collect-dmi.sh 需要）"
  if [[ "$FLAVOR" == cachyos ]]; then
    note "sudo pacman -S --needed python"
  elif [[ "$FLAVOR" == bazzite ]]; then
    note "镜像一般自带 python3；若在 toolbox 外缺失，先确认未切到精简环境"
  fi
fi

if [[ "$COLLECT_ONLY" -eq 1 ]]; then
  echo
  echo "模式: --collect-only（不检查编译工具链）"
  if [[ "$FAIL" -gt 0 ]]; then
    echo "结果: FAIL=${FAIL} WARN=${WARN}  — 还不能采集 DMI"
    exit 1
  fi
  echo "结果: OK WARN=${WARN}  — 可以 collect-dmi.sh --add"
  exit 0
fi

# --- fetch ---
oxpec=""
if [[ -n "$ROOT" && -f "${ROOT}/kmod/oxpec/oxpec.c" ]]; then
  oxpec="${ROOT}/kmod/oxpec/oxpec.c"
fi
if [[ -n "$oxpec" ]]; then
  ok "oxpec.c" "已有 ${oxpec}（不必访问 GitHub）"
else
  if has_cmd curl; then
    ok "curl" "$(command -v curl)"
    if curl -fsI --connect-timeout 5 --max-time 8 \
      https://raw.githubusercontent.com/torvalds/linux/master/README >/dev/null 2>&1; then
      ok "GitHub" "raw.githubusercontent.com 可达，fetch-oxpec.sh 能拉源码"
    else
      auto_or_fail "GitHub" "现在访问不了 raw.githubusercontent.com" \
        "有网再装，或在电脑上 fetch+inject 后 OXP_PUSH_SOURCE=1 push"
    fi
  else
    auto_or_fail "curl" "未安装，且本地没有 oxpec.c" \
      "CachyOS: sudo pacman -S curl；或从电脑 OXP_PUSH_SOURCE=1 推入源码"
  fi
fi

# --- toolchain ---
if has_cmd make; then
  ok "make" "$(command -v make)"
else
  if [[ "$FLAVOR" == cachyos ]]; then
    auto_or_fail "make" "未安装" "install-cachyos.sh 会装 base-devel"
  else
    fail "make" "未安装（编 oxpec.ko 需要）"
    note "Bazzite 需在带匹配 kernel-devel 的环境里有 make；不要只用 Fedora 官方 devel"
  fi
fi

need_clang=0
if [[ -f "${KDIR}/.config" ]] && grep -q '^CONFIG_CC_IS_CLANG=y' "${KDIR}/.config"; then
  need_clang=1
fi

if [[ "$need_clang" -eq 1 ]]; then
  if has_cmd clang; then
    ok "编译器" "clang $(clang --version 2>/dev/null | head -n1)（内核为 LLVM）"
  else
    fail "编译器" "内核 CONFIG_CC_IS_CLANG=y，但没有 clang"
    note "CachyOS: pacman -S clang llvm；或换 deckify（多为 GCC）"
  fi
else
  if has_cmd gcc; then
    ok "编译器" "gcc $(gcc -dumpversion 2>/dev/null)"
  elif [[ "$FLAVOR" == cachyos ]]; then
    auto_or_fail "编译器" "未找到 gcc" "install-cachyos.sh 会装 base-devel"
  else
    fail "编译器" "未找到 gcc"
    note "Bazzite 主机往往不带完整编译链；有 kernel-devel 时通常一起有"
  fi
fi

if [[ -d "$KDIR" && -e "${KDIR}/Makefile" ]]; then
  ok "内核头文件" "$KDIR"
  if [[ -f "${KDIR}/include/config/auto.conf" || -f "${KDIR}/.config" ]]; then
    ok "headers 完整" "build 树含 .config / auto.conf"
  else
    warn "headers 完整" "目录在，但缺少 .config（可能是断掉的符号链接）"
    note "重新安装与 uname -r 完全一致的 headers / kernel-devel"
  fi
else
  if [[ "$FLAVOR" == cachyos ]]; then
    auto_or_fail "内核头文件" "缺少 $KDIR" \
      "install-cachyos.sh 会 pacman -S linux-cachyos-deckify-headers；确认 uname -r 含 deckify"
  elif [[ "$FLAVOR" == bazzite ]]; then
    fail "内核头文件" "缺少 $KDIR"
    note "Bazzite 镜像常不带 kernel-devel。必须装与 ${KREL} 一致的 OGC kernel-devel，不要 layer 官方 Fedora"
    note "rpm -q kernel-devel kernel-devel-matched || true"
  else
    fail "内核头文件" "缺少 $KDIR"
  fi
fi

if has_cmd pahole; then
  ok "pahole" "$(command -v pahole)"
else
  if [[ "$FLAVOR" == cachyos ]]; then
    auto_or_fail "pahole" "未安装（部分内核编模块要 BTF）" "install-cachyos.sh 会装 pahole"
  else
    warn "pahole" "未安装；若 make 报 BTF / pahole 再补"
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
  fail "模块强制签名" "CONFIG_MODULE_SIG_FORCE=y：未签名 .ko 即使关掉 Secure Boot 也会被拒"
  note "只能用内核信任的密钥签名 oxpec.ko，或换不带 FORCE 的内核"
fi

sb_on=0
if has_cmd mokutil; then
  sb="$(mokutil --sb-state 2>/dev/null | head -n1 || true)"
  if printf '%s' "$sb" | grep -qi 'SecureBoot enabled'; then
    sb_on=1
    fail "Secure Boot" "${sb}"
    note "只编 oxpec.ko 不会带发行版签名。SB 开启时 insmod 报 Key was rejected / Required key not available"
    note "处理：固件关 SB，或用自己的 MOK 签名（ujust enroll-secure-boot-key 只登记发行版密钥，签不了你的 .ko）"
  else
    ok "Secure Boot" "${sb:-disabled / unknown}"
    if [[ "$sig" == y && "$sig_force" != y ]]; then
      ok "未签名模块" "SB 已关且未 FORCE，本地编的 oxpec.ko 可以 insmod"
    fi
  fi
else
  warn "Secure Boot" "没有 mokutil，无法探测；若固件开了 SB，未签名 .ko 会被拒"
fi

for ko in "${ROOT:+${ROOT}/kmod/oxpec/oxpec.ko}" /var/lib/oxp-kmod/oxpec.ko; do
  [[ -n "$ko" && -f "$ko" ]] || continue
  signer="$(modinfo -F signer "$ko" 2>/dev/null || true)"
  if [[ -n "$signer" ]]; then
    ok "已有 .ko 签名" "$(basename "$ko"): signer=${signer}"
  else
    if [[ "$sb_on" -eq 1 || "$sig_force" == y ]]; then
      warn "已有 .ko 签名" "$(basename "$ko"): 无 signer（当前策略会拒收）"
    else
      ok "已有 .ko 签名" "$(basename "$ko"): 未签名（当前策略允许）"
    fi
  fi
  break
done

# --- sudo ---
if [[ "${EUID}" -eq 0 ]]; then
  ok "sudo" "当前已是 root"
elif has_cmd sudo; then
  if sudo -n true >/dev/null 2>&1; then
    ok "sudo" "免密可用"
  else
    warn "sudo" "需要密码（ssh-handheld.sh 用 -t 可以交互输入）"
  fi
else
  fail "sudo" "没有 sudo，install / insmod 需要 root"
fi

# --- InputPlumber ---
if [[ -d /etc/inputplumber/devices || -d /usr/share/inputplumber/devices ]]; then
  ok "InputPlumber" "已有 devices 目录"
else
  if [[ "$FLAVOR" == cachyos ]]; then
    auto_or_fail "InputPlumber" "未找到 devices 目录" \
      "on-device-install.sh 会 pacman -S inputplumber"
  else
    warn "InputPlumber" "未找到 /etc 或 /usr/share 下的 devices 目录"
    note "Bazzite 镜像一般自带；若被卸掉，先装回 inputplumber"
  fi
fi

# --- in-tree oxpec ---
oxpec_cfg="$(kconfig_val CONFIG_OXPEC)"
if [[ "$oxpec_cfg" == y ]]; then
  warn "CONFIG_OXPEC" "CONFIG_OXPEC=y（编进内核，树外 .ko 换不掉）"
  note "只能走重编发行版内核；DMI-only 机型一般是 =m"
elif [[ -n "$oxpec_cfg" ]]; then
  ok "CONFIG_OXPEC" "CONFIG_OXPEC=${oxpec_cfg}"
fi

if [[ -e /var/lib/oxp-kmod/oxpec.ko ]]; then
  ok "已装模块" "/var/lib/oxp-kmod/oxpec.ko"
fi

if [[ -n "$ROOT" && -d "${ROOT}/kmod/devices" ]]; then
  echo "目录 ${ROOT}/kmod/devices:"
  ls -1 "${ROOT}/kmod/devices/"*.env 2>/dev/null | sed 's|.*/|  |' || echo "  (还没有型号 .env)"
fi

echo
if [[ "$FAIL" -gt 0 ]]; then
  echo "结果: FAIL=${FAIL} WARN=${WARN}  — 先补齐 [FAIL] 再 install"
  echo "说明: CachyOS 上标成 [WARN] 的 headers/make/gcc 可由 install-cachyos.sh 自动安装；Bazzite 缺 kernel-devel 必须先手动装。"
  exit 1
fi
echo "结果: OK WARN=${WARN}  — 可以继续 collect / install"
if [[ "$WARN" -gt 0 ]]; then
  echo "说明: [WARN] 不阻断；--strict 会把可自动补齐的缺口也当成失败。"
fi
exit 0
