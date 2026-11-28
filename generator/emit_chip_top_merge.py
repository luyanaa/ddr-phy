#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Merge the routed chip-top GDS with power distribution and LVS labels.

Run from the repository root with the LibreLane KLayout environment:
    klayout -b -r generator/emit_chip_top_merge.py

The stream-out pad master is normalized to the positive-coordinate LEF frame
before it is merged.  Its GDS content was authored around the pad center, so
this script keeps the original site transform (also pad-center based) and
converts normalized LEF pin coordinates into that local frame explicitly.
"""
import os

import pya

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
PCELL = os.path.join(ROOT, "sch", "pads", "gf180mcuD", "pcell")
BASE_GDS = os.environ.get("CHIPTOP_BASE_GDS", "/tmp/chiptop_base.gds")
PAD_GDS = os.path.join(PCELL, "gf180_pad_tile.gds")
PAD_NORM_GDS = os.path.join(PCELL, "gf180_pad_tile_norm.gds")
OUT_GDS = os.path.join(PCELL, "gf180mcu_sdram_chip_top.gds")

UM = 1000  # pad GDS database unit is 0.001 um
PAD_CENTER_OFFSET = (66.5, 65.0)  # LEF origin to original GDS pad-center frame
DIE = 1800.0

METAL = {
    "Metal1": (34, 0), "Metal2": (36, 0), "Metal3": (42, 0),
    "Metal4": (46, 0), "Metal5": (81, 0),
}
VIA = {"Via1": (35, 0), "Via2": (38, 0), "Via3": (40, 0)}
LABEL = {
    "Metal1": (34, 10), "Metal2": (36, 10), "Metal3": (42, 10),
    "Metal4": (46, 10), "Metal5": (81, 10),
}

# Pad assignments from generator/emit_chip_top.py.  Sites 0 and 8 are the
# two unpopulated supply-pad locations; the other 30 sites carry signals.
ASSIGN = {
    0: "VDDIO", 1: "cmd_o[11]", 2: "cmd_o[12]", 3: "cmd_o[13]",
    4: "pad_ck", 5: "cmd_o[14]", 6: "cmd_o[15]", 7: "cmd_o[16]",
    8: "VSSIO", 9: "dq[0]", 10: "dq[1]", 11: "dq[2]", 12: "dq[3]",
    13: "dq[4]", 14: "dq[5]", 15: "dq[6]", 16: "dq[7]",
    17: "cmd_o[20]", 18: "cmd_o[19]", 19: "cmd_o[18]",
    20: "cmd_o[17]", 21: "cmd_o[10]", 22: "cmd_o[9]",
    23: "cmd_o[8]", 24: "cmd_o[7]", 25: "cmd_o[6]",
    26: "cmd_o[5]", 27: "cmd_o[4]", 28: "cmd_o[3]",
    29: "cmd_o[2]", 30: "cmd_o[1]", 31: "cmd_o[0]",
}

SITES = ([dict(index=i, side="B") for i in range(9)] +
         [dict(index=i, side="R") for i in range(9, 16)] +
         [dict(index=i, side="T") for i in range(16, 25)] +
         [dict(index=i, side="L") for i in range(25, 32)])


def dbu(value):
    return int(round(value * UM))


def site_transform(site, layout):
    """Pad-center transform copied from emit_chip_top.py."""
    index = site["index"]
    side = site["side"]
    if side == "B":
        rot, tx, ty = pya.Trans.R0, 140.0 + 190.0 * index, 90.0
    elif side == "R":
        j = index - 9
        rot, tx, ty = pya.Trans.R90, 1710.0, 281.66 + 190.0 * j
    elif side == "T":
        i = index - 16
        rot, tx, ty = pya.Trans.R180, 1660.0 - 190.0 * i, 1710.0
    else:
        j = index - 25
        rot, tx, ty = pya.Trans.R270, 90.0, 1421.66 - 190.0 * j
    return pya.Trans(rot, dbu(tx), dbu(ty))


def normalize_pad_gds():
    """Shift the pad master into the normalized LEF frame in place."""
    ly = pya.Layout()
    ly.read(PAD_GDS)
    raw = ly.cell("gf180_pad_tile")
    if raw is None:
        raise RuntimeError("gf180_pad_tile cell missing from " + PAD_GDS)
    bb = raw.bbox()
    dx, dy = -bb.left, -bb.bottom
    expected = (dbu(66.5), dbu(65.0))
    if (dx, dy) != expected:
        raise RuntimeError("unexpected raw pad GDS origin offset: %s (expected %s)" %
                           ((dx, dy), expected))
    # Transform this cell's shapes and instance placements, not a wrapper
    # instance: the macro's gf180_pad_core hierarchy must remain unchanged for LVS.
    raw.transform(pya.Trans(pya.Point(dx, dy)))
    nbb = raw.bbox()
    if (nbb.left, nbb.bottom) != (0, 0):
        raise RuntimeError("normalized pad bbox does not start at (0,0): %s" %
                           nbb.to_s())
    ly.write(PAD_NORM_GDS)
    print("normalized pad GDS %s: raw bbox %s, shift (%g,%g) um, result %s" %
          (PAD_NORM_GDS, bb.to_s(), dx / float(UM), dy / float(UM),
           nbb.to_s()))


def layer(layout, name):
    num, datatype = METAL[name]
    return layout.layer(num, datatype)


def label_layer(layout, name):
    num, datatype = LABEL[name]
    return layout.layer(num, datatype)


def rect(cell, layout, layer_name, x0, y0, x1, y1):
    cell.shapes(layer(layout, layer_name)).insert(
        pya.Box(dbu(x0), dbu(y0), dbu(x1), dbu(y1)))


def text(cell, layout, layer_name, value, x, y):
    cell.shapes(label_layer(layout, layer_name)).insert(
        pya.Text(value, pya.Trans(pya.Point(dbu(x), dbu(y)))))


def wire_segment(cell, layout, layer_name, a, b, width):
    x0, y0 = a
    x1, y1 = b
    half = width / 2.0
    if abs(x0 - x1) < 1e-9:
        rect(cell, layout, layer_name, x0 - half, min(y0, y1),
             x0 + half, max(y0, y1))
    elif abs(y0 - y1) < 1e-9:
        rect(cell, layout, layer_name, min(x0, x1), y0 - half,
             max(x0, x1), y0 + half)
    else:
        raise RuntimeError("non-Manhattan power segment: %r -> %r" % (a, b))


def ring_region(layout, segments, width):
    region = pya.Region()
    for x0, y0, x1, y1 in segments:
        half = width / 2.0
        if abs(x0 - x1) < 1e-9:
            region.insert(pya.Box(dbu(x0 - half), dbu(min(y0, y1)),
                                  dbu(x0 + half), dbu(max(y0, y1))))
        else:
            region.insert(pya.Box(dbu(min(x0, x1)), dbu(y0 - half),
                                  dbu(max(x0, x1)), dbu(y0 + half)))
    region.merge()
    return region


def cell_region(cell, layout, layer_index):
    region = pya.Region()
    li = layout.find_layer(*layer_index)
    if li is None or li < 0:
        return region
    it = cell.begin_shapes_rec(li)
    while not it.at_end():
        shape = it.shape()
        if not shape.is_text():
            try:
                region.insert(shape.polygon.transformed(it.trans()))
            except Exception:
                pass
        it.next()
    region.merge()
    return region


def pin_box(site, layout, coords):
    """Transform positive LEF coordinates through the pad-center frame.

    The base GDS is normalized by (+66.5,+65) before stream-out.  The copied
    site transform is the pad center, not the LEF origin, so subtract that
    local offset before applying it.  This is equivalent to transforming the
    positive LEF pin from the actual DEF macro origin.
    """
    x0, y0, x1, y1 = coords
    ox, oy = PAD_CENTER_OFFSET
    local = pya.Box(dbu(x0 - ox), dbu(y0 - oy),
                    dbu(x1 - ox), dbu(y1 - oy))
    return local.transformed(site_transform(site, layout))


def point_region(point):
    return pya.Region(pya.Box(point.x - 1, point.y - 1,
                              point.x + 1, point.y + 1))


def verify_pad_pin_geometry(top, layout, sites):
    """Prove the normalized master exposes every supply pin at its LEF site."""
    m3 = cell_region(top, layout, METAL["Metal3"])
    m4 = cell_region(top, layout, METAL["Metal4"])
    m2 = cell_region(top, layout, METAL["Metal2"])
    pads = [s for s in sites if s["index"] not in (0, 8)]
    for site in pads:
        # Pin access rectangles from gf180_pad_tile.lef.
        vddio = pin_box(site, layout, (8.6, 0.0, 9.0, 25.4))
        vssio = pin_box(site, layout, (101.5, 74.5, 102.1, 156.2))
        if (m3 & pya.Region(vddio)).area() == 0:
            raise RuntimeError("normalized GDS has no VDDIO/M3 pin at pad site %d" %
                               site["index"])
        if (m4 & pya.Region(vssio)).area() == 0:
            raise RuntimeError("normalized GDS has no VSSIO/M4 pin at pad site %d" %
                               site["index"])
        center = site_transform(site, layout).disp
        if (m2 & point_region(center)).area() == 0:
            raise RuntimeError("normalized GDS has no signal pad M2 at site %d" %
                               site["index"])
    print("verified normalized GDS: M2 signal pad + M3 VDDIO + M4 VSSIO at %d sites" %
          len(pads))


def draw_pad_power(top, layout, sites):
    # Move the right M3 trunk outside the routed-wire endpoints; local taps
    # connect it to each right-edge pad's VDDIO strap.
    vdd_segments = [
        (30.0, 30.0, 1780.0, 30.0),
        (30.0, 1765.0, 1780.0, 1765.0),
        (30.0, 30.0, 30.0, 1765.0),
        (1780.0, 30.0, 1780.0, 1765.0),
    ]
    for site in sites:
        if site["side"] != "R" or site["index"] in (0, 8):
            continue
        strap = pin_box(site, layout, (8.6, 0.0, 9.0, 25.4))
        y = (strap.bottom + strap.top) / (2.0 * UM)
        vdd_segments.append((strap.left / float(UM), y, 1780.0, y))
    # The top VSSIO strap runs through each top-edge pad's M4 power pin. Split
    # it around the routed M4 crossing near x=761.32 instead of extending taps
    # through the pad interiors.
    vss_segments = [
        (38.0, 134.0, 1762.0, 134.0),
        (38.0, 1666.0, 760.0, 1666.0),
        (762.5, 1666.0, 1762.0, 1666.0),
        (134.0, 134.0, 134.0, 1666.0),
        (1666.0, 134.0, 1666.0, 1666.0),
    ]
    for a, b, c, d in vdd_segments:
        wire_segment(top, layout, "Metal3", (a, b), (c, d), 4.0)
    for a, b, c, d in vss_segments:
        wire_segment(top, layout, "Metal4", (a, b), (c, d), 4.0)

    vdd_ring = ring_region(layout, vdd_segments, 4.0)
    vss_ring = ring_region(layout, vss_segments, 4.0)
    pads = [s for s in sites if s["index"] not in (0, 8)]
    for site in pads:
        vddio = pya.Region(pin_box(site, layout, (8.6, 0.0, 9.0, 25.4)))
        vssio = pya.Region(pin_box(site, layout, (101.5, 74.5, 102.1, 156.2)))
        if (vdd_ring & vddio).area() == 0:
            raise RuntimeError("VDDIO ring misses pad site %d" % site["index"])
        if (vss_ring & vssio).area() == 0:
            raise RuntimeError("VSSIO ring misses pad site %d" % site["index"])
    print("verified perimeter power mesh intersections: VDDIO %d/%d, VSSIO %d/%d" %
          (len(pads), len(pads), len(pads), len(pads)))
    text(top, layout, "Metal3", "VDDIO", 50.0, 30.0)
    text(top, layout, "Metal4", "VSSIO", 150.0, 134.0)


def draw_via_stack(top, layout, x, y):
    """Via stack from inverter M1 power pin to Metal4 with legal enclosures."""
    via_size = 0.26
    enclosure = 0.40
    half_via = via_size / 2.0
    half_enc = enclosure / 2.0
    for name in ("Metal1", "Metal2", "Metal3", "Metal4"):
        rect(top, layout, name, x - half_enc, y - half_enc,
             x + half_enc, y + half_enc)
    for name in ("Via1", "Via2", "Via3"):
        ln, dt = VIA[name]
        top.shapes(layout.layer(ln, dt)).insert(
            pya.Box(dbu(x - half_via), dbu(y - half_via),
                    dbu(x + half_via), dbu(y + half_via)))


def draw_core_power(top, layout):
    """Connect east core power straps to the placed inverter's M1 rails."""
    # Exact FIXED origins from chiptop_routed.def (DEF units 2000/um).
    core_x, core_y = 762.985, 754.025
    inv_x, inv_y = 1042.020, 985.995

    core_top_strap_y = core_y + 274.7
    power_routes = (
        # net, core strap x (local), inverter M1 tap (local x/y), route y
        ("VDD", 176.64, 0.30, 3.92, 1050.0),
        ("VSS", 179.94, 1.12, 0.00, 1055.0),
    )
    for net, core_local_x, inv_local_x, inv_local_y, track_y in power_routes:
        cx = core_x + core_local_x
        iy = inv_y + inv_local_y
        ix = inv_x + inv_local_x
        # The core M4 straps end at local y=274.7.  The 0.2 um overlap makes
        # the continuation unambiguously touch the existing stripe.
        wire_segment(top, layout, "Metal4", (cx, core_top_strap_y - 0.2),
                     (cx, track_y), 0.44)
        wire_segment(top, layout, "Metal4", (cx, track_y), (ix, track_y), 0.44)
        wire_segment(top, layout, "Metal4", (ix, track_y), (ix, iy), 0.44)
        draw_via_stack(top, layout, ix, iy)
        # Keep top-level port labels on the actual core strap and on the
        # power distribution net; the inverter's own VDD/VSS/VNW/VPW labels
        # remain in its standard-cell master.
        text(top, layout, "Metal4", net,
             cx, core_y + 145.04)
    print("connected core east M4 straps to inverter M1 rails: VDD, VSS")


