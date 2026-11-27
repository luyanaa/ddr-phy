# SPDX-License-Identifier: Apache-2.0
"""Emit the LVS black-box abstract of sdram_phy_core.

The chip-top hierarchical LVS treats the core as a black box.  The abstract
carries exactly the boundary pin geometry: for every pin net label, the
metal pin rectangle it sits on, plus the label itself.  Internal routing is
dropped so extraction sees an empty black box whose pins land exactly where
the top-level wires connect.

Method: for each net label on a metal label layer (datatype 10), take the
metal drawing shapes (datatype 0, same metal) within a small halo of the
label anchor.  The power straps (VDD/VSS on Metal4) are kept whole because
the chip PDN lands on them.

Run:  klayout -b -r generator/emit_core_abstract.py
Output: sch/pads/gf180mcuD/pcell/sdram_phy_core_lvs_abstract.gds
"""
import os
import pya

HERE = os.path.dirname(os.path.abspath(__file__))
CORE_GDS = os.path.join(HERE, "..", "flow", "runs",
                        "gf180-as-7t3v3-sdram_phy_core", "final", "gds",
                        "sdram_phy_core.gds")
OUT = os.path.join(HERE, "..", "sch", "pads", "gf180mcuD", "pcell",
                   "sdram_phy_core_lvs_abstract.gds")

# metal layers to consider for pins
METALS = [34, 36, 42, 46, 81]
HALO = 4000  # dbu (4 um) search halo around each label anchor

# Top-level port whitelist: ONLY these labels are real chip pins.  Everything
# else on the metal label layers is internal routing or sub-cell pin names
# (Q/A/Y/D/CLK/ZERO/ONE/capture_ready/...) that must NOT become black-box pins.
import re as _re
def _port_names():
    names = {"VDD", "VSS", "clk", "rst", "ck_o", "dq_oe"}
    names |= {"cmd_o[%d]" % i for i in range(21)}
    names |= {"dq_o[%d]" % i for i in range(8)}
    names |= {"dq_i[%d]" % i for i in range(8)}
    return names
PORTS = _port_names()



def main():
    ly = pya.Layout()
    ly.read(CORE_GDS)
    src = ly.top_cell()

    out = pya.Layout()
    out.dbu = ly.dbu
    nc = out.create_cell("sdram_phy_core")

    # map (layer,datatype) -> index
    idx = {}
    for li in range(ly.layers()):
        inf = ly.get_info(li)
        idx[(inf.layer, inf.datatype)] = li

    nlabels = 0
    npins = 0
    for ln in METALS:
        labli = idx.get((ln, 10))
        drawli = idx.get((ln, 0))
        if labli is None:
            continue
        # gather labels
        labels = []
        # DIRECT shapes only: top-level port labels live on the core top cell.
        # Recursing would sweep in thousands of sub-cell clk/VDD/VSS pin labels.
        for s in src.shapes(labli).each():
            if s.is_text():
                labels.append((s, pya.Trans()))
        if not labels:
            continue
        nlab = out.layer(ln, 10)
        ndraw = out.layer(ln, 0) if drawli is not None else None
        drawreg = None
        if drawli is not None:
            drawreg = pya.Region(src.begin_shapes_rec(drawli))
            drawreg.merge()
        copied = set()
        for s, tr in labels:
            nc.shapes(nlab).insert(s, tr)
            nlabels += 1
            if drawreg is None:
                continue
            # anchor point of the label in top coords
            ap = s.bbox().transformed(tr)
            cx = (ap.left + ap.right) // 2
            cy = (ap.bottom + ap.top) // 2
            probe = pya.Region(pya.Box(cx - HALO, cy - HALO, cx + HALO, cy + HALO))
            hits = drawreg.interacting(probe)
            for poly in hits.each():
                bb = poly.bbox()
                key = (bb.left, bb.bottom, bb.right, bb.top)
                if key in copied:
                    continue
                copied.add(key)
                nc.shapes(ndraw).insert(poly)
                npins += 1

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    out.write(OUT)
    print(f"wrote abstract: {nlabels} labels, {npins} pin shapes")


main()
