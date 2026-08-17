# 树外 EC 模块 + InputPlumber 本地叠加

完整步骤见 [docs/local-build-and-deploy.md](../docs/local-build-and-deploy.md)。

**可以在不同型号上反复执行。** 每台机写一份 `kmod/devices/<slug>.env`。  
**X2 Mini（Intel / OxpWMI）** 走 `linux/oxp-wmi`，不拉、不注入 `oxpec.c`。AMD 机型仍走 `oxpec`。

```bash
kmod/scripts/ec-stack.sh                 # X2 Mini 应打印 oxp-wmi
kmod/scripts/collect-dmi.sh --add

# Intel G3E / X2 Mini
kmod/scripts/apply-all.sh                # 编 oxp-wmi.ko
sudo kmod/scripts/test-oxp-wmi.sh
sudo kmod/scripts/install-oxp-wmi.sh

# AMD / oxpec
kmod/scripts/apply-all.sh --fetch ogc
sudo kmod/scripts/test-oxpec.sh kmod/oxpec/oxpec.ko
sudo kmod/scripts/install-common.sh

sudo kmod/scripts/install-inputplumber.sh
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
