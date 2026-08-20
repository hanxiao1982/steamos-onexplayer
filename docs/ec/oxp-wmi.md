# oxp-wmi — Linux WMI client for OneXPlayer Intel

Out-of-tree module: [`linux/oxp-wmi/`](../../linux/oxp-wmi/).

Same *shape* as in-tree `msi-wmi-platform`: `struct wmi_driver`, mutex, hwmon, debugfs. Different GUID, methods, and Arg2 type. Default path is ACPI method **`WMAC` with Integer Arg2** (Windows CIM). `wmidev_evaluate_method()` Buffer Arg2 is fallback only if WMAC is missing. Do **not** bind the MSI GUID.

OxpWMI is the Intel path (`ecAccessType=2`). AMD / WinRing0 boards stay on `oxpec`.

Register map (current OneXConsole Intel table): [x2-mini.md](x2-mini.md). Protocol: [linux-wmi.md](linux-wmi.md), [access.md](access.md). Per-SKU offsets can be added later; the WMI transport stays the same.

**X2 Mini Bazzite live:** WMAC Integer Arg2. `pwm1=153` (~60%) held ~4400 RPM; auto restore dropped RPM. Charge sysfs is present, not soak-tested.

## What it controls

| Sysfs | EC | Notes |
|---|---|---|
| `hwmon/oxp_wmi/fan1_input` | `0x58`/`0x59` BE16 | RPM, read-only |
| `hwmon/oxp_wmi/pwm1` | `0x4B` | hwmon 0–255 ↔ EC 0–184 (same scale as `oxpec` X1) |
| `hwmon/oxp_wmi/pwm1_enable` | `0x4A` | `1` manual (then **rewrite `0x4B`** to latch), `2` auto (`0` = manual + 100%) |
| `hwmon/oxp_wmi/temp1_input` | `0x70` | millidegree C |
| `charge_control_end_threshold` | `0xA3` | 0–100 (UI uses 50–100 step 5) |
| `charge_behaviour` | `0xA4` | `auto` / `inhibit-charge-awake` / `inhibit-charge` → 0 / 1 / 3 |
| `power_supply_mode` | `0xE3` | read-only; prints raw + oxp-normalized key |

Not implemented (unused on the current Intel table, or not EC): `0xEB`, `0x2D`, `0xED`, `0xA5`, board temps, TDP, RGB.

## Build / load

X2 Mini (and other Intel G3E SKUs) go through the same `kmod/` deploy path as AMD boards. `ec-stack.sh` sees `ONEXPLAYER X2Mini` and builds **oxp-wmi**, not oxpec.

```
# On the handheld, or via ssh-handheld.sh user@host all
kmod/scripts/ec-stack.sh                  # should print oxp-wmi
kmod/scripts/apply-all.sh                 # make linux/oxp-wmi/oxp-wmi.ko
sudo kmod/scripts/test-oxp-wmi.sh
sudo kmod/scripts/install-oxp-wmi.sh      # /var/lib/oxp-kmod + systemd
sudo kmod/scripts/install-inputplumber.sh
sudo kmod/scripts/install-tdp-rapl.sh     # TdpLimit1 → RAPL; no-op on AMD
```

CachyOS / Bazzite one-shot (`install-cachyos.sh` / `install-bazzite.sh` / `on-device-install.sh`) detect the stack and take this path automatically.

Manual:

```
cd linux/oxp-wmi
make
sudo insmod oxp-wmi.ko
# or: sudo insmod oxp-wmi.ko force=1   # skip DMI / probe-read checks
```

DMI: `Manufacturer` or `Board Vendor` contains `ONE-NETBOOK`. Known AMD products (`ONEXPLAYER X2Mini PRO`, `ONEXPLAYER APEX`) are denied. The WMI GUID only exists on OxpWMI firmware, so other Intel SKUs can bind without a per-model allow list.

## Check

```
dmesg | grep oxp-wmi
# calling WMAC with Integer Arg2
# OxpWMI ok, WMAC Integer Arg2, CPU temp NN C

ls /sys/class/hwmon/hwmon*/name
cat /sys/class/hwmon/oxp_wmi/fan1_input
cat /sys/class/hwmon/oxp_wmi/temp1_input
cat /sys/bus/wmi/devices/43B5A593-AD62-4257-8546-91B0797BEC1B*/charge_behaviour
cat /sys/bus/wmi/devices/43B5A593-AD62-4257-8546-91B0797BEC1B*/power_supply_mode
```

Manual fan ~60% (EC duty 110 / 184). `pwm1_enable=1` writes `0x4A=1` then **strobes `0x4B`** (Windows: leftover duty does not apply until `WriteECReg 0x4B` runs again). Then set the duty:

```
H=$(ls -d /sys/class/hwmon/hwmon* | while read d; do grep -q oxp_wmi $d/name && echo $d; done)
echo 1 > $H/pwm1_enable
echo 153 > $H/pwm1          # 153/255 ≈ 60% → EC ≈ 110/184
# fan1_input should leave ~400 RPM and climb within 1s
cat $H/pwm1                 # stays ~153 (unlike the old Buffer path)
echo 2 > $H/pwm1_enable     # auto; RPM falls; 0x4B readback may stay stale
```

## Packing (Windows CIM, confirmed)

Arg2 is ACPI **Integer** (`UInt32`), not a Buffer / 32-byte Package. Linux calls `WMAC` with that Integer. Method **2 (`WriteECReg`) is the apply**; method 3 (`WriteReadECReg`) is not required.

```
read:  GroupOffset      = 0x04 | (reg << 8)               # bytes 04, reg, 00, 00
write: GroupOffsetValue = 0x04 | (reg << 8) | (val << 16) # bytes 04, reg, val, 00
```

Examples: `0x4A=1` → `0x00014A04`; `0x4B=184` → `0x00B84B04`. JS `0x400+reg` (`0x44A`) is rejected (status `0xFF`).

Output STRING: `"0x00,0xNN,…"`. Byte0 `0x00` ok / `0xFF` fail (inverted vs MSI). Byte1 = EC value. `WriteECReg` may return all zeros on success (no echo).

In auto, `0x4B` is not the live motor compare (stale). After `0x4A=1`, rewrite `0x4B` even if readback already matches.

```
# write 1-byte register number, then read 8-byte last output
printf '\x70' | sudo tee /sys/kernel/debug/oxp-wmi-*/read_ec >/dev/null
sudo hexdump -C /sys/kernel/debug/oxp-wmi-*/read_ec | head
sudo cat /sys/kernel/debug/oxp-wmi-*/last_info   # wm=WMAC arg2=integer …

# write reg 0x4A = 1 (manual); hwmon pwm1_enable=1 also strobes 0x4B
printf '\x4a\x01' | sudo tee /sys/kernel/debug/oxp-wmi-*/write_ec >/dev/null
```

Status byte `0x00` = ok, `0xFF` = fail (inverted vs `msi-wmi-platform`).
