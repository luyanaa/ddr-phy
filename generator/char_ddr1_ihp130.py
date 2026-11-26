#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""IHP SG13G2 DDR1 SSTL-2 characterization — thin process profile over the
process-neutral engine in char_ddr1_sstl2.py.

All bench waveforms, hard limits and measurement names live in the shared
engine. This file only injects IHP-specific model inclusion, corner sections,
supply voltages and OSDI setup. signoff is False: the 2.5 V operating point is
NOT characterized by IHP (HV devices are 3.3 V Vds-rated); evidence is a
witness-point study, never a tapeout claim.
"""

from pathlib import Path

from char_ddr1_sstl2 import characterize

MODEL = Path("libs.tech/ngspice/models")
OSDI = ("psp103", "psp103_nqs", "r3_cmc", "mosvar")

# MOS corner, resistor corner, degrees C, core V, I/O V.
# The corner keys (tt/ss/ff/sf/fs) index into specs/pads/devices/ihp130.yaml
# char.corners -> mos_<key> sections; resistors use cornerRES.lib res_<res>.
CASES = {
    "tt": ("tt", "typ", 27, 1.20, 2.50),
    "ss_low": ("ss", "wcs", 125, 1.08, 2.30),
    "ss_shift": ("ss", "wcs", 125, 1.08, 2.70),
    "ff_high": ("ff", "bcs", -40, 1.32, 2.70),
    "ff_hot": ("ff", "bcs", 125, 1.32, 2.70),
    "sf_shift": ("sf", "wcs", 125, 1.08, 2.70),
    "fs_low_io": ("fs", "wcs", 125, 1.08, 2.30),
}


def res_model_line(pdk, res_corner):
    return f'.lib "{pdk / MODEL / "cornerRES.lib"}" res_{res_corner}'


def extra_model_lines(pdk, mos_corner):
    return ""


PROFILE = {
    "name": "ihp130",
    "subckt": "ihp130_sstl2_dq",
    "default_cell": "sch/pads/ihp130/sstl2_dq.spice",
    "device_yaml": "specs/pads/devices/ihp130.yaml",
    "cases": CASES,
    "res_model_line": res_model_line,
    "extra_model_lines": extra_model_lines,
    "dc_solver": "klu",
    "license": "Apache-2.0 (IHP PDK Authors); 2.5 V operating point UNCHARACTERIZED",
    "required_root_files": [str(MODEL / "cornerRES.lib")] + [
        str(Path("libs.tech/ngspice/osdi") / f"{n}.osdi") for n in OSDI
    ],
    "spiceinit": (
        "setcs sourcepath = ( $sourcepath @root@/libs.tech/ngspice/models )\n"
        "osdi '@root@/libs.tech/ngspice/osdi/psp103.osdi'\n"
        "osdi '@root@/libs.tech/ngspice/osdi/psp103_nqs.osdi'\n"
        "osdi '@root@/libs.tech/ngspice/osdi/r3_cmc.osdi'\n"
        "osdi '@root@/libs.tech/ngspice/osdi/mosvar.osdi'\n"
    ),
}


def main():
    return characterize(PROFILE)


if __name__ == "__main__":
    raise SystemExit(main())
