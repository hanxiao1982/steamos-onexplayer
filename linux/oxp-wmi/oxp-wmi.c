// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * OneXPlayer OxpWMI (SuRwECRegInterface) — Intel / ecAccessType=2.
 *
 * Call pattern copied from msi-wmi-platform (Armin Wolf):
 *
 *   mutex around wmidev_evaluate_method(wdev, 0x0, method, in, out)
 *   input is a zeroed 32-byte ACPI Buffer (Windows CreateByteField quirk)
 *
 * The ABI is not MSI's:
 *
 *   GUID   43B5A593-AD62-4257-8546-91B0797BEC1B   (not ABBC0F6E-…)
 *   Read   WmiMethodId 1  ReadECReg(GroupOffset)
 *   Write  WmiMethodId 2  WriteECReg(GroupOffsetValue)
 *   Input  first 4 bytes = LE UInt32
 *          read:  0x04 | (reg << 8)
 *          write: 0x04 | (reg << 8) | (val << 16)   (hypothesized)
 *   Output ACPI STRING (X2 Mini Linux live):
 *          "0x00,0x28,0x00,0x00,0x00,0x00,0x00,0x00"  (len 39)
 *          byte[0] = 0x00 ok / 0xFF fail  (inverted vs MSI)
 *          byte[1] = EC RAM value
 *   object_id AC → ACPI method WMAC. in_len=32 is required.
 *
 * Do not bind the MSI GUID. Not for AMD / WinRing0 boards.
 *
 * Copyright (C) 2026
 */

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <linux/acpi.h>
#include <linux/ctype.h>
#include <linux/debugfs.h>
#include <linux/dmi.h>
#include <linux/hwmon.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/slab.h>
#include <linux/string.h>
#include <linux/uaccess.h>
#include <linux/wmi.h>

#define DRIVER_NAME		"oxp-wmi"

/* Windows class SuRwECRegInterface */
#define OXP_WMI_GUID		"43B5A593-AD62-4257-8546-91B0797BEC1B"

#define OXP_WMI_GROUP		0x04

enum oxp_wmi_method {
	OXP_WMI_READ_EC		= 1,
	OXP_WMI_WRITE_EC	= 2,
	OXP_WMI_WRITE_READ_EC	= 3,
};

/* Same size msi-wmi-platform uses for CreateByteField(). */
#define OXP_WMI_IN_LEN		32
#define OXP_WMI_OUT_LEN		8

/* Default OxpWMI register set from the current OneXConsole Intel table */
#define OXP_REG_PWM_ENABLE	0x4A
#define OXP_REG_PWM_DUTY	0x4B
#define OXP_REG_FAN_H		0x58
#define OXP_REG_FAN_L		0x59
#define OXP_REG_CPU_TEMP	0x70
#define OXP_REG_CHARGE_LIMIT	0xA3
#define OXP_REG_CHARGE_BYPASS	0xA4
#define OXP_REG_POWER_SUPPLY	0xE3

#define OXP_PWM_AUTO		0
#define OXP_PWM_MANUAL		1
#define OXP_PWM_MAX		184

#define OXP_BYPASS_AUTO		0
#define OXP_BYPASS_AWAKE	1
#define OXP_BYPASS_ALWAYS	3

static bool force;
module_param_unsafe(force, bool, 0444);
MODULE_PARM_DESC(force, "Load without DMI whitelist (debug)");

/*
 * 0 = auto (try 32, then 8, then 4). MSI always uses 32.
 * 4/8/32 force that input buffer length.
 */
static int in_len_param;
module_param_named(in_len, in_len_param, int, 0444);
MODULE_PARM_DESC(in_len, "WMI input buffer bytes: 0=auto, 4, 8, or 32");

struct oxp_wmi_data {
	struct wmi_device *wdev;
	struct mutex wmi_lock;	/* firmware WMxx is not thread-safe */
	struct dentry *debugfs;
	size_t in_len;
	u8 last_out[OXP_WMI_OUT_LEN];
	u8 last_acpi_type;
	u32 last_acpi_len;
	char last_desc[160];
};

