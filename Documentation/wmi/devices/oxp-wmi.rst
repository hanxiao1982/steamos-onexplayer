.. SPDX-License-Identifier: GPL-2.0-or-later

====================================================
OneXPlayer OxpWMI (SuRwECRegInterface)
====================================================

OneXPlayer Intel handhelds that use OxpWMI (``SuRwECRegInterface``) expose
EC RAM through ACPI-WMI, not through the ACPI Embedded Controller address
space that ``oxpec`` uses on AMD boards.

This driver is the Linux client for that interface. The call path matches
``msi-wmi-platform``: a driver mutex around
``wmidev_evaluate_method(wdev, 0x0, method, in, out)``, with a **32-byte**
zeroed input buffer (Windows ``CreateByteField()`` quirk). The GUID, method
IDs, and payload layout do not match MSI.

WMI interface
=============

GUID ``43B5A593-AD62-4257-8546-91B0797BEC1B``
Windows class ``SuRwECRegInterface`` (``root\\WMI``)

========  ============  ==========================================
Method    WmiMethodId   Input (32-byte Buffer, first 4 bytes LE)
========  ============  ==========================================
ReadECReg     1         ``04 reg 00 00`` + 28 zero bytes
WriteECReg    2         ``04 reg val 00`` + 28 zero bytes (hypothesized)
========  ============  ==========================================

On X2 Mini Linux the method returns an ACPI string
``"0x00,0x28,0x00,0x00,0x00,0x00,0x00,0x00"`` (status + EC byte as
``0xNN`` hex). Byte 0 is status (``0x00`` success, ``0xFF`` failure).
Byte 1 is the EC value. The WMI object id is ``AC`` (ACPI method ``WMAC``).
Input must be a 32-byte buffer; 4 bytes return success and value 0.

Do not bind ``ABBC0F6E-8EA1-11D1-00A0-C90629100000`` (MSI / Microsoft sample).

Sysfs
=====

hwmon device ``oxp_wmi``
  ``fan1_input``, ``pwm1``, ``pwm1_enable``, ``temp1_input``

WMI device attributes
  ``charge_control_end_threshold``, ``charge_behaviour``, ``power_supply_mode``

See ``docs/ec/oxp-wmi.md`` in this repository for the live register map and
userspace examples.
