#!/usr/bin/env python3
import math
import pathlib
import re
import sys

if len(sys.argv) != 2:
    raise SystemExit(f"usage: {sys.argv[0]} path/to/oxpec.c")

source = pathlib.Path(sys.argv[1]).read_text()

VALUES = {
    "OXP_SENSOR_FAN_REG": 0x76,
    "OXP_2_SENSOR_FAN_REG": 0x58,
    "OXP_SENSOR_PWM_ENABLE_REG": 0x4A,
    "OXP_SENSOR_PWM_REG": 0x4B,
    "ORANGEPI_SENSOR_FAN_REG": 0x78,
    "ORANGEPI_SENSOR_PWM_ENABLE_REG": 0x40,
    "ORANGEPI_SENSOR_PWM_REG": 0x38,
    "OXP_TURBO_SWITCH_REG": 0xF1,
    "OXP_2_TURBO_SWITCH_REG": 0xEB,
    "OXP_MINI_TURBO_SWITCH_REG": 0x1E,
    "OXP_MINI_TURBO_TAKE_VAL": 0x01,
    "OXP_TURBO_TAKE_VAL": 0x40,
    "OXP_X1_TURBO_LED_REG": 0x57,
    "OXP_X1_TURBO_LED_OFF": 0x01,
    "OXP_X1_TURBO_LED_ON": 0x02,
    "OXP_X1_CHARGE_LIMIT_REG": 0xA3,
    "OXP_X1_CHARGE_INHIBIT_REG": 0xA4,
    "OXP_X1_CHARGE_INHIBIT_MASK_AWAKE": 0x01,
    "OXP_X1_CHARGE_INHIBIT_MASK_OFF": 0x02,
    "true": 1,
}

EXPECTED = {
    "aok_zoe_a1": dict(fan_reg=0x76, pwm_enable_reg=0x4A, pwm_reg=0x4B,
                        pwm_min=0, pwm_max=255, turbo_reg=0xF1, turbo_mask=0x40),
    "orange_pi_neo": dict(fan_reg=0x78, pwm_enable_reg=0x40, pwm_reg=0x38,
                           pwm_min=1, pwm_max=244),
    "oxp_2": dict(fan_reg=0x58, pwm_enable_reg=0x4A, pwm_reg=0x4B,
                   pwm_min=0, pwm_max=184, turbo_reg=0xEB, turbo_mask=0x40),
    "oxp_fly": dict(fan_reg=0x76, pwm_enable_reg=0x4A, pwm_reg=0x4B,
                     pwm_min=0, pwm_max=255, turbo_reg=0xF1, turbo_mask=0x40,
                     charge_limit_reg=0xA3, charge_inhibit_reg=0xA4,
                     charge_inhibit_mask_awake=1, charge_inhibit_mask_off=2),
    "oxp_mini_amd": dict(fan_reg=0x76, pwm_enable_reg=0x4A, pwm_reg=0x4B,
                          pwm_min=0, pwm_max=100, amd_only=1),
    "oxp_mini_amd_a07": dict(fan_reg=0x76, pwm_enable_reg=0x4A, pwm_reg=0x4B,
                              pwm_min=0, pwm_max=100, turbo_reg=0x1E, turbo_mask=1),
    "oxp_mini_amd_pro": dict(fan_reg=0x76, pwm_enable_reg=0x4A, pwm_reg=0x4B,
                              pwm_min=0, pwm_max=255, turbo_reg=0xF1, turbo_mask=0x40),
    "oxp_x1": dict(fan_reg=0x58, pwm_enable_reg=0x4A, pwm_reg=0x4B,
                    pwm_min=0, pwm_max=184, turbo_reg=0xEB, turbo_mask=0x40,
                    turbo_led_reg=0x57, turbo_led_off=1, turbo_led_on=2,
                    charge_limit_reg=0xA3, charge_inhibit_reg=0xA4,
                    charge_inhibit_mask_awake=1, charge_inhibit_mask_off=2),
    "oxp_g1_i": dict(fan_reg=0x58, pwm_enable_reg=0x4A, pwm_reg=0x4B,
                      pwm_min=0, pwm_max=184, turbo_reg=0xEB, turbo_mask=0x40,
                      charge_limit_reg=0xA3, charge_inhibit_reg=0xA4,
                      charge_inhibit_mask_awake=1, charge_inhibit_mask_off=2),
    "oxp_g1_a": dict(fan_reg=0x76, pwm_enable_reg=0x4A, pwm_reg=0x4B,
                      pwm_min=0, pwm_max=255, turbo_reg=0xF1, turbo_mask=0x40,
                      charge_limit_reg=0xA3, charge_inhibit_reg=0xA4,
                      charge_inhibit_mask_awake=1, charge_inhibit_mask_off=2),
}

ALL_FIELDS = [
    "fan_reg", "pwm_enable_reg", "pwm_reg", "pwm_min", "pwm_max",
    "turbo_reg", "turbo_mask", "turbo_led_reg", "turbo_led_off",
    "turbo_led_on", "charge_limit_reg", "charge_inhibit_reg",
    "charge_inhibit_mask_awake", "charge_inhibit_mask_off", "amd_only",
]


def resolve(token):
    token = token.strip()
    if token in VALUES:
        return VALUES[token]
    return int(token, 0)


def parse_profiles(text):
    found = {}
    pattern = re.compile(
        r"static const struct oxp_ec_profile ([a-z0-9_]+) = \{\n(.*?)\n\};",
        re.S,
    )
    for name, body in pattern.findall(text):
        if name not in EXPECTED:
            continue
        fields = {field: 0 for field in ALL_FIELDS}
        for field, token in re.findall(r"\t\.([a-z0-9_]+) = ([^,]+),", body):
            fields[field] = resolve(token)
        found[name] = fields
    return found