static u32 oxp_wmi_pack_read(u8 reg)
{
	return OXP_WMI_GROUP | ((u32)reg << 8);
}

static u32 oxp_wmi_pack_write(u8 reg, u8 value)
{
	return OXP_WMI_GROUP | ((u32)reg << 8) | ((u32)value << 16);
}

static bool oxp_looks_like_hex_text(const u8 *p, u32 n)
{
	u32 i, hex = 0;

	if (!p || n < 4)
		return false;

	for (i = 0; i < n; i++) {
		if (!p[i])
			break;
		if (isxdigit(p[i])) {
			hex++;
			continue;
		}
		if (p[i] == ',' || p[i] == ':' || p[i] == 'x' || p[i] == 'X' ||
		    isspace(p[i]))
			continue;
		return false;
	}

	return hex >= 4;
}

static int oxp_wmi_parse_hex_text(const char *s, u32 len, u8 *out)
{
	const char *end = s + len;
	unsigned int n = 0;

	if (!s)
		return -EPROTO;

	while (s < end && n < OXP_WMI_OUT_LEN) {
		unsigned int v;
		int got = 0;

		while (s < end && (*s == ',' || *s == ':' || isspace(*s)))
			s++;
		if (s >= end || !*s)
			break;
		if (s + 1 < end && s[0] == '0' && (s[1] == 'x' || s[1] == 'X'))
			s += 2;
		if (sscanf(s, "%2x%n", &v, &got) != 1 || got <= 0)
			return -EPROTO;
		out[n++] = v;
		s += got;
	}

	return n >= 2 ? 0 : -EPROTO;
}

static bool oxp_is_utf16le(const u8 *p, u32 len)
{
	u32 i;

	if (!p || len < 4 || (len % 2))
		return false;
	for (i = 1; i < len; i += 2) {
		if (p[i])
			return false;
	}
	return true;
}

static int oxp_wmi_copy_bytes(const u8 *p, u32 len, u8 *out)
{
	u8 ascii[64];
	u32 n, i;

	if (!p || len < 2)
		return -EPROTO;

	if (oxp_is_utf16le(p, len)) {
		n = min_t(u32, len / 2, sizeof(ascii) - 1);
		for (i = 0; i < n; i++)
			ascii[i] = p[i * 2];
		ascii[n] = 0;
		if (oxp_looks_like_hex_text(ascii, n))
			return oxp_wmi_parse_hex_text((char *)ascii, n, out);
		n = min_t(u32, len / 2, OXP_WMI_OUT_LEN);
		for (i = 0; i < n; i++)
			out[i] = p[i * 2];
		return n >= 2 ? 0 : -EPROTO;
	}

	if (oxp_looks_like_hex_text(p, len))
		return oxp_wmi_parse_hex_text((const char *)p, len, out);

	memcpy(out, p, min_t(u32, len, OXP_WMI_OUT_LEN));
	return 0;
}

static void oxp_wmi_describe_obj(const union acpi_object *obj, char *buf,
				 size_t buflen)
{
	unsigned int n, i;
	char *p = buf;
	size_t left = buflen;
	int w;

	if (!buf || !buflen)
		return;
	buf[0] = '\0';
	if (!obj)
		return;

	switch (obj->type) {
	case ACPI_TYPE_INTEGER:
		scnprintf(buf, buflen, "INTEGER 0x%llx",
			  (unsigned long long)obj->integer.value);
		break;
	case ACPI_TYPE_STRING:
		scnprintf(buf, buflen, "STRING len=%u \"%.*s\"",
			  obj->string.length,
			  min_t(u32, obj->string.length, 48),
			  obj->string.pointer ? obj->string.pointer : "");
		break;
	case ACPI_TYPE_BUFFER:
		w = scnprintf(p, left, "BUFFER len=%u", obj->buffer.length);
		if (w < 0)
			return;
		p += w;
		left -= w;
		n = min_t(u32, obj->buffer.length, 16);
		for (i = 0; i < n && left > 4; i++) {
			w = scnprintf(p, left, " %02x",
				      obj->buffer.pointer[i]);
			if (w < 0)
				return;
			p += w;
			left -= w;
		}
		break;
	case ACPI_TYPE_PACKAGE:
		scnprintf(buf, buflen, "PACKAGE count=%u", obj->package.count);
		break;
	default:
		scnprintf(buf, buflen, "type=%u", obj->type);
		break;
	}
}

