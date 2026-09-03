#!/usr/bin/env python3
import pathlib
import re
import shutil
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
PATCH_DIR = ROOT / "kmod/oxpec/patches"
BASELINE_SHA = "34bb17fca14813669b14c8e833a87a8a85e3bd17"
BASELINE_URL = "https://raw.githubusercontent.com/torvalds/linux/master/drivers/platform/x86/oxpec.c"


def run(*args, cwd=None, input_text=None):
    subprocess.run(args, cwd=cwd, input=input_text, text=True, check=True)


def git_commit(repo, subject, body):
    msg = subject + "\n\n" + body.rstrip() + "\n"
    run("git", "add", "drivers/platform/x86/oxpec.c", cwd=repo)
    run("git", "diff", "--cached", "--check", cwd=repo)
    run("git", "commit", "-s", "-F", "-", cwd=repo, input_text=msg)


def profile_object(name, fields):
    lines = []
    for line in fields.splitlines():
        if line.startswith("\t\t"):
            line = line[1:]
        lines.append(line)
    return f"static const struct oxp_ec_profile {name} = {{\n" + "\n".join(lines) + "\n};"


def convert_patch1_to_direct_profiles(src):
    src, n = re.subn(r"enum oxp_board \{\n.*?\n\};\n\n", "", src, count=1, flags=re.S)
    assert n == 1, "enum oxp_board block not found"
    src, n = re.subn(r"static enum oxp_board board;\n", "", src, count=1)
    assert n == 1, "board global not found"

    array_re = re.compile(
        r"static const struct oxp_ec_profile oxp_ec_profiles\[\] = \{\n(.*?)\n\};",
        re.S,
    )
    match = array_re.search(src)
    assert match, "profile array not found"
    entries = re.findall(r"\t\[([a-z0-9_]+)\] = \{\n(.*?)\n\t\},", match.group(1), re.S)
    assert len(entries) == 10, f"expected 10 profiles, found {len(entries)}"

    objects = "\n\n".join(profile_object(name, fields) for name, fields in entries)
    validator = r'''

static bool oxp_ec_profile_valid(const struct oxp_ec_profile *profile)
{
	if (!profile || !profile->fan_reg || !profile->pwm_enable_reg ||
	    !profile->pwm_reg || !profile->pwm_max)
		return false;

	if (profile->pwm_min >= profile->pwm_max)
		return false;

	if (!!profile->turbo_reg != !!profile->turbo_mask)
		return false;

	if (!!profile->turbo_led_reg != !!profile->turbo_led_off ||
	    !!profile->turbo_led_reg != !!profile->turbo_led_on)
		return false;

	if (!!profile->charge_limit_reg != !!profile->charge_inhibit_reg ||
	    !!profile->charge_inhibit_reg != !!profile->charge_inhibit_mask_awake ||
	    !!profile->charge_inhibit_reg != !!profile->charge_inhibit_mask_off)
		return false;

	return true;
}'''
    src = src[:match.start()] + objects + validator + src[match.end():]

    src, dmi_count = re.subn(
        r"(\.driver_data = \(void \*\))([a-z0-9_]+),",
        r"\1&\2,",
        src,
    )
    assert dmi_count >= 20, f"unexpected DMI conversion count: {dmi_count}"

    old = "\tboard = (enum oxp_board)(unsigned long)dmi_entry->driver_data;\n\tprofile = &oxp_ec_profiles[board];"
    new = "\tprofile = dmi_entry->driver_data;\n\tif (!oxp_ec_profile_valid(profile))\n\t\treturn -EINVAL;"
    assert old in src, "old board/profile init not found"
    src = src.replace(old, new, 1)

    assert "enum oxp_board" not in src
    assert "oxp_ec_profiles[" not in src
    assert "switch (board)" not in src
    return src


