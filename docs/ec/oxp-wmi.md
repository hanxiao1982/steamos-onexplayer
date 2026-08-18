# oxp-wmi — Linux WMI client for OneXPlayer Intel

Out-of-tree module: [`linux/oxp-wmi/`](../../linux/oxp-wmi/).

Same *call path* as in-tree `msi-wmi-platform`: mutex around `wmidev_evaluate_method(wdev, 0x0, method, in, out)`, and a **32-byte** zeroed input buffer (Windows `CreateByteField()` quirk). Different GUID, methods, and payload. Do **not** bind the MSI GUID.

OxpWMI is the Intel path (`ecAccessType=2`). AMD / WinRing0 boards stay on `oxpec`.

Register map (current OneXConsole Intel table): [x2-mini.md](x2-mini.md). Protocol: [linux-wmi.md](linux-wmi.md), [access.md](access.md). Per-SKU offsets can be added later; the WMI transport stays the same.

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
```

CachyOS / Bazzite one-shot (`install-cachyos.sh` / `install-bazzite.sh` / `on-device-install.sh`) detect the stack and take this path automatically.

Manual:

```
cd linux/oxp-wmi
make
sudo insmod oxp-wmi.ko
# or: sudo insmod oxp-wmi.ko force=1        # skip DMI / probe-read checks
# or: sudo insmod oxp-wmi.ko in_len=32      # force MSI-sized input buffer
```

DMI: `Manufacturer` or `Board Vendor` contains `ONE-NETBOOK`. Known AMD products (`ONEXPLAYER X2Mini PRO`, `ONEXPLAYER APEX`) are denied. The WMI GUID only exists on OxpWMI firmware, so other Intel SKUs can bind without a per-model allow list.

## Check

```
dmesg | grep oxp-wmi
# ReadECReg in=32: ret=0 CPU 40 C (STRING len=39 "0x00,0x28,...")
# using 32-byte WMI input buffer
# OxpWMI ok, CPU temp 40 C (in_len=32)

ls /sys/class/hwmon/hwmon*/name
cat /sys/class/hwmon/oxp_wmi/fan1_input
cat /sys/class/hwmon/oxp_wmi/temp1_input
cat /sys/bus/wmi/devices/43B5A593-AD62-4257-8546-91B0797BEC1B*/charge_behaviour
cat /sys/bus/wmi/devices/43B5A593-AD62-4257-8546-91B0797BEC1B*/power_supply_mode
sudo cat /sys/kernel/debug/oxp-wmi-*/last_info
```

X2 Mini live on Bazzite (kernel 7.2 OGC): `object_id=AC`, `in_len=32`, ACPI `STRING` `"0x00,0x28,…"`, `temp1_input=40000`, `fan1_input=360`, `pwm1_enable=2`. A 4-byte input returns status ok and every value 0.

In auto (`pwm1_enable=2`) `pwm1` may read 0 while the fan still spins; duty `0x4B` is only meaningful after `pwm1_enable=1`.

If `temp1_input` is `0` but `dmesg` says `OxpWMI ok` with no `in_len=`, you are still on the old `.ko`. Probe tries **32, then 8, then 4**. Override with `insmod oxp-wmi.ko in_len=32`.

Manual fan 40% (rebuild 0.2+ first; writes now read back `0x4A`/`0x4B`):

```
sudo kmod/scripts/hwmon-pwm.sh --read
sudo kmod/scripts/hwmon-pwm.sh --hold 8 80
```

X2 Mini live: `WriteECReg` packing works (`pwm1_enable` stays 1; `pwm1` readback is 203 after an 80% write). Stopping `steamos-manager` / PowerStation does **not** change that. Within ~1s `0x4B` reads back 0, and `fan1_input` stays 360 even in the instant when `pwm1` is 203. Firmware is either sampling/clearing duty on a 1 Hz loop, or `0x4B` is a mailbox that does not drive the motor until something else applies it. Next check: `hwmon-pwm.sh --burst --hold 8 100` (rewrite every 50ms, no mid-hold pwm reads).

If `pwm1_enable` stays `2`, the write itself did not stick. The driver tries method 2/3 and a few UInt32 layouts; `dmesg` prints which packing read back.

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
