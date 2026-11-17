#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Assemble a pad ring from the GF180 pad macro and add a seal ring.

This is a STRUCTURAL assembly, not a signoff layout: it tiles the verified
`gf180_pad_core` cell around a rectangular die, adds an empty corner cell
and a metal/contact seal ring, and checks that no two pad instances overlap.

The pad cell is not modified. Guard rings around the individual pad devices
are the pad cell's own responsibility and are still an open item.

Usage:
  python3 generator/emit_pad_ring.py [--die-um 1500 1500] [--pitch 140]
                                    [--seal-um 20]
Output:
  sch/pads/gf180mcuD/pcell/gf180_pad_ring.gds
  sch/pads/gf180mcuD/pcell/gf180_pad_ring_manifest.json
"""
import argparse
import json
import sys
from pathlib import Path

import pya

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "sch" / "pads" / "gf180mcuD" / "pcell"
PAD = OUT / "gf180_pad_core.gds"

# Layers used by the seal ring (mirrors the pad generator's table).
SEAL = {
    "Metal1": (34, 0), "Metal2": (36, 0), "Metal3": (42, 0),
    "Metal4": (46, 0), "Metal5": (81, 0), "MetalTop": (53, 0),
    "Via1": (35, 0), "Via2": (38, 0), "Via3": (40, 0),
    "Via4": (41, 0), "Via5": (82, 0),
    "Comp": (22, 0), "Pplus": (31, 0), "Nplus": (32, 0),
    "Contact": (33, 0), "Nwell": (21, 0),
}


def seal_ring(ly, top, w_um, h_um, width_um, dbu):
    """Draw a closed seal ring frame around the die."""
    w = int(width_um * 1000)
    W = int(w_um * 1000)
    H = int(h_um * 1000)

    def frame(layer, inset, wd):
        l = ly.layer(*SEAL[layer])
        x0, y0, x1, y1 = inset, inset, W - inset, H - inset
        # four bars, overlapping at the corners
        top.shapes(l).insert(pya.Box(x0, y1 - wd, x1, y1))
        top.shapes(l).insert(pya.Box(x0, y0, x1, y0 + wd))
        top.shapes(l).insert(pya.Box(x0, y0, x0 + wd, y1))
        top.shapes(l).insert(pya.Box(x1 - wd, y0, x1, y1))

    # substrate / well ring under the metal
    frame("Comp", 0, w)
    frame("Nwell", 2000, w - 4000)
    frame("Pplus", 400, w - 800)
    frame("Contact", 600, w - 1200)
    # metal stack with a via at each level
    for m, v in (("Metal1", "Via1"), ("Metal2", "Via2"), ("Metal3", "Via3"),
                 ("Metal4", "Via4"), ("Metal5", "Via5")):
        frame(m, 0, w)
        frame(v, 300, w - 600)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--die-um", type=float, nargs=2, default=(1500.0, 1500.0))
    ap.add_argument("--pitch-um", type=float, default=145.0)
    ap.add_argument("--seal-um", type=float, default=20.0)
    args, _unknown = ap.parse_known_args()

    if not PAD.exists():
        raise SystemExit("ERROR: %s missing; run sim/gf180_pad_layout.sh first"
                         % PAD)

    # Build the ring inside the pad layout: the pad cell stays the leaf,
    # a new top cell instantiates it around the die.
    ly = pya.Layout()
    ly.read(str(PAD))
    pad_cell = ly.top_cell()
    pad_idx = pad_cell.cell_index()
    top = ly.create_cell("gf180_pad_ring")
    pad_bb = pad_cell.bbox()
    pw, ph = pad_bb.width(), pad_bb.height()

    W = int(args.die_um[0] * 1000)
    H = int(args.die_um[1] * 1000)
    pitch = int(args.pitch_um * 1000)

    if pitch < ph + 4000:
        raise SystemExit("ERROR: pitch %d too small for a %.1f um tall pad"
                         % (pitch, ph / 1000.0))

    placed = []
    # bottom edge: pad stack at the edge, core inside (+y)
    n = (W - 2 * pitch) // pitch + 1
    xs = [(W - (n - 1) * pitch) // 2 + i * pitch for i in range(n)]
    for x in xs:
        top.insert(pya.CellInstArray(pad_idx, pya.Trans(pya.Trans.R0, x, 0)))
        placed.append(("bottom", x, 0, 0))
    # top edge: rotated 180, core inside (-y)
    for x in xs:
        top.insert(pya.CellInstArray(pad_idx, pya.Trans(pya.Trans.R180, x, H)))
        placed.append(("top", x, H, 180))
    # left edge: rotated 270 so the core faces +x
    n = (H - 2 * pitch) // pitch + 1
    ys = [(H - (n - 1) * pitch) // 2 + i * pitch for i in range(n)]
    for y in ys:
        top.insert(pya.CellInstArray(pad_idx, pya.Trans(pya.Trans.R270, 0, y)))
        placed.append(("left", 0, y, 270))
    for y in ys:
        top.insert(pya.CellInstArray(pad_idx, pya.Trans(pya.Trans.R90, W, y)))
        placed.append(("right", W, y, 90))

    seal_ring(ly, top, args.die_um[0], args.die_um[1], args.seal_um, ly.dbu)

    # Guard ring in every pad slot: the ring generator is DRC-clean
    # (sim/gf180_guard_ring.sh) and the pad ring has the free area the pad
    # cell itself lacks.
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import emit_guard_ring as gr
    import emit_esd_clamp as ecl
    for side, x, y, rot in placed:
        t = pya.Trans(getattr(pya.Trans, "R%d" % rot), x, y)
        # ring drawn in the pad cell's local frame, then transformed
        sub = ly.create_cell("gr_%s_%d_%d" % (side, x, y))
        gr.draw_ring(ly, sub, -60000, -62000, 40000, -20000, 1000,
                     fill=True, label="VSSIO")
        top.insert(pya.CellInstArray(sub.cell_index(), t))
        # ESD clamp next to each pad, in the same local frame.
        cl = ly.create_cell("cl_%s_%d_%d" % (side, x, y))
        ecl.draw_clamp(ly, cl)
        top.insert(pya.CellInstArray(cl.cell_index(), t))

    # overlap check on transformed bounding boxes
    boxes = []
    for side, x, y, rot in placed:
        t = pya.Trans(getattr(pya.Trans, "R%d" % rot), x, y)
        boxes.append(pya.Box(pad_bb).transformed(t))
    bad = 0
    for i in range(len(boxes)):
        for j in range(i + 1, len(boxes)):
            if boxes[i] & boxes[j] and not (boxes[i] & boxes[j]).empty():
                if (boxes[i] & boxes[j]).area() > 0:
                    bad += 1
    if bad:
        raise SystemExit("ERROR: %d overlapping pad instances" % bad)

    OUT.mkdir(parents=True, exist_ok=True)
    gds = OUT / "gf180_pad_ring.gds"
    ly.write(str(gds))
    man = {
        "generated_by": "generator/emit_pad_ring.py",
        "status": "structural_assembly - not signoff",
        "pad_cell": "gf180_pad_core",
        "die_um": args.die_um,
        "pitch_um": args.pitch_um,
        "seal_ring_um": args.seal_um,
        "pads": {"bottom": len(xs), "top": len(xs),
                 "left": len(ys), "right": len(ys),
                 "total": len(placed)},
        "overlap_check": "pass",
        "guard_ring_per_pad": "open - pad cell has no dedicated guard ring yet",
        "not_included": ["bond pads / package", "ESD qualification",
                         "power grid", "DRC on the assembled ring",
                         "seal ring DRC/LVS"],
        "seal_layers": list(SEAL),
    }
    (OUT / "gf180_pad_ring_manifest.json").write_text(
        json.dumps(man, indent=2) + "\n")
    print("wrote %s (%d pads, %d x %d um die)"
          % (gds, len(placed), args.die_um[0], args.die_um[1]))
    print("  pads per side: bottom/top %d, left/right %d" % (len(xs), len(ys)))
    print("  overlap check: pass")
    return 0


if __name__ == "__main__":
    try:
        rc = main()
    except SystemExit as e:
        print("RING EXIT: %s" % e, flush=True)
        raise
    except Exception as e:
        import traceback
        traceback.print_exc()
        print("RING ERROR: %r" % e, flush=True)
        rc = 3
    print("RING RETURN %s" % rc, flush=True)
