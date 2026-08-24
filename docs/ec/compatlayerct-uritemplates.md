# CompatLayerCT.exe UriTemplates (0.10.2-fix8)

Source: official installer `OneXConsole_0.10.2-fix8.exe` from
`https://app.onexconsole.com/web/agg/app:download`. Binary path inside the
NSIS / `app-64.7z` payload:

`resources/resources/CompatLayerCT.exe`

Installer and exe are **not** in this repo. Strings were scanned on Linux
(ASCII + UTF-16LE). WCF stores `[WebInvoke(UriTemplate=…)]`; a one-byte
length prefix sits in front of some paths and was stripped. Trailing `TU`
is a UTF-16 extract artifact.

`background.js` invoke paths (270) are a **caller** list. The exe can
expose a template the JS of this build never calls.

## Not present

No `getCpuPl`, `getCpuPl4`, `/dtt/`, `/ipf/`, `/xtu/`, or
`time_window` / `tau` / `long_term` template.

TDP slider cannot be observed by polling OneXConsole gets. The only TDP
“get” is `/func/getOXPSetTdpAble` (EC `0xED`, stays 0 on X2 Mini).

## Power / TDP / CPU↔GPU (this is why we scanned)

| Template | In `background.js`? | Role |
|---|---|---|
| `msr/setCpuPl/{pl1}/{pl2}/{type}` | yes (`intelTdpSetType`) | Live: `11/12`, `18/19`, `32/33`, `34/35`, `28/29`, `37/38`, `45/46` type **4**. PL2=PL1+1. |
| `msr/setCpuPl4/{pl4}/{type}` | yes | Adapter-class PL4. Battery: 160 (100 W) / 120 (65 W+battery) before every `setCpuPl`. Adapter-only 16/18: not sent. |
| `tdp/init/{minTdp}/{maxTdp}/{maxBoostTdp}` | yes | UI slider bounds only. Live boot: `3/45/46`. |
| `ryzenadj/setCpuPl/{pl1}/{pl2}` | yes | AMD. |
| `ryzenadj/setGpuClock/{clock}` | yes | AMD; X2 Mini does not enable this. |
| `ryzenadj/setCpuPlAndGpuClock/{pl}/{clock}` | yes | AMD combined. |
| `func/getOXPSetTdpAble` | yes | EC gate. |
| `battery/setMaxTdpLimit/{isLimit}` | yes | Live boot: `true`. Slider still moved 11–45 W. |
| `powerplan/setCpuBoostMode/{boostMode}` | yes | Live boot: `2` (Turbo on), once. Not re-sent on TDP or adapter swap. |
| `powerplan/setCpuMaxClock/{clock}` | yes | Cap IA MHz. |
| `powerplan/setCpuCorePriority/{corePriority}` | yes | Core parking / priority. |
| `powerplan/init/{cpuMaxClockThreshold}` | yes | Live boot: `/powerplan/init/2000`. |
| `powerplan/getSleepHibernateTimeout` | yes | Sleep. |
| `powerplan/setSleepHibernateTimeout/{minutes}` | yes | Sleep. |
| `powerplan/isHyperThreadingDisabled` | yes | HT. |
| `powerplan/setHyperThreadingDisabled/{disable}` | yes | HT. |
| **`power/setCpuBoostMode/{boostMode}`** | **no** | Same idea as `powerplan/…`, extra exe route. |
| **`power/setCpuMaxStatusPercent/{cpuMaxStatusPercent}`** | **no** | Windows “processor maximum state” (%). Caps IA so GT can keep package watts. Closest **named** CPU↔GPU share knob in this binary. JS 0.10.2-fix8 does not `invoke` it — either unused, built at runtime, or used by another front-end. |
| **`intelpnp/setOEMVarWithPowerScheme/{oemVar}`** | **yes** | Intel PnP OEM variable via the power scheme. This is the DTT/Adaptive-Performance-shaped write, not RAPL watts. |

Internal (not HTTP templates), same binary: `MsrService`, `msr-cmd.exe`,
`/rdmsr 0x610`, `/wrmsr 0x610 …`, `get_msr_limit`, `set_msr_limits`,
`RyzenAdjService`, `msiSetTdpByDevice`. Type 4 still goes through DTT/IPF
even though a raw `0x610` helper exists.

`background.js` also invokes `/powerplan/getCpuBoostMode` and
`/osd/getAllHWiNFO`. Those two did **not** appear next to a `UriTemplate`
string (they may still exist; the attribute dump is not a 100% method
list).

## Full cleaned template list (154)

Paths are relative to `http://localhost:1013/` (POST).

