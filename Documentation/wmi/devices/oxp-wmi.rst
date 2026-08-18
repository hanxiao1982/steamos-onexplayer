.. SPDX-License-Identifier: GPL-2.0-or-later

====================================================
OneXPlayer OxpWMI (SuRwECRegInterface)
====================================================

OneXPlayer Intel handhelds that use OxpWMI (``SuRwECRegInterface``) expose
EC RAM through ACPI-WMI, not through the ACPI Embedded Controller address
space that ``oxpec`` uses on AMD boards.

This driver is the Linux client for that interface. The call pattern matches
``msi-wmi-platform`` (mutex around the ``WMxx`` evaluate). The GUID and method
table do not. Windows CIM sends ``GroupOffset`` as an ACPI Integer; this driver
calls ``WMxx`` the same way after reading the object id from ``_WDG``. Using
``wmidev_evaluate_method()`` alone passes Arg2 as a Buffer/String and can
return status ``0x00`` with every EC value ``0``.

WMI interface
=============

GUID ``43B5A593-AD62-4257-8546-91B0797BEC1B``
Windows class ``SuRwECRegInterface`` (``root\\WMI``)

========  ============  =======================
Method    WmiMethodId   Input (4-byte LE)
========  ============  =======================
ReadECReg     1         ``04 reg 00 00``
WriteECReg    2         ``04 reg val 00`` (hypothesized)
========  ============  =======================

Output is an 8-byte block (ACPI buffer, hex string ``uStringReturn``, or a
package of bytes / ``{ ReturnValue, string }``). Byte 0 is status
(``0x00`` success, ``0xFF`` failure). Byte 1 is the EC value.

Do not bind ``ABBC0F6E-8EA1-11D1-00A0-C90629100000`` (MSI / Microsoft sample).

Sysfs
=====

hwmon device ``oxp_wmi``
  ``fan1_input``, ``pwm1``, ``pwm1_enable``, ``temp1_input``

WMI device attributes
  ``charge_control_end_threshold``, ``charge_behaviour``, ``power_supply_mode``

See ``docs/ec/oxp-wmi.md`` in this repository for the live register map and
userspace examples.
