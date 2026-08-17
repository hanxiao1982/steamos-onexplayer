# 树外 oxpec + InputPlumber 本地叠加

完整步骤见 [docs/local-build-and-deploy.md](../docs/local-build-and-deploy.md)。

```bash
kmod/scripts/collect-dmi.sh          # 真机
# 编辑 kmod/local-device.env
kmod/scripts/fetch-oxpec.sh ogc      # 或 mainline
python3 kmod/scripts/inject-dmi.py --env kmod/local-device.env --oxpec kmod/oxpec/oxpec.c
kmod/scripts/build.sh
sudo kmod/scripts/test-oxpec.sh
sudo kmod/scripts/install-common.sh
sudo kmod/scripts/install-inputplumber.sh
```

CachyOS 一键：`sudo kmod/scripts/install-cachyos.sh`  
Bazzite 一键：`sudo kmod/scripts/install-bazzite.sh`（需要匹配的 kernel-devel，且关闭 Secure Boot）
