#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""gf180mcuD DDR1 SSTL-2 characterization - thin profile over char_ddr1_sstl2.py.

EXPERIMENTAL_UNCHARACTERIZED + PHYSICAL NO-GO: GF180's 2.3-2.7 V SSTL-2
operating point using 03v3 devices is not foundry-characterized. This lane
is a schematic witness only; it does not establish SSTL-2 compliance.
signoff=False always.
"""

from char_ddr1_sstl2 import characterize

# MOS corner, resistor corner, degrees C, core V, I/O V.
# core_v nominal is 3.3 V (gf180mcu core == io device rating). The SSTL-2 IO rail
# is fixed at 2.5 +/- 0.2 by JEDEC regardless of what the devices are rated for.
# cornersonly typical/ss/ff exist in sm141064.ngspice.
CASES = {
    "tt": ("tt", "typ", 27, 3.30, 2.50),
    "ss_low": ("ss", "wcs", 125, 2.97, 2.30),
    "ss_shift": ("ss", "wcs", 125, 2.97, 2.70),
    "ff_high": ("ff", "bcs", -40, 3.63, 2.70),
    "ff_hot": ("ff", "bcs", 125, 3.63, 2.70),
    "sf_shift": ("ff", "wcs", 125, 2.97, 2.70),
    "fs_low_io": ("ss", "wcs", 125, 2.97, 2.30),
}


RES_SECTIONS = {"tt": "res_typical", "ss": "res_ss", "ff": "res_ff",
                "typ": "res_typical", "wcs": "res_ss", "bcs": "res_ff"}


def res_model_line(pdk, res_corner):
    # ppolyf_u lives in cornered res sections of sm141064.ngspice.
    section = RES_SECTIONS.get(res_corner, "res_typical")
    return '.lib "%s/libs.tech/ngspice/sm141064.ngspice" %s' % (pdk, section)


def extra_model_lines(pdk, mos_corner):
    return ""


PROFILE = {
    "name": "gf180mcu",
    "subckt": "gf180_sstl2_dq",
    "default_cell": "sch/pads/gf180mcu/sstl2_dq.spice",
    "device_yaml": "specs/pads/devices/gf180mcuD.yaml",
    "cases": CASES,
    "res_model_line": res_model_line,
    "extra_model_lines": extra_model_lines,
    "dc_solver": "klu",
    "license": "Apache-2.0 (GlobalFoundries PDK Authors); 2.5 V op-point UNCHARACTERIZED, NO_GO",
    "required_root_files": ["libs.tech/ngspice/sm141064.ngspice"],
    "spiceinit": "* local empty spiceinit: neutralizes global ~/.spiceinit\n",
}


def main():
    return characterize(PROFILE)


if __name__ == "__main__":
    raise SystemExit(main())
