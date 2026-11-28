# SPDX-License-Identifier: Apache-2.0
"""Density fill + seal ring post-pass for the GF180 SDRAM chip top.

Reads the routed chip-top GDS, draws the chip-level seal ring at the die
edge, then floods the empty interior with dummy-layer tiles on a regular
grid.  Dummy layers are distinct datatypes (x,4) so they never short signal
nets; DM.x / DCF.x / DPF.x spacing is honoured by grid pitch + keepout halo.

Method: build the full regular grid of dummy squares as a pya.Region, then
subtract every square that interacts with (a) drawn geometry + halo on the
same layer family, (b) the core block, (c) the seal ring band.  Region
boolean ops are far faster than per-polygon Python loops on a 1.8 mm die.

Run:  klayout -b -r generator/emit_chip_fill.py
"""
import os
import pya

HERE = os.path.dirname(os.path.abspath(__file__))
PCELL = os.path.join(HERE, "..", "sch", "pads", "gf180mcuD", "pcell")
IN_GDS = os.path.join(PCELL, "gf180mcu_sdram_chip_top.gds")
OUT_GDS = os.path.join(PCELL, "gf180mcu_sdram_chip_top_filled.gds")

UM = 1000
DIE = 1800.0
INNER = 210.16           # ring inner boundary
CORE_X = (DIE - 274.035) / 2.0
CORE_Y = (DIE - 291.955) / 2.0
CORE_W, CORE_H = 274.035, 291.955


def dbu(v):
    return int(round(v * UM))


def region_of(cell, li):
    if li is None:
        return pya.Region()
    r = pya.Region(cell.begin_shapes_rec(li))
    r.merge()
    return r


def main():
    ly = pya.Layout()
    ly.read(IN_GDS)
    top = ly.cell("gf180mcu_sdram_chip_top") or ly.top_cell()

    layermap = {}
    for li in range(ly.layers()):
        inf = ly.get_info(li)
        layermap[(inf.layer, inf.datatype)] = li

    def L(ln, dt):
        if (ln, dt) in layermap:
            return layermap[(ln, dt)]
        return ly.layer(ln, dt)

    def find(ln, dt):
        return layermap.get((ln, dt))

    # --------------------------------------------------------------
    # 1. seal ring frames at the die edge.
    # --------------------------------------------------------------
    sw = 12.0

    def frame(ln, dt, inset_um, width_um):
        li = L(ln, dt)
        ins = dbu(inset_um)
        w = dbu(width_um)
        Wd = dbu(DIE)
        x0, y0, x1, y1 = ins, ins, Wd - ins, Wd - ins
        for b in (pya.Box(x0, y1 - w, x1, y1), pya.Box(x0, y0, x1, y0 + w),
                  pya.Box(x0, y0, x0 + w, y1), pya.Box(x1 - w, y0, x1, y1)):
            top.shapes(li).insert(b)

    frame(22, 0, 2.0, sw)        # Comp
    frame(31, 0, 2.4, sw - 0.8)  # Pplus
    for m in (34, 36, 42, 46, 81, 53):
        frame(m, 0, 2.0, sw)     # Metal1..MetalTop drawn
    print("seal ring drawn")

    # --------------------------------------------------------------
    # 2. density fill on the cavity minus keepouts.
    # --------------------------------------------------------------
    diebox = pya.Region(pya.Box(0, 0, dbu(DIE), dbu(DIE)))
    cavity = pya.Region(pya.Box(dbu(INNER), dbu(INNER),
                                dbu(DIE - INNER), dbu(DIE - INNER)))
    coreblk = pya.Region(pya.Box(dbu(CORE_X - 2), dbu(CORE_Y - 2),
                                 dbu(CORE_X + CORE_W + 2),
                                 dbu(CORE_Y + CORE_H + 2)))
    inner_clip = pya.Region(pya.Box(dbu(INNER - 5), dbu(INNER - 5),
                                    dbu(DIE - INNER + 5), dbu(DIE - INNER + 5)))
    sealband = diebox - inner_clip

    SPEC = [
        ((34, 0), (34, 4), 6.0, 7.0, 2.2, "Metal1"),
        ((36, 0), (36, 4), 6.0, 7.0, 2.2, "Metal2"),
        ((42, 0), (42, 4), 6.0, 7.0, 2.2, "Metal3"),
        ((46, 0), (46, 4), 6.0, 7.0, 2.2, "Metal4"),
        ((81, 0), (81, 4), 6.0, 7.0, 2.2, "Metal5"),
        ((53, 0), (53, 4), 6.0, 7.0, 2.2, "MetalTop"),
    ]

    def grid_region(tile, pitch):
        t = dbu(tile); p = dbu(pitch)
        x0 = dbu(INNER); y0 = dbu(INNER)
        x1 = dbu(DIE - INNER); y1 = dbu(DIE - INNER)
        reg = pya.Region()
        y = y0
        while y + t <= y1:
            x = x0
            while x + t <= x1:
                reg.insert(pya.Box(x, y, x + t, y + t))
                x += p
            y += p
        return reg

    for (dln, ddt), (mln, mdt), tile, pitch, halo, nm in SPEC:
        drawn = region_of(top, find(dln, ddt))
        keepout = drawn.sized(dbu(halo)) + coreblk + sealband
        keepout.merge()
        grid = grid_region(tile, pitch) & cavity
        bad = grid.interacting(keepout)
        good = grid - bad
        mli = L(mln, mdt)
        cnt = 0
        for poly in good.each():
            top.shapes(mli).insert(poly)
            cnt += 1
        print(f"{nm}: {cnt} dummy tiles")


    # --------------------------------------------------------------
    # 3. coupled comp/poly2 fill.  DPF.1: dummy poly2 must be generated on
    #    top of dummy comp, so each surviving comp tile gets a smaller poly2
    #    tile centred inside it.  comp tile 3.0/pitch 5.0 (cov 36%), poly2
    #    tile 5.0 centred inside the 6.0 comp tile (cov 40%) - both above the
    #    25%/14% density floors.  comp T=6.0 pitch 7.9 (cov 58%).
    # --------------------------------------------------------------
    def layer_region(ln, dt):
        return region_of(top, find(ln, dt))

    comp_drawn = layer_region(22, 0)
    poly2_drawn = layer_region(30, 0)
    # comp+poly2 are a coincident pair.  DPF.1: dummy poly2 must COVER dummy
    # comp (proven: poly2 inset inside comp fails not_covering).  So both
    # dummies are the same 6.0 um tile, comp on (22,4), poly2 on (30,4).
    # keepout union (binding): circuit COMP 3.5 (DCF.4), circuit poly2 5.0
    # (DPF.5).  comp tile 6.0 pitch 7.9 -> cov 58% over fill area.
    comp_keep = (comp_drawn.sized(dbu(3.5)) + poly2_drawn.sized(dbu(5.0))
                 + coreblk + sealband)
    comp_keep.merge()
    comp_grid = grid_region(6.0, 7.9) & cavity
    comp_bad = comp_grid.interacting(comp_keep)
    comp_good = comp_grid - comp_bad

    comp_li = L(22, 4)
    poly_li = L(30, 4)
    ncomp = 0
    for poly in comp_good.each():
        bb = poly.bbox()
        top.shapes(comp_li).insert(poly)
        top.shapes(poly_li).insert(pya.Box(bb.left, bb.bottom, bb.right, bb.top))
        ncomp += 1
    print(f"Comp+Poly2: {ncomp} coincident dummy tile pairs")

    ly.write(OUT_GDS)
    print("wrote", OUT_GDS)


main()
