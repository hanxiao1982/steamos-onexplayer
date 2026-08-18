# Copy the scripts to the handheld over SSH and run the full bring-up

Yes. If the handheld accepts SSH, you do not need its on-screen keyboard: copy this repo from a PC, collect DMI remotely, build `oxpec.ko` or `oxp-wmi.ko`, install the boot service and InputPlumber.

Two equivalent approaches:

1. **One command** (this repo already on the PC): `kmod/scripts/ssh-handheld.sh user@IP all`
2. **Raw ssh / scp / rsync** (no wrapper)

The work still happens in `kmod/scripts/` on the handheld. SSH only copies and runs those scripts.

---

## 0. Enable SSH on the handheld

Once, on the handheld (or any existing terminal):

```bash
sudo systemctl enable --now sshd
# some images use the unit name ssh
# sudo systemctl enable --now ssh
ip -4 -br addr
```

On Bazzite you can also enable it under desktop Settings → Sharing / SSH. Note the `wlan0` / `wlp*` address, e.g. `192.168.1.50`.

From the PC (user and IP are yours; Bazzite’s default user is often `bazzite`):

```bash
ssh bazzite@192.168.1.50 'uname -r; cat /etc/os-release | head -n 4'
```

Accept the host key with `yes` the first time. Passwordless login:

```bash
ssh-copy-id bazzite@192.168.1.50
```

`install` needs sudo. Optional: NOPASSWD for that user if you do not want a password each time.

The handheld also needs GitHub access (`fetch-oxpec.sh` pulls `oxpec.c`). If it is offline, see “Offline handheld” below.

Bazzite extras:

- **Disable Secure Boot** in firmware (unsigned `.ko` files are rejected)
- `/lib/modules/$(uname -r)/build` must exist, otherwise install the OGC `kernel-devel` whose **vermagic matches**. Do not layer stock Fedora devel

---

## 1. Recommended: one-shot from the PC

In the **PC** repo root:

```bash
cd /path/to/steamos-onexplayer
chmod +x kmod/scripts/*.sh kmod/scripts/*.py

# copy repo → check env → --add on the handheld → build/install → pull the new .env back
kmod/scripts/ssh-handheld.sh bazzite@192.168.1.50 all

# check only (pipes check-env.sh over SSH even before push)
kmod/scripts/ssh-handheld.sh bazzite@192.168.1.50 check
```

If this is X1 / G1 and not the default `oxp_fly`:

```bash
OXP_BOARD_VARIANT=oxp_x1 kmod/scripts/ssh-handheld.sh user@192.168.1.50 all
# other variants: oxp_2 / oxp_g1_a / oxp_g1_i
```

Step by step (inspect DMI before install):

```bash
H=bazzite@192.168.1.50
kmod/scripts/ssh-handheld.sh "$H" push
kmod/scripts/ssh-handheld.sh "$H" check          # stops here if headers / SB / compiler are missing
kmod/scripts/ssh-handheld.sh "$H" collect --add
kmod/scripts/ssh-handheld.sh "$H" install
kmod/scripts/ssh-handheld.sh "$H" pull-devices
```

| Subcommand | What it does |
| --- | --- |
| `push` | Copy the repo to `~/steamos-onexplayer` (no `.git`, no built `.ko`) |
| `check` / `status` | Run `check-env.sh` after SSH: distro, EC stack (X2 Mini=`oxp-wmi`), DMI, toolchain, headers, signing, Secure Boot |
| `collect` | `--collect-only` check, then remote `collect-dmi.sh` (default `--add`; X2 Mini writes `oxp_wmi`) |
| `install` | Full env check, then `sudo on-device-install.sh` (X2 Mini builds `oxp-wmi.ko`) |
| `pull-devices` | Copy `kmod/devices/*.env` back to the PC catalog |
| `all` | `push` + `check` + `collect --add` + `install` + `pull-devices`; stops on `[FAIL]` |
| `run -- cmd` | Run an arbitrary command in the remote repo |

`check` prints `[OK]` / `[WARN]` / `[FAIL]`. Missing matching `kernel-devel` or Secure Boot on Bazzite is `[FAIL]` and aborts `install` / `all`. Missing CachyOS headers / `base-devel` is usually `[WARN]` (`install-cachyos.sh` will `pacman` them). `OXP_CHECK_STRICT=1` turns those into failures. Skip checks: `OXP_SKIP_CHECK=1`.

Raw equivalent:

```bash
# works before the repo is copied
ssh bazzite@192.168.1.50 'bash -s' < kmod/scripts/check-env.sh
# after push
ssh bazzite@192.168.1.50 '~/steamos-onexplayer/kmod/scripts/check-env.sh'
```

Non-22 port or a specific key:

```bash
OXP_SSH_OPTS='-p 2222 -i ~/.ssh/id_ed25519' \
  kmod/scripts/ssh-handheld.sh user@host all
```

Next handheld: run `all` against the **new** `user@IP`. Each machine adds one `kmod/devices/<slug>.env`; old files stay. `push` sends every `.env` already on the PC, so a new AMD `oxpec.ko` includes all catalogued board names.

---

## 2. Raw SSH / rsync / scp (no wrapper)

Replace `H` and the user. `cd` to this repo on the PC first.

### 2.1 Copy the repo

If both sides have rsync:

```bash
H=bazzite@192.168.1.50
rsync -az --exclude '.git/' --exclude 'kmod/oxpec/oxpec.c' \
  --exclude 'kmod/oxpec/*.ko' --exclude '**/__pycache__/' \
  ./ "${H}:steamos-onexplayer/"
ssh "$H" 'chmod +x ~/steamos-onexplayer/kmod/scripts/*.sh ~/steamos-onexplayer/kmod/scripts/*.py'
```

