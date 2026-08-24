# OneXConsole local API (port 1013)

Source: OneXConsole **0.10.2-fix8** (`background.js` defaults + `CompatLayerCT.exe` WCF `UriTemplate` strings).

The Vue UI is an Electron Chromium window (`app://./index.html`). Hardware work is not in the renderer. The main process starts `CompatLayerCT.exe` and calls it with the same path list you would see on localhost.

## Ports

Hard-coded in `background.js`:

```
layerHeader: "http://"
layerHost:   "localhost"
layerPort:   1013
layerUrl:    http://localhost:1013

socketHost:  127.0.0.103
socketPort:  1014
lanSharePort: 1017
```

| Port | Bind | Role |
|---|---|---|
| **1013** | `localhost` | CompatLayerCT HTTP API (WCF `WebServiceHost`). First argv: `CompatLayerCT.exe 1013 OneXConsole`. |
| 1014 | `127.0.0.103` | Extra TCP socket (JSON objects). Only started when HTTP mode is on. |
| 1017 | LAN share | File-share website, not EC. |

`1013` is the port to watch for EC / fan / battery / TDP calls.

## Two transports (this is why F12 may be empty)

Default `isPipeMode` is **true**. Startup log: `Layer run by pipe` vs `Layer run by webservice`.

| Mode | How Electron calls CompatLayerCT | 1013 in F12 / browser |
|---|---|---|
| Pipe (default) | Named pipe `\\.\pipe\CompatLayerCT`. Same URL paths, not HTTP. Extra argv `2`: `CompatLayerCT.exe 1013 OneXConsole 2`. | Renderer DevTools **Network** will not show these. `netstat` may still list 1013 if the exe also binds HTTP. |
| HTTP | `POST http://localhost:1013<path>` from the **main process** (`http.request`), `Content-Type: application/json`. | Still not in the Vue window’s F12. Capture with a second client, Fiddler/loopback, or `netsh`/Wireshark on 1013. |

The renderer only uses `ipcRenderer.invoke(...)`. It never `fetch`es `localhost:1013`. Opening F12 on the OneXConsole window therefore cannot show the layer API unless you also intercept main-process traffic.

Force HTTP mode (admin, then restart OneXConsole):

```json
// C:\Windows\OEM\app_config.json
{ "isPipeMode": 0 }
```

`isPipeMode` is only read from that OEM file. There is no CLI flag for it.

`--productionDebug` on the Electron exe turns on window DevTools. That still does not put layer POSTs in the renderer Network tab.

Check whether 1013 is listening (admin CMD):

```
netstat -ano | findstr :1013
```

The owning process should be `CompatLayerCT.exe`.

## Wire format

```
POST /fan/setFanSpeed/40
Content-Type: application/json

{"enabled":"..."}     // only when the JS wrapper passes params; many routes are path-only
```

Response wrapper:

```
{ "code": 1, "result": "<JSON string>" }
```

`code == 1` is success; Electron then `JSON.parse(result)`.

Init routes put **encoded EC addresses** in the path (`encoded = 0x400 + reg`). Later get/set routes send **logical values** (percent, watts, 0/1), not raw register numbers. There is no public `/ECRamReadByte` HTTP route; `ECRamReadByte` / `ECRamDirectWrite` stay inside CompatLayerCT after the address table is filled.

## What init actually does

These calls are **userspace bookkeeping inside `CompatLayerCT.exe`**. They do not handshake the EC firmware and (except as noted) they do not write EC RAM.

Two layers:

| Layer | Call | What it does | Needed before raw EC R/W? |
|---|---|---|---|
| Backend | `/func/setECAccessType/{1\|2}` → `InitEC` / `FreeEC` | Pick WinRing0 vs OxpWMI and open that backend (`InitializeOls` or WMI `SuRwECRegInterface`). | Only if you use CompatLayerCT’s own `ECRamReadByte`. Direct WMI / ACPI EC / `ec_sys` does **not** need this. |
| Address table | `initBaseEc`, `fan/init`, `initHandleEc`, `initOXPSensorEc`, `battery/initEc`, `initPowerSupplyModeEC` | Copy encoded offsets and constants into static fields (`EC_ADDR_FAN_SPEED_H`, `EC_VALUE_FAN_AUTOMATE_ON`, …). | **No.** The EC already has those bytes. You already know the map. |
| UI only | `/tdp/init/{min}/{max}/{maxBoost}` | Store watt bounds for the slider. | No. Not an EC register. |

Startup order in `background.js` (`Global step1` → `step8`):

1. DMI `getSimpleDeviceInfo` → override `ecAccessType` and the address variables (`w,k,C,x,S,L,T,A,E,O,M,z,D,…`).
2. `setECAccessType` (then unpack `wr0_build.7z` if type `1`).
3. `initBaseEc` → `fan/init` → `initHandleEc` → `initOXPSensorEc` (and `initPowerSupplyModeEC` if `powerSupplyMode`).
4. Later, if `enableBatteryProtection`: `battery/initEc`, then apply saved `chargeLimit` / `byPassPowerMode` (those two **are** writes).

