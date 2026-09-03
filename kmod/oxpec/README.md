# OGC-based oxpec patches

The files in [`patches/`](patches/) are diffs against the current
OpenGamingCollective Linux `features/onexplayer` branch, rather than copies of
the complete `drivers/platform/x86/oxpec.c` source.

## ONEXPLAYER 3 patch

`patches/0001-platform-x86-oxpec-add-onexplayer-3.diff` is based on OGC commit
`89c89f448aa44393b39da64efa834c64735e7cbb` (the branch head when the diff was
generated). It leaves OGC's existing USB/Input tablet-mode code unchanged and
contains only the ONEXPLAYER 3 EC work plus the independent ACPI global-lock
error-path fix.

The diff adds:

- a dedicated `oxp_3` board type and exact DMI match;
- fan RPM at `0x58`/`0x59` (16-bit big-endian);
- PWM mode/duty at `0x4A`/`0x4B`, with EC range `0..184` and manual-mode
  relatch;
- CPU temperature at `0x70`;
- charge limit/bypass at `0xA3`/`0xA4`;
- no unverified `0xEB` turbo takeover for ONEXPLAYER 3;
- release of the ACPI global lock when an EC read fails.

Evidence comes from OneXConsole's Intel G3E map, live X2 Mini tests of the
shared registers, and the original ONEXPLAYER 3 RPM test. PWM and charge writes
must still be verified directly on ONEXPLAYER 3 hardware before upstreaming.

Apply it to an OGC Linux checkout:

```bash
git switch features/onexplayer
git apply --check /path/to/0001-platform-x86-oxpec-add-onexplayer-3.diff
git apply /path/to/0001-platform-x86-oxpec-add-onexplayer-3.diff
```

To apply it to the standalone source fetched by this repository:

```bash
kmod/scripts/fetch-oxpec.sh ogc
patch -p4 -d kmod/oxpec \
  < kmod/oxpec/patches/0001-platform-x86-oxpec-add-onexplayer-3.diff
```

The pinned base makes review reproducible. When OGC advances, fetch the new
branch head, reapply the logical changes, regenerate the diff, and update the
base commit recorded here.
