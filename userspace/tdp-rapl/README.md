# Intel RAPL TdpLimit1 remote

Steam hides the TDP slider until `TdpLimit1` exists. This daemon owns
`com.steampowered.OxpRapl.Tdp` on the system bus and writes package RAPL
PL1/PL2. It is not EC / `oxp-wmi` / HHD.

Install: `sudo kmod/scripts/install-tdp-rapl.sh`  

That copies `remotes.d` and then runs `kmod/scripts/reload-tdp-rapl.sh`
(stop remote → restart user `steamos-manager` → start remote). Dropping the
toml alone leaves `RemoteInterfaces` empty. How it fits:
[docs/ec/tdp.md](../../docs/ec/tdp.md)