def c_div(a, b):
    if b == 0:
        raise ZeroDivisionError
    return math.trunc(a / b)


def old_pwm_write(name, val):
    if name == "orange_pi_neo":
        return 0x38, c_div((val - 1) * 243, 254) + 1
    if name in {"oxp_2", "oxp_x1", "oxp_g1_i"}:
        return 0x4B, c_div(val * 184, 255)
    if name in {"oxp_mini_amd", "oxp_mini_amd_a07"}:
        return 0x4B, c_div(val * 100, 255)
    return 0x4B, val


def new_pwm_write(p, val):
    if p["pwm_min"]:
        val = c_div((val - p["pwm_min"]) * (p["pwm_max"] - p["pwm_min"]),
                    255 - p["pwm_min"]) + p["pwm_min"]
    elif p["pwm_max"] != 255:
        val = c_div(val * p["pwm_max"], 255)
    return p["pwm_reg"], val


def old_pwm_read(name, raw):
    if name == "orange_pi_neo":
        return c_div((raw - 1) * 254, 243) + 1
    if name in {"oxp_2", "oxp_x1", "oxp_g1_i"}:
        return c_div(raw * 255, 184)
    if name in {"oxp_mini_amd", "oxp_mini_amd_a07"}:
        return c_div(raw * 255, 100)
    return raw


def new_pwm_read(p, raw):
    if p["pwm_min"]:
        return c_div((raw - p["pwm_min"]) * (255 - p["pwm_min"]),
                     p["pwm_max"] - p["pwm_min"]) + p["pwm_min"]
    if p["pwm_max"] != 255:
        return c_div(raw * 255, p["pwm_max"])
    return raw


profiles = parse_profiles(source)
assert set(profiles) == set(EXPECTED), f"profile set mismatch: {set(profiles)}"

cases = 0
for name, expected_nonzero in EXPECTED.items():
    p = profiles[name]
    expected = {field: 0 for field in ALL_FIELDS}
    expected.update(expected_nonzero)
    assert p == expected, f"{name}: profile mismatch\nactual={p}\nexpected={expected}"

    # Register selection and AMD-only behavior.
    assert p["fan_reg"] == expected["fan_reg"]
    assert p["pwm_enable_reg"] == expected["pwm_enable_reg"]
    assert bool(p["amd_only"]) == (name == "oxp_mini_amd")
    cases += 3

    # Exhaustive user PWM write and raw PWM read domains.
    for val in range(256):
        assert new_pwm_write(p, val) == old_pwm_write(name, val), (name, "write", val)
        assert new_pwm_read(p, val) == old_pwm_read(name, val), (name, "read", val)
        cases += 2

    # Turbo visibility/read-modify-write semantics for every possible EC byte.
    old_turbo = {
        "aok_zoe_a1": (0xF1, 0x40), "oxp_2": (0xEB, 0x40),
        "oxp_fly": (0xF1, 0x40), "oxp_mini_amd_a07": (0x1E, 0x01),
        "oxp_mini_amd_pro": (0xF1, 0x40), "oxp_x1": (0xEB, 0x40),
        "oxp_g1_i": (0xEB, 0x40), "oxp_g1_a": (0xF1, 0x40),
    }.get(name, (0, 0))
    assert (p["turbo_reg"], p["turbo_mask"]) == old_turbo
    for raw in range(256):
        if old_turbo[0]:
            for enable in (False, True):
                old_val = raw | old_turbo[1] if enable else raw & ~old_turbo[1]
                new_val = raw | p["turbo_mask"] if enable else raw & ~p["turbo_mask"]
                assert new_val == old_val
                cases += 1
            assert ((raw & p["turbo_mask"]) == p["turbo_mask"]) == \
                   ((raw & old_turbo[1]) == old_turbo[1])
            cases += 1

    # LED capability/value mapping.
    if name == "oxp_x1":
        assert (p["turbo_led_reg"], p["turbo_led_off"], p["turbo_led_on"]) == (0x57, 1, 2)
    else:
        assert p["turbo_led_reg"] == 0
    cases += 1

    # Charge support and behavior decode over the full byte domain.
    charge_supported = name in {"oxp_fly", "oxp_x1", "oxp_g1_i", "oxp_g1_a"}
    assert bool(p["charge_limit_reg"] and p["charge_inhibit_reg"]) == charge_supported
    if charge_supported:
        assert (p["charge_limit_reg"], p["charge_inhibit_reg"]) == (0xA3, 0xA4)
        for raw in range(256):
            old_always = (raw & 3) == 3
            old_awake = (raw & 1) == 1
            new_always = (raw & (p["charge_inhibit_mask_awake"] |
                                 p["charge_inhibit_mask_off"])) == \
                         (p["charge_inhibit_mask_awake"] | p["charge_inhibit_mask_off"])
            new_awake = (raw & p["charge_inhibit_mask_awake"]) == p["charge_inhibit_mask_awake"]
            assert (new_always, new_awake) == (old_always, old_awake)
            cases += 1
    cases += 1

# The new design must fail closed before helpers can dereference an incomplete profile.
for needle in (
    "!profile->fan_reg", "!profile->pwm_enable_reg", "!profile->pwm_reg",
    "!profile->pwm_max", "profile->pwm_min >= profile->pwm_max",
    "!!profile->turbo_reg != !!profile->turbo_mask",
    "profile = dmi_entry->driver_data",
    "if (!oxp_ec_profile_valid(profile))",
):
    assert needle in source, f"missing validator/init guard: {needle}"

assert "enum oxp_board" not in source
assert "oxp_ec_profiles[" not in source
assert "switch (board)" not in source

print(f"profile refactor mock: {cases} behavior cases passed across {len(profiles)} profiles")
