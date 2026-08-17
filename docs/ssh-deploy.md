# 用 SSH 把脚本拷到掌机并跑完整适配

可以。掌机能 SSH 登入时，不必在掌机屏幕上敲命令：在电脑上把本仓库拷过去，远程采集 DMI、编译 `oxpec.ko`、装开机服务和 InputPlumber。

下面两套做法等价：

1. **一条命令**（电脑上已有本仓库）：`kmod/scripts/ssh-handheld.sh user@IP all`
2. **手写 ssh / scp / rsync**（不依赖封装脚本）

掌机上真正干活的仍是 `kmod/scripts/`，SSH 只负责复制和远程执行。

---

## 0. 掌机先打开 SSH

在掌机本机（或已有的任意终端）执行一次：

```bash
sudo systemctl enable --now sshd
# 有的镜像单元名是 ssh
# sudo systemctl enable --now ssh
ip -4 -br addr
```

Bazzite 也可在桌面「设置 → 共享 / SSH」里打开。记下 `wlan0` / `wlp*` 的地址，例如 `192.168.1.50`。

电脑上先测通（把用户和 IP 换成你的；Bazzite 默认用户常是 `bazzite`）：

```bash
ssh bazzite@192.168.1.50 'uname -r; cat /etc/os-release | head -n 4'
```

第一次会问 host key，输入 `yes`。建议免密：

```bash
ssh-copy-id bazzite@192.168.1.50
```

后面 `install` 需要 sudo。若不想每次输密码，可在掌机上给该用户配 NOPASSWD（可选，按你的安全习惯）。

掌机还要能访问 GitHub（`fetch-oxpec.sh` 拉 `oxpec.c`）。不能上网时见文末「离线」。

Bazzite 额外检查：

- 固件里 **关掉 Secure Boot**（未签名 `.ko` 会被拒）
- `/lib/modules/$(uname -r)/build` 必须存在，否则先装 **vermagic 一致** 的 OGC `kernel-devel`，不要 layer 官方 Fedora 的 devel

---

## 1. 推荐：电脑上一条龙

在**电脑**的仓库根目录：

```bash
cd /path/to/steamos-onexplayer
chmod +x kmod/scripts/*.sh kmod/scripts/*.py

# 整段：拷仓库 → 检查开发环境 → 真机 --add → 编译安装 → 把新 .env 拉回电脑
kmod/scripts/ssh-handheld.sh bazzite@192.168.1.50 all

# 只检查、不安装（仓库还没拷过去也会把 check-env.sh 经 SSH 灌进去）
kmod/scripts/ssh-handheld.sh bazzite@192.168.1.50 check
```

X1 / G1 等不要用默认 `oxp_fly` 时：

```bash
OXP_BOARD_VARIANT=oxp_x1 kmod/scripts/ssh-handheld.sh user@192.168.1.50 all
# 其它变体：oxp_2 / oxp_g1_a / oxp_g1_i
```

分步（先看 DMI 再装）：

```bash
H=bazzite@192.168.1.50
kmod/scripts/ssh-handheld.sh "$H" push
kmod/scripts/ssh-handheld.sh "$H" check          # 或缺 headers / SB / 编译器时在这里停
kmod/scripts/ssh-handheld.sh "$H" collect --add
kmod/scripts/ssh-handheld.sh "$H" install
kmod/scripts/ssh-handheld.sh "$H" pull-devices
```

| 子命令 | 做什么 |
| --- | --- |
| `push` | 把仓库拷到掌机 `~/steamos-onexplayer`（不含 `.git`、不含已编的 `.ko`） |
| `check` / `status` | SSH 进去后跑 `check-env.sh`：发行版、EC 栈（X2 Mini=`oxp-wmi`）、DMI、工具链、headers、签名、Secure Boot |
| `collect` | 先 `--collect-only` 检查，再远程 `collect-dmi.sh`（默认 `--add`；X2 Mini 写成 `oxp_wmi`） |
| `install` | 先完整环境检查，再 `sudo on-device-install.sh`（X2 Mini 编装 `oxp-wmi.ko`） |
| `pull-devices` | 把掌机上的 `kmod/devices/*.env` 拉回电脑，和其它型号放一起 |
| `all` | `push` + `check` + `collect --add` + `install` + `pull-devices`；有 `[FAIL]` 会停下来不装 |
| `run -- cmd` | 在掌机仓库目录执行任意命令 |

