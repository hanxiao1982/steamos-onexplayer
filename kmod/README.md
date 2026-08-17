# 树外 oxpec + InputPlumber 本地叠加

完整步骤见 [docs/local-build-and-deploy.md](../docs/local-build-and-deploy.md)。

**可以在不同型号上反复执行。** 每台机写一份 `kmod/devices/<slug>.env`，注入/安装会累加，不会冲掉已有型号。

```bash
# 真机：只追加这一台，不改其它 .env
kmod/scripts/collect-dmi.sh --add

# 仓库里已有多份 devices/*.env 时：拉取上游源码并重新注入全部型号
kmod/scripts/apply-all.sh --fetch ogc          # 或 mainline
# 没有 kernel headers 时先只注入：
# kmod/scripts/apply-all.sh --fetch ogc --inject-only

sudo kmod/scripts/test-oxpec.sh kmod/oxpec/oxpec.ko
sudo kmod/scripts/install-common.sh
sudo kmod/scripts/install-inputplumber.sh      # 每型号一份 YAML
```

查看目录：`kmod/scripts/apply-all.sh --list`

CachyOS 一键：`sudo kmod/scripts/install-cachyos.sh`  
Bazzite 一键：`sudo kmod/scripts/install-bazzite.sh`（需要匹配的 kernel-devel，且关闭 Secure Boot）

掌机已开 SSH 时，在**电脑**上拷过去并远程执行（详见 [docs/ssh-deploy.md](../docs/ssh-deploy.md)）：

```bash
kmod/scripts/ssh-handheld.sh bazzite@192.168.1.50 check   # 先看 headers / 编译器 / SB
kmod/scripts/ssh-handheld.sh bazzite@192.168.1.50 all
```

真机上也可直接：`kmod/scripts/check-env.sh`

`kmod/local-device.env` 仍可作为额外一份（兼容旧流程）；正式积累请用 `kmod/devices/`。
