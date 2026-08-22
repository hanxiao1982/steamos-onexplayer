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

Live X2 Mini capture (slider **37 W**):

```
POST /msr/setCpuPl/37/38/4
```

That is exactly `background.js` `He.setCpuPl(pl1, pl2)` with
`intelTdpSetType=4`. First field is the slider (PL1). Second is
`pl2MappingFunc(PL1)`: on `ONEXPLAYER X2Mini`, **PL2 = PL1+1**, except at
`maxTdp` 45 where PL2 is `maxBoostTdp` **46** (still +1). Generic Intel
default *before* the product override is `PL1+5`; X2 Mini replaces it.
Third field is the write backend, not a watt.

Slider IPC is `tdpChanged` → `et.setTdp(W)` → queue `Ye=PL1`, `Je=PL2`.
A ~1.5 s loop runs `makeSetEffect()`:

1. If `adjustAlwaysSetPl4` (Arc G3): `changePl4Func(0xE3)` →
   `He.setCpuPl4(160|120|65, 4)` **first**.
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

`/tdp/init` is still UI bounds only. 65 W adapter (`0xE3` key 8) also
clamps the slider to 25/26 — a 37 W POST means that clamp is not active.

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
`changePl4Func` is adapter-class / PL4, not a window write. Linux should
copy that: set PL1/PL2/PL4 watts, leave `time_window_us` alone. A short
tau is a measurement convenience, not a OneXConsole clone. See
[tdp.md](tdp.md#onexconsole-and-long_term-tau).

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

### 2. Preferred: `pktmon` (built-in, no extra install)

Admin CMD. Do **one** UI gesture per capture so the POST is obvious.

```bat
pktmon filter remove
pktmon filter add -t TCP -p 1013
pktmon start --capture --pkt-size 0 --comp nics
```

In OneXConsole, toggle **one** control (Intel dynamic performance, Turbo,
TDP slider, CPU boost). Then:

```bat
pktmon stop
pktmon etl2pcap PktMon.etl -o oxp-1013.pcap
```

Open `oxp-1013.pcap` in Wireshark. Display filter:

```
tcp.port == 1013 && http.request.method == "POST"
```

If Wireshark does not decode HTTP (chunked WCF), follow the TCP stream
(`Follow` → `TCP Stream`) and look for `POST /`.

`PktMon.etl` lands in the current directory. Convert is optional; Wireshark
can also open the etl after `etl2pcap`.

### 3. Wireshark + Npcap loopback

Install Npcap with **loopback** support. Capture on
**Adapter for loopback traffic capture**. Filter `tcp.port == 1013`.
Same UI toggle, then `http.request.method == "POST"` or Follow TCP Stream.

Do not pick the Wi-Fi / Ethernet NIC — this traffic never leaves the box.

### 4. If you must stay on the pipe

Default `isPipeMode=1` uses `\\.\pipe\CompatLayerCT` (same URL paths, not
HTTP). Wireshark will see nothing on 1013.

- Sysinternals **Process Monitor**: process `OneXConsole.exe` /
  `CompatLayerCT.exe`, operation `WriteFile`, path contains
  `\pipe\CompatLayerCT`. Enable **stack + detail**; the buffer is the
  `POST /…` line. Noisy; still usable for a single toggle.
- API Monitor on `WriteFile` for that pipe — same idea.

There is no public `/ECRamReadByte` HTTP route to watch instead.

### 5. What to click, what to keep

One toggle per pcap. Write down: control name, before/after, file name.

| You click | Paths to keep |
|---|---|
| TDP slider | `/msr/setCpuPl/`, `/msr/setCpuPl4/`, `/tdp/` |
| Turbo / CPU boost / max clock | `/powerplan/` |
| Intel dynamic performance / Adaptive TDP / Follow FPS | `/intelpnp/`, `/power/setCpuMaxStatusPercent`, `/powerplan/`, `/msr/` — no `/dtt/` in the exe |
| Fan / charge (sanity) | `/fan/`, `/battery/` — already mapped; use only to prove capture works |

Ignore startup `init*` after the first boot capture. Decode init
addresses with `reg = encoded - 0x400` (1259 → `0xEB`). Live set routes
are already human values (`40`, `25`, `true`).

Copy the **full path + JSON body** (often empty). `code == 1` is success.

Do not write unknown addresses from a replayed `init*` or `set*` call; the
write packing for OxpWMI is still only confirmed for reads.

Restore pipe mode when done: put `isPipeMode` back to `1` (or restore the
`.bak`) and restart OneXConsole. HTTP mode is only for capture.
