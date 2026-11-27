#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Assemble a pad ring from the verified `gf180_pad_tile` and add a seal ring.

The tile already contains the pad macro, its internal 160 um ggNMOS clamp,
the Metal4 VSSIO edge port and the VSSIO guard-ring strip.  It is the unit
that passed full DRC (0 violations) and LVS (netlists match) in
reports/gf180_pad_tile_*.log, so the ring only has to place it, keep the
tiles inside the seal ring and prove the ring-level geometry.

This is still a STRUCTURAL assembly: bond pads / package, the core PDN,
chip-level DRC and LVS are not included here.

Usage:
  python3 generator/emit_pad_ring.py --die-um 1600 1600 --pitch-um 190
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
TILE = OUT / "gf180_pad_tile.gds"

SEAL = {
    "Metal1": (34, 0), "Metal2": (36, 0), "Metal3": (42, 0),
    "Metal4": (46, 0), "Metal5": (81, 0), "MetalTop": (53, 0),
    "Via1": (35, 0), "Via2": (38, 0), "Via3": (40, 0),
    "Via4": (41, 0), "Via5": (82, 0),
    "Comp": (22, 0), "Pplus": (31, 0), "Nplus": (32, 0),
    "Contact": (33, 0), "Nwell": (21, 0),
}


def seal_ring(ly, top, w_um, h_um, width_um):
    w = int(width_um * 1000)
    W = int(w_um * 1000)
    H = int(h_um * 1000)

    def frame(layer, inset, wd):
        l = ly.layer(*SEAL[layer])
        x0, y0, x1, y1 = inset, inset, W - inset, H - inset
        top.shapes(l).insert(pya.Box(x0, y1 - wd, x1, y1))
        top.shapes(l).insert(pya.Box(x0, y0, x1, y0 + wd))
        top.shapes(l).insert(pya.Box(x0, y0, x0 + wd, y1))
        top.shapes(l).insert(pya.Box(x1 - wd, y0, x1, y1))

    frame("Comp", 0, w)
    frame("Nwell", 2000, w - 4000)
    frame("Pplus", 400, w - 800)
    frame("Contact", 600, w - 1200)
    for m, v in (("Metal1", "Via1"), ("Metal2", "Via2"), ("Metal3", "Via3"),
                 ("Metal4", "Via4"), ("Metal5", "Via5")):
        frame(m, 0, w)
        frame(v, 300, w - 600)
    frame("MetalTop", 0, w)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--die-um", type=float, nargs=2, default=(1800.0, 1800.0))
    ap.add_argument("--pitch-um", type=float, default=190.0)
    ap.add_argument("--seal-um", type=float, default=0.0,
                    help="0 = no seal ring; a chip-level seal is added at assembly")
    ap.add_argument("--margin-um", type=float, default=25.0,
                    help="pad-tile-to-die-edge clearance (seal + DRC)")
    args, _unknown = ap.parse_known_args()

    if not TILE.exists():
        raise SystemExit("ERROR: %s missing; run generator/emit_pad_tile.py first"
                         % TILE)

    ly = pya.Layout()
    ly.read(str(TILE))
    tile_cell = ly.top_cell()
    tile_idx = tile_cell.cell_index()
    top = ly.create_cell("gf180_pad_ring")
    bb = tile_cell.bbox()
    pw, ph = bb.width(), bb.height()

    W = int(args.die_um[0] * 1000)
    H = int(args.die_um[1] * 1000)
    pitch = int(args.pitch_um * 1000)
    margin = int(args.margin_um * 1000)

    if pitch < ph + 4000:
        raise SystemExit("ERROR: pitch %d too small for a %.1f um tall tile"
                         % (pitch, ph / 1000.0))

    # Bottom/top rows run the full width.  The side columns must start above
    # the bottom row and stop below the top row, because every tile bbox is
    # 185 um tall (the inward VSSIO guard strip) while the pitch is 190 um.
    n_x = int((W - 2 * margin) // pitch)
    xs = [W // 2 + int((i - (n_x - 1) / 2) * pitch) for i in range(n_x)]

    y_bot = margin - bb.bottom
    bottom_top = y_bot + bb.top
    y_top = H - margin + bb.bottom
    top_bottom = y_top + bb.bottom
    # R270/R90 side tiles map local +x to -y, so their bbox spans
    # [y0 + bb.left, y0 - bb.left] in y; clear the rows with that extent.
    y_lo = bottom_top - bb.left + 5000       # 5 um corner gap (DCF.4/DPF.4)
    y_hi = top_bottom + bb.left - 5000       # 5 um corner gap
    n_y = int((y_hi - y_lo) // pitch) + 1
    if n_y < 2:
        raise SystemExit("ERROR: no room for side-column tiles")
    ys = [y_lo + i * pitch for i in range(n_y)]

    placed = []
    for x in xs:
        top.insert(pya.CellInstArray(tile_idx, pya.Trans(pya.Trans.R0, x, y_bot)))
        placed.append(("bottom", x, y_bot, 0))
    for x in xs:
        top.insert(pya.CellInstArray(tile_idx, pya.Trans(pya.Trans.R180, x, y_top)))
        placed.append(("top", x, y_top, 180))
    x_left = margin - bb.bottom
    for y in ys:
        top.insert(pya.CellInstArray(tile_idx, pya.Trans(pya.Trans.R270, x_left, y)))
        placed.append(("left", x_left, y, 270))
    x_right = W - margin + bb.bottom
    for y in ys:
        top.insert(pya.CellInstArray(tile_idx, pya.Trans(pya.Trans.R90, x_right, y)))
        placed.append(("right", x_right, y, 90))

    if args.seal_um > 0:
        seal_ring(ly, top, args.die_um[0], args.die_um[1], args.seal_um)

    boxes = []
    for side, x, y, rot in placed:
        t = pya.Trans(getattr(pya.Trans, "R%d" % rot), x, y)
        boxes.append(pya.Box(bb).transformed(t))
    bad = 0
    for i in range(len(boxes)):
        for j in range(i + 1, len(boxes)):
            inter = boxes[i] & boxes[j]
            if not inter.empty() and inter.area() > 0:
                bad += 1
    if bad:
        raise SystemExit("ERROR: %d overlapping pad tiles" % bad)

    # Every tile must stay inside the seal ring (no tile may touch the die
    # edge where the seal ring lives).
    outside = 0
    for b in boxes:
        if b.left < margin - 1000 or b.bottom < margin - 1000 or \
           b.right > W - margin + 1000 or b.top > H - margin + 1000:
            outside += 1
    if outside:
        raise SystemExit("ERROR: %d tiles outside the seal keep-out" % outside)

    OUT.mkdir(parents=True, exist_ok=True)
    gds = OUT / "gf180_pad_ring.gds"
    ly.write(str(gds))
    man = {
        "generated_by": "generator/emit_pad_ring.py",
        "status": "structural_assembly - not signoff",
        "pad_cell": "gf180_pad_tile (pad + clamp + guard ring + edge ports)",
        "die_um": args.die_um,
        "pitch_um": args.pitch_um,
        "seal_ring_um": args.seal_um,
        "density_note": "die-level density rules are only meaningful with the "
                        "core and chip fill; run DRC with decks=all,-density",
        "margin_um": args.margin_um,
        "tile_bbox_um": [bb.left / 1000, bb.bottom / 1000,
                         bb.right / 1000, bb.top / 1000],
        "pads": {"bottom": n_x, "top": n_x, "left": n_y, "right": n_y,
                 "total": len(placed)},
        "overlap_check": "pass",
        "inside_seal_check": "pass",
        "tile_evidence": {
            "drc": "reports/gf180_pad_tile_drc.log (0 violations, flat)",
            "lvs": "reports/gf180_pad_tile_lvs.log (Netlists match)",
        },
        "not_included": ["bond pads / package", "ESD qualification (TLP/HBM)",
                         "chip-level PDN", "flat DRC on the assembled ring",
                         "chip-level LVS against the core harden"],
        "seal_layers": list(SEAL),
    }
    (OUT / "gf180_pad_ring_manifest.json").write_text(
        json.dumps(man, indent=2) + "\n")
    print("wrote %s (%d tiles, %d x %d um die)"
          % (gds, len(placed), args.die_um[0], args.die_um[1]))
    print("  tiles per side: bottom/top %d, left/right %d" % (n_x, n_y))
    print("  overlap / inside-seal checks: pass")
    return 0


if __name__ == "__main__":
    sys.exit(main())
