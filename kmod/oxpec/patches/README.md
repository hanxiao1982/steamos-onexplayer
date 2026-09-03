# oxpec patch series

These patches target mainline `drivers/platform/x86/oxpec.c` as inspected on 2026-09-04.

Baseline source:

- repository: `torvalds/linux`
- branch: `master`
- `oxpec.c` blob SHA: `34bb17fca14813669b14c8e833a87a8a85e3bd17`
- baseline includes mainline support for `ONEXPLAYER X2Mini PRO`

The patches are ordered by [`series`](series):

1. `0001-platform-x86-oxpec-use-data-driven-profiles.patch` — structural refactor only; existing enum values, DMI matches and behaviour are intentionally preserved.
2. `0002-platform-x86-oxpec-split-onexplayer-2-profiles.patch` — vendor-profile correction for OXP2 ARP23/ARP23P (PWM 184) vs GA18/GA72-R (PWM 255), with exact DMI strings.
3. `0003-platform-x86-oxpec-add-apex-profile.patch` — vendor-profile correction for APEX/X2 Mini PRO charge registers E5/E6.

Local workflow:

```bash
kmod/scripts/fetch-oxpec.sh mainline
bash kmod/scripts/apply-oxpec-patches.sh
kmod/scripts/build.sh oxpec
```

For staged testing, pass the last patch number to apply. The number means **apply through N**, not "apply only N":

```bash
kmod/scripts/fetch-oxpec.sh mainline

# State after patch 1 only
bash kmod/scripts/apply-oxpec-patches.sh 1
kmod/scripts/build.sh oxpec

# Continue the same source through patch 2; patch 1 is detected and skipped.
bash kmod/scripts/apply-oxpec-patches.sh 2
kmod/scripts/build.sh oxpec

# Continue through patch 3.
bash kmod/scripts/apply-oxpec-patches.sh 3
kmod/scripts/build.sh oxpec
```

With no argument, or with `all`, the script applies the full series. Valid numeric values are `1` through the current number of entries in `series`. Already-applied prerequisite patches are detected with a reverse apply check and skipped, so the same fetched source can be advanced incrementally from patch 1 to 2 to 3.

`fetch-oxpec.sh` deliberately remains a clean-source fetcher. Patch application is explicit so an unmodified upstream source and each intermediate patch state can be reviewed independently.

For upstream submission, the files are already written against the kernel path `drivers/platform/x86/oxpec.c`; the local runner strips that prefix when applying them to the ignored `kmod/oxpec/oxpec.c` test copy.