/*
 * MSI parse_buffer() requires ACPI_TYPE_BUFFER of exact length.
 * OxpWMI MOF returns uStringReturn (hex string or 8-byte block), and
 * ACPI may wrap it as Package { ReturnValue, string }.
 */
static int oxp_wmi_parse_output(union acpi_object *obj, u8 *out)
{
	const union acpi_object *e;
	u32 i, ints;

	memset(out, 0, OXP_WMI_OUT_LEN);
	if (!obj)
		return -ENODATA;

	switch (obj->type) {
	case ACPI_TYPE_BUFFER:
		if (!obj->buffer.pointer)
			return -EPROTO;
		return oxp_wmi_copy_bytes(obj->buffer.pointer,
					  obj->buffer.length, out);

	case ACPI_TYPE_STRING:
		return oxp_wmi_copy_bytes(obj->string.pointer,
					  obj->string.length, out);

	case ACPI_TYPE_PACKAGE:
		if (obj->package.count < 1 || !obj->package.elements)
			return -EPROTO;

		ints = 0;
		for (i = 0; i < obj->package.count; i++) {
			if (obj->package.elements[i].type == ACPI_TYPE_INTEGER)
				ints++;
		}

		if (ints == obj->package.count && ints >= 2) {
			for (i = 0; i < min_t(u32, ints, OXP_WMI_OUT_LEN); i++)
				out[i] = obj->package.elements[i].integer.value &
					 0xff;
			return 0;
		}

		for (i = 0; i < obj->package.count; i++) {
			e = &obj->package.elements[i];
			if (e->type == ACPI_TYPE_STRING ||
			    e->type == ACPI_TYPE_BUFFER ||
			    e->type == ACPI_TYPE_PACKAGE)
				return oxp_wmi_parse_output((union acpi_object *)e,
							    out);
		}
		return oxp_wmi_parse_output(&obj->package.elements[0], out);

	case ACPI_TYPE_INTEGER: {
		u64 v = obj->integer.value;

		out[0] = v & 0xff;
		out[1] = (v >> 8) & 0xff;
		return 0;
	}

	default:
		return -ENOMSG;
	}
}

/*
 * Same shape as msi_wmi_platform_query(): mutex + wmidev_evaluate_method.
 * @input_length is 32 (MSI default), 8, or 4. First 4 bytes are the UInt32.
 * Status polarity is inverted vs MSI: 0x00 is success here.
 */
static int oxp_wmi_query_len(struct oxp_wmi_data *data, u32 method, u32 in_val,
			     u8 *out, size_t input_length)
{
	u8 input[OXP_WMI_IN_LEN] = { 0 };
	struct acpi_buffer acpi_out = { ACPI_ALLOCATE_BUFFER, NULL };
	struct acpi_buffer acpi_in = {
		.length = input_length,
		.pointer = input,
	};
	union acpi_object *obj;
	__le32 packed = cpu_to_le32(in_val);
	acpi_status status;
	int ret;

	if (!input_length || input_length > sizeof(input))
		return -EINVAL;

	memcpy(input, &packed, sizeof(packed));

	mutex_lock(&data->wmi_lock);
	status = wmidev_evaluate_method(data->wdev, 0x0, method, &acpi_in,
					&acpi_out);
	mutex_unlock(&data->wmi_lock);

	if (ACPI_FAILURE(status))
		return -EIO;

	obj = acpi_out.pointer;
	if (!obj)
		return -ENODATA;

	data->last_acpi_type = obj->type;
	data->last_acpi_len = (obj->type == ACPI_TYPE_BUFFER) ?
				      obj->buffer.length :
			      (obj->type == ACPI_TYPE_STRING) ?
				      obj->string.length :
			      (obj->type == ACPI_TYPE_PACKAGE) ?
				      obj->package.count : 0;
	oxp_wmi_describe_obj(obj, data->last_desc, sizeof(data->last_desc));

	ret = oxp_wmi_parse_output(obj, out);
	kfree(obj);
	if (ret)
		return ret;

	memcpy(data->last_out, out, OXP_WMI_OUT_LEN);

	/* MSI: byte0 == 0 is failure. OxpWMI: byte0 == 0 is success. */
	if (out[0] != 0x00)
		return -EIO;

	return 0;
}

