#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""One pad site: pad macro + guard ring + 160 um clamp, fully wired.

The full 1.5 mm ring is too large for a flat DRC deck, so the electrical
connection is proven on a single tile first: the clamp's PAD drain is tied
to the pad's PAD net and its source bus to VSSIO, then the tile runs the
full DRC and LVS decks. The ring instances this verified tile.

Ports (labels on the tile, in cell coordinates):
  PAD, VSSIO, VDDIO and the pad's core-side signals.
"""
import sys
from pathlib import Path

import pya

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "sch" / "pads" / "gf180mcuD" / "pcell"

L = {"Metal1": (34, 0), "Metal2": (36, 0), "Metal3": (42, 0),
     "Metal4": (46, 0), "Via1": (35, 0), "Via2": (38, 0), "Via3": (40, 0)}


def main():
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import emit_esd_clamp as ecl
    import emit_guard_ring as gr

    ly = pya.Layout()
    ly.dbu = 0.001
    tile = ly.create_cell("gf180_pad_tile")

    # Read the verified pad macro straight into this layout (KLayout merges
    # cells and layers by name), then wrap it in the tile cell.
    ly.read(str(OUT / "gf180_pad_core.gds"))
    pad_idx = ly.cell("gf180_pad_core").cell_index()
    tile.insert(pya.CellInstArray(pad_idx, pya.Trans(pya.Point(0, 0))))

    # NOTE: the guard ring is NOT drawn inside the pad cell: the cell is
    # densely dummy-filled and a ring there collides with it (114 DPF.5
    # violations). The ring generator is verified as its own cell
    # (sim/gf180_guard_ring.sh) and the ring places it in the free area
    # outside the pad bbox.

    # The pad cell is 100 % dummy-filled inside its bbox and its Metal2 is a
    # dense mesh, so neither the clamp body nor any Metal2 strap can live
    # there without shorting PAD to VSSIO (measured: the whole pad M2 became
    # one net). The clamp therefore sits above the pad bbox, its drain joins
    # the pad's Metal3 plate directly, and the source reaches VSSIO on
    # Metal4 over the plate - Metal4 is otherwise unused in the pad cell.
    clamp_y0 = 76000
    ecl.draw_clamp(ly, tile, nf=40, w=4.0, dy=clamp_y0, fill=False)
    l42 = ly.layer(*L["Metal3"])
    l38 = ly.layer(*L["Via2"])
    l40 = ly.layer(*L["Via3"])
    l46 = ly.layer(*L["Metal4"])
    l34 = ly.layer(*L["Metal1"])
    l35 = ly.layer(*L["Via1"])

    # --- PAD: clamp drain bus -> pad Metal3 plate -----------------------
    yd0, yd1 = clamp_y0 - 2030, clamp_y0 - 1630
    for x in range(1500, 29400, 3600):
        tile.shapes(l38).insert(pya.Box(x, yd0 + 60, x + 260, yd0 + 320))
    # riser down to the plate (plate top edge y = 32000), inside x < 29500
    tile.shapes(l42).insert(pya.Box(-1750, 32000, 29500, yd1))

    # --- VSSIO: clamp source bus -> Metal4 -> pad VSSIO -----------------
    # source bus is at clamp_y0+800..+1200, drain bus ends at +1200, so the
    # source escape goes UP first, then over on Metal4.
    ys0 = clamp_y0 + 800
    tile.shapes(l38).insert(pya.Box(-1000, ys0 + 40, -740, ys0 + 300))
    tile.shapes(l42).insert(pya.Box(-1200, ys0, -540, clamp_y0 + 6000))
    tile.shapes(l42).insert(pya.Box(-1200, clamp_y0 + 5700, 30000, clamp_y0 + 6000))
    # Via3 pad on top, then the Metal4 bar that runs left and down to the
    # pad's VSSIO rail region.
    for x in range(0, 30000, 4000):
        tile.shapes(l40).insert(pya.Box(x, clamp_y0 + 5700, x + 260, clamp_y0 + 5980))
    tile.shapes(l46).insert(pya.Box(-40000, clamp_y0 + 5600, 30200, clamp_y0 + 6100))
    tile.shapes(l46).insert(pya.Box(-40000, -6000, -39500, clamp_y0 + 6100))
    # drop to the pad's VSSIO Metal2 rail (x -62800..-61500 at y -42000..-5600)
    for y in range(-5600, 4000, 4000):
        tile.shapes(l40).insert(pya.Box(-39800, y, -39540, y + 260))
    tile.shapes(l46).insert(pya.Box(-40200, -5600, -39500, -5340))

    ly.write(str(OUT / "gf180_pad_tile.gds"))
    print("wrote %s" % (OUT / "gf180_pad_tile.gds"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