So OneXConsole inits **before its own** `/fan/getFanSpeed` / `/battery/setChargeLimit`, because those routes have no address in the URL. They read `EC_ADDR_*` that init stored.

### Field each init fills

| Init | CompatLayerCT fields | Typical G3E (X2 Mini) | Typical AMD (Mini PRO) |
|---|---|---|---|
| `initBaseEc` | `EC_ADDR_APP_FUN_EN`, `EC_ADDR_FAN_SPEED_H/L` | `0xEB`, `0x58`/`0x59` | `0xF1`, `0x76`/`0x77` |
| `fan/init` | `EC_ADDR_FAN_AUTOMATE` + on/off values, `EC_ADDR_FAN_SPEED`, `FAN_MAX_SPEED_VALUE` | `0x4A` 0/1, `0x4B`, max 184 | same addrs, max 255 |
| `initHandleEc` | `EC_ADDR_HANDLE_POWER` + on/off/restore values | `0x2D`, 1 / 0 / −1 | same |
| `initOXPSensorEc` | board/CPU/battery/current addrs | only `0x70` useful on X2 Mini | same addrs (AMD live untested) |
| `battery/initEc` | charge / bypass / force-min addrs + bypass values | `0xA3`/`0xA4` used; `0xA5` unused on X2 Mini | `0xE5`/`0xE6` ( `0xE7` untested ) |
| `initPowerSupplyModeEC` | `EC_ADDR_POWER_SUPPLY_MODE` | `0xE3` | `0xE3` |

`EC_ADDR_OXP_SET_TDP_ABLE` (`0xED`) is **not** passed in any init URL. `getOXPSetTdpAble` uses a built-in offset.

### Do you need init before read/write?

| What you are calling | Init first? |
|---|---|
| WMI `ReadECReg` / `WriteECReg` with a known `GroupOffset` (X2 Mini PowerShell) | **No.** |
| Linux `ec_read` / `ec_write` / `ec_sys` `/sys/kernel/debug/ec/ec0/io` | **No.** |
| CompatLayerCT `ECRamReadByte(0x400+reg)` after you already called `setECAccessType` | Address-table init **not** required; backend init is. |
| HTTP `/fan/getFanSpeed`, `/fan/setFanSpeed/{n}`, `/battery/setChargeLimit/{n}`, `/func/getOXPSensorInfo` | **Yes**, the matching `init*` (or just let OneXConsole finish startup). Without it the helper has no `EC_ADDR_*` and the call is meaningless or uses leftover defaults (AMD `0xF1`/`0x76`/`0x77` / charge `0xA3`). |
| `/msr/setCpuPl` / `/ryzenadj/setCpuPl` | No EC init. Optional `/func/getOXPSetTdpAble` is only a gate read. |

Watching F12/proxy: the `init*` lines are how you learn **which registers this SKU uses**. The later `get*`/`set*` lines are how you learn **which values** the UI writes. You do not replay `init*` against the EC itself.

## EC-related routes

Filter F12 / proxy / `netstat` captures on these prefixes: `/func/`, `/fan/`, `/battery/`, `/tdp/`, `/msr/`, `/ryzenadj/`.

### Init (addresses in the URL)

| Method | Path | Meaning |
|---|---|---|
| POST | `/func/setECAccessType/{type}` | `1` WinRing0, `2` OxpWMI |
| POST | `/func/initBaseEc/{appFunENECAddr}/{fanSpeedHECAddr}/{fanSpeedLECAddr}` | Turbo + fan RPM pair |
| POST | `/func/initHandleEc/{addrHandlePower}/{valueOn}/{valueOff}/{valueOnRestore}` | Handle power `0x2D` |
| POST | `/func/initOXPSensorEc/{board1}/{board2}/{cpu}/{batTemp}/{curH}/{curL}` | Sensors `0x60`/`0x61`/`0x70`/`0xA0`/`0xA1`/`0xA2` |
| POST | `/fan/init/{fanMode}/{addrAutomate}/{valOn}/{valOff}/{addrPwm}/{pwmMax}` | PWM `0x4A`/`0x4B` |
| POST | `/battery/initEc` | JSON `addrChargeLimit`, `addrBypassPower`, `addrForceChargeMin`, bypass values |
| POST | `/battery/initPowerSupplyModeEC` | JSON `addrPowerSupplyMode` (`0xE3`) |
| POST | `/tdp/init/{minTdp}/{maxTdp}/{maxBoostTdp}` | UI watt range only, not an EC write of TDP |

X2 Mini / other Intel G3E (after DMI detect) typically hits:

```
POST /func/setECAccessType/2
POST /func/initBaseEc/1259/1112/1113          # 0xEB, 0x58, 0x59
POST /func/initHandleEc/1069/1/0/{restore}    # 0x2D
POST /func/initOXPSensorEc/1120/1121/1136/1184/1185/1186
POST /fan/init/common/1098/0/1/1099/{pwmMax}  # 0x4A, 0x4B
POST /battery/initEc   body: addrs 1187/1188/1189 (0xA3–0xA5), bypass 0/1/3
POST /battery/initPowerSupplyModeEC  body: addr 1251 (0xE3)
```