static int oxp_wmi_query(struct oxp_wmi_data *data, u32 method, u32 in_val,
			 u8 *out)
{
	return oxp_wmi_query_len(data, method, in_val, out, data->in_len);
}

static int oxp_wmi_read_len(struct oxp_wmi_data *data, u8 reg, u8 *value,
			    size_t input_length)
{
	u8 out[OXP_WMI_OUT_LEN];
	int ret;

	ret = oxp_wmi_query_len(data, OXP_WMI_READ_EC,
				oxp_wmi_pack_read(reg), out, input_length);
	if (ret)
		return ret;

	*value = out[1];
	return 0;
}

static int oxp_wmi_read(struct oxp_wmi_data *data, u8 reg, u8 *value)
{
	return oxp_wmi_read_len(data, reg, value, data->in_len);
}

static int oxp_wmi_write(struct oxp_wmi_data *data, u8 reg, u8 value)
{
	u8 out[OXP_WMI_OUT_LEN];

	return oxp_wmi_query(data, OXP_WMI_WRITE_EC,
			     oxp_wmi_pack_write(reg, value), out);
}

static int oxp_wmi_read_be16(struct oxp_wmi_data *data, u8 hi_reg, u16 *val)
{
	u8 hi, lo;
	int ret;

	ret = oxp_wmi_read(data, hi_reg, &hi);
	if (ret)
		return ret;
	ret = oxp_wmi_read(data, hi_reg + 1, &lo);
	if (ret)
		return ret;

	*val = ((u16)hi << 8) | lo;
	return 0;
}

static bool oxp_temp_plausible(u8 temp)
{
	return temp >= 10 && temp <= 110;
}

static int oxp_wmi_probe_in_len(struct oxp_wmi_data *data)
{
	static const size_t candidates[] = { 32, 8, 4 };
	u8 temp;
	int i, ret, last_err = -ENODEV;

	if (in_len_param == 4 || in_len_param == 8 || in_len_param == 32) {
		data->in_len = in_len_param;
		dev_info(&data->wdev->dev, "using %zu-byte WMI input (forced)\n",
			 data->in_len);
		return 0;
	}

	/* MSI: always 32. Try that first, then MOF-sized 8 and 4. */
	for (i = 0; i < ARRAY_SIZE(candidates); i++) {
		ret = oxp_wmi_read_len(data, OXP_REG_CPU_TEMP, &temp,
				       candidates[i]);
		dev_info(&data->wdev->dev,
			 "ReadECReg in=%zu: ret=%d CPU %u C (%s)\n",
			 candidates[i], ret, ret ? 0 : temp, data->last_desc);
		if (ret) {
			last_err = ret;
			continue;
		}
		data->in_len = candidates[i];
		if (oxp_temp_plausible(temp)) {
			dev_info(&data->wdev->dev,
				 "using %zu-byte WMI input buffer\n",
				 data->in_len);
			return 0;
		}
		last_err = 0;
	}

	if (!data->in_len)
		data->in_len = 32;

	if (last_err)
		return last_err;

	dev_warn(&data->wdev->dev,
		 "using %zu-byte input; CPU temp still 0, dump debugfs last_info\n",
		 data->in_len);
	return 0;
}

/* ---- hwmon (oxpec-compatible scaling: PWM 0-184 ↔ sysfs 0-255) ---- */

static umode_t oxp_wmi_hwmon_is_visible(const void *drvdata,
					enum hwmon_sensor_types type, u32 attr,
					int channel)
{
	switch (type) {
	case hwmon_fan:
	case hwmon_temp:
		return 0444;
	case hwmon_pwm:
		return 0644;
	default:
		return 0;
	}
}

