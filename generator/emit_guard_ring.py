#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Standalone guard-ring cell, used to verify the ring generator under DRC.

The pad cell has no free area for a compliant ring around the output stage
(its own Metal2 buses box it in), so the ring generator is verified as a
standalone cell first. Once the pad cell gets a dedicated ring channel the
same helper can be dropped in.

Ring construction (all widths from the GF180 DRC deck):
  Comp    1.0 um band
  Pplus   Comp + 0.16 um each side
  Contact 0.22 um squares, 0.5 um pitch (CO.2a 0.25 spacing)
  Metal1  Comp + 0.07 um each side
  Via1    0.26 um squares, 0.6 um pitch (V1.2a 0.26 spacing)
  Metal2  Comp + 0.07 um each side
"""
import sys
from pathlib import Path

import pya

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "sch" / "pads" / "gf180mcuD" / "pcell"

L = {"Comp": (22, 0), "Pplus": (31, 0), "Contact": (33, 0),
     "Metal1": (34, 0), "Via1": (35, 0), "Metal2": (36, 0)}


def frame(ly, cell, layer, x0, y0, x1, y1, w):
    l = ly.layer(*L[layer])
    cell.shapes(l).insert(pya.Box(x0, y0, x1, y0 + w))
    cell.shapes(l).insert(pya.Box(x0, y1 - w, x1, y1))
    cell.shapes(l).insert(pya.Box(x0, y0, x0 + w, y1))
    cell.shapes(l).insert(pya.Box(x1 - w, y0, x1, y1))


def contacts(ly, cell, layer, x0, y0, x1, y1, w, size, pitch):
    l = ly.layer(*L[layer])
    def row(yy):
        x = x0 + w
        while x + size <= x1 - w:
            cell.shapes(l).insert(pya.Box(x, yy, x + size, yy + size))
            x += pitch
    def col(xx):
        y = y0 + w
        while y + size <= y1 - w:
            cell.shapes(l).insert(pya.Box(xx, y, xx + size, y + size))
            y += pitch
    row(y0 + (w - size) // 2)
    row(y1 - (w + size) // 2)
    col(x0 + (w - size) // 2)
    col(x1 - (w + size) // 2)


def draw_ring(ly, cell, x0, y0, x1, y1, w=1000, fill=True, label="VSSIO"):
    """Draw a complete guard ring (Comp/Pplus/Contact/M1/Via1/M2) + fill."""
    frame(ly, cell, "Comp", x0, y0, x1, y1, w)
    frame(ly, cell, "Pplus", x0 - 160, y0 - 160, x1 + 160, y1 + 160, w + 320)
    contacts(ly, cell, "Contact", x0, y0, x1, y1, w, 220, 500)
    frame(ly, cell, "Metal1", x0 - 70, y0 - 70, x1 + 70, y1 + 70, w + 140)
    contacts(ly, cell, "Via1", x0, y0, x1, y1, w, 260, 600)
    frame(ly, cell, "Metal2", x0 - 70, y0 - 70, x1 + 70, y1 + 70, w + 140)
    if fill:
        for name, (ln, dt) in {"Comp_dummy": (22, 4), "Poly2_dummy": (30, 4),
                               "Metal1_dummy": (34, 4), "Metal2_dummy": (36, 4),
                               "Metal3_dummy": (42, 4), "Metal4_dummy": (46, 4),
                               "Metal5_dummy": (81, 4), "MetalTop_dummy": (53, 4)}.items():
            cell.shapes(ly.layer(ln, dt)).insert(
                pya.Box(x0 + 5000, y0 + 5000, x1 - 5000, y1 - 5000))
    cell.shapes(ly.layer(36, 10)).insert(
        pya.Text(label, pya.Trans(pya.Point(x0 + w // 2, y0 + w // 2))))


def main():
    ly = pya.Layout()
    ly.dbu = 0.001
    cell = ly.create_cell("gf180_guard_ring")
    x0, y0, x1, y1 = 0, 0, 60000, 40000
    w = 1000
    draw_ring(ly, cell, x0, y0, x1, y1, w)
    # Dummy fill: the die-level density rules (DCF.1a/b, PL.8, M*.4, MT.3)
    # are evaluated on the whole cell, so a ring-only cell fails them even
    # though its own geometry is clean. Fill the interior, keeping the PDK
    # dummy clearances (DCF.4 3.5 um to COMP, DM.3 2 um to metal).
    fill = {"Comp_dummy": (22, 4), "Poly2_dummy": (30, 4),
            "Metal1_dummy": (34, 4), "Metal2_dummy": (36, 4),
            "Metal3_dummy": (42, 4), "Metal4_dummy": (46, 4),
            "Metal5_dummy": (81, 4), "MetalTop_dummy": (53, 4)}
    for name, (ln, dt) in fill.items():
        cell.shapes(ly.layer(ln, dt)).insert(
            pya.Box(5000, 5000, 55000, 35000))
    cell.shapes(ly.layer(36, 10)).insert(
        pya.Text("VSSIO", pya.Trans(pya.Point(x0 + w // 2, y0 + w // 2))))
    OUT.mkdir(parents=True, exist_ok=True)
    gds = OUT / "gf180_guard_ring.gds"
    ly.write(str(gds))
    print("wrote %s" % gds)
    return 0


if __name__ == "__main__":
    sys.exit(main())