X2 Mini PRO / APEX keep WinRing0 (`setECAccessType/1`) and the AMD defaults `1265/1142/1143` (`0xF1`/`0x76`/`0x77`), PWM max `255`, charge addrs `1253/1254/1255` (`0xE5`–`0xE7`).

### Live get/set (values in the URL)

| Method | Path | What you see |
|---|---|---|
| POST | `/fan/getFanSpeed` | Current fan (percent or RPM depending on `fanMode`) |
| POST | `/fan/setFanSpeed/{fanSpeed}` | Manual PWM percent (JS clamps 20–100) |
| POST | `/fan/automate/{enabled}` | Auto vs manual |
| POST | `/func/getOXPSensorInfo` | Board / CPU / battery / current bundle |
| POST | `/func/getOXPSensorCpuTemp` | CPU temp from EC `0x70` |
| POST | `/func/getOXPSetTdpAble` | EC gate `0xED` (bool) |
| POST | `/battery/getPowerSupplyMode` | `0xE3` |
| POST | `/battery/setChargeLimit/{percent}` | UI percent **50–100 step 5** (EC byte 0–100) |
| POST | `/battery/setByPassPowerMode/{mode}` | HTTP **0 / 1 / 2** → EC **0 / 1 / 3** |
| POST | `/battery/setMaxTdpLimit/{true\|false}` | Whether max-TDP lock is applied |

## TDP watts (not EC)

Live X2 Mini Packet Monitor pcapng (58.6 s, 834 frames, ASCII extract —
tshark HTTP/`data.text` is empty on this file):

| Count | POST | Role |
|---|---|---|
| 36 | `/battery/getPowerSupplyMode` | Poll EC `0xE3` (~1.6 s; 36 × 1.6 s ≈ capture length) |
| 36 | `/func/getOXPSensorCpuTemp` | Poll EC temp |
| 36 | `/func/listAllProcess` | Same poll loop |
| 5 | `/programhandle/ph/changeReportMode` | Handle HID, not TDP |
| 4 | `/fan/getFanSpeed` | Fan poll |
| 4 | `/handledHID/setSimulateEnabled/false` | Handle HID |
| 4 | `/screen/getBrightness` | Windows brightness get |
| 4 | `/volume/getVolume` | Windows volume get |
| 2 | `/handledHID/clearAll` | Handle HID |
| 2 | `/msr/setCpuPl/37/38/4` | TDP slider 37 W |
| 2 | `/screen/getCurrentSettingResolution` | Display get |
| 2 | `/screen/listResolution` | Display get |
| 1 | `/msr/setCpuPl/11/12/4` | TDP slider 11 W |
| 1 | `/msr/setCpuPl/45/46/4` | TDP slider 45 W (max) |

**Not in this (adapter-only) capture:** `/msr/setCpuPl4`, `/tdp/`,
`/powerplan/`, `/intelpnp/`, `/power/setCpuMaxStatusPercent`, `/dtt/`,
tau / `time_window`. Sliding TDP here only emits `setCpuPl`.

### Live boot + battery + 65 W / 100 W swap

Second Packet Monitor extract (battery inserted, OneXConsole cold start,
then several TDP moves, then 65 W ↔ 100 W adapters). Chronological
TDP-related POSTs:

```
POST /func/setECAccessType/2
POST /func/initBaseEc/1259/1112/1113          # 0xEB, 0x58, 0x59
POST /battery/initPowerSupplyModeEC
POST /func/initMatchKeys
POST /fan/init/common/1098/0/1/1099/184       # 0x4A / 0x4B, PWM max 184
POST /func/initHandleEc/1069/1/0/-1           # 0x2D
POST /func/initOXPSensorEc/1120/1121/1136/1184/1185/1186
POST /powerplan/init/2000
POST /battery/initEc
POST /battery/setChargeLimit/95
POST /battery/setByPassPowerMode/2            # HTTP 2 → EC 3
POST /tdp/init/3/45/46                        # UI min is 3, not 8
POST /battery/setMaxTdpLimit/true
POST /tdp/init/3/45/46
POST /powerplan/setCpuBoostMode/2             # Turbo on, once at boot
POST /msr/setCpuPl4/160/4
POST /msr/setCpuPl/11/12/4                    # restore / first apply
… slider: 18/19, 32/33, 45/46, always after setCpuPl4/160 …
… adapter → 65 W: setCpuPl4/120 + setCpuPl/45/46 (×5) …
… adapter → 100 W: setCpuPl4/160 + setCpuPl/34/35 then 28/29 …
```

Counts that matter: `setCpuPl4/160` ×11, `setCpuPl4/120` ×5,
`setCpuPl/45/46` ×6, plus `11/12`, `18/19`, `32/33`, `34/35`, `28/29`.
Still **no** `/intelpnp/`, `/power/setCpuMaxStatusPercent`, `/dtt/`,
`/powerplan/setCpuMaxClock`, tau. Adapter swaps do **not** add a new
route — they only change the PL4 argument and re-send the current PL1/PL2.

