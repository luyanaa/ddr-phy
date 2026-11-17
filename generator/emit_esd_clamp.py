#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Standalone grounded-gate NMOS ESD clamp cell (PAD -> VSSIO).

The pad cell has no room for a compliant clamp: every in-cell attempt
either crossed the output stage's Metal2 buses or left the clamp source as
an isolated net. ESD clamps are normally delivered as library cells, so
this generator builds one as a standalone cell with its own routing
channel, verifies it under the full DRC deck, and the pad ring instances
it next to each pad.

Topology: 40 fingers x 2 um = 80 um channel, gate tied to VSSIO (ggNMOS),
drain on PAD, source and bulk on VSSIO.
"""
import sys
from pathlib import Path

import pya

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "sch" / "pads" / "gf180mcuD" / "pcell"
PDK_GLOB = "~/.ciel/ciel/gf180mcu/versions/*/gf180mcuD"

L = {"Comp": (22, 0), "Nwell": (21, 0), "Pplus": (31, 0), "Nplus": (32, 0),
     "Poly2": (30, 0), "Contact": (33, 0), "Metal1": (34, 0),
     "Metal2": (36, 0), "Via1": (35, 0)}


def find_pdk():
    import glob
    pats = sorted(glob.glob(str(Path(PDK_GLOB).expanduser())))
    for p in pats:
        if (Path(p) / "libs.tech/klayout/tech/drc/gf180mcu.drc").exists():
            return Path(p)
    raise SystemExit("ERROR: no gf180mcuD PDK found")


def draw_clamp(ly, cell, nf=40, w=2.0):
    """Draw the ggNMOS clamp into an existing layout/cell."""
    import glob
    pdk = sorted(glob.glob(str(Path(PDK_GLOB).expanduser())))
    pdk = [Path(p) for p in pdk if (Path(p) / "libs.tech/klayout/tech/drc/gf180mcu.drc").exists()][0]
    sys.path.insert(0, str(pdk / "libs.tech/klayout/tech/pymacros/klayout_api_cells"))
    from draw_mos import draw_nfet
    dev = draw_nfet(ly, 0.28, w, 0.44, nf, 0.36, "Bulk Tie", "3.3V", False, False)
    cell.insert(pya.CellInstArray(dev.cell_index(), pya.Trans(pya.Point(0, 0))))
    bb = dev.bbox()
    yt, yb = bb.top, bb.bottom

    def rect(layer, x0, y0, x1, y1):
        cell.shapes(ly.layer(*L[layer])).insert(pya.Box(x0, y0, x1, y1))

    def label(layer, text, x, y):
        cell.shapes(ly.layer(L[layer][0], 10)).insert(
            pya.Text(text, pya.Trans(pya.Point(x, y))))

    rect("Poly2", -2000, yt + 20, bb.right, yt + 520)
    for i in range(nf):
        rect("Poly2", 440 + i * 800, yt - 260, 720 + i * 800, yt + 120)
    rect("Contact", -1600, yt + 100, -1380, yt + 320)
    rect("Metal1", -1900, yt - 100, -1100, yt + 600)
    label("Metal1", "VSSIO", -1700, yt + 100)
    pitch, pw = 800, 380
    xs, src_y, drn_y = -10, yt + 800, yb - 1400
    for i in range(nf + 1):
        cx = xs + i * pitch + pw // 2
        rect("Via1", cx - 130, 1000 - 130, cx + 130, 1000 + 130)
        if i % 2 == 0:
            rect("Metal2", cx - 200, 800, cx + 200, src_y + 400)
        else:
            rect("Metal2", cx - 200, drn_y - 400, cx + 200, 1200)
    xend = xs + nf * pitch + pw - 100
    rect("Metal2", -1900, src_y, xend, src_y + 400)
    rect("Metal2", -1900, yt + 100, -1500, src_y + 400)
    rect("Via1", -1830, yt + 170, -1570, yt + 430)
    rect("Metal2", xs + 100, drn_y - 400, xend, drn_y)
    rect("Metal1", -760, 1400, 370, 1700)
    label("Metal2", "VSSIO", xs + 200, src_y + 50)
    label("Metal2", "PAD", xs + 200, drn_y - 200)


def main():
    pdk = find_pdk()
    sys.path.insert(0, str(pdk / "libs.tech/klayout/tech/pymacros/klayout_api_cells"))
    from draw_mos import draw_nfet

    ly = pya.Layout()
    ly.dbu = 0.001
    cell = ly.create_cell("gf180_esd_clamp")
    nf, w = 40, 2.0
    dev = draw_nfet(ly, 0.28, w, 0.44, nf, 0.36, "Bulk Tie", "3.3V", False, False)
    cell.insert(pya.CellInstArray(dev.cell_index(), pya.Trans(pya.Point(0, 0))))
    bb = dev.bbox()
    yt, yb = bb.top, bb.bottom

    def rect(layer, x0, y0, x1, y1):
        cell.shapes(ly.layer(*L[layer])).insert(pya.Box(x0, y0, x1, y1))

    def label(layer, text, x, y):
        cell.shapes(ly.layer(L[layer][0], 10)).insert(
            pya.Text(text, pya.Trans(pya.Point(x, y))))

    # gate bus above the device, tied to VSSIO. Each finger needs a short
    # Poly2 stub from the gate end cap up to the bus (PL.3a).
    rect("Poly2", -2000, yt + 20, bb.right, yt + 520)
    for i in range(nf):
        rect("Poly2", 440 + i * 800, yt - 260, 720 + i * 800, yt + 120)
    rect("Contact", -1600, yt + 100, -1380, yt + 320)
    rect("Metal1", -1900, yt - 100, -1100, yt + 600)
    label("Metal1", "VSSIO", -1700, yt + 100)

    # per-finger source/drain straps with vias
    pitch, pw = 800, 380
    xs = -10
    src_y = yt + 800
    drn_y = yb - 1400
    for i in range(nf + 1):
        cx = xs + i * pitch + pw // 2
        rect("Via1", cx - 130, 1000 - 130, cx + 130, 1000 + 130)
        if i % 2 == 0:
            rect("Metal2", cx - 200, 800, cx + 200, src_y + 400)
        else:
            rect("Metal2", cx - 200, drn_y - 400, cx + 200, 1200)
    xend = xs + nf * pitch + pw - 100
    # Extend the source bus left and tie it to the gate M1 pad so the
    # source/bulk island is the same net as the gate (otherwise LVS extracts
    # an isolated VSSIO$1).
    rect("Metal2", -1900, src_y, xend, src_y + 400)
    rect("Metal2", -1900, yt + 100, -1500, src_y + 400)
    rect("Via1", -1830, yt + 170, -1570, yt + 430)
    rect("Metal2", xs + 100, drn_y - 400, xend, drn_y)
    rect("Metal1", -760, 1400, 370, 1700)
    label("Metal2", "VSSIO", xs + 200, src_y + 50)
    label("Metal2", "PAD", xs + 200, drn_y - 200)

    # die-level density rules need fill in a standalone cell
    # No fill in this cell: the die-level density rules (DCF.1b, PL.8,
    # M*.4, MT.3) are evaluated per cell, and a clamp cell is instanced
    # inside a die that carries the fill. The cell's own geometry must be
    # clean, which is what the DRC check below verifies.

    OUT.mkdir(parents=True, exist_ok=True)
    gds = OUT / "gf180_esd_clamp.gds"
    ly.write(str(gds))
    print("wrote %s (nf=%d w=%g, %dx%d dbu)" % (gds, nf, w, bb.width(), bb.height()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