def add_patch2(src):
    oxp2 = r'''static const struct oxp_ec_profile oxp_2 = {
	.fan_reg = OXP_2_SENSOR_FAN_REG,
	.pwm_enable_reg = OXP_SENSOR_PWM_ENABLE_REG,
	.pwm_reg = OXP_SENSOR_PWM_REG,
	.pwm_max = 184,
	.turbo_reg = OXP_2_TURBO_SWITCH_REG,
	.turbo_mask = OXP_TURBO_TAKE_VAL,
};'''
    ga18 = r'''

static const struct oxp_ec_profile oxp_2_ga18 = {
	.fan_reg = OXP_2_SENSOR_FAN_REG,
	.pwm_enable_reg = OXP_SENSOR_PWM_ENABLE_REG,
	.pwm_reg = OXP_SENSOR_PWM_REG,
	.pwm_max = 255,
	.turbo_reg = OXP_2_TURBO_SWITCH_REG,
	.turbo_mask = OXP_TURBO_TAKE_VAL,
};'''
    assert oxp2 in src
    src = src.replace(oxp2, oxp2 + ga18, 1)

    old = r'''	{
		.matches = {
			DMI_MATCH(DMI_BOARD_VENDOR, "ONE-NETBOOK"),
			DMI_MATCH(DMI_BOARD_NAME, "ONEXPLAYER 2"),
		},
		.driver_data = (void *)&oxp_2,
	},'''
    new = r'''	{
		.matches = {
			DMI_MATCH(DMI_BOARD_VENDOR, "ONE-NETBOOK"),
			DMI_EXACT_MATCH(DMI_BOARD_NAME, "ONEXPLAYER 2 ARP23"),
		},
		.driver_data = (void *)&oxp_2,
	},
	{
		.matches = {
			DMI_MATCH(DMI_BOARD_VENDOR, "ONE-NETBOOK"),
			DMI_EXACT_MATCH(DMI_BOARD_NAME, "ONEXPLAYER 2 PRO ARP23P"),
		},
		.driver_data = (void *)&oxp_2,
	},
	{
		.matches = {
			DMI_MATCH(DMI_BOARD_VENDOR, "ONE-NETBOOK"),
			DMI_EXACT_MATCH(DMI_BOARD_NAME, "ONEXPLAYER 2 PRO ARP23P EVA-01"),
		},
		.driver_data = (void *)&oxp_2,
	},
	{
		.matches = {
			DMI_MATCH(DMI_BOARD_VENDOR, "ONE-NETBOOK"),
			DMI_EXACT_MATCH(DMI_BOARD_NAME, "ONEXPLAYER 2 GA18"),
		},
		.driver_data = (void *)&oxp_2_ga18,
	},
	{
		.matches = {
			DMI_MATCH(DMI_BOARD_VENDOR, "ONE-NETBOOK"),
			DMI_EXACT_MATCH(DMI_BOARD_NAME, "ONEXPLAYER 2 GA72-R"),
		},
		.driver_data = (void *)&oxp_2_ga18,
	},'''
    assert old in src, "broad OXP2 DMI entry not found"
    return src.replace(old, new, 1)


def replace_dmi_profile(src, product, old_profile, new_profile):
    pattern = re.compile(
        r'(DMI_EXACT_MATCH\(DMI_BOARD_NAME, "' + re.escape(product) + r'"\),\n\t\t\},\n\t\t\.driver_data = \(void \*\)&)'
        + re.escape(old_profile)
        + r'(,)',
    )
    src, n = pattern.subn(r"\1" + new_profile + r"\2", src, count=1)
    assert n == 1, f"DMI profile mapping not found for {product}"
    return src


def add_patch3(src):
    charge_regs = "#define OXP_X1_CHARGE_LIMIT_REG\t\t0xA3 /* X1 charge limit (%) */\n#define OXP_X1_CHARGE_INHIBIT_REG\t0xA4 /* X1 bypass charging */"
    apex_regs = charge_regs + "\n\n#define OXP_APEX_CHARGE_LIMIT_REG\t0xE5\n#define OXP_APEX_CHARGE_INHIBIT_REG\t0xE6"
    assert charge_regs in src
    src = src.replace(charge_regs, apex_regs, 1)

    fly = r'''static const struct oxp_ec_profile oxp_fly = {
	.fan_reg = OXP_SENSOR_FAN_REG,
	.pwm_enable_reg = OXP_SENSOR_PWM_ENABLE_REG,
	.pwm_reg = OXP_SENSOR_PWM_REG,
	.pwm_max = 255,
	.turbo_reg = OXP_TURBO_SWITCH_REG,
	.turbo_mask = OXP_TURBO_TAKE_VAL,
	.charge_limit_reg = OXP_X1_CHARGE_LIMIT_REG,
	.charge_inhibit_reg = OXP_X1_CHARGE_INHIBIT_REG,
	.charge_inhibit_mask_awake = OXP_X1_CHARGE_INHIBIT_MASK_AWAKE,
	.charge_inhibit_mask_off = OXP_X1_CHARGE_INHIBIT_MASK_OFF,
};'''
    apex = r'''

static const struct oxp_ec_profile oxp_apex = {
	.fan_reg = OXP_SENSOR_FAN_REG,
	.pwm_enable_reg = OXP_SENSOR_PWM_ENABLE_REG,
	.pwm_reg = OXP_SENSOR_PWM_REG,
	.pwm_max = 255,
	.turbo_reg = OXP_TURBO_SWITCH_REG,
	.turbo_mask = OXP_TURBO_TAKE_VAL,
	.charge_limit_reg = OXP_APEX_CHARGE_LIMIT_REG,
	.charge_inhibit_reg = OXP_APEX_CHARGE_INHIBIT_REG,
	.charge_inhibit_mask_awake = OXP_X1_CHARGE_INHIBIT_MASK_AWAKE,
	.charge_inhibit_mask_off = OXP_X1_CHARGE_INHIBIT_MASK_OFF,
};'''
    assert fly in src
    src = src.replace(fly, fly + apex, 1)
    src = replace_dmi_profile(src, "ONEXPLAYER APEX", "oxp_fly", "oxp_apex")
    src = replace_dmi_profile(src, "ONEXPLAYER X2Mini PRO", "oxp_fly", "oxp_apex")
    return src