static int oxp_wmi_hwmon_read(struct device *dev, enum hwmon_sensor_types type,
			      u32 attr, int channel, long *val)
{
	struct oxp_wmi_data *data = dev_get_drvdata(dev);
	u16 rpm;
	u8 raw;
	int ret;

	switch (type) {
	case hwmon_fan:
		if (attr != hwmon_fan_input)
			return -EOPNOTSUPP;
		ret = oxp_wmi_read_be16(data, OXP_REG_FAN_H, &rpm);
		if (ret)
			return ret;
		*val = rpm;
		return 0;

	case hwmon_temp:
		if (attr != hwmon_temp_input)
			return -EOPNOTSUPP;
		ret = oxp_wmi_read(data, OXP_REG_CPU_TEMP, &raw);
		if (ret)
			return ret;
		*val = (long)raw * 1000;
		return 0;

	case hwmon_pwm:
		switch (attr) {
		case hwmon_pwm_input:
			ret = oxp_wmi_read(data, OXP_REG_PWM_DUTY, &raw);
			if (ret)
				return ret;
			if (raw > OXP_PWM_MAX)
				raw = OXP_PWM_MAX;
			*val = (raw * 255) / OXP_PWM_MAX;
			return 0;
		case hwmon_pwm_enable:
			ret = oxp_wmi_read(data, OXP_REG_PWM_ENABLE, &raw);
			if (ret)
				return ret;
			/* EC 0 auto → hwmon 2; EC 1 manual → hwmon 1 */
			*val = raw ? 1 : 2;
			return 0;
		default:
			return -EOPNOTSUPP;
		}

	default:
		return -EOPNOTSUPP;
	}
}

static int oxp_wmi_hwmon_write(struct device *dev, enum hwmon_sensor_types type,
			       u32 attr, int channel, long val)
{
	struct oxp_wmi_data *data = dev_get_drvdata(dev);
	u8 duty;
	int ret;

	if (type != hwmon_pwm)
		return -EOPNOTSUPP;

	switch (attr) {
	case hwmon_pwm_enable:
		if (val == 2)
			return oxp_wmi_write(data, OXP_REG_PWM_ENABLE,
					     OXP_PWM_AUTO);
		if (val == 1)
			return oxp_wmi_write(data, OXP_REG_PWM_ENABLE,
					     OXP_PWM_MANUAL);
		if (val != 0)
			return -EINVAL;
		ret = oxp_wmi_write(data, OXP_REG_PWM_ENABLE, OXP_PWM_MANUAL);
		if (ret)
			return ret;
		return oxp_wmi_write(data, OXP_REG_PWM_DUTY, OXP_PWM_MAX);

	case hwmon_pwm_input:
		if (val < 0 || val > 255)
			return -EINVAL;
		duty = (val * OXP_PWM_MAX) / 255;
		return oxp_wmi_write(data, OXP_REG_PWM_DUTY, duty);

	default:
		return -EOPNOTSUPP;
	}
}

static const struct hwmon_ops oxp_wmi_hwmon_ops = {
	.is_visible	= oxp_wmi_hwmon_is_visible,
	.read		= oxp_wmi_hwmon_read,
	.write		= oxp_wmi_hwmon_write,
};

static const struct hwmon_channel_info * const oxp_wmi_hwmon_info[] = {
	HWMON_CHANNEL_INFO(fan, HWMON_F_INPUT),
	HWMON_CHANNEL_INFO(pwm, HWMON_PWM_INPUT | HWMON_PWM_ENABLE),
	HWMON_CHANNEL_INFO(temp, HWMON_T_INPUT),
	NULL
};

static const struct hwmon_chip_info oxp_wmi_chip_info = {
	.ops	= &oxp_wmi_hwmon_ops,
	.info	= oxp_wmi_hwmon_info,
};

/* ---- device sysfs: charge + power-supply mode ---- */

static ssize_t charge_control_end_threshold_show(struct device *dev,
						 struct device_attribute *attr,
						 char *buf)
{
	struct oxp_wmi_data *data = dev_get_drvdata(dev);
	u8 val;
	int ret;

	ret = oxp_wmi_read(data, OXP_REG_CHARGE_LIMIT, &val);
	if (ret)
		return ret;
	if (val > 100)
		return -EINVAL;
	return sysfs_emit(buf, "%u\n", val);
}

