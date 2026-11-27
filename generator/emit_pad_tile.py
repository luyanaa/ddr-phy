#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""One pad site: gf180_pad_core + VSSIO guard-ring strip, fully wired.

The 160 um ggNMOS clamp is already inside gf180_pad_core (MCLAMP, nf=40
w=4.0, tied PAD->VSSIO), so this tile no longer instances a second clamp.
The remaining structure is the substrate guard ring: a Comp/Pplus/Contact/
Metal1/Via1/Metal2 frame placed in the free strip on the core side of the
pad, tied to the pad's VSSIO edge port through the pad's dedicated Metal4
corridor.  The tile is what the ring instances and what DRC/LVS sign off.

Ports (labels, cell coordinates): PAD, VSSIO, VDDIO, OUT, OE_N, PU_OK, IN.

Usage: python3 generator/emit_pad_tile.py
       then sim/gf180_pad_tile.sh runs DRC + LVS.
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
    import emit_guard_ring as gr

    ly = pya.Layout()
    ly.dbu = 0.001
    tile = ly.create_cell("gf180_pad_tile")

    ly.read(str(OUT / "gf180_pad_core.gds"))
    pad = ly.cell("gf180_pad_core")
    pad_bb = pad.bbox()
    tile.insert(pya.CellInstArray(pad.cell_index(), pya.Trans(pya.Point(0, 0))))

    # Guard-ring strip on the core side of the pad.  The pad bbox top is
    # y=86.3 um; keep 0.7 um clearance and draw a 10 um wide frame.
    x0, x1 = -50000, 45000
    y0, y1 = 90000, 120000
    gr.draw_ring(ly, tile, x0, y0, x1, y1, 1000, fill=True, label="VSSIO")

    # VSSIO: pad edge port is Metal4 at x 35.0..35.6, y 71.5..72.5.
    # Strap it up to the ring's bottom Metal2 bar and via down to it.
    l46 = ly.layer(*L["Metal4"])
    l40 = ly.layer(*L["Via3"])
    l38 = ly.layer(*L["Via2"])
    l36 = ly.layer(*L["Metal2"])
    l42 = ly.layer(*L["Metal3"])
    tile.shapes(l46).insert(pya.Box(35000, 85000, 35600, y0 + 1200))
    # One via column (two columns broke V2.2a/V3.2a min spacing).
    x, y = 35000, y0 + 100
    tile.shapes(l46).insert(pya.Box(x - 500, y - 500, x + 760, y + 760))
    tile.shapes(l42).insert(pya.Box(x - 500, y - 500, x + 760, y + 760))
    tile.shapes(l40).insert(pya.Box(x, y, x + 260, y + 260))
    tile.shapes(l38).insert(pya.Box(x, y, x + 260, y + 260))
    # Metal2 landing pad on the ring's bottom bar.
    tile.shapes(l36).insert(pya.Box(34500, y0 - 400, 36500, y0 + 1400))

    ly.write(str(OUT / "gf180_pad_tile.gds"))
    print("wrote %s" % (OUT / "gf180_pad_tile.gds"))
    print("  pad bbox %s" % pad_bb.to_s())
    print("  guard ring %d..%d x %d..%d um" % (x0 / 1000, x1 / 1000, y0 / 1000, y1 / 1000))
    return 0


if __name__ == "__main__":
    sys.exit(main())