`check` 会逐项打印 `[OK]` / `[WARN]` / `[FAIL]`。Bazzite 缺与 `uname -r` 一致的 `kernel-devel`、开着 Secure Boot，会直接 `[FAIL]` 并中止 `install` / `all`。CachyOS 缺 headers / `base-devel` 一般是 `[WARN]`（`install-cachyos.sh` 会 `pacman` 补上）；`OXP_CHECK_STRICT=1` 时这些也算失败。跳过检查：`OXP_SKIP_CHECK=1`。

手写等价：

```bash
# 仓库还没拷过去也可以
ssh bazzite@192.168.1.50 'bash -s' < kmod/scripts/check-env.sh
# 已经 push 之后
ssh bazzite@192.168.1.50 '~/steamos-onexplayer/kmod/scripts/check-env.sh'
```

非 22 端口或指定密钥：

```bash
OXP_SSH_OPTS='-p 2222 -i ~/.ssh/id_ed25519' \
  kmod/scripts/ssh-handheld.sh user@host all
```

换下一台掌机：对**新的** `user@IP` 再跑一遍 `all`。每台只多一份 `kmod/devices/<slug>.env`，旧的不会被覆盖。`push` 会把电脑上已有的全部 `.env` 带过去，所以新机编出来的 `oxpec.ko` 会带上所有已收录型号。

---

## 2. 手写 SSH / rsync / scp（不跑封装脚本）

把 `H` 和用户换成你的。电脑上先 `cd` 到本仓库。

### 2.1 拷贝仓库

有 rsync（两边都有）时：

```bash
H=bazzite@192.168.1.50
rsync -az --exclude '.git/' --exclude 'kmod/oxpec/oxpec.c' \
  --exclude 'kmod/oxpec/*.ko' --exclude '**/__pycache__/' \
  ./ "${H}:steamos-onexplayer/"
ssh "$H" 'chmod +x ~/steamos-onexplayer/kmod/scripts/*.sh ~/steamos-onexplayer/kmod/scripts/*.py'
```

没有 rsync 时用 tar 管道（不必在掌机装 git）：

```bash
H=bazzite@192.168.1.50
tar --exclude='.git' --exclude='kmod/oxpec/oxpec.c' --exclude='kmod/oxpec/*.ko' \
  -czf - . | ssh "$H" 'mkdir -p ~/steamos-onexplayer && tar -xzf - -C ~/steamos-onexplayer'
ssh "$H" 'chmod +x ~/steamos-onexplayer/kmod/scripts/*.sh ~/steamos-onexplayer/kmod/scripts/*.py'
```

或整目录 `scp -r`（较慢，但到处都有）：

```bash
scp -r ./kmod ./docs "$H:steamos-onexplayer/"
```

掌机自己能 `git clone` 也可以，和 SSH 拷贝二选一，不要混用两份不同的 `devices/`。

### 2.2 远程采集 DMI

```bash
ssh -t "$H" 'cd ~/steamos-onexplayer && kmod/scripts/collect-dmi.sh --add'
```

指定 slug 或变体：

```bash
ssh -t "$H" 'cd ~/steamos-onexplayer && OXP_BOARD_VARIANT=oxp_x1 kmod/scripts/collect-dmi.sh --add x1-mini'
```

`-t` 分配伪终端；采集本身通常不用 sudo（读 `/sys/class/dmi/id`）。

### 2.3 远程编译并安装

```bash
# 自动辨认发行版
ssh -t "$H" 'cd ~/steamos-onexplayer && sudo ./kmod/scripts/on-device-install.sh'
```

或写死：

```bash
# CachyOS
ssh -t "$H" 'cd ~/steamos-onexplayer && sudo kmod/scripts/install-cachyos.sh && sudo kmod/scripts/install-inputplumber.sh'

# Bazzite（先确认 headers 和 Secure Boot）
ssh -t "$H" 'cd ~/steamos-onexplayer && sudo kmod/scripts/install-bazzite.sh && sudo kmod/scripts/install-inputplumber.sh'
```

