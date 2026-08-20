# steamos-onexplayer

SteamOS / Linux bring-up notes for OneXPlayer handhelds.

**This repository is for research only.** Nothing here has been validated for
real-world use. Do not install the kernel modules, scripts, or other artifacts
on a device you care about. Production use is not recommended at this time.

## EC register maps

From OneXConsole 0.10.2-fix8. Installer and unpacked binaries are not in this repo.

Two platforms, two maps:

- [docs/ec/x2-mini.md](docs/ec/x2-mini.md) — Intel Arc G3 Extreme (X2 Mini, X2, OneXPlayer 3, Apex Air, …)
- [docs/ec/x2-mini-pro.md](docs/ec/x2-mini-pro.md) — AMD (X2 Mini PRO, APEX)
- [docs/ec/README.md](docs/ec/README.md) — merged platform table
- [docs/ec/access.md](docs/ec/access.md) — WinRing0 vs OxpWMI vs Linux `oxpec` / `oxp-wmi`
- [docs/ec/linux-wmi.md](docs/ec/linux-wmi.md) — kernel WMI / MSI Claw G3E vs OxpWMI
- [docs/ec/oxp-wmi.md](docs/ec/oxp-wmi.md) — Linux `oxp-wmi` module (OneXPlayer Intel / OxpWMI)
- [docs/ec/tdp.md](docs/ec/tdp.md) — Steam `TdpLimit1` via Intel RAPL (not EC)
- [linux/oxp-wmi/](linux/oxp-wmi/) — out-of-tree Intel OxpWMI client (`WMAC` Integer Arg2)
- X2 Mini deploy uses `kmod/scripts` (`ec-stack.sh` → `build.sh oxp-wmi` → `install-oxp-wmi.sh`); see [docs/local-build-and-deploy.md](docs/local-build-and-deploy.md)
- [docs/ec/maps.yaml](docs/ec/maps.yaml) — machine-readable tables