static ssize_t charge_control_end_threshold_store(struct device *dev,
						  struct device_attribute *attr,
						  const char *buf, size_t count)
{
	struct oxp_wmi_data *data = dev_get_drvdata(dev);
	unsigned int val;
	int ret;

	ret = kstrtouint(buf, 0, &val);
	if (ret)
		return ret;
	if (val > 100)
		return -EINVAL;
	ret = oxp_wmi_write(data, OXP_REG_CHARGE_LIMIT, val);
	return ret ? ret : count;
}

static ssize_t charge_behaviour_show(struct device *dev,
				     struct device_attribute *attr, char *buf)
{
	struct oxp_wmi_data *data = dev_get_drvdata(dev);
	u8 val;
	int ret;

	ret = oxp_wmi_read(data, OXP_REG_CHARGE_BYPASS, &val);
	if (ret)
		return ret;

	switch (val) {
	case OXP_BYPASS_AUTO:
		return sysfs_emit(buf, "[auto] inhibit-charge-awake inhibit-charge\n");
	case OXP_BYPASS_AWAKE:
		return sysfs_emit(buf, "auto [inhibit-charge-awake] inhibit-charge\n");
	case OXP_BYPASS_ALWAYS:
		return sysfs_emit(buf, "auto inhibit-charge-awake [inhibit-charge]\n");
	default:
		return sysfs_emit(buf, "unknown %u\n", val);
	}
}

static ssize_t charge_behaviour_store(struct device *dev,
				      struct device_attribute *attr,
				      const char *buf, size_t count)
{
	struct oxp_wmi_data *data = dev_get_drvdata(dev);
	u8 val;
	int ret;

	if (sysfs_streq(buf, "auto"))
		val = OXP_BYPASS_AUTO;
	else if (sysfs_streq(buf, "inhibit-charge-awake"))
		val = OXP_BYPASS_AWAKE;
	else if (sysfs_streq(buf, "inhibit-charge"))
		val = OXP_BYPASS_ALWAYS;
	else
		return -EINVAL;

	ret = oxp_wmi_write(data, OXP_REG_CHARGE_BYPASS, val);
	return ret ? ret : count;
}

static ssize_t power_supply_mode_show(struct device *dev,
				      struct device_attribute *attr, char *buf)
{
	struct oxp_wmi_data *data = dev_get_drvdata(dev);
	u8 e3, oxp;
	const char *name;
	int ret;

	ret = oxp_wmi_read(data, OXP_REG_POWER_SUPPLY, &e3);
	if (ret)
		return ret;

	if (e3 == 16)
		oxp = 8;
	else if (e3 == 18)
		oxp = 2;
	else
		oxp = e3;

	switch (oxp) {
	case 1:
		name = "battery";
		break;
	case 2:
		name = "typec-100w";
		break;
	case 3:
		name = "typec-100w+battery";
		break;
	case 4:
	case 5:
		name = "typec-140w";
		break;
	case 8:
		name = "typec-65w";
		break;
	case 9:
		name = "typec-65w+battery";
		break;
	default:
		name = "unknown";
		break;
	}

	return sysfs_emit(buf, "%u %s oxp=%u batt=%u pd100=%u pd65=%u ac_only=%u\n",
			  e3, name, oxp,
			  !!(e3 & 0x01), !!(e3 & 0x02),
			  !!(e3 & 0x08) || e3 == 0x10, !!(e3 & 0x10));
}

static DEVICE_ATTR_RW(charge_control_end_threshold);
static DEVICE_ATTR_RW(charge_behaviour);
static DEVICE_ATTR_RO(power_supply_mode);

static struct attribute *oxp_wmi_attrs[] = {
	&dev_attr_charge_control_end_threshold.attr,
	&dev_attr_charge_behaviour.attr,
	&dev_attr_power_supply_mode.attr,
	NULL
};
ATTRIBUTE_GROUPS(oxp_wmi);

/* ---- debugfs ---- */

static int oxp_dbg_ec_open(struct inode *inode, struct file *file)
{
	file->private_data = inode->i_private;
	return 0;
}

