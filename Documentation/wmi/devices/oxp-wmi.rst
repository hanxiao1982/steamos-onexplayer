.. SPDX-License-Identifier: GPL-2.0-or-later

====================================================
OneXPlayer OxpWMI (SuRwECRegInterface)
====================================================

OneXPlayer Intel handhelds that use OxpWMI (``SuRwECRegInterface``) expose
EC RAM through ACPI-WMI, not through the ACPI Embedded Controller address
space that ``oxpec`` uses on AMD boards.

This driver is the Linux client for that interface. It uses a driver mutex
like ``msi-wmi-platform``, but calls ACPI method ``WMAC`` with Integer Arg2
(Windows CIM). ``wmidev_evaluate_method`` Buffer Arg2 is fallback only.
The GUID and method table are not MSI's.

WMI interface
=============

GUID ``43B5A593-AD62-4257-8546-91B0797BEC1B``
Windows class ``SuRwECRegInterface`` (``root\\WMI``)

========  ============  ==========================================
Method    WmiMethodId   Input (ACPI Integer / UInt32)
========  ============  ==========================================
ReadECReg     1         ``0x04 | (reg << 8)``
WriteECReg    2         ``0x04 | (reg << 8) | (val << 16)``
========  ============  ==========================================

WriteECReg (method 2) is the apply. WriteReadECReg (method 3) is not
required. Output is STRING ``"0x00,0xNN,..."``. Byte 0 is status
(``0x00`` success, ``0xFF`` failure). Byte 1 is the EC value.

Entering manual PWM (``pwm1_enable=1``) writes ``0x4A=1`` then rewrites
``0x4B`` so leftover duty latches.

Do not bind ``ABBC0F6E-8EA1-11D1-00A0-C90629100000`` (MSI / Microsoft sample).

Sysfs
=====

hwmon device ``oxp_wmi``
  ``fan1_input``, ``pwm1``, ``pwm1_enable``, ``temp1_input``

WMI device attributes
  ``charge_control_end_threshold``, ``charge_behaviour``, ``power_supply_mode``

See ``docs/ec/oxp-wmi.md`` in this repository for the live register map and
userspace examples.
