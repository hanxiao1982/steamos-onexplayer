#!/usr/bin/env python3
"""Insert every catalogued DMI entry into fetched oxpec.c. Safe to re-run."""
from __future__ import annotations

import argparse
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from device_lib import VALID_VARIANTS, is_placeholder, load_catalog

ENTRY = """\
	{{
		.matches = {{
			DMI_MATCH(DMI_BOARD_VENDOR, "{vendor}"),
			DMI_EXACT_MATCH(DMI_BOARD_NAME, "{board}"),
		}},
		.driver_data = (void *){variant},
	}},
"""


def already_present(source: str, board: str) -> bool:
    return f'DMI_EXACT_MATCH(DMI_BOARD_NAME, "{board}")' in source


def inject_one(source: str, vendor: str, board: str, variant: str) -> tuple[str, bool]:
    if already_present(source, board):
        return source, False

    block = ENTRY.format(vendor=vendor, board=board, variant=variant)
    apex = re.search(
        r'\t\{\n\t\t\.matches = \{\n\t\t\tDMI_MATCH\(DMI_BOARD_VENDOR, "ONE-NETBOOK"\),\n'
        r'\t\t\tDMI_EXACT_MATCH\(DMI_BOARD_NAME, "ONEXPLAYER APEX"\),\n'
        r"\t\t\},\n\t\t\.driver_data = \(void \*\)oxp_fly,\n\t\},\n",
        source,
    )
    if apex:
        return source[: apex.end()] + block + source[apex.end() :], True

    closer = source.rfind("\t{},\n};")
    if closer == -1:
        raise SystemExit("Could not find dmi_table terminator in oxpec.c")
    return source[:closer] + block + source[closer:], True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--oxpec", type=pathlib.Path, required=True)
    parser.add_argument("--devices-dir", type=pathlib.Path)
    parser.add_argument("--env", type=pathlib.Path, action="append", default=[])
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args()

    root = pathlib.Path(__file__).resolve().parents[1]
    devices_dir = args.devices_dir or (root / "devices")
    devices = load_catalog(devices_dir, args.env)
    if args.list:
        if not devices:
            print("no devices in catalog")
            return 0
        for dev in devices:
            print(f"{dev['SLUG']}: {dev['OXP_BOARD_VENDOR']} / {dev['OXP_BOARD_NAME']} -> {dev['OXP_BOARD_VARIANT']}")
        return 0

    if not devices:
        raise SystemExit(
            f"no devices to inject. Add kmod/devices/<model>.env or pass --env. "
            f"See {devices_dir / 'example.env'}"
        )

    text = args.oxpec.read_text(encoding="utf-8")
    added = 0
    skipped = 0
    for dev in devices:
        if is_placeholder(dev["OXP_BOARD_NAME"]):
            print(f"skip placeholder {dev['OXP_BOARD_NAME']}", file=sys.stderr)
            continue
        if dev["OXP_BOARD_VARIANT"] not in VALID_VARIANTS:
            raise SystemExit(f"bad variant {dev['OXP_BOARD_VARIANT']}")
        text, changed = inject_one(
            text,
            dev["OXP_BOARD_VENDOR"],
            dev["OXP_BOARD_NAME"],
            dev["OXP_BOARD_VARIANT"],
        )
        if changed:
            added += 1
            print(f"added {dev['OXP_BOARD_VENDOR']} / {dev['OXP_BOARD_NAME']} -> {dev['OXP_BOARD_VARIANT']}")
        else:
            skipped += 1
            print(f"already present: {dev['OXP_BOARD_NAME']}")

    args.oxpec.write_text(text, encoding="utf-8")
    print(f"done: added={added} skipped={skipped} total={len(devices)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
