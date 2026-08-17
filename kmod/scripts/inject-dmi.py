#!/usr/bin/env python3
"""Insert a local DMI entry into fetched oxpec.c. Same edit for both distros."""
from __future__ import annotations

import argparse
import pathlib
import re
import sys

VALID_VARIANTS = {
    "oxp_fly",
    "oxp_x1",
    "oxp_2",
    "oxp_g1_a",
    "oxp_g1_i",
    "oxp_mini_amd",
    "oxp_mini_amd_a07",
    "oxp_mini_amd_pro",
}

ENTRY = """\
	{{
		.matches = {{
			DMI_MATCH(DMI_BOARD_VENDOR, "{vendor}"),
			DMI_EXACT_MATCH(DMI_BOARD_NAME, "{board}"),
		}},
		.driver_data = (void *){variant},
	}},
"""


def load_env(path: pathlib.Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip()
    return values


def inject(source: str, vendor: str, board: str, variant: str) -> str:
    if f'DMI_EXACT_MATCH(DMI_BOARD_NAME, "{board}")' in source:
        print(f"DMI already present: {board}")
        return source

    block = ENTRY.format(vendor=vendor, board=board, variant=variant)
    apex = re.search(
        r'\t\{\n\t\t\.matches = \{\n\t\t\tDMI_MATCH\(DMI_BOARD_VENDOR, "ONE-NETBOOK"\),\n'
        r'\t\t\tDMI_EXACT_MATCH\(DMI_BOARD_NAME, "ONEXPLAYER APEX"\),\n'
        r"\t\t\},\n\t\t\.driver_data = \(void \*\)oxp_fly,\n\t\},\n",
        source,
    )
    if apex:
        return source[: apex.end()] + block + source[apex.end() :]

    closer = source.rfind("\t{},\n};")
    if closer == -1:
        raise SystemExit("Could not find dmi_table terminator in oxpec.c")
    return source[:closer] + block + source[closer:]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--env", type=pathlib.Path, required=True)
    parser.add_argument("--oxpec", type=pathlib.Path, required=True)
    args = parser.parse_args()

    env = load_env(args.env)
    vendor = env["OXP_BOARD_VENDOR"]
    board = env["OXP_BOARD_NAME"]
    variant = env["OXP_BOARD_VARIANT"]
    if variant not in VALID_VARIANTS:
        raise SystemExit(f"unknown OXP_BOARD_VARIANT={variant}; use {sorted(VALID_VARIANTS)}")
    if "NEWMODEL" in board:
        print("warning: OXP_BOARD_NAME is still the placeholder ONEXPLAYER NEWMODEL", file=sys.stderr)

    text = args.oxpec.read_text(encoding="utf-8")
    args.oxpec.write_text(inject(text, vendor, board, variant), encoding="utf-8")
    print(f"injected {vendor} / {board} -> {variant}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