def add_top_labels(top, layout, sites):
    labeled = 0
    for site in sites:
        assignment = ASSIGN[site["index"]]
        if assignment in ("VDDIO", "VSSIO"):
            continue
        if assignment == "pad_ck":
            net = "pad_ck"
        elif assignment.startswith("cmd_o"):
            net = "pad_cmd" + assignment[len("cmd_o"):]
        else:
            net = "pad_dq" + assignment[len("dq"):]
        point = site_transform(site, layout).disp
        text(top, layout, "Metal2", net,
             point.x / float(UM), point.y / float(UM))
        labeled += 1
    if labeled != 30:
        raise RuntimeError("expected 30 signal pad labels, got %d" % labeled)
    print("added Metal2 labels for %d signal top-level ports" % labeled)


def main():
    normalize_pad_gds()
    normalize_only = str(globals().get("normalize_only", "false")).lower()
    if normalize_only in ("1", "true", "yes"):
        return

    if not os.path.isfile(BASE_GDS):
        raise RuntimeError("base routed GDS missing: %s" % BASE_GDS)
    ly = pya.Layout()
    ly.read(BASE_GDS)
    top = ly.cell("sdram_chip_top_pnr") or ly.top_cell()
    if top is None:
        raise RuntimeError("base GDS has no top cell")
    top.name = "gf180mcu_sdram_chip_top"
    ly.dbu = 0.001

    # Validate the actual merged pad GDS frame before adding any overlay.
    verify_pad_pin_geometry(top, ly, SITES)
    add_top_labels(top, ly, SITES)
    draw_pad_power(top, ly, SITES)
    draw_core_power(top, ly)

    os.makedirs(os.path.dirname(OUT_GDS), exist_ok=True)
    ly.write(OUT_GDS)
    print("wrote", OUT_GDS)


main()
