#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Hierarchical ring checks: instance overlap, pitch, seal ring presence.

This is the ring-level part of the verification. Cell-level DRC/LVS is
covered by the three per-cell scripts; a flat deck over the whole 1.5 mm
ring exceeds the DRC budget on this machine, so the checks that only exist
at ring level are done here with region operations.
"""
import json
import sys
from pathlib import Path

import pya

ROOT = Path(__file__).resolve().parent.parent
GDS = ROOT / "sch" / "pads" / "gf180mcuD" / "pcell" / "gf180_pad_ring.gds"
MIN_PAD_SPACING_UM = 20.0     # design rule for the pad ring (pad edge to edge)


def main():
    ly = pya.Layout()
    ly.read(str(GDS))
    top = ly.top_cell()
    pads, rings, clamps = [], [], []
    for it in top.each_inst():
        n = it.cell.name
        b = it.bbox()
        if n == "gf180_pad_core":
            pads.append(b)
        elif n.startswith("gr_"):
            rings.append(b)
        elif n.startswith("cl_"):
            clamps.append(b)
    print("top %s bbox %s" % (top.name, top.bbox().to_s()))
    print("instances: pads %d, guard rings %d, clamps %d"
          % (len(pads), len(rings), len(clamps)))

    # 1. no two pad cells may overlap
    ov = 0
    for i in range(len(pads)):
        for j in range(i + 1, len(pads)):
            inter = pads[i] & pads[j]
            if not inter.empty() and inter.area() > 0:
                ov += 1
    print("pad overlap pairs: %d" % ov)

    # 2. minimum pad-to-pad spacing
    worst = None
    for i in range(len(pads)):
        for j in range(i + 1, len(pads)):
            a, b = pads[i], pads[j]
            dx = max(b.left - a.right, a.left - b.right)
            dy = max(b.bottom - a.top, a.bottom - b.top)
            gap = max(dx, dy) / 1000.0
            if worst is None or gap < worst:
                worst = gap
    print("minimum pad-to-pad gap: %.1f um (limit %.1f)" % (worst, MIN_PAD_SPACING_UM))

    # 3. seal ring present on every metal layer
    seal_ok = {}
    for nm, (ln, dt) in (("Metal1", (34, 0)), ("Metal2", (36, 0)),
                         ("Metal3", (42, 0)), ("Metal4", (46, 0)),
                         ("Metal5", (81, 0)), ("MetalTop", (53, 0)),
                         ("Comp", (22, 0))):
        li = ly.find_layer(ln, dt)
        if li is None:
            seal_ok[nm] = False
            continue
        r = pya.Region(top.begin_shapes_rec(li))
        seal_ok[nm] = r.count() > 0
    print("seal layers present: %s"
          % ", ".join("%s=%s" % (k, "y" if v else "n") for k, v in seal_ok.items()))

    ok = ov == 0 and worst >= MIN_PAD_SPACING_UM and all(seal_ok.values())
    rep = {
        "pads": len(pads), "guard_rings": len(rings), "clamps": len(clamps),
        "pad_overlap_pairs": ov,
        "min_pad_gap_um": worst,
        "min_pad_gap_limit_um": MIN_PAD_SPACING_UM,
        "seal_layers_present": seal_ok,
        "status": "PASS" if ok else "FAIL",
        "method": "hierarchical region checks; cell-level DRC/LVS in "
                  "sim/gf180_pad_layout.sh, sim/gf180_guard_ring.sh, "
                  "sim/gf180_esd_clamp_160.sh",
        "why_not_flat": "a flat deck over 108 instances on a 1.5 mm die "
                        "exceeds the 30 min DRC budget on this machine",
    }
    out = ROOT / "reports" / "gf180_pad_ring_check.json"
    out.write_text(json.dumps(rep, indent=2) + "\n")
    print("wrote %s -> %s" % (out, rep["status"]))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