Rules this pcap locks:

| Knob | Live behavior |
|---|---|
| Pairing | Every TDP apply is `setCpuPl4` **then** `setCpuPl` when `0xE3` maps |
| PL2 | Always PL1+1 (`11/12` … `45/46`) |
| Type | Always `4` |
| PL4 | **Adapter class**, not a function of the slider. 100 W / keys `1–5` → **160**; 65 W + battery / key `9` → **120**. 11 W and 45 W both used PL4 160 on the 100 W brick |
| 65 W clamp | Key `8` (JS) clamps the slider to 25/26. Key `9` does **not**: this capture kept `/45/46` while PL4 was 120 |
| `setMaxTdpLimit/true` | Boot only. Slider still moved to 11–45, so this is not “pin to max watts” |
| `tdp/init` | `3/45/46` twice (bounds only) |

The first adapter-only pcap skipped `setCpuPl4` because `0xE3` 16/18 are
unmapped. With a battery the key is `1–5` / `8` / `9` and PL4 is sent.

That is exactly `background.js` `He.setCpuPl(pl1, pl2)` with
`intelTdpSetType=4`. First field is the slider (PL1). Second is
`pl2MappingFunc(PL1)`: on `ONEXPLAYER X2Mini`, **PL2 = PL1+1**, except at
`maxTdp` 45 where PL2 is `maxBoostTdp` **46** (still +1). Live
`11/12`, `37/38`, `45/46` all match. Generic Intel default *before* the
product override is `PL1+5`; X2 Mini replaces it. Third field is the write
backend, not a watt.

Slider IPC is `tdpChanged` → `et.setTdp(W)` → queue `Ye=PL1`, `Je=PL2`.
A ~1.5 s loop runs `makeSetEffect()`:

1. If `adjustAlwaysSetPl4` (Arc G3): `changePl4Func(0xE3)` → PL4 only
   when the key is `1|2|3|4|5` (160), `9` (120), or `8` (65).
   `makeSetEffect` does `if (r) He.setCpuPl4(r)`. Live adapter-only
   `0xE3` **16** / **18** are not in that table, so `r` is `undefined`
   and **no** `/msr/setCpuPl4` is sent. This pcap matches that skip.
2. Then `He.setCpuPl(PL1, PL2)` → `/msr/setCpuPl/{pl1}/{pl2}/4`.

