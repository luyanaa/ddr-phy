#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Generate a pad-only QFN bondplan coupon die (QFN40 or QFN48 study).

IHP SG13G2 layer map:
  9/0    Passiv openings (bondpad detection)
  134/0  TopMetal2 pad metal
  134/25 TopMetal2 text labels (pad names)

This is a package/padring geometry witness, not a chip: no IO cells, no core.
"""
import argparse
import pya


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--output", required=True)
    ap.add_argument("--cell-name", default="qfn_padring_coupon")
    ap.add_argument("--pads-per-side", type=int, default=10)
    ap.add_argument("--die-um", type=float, default=2000.0)
    ap.add_argument("--edge-inset-um", type=float, default=287.0)
    ap.add_argument("--pitch-um", type=float, default=114.0)
    ap.add_argument("--pad-um", type=float, default=70.0)
    args = ap.parse_args()

    n = args.pads_per_side
    ly = pya.Layout()
    ly.dbu = 0.001  # 1 nm
    cell = ly.create_cell(args.cell_name)
    l_pass = ly.layer(9, 0)
    l_tm2 = ly.layer(134, 0)
    l_text = ly.layer(134, 25)
    l_outline = ly.layer(0, 0)

    die = args.die_um
    inset = args.edge_inset_um
    pitch = args.pitch_um
    pad = args.pad_um
    cell.shapes(l_outline).insert(pya.DBox(-die / 2, -die / 2, die / 2, die / 2))

    for side in ("W", "S", "E", "N"):
        for i in range(n):
            off = (i - (n - 1) / 2) * pitch
            if side == "W":
                x, y = -die / 2 + inset, off
            elif side == "S":
                x, y = off, -die / 2 + inset
            elif side == "E":
                x, y = die / 2 - inset, off
            else:
                x, y = off, die / 2 - inset
            box = pya.DBox(x - pad / 2, y - pad / 2, x + pad / 2, y + pad / 2)
            cell.shapes(l_pass).insert(box)
            cell.shapes(l_tm2).insert(box)
            cell.shapes(l_text).insert(pya.DText(f"{side}{i}", x, y))

    ly.write(args.output)
    print(f"wrote {args.output}: {cell.bbox()} pads={4*n} dbu={ly.dbu}")


if __name__ == "__main__":
    main()
