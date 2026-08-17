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

Init routes put **encoded EC addresses** in the path (`encoded = 0x400 + reg`). Later get/set routes send **logical values** (percent, watts, 0/1), not raw register numbers. There is no public `/ECRamReadByte` HTTP route; `ECRamReadByte` / `ECRamDirectWrite` stay inside CompatLayerCT after init.

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
| POST | `/battery/setChargeLimit/{percent}` | Charge-limit byte |
| POST | `/battery/setByPassPowerMode/{mode}` | Bypass 0 / 1 / 3 |
| POST | `/battery/setMaxTdpLimit/{true\|false}` | Whether max-TDP lock is applied |

## TDP watts (not EC)

Changing TDP in the UI does **not** write watts into an EC register. After optional `/func/getOXPSetTdpAble`, Electron POSTs:

| CPU | Path | Values |
|---|---|---|
| Intel G3E | `/msr/setCpuPl/{pl1}/{pl2}/{type}` | Watts + `intelTdpSetType` (G3 Arc is `4`) |
| Intel G3E | `/msr/setCpuPl4/{pl4}/{type}` | PL4 watts |
| AMD | `/ryzenadj/setCpuPl/{pl1}/{pl2}` | Watts |
| AMD | `/ryzenadj/setCpuPlAndGpuClock/{pl}/{clock}` | Combined path |

`/tdp/init/...` only refreshes min/max/boost bounds used by the UI.

## How to use this on the device

1. Start OneXConsole. Confirm `CompatLayerCT.exe` and `netstat` `:1013`.
2. If 1013 is closed, set `C:\Windows\OEM\app_config.json` `isPipeMode` to `0` and restart.
3. In a second browser or Fiddler, watch `http://localhost:1013`. Filter `/func/`, `/fan/`, `/battery/`, `/msr/`, `/ryzenadj/`.
4. Change fan / charge / TDP in the UI and read the path numbers.
5. Decode init addresses with `reg = encoded - 0x400` (1259 → `0xEB`). Live set routes are already human values (40, 25, `true`).

Do not write unknown addresses from a replayed `init*` or `set*` call; the write packing for OxpWMI is still only confirmed for reads.
