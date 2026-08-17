#!/usr/bin/env python3
"""Render one InputPlumber YAML per catalogued device plus a combined hwdb."""
from __future__ import annotations

import argparse
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from device_lib import load_catalog

YAML_NAME = "50-onexplayer-local-{slug}.yaml"
HWDB_NAME = "61-oxp-local.hwdb"


def compact(value: str) -> str:
    return value.replace(" ", "")


def render_yaml(template: str, dev: dict[str, str]) -> str:
    text = template
    text = text.replace("ONEXPLAYER NEWMODEL", dev["OXP_PRODUCT_NAME"])
    text = text.replace("ONE-NETBOOK", dev["OXP_SYS_VENDOR"])
    text = text.replace("name: ONEXPLAYER LOCAL", f"name: ONEXPLAYER LOCAL {dev['SLUG']}")
    text = text.replace("capability_map_id: oxp8", f"capability_map_id: {dev['OXP_CAP_MAP']}")
    return text


def render_hwdb(devices: list[dict[str, str]]) -> str:
    lines = ["# Generated from kmod/devices — do not edit by hand", ""]
    for dev in devices:
        svn = compact(dev["OXP_SYS_VENDOR"])
        pn = compact(dev["OXP_PRODUCT_NAME"])
        lines.append(f"# {dev['SLUG']}: {dev['OXP_SYS_VENDOR']} / {dev['OXP_PRODUCT_NAME']}")
        lines.append(f"dmi:*svn{svn}:*pn{pn}:*")
        lines.append(" USE_INPUTPLUMBER=1")
        lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--template", type=pathlib.Path, required=True)
    parser.add_argument("--devices-dir", type=pathlib.Path, required=True)
    parser.add_argument("--out-dir", type=pathlib.Path, required=True)
    parser.add_argument("--env", type=pathlib.Path, action="append", default=[])
    args = parser.parse_args()

    devices = load_catalog(args.devices_dir, args.env)
    if not devices:
        raise SystemExit("no devices to render; add kmod/devices/<model>.env first")

    template = args.template.read_text(encoding="utf-8")
    args.out_dir.mkdir(parents=True, exist_ok=True)
    written: list[str] = []
    for dev in devices:
        name = YAML_NAME.format(slug=dev["SLUG"])
        (args.out_dir / name).write_text(render_yaml(template, dev), encoding="utf-8")
        written.append(name)
        print(f"yaml {name}  cap={dev['OXP_CAP_MAP']}")

    (args.out_dir / HWDB_NAME).write_text(render_hwdb(devices), encoding="utf-8")
    print(f"hwdb {HWDB_NAME}  entries={len(devices)}")
    print("files " + " ".join(written + [HWDB_NAME]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