`type=4` is set when DMI CPU string contains `"arc"` and `"g3"` (X2 Mini).
Global default is **3**. OEM `app_config.json` may force 1–4. At startup,
type 4 copies bundled `CCHWApiExt.sys` / `cchwapiext.cat` into
`C:\Program Files\Intel Corporation\Intel(R)CCHWAPI\`
(`IntelPowerPlugin init`). CompatLayerCT then talks to
`IntelPowerPlugin` / `PowerPlugin.dll` (`SetPL1MSR`, `SetPL2MSR`,
`SetPL1MMIO`, `SetPL2MMIO`, `-PL1`/`-PL2`/`-PL4`). Types 1–3 are the
raw `msr-cmd.exe` `0x610` path. There is no JS comment “4 = DTT”; the
plugin + MMIO+MSR exports are the evidence.

`/tdp/init` is still UI bounds only. Live boot sent `/tdp/init/3/45/46`
(min **3**, not the Linux remote’s 8). 65 W adapter **key 8** clamps the
slider to 25/26; **key 9** (65 W + battery, PL4 120) does not — live
`/45/46` + `/setCpuPl4/120` on that brick.

Changing TDP in the UI does **not** write watts into an EC register. After optional `/func/getOXPSetTdpAble`, Electron POSTs:

| CPU | Path | Values |
|---|---|---|
| Intel G3E | `/msr/setCpuPl/{pl1}/{pl2}/{type}` | Watts + `intelTdpSetType` (G3 Arc is `4`) |
| Intel G3E | `/msr/setCpuPl4/{pl4}/{type}` | PL4 watts |
| AMD | `/ryzenadj/setCpuPl/{pl1}/{pl2}` | Watts |
| AMD | `/ryzenadj/setCpuPlAndGpuClock/{pl}/{clock}` | Combined path |

`/tdp/init/...` only refreshes min/max/boost bounds used by the UI.

Package PL is the ceiling. CPU vs GPU **share** is not a watt field on
`setCpuPl`. On G3E the extra knobs already in this route list are the
`{type}` on `/msr/setCpuPl` (`intelTdpSetType=4` = DTT/IPF, not raw RAPL),
`/powerplan/setCpuBoostMode/{0|2}`, `/powerplan/setCpuMaxClock/{MHz}`,
and `/battery/setMaxTdpLimit`. The Intel UI also has “dynamic performance mode” / Adaptive TDP. The exe
has **no** `/dtt/` template. The named extras are
`/intelpnp/setOEMVarWithPowerScheme/{oemVar}` (JS calls it) and
`/power/setCpuMaxStatusPercent/{n}` (exe UriTemplate, not in this JS
invoke list). Full scan:
[compatlayerct-uritemplates.md](compatlayerct-uritemplates.md). See
[tdp.md — CPU vs GPU split](tdp.md#cpu-vs-gpu-split-not-pl1).

### Polling gets while moving the TDP slider

That does **not** replace a POST capture if you want the **path**. The
extracted UriTemplates have `setCpuPl` / `setCpuPl4`, not `getCpuPl`.
OneXConsole “get” routes are still **POST**, and the ones we have are EC:

| You poll | Moves with the TDP slider? |
|---|---|
| `/func/getOXPSetTdpAble` | **No.** `0xED` stays 0. |
| `/func/getOXPSensorInfo` / `getOXPSensorCpuTemp` | Only temps / leftover sensor bytes. |
| `/fan/getFanSpeed` | Only if the fan curve also changes. |
| `/battery/getPowerSupplyMode` | Only if the adapter/`0xE3` class changes. |

So: HTTP get → move slider → HTTP get will look identical for TDP.

To see **hardware** change without capturing POSTs, read RAPL / IA / GT
outside OneXConsole (HWiNFO, Intel XTU, ThrottleStop: Package PL1/PL2/PL4,
IA power, GT power) at the same load, then move the slider. That answers
“what watts/split changed”. It does **not** show extra DTT / powerplan
routes. For those, still capture 1013 or dump UriTemplates.

Probing `POST /msr/getCpuPl` (or `/tdp/get`) is optional; it was not in
the 0.10.2-fix8 string table. A non-`code==1` reply means it is not
there — do not treat that as a new API.

There is **no** tau / `time_window` / `long_term` argument on these routes.
`setCpuPl` writes watts (and, inside CompatLayerCT, the usual RAPL
clamp-enable bits). Firmware PL1 window stays at the BIOS default
(~28 s on live X2 Mini `constraint_0_time_window_us=27983872`).
`changePl4Func` is adapter-class / PL4, not a window write. Adapter-only
`0xE3` 16/18 → no HTTP `setCpuPl4`. Battery + mapped key → `setCpuPl4` on
every slider move and every adapter swap, value 160 or 120 (or 65),
independent of PL1. Linux `oxp-tdp-rapl` uses the same table (and the
16→8 / 18→2 normalize so adapter-only is not stuck on BIOS 55 W). Leave
`time_window_us` alone. See
[tdp.md — Linux TDP policy](tdp.md#linux-tdp-policy-onexconsole-clone).

## How to capture POSTs (Windows)

The Vue F12 Network tab will **never** show these. The main process talks
to CompatLayerCT (pipe or `http.request`), not the renderer. Fiddler /
system-proxy tools usually miss `127.0.0.1` Node requests too. Capture
**loopback TCP 1013**, or stay on the pipe and read WriteFile buffers.

### 1. Switch pipe → HTTP (required for Wireshark / pktmon)

Admin CMD. The file is only read from this path; there is no CLI flag.

```bat
mkdir C:\Windows\OEM 2>nul
if exist C:\Windows\OEM\app_config.json copy /y C:\Windows\OEM\app_config.json C:\Windows\OEM\app_config.json.bak
echo { "isPipeMode": 0 } > C:\Windows\OEM\app_config.json
taskkill /IM OneXConsole.exe /F
taskkill /IM CompatLayerCT.exe /F
```

Start OneXConsole. Log should say `Layer run by webservice`, not
`Layer run by pipe`. Then:

```bat
netstat -ano | findstr :1013
```

`LISTENING` on `127.0.0.1:1013` (or `0.0.0.0:1013`) owned by
`CompatLayerCT.exe`. If 1013 is still closed, you are still on the pipe
— check the JSON is valid (no UTF-16 from `echo` in PowerShell; use CMD
or write the file in notepad as ANSI/UTF-8).

Smoke-test the capture path with a known route **before** hunting DTT:

```bat
curl -s -X POST http://127.0.0.1:1013/func/getOXPSetTdpAble
```

Expect `{ "code": 1, "result": "..." }`. If curl fails, capture will be empty.

### 2. Preferred: Wireshark + Npcap loopback

`127.0.0.1:1013` never hits a Wi-Fi / Ethernet NIC. Windows loopback is
not NDIS, so `pktmon … --comp nics` usually captures **nothing useful**
(or leftover LAN frames that look like “Raw packet”).

Install Npcap with **loopback** support. Capture on **Adapter for
loopback traffic capture**. Capture filter `tcp port 1013`. Same UI
toggle, then Follow TCP Stream and look for `POST /`.

Do not pick the Wi-Fi / Ethernet NIC.

tshark will **not** auto-decode HTTP on port 1013. Force it, or search
bytes (see “tshark says Raw packet / HTTP filter empty” below).

### 3. `pktmon` (built-in; often raw, often misses loopback)

Admin CMD. Do **one** UI gesture per capture so the POST is obvious.

```bat
pktmon filter remove
pktmon filter add -t TCP -p 1013
pktmon start --capture --pkt-size 0 --comp all
```

`--comp all` is required for a chance at localhost. `--comp nics` is the
wrong layer for `127.0.0.1`. Even with `--comp all`, `etl2pcap` often
emits packets with a bogus L2 header; Wireshark then shows **Raw packet
data** and `http.request` is empty. That is a dissect problem, not proof
the POST is missing.

```bat
pktmon stop
pktmon etl2pcap PktMon.etl -o oxp-1013.pcap
pktmon format PktMon.etl -o oxp-1013.txt
findstr /C:"POST /" oxp-1013.txt
```

`pktmon format` dumps the ETL as text/hex and does not need an HTTP
dissector. Keep the `.etl` until you have extracted `POST /` lines.

### 4. tshark says Raw packet / HTTP filter empty

Do this on the machine that has the pcap. Do **not** rename the file
`.jpg` and upload it — the binary will not land here.

**1. See what tshark actually thinks the packets are**

```bat
capinfos oxp-1013.pcap
tshark -r oxp-1013.pcap -T fields -e frame.number -e frame.protocols -e frame.len -c 20
```

Typical bad cases:

| `frame.protocols` | Meaning |
|---|---|
| `eth:ethertype:ip:tcp` (no `http`) | TCP is fine; HTTP not bound to port 1013 |
| `eth:ethertype:data` | **Live X2 Mini Packet Monitor pcapng.** `capinfos` says Ethernet, but the EtherType is not IPv4/IPv6, so tshark never builds IP/TCP/HTTP. 60-byte frames are Ethernet min padding; keep the 200–1400 byte ones. |
| `eth:data` / `data` / “Raw packet data” | Same class of `etl2pcap` L2 lie |
| empty / only ARP / IPv6 MDNS | Capture missed loopback; recapture with Npcap |

Do **not** `editcap -T rawip` on a file `capinfos` already calls Ethernet — that eats the first 14 bytes of each frame. Search the `data` payload instead.

**2. If TCP is present: Decode As HTTP on 1013**

Wireshark: right-click a 1013 frame → **Decode As…** → TCP port 1013 →
HTTP.

tshark (two-pass so requests split across segments still reassemble):

```bat
tshark -2 -r oxp-1013.pcap -d tcp.port==1013,http -Y "http.request.method == POST" -T fields -e frame.number -e http.request.uri
```

**3. If it is only raw (`eth:ethertype:data`): ignore HTTP, search ASCII**

The POST line is still `POST /msr/setCpuPl/…` in the payload. Do not
wait for a dissector. On a Packet Monitor file the bytes live in
`data.text`, not `http.request.uri`.

```bat
REM CMD: do not write \". A backslash is a literal and the filter misses.
tshark -r oxp-1013.pcap -Y "frame contains POST" -T fields -e frame.number -e frame.len
```

`data.text contains "POST /"` was empty on the live Packet Monitor file
even when `POST /` is in the bytes. Use PowerShell ASCII (below). In
`cmd.exe`, `\"` is also wrong quoting.

