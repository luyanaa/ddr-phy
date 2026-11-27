#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""First-order package RLC from an IHP bondplan report.

The bondplan report is produced by the IHP AMS template's
packaging/scripts/run_bondplan.py.  This script does not replace a 3D
field solver: it converts the *drawn* gold bondwire length and a fixed
leadframe allowance into a per-pin series R-L and a lumped shunt C, so the
numbers can be carried into an ngspice package deck or an RTL timing
derate.  The model is deliberately conservative and marked non-signoff.
"""
import argparse
import json
import math
import re
from pathlib import Path

# Geometry / material assumptions.  Keep them explicit and overridable.
RHO_AU = 2.44e-8       # ohm*m, gold
WIRE_DIAMETER_M = 25e-6
RHO_CU = 1.68e-8       # ohm*m, leadframe copper
LEAD_THICKNESS_M = 200e-6
MU0 = 4.0 * math.pi * 1e-7

# A QFN lead finger is short; use a fixed allowance instead of pretending to
# extract the leadframe from the package GDS.  These are update points when a
# real leadframe stack-up is available.
LEAD_R_OHM = 0.006
LEAD_L_H = 0.120e-9
PKG_C_PF = 0.100

LINE_RE = re.compile(
    r"\|\s*(\d+)\s*\|\s*([A-Za-z0-9_\[\]\\]+)\s*\|"
    r"\s*([-\d.]+)\s*/\s*([-\d.]+)\s*\|"
    r"\s*([-\d.]+)\s*/\s*([-\d.]+)\s*\|"
    r"\s*([\d.]+)\s*\|"
)


def wire_rl(length_m):
    area = math.pi * (WIRE_DIAMETER_M / 2.0) ** 2
    r = RHO_AU * length_m / area
    # Straight-round-wire low-frequency formula; loop height is already in
    # the bondplan length.
    l = (MU0 * length_m / (2.0 * math.pi)) * (
        math.log(2.0 * length_m / (WIRE_DIAMETER_M / 2.0)) - 0.75
    )
    return r, l


def parse_bondplan(path):
    rows = []
    for line in Path(path).read_text().splitlines():
        m = LINE_RE.match(line)
        if not m:
            continue
        rows.append(
            {
                "pin": int(m.group(1)),
                "pad": m.group(2).replace("\\", ""),
                "die_x_um": float(m.group(3)),
                "die_y_um": float(m.group(4)),
                "pkg_x_um": float(m.group(5)),
                "pkg_y_um": float(m.group(6)),
                "wire_len_um": float(m.group(7)),
            }
        )
    if not rows:
        raise SystemExit(f"no bond table rows found in {path}")
    return rows


def build(rows, package, die_size_um, pad_pitch_um, source):
    out = []
    for row in rows:
        length_m = row["wire_len_um"] * 1e-6
        r_wire, l_wire = wire_rl(length_m)
        r_total = r_wire + LEAD_R_OHM
        l_total = l_wire + LEAD_L_H
        out.append(
            {
                **row,
                "r_wire_ohm": round(r_wire, 5),
                "l_wire_nh": round(l_wire * 1e9, 4),
                "r_total_ohm": round(r_total, 5),
                "l_total_nh": round(l_total * 1e9, 4),
                "c_total_pf": PKG_C_PF,
                # Conservative bound for a 50 ohm channel; not a delay
                # extracted from a 3D solve.
                "t_l_over_50_ps": round(l_total / 50.0 * 1e12, 2),
            }
        )
    l_values = [r["l_total_nh"] for r in out]
    r_values = [r["r_total_ohm"] for r in out]
    t_values = [r["t_l_over_50_ps"] for r in out]
    return {
        "meta": {
            "source": source,
            "package": package,
            "die_size_um": die_size_um,
            "pad_pitch_um": pad_pitch_um,
            "wire_diameter_um": WIRE_DIAMETER_M * 1e6,
            "lead_r_ohm": LEAD_R_OHM,
            "lead_l_nh": LEAD_L_H * 1e9,
            "pkg_c_pf": PKG_C_PF,
            "model": "first-order series R-L + lumped shunt C; not 3D EM signoff",
            "signoff": False,
        },
        "summary": {
            "wire_len_um": [min(r["wire_len_um"] for r in out), max(r["wire_len_um"] for r in out)],
            "l_total_nh": [min(l_values), max(l_values)],
            "r_total_ohm": [min(r_values), max(r_values)],
            "t_l_over_50_ps": [min(t_values), max(t_values)],
        },
        "pins": out,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bondplan", required=True)
    ap.add_argument("--package", required=True)
    ap.add_argument("--die-size-um", type=float, required=True)
    ap.add_argument("--pad-pitch-um", type=float, required=True)
    ap.add_argument("--output", required=True)
    args = ap.parse_args()
    rows = parse_bondplan(args.bondplan)
    data = build(rows, args.package, args.die_size_um, args.pad_pitch_um, args.bondplan)
    Path(args.output).write_text(json.dumps(data, indent=2) + "\n")
    print(
        f"{args.package}: {len(rows)} pins, "
        f"wire {data['summary']['wire_len_um'][0]:.0f}-{data['summary']['wire_len_um'][1]:.0f} um, "
        f"L {data['summary']['l_total_nh'][0]:.2f}-{data['summary']['l_total_nh'][1]:.2f} nH, "
        f"R {data['summary']['r_total_ohm'][0]:.3f}-{data['summary']['r_total_ohm'][1]:.3f} ohm"
    )


if __name__ == "__main__":
    main()