```
battery/getPowerSupplyMode
battery/initEc
battery/initPowerSupplyModeEC
battery/setByPassPowerMode/{mode}
battery/setChargeLimit/{percent}
battery/setMaxTdpLimit/{isLimit}
coolingsystem/checkPairedConnect
coolingsystem/disconnect/{unpair}
fan/automate/{enabled}
fan/getFanSpeed
fan/init/{fanMode}/{addrFanAutomate}/{valueFanAutomateOn}/{valueFanAutomateOff}/{addrFanSpeed}/{valueFanSpeedValue}
fan/setFanSpeed/{fanSpeed}
fridge/resumeProcess/{processId}
fridge/suspendProcess/{processId}
func/checkSetProcessAffinity
func/focusMostTopGameWindow
func/fshEnabled/{enabled}
func/getBindableProcess
func/getHwndByWindowTitle?windowTitles={windowTitles}
func/getOXPSensorCpuTemp
func/getOXPSensorInfo
func/getOXPSetTdpAble
func/getProcessIdsByName/{processName}
func/getProcessorCount
func/initBaseEc/{appFunENECAddr}/{fanSpeedHECAddr}/{fanSpeedLECAddr}
func/initHandleEc/{addrHandlePower}/{valueHandlePowerOn}/{valueHandlePowerOff}/{valueHandlePowerOnResotre}
func/initMatchKeys
func/initOXPSensorEc/{addrBoardSensor1}/{addrBoardSensor2}/{addrCpuTemp}/{addrBatteryTemp}/{addrBatteryChargeCurrentH}/{addrBatteryChargeCurrentL}
func/isForegroundWindowFullScreen
func/isWinX86/{processId}
func/listAllProcess
func/openWebSite?webSite={webSite}
func/refreshTray
func/scaleToFullScreen/{hwnd}/{type}/{keepFullscreen}
func/setECAccessType/{type}
func/setForegroundFullScreen
func/setFullScreen/{hwnd}
func/setK12CustomMode/{mode}
func/setTopMost/{hwnd}
func/takeOverTurboButton/{enabled}
gyro/getExecutingAssemblyLocation
gyro/setAccAxis/{accXAxisType}/{accXAxisReverse}/{accYAxisType}/{accYAxisReverse}/{accZAxisType}/{accZAxisReverse}
gyro/setAdaptiveTriggerMode/{adaptiveTriggerMode}
gyro/setGyroAxis/{gyroXAxisType}/{gyroXAxisReverse}/{gyroYAxisType}/{gyroYAxisReverse}/{gyroZAxisType}/{gyroZAxisReverse}
gyro/setGyroMouseLightRate/{gyroMouseLightRate}
gyro/setGyroMouseRate/{gyroMouseRate}
gyro/setGyroXboxLightRate/{gyroXboxLightRate}
gyro/setGyroXboxMaxSteeringXAngle/{gyroXboxMaxSteeringXAngle}
gyro/setGyroXboxMaxSteeringYAngle/{gyroXboxMaxSteeringYAngle}
gyro/setGyroXboxMinThumbXValue/{gyroXboxMinThumbXValue}
gyro/setGyroXboxMinThumbYValue/{gyroXboxMinThumbYValue}
gyro/setGyroXboxRate/{gyroXboxRate}
gyro/setSimulateRockerMode/{simulateRockerMode}
gyro/setSteeringMode/{steeringMode}
gyro/setTriggerMode/{triggerMode}
gyro/setXInputControllerMode/{xInputControllerMode}
gyro/xInputPlusInjectProcess/{processId}
handledHID/forceXboxGamepadUseHid/{isForce}
handledHID/initWindowStatus/{windowName}/{hwnd}/{isDebug}
handledHID/setMouseSimulate/{mouseSimulate}
handledHID/setSimulateEnabled/{simulateEnabled}
handledHID/setSupportHandleMode/{enableProgramHandle}/{enableMappingHandle}
handykit/enableWindowsTabletMode/{enable}
handykit/enableWindowsUpdate/{enable}
handykit/setClickToDoDisabled/{disable}
hardware/controllerToVKMapping/{enabled}
hardware/enableTouchScreen/{enable}
hardware/gamepadHIDReg/{enabled}
hardware/getDiskdriveSerialnumber
hardware/getVideoMemory370PlatformPlus
hardware/setVideoMemory370PlatformPlus/{plus}
hardware/setVideoMemoryPlus/{plus}
hardware/syncCloseControllerToVKMapping/{enabled}
intelpnp/setOEMVarWithPowerScheme/{oemVar}
joycon/setJoyconBundle/{handle}/{isBundle}
keyboard/quickButtonHookStart/{type}
keyboard/sendkeys/{type}?keyEvents={keyEvents}
library/checkDirectoryProcesses/{byProcessNames}?directory={directory}
library/existXboxGameStarter?directory={directory}
library/isRunningByFullPath?path={path}
library/killProcessByContext?path={path}
library/killProcessByExe?path={path}
library/runCustomGame?path={path}
library/runXboxGame?directory={directory}
library/uninstallUWPApp?appPackageName={appPackageName}
motor/shake/{seconds}/{leftMotor}/{rightMotor}
mouse/horizontalScroll/{scrollAmountInClicks}
mouse/verticalScroll/{scrollAmountInClicks}
msr/setCpuPl/{pl1}/{pl2}/{type}
msr/setCpuPl4/{pl4}/{type}
osd/getHWiNFOSharedMemPollTimeMillis
osd/stopRTSSFramerateLimitServer
power/setCpuBoostMode/{boostMode}
power/setCpuMaxStatusPercent/{cpuMaxStatusPercent}
powerplan/getSleepHibernateTimeout
powerplan/init/{cpuMaxClockThreshold}
powerplan/isHyperThreadingDisabled
powerplan/setCpuBoostMode/{boostMode}
powerplan/setCpuCorePriority/{corePriority}
powerplan/setCpuMaxClock/{clock}
powerplan/setHyperThreadingDisabled/{disable}
powerplan/setSleepHibernateTimeout/{minutes}
programhandle/commonhid/enterCalibrateMode
programhandle/commonhid/setMotorLevel/{level}
programhandle/ph/changeReportMode
programhandle/ph/effectRockerModeAndKeyMapping
programhandle/ph/getKeyMappingInfo/{mode}
programhandle/ph/getTriggerRockerInfo
programhandle/ph/setKeyMappingInfo
programhandle/ph/setTriggerRockerInfo
programhandle/rgb/assignSetColor/{target}/{r}/{g}/{b}
programhandle/rgb/assignSetOpen/{target}/{open}
programhandle/rgb/setColor/{r}/{g}/{b}
programhandle/rgb/setOpen2/{open}/{lightLevel}
programhandle/rgb/setPreset/{mode}
programhandle/setType/{type}/{exLine}/{rgbPartitionType}
rgb/setOpen2/{open}/{lightLevel}
rgbPartition/setColor/{pcode}/{r}/{g}/{b}/{rgbPureBreathing}
rgbPartition/setOpen/{pcode}/{open}/{lightLevel}
rgbPartition/setPreset/{pcode}/{mode}
rog/setAuraBrightnessPercent/{brightnessPercent}
ryzenadj/setCpuPl/{pl1}/{pl2}
ryzenadj/setCpuPlAndGpuClock/{pl}/{clock}
ryzenadj/setGpuClock/{clock}
screen/getCurrentSettingResolution
screen/setColorRamp/{brightnessValue}/{contrastValue}/{gammaValue}
screen/setDisplayRefreshRate/{refreshRate}
screen/setResolution/{width}/{height}
tdp/init/{minTdp}/{maxTdp}/{maxBoostTdp}
volume/playSoundImmediately/{fileName}/{volume}
volume/setDefaultOutputDevice/{outputDeviceGUID}
windows/gameOptimizer/isDeliveryOptimizationDisabled
windows/gameOptimizer/isGameTaskOptimized
windows/gameOptimizer/isHagsDisabled
windows/gameOptimizer/isMpoDisabled/{landscapeScreen}
windows/gameOptimizer/isSystemSchedulingOptimized
windows/gameOptimizer/isTdrDelayEnabled
windows/gameOptimizer/setDeliveryOptimizationDisabled/{disable}
windows/gameOptimizer/setGameTaskOptimized/{optimize}
windows/gameOptimizer/setHagsDisabled/{disable}
windows/gameOptimizer/setMpoDisabled/{disable}/{landscapeScreen}
windows/gameOptimizer/setSystemSchedulingOptimized/{optimize}
windows/gameOptimizer/setTdrDelayEnabled/{enable}
windows/interactionOptimizer/isCompactModeEnabled
windows/interactionOptimizer/isIconCacheExtended
windows/interactionOptimizer/isMenuHoverDelayDisabled
windows/interactionOptimizer/isMouseHoverDelayReduced
windows/interactionOptimizer/isVisualEffectsOptimized
windows/interactionOptimizer/setCompactModeEnabled/{enable}
windows/interactionOptimizer/setIconCacheExtended/{extend}
windows/interactionOptimizer/setMenuHoverDelayDisabled/{disable}
windows/interactionOptimizer/setMouseHoverDelayReduced/{reduce}
windows/interactionOptimizer/setVisualEffectsOptimized/{optimize}
xbox/fse/setEnable/{enable}/{enableStartTouchKeyboard}
```

Re-scan locally:

```bash
curl -L -o OneXConsole_0.10.2-fix8.exe https://app.onexconsole.com/web/agg/app:download
7z x OneXConsole_0.10.2-fix8.exe
7z x '$PLUGINSDIR/app-64.7z' -oapp
# then strings / UTF-16 scan app/resources/resources/CompatLayerCT.exe
```