CachyOS 一键脚本会 `pacman` 安装 `linux-cachyos-deckify-headers`。Bazzite 缺 headers 时脚本会失败并打印下一步，不能靠 SSH 变出匹配的 `kernel-devel`。

### 2.4 把新机型拉回电脑仓库

```bash
mkdir -p kmod/devices
rsync -az "${H}:steamos-onexplayer/kmod/devices/" ./kmod/devices/
# 或
scp "${H}:steamos-onexplayer/kmod/devices/"*.env ./kmod/devices/
```

提交这些 `.env`，下一台 `push` 就会带上。

### 2.5 看是否成功

```bash
ssh -t "$H" 'systemctl --no-pager --full status oxpec-local.service'
ssh "$H" 'ls -l /var/lib/oxp-kmod/oxpec.ko; ls /sys/class/hwmon/*/name | while read f; do echo "$f=$(cat "$f")"; done'
ssh "$H" 'journalctl -u inputplumber -b --no-pager | tail -n 30'
```

`hwmon` 里应有 `name=oxpec`，且 `fan1_input` 像转速。

---

## 3. 多台掌机（同一套脚本反复跑）

```text
电脑仓库
  kmod/devices/apex.env
  kmod/devices/x1-mini.env     ← 每台 --add 多一份
       │
       │  ssh-handheld.sh HOST push
       ▼
掌机 ~/steamos-onexplayer     注入时写入 oxpec.c 的全部 DMI
```

1. 电脑上已有若干 `devices/*.env`
2. `push` 到新机（旧型号一起过去）
3. 新机 `collect --add`（只多一个文件）
4. `install`（一个 `.ko` 含全部 board_name）
5. `pull-devices` 把新文件收进电脑
6. 换 IP，重复

不要在掌机上改 `local-device.env` 来切换型号。

---

## 4. 离线掌机（不能访问 GitHub）

在**能上网的电脑**上先拉源码（采集仍必须在掌机上做，DMI 不能猜）：

```bash
H=user@192.168.1.50
kmod/scripts/ssh-handheld.sh "$H" push
kmod/scripts/ssh-handheld.sh "$H" collect --add
kmod/scripts/ssh-handheld.sh "$H" pull-devices

# 电脑有网：拉 oxpec.c 并注入目录里全部型号
kmod/scripts/fetch-oxpec.sh ogc          # CachyOS 可用 mainline
kmod/scripts/inject-catalog.sh

# 把已经注入好的 oxpec.c 一并推过去，掌机不再 curl GitHub
OXP_PUSH_SOURCE=1 kmod/scripts/ssh-handheld.sh "$H" push
kmod/scripts/ssh-handheld.sh "$H" install
```

---

## 5. 常见失败

| 现象 | 处理 |
| --- | --- |
| `Permission denied` | 用户名/密钥/密码；`ssh-copy-id` |
| `Connection refused` | 掌机未开 `sshd`，或防火墙/AP 隔离 |
| `collect-dmi` 报 UNKNOWN | 不在真机上，或 DMI sysfs 不可读 |
| `check` 出现 `[FAIL] 内核头文件` | CachyOS：`sudo pacman -S linux-cachyos-deckify-headers`（非 `--strict` 时只警告，install 会代装）；Bazzite：先装匹配的 OGC `kernel-devel` 再重启 |
| `check` 出现 `[FAIL] Secure Boot` | 固件里关掉 SB，或自签 MOK |
| `Key was rejected` / Secure Boot | 关 SB，或自签 MOK（`ujust enroll-secure-boot-key` 签不了你的本地模块） |
| `Invalid module format` | headers 的 vermagic ≠ `uname -r` |
| `InputPlumber device dir not found` | 镜像未装 InputPlumber：CachyOS `sudo pacman -S inputplumber` |
| `curl: ... github.com` | 掌机无外网，走第 4 节离线 |

更细的编译/变体说明见 [local-build-and-deploy.md](local-build-and-deploy.md)。
