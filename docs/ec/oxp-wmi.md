# oxp-wmi — Linux WMI client for X2 Mini

Out-of-tree module: [`linux/oxp-wmi/`](../../linux/oxp-wmi/).

Same *shape* as in-tree `msi-wmi-platform` (Claw G3E): `struct wmi_driver`, mutex around `wmidev_evaluate_method()`, hwmon, debugfs. Different GUID, methods, and buffer layout. Do **not** bind the MSI GUID.

Register map: [x2-mini.md](x2-mini.md). Protocol: [linux-wmi.md](linux-wmi.md), [access.md](access.md).

## What it controls

| Sysfs | EC | Notes |
|---|---|---|
| `hwmon/oxp_wmi/fan1_input` | `0x58`/`0x59` BE16 | RPM, read-only |
| `hwmon/oxp_wmi/pwm1` | `0x4B` | hwmon 0–255 ↔ EC 0–184 (same scale as `oxpec` X1) |
| `hwmon/oxp_wmi/pwm1_enable` | `0x4A` | `1` manual, `2` auto (`0` = manual + 100%) |
| `hwmon/oxp_wmi/temp1_input` | `0x70` | millidegree C |
| `charge_control_end_threshold` | `0xA3` | 0–100 (UI uses 50–100 step 5) |
| `charge_behaviour` | `0xA4` | `auto` / `inhibit-charge-awake` / `inhibit-charge` → 0 / 1 / 3 |
| `power_supply_mode` | `0xE3` | read-only; prints raw + oxp-normalized key |

Not implemented (live unused or not EC): `0xEB`, `0x2D`, `0xED`, `0xA5`, board temps, TDP, RGB.

## Build / load

On the handheld (kernel headers for the running image):

```
cd linux/oxp-wmi
make
sudo insmod oxp-wmi.ko
# or: sudo insmod oxp-wmi.ko force=1   # skip DMI / probe-read checks
```

DMI whitelist: `Manufacturer` contains `ONE-NETBOOK` and `Product` is `ONEXPLAYER X2Mini` (also X2 / X2 EVA / 3 / Apex Air / Apex i). X2 Mini PRO is AMD — use `oxpec`, not this module.

## Check

```
dmesg | grep oxp-wmi
# OxpWMI ok, CPU temp NN C

ls /sys/class/hwmon/hwmon*/name
cat /sys/class/hwmon/oxp_wmi/fan1_input
cat /sys/class/hwmon/oxp_wmi/temp1_input
cat /sys/bus/wmi/devices/43B5A593-AD62-4257-8546-91B0797BEC1B*/charge_behaviour
cat /sys/bus/wmi/devices/43B5A593-AD62-4257-8546-91B0797BEC1B*/power_supply_mode
```

Manual fan 40%:

```
H=$(ls -d /sys/class/hwmon/hwmon* | while read d; do grep -q oxp_wmi $d/name && echo $d; done)
echo 1 > $H/pwm1_enable
echo 102 > $H/pwm1          # 102/255 ≈ 40% → EC ≈ 74/184
```

## Write packing (still a hypothesis)

Reads are live-confirmed: `GroupOffset = 0x04 | (reg << 8)`.

Writes use `GroupOffsetValue = 0x04 | (reg << 8) | (value << 16)` (bytes `04, reg, value, 00`). That layout was **not** probed on Windows. If `pwm1_enable` / charge stores return `-EIO`, dump debugfs and compare.

```
# write 1-byte register number, then read 8-byte last output
printf '\x70' | sudo tee /sys/kernel/debug/oxp-wmi-*/read_ec >/dev/null
sudo hexdump -C /sys/kernel/debug/oxp-wmi-*/read_ec | head

# write reg 0x4A = 1 (manual)
printf '\x4a\x01' | sudo tee /sys/kernel/debug/oxp-wmi-*/write_ec >/dev/null
```

Status byte `0x00` = ok, `0xFF` = fail (inverted vs `msi-wmi-platform`).
