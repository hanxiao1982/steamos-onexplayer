# Out-of-tree EC modules + local InputPlumber overlay

Full steps: [docs/local-build-and-deploy.md](../docs/local-build-and-deploy.md).

**Safe to rerun on every model.** Each machine gets one `kmod/devices/<slug>.env`.  
**X2 Mini (Intel / OxpWMI)** uses `linux/oxp-wmi` and does not fetch or inject `oxpec.c`. AMD devices still use `oxpec`.

```bash
kmod/scripts/ec-stack.sh                 # X2 Mini should print oxp-wmi
kmod/scripts/collect-dmi.sh --add

# Intel G3E / X2 Mini
kmod/scripts/apply-all.sh                # build oxp-wmi.ko
sudo kmod/scripts/test-oxp-wmi.sh
sudo kmod/scripts/install-oxp-wmi.sh

# AMD / oxpec
kmod/scripts/apply-all.sh --fetch ogc
sudo kmod/scripts/test-oxpec.sh kmod/oxpec/oxpec.ko
sudo kmod/scripts/install-common.sh

sudo kmod/scripts/install-inputplumber.sh
```

List the catalog: `kmod/scripts/apply-all.sh --list`

CachyOS one-shot: `sudo kmod/scripts/install-cachyos.sh`  
Bazzite one-shot: `sudo kmod/scripts/install-bazzite.sh` (matching kernel-devel, Secure Boot off)

If the handheld has SSH, copy and run from a **PC** ([docs/ssh-deploy.md](../docs/ssh-deploy.md)):

```bash
kmod/scripts/ssh-handheld.sh bazzite@192.168.1.50 check   # headers / compiler / SB
kmod/scripts/ssh-handheld.sh bazzite@192.168.1.50 all
```

On the handheld you can also run `kmod/scripts/check-env.sh` directly.

`kmod/local-device.env` is an optional extra (legacy). Use `kmod/devices/` for the catalog.