def main():
    with tempfile.TemporaryDirectory(prefix="oxpec-patchgen-") as td:
        repo = pathlib.Path(td)
        source = repo / "drivers/platform/x86/oxpec.c"
        source.parent.mkdir(parents=True)
        run("curl", "-fsSL", BASELINE_URL, "-o", str(source))
        actual = subprocess.check_output(["git", "hash-object", str(source)], text=True).strip()
        assert actual == BASELINE_SHA, f"baseline moved: {actual}"

        run("git", "init", "-q", cwd=repo)
        run("git", "config", "user.name", "Xiao Han", cwd=repo)
        run("git", "config", "user.email", "hanxiao@live.com", cwd=repo)
        run("git", "add", ".", cwd=repo)
        run("git", "commit", "-q", "-m", "baseline", cwd=repo)

        old_patch1 = PATCH_DIR / "0001-platform-x86-oxpec-use-data-driven-profiles.patch"
        run("git", "apply", "--recount", "--whitespace=nowarn", str(old_patch1), cwd=repo)
        src = source.read_text()
        src = convert_patch1_to_direct_profiles(src)
        source.write_text(src)
        git_commit(
            repo,
            "platform/x86: oxpec: Use data-driven EC profiles",
            "Replace board-specific register switch statements with immutable EC profiles.\n\n"
            "Point DMI driver_data directly at each profile and validate mandatory\n"
            "registers and paired optional fields once during driver initialization.\n"
            "This keeps existing supported-board behavior while making incomplete\n"
            "profiles fail closed before any EC access.",
        )

        src = add_patch2(source.read_text())
        source.write_text(src)
        git_commit(
            repo,
            "platform/x86: oxpec: Split OneXPlayer 2 PWM profiles",
            "OneXConsole does not treat all ONEXPLAYER 2 boards as one EC profile.\n"
            "ARP23/ARP23P use PWM max 184 while GA18 and GA72-R use PWM max 255.\n\n"
            "Split the profiles and use the exact vendor DMI board names.",
        )

        src = add_patch3(source.read_text())
        source.write_text(src)
        git_commit(
            repo,
            "platform/x86: oxpec: Add APEX charge profile",
            "OneXConsole uses the Fly-style fan and turbo registers on ONEXPLAYER APEX\n"
            "and ONEXPLAYER X2Mini PRO, but their charge-control registers are E5/E6\n"
            "rather than A3/A4.\n\n"
            "Add an APEX profile that preserves the existing fan, PWM and turbo\n"
            "behavior while selecting the vendor charge registers.",
        )

        out = repo / "out"
        out.mkdir()
        run("git", "format-patch", "--no-signature", "-3", "-o", str(out), cwd=repo)
        generated = sorted(out.glob("*.patch"))
        assert len(generated) == 3
        targets = [
            PATCH_DIR / "0001-platform-x86-oxpec-use-data-driven-profiles.patch",
            PATCH_DIR / "0002-platform-x86-oxpec-split-onexplayer-2-profiles.patch",
            PATCH_DIR / "0003-platform-x86-oxpec-add-apex-profile.patch",
        ]
        for src_patch, target in zip(generated, targets):
            shutil.copyfile(src_patch, target)
            print(f"generated {target.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
