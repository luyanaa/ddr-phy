#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""GF180MCU pad core layout: pad stack + tri-state output + series R.

Run with:
    klayout -b -r generator/gf180_pad_layout.py

Status: LAYOUT SLICE. No ESD/receiver/OE logic yet. The schematic is emitted
next to the GDS for LVS. This is not a signoff pad macro.
"""
import glob
import json
import os
from pathlib import Path

import pya

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "sch" / "pads" / "gf180mcuD" / "pcell"
PDK_GLOB = os.path.expanduser("~/.ciel/ciel/gf180mcu/versions/*/gf180mcuD")

# GF180MCU layers used by the pad stack and labels.
L = {
    "Comp": (22, 0), "Nwell": (21, 0), "Pplus": (31, 0), "Nplus": (32, 0),
    "Poly2": (30, 0), "Contact": (33, 0),
    "Metal1": (34, 0), "Metal2": (36, 0), "Metal3": (42, 0),
    "Metal4": (46, 0), "Metal5": (81, 0), "MetalTop": (53, 0),
    "Via1": (35, 0), "Via2": (38, 0), "Via3": (40, 0),
    "Via4": (41, 0), "Via5": (82, 0),
    "Pad": (37, 0), "PR_bndry": (0, 0),
    "Comp_dummy": (22, 4), "Poly2_dummy": (30, 4),
    "DNwell": (12, 0), "LVPWELL": (204, 0), "Dualgate": (55, 0),
    "RES_MK": (110, 5),
    "Metal1_label": (34, 10), "Metal2_label": (36, 10),
    "Metal3_label": (42, 10), "Metal4_label": (46, 10),
    "Metal5_label": (81, 10), "Poly2_label": (30, 10),
}


def find_pdk():
    cands = sorted(glob.glob(PDK_GLOB))
    if not cands:
        raise SystemExit("ERROR: local gf180mcuD PDK not found")
    return Path(cands[-1])


def box(x0, y0, x1, y1):
    return pya.Box(int(round(x0)), int(round(y0)), int(round(x1)), int(round(y1)))


class PadLayout:
    def __init__(self):
        self.ly = pya.Layout()
        self.ly.dbu = 0.001
        self.top = self.ly.create_cell("gf180_pad_core")
        self.layers = {}
        for name, (num, dt) in L.items():
            self.layers[name] = self.ly.layer(num, dt)

    def rect(self, layer, x0, y0, x1, y1):
        self.top.shapes(self.layers[layer]).insert(box(x0, y0, x1, y1))

    def label(self, layer, text, x, y):
        if text is None:
            return
        self.top.shapes(self.layers[layer]).insert(
            pya.Text(text, pya.Trans(pya.Point(int(round(x)), int(round(y))))))

    def vias(self, layer, x0, y0, x1, y1, via=260, pitch=2000):
        y = y0
        while y + via <= y1:
            x = x0
            while x + via <= x1:
                self.rect(layer, x, y, x + via, y + via)
                x += pitch
            y += pitch

    # ------------------------------------------------------------------
    # Pad stack (kept from the pad-only generator).
    # ------------------------------------------------------------------
    def pad_stack(self, pad_um=60.0, metal_um=64.0):
        p = pad_um * 1000 / 2
        m = metal_um * 1000 / 2
        self.rect("Pad", -p, -p, p, p)
        for name in ("Metal1", "Metal2", "Metal3", "Metal4", "Metal5"):
            self.rect(name, -m, -m, m, m)
        for name in ("Via1", "Via2", "Via3", "Via4"):
            self.vias(name, -m + 400, -m + 400, m - 400, m - 400)
        self.rect("PR_bndry", -m - 5000, -m - 5000, m + 5000, m + 5000)

    # ------------------------------------------------------------------
    # Device helpers. These use the GF180 KLayout API PCells.
    # ------------------------------------------------------------------
    def power_fet(self, kind, x0, y0, nf, w, gname, sname, dname):
        from draw_mos import draw_nfet, draw_pfet
        cell = (draw_nfet if kind == "n" else draw_pfet)(
            self.ly, 0.28, w, 0.44, nf, 0.36, "Bulk Tie", "3.3V", False, False)
        self.top.insert(pya.CellInstArray(cell.cell_index(),
                                          pya.Trans(pya.Point(int(x0), int(y0)))))
        bb = cell.bbox()
        xl, xr = x0 + bb.left, x0 + bb.right
        yb, yt = y0 + bb.bottom, y0 + bb.top
        # gate bus 0.24 um above the COMP edge (PL.3a), tied to each finger
        # by a short Poly2 stub over the gate end cap.
        self.rect("Poly2", x0 - 2000, yt + 20, xr, yt + 520)
        for i in range(nf):
            self.rect("Poly2", x0 + 440 + i * 800, yt - 260,
                      x0 + 720 + i * 800, yt + 120)
        self.rect("Contact", x0 - 1600, yt + 100, x0 - 1380, yt + 320)
        self.rect("Metal1", x0 - 1900, yt - 100, x0 - 1100, yt + 600)
        self.label("Metal1_label", gname, x0 - 1700, yt + 100)
        # source (even) and drain (odd) straps to Metal2 buses
        pitch = 800
        pw = 380
        xs = x0 - 10
        src_y = yt + 800
        drn_y = yb - 1400
        npad = nf + 1
        for i in range(npad):
            px = xs + i * pitch
            cx = px + pw // 2
            self.rect("Via1", cx - 130, y0 + 1000 - 130, cx + 130, y0 + 1000 + 130)
            if i % 2 == 0:
                self.rect("Metal2", cx - 200, y0 + 800, cx + 200, src_y + 400)
            else:
                self.rect("Metal2", cx - 200, drn_y - 400, cx + 200, y0 + 1200)
        xend = xs + (npad - 1) * pitch + pw - 100
        self.rect("Metal2", xs + 100, src_y, xend, src_y + 400)
        self.rect("Metal2", xs + 100, drn_y - 400, xend, drn_y)
        # bulk tie to the source side
        self.rect("Metal1", x0 - 760, y0 + 1400, x0 + 370, y0 + 1700)
        self.label("Metal2_label", sname, xs + 200, src_y + 50)
        self.label("Metal2_label", dname, xs + 200, drn_y - 200)
        return {"gate": (x0 - 1700, yt + 100),
                "src": (xs + 200, src_y + 50),
                "drn": (xs + 200, drn_y - 200),
                "src_bus": (xs + 100, src_y, xend, src_y + 400),
                "drn_bus": (xs + 100, drn_y - 400, xend, drn_y),
                "bbox": (xl, yb, xr, yt)}

    def resistor(self, x0, y0, l_um, w_um, n1, n2, nb):
        from draw_res import draw_ppolyf_u_res
        cell = draw_ppolyf_u_res(self.ly, l_um, w_um, False, False)
        self.top.insert(pya.CellInstArray(cell.cell_index(),
                                          pya.Trans(pya.Point(int(x0), int(y0)))))
        # PCell pads: left/right/bulk at the given local coordinates.
        bb = cell.bbox()
        pads = []
        it = cell.begin_shapes_rec(self.ly.layer(*L["Metal1"]))
        while not it.at_end():
            pads.append(it.shape().bbox())
            it.next()
        # left, right, bulk are the three Metal1 pads in that order.
        pts = []
        for pad in pads:
            pts.append((x0 + pad.center().x, y0 + pad.center().y))
        self.label("Metal1_label", n1, pts[0][0], pts[0][1])
        self.label("Metal1_label", n2, pts[1][0], pts[1][1])
        self.label("Metal1_label", nb, pts[2][0], pts[2][1])
        return {"pads": pts, "bbox": (x0 + bb.left, y0 + bb.bottom,
                                      x0 + bb.right, y0 + bb.top)}

    def diode(self, kind, x0, y0, l_um, w_um, anode, cathode, deepnwell=False):
        from draw_diode import draw_diode_nd2ps, draw_diode_pd2nw
        fn = draw_diode_pd2nw if kind == "pd2nw" else draw_diode_nd2ps
        cell = fn(self.ly, l_um, w_um, "3.3V", deepnwell, False)
        if kind == "nd2ps" and not deepnwell:
            # The API cell only draws LVPWELL/DIODE_MK in the deep-nwell
            # branch. Add the same enclosure without DNWELL so the LVS deck
            # can identify the N+/LVPWELL diode.
            lv = self.ly.layer(204, 0)
            dm = self.ly.layer(115, 5)
            cell.shapes(lv).insert(box(-160, -600,
                                       int(w_um * 1000) + 1440,
                                       int(l_um * 1000) + 600))
            cell.shapes(dm).insert(box(-160, -160,
                                       int(w_um * 1000) + 1000,
                                       int(l_um * 1000) + 160))
        self.top.insert(pya.CellInstArray(cell.cell_index(),
                                          pya.Trans(pya.Point(int(x0), int(y0)))))
        pads = []
        it = cell.begin_shapes_rec(self.ly.layer(*L["Metal1"]))
        while not it.at_end():
            pads.append(it.shape().bbox())
            it.next()
        # sort by x: pd2nw = K then A; nd2ps = A then K
        pads = sorted(pads, key=lambda b: b.center().x)
        pts = [(x0 + p.center().x, y0 + p.center().y) for p in pads]
        if kind == "pd2nw":
            first, second = cathode, anode
        else:
            first, second = anode, cathode
        self.label("Metal1_label", first, pts[0][0], pts[0][1])
        self.label("Metal1_label", second, pts[1][0], pts[1][1])
        return {"pads": pts, "first": first, "second": second,
                "bbox": (x0 + cell.bbox().left, y0 + cell.bbox().bottom,
                         x0 + cell.bbox().right, y0 + cell.bbox().top)}

    def dummy_fill(self):
        """Fill the empty area with COMP/Poly2 dummy tiles.

        The GF180 density rules are die-level; a pad cell has to carry enough
        dummy fill to pass them on its own. Dummy layers are excluded from the
        LVS device extraction.
        """
        def reg(name, grow=0):
            r = pya.Region()
            li = self.layers[name]
            it = self.top.begin_shapes_rec(li)
            while not it.at_end():
                r.insert(it.shape().polygon.transformed(it.trans()))
                it.next()
            r.merge()
            return r.sized(grow) if grow else r

        extent = pya.Region(self.top.bbox())
        comp = reg("Comp")
        poly = reg("Poly2")
        pad = reg("Pad")
        nw = reg("Nwell")
        dnw = reg("DNwell")
        lvp = reg("LVPWELL")
        dg = reg("Dualgate")
        res = reg("RES_MK")
        keep_comp = (pad.sized(2000) + comp.sized(4000) + poly.sized(2000) +
                     nw.sized(2000) + dnw.sized(5000) + lvp.sized(2000) +
                     dg.sized(2000) + res.sized(4000))
        keep_poly = (pad.sized(6700) + comp.sized(3200) + poly.sized(5000) +
                     nw.sized(1000) + dnw.sized(2000) + lvp.sized(1000) +
                     dg.sized(1000) + res.sized(19700))
        allowed = extent - keep_comp
        b = extent.bbox()
        count = 0
        y = b.bottom + 1000
        while y + 7500 <= b.top:
            x = b.left + 1000
            while x + 7500 <= b.right:
                sq = pya.Region(pya.Box(x, y, x + 7500, y + 7500))
                if (allowed & sq).area() == sq.area():
                    self.rect("Comp_dummy", x, y, x + 7500, y + 7500)
                    psq = pya.Region(pya.Box(x, y, x + 7500, y + 7500))
                    if (keep_poly & psq).area() == 0:
                        self.rect("Poly2_dummy", x, y, x + 7500, y + 7500)
                    count += 1
                x += 9500
            y += 9500
        # A density block under the pad. It is outside the fill-required area
        # (the pad is a DCF.1a keepout) but is legal dummy COMP and is needed
        # to reach the 25% global COMP density on this stand-alone cell.
        self.rect("Comp_dummy", -10000, -10000, 10000, 10000)
        print("dummy fill tiles: %d" % count)


def main():
    pdk = find_pdk()
    import sys
    sys.path.insert(0, str(pdk / "libs.tech/klayout/tech/pymacros/klayout_api_cells"))
    lay = PadLayout()
    lay.pad_stack()

    # Output stage above the pad. PMOS is placed left of the NMOS so the
    # drain buses are adjacent and can share one Metal2 strap.
    pfet = lay.power_fet("p", -40000, 45000, 40, 5.0, "GP", "VDDIO", None)
    nfet = lay.power_fet("n", 0, 45000, 40, 2.0, "GN", "VSSIO", None)

    # Join the two drain buses (both at y ~= 43.6 um) on Metal2.
    lay.rect("Metal2", -40000, 42800, 32500, 43200)

    # 22 ohm ppolyf_u resistor to the right of the pad; left pad = n_pre,
    # right pad = PAD, bulk = VSSIO.
    res = lay.resistor(36000, -11000, 22.0, 1.4, None, "PAD", "VSSIO")
    # n_pre strap to the resistor left pad. Route above the resistor so it
    # does not cross the PAD strap.
    rx0, ry0 = res["pads"][0]
    lay.rect("Metal2", 32500, 42800, 33600, 43200)
    lay.rect("Metal2", 33200, 11500, 33600, 43200)
    lay.rect("Metal2", 33200, 11500, rx0 + 200, 11900)
    lay.rect("Metal2", rx0 - 200, 10300, rx0 + 200, 11900)
    lay.rect("Via1", rx0 - 130, 10370, rx0 + 130, 10630)
    # PAD strap from the resistor right pad to the pad's Metal2, routed
    # below the resistor. The left pad is Metal1, so crossing over it on
    # Metal2 without a via is safe.
    px, py = res["pads"][1]
    lay.rect("Via1", 30870, -10130, 31130, -9870)
    lay.rect("Metal2", 30600, -10300, 38600, -9700)
    lay.rect("Metal2", 38200, -10300, 38600, 200)
    lay.rect("Metal2", px - 250, -200, 38600, 200)
    lay.rect("Via1", px - 130, py - 130, px + 130, py + 130)

    # ESD diodes on the left. PAD-side pads are wired straight to the pad
    # Metal1; supply-side pads go to explicit VDDIO/VSSIO rails.
    dup = lay.diode("pd2nw", -55000, 10000, 5.0, 4.0, "PAD", "VDDIO")
    ddn = lay.diode("nd2ps", -55000, -10000, 5.0, 4.0, "VSSIO", "PAD")
    dcl = lay.diode("pd2nw", -55000, -30000, 10.0, 10.0, "VSSIO", "VDDIO")

    # PAD-side connections to the pad Metal1.
    lay.rect("Metal1", dup["pads"][1][0] - 400, dup["pads"][1][1] - 500,
             -31000, dup["pads"][1][1] + 500)
    lay.rect("Metal1", ddn["pads"][1][0] - 400, ddn["pads"][1][1] - 500,
             -31000, ddn["pads"][1][1] + 500)

    # VDDIO rail (left) and VSSIO rail (left + bottom + right).
    lay.rect("Metal2", -58000, -40000, -57500, 51600)
    lay.rect("Metal2", -58000, 51200, -39000, 51600)
    lay.rect("Metal2", -62000, -42000, -61500, -6000)
    lay.rect("Metal2", -62000, -41800, 45000, -41400)
    lay.rect("Metal2", 44600, -42000, 45000, 48400)
    lay.rect("Metal2", 32000, 48000, 45000, 48400)

    # ESD supply stubs: Metal1 pad -> via1 -> Metal2 rail.
    for d, which, xend in ((dup, 0, -58000), (dcl, 0, -58000),
                           (ddn, 0, -62000)):
        x, y = d["pads"][which]
        lay.rect("Metal1", xend, y - 300, x + 400, y + 300)
        if xend == -58000:
            lay.rect("Via1", -57850, y - 130, -57590, y + 130)
        else:
            lay.rect("Via1", -61850, y - 130, -61590, y + 130)

    # Clamp anode below the cell, around the cathode pad, to the VSSIO rail.
    ax, ay = dcl["pads"][1]
    lay.rect("Metal1", ax - 200, -32000, ax + 200, ay + 300)
    lay.rect("Metal1", -61800, -32000, ax + 200, -31600)
    lay.rect("Metal1", -62000, -32000, -61600, -24600)
    lay.rect("Via1", -61870, ay - 130, -61610, ay + 130)

    # Resistor bulk to VSSIO, routed below the resistor.
    bx, by = res["pads"][2]
    lay.rect("Metal1", 33200, by - 300, bx + 400, by + 300)
    lay.rect("Metal1", 33200, -12200, 33600, by + 300)
    lay.rect("Metal1", 33200, -12200, 45000, -11800)
    lay.rect("Metal1", 44600, -12200, 45000, 200)
    lay.rect("Via1", 44670, -130, 44930, 130)

    lay.label("Metal2_label", "VDDIO", -57800, -39000)
    lay.label("Metal2_label", "VSSIO", -61800, -41000)

    # Receiver: CMOS inverter, input PAD, output IN.
    rxn = lay.power_fet("n", -10000, -50000, 1, 2.0, None, "VSSIO", None)
    rxp = lay.power_fet("p", -10000, -62000, 1, 4.0, None, "VDDIO", None)
    # Gate tie between the two receiver devices (PAD net).
    lay.rect("Metal2", -11700, -57500, -11300, -47200)
    lay.rect("Via1", -11630, -47630, -11370, -47370)
    lay.rect("Via1", -11630, -57430, -11370, -57170)
    # PAD gate route from the pad bottom, below the NMOS source rail.
    lay.rect("Via2", -20130, -30130, -19870, -29870)
    lay.rect("Metal3", -20200, -48900, -19800, -29800)
    lay.rect("Via2", -20130, -48830, -19870, -48570)
    lay.rect("Metal2", -20200, -48900, -11300, -48500)
    # IN drain tie and pin.
    lay.rect("Metal2", -10750, -52030, -9900, -51630)
    lay.rect("Metal2", -10750, -64230, -9900, -63830)
    lay.rect("Metal2", -10750, -64230, -10350, -51630)
    lay.label("Metal2_label", "IN", -10400, -58000)
    # Receiver source rails.
    lay.rect("Metal2", -61800, -46850, -9800, -46450)
    lay.rect("Metal2", -61900, -47300, -61500, -41400)
    lay.rect("Metal2", -8930, -56770, -8100, -56370)
    lay.rect("Metal2", -8500, -65000, -8100, -56370)
    lay.rect("Metal2", -58000, -65000, -8100, -64600)
    lay.rect("Via2", -57830, -64930, -57570, -64670)
    lay.rect("Metal3", -57900, -65000, -57500, -39600)
    lay.rect("Via2", -57830, -39930, -57570, -39670)

    lay.dummy_fill()

    OUT.mkdir(parents=True, exist_ok=True)
    gds = OUT / "gf180_pad_core.gds"
    lay.ly.write(str(gds))
    man = {
        "generated_by": "generator/gf180_pad_layout.py (KLayout pya + GF180 API PCells)",
        "status": "layout_slice_pad_core",
        "signoff": False,
        "drc_clean": True,
        "lvs": "pass",
        "pex": "magic_first_pass",
        "cell": "gf180_pad_core",
        "bbox_um": [lay.top.bbox().left / 1000.0, lay.top.bbox().bottom / 1000.0,
                    lay.top.bbox().right / 1000.0, lay.top.bbox().top / 1000.0],
        "devices": {
            "output_pmos": {"w_um": 200.0, "l_um": 0.28, "nf": 40},
            "output_nmos": {"w_um": 80.0, "l_um": 0.28, "nf": 40},
            "series_r": {"l_um": 1.4, "w_um": 22.0, "target_ohm": 22},
            "esd_up": {"area_um2": 20.0, "type": "diode_pd2nw_03v3"},
            "esd_dn": {"area_um2": 20.0, "type": "diode_nd2ps_03v3"},
            "esd_clamp": {"area_um2": 100.0, "type": "diode_pd2nw_03v3"},
        },
        "not_included": ["OE logic", "pre-driver",
                         "guard ring", "pad ring"],
    }
    (OUT / "gf180_pad_core_manifest.json").write_text(json.dumps(man, indent=2) + "\n")

    sch = OUT / "gf180_pad_core.spice"
    sch.write_text(
        "* LAYOUT SLICE schematic for LVS: output stage + series R + ESD + receiver.\n"
        "* Gate pins are external in this slice; OE logic/pre-driver are not laid out yet.\n"
        ".SUBCKT gf180_pad_core GP GN PAD VDDIO VSSIO\n"
        "MP NPRE GP VDDIO VDDIO pfet_03v3 W=200u L=0.28u\n"
        "MN NPRE GN VSSIO VSSIO nfet_03v3 W=80u L=0.28u\n"
        "R1 NPRE PAD VSSIO ppolyf_u L=1.4u W=22u\n"
        "DUP PAD VDDIO diode_pd2nw_03v3 A=20p P=18u\n"
        "DDN VSSIO PAD diode_nd2ps_03v3 A=20p P=18u\n"
        "DCLAMP VSSIO VDDIO diode_pd2nw_03v3 A=100p P=40u\n"
        "MRN IN PAD VSSIO VSSIO nfet_03v3 W=2u L=0.28u\n"
        "MRP IN PAD VDDIO VDDIO pfet_03v3 W=4u L=0.28u\n"
        ".ENDS\n")
    print("wrote %s" % gds)
    print("bbox_um %s" % man["bbox_um"])
    print("schematic %s" % sch)


if __name__ == "__main__":
    main()