PowerShell (works on pktmon “raw” and on Npcap loopback):

```powershell
$pcap = 'C:\path\to\oxp-1013.pcap'
$text = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($pcap))
[regex]::Matches($text, 'POST /[A-Za-z0-9_./-]+') |
  ForEach-Object { $_.Value } |
  Group-Object |
  Sort-Object Count -Descending |
  ForEach-Object { '{0,5}  {1}' -f $_.Count, $_.Name }
```

If that list is empty, the pcap does not contain the OneXConsole POSTs.
Recapture on the Npcap loopback adapter (section 2), after
`isPipeMode: 0` and a working
`curl -s -X POST http://127.0.0.1:1013/func/getOXPSetTdpAble`.

**4. Optional: restamp a raw-IP pcap so tshark grows TCP/HTTP layers**

Only if `capinfos` says the link type is raw / user / unknown:

```bat
editcap -T rawip oxp-1013.pcap oxp-rawip.pcap
tshark -2 -r oxp-rawip.pcap -d tcp.port==1013,http -Y "http.request.method == POST" -T fields -e http.request.uri
```

If `editcap -T rawip` makes it worse, try `-T linux-sll` or just stay
with the ASCII extract. Paste the unique `POST /…` lines (and any JSON
body on the next few lines). Do not send the pcap.

### 5. If you must stay on the pipe

Default `isPipeMode=1` uses `\\.\pipe\CompatLayerCT` (same URL paths, not
HTTP). Wireshark will see nothing on 1013.

- Sysinternals **Process Monitor**: process `OneXConsole.exe` /
  `CompatLayerCT.exe`, operation `WriteFile`, path contains
  `\pipe\CompatLayerCT`. Enable **stack + detail**; the buffer is the
  `POST /…` line. Noisy; still usable for a single toggle.
- API Monitor on `WriteFile` for that pipe — same idea.

There is no public `/ECRamReadByte` HTTP route to watch instead.

### 6. What to click, what to keep

One toggle per pcap. Write down: control name, before/after, file name.

