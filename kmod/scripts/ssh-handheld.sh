#!/usr/bin/env bash
# Copy this repo to a handheld over SSH and run collect / install / pull-back.
# Run from a PC that already has the repo. The handheld only needs sshd + sudo.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REMOTE_NAME="${OXP_REMOTE_DIR:-steamos-onexplayer}"
SSH_OPTS=(${OXP_SSH_OPTS:-})

usage() {
  cat <<'EOF'
Usage (on your PC, not on the handheld):
  ssh-handheld.sh user@host push
  ssh-handheld.sh user@host collect [--add [slug]] [--force]
  ssh-handheld.sh user@host pull-devices
  ssh-handheld.sh user@host install
  ssh-handheld.sh user@host status
  ssh-handheld.sh user@host all              # push + collect --add + install + pull-devices
  ssh-handheld.sh user@host run -- <cmd>     # remote shell in the copied repo

Environment:
  OXP_SSH_OPTS        Extra ssh/scp options, e.g. '-p 22 -i ~/.ssh/id_ed25519'
  OXP_REMOTE_DIR      Directory name under $HOME (default: steamos-onexplayer)
                      Absolute path is also accepted.
  OXP_BOARD_VARIANT   Passed to collect-dmi.sh (default on device: oxp_fly)
  OXP_CAP_MAP         Passed to collect-dmi.sh (default: oxp8)
  OXP_PUSH_SOURCE=1   Also copy kmod/oxpec/oxpec.c (handheld cannot reach GitHub)

Examples:
  kmod/scripts/ssh-handheld.sh bazzite@192.168.1.50 all
  OXP_BOARD_VARIANT=oxp_x1 kmod/scripts/ssh-handheld.sh user@10.0.0.8 all
EOF
}

