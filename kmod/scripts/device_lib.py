#!/usr/bin/env python3
"""Load one or many OneXPlayer device env files."""
from __future__ import annotations

import re
from pathlib import Path

VALID_VARIANTS = {
    "oxp_fly",
    "oxp_x1",
    "oxp_2",
    "oxp_g1_a",
    "oxp_g1_i",
    "oxp_mini_amd",
    "oxp_mini_amd_a07",
    "oxp_mini_amd_pro",
    "oxp_wmi",  # Intel OxpWMI (X2 Mini / G3E); not an oxpec enum
}

OXPEC_VARIANTS = VALID_VARIANTS - {"oxp_wmi"}

PLACEHOLDERS = {"", "UNKNOWN", "ONEXPLAYER NEWMODEL", "NEWMODEL"}


def load_env(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip()
    return values


def slugify(name: str) -> str:
    slug = name.strip().lower()
    slug = re.sub(r"[^a-z0-9]+", "-", slug)
    return slug.strip("-") or "device"


def is_placeholder(board: str) -> bool:
    return board.strip() in PLACEHOLDERS or "NEWMODEL" in board


def normalize(env: dict[str, str], source: Path) -> dict[str, str]:
    required = ("OXP_BOARD_VENDOR", "OXP_BOARD_NAME", "OXP_BOARD_VARIANT")
    missing = [key for key in required if not env.get(key)]
    if missing:
        raise SystemExit(f"{source}: missing {', '.join(missing)}")
    variant = env["OXP_BOARD_VARIANT"]
    if variant not in VALID_VARIANTS:
        raise SystemExit(f"{source}: unknown OXP_BOARD_VARIANT={variant}; use {sorted(VALID_VARIANTS)}")
    env = dict(env)
    env.setdefault("OXP_SYS_VENDOR", env["OXP_BOARD_VENDOR"])
    env.setdefault("OXP_PRODUCT_NAME", env["OXP_BOARD_NAME"])
    env.setdefault("OXP_CAP_MAP", "oxp8")
    if variant == "oxp_wmi" or env.get("OXP_EC_STACK") == "oxp-wmi":
        env["OXP_EC_STACK"] = "oxp-wmi"
        env["OXP_BOARD_VARIANT"] = "oxp_wmi"
    else:
        env.setdefault("OXP_EC_STACK", "oxpec")
    env["SLUG"] = env.get("OXP_SLUG") or slugify(env["OXP_BOARD_NAME"])
    env["SOURCE"] = str(source)
    return env


def load_catalog(devices_dir: Path | None, extra_envs: list[Path]) -> list[dict[str, str]]:
    paths: list[Path] = []
    if devices_dir and devices_dir.is_dir():
        paths.extend(sorted(devices_dir.glob("*.env")))
    paths.extend(extra_envs)

    seen: dict[str, dict[str, str]] = {}
    for path in paths:
        if path.name.startswith("_") or path.name == "example.env":
            continue
        env = normalize(load_env(path), path)
        if is_placeholder(env["OXP_BOARD_NAME"]):
            print(f"skip placeholder {path}")
            continue
        key = (env["OXP_BOARD_VENDOR"], env["OXP_BOARD_NAME"])
        seen[key] = env
    return list(seen.values())