| You click | Paths to keep |
|---|---|
| **Cold start (no click)** | See section 7. `init*`, `/tdp/init`, first `setCpuPl` / `setCpuPl4`, `/powerplan/`, `/intelpnp/`. |
| TDP slider | Always `/msr/setCpuPl/{pl1}/{pl1+1}/4`. Plus `/msr/setCpuPl4/{160\|120\|65}/4` first when `0xE3` maps (battery / known adapter key). Adapter-only 16/18: no PL4 POST. |
| Turbo / CPU boost / max clock | `/powerplan/` |
| Intel dynamic performance / Adaptive TDP / Follow FPS | `/intelpnp/`, `/power/setCpuMaxStatusPercent`, `/powerplan/`, `/msr/` — no `/dtt/` in the exe |
| Fan / charge (sanity) | `/fan/`, `/battery/` — already mapped; use only to prove capture works |

Ignore startup `init*` **after** you have one boot capture. Decode init
addresses with `reg = encoded - 0x400` (1259 → `0xEB`). Live set routes
are already human values (`40`, `25`, `true`).

### 7. Startup capture (one shot)

Slider-only pcaps miss boot work: `init*`, `/tdp/init`, IntelPowerPlugin
bring-up, restored last TDP, and any one-shot `/powerplan/` /
`/intelpnp/` / `setCpuPl4`. Capture **from before `OneXConsole.exe`
starts** until the window is idle. Do not touch the TDP slider.

**Already proven on this unit:** Packet Monitor pcapng is
`eth:ethertype:data`. Do not wait for tshark HTTP. Extract ASCII with
PowerShell. Prefer the same `pktmon --comp all` path that already
worked, or Npcap loopback.

#### A. HTTP mode must already work

Admin **CMD** (not PowerShell — `echo` there writes UTF-16 and the exe
ignores the file):

```bat
mkdir C:\Windows\OEM 2>nul
if exist C:\Windows\OEM\app_config.json copy /y C:\Windows\OEM\app_config.json C:\Windows\OEM\app_config.json.bak
echo { "isPipeMode": 0 } > C:\Windows\OEM\app_config.json
type C:\Windows\OEM\app_config.json
```

`type` must show exactly `{ "isPipeMode": 0 }` on one line. Then start
OneXConsole **once**, confirm, and only then kill it:

```bat
netstat -ano | findstr :1013
curl -s -X POST http://127.0.0.1:1013/func/getOXPSetTdpAble
```

Need `LISTENING` on 1013 and a JSON `{ "code": 1, ... }`. Log line:
`Layer run by webservice`. If 1013 is closed, stop here — startup
capture will be empty.

Write down before killing: AC vs battery, last TDP the UI showed.
Adapter-only `0xE3` 16/18 still will not map `changePl4Func`; the
question is whether boot sends `setCpuPl4` anyway.

#### B. Stop the app so the next launch is a real start

```bat
taskkill /IM OneXConsole.exe /F
taskkill /IM CompatLayerCT.exe /F
timeout /t 2
tasklist | findstr /I "OneXConsole CompatLayerCT"
```

`tasklist` must show neither. If OneXConsole is “start with Windows”
or a helper relaunches it, disable that for this shot or the capture
starts mid-init.

#### C. Start capture, then start the app

Admin CMD, working directory you will remember (`C:\Users\hanxiao`):

```bat
cd /d C:\Users\hanxiao
pktmon filter remove
pktmon filter add -t TCP -p 1013
pktmon start --capture --pkt-size 0 --comp all
```

Now start OneXConsole from the Start menu (or the installed shortcut).
Do **not** move TDP / Turbo / Adaptive / fan. Wait until the window is
fully up, then **10 more seconds** (first `makeSetEffect` is ~1.5 s;
plugin copy can take longer). About 20–40 s of UI-up time is enough.
Longer only adds `getPowerSupplyMode` / temp / `listAllProcess` polls.

```bat
pktmon stop
pktmon etl2pcap PktMon.etl -o oxp-1013-startup.pcap
pktmon format PktMon.etl -o oxp-1013-startup.txt
```

Keep `PktMon.etl` until the POST list looks right.

Npcap alternative: start Wireshark on **Adapter for loopback traffic
capture**, filter `tcp port 1013`, start capture, *then* launch
OneXConsole, then stop. Same extract below.

#### D. Extract request **and** response (not a blanket `HTTP` regex)

CompatLayerCT answers are **not** another `POST`. They look like:

```
HTTP/1.1 200 OK
Content-Type: application/json

{"code":1,"result":"..."}
```

Do **not** widen the path regex to the word `HTTP`. That hits the
request line (`POST /foo HTTP/1.1`), every `Host:` / `Content-Type`
header, and still misses the JSON. Three separate tokens, merged by
file offset:

| Token | Regex | What it is |
|---|---|---|
| Request | `POST /[A-Za-z0-9_./-]+` | Path (already proven on the slider pcap) |
| Status | `HTTP/1\.[01] \d{3}` | Response line only (`POST … HTTP/1.1` has no ` \d{3}`) |
| Body | `\{[^{}]*"code"[^{}]*\}` | Wrapper JSON. Init *request* bodies (`addrChargeLimit`, …) have no `"code"`, so they stay out |