if [[ $# -lt 2 ]]; then
  usage >&2
  exit 2
fi

HOST="$1"
CMD="$2"
shift 2

if [[ "$REMOTE_NAME" == /* ]]; then
  REMOTE_ABS="$REMOTE_NAME"
  RSYNC_DEST="${HOST}:${REMOTE_NAME}/"
else
  REMOTE_ABS="\$HOME/${REMOTE_NAME}"
  RSYNC_DEST="${HOST}:${REMOTE_NAME}/"
fi

ssh_r() {
  # shellcheck disable=SC2086
  ssh "${SSH_OPTS[@]}" "$@"
}

ssh_t() {
  # sudo / collect may need a TTY for passwords
  # shellcheck disable=SC2086
  ssh -t "${SSH_OPTS[@]}" "$@"
}

remote_has() {
  ssh_r "$HOST" "command -v $1 >/dev/null 2>&1"
}

ensure_remote_dir() {
  ssh_r "$HOST" "mkdir -p ${REMOTE_ABS}"
}

push_repo() {
  ensure_remote_dir
  local excludes=(
    --exclude '.git/'
    --exclude '**/__pycache__/'
    --exclude 'kmod/oxpec/*.ko'
    --exclude 'kmod/oxpec/*.o'
    --exclude 'kmod/oxpec/*.mod'
    --exclude 'kmod/oxpec/*.mod.c'
    --exclude 'kmod/oxpec/Module.symvers'
    --exclude 'kmod/oxpec/modules.order'
  )
  if [[ "${OXP_PUSH_SOURCE:-0}" != 1 ]]; then
    excludes+=(--exclude 'kmod/oxpec/oxpec.c')
  fi

  if command -v rsync >/dev/null && remote_has rsync; then
    echo "push via rsync -> ${RSYNC_DEST}"
    rsync -az -e "ssh ${SSH_OPTS[*]}" "${excludes[@]}" "${ROOT}/" "${RSYNC_DEST}"
  else
    echo "push via tar|ssh -> ${HOST}:${REMOTE_ABS}"
    local tar_ex=(
      --exclude='.git'
      --exclude='kmod/scripts/__pycache__'
      --exclude='kmod/oxpec/*.ko'
      --exclude='kmod/oxpec/*.o'
      --exclude='kmod/oxpec/*.mod'
      --exclude='kmod/oxpec/*.mod.c'
    )
    if [[ "${OXP_PUSH_SOURCE:-0}" != 1 ]]; then
      tar_ex+=(--exclude='kmod/oxpec/oxpec.c')
    fi
    tar -C "${ROOT}" "${tar_ex[@]}" -czf - . | ssh_r "$HOST" "tar -xzf - -C ${REMOTE_ABS}"
  fi
  ssh_r "$HOST" "chmod +x ${REMOTE_ABS}/kmod/scripts/*.sh ${REMOTE_ABS}/kmod/scripts/*.py"
  echo "copied to ${HOST}:${REMOTE_ABS}"
}

collect_dmi() {
  local args=()
  if [[ $# -eq 0 ]]; then
    args=(--add)
  else
    args=("$@")
  fi
  local env_prefix=""
  if [[ -n "${OXP_BOARD_VARIANT:-}" ]]; then
    env_prefix+="OXP_BOARD_VARIANT=$(printf '%q' "$OXP_BOARD_VARIANT") "
  fi
  if [[ -n "${OXP_CAP_MAP:-}" ]]; then
    env_prefix+="OXP_CAP_MAP=$(printf '%q' "$OXP_CAP_MAP") "
  fi
  echo "collect on ${HOST}: ${args[*]}"
  ssh_t "$HOST" "cd ${REMOTE_ABS} && chmod +x kmod/scripts/*.sh kmod/scripts/*.py && ${env_prefix}kmod/scripts/collect-dmi.sh $(printf '%q ' "${args[@]}")"
}

pull_devices() {
  mkdir -p "${ROOT}/kmod/devices"
  if command -v rsync >/dev/null && remote_has rsync; then
    echo "pull devices via rsync"
    rsync -az -e "ssh ${SSH_OPTS[*]}" \
      "${HOST}:${REMOTE_NAME}/kmod/devices/" "${ROOT}/kmod/devices/"
  else
    echo "pull devices via scp"
    # shellcheck disable=SC2086
    scp ${SSH_OPTS[*]} "${HOST}:${REMOTE_NAME}/kmod/devices/"*.env "${ROOT}/kmod/devices/"
  fi
  echo "catalog on PC:"
  ls -1 "${ROOT}/kmod/devices/"*.env
}

do_install() {
  echo "install on ${HOST} (sudo)"
  ssh_t "$HOST" "cd ${REMOTE_ABS} && sudo ./kmod/scripts/on-device-install.sh"
}

do_status() {
  ssh_r "$HOST" "bash -s" <<EOF
set -e
cd ${REMOTE_ABS} 2>/dev/null || { echo "repo not copied yet"; exit 1; }
if [[ -r /usr/lib/os-release ]]; then . /usr/lib/os-release; else . /etc/os-release; fi
echo "host=\$(hostname) user=\$(whoami)"
echo "distro=\${PRETTY_NAME:-unknown} id=\${ID:-}"
echo "kernel=\$(uname -r)"
if command -v mokutil >/dev/null; then
  echo "secureboot=\$(mokutil --sb-state 2>/dev/null | head -n1 || true)"
else
  echo "secureboot=n/a"
fi
krel=\$(uname -r)
if [[ -d /lib/modules/\$krel/build ]]; then
  echo "kernel-headers=yes (/lib/modules/\$krel/build)"
else
  echo "kernel-headers=NO  (Bazzite needs matching kernel-devel; CachyOS: linux-cachyos-deckify-headers)"
fi
echo "catalog:"
ls -1 kmod/devices/*.env 2>/dev/null || echo "  (none)"
if [[ -e /var/lib/oxp-kmod/oxpec.ko ]]; then
  echo "installed-ko=/var/lib/oxp-kmod/oxpec.ko"
else
  echo "installed-ko=missing"
fi
systemctl is-enabled oxpec-local.service 2>/dev/null | sed 's/^/oxpec-local=/' || true
EOF
}

case "$CMD" in
  push)
    push_repo
    ;;
  collect)
    collect_dmi "$@"
    ;;
  pull-devices|pull)
    pull_devices
    ;;
  install)
    do_install
    ;;
  status)
    do_status
    ;;
  all)
    push_repo
    collect_dmi --add
    do_install
    pull_devices
    ;;
  run)
    if [[ "${1:-}" == -- ]]; then
      shift
    fi
    ssh_t "$HOST" "cd ${REMOTE_ABS} && $*"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    echo "unknown command: $CMD" >&2
    usage >&2
    exit 2
    ;;
esac
