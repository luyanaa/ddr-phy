#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Compose the IHP130 DDR1 digital top into the QFN48 package coupon GDS.

This is a floorplan/assembly view, not a connected padring: the QFN48 coupon
has bond pads but no SSTL-2 signal routes.  The digital top is the hardened
LiteDRAM controller + DDR1 init + DDR1 PHY.
"""

import argparse
from pathlib import Path

import pya


def add_text(top, layer, text, x_um, y_um, size_um):
    t = pya.Text(text, pya.Trans(pya.Point(int(x_um * 1000), int(y_um * 1000))))
    t.size = int(size_um * 1000)
    top.shapes(layer).insert(t)


def add_outline(top, layer, box_um, width_um):
    box = pya.Box(
        int(box_um[0] * 1000), int(box_um[1] * 1000),
        int(box_um[2] * 1000), int(box_um[3] * 1000),
    )
    top.shapes(layer).insert(pya.Path([pya.Point(box.left, box.top), pya.Point(box.right, box.top),
                                       pya.Point(box.right, box.bottom), pya.Point(box.left, box.bottom),
                                       pya.Point(box.left, box.top)], int(width_um * 1000)))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--package", type=Path, default=Path("results/ihp130/package/qfn48_padring_coupon.gds"))
    ap.add_argument("--top", type=Path, default=Path("results/ihp130/ddr1_top/gds/ddr1_top.gds"))
    ap.add_argument("--output", type=Path, default=Path("results/ihp130/ddr1_qfn48_assembly.gds"))
    args = ap.parse_args()

    pkg = pya.Layout()
    pkg.read(str(args.package))
    src = pya.Layout()
    src.read(str(args.top))
    pkg_top = pkg.top_cell()

    top_cell = pkg.create_cell("ddr1_top_harden")
    top_cell.copy_tree(src.top_cell())
    b = top_cell.bbox()
    dx = -int((b.left + b.right) / 2)
    dy = -int((b.top + b.bottom) / 2)
    pkg_top.insert(pya.CellInstArray(top_cell.cell_index(), pya.Trans(pya.Point(dx, dy))))

    ann = pkg.layer(134, 0)
    top = pkg_top

    # 7 mm QFN body and the 2.4 mm die outline.
    add_outline(top, ann, (-3500, -3500, 3500, 3500), 80)
    add_outline(top, ann, (-1200, -1200, 1200, 1200), 35)
    # Pin 1 marker near W11 (top-left of the padring).
    top.shapes(ann).insert(pya.Box(-1160 * 1000, 1060 * 1000, -1100 * 1000, 1120 * 1000))
    add_text(top, ann, "1", -1250, 1075, 90)

    add_text(top, ann, "QFN48 7x7 mm", -3300, 3150, 300)
    add_text(top, ann, "2.4 mm die / 48 pads", -1100, 995, 150)
    add_text(top, ann, "LiteDRAM controller", -320, 445, 130)
    add_text(top, ann, "+ DDR1 PHY (IHP130)", -320, 375, 130)
    add_text(top, ann, "646 x 664 um digital harden", -200, -405, 100)
    add_text(top, ann, "Package coupon + digital floorplan; no padring signal routes", -3300, -3300, 110)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    pkg.write(str(args.output))
    print(f"wrote {args.output} (digital top {b.width()/1000:.1f} x {b.height()/1000:.1f} um)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