static ssize_t oxp_dbg_read_ec_write(struct file *file, const char __user *ubuf,
				     size_t len, loff_t *off)
{
	struct oxp_wmi_data *data = file->private_data;
	u8 buf[1];
	u8 dummy;
	int ret;

	if (*off || len < 1)
		return -EINVAL;
	if (copy_from_user(buf, ubuf, 1))
		return -EFAULT;
	ret = oxp_wmi_read(data, buf[0], &dummy);
	return ret ? ret : 1;
}

static ssize_t oxp_dbg_write_ec_write(struct file *file, const char __user *ubuf,
				      size_t len, loff_t *off)
{
	struct oxp_wmi_data *data = file->private_data;
	u8 buf[2];
	int ret;

	if (*off || len < 2)
		return -EINVAL;
	if (copy_from_user(buf, ubuf, 2))
		return -EFAULT;
	ret = oxp_wmi_write(data, buf[0], buf[1]);
	return ret ? ret : 2;
}

static ssize_t oxp_dbg_last_out_read(struct file *file, char __user *ubuf,
				     size_t len, loff_t *off)
{
	struct oxp_wmi_data *data = file->private_data;

	return simple_read_from_buffer(ubuf, len, off, data->last_out,
				       OXP_WMI_OUT_LEN);
}

static ssize_t oxp_dbg_last_info_read(struct file *file, char __user *ubuf,
				      size_t len, loff_t *off)
{
	struct oxp_wmi_data *data = file->private_data;
	char buf[256];
	int n;

	n = scnprintf(buf, sizeof(buf),
		      "in_len=%zu acpi_type=%u acpi_len=%u\n"
		      "out=%02x %02x %02x %02x %02x %02x %02x %02x\n"
		      "%s\n",
		      data->in_len, data->last_acpi_type, data->last_acpi_len,
		      data->last_out[0], data->last_out[1],
		      data->last_out[2], data->last_out[3],
		      data->last_out[4], data->last_out[5],
		      data->last_out[6], data->last_out[7],
		      data->last_desc);
	return simple_read_from_buffer(ubuf, len, off, buf, n);
}

static const struct file_operations oxp_dbg_read_ec_fops = {
	.owner	= THIS_MODULE,
	.open	= oxp_dbg_ec_open,
	.write	= oxp_dbg_read_ec_write,
	.read	= oxp_dbg_last_out_read,
	.llseek	= default_llseek,
};

static const struct file_operations oxp_dbg_write_ec_fops = {
	.owner	= THIS_MODULE,
	.open	= oxp_dbg_ec_open,
	.write	= oxp_dbg_write_ec_write,
	.read	= oxp_dbg_last_out_read,
	.llseek	= default_llseek,
};

static const struct file_operations oxp_dbg_last_info_fops = {
	.owner	= THIS_MODULE,
	.open	= oxp_dbg_ec_open,
	.read	= oxp_dbg_last_info_read,
	.llseek	= default_llseek,
};

static void oxp_wmi_debugfs_remove(void *dentry)
{
	debugfs_remove_recursive(dentry);
}

static void oxp_wmi_debugfs_init(struct oxp_wmi_data *data)
{
	char name[64];
	struct dentry *dir;

	scnprintf(name, sizeof(name), "%s-%s", DRIVER_NAME,
		  dev_name(&data->wdev->dev));
	dir = debugfs_create_dir(name, NULL);
	if (IS_ERR(dir))
		return;

	if (devm_add_action_or_reset(&data->wdev->dev, oxp_wmi_debugfs_remove,
				     dir))
		return;

	data->debugfs = dir;
	debugfs_create_file("read_ec", 0600, dir, data, &oxp_dbg_read_ec_fops);
	debugfs_create_file("write_ec", 0600, dir, data, &oxp_dbg_write_ec_fops);
	debugfs_create_file("last_info", 0400, dir, data,
			    &oxp_dbg_last_info_fops);
}

/* ---- probe ---- */