Without rsync, use a tar pipe (no git on the handheld):

```bash
H=bazzite@192.168.1.50
tar --exclude='.git' --exclude='kmod/oxpec/oxpec.c' --exclude='kmod/oxpec/*.ko' \
  -czf - . | ssh "$H" 'mkdir -p ~/steamos-onexplayer && tar -xzf - -C ~/steamos-onexplayer'
ssh "$H" 'chmod +x ~/steamos-onexplayer/kmod/scripts/*.sh ~/steamos-onexplayer/kmod/scripts/*.py'
```

Or `scp -r` of the whole tree (slower, everywhere):

```bash
scp -r ./kmod ./docs "$H:steamos-onexplayer/"
```

`git clone` on the handheld is fine too — pick one method, do not mix two different `devices/` trees.

### 2.2 Collect DMI remotely

```bash
ssh -t "$H" 'cd ~/steamos-onexplayer && kmod/scripts/collect-dmi.sh --add'
```

Slug or variant:

```bash
ssh -t "$H" 'cd ~/steamos-onexplayer && OXP_BOARD_VARIANT=oxp_x1 kmod/scripts/collect-dmi.sh --add x1-mini'
```

`-t` allocates a TTY. Collection itself usually needs no sudo (reads `/sys/class/dmi/id`).

### 2.3 Build and install remotely

```bash
# auto-detect distro and EC stack
ssh -t "$H" 'cd ~/steamos-onexplayer && sudo ./kmod/scripts/on-device-install.sh'
```

Or pin the script:

```bash
# CachyOS
ssh -t "$H" 'cd ~/steamos-onexplayer && sudo kmod/scripts/install-cachyos.sh && sudo kmod/scripts/install-inputplumber.sh'

# Bazzite (headers and Secure Boot first)
ssh -t "$H" 'cd ~/steamos-onexplayer && sudo kmod/scripts/install-bazzite.sh && sudo kmod/scripts/install-inputplumber.sh'
```

The CachyOS one-shot `pacman`-installs `linux-cachyos-deckify-headers`. If Bazzite lacks headers the script fails and prints the next step; SSH cannot invent a matching `kernel-devel`.

### 2.4 Pull the new model back into the PC repo

```bash
mkdir -p kmod/devices
rsync -az "${H}:steamos-onexplayer/kmod/devices/" ./kmod/devices/
# or
scp "${H}:steamos-onexplayer/kmod/devices/"*.env ./kmod/devices/
```

Commit those `.env` files so the next `push` includes them.

### 2.5 Confirm it worked

```bash
ssh -t "$H" 'systemctl --no-pager --full status oxpec-local.service oxp-wmi-local.service'
ssh "$H" 'ls -l /var/lib/oxp-kmod/; ls /sys/class/hwmon/*/name | while read f; do echo "$f=$(cat "$f")"; done'
ssh "$H" 'journalctl -u inputplumber -b --no-pager | tail -n 30'
```

hwmon should show `name=oxpec` or `name=oxp_wmi`, and `fan1_input` should look like an RPM.

---

## 3. Several handhelds (same scripts, repeated)

```text
PC repo
  kmod/devices/apex.env
  kmod/devices/x1-mini.env     ← one extra file per --add
       │
       │  ssh-handheld.sh HOST push
       ▼
handheld ~/steamos-onexplayer  inject writes every DMI into oxpec.c
```

1. The PC already has several `devices/*.env`
2. `push` to the new machine (old models go with it)
3. `collect --add` on the new machine (one extra file)
4. `install` (one AMD `.ko` with every `board_name`, or `oxp-wmi` on X2 Mini)
5. `pull-devices` brings the new file back
6. Change IP and repeat

Do not edit `local-device.env` on the handheld to switch models.

---

## 4. Offline handheld (no GitHub)

Collect DMI on the handheld anyway (do not guess). Fetch source on a **PC that has internet**:

```bash
H=user@192.168.1.50
kmod/scripts/ssh-handheld.sh "$H" push
kmod/scripts/ssh-handheld.sh "$H" collect --add
kmod/scripts/ssh-handheld.sh "$H" pull-devices

# PC has net: fetch oxpec.c and inject the whole catalog
kmod/scripts/fetch-oxpec.sh ogc          # CachyOS can use mainline
kmod/scripts/inject-catalog.sh

# push the already-injected oxpec.c; the handheld will not curl GitHub
OXP_PUSH_SOURCE=1 kmod/scripts/ssh-handheld.sh "$H" push
kmod/scripts/ssh-handheld.sh "$H" install
```

X2 Mini does not need this: `oxp-wmi.c` is already in the repo.

---

## 5. Common failures

| Symptom | Fix |
| --- | --- |
| `Permission denied` | user / key / password; `ssh-copy-id` |
| `Connection refused` | `sshd` not running, or firewall / AP isolation |
| `collect-dmi` reports UNKNOWN | not on real hardware, or DMI sysfs unreadable |
| `check` `[FAIL] kernel headers` | CachyOS: `sudo pacman -S linux-cachyos-deckify-headers` (warning unless `--strict`; install will add them). Bazzite: matching OGC `kernel-devel`, then reboot |
| `check` `[FAIL] Secure Boot` | disable SB in firmware, or sign with your own MOK |
| `Key was rejected` / Secure Boot | same; `ujust enroll-secure-boot-key` does not sign your local module |
| `Invalid module format` | headers vermagic ≠ `uname -r` |
| `InputPlumber device dir not found` | CachyOS: `sudo pacman -S inputplumber` |
| `curl: ... github.com` | no outbound net; use section 4 |

More build and variant detail: [local-build-and-deploy.md](local-build-and-deploy.md).
