#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""ics55 DDR1 SSTL-2 characterization - thin profile over char_ddr1_sstl2.py.

License: vendor evaluation/research only; signoff=False always, evidence is
license=evaluation-only and never tapeout signoff. Corners tt/ss/ff/fnsp/snfp
are wired via flat per-corner cornerparams_<corner>.inc files (non-zero wrapper
deltas extracted by generator/gen_ics55_corners.py; the foundry nested .lib
wrapper is not parseable by ngspice, so corners cannot be selected through it).
ics55 has the ONLY native 2.5 V IO devices (nm2p5_lp/pm2p5_lp) among the
secondary lanes and native 2.5 V diodes, so it is the highest-value secondary lane.
"""

from char_ddr1_sstl2 import characterize

# MOS corner, resistor corner, degrees C, core V, I/O V.
# core 1.2 V (ics55 core), IO 2.5 +/- 0.2 (native 2.5 V devices).
# All corners use real per-corner device models (offsets wired, verified correct direction).
CASES = {
    "tt": ("tt", "tt", 27, 1.20, 2.50),
    "ss_low": ("ss", "ss", 125, 1.08, 2.30),
    "ss_shift": ("ss", "ss", 125, 1.08, 2.70),
    "ff_high": ("ff", "ff", -40, 1.32, 2.70),
    "ff_hot": ("ff", "ff", 125, 1.32, 2.70),
    "sf_shift": ("fnsp", "ss", 125, 1.08, 2.70),
    "fs_low_io": ("snfp", "ss", 125, 1.08, 2.30),
}


def res_model_line(pdk, res_corner):
    # resistor.ckt ships flat in the includes list; no cornered res section.
    return ""


def extra_model_lines(pdk, mos_corner):
    # Per-corner flat-include delta offsets. The foundry hspice wrapper uses
    # nested .lib sections that re-.INC the subckt/.mdl files, which ngspice
    # cannot parse (subckt redefinition -> fatal). We instead extracted the
    # per-corner .PARAM delta values (corner_ratio=1, mismatch forced 0) into
    # generated cornerparams_<corner>.inc files; see generator/gen_ics55_corners.py.
    # mos_corner is one of tt/ff/ss/fnsp/snfp; the corner file must exist.
    inc = pdk / "libs.tech/spice/foundry/ngspice" / ("cornerparams_%s.inc" % mos_corner)
    if not inc.exists():
        raise SystemExit("ERROR: missing corner file: %s" % inc)
    return '.include "%s"' % inc


PROFILE = {
    "name": "ics55",
    "subckt": "ics55_sstl2_dq",
    "default_cell": "sch/pads/ics55/sstl2_dq.spice",
    "device_yaml": "specs/pads/devices/ics55.yaml",
    "cases": CASES,
    "res_model_line": res_model_line,
    "extra_model_lines": extra_model_lines,
    "dc_solver": "klu",
    "license": "foundry evaluation/research only; signoff=False; corners tt/ss/ff/fnsp/snfp wired",
    "required_root_files": ["libs.tech/spice/foundry/ngspice/mos/nio25.mdl"],
    "spiceinit": "* local empty spiceinit: neutralizes global ~/.spiceinit\n",
}


def main():
    return characterize(PROFILE)


if __name__ == "__main__":
    raise SystemExit(main())
