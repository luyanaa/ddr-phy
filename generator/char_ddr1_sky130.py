#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""sky130 DDR1 SSTL-2 characterization — thin process profile over the
process-neutral engine in char_ddr1_sstl2.py.

EXPERIMENTAL: sky130 has no characterized 2.5 V IO library. The IO devices
are 5 V-gate-class nfet/pfet_g5v0d10v5 operated at 2.5 V inside their safe
operating area. signoff is False; evidence is a witness-point study only.
"""

from char_ddr1_sstl2 import characterize

# MOS corner, resistor corner, degrees C, core V, I/O V.
# Xyce uses an explicitly disclosed nominal linear resistor approximation.
# The resistor corner here is a case label, not a varied resistor model.
# SSTL-2 Class I supply is 2.5 V +/- 0.2 / core 1.8 V +/- 10 %.
CASES = {
    "tt": ("tt", "typ", 27, 1.80, 2.50),
    "ss_low": ("ss", "wcs", 125, 1.62, 2.30),
    "ss_shift": ("ss", "wcs", 125, 1.62, 2.70),
    "ff_high": ("ff", "bcs", -40, 1.98, 2.70),
    "ff_hot": ("ff", "bcs", 125, 1.98, 2.70),
    "sf_shift": ("sf", "wcs", 125, 1.62, 2.70),
    "fs_low_io": ("fs", "wcs", 125, 1.62, 2.30),
}


PROFILE = {
    "name": "sky130",
    "subckt": "sky130_sstl2_dq",
    "default_cell": "sch/pads/sky130/sstl2_dq.spice",
    "device_yaml": "specs/pads/devices/sky130.yaml",
    "cases": CASES,
    "license": "Apache-2.0 (SkyWater PDK Authors); 2.5 V operating point UNCHARACTERIZED",
    "required_root_files": ["libs.tech/ngspice/sky130.lib.spice"],
}


def main():
    return characterize(PROFILE)


if __name__ == "__main__":
    raise SystemExit(main())