`cmd.exe` tshark `data.text` / `\"` filters stay empty on this
Packet Monitor file. Use PowerShell 7. Pair each POST with the next
status + `"code"` JSON that appear **before the next POST** (TCP
splits can leave a hole; that line is still useful):

```powershell
$pcap = 'C:\Users\hanxiao\oxp-1013-startup.pcap'
$text = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($pcap))
$interesting = 'POST /(?:msr|tdp|powerplan|intelpnp|power/|func/(?:set|init)|fan/init|battery/init|battery/set|battery/getPowerSupplyMode|func/getOXPSetTdpAble)'

$ev = [System.Collections.Generic.List[object]]::new()
foreach ($m in [regex]::Matches($text, 'POST /[A-Za-z0-9_./-]+')) {
  $ev.Add([pscustomobject]@{ At = $m.Index; Kind = 'REQ'; Text = $m.Value })
}
foreach ($m in [regex]::Matches($text, 'HTTP/1\.[01] \d{3}[^\r\n]{0,40}')) {
  $ev.Add([pscustomobject]@{ At = $m.Index; Kind = 'STATUS'; Text = $m.Value.Trim() })
}
foreach ($m in [regex]::Matches($text, '\{[^{}]{0,800}?"code"[^{}]{0,800}\}')) {
  $ev.Add([pscustomobject]@{ At = $m.Index; Kind = 'JSON'; Text = ($m.Value -replace '[^\x20-\x7E]+',' ') })
}
$ev = $ev | Sort-Object At

function Show-Pair($req, $items) {
  if (-not $req) { return }
  $st = @($items | Where-Object Kind -eq 'STATUS') | Select-Object -First 1
  $js = @($items | Where-Object Kind -eq 'JSON')   | Select-Object -First 1
  $req.Text
  if ($st) { '    {0}' -f $st.Text } else { '    (no HTTP status before next POST)' }
  if ($js) { '    {0}' -f $js.Text } else { '    (no {"code"} JSON before next POST)' }
}

'--- transcript (interesting paths) ---'
$pending = $null; $buf = @()
foreach ($e in $ev) {
  if ($e.Kind -eq 'REQ') {
    if ($pending -and $pending.Text -match $interesting) { Show-Pair $pending $buf }
    $pending = $e; $buf = @()
  } elseif ($pending) { $buf += $e }
}
if ($pending -and $pending.Text -match $interesting) { Show-Pair $pending $buf }

'--- POST counts ---'
$ev | Where-Object Kind -eq 'REQ' | Group-Object Text | Sort-Object Count -Descending |
  ForEach-Object { '{0,5}  {1}' -f $_.Count, $_.Name }
```

`getPowerSupplyMode` / `getOXPSetTdpAble` are in the interesting list
on purpose: their **result** is the live `0xE3` / `0xED` byte. Slider
POSTs have empty request bodies; the useful JSON is the response.

Paste the **interesting transcript + POST counts**. Do not upload the
pcap. A good startup list should include most of:

```
POST /func/setECAccessType/2
POST /func/initBaseEc/...
POST /func/initHandleEc/...
POST /func/initOXPSensorEc/...
POST /fan/init/...
POST /battery/initEc
POST /battery/initPowerSupplyModeEC
POST /tdp/init/3/45/46
```

New vs the 58 s slider pcap (those are the reason for this shot):

| Path | Why we care |
|---|---|
| `/msr/setCpuPl4/{pl4}/4` | Yes with battery: 160 on 100 W, 120 on 65 W+battery. Absent on adapter-only 16/18. |
| `/msr/setCpuPl/{pl1}/{pl2}/4` | Restored last slider, not a new gesture |
| `/intelpnp/setOEMVarWithPowerScheme/{n}` | DTT-shaped OEM var |
| `/powerplan/setCpuBoostMode/{0\|2}` | Turbo restore |
| `/powerplan/setCpuMaxClock/{MHz}` | IA cap restore |
| `/power/setCpuMaxStatusPercent/{n}` | Exe-only; JS 0.10.2-fix8 does not invoke it |
| `/battery/setChargeLimit/` / `setByPassPowerMode/` | Saved charge policy writes |
| anything else under `/msr/`, `/power`, `/intel` | Unknown — keep the full path |

`IntelPowerPlugin init` is a **file copy** of `CCHWApiExt.sys` into
`C:\Program Files\Intel Corporation\Intel(R)CCHWAPI\`, not an HTTP
route. Absence of `/dtt/` is expected.

If the interesting list is only the 1.6 s polls (`getPowerSupplyMode`,
`getOXPSensorCpuTemp`, `listAllProcess`), capture started after init or
HTTP mode was off. Re-check section A and start pktmon *before* the
exe.

Copy the **full path + JSON body** (often empty). `code == 1` is success.

Do not write unknown addresses from a replayed `init*` or `set*` call; the
write packing for OxpWMI is still only confirmed for reads.

Restore pipe mode when done: put `isPipeMode` back to `1` (or restore the
`.bak`) and restart OneXConsole. HTTP mode is only for capture.
