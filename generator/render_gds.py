#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Headless KLayout GDS render for documentation previews."""

import argparse
from pathlib import Path

import pya

# IHP SG13G2 GDS layer map; colors are for documentation, not DRC.
SG13G2_COLORS = {
    1: 0x00A000,   # Activ
    5: 0xC00000,   # GatPoly
    6: 0x444444,   # Cont
    8: 0x1F4FFF,   # Metal1
    10: 0x00A0A0,  # Metal2
    30: 0xCC00CC,  # Metal3
    50: 0xFF8000,  # Metal4
    67: 0x008800,  # Metal5
    125: 0xDDDD00, # TopMetal1
    126: 0xDDDD00, # TopMetal2
    133: 0x888888, # Passivation
}


def apply_sg13g2_colors(view):
    it = view.begin_layers()
    while not it.at_end():
        lp = it.current().dup()
        layer, datatype = lp.source_layer, lp.source_datatype
        if datatype == 0 and layer in SG13G2_COLORS:
            lp.visible = True
            lp.fill_color = SG13G2_COLORS[layer]
            lp.frame_color = SG13G2_COLORS[layer]
            lp.width = 1
            lp.transparent = False
        elif layer == 134:
            lp.visible = True
            lp.fill_color = 0xFF9900
            lp.frame_color = 0xFF9900
        else:
            lp.visible = False
        view.set_layer_properties(it, lp)
        it.next()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--gds", type=Path, required=True)
    ap.add_argument("--png", type=Path, required=True)
    ap.add_argument("--width", type=int, default=1800)
    ap.add_argument("--height", type=int, default=1800)
    ap.add_argument("--tech", choices=["none", "sg13g2"], default="none",
                    help="apply a documentation layer-color preset")
    args = ap.parse_args()
    view = pya.LayoutView()
    view.load_layout(str(args.gds), 0)
    if args.tech == "sg13g2":
        apply_sg13g2_colors(view)
    view.max_hier()
    view.zoom_fit()
    view.set_config("background-color", "#ffffff")
    args.png.parent.mkdir(parents=True, exist_ok=True)
    view.save_image(str(args.png), args.width, args.height)
    print(f"wrote {args.png}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
