# steamos-onexplayer

SteamOS / Linux bring-up notes for OneXPlayer handhelds.

**This repository is for research only.** Nothing here has been validated for
real-world use. Do not install the kernel modules, scripts, or other artifacts
on a device you care about. Production use is not recommended at this time.

## EC support

The EC model is derived from OneXConsole 0.10.2-fix8. The vendor application has two EC access types, mapped to two independent Linux drivers:

- [docs/ec/oxpec.md](docs/ec/oxpec.md) — OneXConsole type 1 devices; direct EC register profiles for Linux `oxpec`.
- [docs/ec/oxp-wmi.md](docs/ec/oxp-wmi.md) — OneXConsole type 2 devices; `SuRwECRegInterface` / Linux `oxp-wmi`.
- [docs/ec/README.md](docs/ec/README.md) — ownership rules, source hierarchy and DMI matching guidance.
- [docs/ec/onexconsole-api.md](docs/ec/onexconsole-api.md) — retained OneXConsole / CompatLayerCT reverse-engineering details.
- [docs/ec/tdp.md](docs/ec/tdp.md) — Steam `TdpLimit1` via Intel RAPL (not EC).
- [linux/oxp-wmi/](linux/oxp-wmi/) — out-of-tree OxpWMI client.

The two EC modules are intentionally separate. A device should bind to exactly one of them according to the exact OneXConsole DMI/access-type mapping; the mere presence of the WMI provider is not sufficient to select `oxp-wmi`.
