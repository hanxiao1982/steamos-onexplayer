# Intel RAPL TdpLimit1 remote

Steam hides the TDP slider until `TdpLimit1` exists. This daemon owns
`com.steampowered.OxpRapl.Tdp` on the system bus and writes package RAPL
PL1/PL2. It is not EC / `oxp-wmi` / HHD.

Install: `sudo kmod/scripts/install-tdp-rapl.sh`  
How it fits: [docs/ec/tdp.md](../../docs/ec/tdp.md)
