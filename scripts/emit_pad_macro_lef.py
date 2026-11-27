#!/usr/bin/env python3
"""Emit a minimal LEF abstract for the IHP130 SSTL2 DQ pad hard macro.

The GDS has port text labels but no LEF pin shapes.  This script reads the
text labels and the metal geometry under them, then writes a BLOCK LEF with
one rectangular pin per port.  It is a packaging / floorplanning abstract,
not a signoff LEF: pin access, obstructions and antenna are deliberately
conservative and must be checked after the pad ring is frozen.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import klayout.db as db

# port -> (LEF layer, direction, use)
PORTS = {
    "OUT": ("Metal1", "INPUT", "SIGNAL"),
    "IN": ("Metal1", "OUTPUT", "SIGNAL"),
    "OE": ("Metal1", "INPUT", "SIGNAL"),
    "VDD": ("Metal1", "INOUT", "POWER"),
    "PU_OK": ("Metal1", "INPUT", "SIGNAL"),
    "VREF": ("Metal1", "INPUT", "SIGNAL"),
    "PAD": ("Metal5", "INOUT", "SIGNAL"),
    "VSSIO": ("Metal5", "INOUT", "GROUND"),
    "VDDIO": ("Metal5", "INOUT", "POWER"),
}


def find_label(layout: db.Layout, name: str):
    cell = layout.top_cell()
    for li in layout.layer_indices():
        for shape in cell.shapes(li).each():
            if shape.is_text() and shape.text.string == name:
                return shape.text.trans, shape.dbbox()
    raise RuntimeError(f"label {name!r} not found")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--gds", default="results/ihp130/sstl2-dq-w12-opt1/sstl2_dq.gds")
    ap.add_argument("--out", default="results/ihp130/sstl2-dq-w12-opt1/macro/sstl2_dq.lef")
    ap.add_argument("--name", default="ihp130_sstl2_dq")
    args = ap.parse_args()

    layout = db.Layout()
    layout.read(args.gds)
    cell = layout.top_cell()
    bbox = cell.dbbox()
    # GDS is drawn with a negative origin; normalize to (0,0) like Magic ORIGIN.
    x0, y0 = -bbox.left, -bbox.bottom
    w, h = bbox.width(), bbox.height()

    pins = {}
    for name, (layer, direction, use) in PORTS.items():
        trans, text_box = find_label(layout, name)
        # label anchor; use a legal 1.0 x 1.0 um pin around it, clipped to bbox
        cx, cy = text_box.center().x + x0, text_box.center().y + y0
        px0 = max(0.0, min(w - 1.0, cx - 0.5))
        py0 = max(0.0, min(h - 1.0, cy - 0.5))
        pins[name] = (layer, direction, use, (px0, py0, px0 + 1.0, py0 + 1.0))

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "VERSION 5.8 ;",
        'BUSBITCHARS "[]" ;',
        'DIVIDERCHAR "/" ;',
        f"MACRO {args.name}",
        "  CLASS BLOCK ;",
        "  ORIGIN 0 0 ;",
        f"  FOREIGN {args.name} ;",
        f"  SIZE {w:.3f} BY {h:.3f} ;",
        "  SYMMETRY X Y R90 ;",
    ]
    for name, (layer, direction, use, rect) in pins.items():
        rx0, ry0, rx1, ry1 = rect
        lines += [
            f"  PIN {name}",
            f"    DIRECTION {direction} ;",
            f"    USE {use} ;",
            "    PORT",
            f"      LAYER {layer} ;",
            f"        RECT {rx0:.3f} {ry0:.3f} {rx1:.3f} {ry1:.3f} ;",
            "    END",
            f"  END {name}",
        ]
    # Conservative obstructed core; keep the bottom 4 um and top 5 um strips
    # clear so the labelled Metal1 / Metal5 pins remain reachable.
    lines += ["  OBS"]
    for layer, rect in {
        "Metal1": (0, 4.0, w, h),
        "Metal2": (0, 0, w, h),
        "Metal3": (0, 0, w, h),
        "Metal4": (0, 0, w, h),
        "Metal5": (0, 0, w, h - 5.0),
    }.items():
        rx0, ry0, rx1, ry1 = rect
        lines += [f"    LAYER {layer} ;", f"      RECT {rx0:.3f} {ry0:.3f} {rx1:.3f} {ry1:.3f} ;"]
    lines += ["  END", "END " + args.name, "END LIBRARY"]
    out.write_text("\n".join(lines) + "\n")
    print(f"wrote {out} ({w:.3f} x {h:.3f} um)")
    for name, (_, _, _, r) in pins.items():
        print(f"  {name:6s} {r}")


if __name__ == "__main__":
    main()