static int oxp_wmi_probe(struct wmi_device *wdev, const void *context)
{
	struct oxp_wmi_data *data;
	struct device *hdev;
	u8 temp;
	int ret;

	data = devm_kzalloc(&wdev->dev, sizeof(*data), GFP_KERNEL);
	if (!data)
		return -ENOMEM;

	data->wdev = wdev;
	data->in_len = OXP_WMI_IN_LEN;
	mutex_init(&data->wmi_lock);
	dev_set_drvdata(&wdev->dev, data);

	ret = oxp_wmi_probe_in_len(data);
	if (ret) {
		dev_err(&wdev->dev,
			"ReadECReg probe failed (%d). Wrong GUID/packing?\n",
			ret);
		if (!force)
			return ret;
		dev_warn(&wdev->dev, "Continuing because force=1\n");
	}

	ret = oxp_wmi_read(data, OXP_REG_CPU_TEMP, &temp);
	if (ret) {
		dev_err(&wdev->dev, "ReadECReg failed after in_len pick (%d)\n",
			ret);
		if (!force)
			return ret;
	} else {
		dev_info(&wdev->dev, "OxpWMI ok, CPU temp %u C (in_len=%zu)\n",
			 temp, data->in_len);
	}

	oxp_wmi_debugfs_init(data);

	hdev = devm_hwmon_device_register_with_info(&wdev->dev, "oxp_wmi", data,
						    &oxp_wmi_chip_info, NULL);
	return PTR_ERR_OR_ZERO(hdev);
}

static const struct wmi_device_id oxp_wmi_id_table[] = {
	{ OXP_WMI_GUID, NULL },
	{ }
};
MODULE_DEVICE_TABLE(wmi, oxp_wmi_id_table);

static struct wmi_driver oxp_wmi_driver = {
	.driver = {
		.name		= DRIVER_NAME,
		.dev_groups	= oxp_wmi_groups,
		.probe_type	= PROBE_PREFER_ASYNCHRONOUS,
	},
	.id_table	= oxp_wmi_id_table,
	.probe		= oxp_wmi_probe,
	.no_singleton	= true,
};

static const struct dmi_system_id oxp_wmi_vendor_dmi[] __initconst = {
	{
		.matches = {
			DMI_MATCH(DMI_SYS_VENDOR, "ONE-NETBOOK"),
		},
	},
	{
		.matches = {
			DMI_MATCH(DMI_BOARD_VENDOR, "ONE-NETBOOK"),
		},
	},
	{ }
};

static const struct dmi_system_id oxp_wmi_amd_dmi[] __initconst = {
	{
		.matches = {
			DMI_EXACT_MATCH(DMI_PRODUCT_NAME, "ONEXPLAYER X2Mini PRO"),
		},
	},
	{
		.matches = {
			DMI_EXACT_MATCH(DMI_BOARD_NAME, "ONEXPLAYER X2Mini PRO"),
		},
	},
	{
		.matches = {
			DMI_EXACT_MATCH(DMI_PRODUCT_NAME, "ONEXPLAYER APEX"),
		},
	},
	{
		.matches = {
			DMI_EXACT_MATCH(DMI_BOARD_NAME, "ONEXPLAYER APEX"),
		},
	},
	{ }
};

static int __init oxp_wmi_init(void)
{
	if (dmi_check_system(oxp_wmi_amd_dmi)) {
		if (!force)
			return -ENODEV;
		pr_warn("AMD / WinRing0 SKU; loading because force=1\n");
	} else if (!dmi_check_system(oxp_wmi_vendor_dmi)) {
		if (!force)
			return -ENODEV;
		pr_warn("Ignoring DMI vendor check\n");
	}

	return wmi_driver_register(&oxp_wmi_driver);
}

static void __exit oxp_wmi_exit(void)
{
	wmi_driver_unregister(&oxp_wmi_driver);
}

module_init(oxp_wmi_init);
module_exit(oxp_wmi_exit);

MODULE_AUTHOR("steamos-onexplayer");
MODULE_DESCRIPTION("OneXPlayer OxpWMI EC access (Intel)");
MODULE_VERSION("0.2");
MODULE_LICENSE("GPL");
MODULE_ALIAS("wmi:" OXP_WMI_GUID);
