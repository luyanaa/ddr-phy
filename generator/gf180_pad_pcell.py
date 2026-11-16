#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""GF180MCU pad PCell prototype (pad/metal/via layers only).

Run with:
    klayout -b -r generator/gf180_pad_pcell.py

This is a PARAMETERIZED PAD-ONLY TEST STRUCTURE, not the full bidirectional
pad macro. It has no ESD diodes, driver/receiver devices, or schematic, so
LVS/PEX and ESD qualification are out of scope here. The next step is to
add the device layers from the generated SPICE topology.
"""
import json
import os
from pathlib import Path

import pya

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "sch" / "pads" / "gf180mcuD" / "pcell"

# GF180MCU layer numbers (libs.tech/klayout/tech/pymacros/sealring_cells/layers.py)
L = {
    "Comp": (22, 0), "Nwell": (21, 0), "Pplus": (31, 0), "Nplus": (32, 0),
    "Poly2": (30, 0), "Contact": (33, 0),
    "Metal1": (34, 0), "Metal2": (36, 0), "Metal3": (42, 0),
    "Metal4": (46, 0), "Metal5": (81, 0), "MetalTop": (53, 0),
    "Via1": (35, 0), "Via2": (38, 0), "Via3": (40, 0),
    "Via4": (41, 0), "Via5": (82, 0),
    "Pad": (37, 0), "GUARD_RING_MK": (167, 5), "PR_bndry": (0, 0),
}


def box(x0, y0, x1, y1):
    return pya.Box(int(x0), int(y0), int(x1), int(y1))


def vias(cell, layer, x0, y0, x1, y1, via=260, pitch=2000):
    g = cell.shapes(layer)
    y = y0
    while y + via <= y1:
        x = x0
        while x + via <= x1:
            g.insert(box(x, y, x + via, y + via))
            x += pitch
        y += pitch


def main():
    dbu = 0.001
    pad_um = 60.0
    metal_um = 64.0
    seal_um = 80.0
    p = int(round(pad_um / dbu))
    m = int(round(metal_um / dbu))
    s = int(round(seal_um / dbu))

    ly = pya.Layout()
    ly.dbu = dbu
    c = ly.create_cell("gf180_pad_pcell")
    # Layer numbers are sufficient for the prototype; names stay in the
    # manifest rather than being written into the GDS.

    # Pad opening (passivation cut) and metal landing stack.
    c.shapes(ly.layer(*L["Pad"])).insert(box(-p // 2, -p // 2, p // 2, p // 2))
    for name in ("Metal1", "Metal2", "Metal3", "Metal4", "Metal5", "MetalTop"):
        c.shapes(ly.layer(*L[name])).insert(box(-m // 2, -m // 2, m // 2, m // 2))
    for name in ("Via1", "Via2", "Via3", "Via4", "Via5"):
        vias(c, ly.layer(*L[name]), -m // 2 + 400, -m // 2 + 400,
             m // 2 - 400, m // 2 - 400)

    # A guard-ring marker around the pad; the actual Comp/Nwell ring and
    # device layers are the next layout step.
    c.shapes(ly.layer(*L["GUARD_RING_MK"])).insert(
        box(-s // 2, -s // 2, s // 2, s // 2))
    c.shapes(ly.layer(*L["PR_bndry"])).insert(
        box(-s // 2 - 5000, -s // 2 - 5000, s // 2 + 5000, s // 2 + 5000))

    OUT.mkdir(parents=True, exist_ok=True)
    gds = OUT / "gf180_pad_pcell.gds"
    ly.write(str(gds))
    man = {
        "generated_by": "generator/gf180_pad_pcell.py (KLayout pya)",
        "status": "pad_only_test_structure",
        "signoff": False,
        "drc_clean": False,
        "lvs": "not_run",
        "pex": "not_run",
        "parameters": {"pad_um": pad_um, "metal_um": metal_um,
                       "guard_ring_marker_um": seal_um, "via_um": 0.26,
                       "via_pitch_um": 2.0},
        "layers": {k: "%d/%d" % v for k, v in L.items()},
        "not_included": ["ESD diodes", "driver/receiver devices",
                         "schematic/netlist", "full guard ring", "pad ring"],
    }
    (OUT / "gf180_pad_pcell_manifest.json").write_text(json.dumps(man, indent=2) + "\n")
    print("wrote %s" % gds)


if __name__ == "__main__":
    main()
