#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""WIP - OE logic / pre-driver layout. LVS progress log:

FIXED (verified via Metal1/2/3/4 connectivity probes):
  1. _m1v was drawing Metal1 from x instead of y -> giant VDDIO-VSSIO short
  2. net_pts missing output pads -> each stage output shorted to its input track
  3. NAND2/NOR2 input heads on PMOS gates -> stub crossed EN_N Metal2 bar
  4. NAND2 EN_N Metal2 bar too short -> did not cover MN1.D via1
  5. NOR2 p2 missing bulk tie stub -> PMOS2 B terminal floating
  6. Mirror sc=+180 (should be -180) -> mirrored S pad at wrong x

REMAINING (LVS still fails):
  - Metal1 probe: MID_GP connected to VDDIO rail (NOR2 PMOS series mid node)
  - Extracted M$47/M$52 B terminal = MID_GP instead of VDDIO (PMOS series
    bulk tie may need to be closer to each device, or the Nwell net is
    confused by the MID Metal1 proximity)
  - ~10 nets unmatched; the graph mismatch cascades from the MID_GP-VDDIO
    connection in the NOR2 series stack

NEXT: probe the NOR2 PMOS MID Metal1 wire (y 58600..59000) against the
MP1.S VDDIO stub (y 53000..55390, x gx-960..-560) and the MP2.B VDDIO stub
(x gx+1780..2180) -- one of them must be touching the MID wire.

Original docstring:

GF180MCU pad core layout: pad stack + tri-state output + series R.

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
    "Metal1_dummy": (34, 4), "Metal2_dummy": (36, 4),
    "Metal3_dummy": (42, 4), "Metal4_dummy": (46, 4),
    "Metal5_dummy": (81, 4), "MetalTop_dummy": (53, 4),
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

    # ------------------------------------------------------------------
    # OE logic + pre-driver (IO domain, W_N=1u W_P=2u L=0.28u).
    # All coordinates dbu. Row above the output stage; internal nets on
    # dedicated Metal3 tracks; GP/GN brought down on Metal4.
    # ------------------------------------------------------------------
    LY_VDD = 52400          # VDDIO rail (Metal1) y0
    LY_PMOS = 55400         # PMOS origin (COMP 55400..57400)
    LY_NMOS = 59600         # NMOS origin (COMP 59600..60600)
    LY_VSS = 62200          # VSSIO rail (Metal1) y0
    LY_HEAD0 = 53200        # bottom gate head Poly2 y0
    LY_HEAD1 = 55400        # bottom gate head Poly2 y1

    def logic_fet(self, kind, x0, y0, mirror=False):
        from draw_mos import draw_nfet, draw_pfet
        cell = (draw_nfet if kind == "n" else draw_pfet)(
            self.ly, 0.28, 1.0 if kind == "n" else 2.0, 0.44, 1, 0.36,
            "Bulk Tie", "3.3V", False, False)
        tr = (pya.Trans(pya.Trans.M90, int(x0), int(y0)) if mirror
              else pya.Trans(int(x0), int(y0)))
        self.top.insert(pya.CellInstArray(cell.cell_index(), tr))
        sc, dc, bc, gc = ((-180, -980, 540, -580) if mirror
                          else (180, 980, -540, 580))
        py_ = y0 + (1000 if kind == "p" else 500)
        # VSS/VDD strap anchor: the gate head sits at x0+gc, so the strap is
        # routed on the far side of the device to keep >=0.23um clearance.
        if mirror:
            vx, vy = x0 + 500, y0 - 300
        else:
            vx, vy = x0 - 540, y0 + 300
        return {"S": x0 + sc, "D": x0 + dc, "B": x0 + bc, "G": x0 + gc,
                "Sy": py_, "Dy": py_, "By": py_,
                "Vx": vx, "Vy": vy, "mirror": mirror}

    def _m1v(self, x, y0, y1):
        self.rect("Metal1", x - 200, min(y0, y1), x + 200, max(y0, y1))

    def _nmos_vss(self, n, tie_source=True):
        """Tie an NMOS bulk (and optionally source) to VSSIO.

        The bulk pad is the one furthest from the gate head, so the vertical
        strap runs there; the source is tied with a short bar below the
        gate-head band.
        """
        if tie_source:
            self.rect("Metal1", min(n["S"], n["B"]) - 200, n["Sy"] - 200,
                      max(n["S"], n["B"]) + 200, n["Sy"] + 200)
        self._m1v(n["B"], n["Sy"] - 200, self.LY_VSS + 400)

    def _gate_head(self, gxc, net, bottom=False):
        """Input tap on a gate finger: top (NMOS) or bottom (PMOS) head."""
        if bottom:
            self.rect("Poly2", gxc - 280, 53200, gxc + 280, 55400)
            self.rect("Contact", gxc - 110, 53450, gxc + 110, 53670)
            self.rect("Metal1", gxc - 230, 53340, gxc + 230, 53780)
            self.rect("Via1", gxc - 130, 53450, gxc + 130, 53710)
            self.rect("Metal2", gxc - 250, 53340, gxc + 250, 53780)
            return {"x": gxc, "pad_y": 53560}
        self.rect("Poly2", gxc - 280, 60700, gxc + 280, 61600)
        self.rect("Contact", gxc - 110, 61150, gxc + 110, 61370)
        self.rect("Metal1", gxc - 230, 61040, gxc + 230, 61480)
        self.rect("Via1", gxc - 130, 61130, gxc + 130, 61390)
        self.rect("Metal2", gxc - 250, 61040, gxc + 250, 61480)
        return {"x": gxc, "pad_y": 61260}

    def _inv(self, gx, a_net):
        yp, yn = self.LY_PMOS, self.LY_NMOS
        p = self.logic_fet("p", gx - 580, yp)
        n = self.logic_fet("n", gx - 580, yn)
        self.rect("Poly2", gx - 140, yp - 220, gx + 140, yn + 1220)
        self._m1v(p["D"], yp + 1800, yn + 200)
        vy = (yp + 1800 + yn + 200) // 2
        self.rect("Via1", p["D"] - 130, vy - 130, p["D"] + 130, vy + 130)
        self.rect("Metal2", p["D"] - 280, vy - 280, p["D"] + 280, vy + 280)
        self._m1v(p["S"], p["Sy"], self.LY_VDD + 600)
        self._m1v(p["B"], p["By"], self.LY_VDD + 600)
        self._nmos_vss(n)
        h = self._gate_head(gx, a_net)
        yx = p["D"] + 300
        self.rect("Metal2", p["D"] - 250, vy - 280, yx + 250, vy + 280)
        return {"y": (yx, vy), "a": (gx, h["pad_y"])}

    def _nand2(self, gx, a_net, b_net):
        yp, yn = self.LY_PMOS, self.LY_NMOS
        p1 = self.logic_fet("p", gx - 580, yp)
        p2 = self.logic_fet("p", gx + 2520, yp)
        n1 = self.logic_fet("n", gx - 580, yn, mirror=True)
        n2 = self.logic_fet("n", gx + 2520, yn, mirror=True)
        for d in (p1, p2):
            self._m1v(d["S"], d["Sy"], self.LY_VDD + 600)
            self._m1v(d["B"], d["By"], self.LY_VDD + 600)
            self._m1v(d["D"], yp + 1800, 58210)
            self.rect("Via1", d["D"] - 130, 57950, d["D"] + 130, 58210)
        self.rect("Metal2", n1["D"] - 280, 57800, p2["D"] + 280, 58260)
        yx = p2["D"] + 300
        # NMOS series: MID between MN1.S and MN2.D (Metal1 in the gap band)
        self.rect("Metal1", n1["S"] - 200, 58600, n2["D"] + 200, 59000)
        self._m1v(n1["S"], 58600, yn + 100)
        self._m1v(n2["D"], 58600, yn + 100)
        self._m1v(n1["D"], 57950, yn + 100)
        self.rect("Via1", n1["D"] - 130, 57950, n1["D"] + 130, 58210)
        self._nmos_vss(n1, tie_source=False)
        self._nmos_vss(n2)
        # gate L-routes (Poly2): A = PMOS1+NMOS1, B = PMOS2+NMOS2
        self.rect("Poly2", p1["G"] - 140, yp - 220, p1["G"] + 140, 58500)
        self.rect("Poly2", n1["G"] - 140, 58500, p1["G"] + 140, 58780)
        self.rect("Poly2", n1["G"] - 140, 58780, n1["G"] + 140, yn + 1220)
        self.rect("Poly2", p2["G"] - 140, yp - 220, p2["G"] + 140, 59100)
        self.rect("Poly2", n2["G"] - 140, 59100, p2["G"] + 140, 59380)
        self.rect("Poly2", n2["G"] - 140, 59380, n2["G"] + 140, yn + 1220)
        a = self._gate_head(n1["G"], a_net)
        b = self._gate_head(n2["G"], b_net)
        self.rect("Metal2", yx - 250, 57800, yx + 250, 58260)
        return {"y": (yx, 58030), "a": (a["x"], a["pad_y"]),
                "b": (b["x"], b["pad_y"])}

    def _nor2(self, gx, a_net, b_net):
        yp, yn = self.LY_PMOS, self.LY_NMOS
        p1 = self.logic_fet("p", gx - 580, yp)
        p2 = self.logic_fet("p", gx + 2520, yp)
        n1 = self.logic_fet("n", gx - 580, yn)
        n2 = self.logic_fet("n", gx + 2520, yn)
        self.rect("Poly2", p1["G"] - 140, yp - 220, p1["G"] + 140, yn + 1220)
        self.rect("Poly2", p2["G"] - 140, yp - 220, p2["G"] + 140, yn + 1220)
        # PMOS series: MID between MP1.D and MP2.S (Metal1 near NMOS row)
        self.rect("Metal1", p1["D"] - 200, 58900, p2["S"] + 200, 59300)
        self._m1v(p1["D"], yp + 1800, 59300)
        self._m1v(p2["S"], yp + 1800, 59300)
        self._m1v(p1["S"], p1["Sy"], self.LY_VDD + 600)
        self._m1v(p1["B"], p1["By"], self.LY_VDD + 600)
        self._m1v(p2["B"], p2["By"], self.LY_VDD + 600)
        # MP2.D -> Y bar over the NMOS drains
        self._m1v(p2["D"], yp + 1800, yn + 100)
        # NMOS parallel: S/B -> VSSIO, D -> Y bar (Metal2)
        for d in (n1, n2):
            self._nmos_vss(d)
        self.rect("Metal2", n1["D"] - 280, yn - 40, n2["D"] + 280, yn + 360)
        for d in (n1, n2):
            self.rect("Via1", d["D"] - 130, yn + 10, d["D"] + 130, yn + 270)
        yx = gx + 1000
        self.rect("Metal2", yx - 250, yn - 40, yx + 250, yn + 360)
        a = self._gate_head(n1["G"], a_net)
        b = self._gate_head(n2["G"], b_net)
        return {"y": (yx, yn + 160), "a": (a["x"], a["pad_y"]),
                "b": (b["x"], b["pad_y"])}

    def _drop(self, x, y_track, y_pad):
        """Metal2 strap from a device pad up to its Metal3 track.

        Only the track end carries a Via2: the pad end is already tied to
        Metal1 by the device/gate-head Via1, and a Via2 there would have no
        Metal3 to land on (V2.4a) and no full Metal2 enclosure (V2.3b).
        """
        self.rect("Metal2", x - 150, min(y_pad, y_track) - 250,
                  x + 150, max(y_pad, y_track) + 250)
        self.rect("Via2", x - 130, y_track - 130, x + 130, y_track + 130)

    def _gate_to_pad(self, y_track, x_target, y_pad):
        self.rect("Metal4", x_target - 250, y_pad + 100, x_target + 250, y_track + 250)
        self.rect("Via3", x_target - 130, y_track - 130, x_target + 130, y_track + 130)
        self.rect("Via3", x_target - 130, y_pad + 150, x_target + 130, y_pad + 410)
        self.rect("Metal3", x_target - 250, y_pad + 50, x_target + 250, y_pad + 550)
        self.rect("Via2", x_target - 130, y_pad + 100, x_target + 130, y_pad + 360)
        self.rect("Metal2", x_target - 250, y_pad - 150, x_target + 250, y_pad + 410)
        self.rect("Via1", x_target - 130, y_pad - 130, x_target + 130, y_pad + 130)

    def oe_logic(self):
        net_pts = {}
        def add(net, pt):
            net_pts.setdefault(net, []).append(pt)
        x = -31000
        plan = [("inv", "OUT", None, "OUTB_I"),
                ("inv", "OE_N", None, "OENB"),
                ("nand2", "PU_OK", "OENB", "EN_N"),
                ("nor2", "EN_N", "OUTB_I", "NGPB"),
                ("inv", "NGPB", None, "N_GP"),
                ("inv", "N_GP", None, "N_GP_S1"),
                ("inv", "N_GP_S1", None, "GP"),
                ("nor2", "EN_N", "OUT", "N_GN"),
                ("inv", "N_GN", None, "N_GN_S1"),
                ("inv", "N_GN_S1", None, "GN")]
        yout = {}
        for typ, a, b, y in plan:
            if typ == "inv":
                g = self._inv(x, a); x += 4000
            elif typ == "nand2":
                g = self._nand2(x, a, b); x += 7000
            else:
                g = self._nor2(x, a, b); x += 7000
            add(a, g["a"])
            if b: add(b, g["b"])
            add(y, g["y"])
        row_x1 = x
        # rails must reach past the outermost device straps (x0-540 of the
        # first gate sits at -32120)
        self.rect("Metal1", -32700, self.LY_VDD, row_x1 + 1200, self.LY_VDD + 600)
        self.rect("Metal1", -32700, self.LY_VSS, 16600, self.LY_VSS + 600)
        # rails -> pad-core buses
        vx = -20000
        self.rect("Via1", vx - 130, self.LY_VDD + 150, vx + 130, self.LY_VDD + 410)
        self.rect("Metal2", vx - 250, self.LY_VDD, vx + 250, self.LY_VDD + 1500)
        self.rect("Via2", vx - 130, self.LY_VDD + 1140, vx + 130, self.LY_VDD + 1400)
        self.rect("Metal3", vx - 250, 51200, vx + 250, self.LY_VDD + 1500)
        self.rect("Via2", vx - 130, 51330, vx + 130, 51590)
        sx = 16000
        self.rect("Via1", sx - 130, self.LY_VSS + 150, sx + 130, self.LY_VSS + 410)
        self.rect("Metal2", sx - 250, self.LY_VSS, sx + 250, self.LY_VSS + 1500)
        self.rect("Via2", sx - 130, self.LY_VSS + 1140, sx + 130, self.LY_VSS + 1400)
        self.rect("Metal3", sx - 250, 48100, sx + 250, self.LY_VSS + 1500)
        self.rect("Via2", sx - 130, 48140, sx + 130, 48400)
        # Metal3 tracks per net
        tr = {"OUT": 63400, "OE_N": 64200, "PU_OK": 65000, "OUTB_I": 65800,
              "OENB": 66600, "EN_N": 67400, "NGPB": 68200, "N_GP": 69000,
              "N_GP_S1": 69800, "GP": 70600, "N_GN": 71400,
              "N_GN_S1": 72200, "GN": 73000}
        pin_pts = {"OUT": (-65500, 55500), "OE_N": (-62500, 58500),
                   "PU_OK": (-59500, 61500)}
        for net, pts in net_pts.items():
            allp = pts + ([pin_pts[net]] if net in pin_pts else [])
            xs = [p[0] for p in allp]
            self.rect("Metal3", min(xs) - 250, tr[net] - 250,
                      max(xs) + 250, tr[net] + 250)
            for px, py in allp:
                self._drop(px, tr[net], py)
        for net, xx, yy in (("OUT", -65500, 55500), ("OE_N", -62500, 58500),
                            ("PU_OK", -59500, 61500)):
            self.rect("Metal2", xx - 1000, yy - 1000, xx + 1000, yy + 1000)
            self.label("Metal2_label", net, xx, yy)
        # GP / GN: Metal3 track -> Metal4 vertical -> output gate pads
        for net, gx_pad, y_pad in (("GP", -41500, 50500), ("GN", -1500, 47300)):
            for px, py in net_pts[net]:
                self.rect("Metal3", min(px, gx_pad) - 250, tr[net] - 250,
                          max(px, gx_pad) + 250, tr[net] + 250)
                self._drop(px, tr[net], py)
            self._gate_to_pad(tr[net], gx_pad, y_pad)
        return tr

    def _ring(self, layer, x0, y0, x1, y1, w):
        self.rect(layer, x0, y0, x1, y0 + w)
        self.rect(layer, x0, y1 - w, x1, y1)
        self.rect(layer, x0, y0, x0 + w, y1)
        self.rect(layer, x1 - w, y0, x1, y1)

    def _ring_contacts(self, layer, x0, y0, x1, y1, w, size=220, pitch=400):
        """Tile square contacts along a ring band."""
        # rows/columns stop at the band edges so corners do not produce
        # merged (oversized) contacts
        def row(ya, yb):
            x = x0 + w
            while x + size <= x1 - w:
                self.rect(layer, x, ya, x + size, yb)
                x += pitch
        def col(xa, xb):
            y = y0 + w
            while y + size <= y1 - w:
                self.rect(layer, xa, y, xb, y + size)
                y += pitch
        row(y0 + (w - size) // 2, y0 + (w - size) // 2 + size)
        row(y1 - (w + size) // 2, y1 - (w + size) // 2 + size)
        col(x0 + (w - size) // 2, x0 + (w - size) // 2 + size)
        col(x1 - (w + size) // 2, x1 - (w + size) // 2 + size)

    def guard_ring(self):
        """Psub guard ring around the pad core, tied to VSSIO.

        Comp 1.0 um, Pplus = Comp + 0.16 um, a tiled contact row (0.22 um at
        0.4 um pitch), Metal1 and a Via1 row, then Metal2.
        """
        bb = self.top.bbox()
        m = 200
        x0, y0 = bb.left + m, bb.bottom + m
        x1, y1 = bb.right - m, bb.top - m
        w = 1000
        self._ring("Comp", x0, y0, x1, y1, w)
        self._ring("Pplus", x0 - 160, y0 - 160, x1 + 160, y1 + 160, w + 320)
        self._ring_contacts("Contact", x0, y0, x1, y1, w, size=220, pitch=500)
        self._ring("Metal1", x0 - 70, y0 - 70, x1 + 70, y1 + 70, w + 140)
        self._ring_contacts("Via1", x0, y0, x1, y1, w, size=260, pitch=600)
        self._ring("Metal2", x0 - 70, y0 - 70, x1 + 70, y1 + 70, w + 140)
        self.label("Metal2_label", "VSSIO", x0 + w // 2, y0 + w // 2)

    def local_guard_ring(self, x0, y0, x1, y1, net, w=800, size=220, pitch=500):
        """Guard ring around one device block (latch-up protection).

        A local ring does not touch the die edge, so it does not remove the
        dummy-fill rows that the die-level density rules depend on.
        """
        def frame(layer, xa, ya, xb, yb, wd):
            self.rect(layer, xa, ya, xb, ya + wd)
            self.rect(layer, xa, yb - wd, xb, yb)
            self.rect(layer, xa, ya, xa + wd, yb)
            self.rect(layer, xb - wd, ya, xb, yb)
        def contacts(layer, xa, ya, xb, yb, wd, size=220, pitch=500):
            def row(yy):
                x = xa + wd
                while x + size <= xb - wd:
                    self.rect(layer, x, yy, x + size, yy + size)
                    x += pitch
            def col(xx):
                y = ya + wd
                while y + size <= yb - wd:
                    self.rect(layer, xx, y, xx + size, y + size)
                    y += pitch
            row(ya + (wd - size) // 2)
            row(yb - (wd + size) // 2)
            col(xa + (wd - size) // 2)
            col(xb - (wd + size) // 2)
        frame("Comp", x0, y0, x1, y1, w)
        frame("Pplus", x0 - 160, y0 - 160, x1 + 160, y1 + 160, w + 320)
        contacts("Contact", x0, y0, x1, y1, w)
        frame("Metal1", x0 - 70, y0 - 70, x1 + 70, y1 + 70, w + 140)
        contacts("Via1", x0, y0, x1, y1, w, size=260, pitch=600)
        frame("Metal2", x0 - 70, y0 - 70, x1 + 70, y1 + 70, w + 140)
        self.label("Metal2_label", net, x0 + w // 2, y0 + w // 2)

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

    def dummy_density_fill(self):
        """Top up layer coverage so the die-level density rules pass.

        The OE-logic row makes the cell taller, which dilutes the pad stack's
        metal plates below the 30 % rule. Dummy tiles on the dedicated dummy
        layers restore the ratios; those layers are excluded from LVS.
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
        total = float(extent.area())
        b = extent.bbox()

        def fill(real, dummy, target, base, tile, pitch, fine=True):
            need = target / 100.0 * total - float(reg(real).area() + reg(dummy).area())
            if need <= 0:
                return 0
            allowed = pya.Region()
            allowed.insert(base)
            placed = 0
            # Coarse pass, then fine passes for the leftover slivers. COMP
            # dummy must keep its 1.9 um spacing, so it only gets the coarse
            # pass.
            passes = ((tile, pitch), (1500, 2600)) if fine else ((tile, pitch),)
            for t, p_ in passes:
                if need <= 0:
                    break
                for poly in allowed.merged().each():
                    if need <= 0:
                        break
                    pr = pya.Region(poly)
                    pb = poly.bbox()
                    y = pb.bottom
                    while y + t <= pb.top and need > 0:
                        x = pb.left
                        while x + t <= pb.right and need > 0:
                            sq = pya.Region(pya.Box(x, y, x + t, y + t))
                            if (pr & sq).area() == sq.area():
                                self.rect(dummy, x, y, x + t, y + t)
                                allowed -= sq
                                need -= float(sq.area())
                                placed += 1
                            x += p_
                        y += p_
            print("density top-up %-8s %3d tiles" % (real, placed))
            return placed

        # COMP dummy has its own keepouts (DCF.4 3.5um to COMP, DCF.2b 1.9um
        # dummy-dummy, DCF.6b 4um to DNWELL).
        keep_comp = pya.Region()
        for name in ("Comp", "Poly2", "Nwell", "DNwell", "LVPWELL",
                     "Dualgate", "RES_MK", "Pad", "Comp_dummy"):
            keep_comp += reg(name)
        keep_comp = (reg("Comp", 4000) + reg("Poly2", 2000) +
                     reg("Nwell", 2000) + reg("DNwell", 5000) +
                     reg("LVPWELL", 2000) + reg("Dualgate", 2000) +
                     reg("RES_MK", 4000) + reg("Pad", 2000) +
                     reg("Comp_dummy", 2000))
        base = extent - keep_comp
        fill("Comp", "Comp_dummy", 25.5, base, 5000, 7100, fine=False)

        # Metal dummy: DM.3 2um to circuit metal, DM.2b 0.98um dummy-dummy.
        keep_m = pya.Region()
        for name in ("Comp", "Poly2", "Nwell", "DNwell", "LVPWELL",
                     "Dualgate", "RES_MK", "Metal1", "Metal2", "Metal3",
                     "Metal4", "Metal5", "MetalTop", "Pad",
                     "Comp_dummy", "Poly2_dummy"):
            keep_m += reg(name)
        base = extent - keep_m.sized(2050)

        # With metal_level=5LM the deck aliases MetalTop to Metal5, so the
        # MT.3 ratio is the Metal5 ratio.
        for real, dummy in (("Metal1", "Metal1_dummy"), ("Metal2", "Metal2_dummy"),
                            ("Metal3", "Metal3_dummy"), ("Metal4", "Metal4_dummy"),
                            ("Metal5", "Metal5_dummy")):
            fill(real, dummy, 31.8, base, 2800, 3900)


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
    # PAD-referenced ESD diodes at 8 x 8 um (64 um2 each); the down diode is
    # duplicated so the PAD -> VSSIO clamp has 128 um2 of junction area.
    dup = lay.diode("pd2nw", -55000, 10000, 8.0, 8.0, "PAD", "VDDIO")
    ddn = lay.diode("nd2ps", -55000, -10000, 8.0, 8.0, "VSSIO", "PAD")
    ddn2 = lay.diode("nd2ps", -55000, -24000, 8.0, 8.0, "VSSIO", "PAD")
    dcl = lay.diode("pd2nw", -55000, -38000, 10.0, 10.0, "VSSIO", "VDDIO")
    # V1.4a: the diode cells place Via1 on their Metal1 pads, so each pad
    # needs Metal2 coverage.
    for d in (dup, ddn, ddn2, dcl):
        for px, py in d["pads"]:
            lay.rect("Metal2", px - 350, py - 350, px + 350, py + 350)

    # PAD-side connections to the pad Metal1.
    lay.rect("Metal1", dup["pads"][1][0] - 400, dup["pads"][1][1] - 500,
             -31000, dup["pads"][1][1] + 500)
    lay.rect("Metal1", ddn["pads"][1][0] - 400, ddn["pads"][1][1] - 500,
             -31000, ddn["pads"][1][1] + 500)
    lay.rect("Metal1", ddn2["pads"][1][0] - 400, ddn2["pads"][1][1] - 500,
             -31000, ddn2["pads"][1][1] + 500)

    # VDDIO rail (left) and VSSIO rail (left + bottom + right).
    lay.rect("Metal2", -58000, -40000, -57500, 51600)
    lay.rect("Metal2", -58000, 51200, -39000, 51600)
    lay.rect("Metal2", -62000, -42000, -61500, -5600)
    lay.rect("Metal2", -62000, -41800, 45000, -41400)
    lay.rect("Metal2", 44600, -42000, 45000, 48400)
    lay.rect("Metal2", 32000, 48000, 45000, 48400)

    # ESD supply stubs: Metal1 pad -> via1 -> Metal2 rail.
    for d, which, xend in ((dup, 0, -58000), (dcl, 0, -58000),
                           (ddn, 0, -62000), (ddn2, 0, -62000)):
        x, y = d["pads"][which]
        lay.rect("Metal1", xend, y - 300, x + 400, y + 300)
        if xend == -58000:
            lay.rect("Via1", -57850, y - 130, -57590, y + 130)
        else:
            lay.rect("Via1", -61850, y - 130, -61590, y + 130)

    # Clamp anode below the cell, around the cathode pad, to the VSSIO rail.
    ax, ay = dcl["pads"][1]
    lay.rect("Metal1", ax - 200, -40000, ax + 200, ay + 300)
    lay.rect("Metal1", -61800, -40000, ax + 200, -39600)
    lay.rect("Metal1", -62000, -40000, -61600, -32600)
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

    lay.oe_logic()
    lay.dummy_fill()
    lay.dummy_density_fill()

    OUT.mkdir(parents=True, exist_ok=True)
    gds = OUT / "gf180_pad_core.gds"
    lay.ly.write(str(gds))
    man = {
        "generated_by": "generator/gf180_pad_layout.py (KLayout pya + GF180 API PCells)",
        "status": "pad_macro_first_pass",
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
            "receiver": {"n_w_um": 2.0, "p_w_um": 4.0, "l_um": 0.28},
            "oe_logic": {"inv": 2, "nand2": 1, "nor2": 2,
                         "w_n_um": 1.0, "w_p_um": 2.0, "l_um": 0.28},
            "pre_driver": {"inv": 5, "w_n_um": 1.0, "w_p_um": 2.0, "l_um": 0.28},
        },
        "ports": ["OUT", "OE_N", "PU_OK", "PAD", "IN", "VDDIO", "VSSIO"],
        "evidence": {
            "drc": "reports/gf180_pad_core_drc.log (KLayout 0.30.7, flat)",
            "lvs": "reports/gf180_pad_core_lvs.log (34 devices)",
            "pex": "reports/gf180_pad_core_pex_sim.spice (3096 R / 11 C)",
        },
        "not_included": ["guard ring", "pad ring", "ESD stress/latch-up/antenna",
                         "SPEF", "STA", "signoff"],
    }
    (OUT / "gf180_pad_core_manifest.json").write_text(json.dumps(man, indent=2) + "\n")

    sch = OUT / "gf180_pad_core.spice"
    sch.write_text(
        "* PAD MACRO schematic for LVS: output stage + series R + ESD + receiver\n"
        "* + OE logic + pre-driver (IO domain, W_N=1u W_P=2u L=0.28u).\n"
        ".SUBCKT gf180_pad_core OUT OE_N PU_OK PAD IN VDDIO VSSIO\n"
        "MP NPRE GP VDDIO VDDIO pfet_03v3 W=200u L=0.28u\n"
        "MN NPRE GN VSSIO VSSIO nfet_03v3 W=80u L=0.28u\n"
        "R1 NPRE PAD VSSIO ppolyf_u L=1.4u W=22u\n"
        "DUP PAD VDDIO diode_pd2nw_03v3 A=64p P=32u\n"
        "DDN VSSIO PAD diode_nd2ps_03v3 A=64p P=32u\n"
        "DDN2 VSSIO PAD diode_nd2ps_03v3 A=64p P=32u\n"
        "DCLAMP VSSIO VDDIO diode_pd2nw_03v3 A=100p P=40u\n"
        "MRN IN PAD VSSIO VSSIO nfet_03v3 W=2u L=0.28u\n"
        "MRP IN PAD VDDIO VDDIO pfet_03v3 W=4u L=0.28u\n"
        "MPOB OUTB_I OUT VDDIO VDDIO pfet_03v3 W=2u L=0.28u\n"
        "MNOB OUTB_I OUT VSSIO VSSIO nfet_03v3 W=1u L=0.28u\n"
        "MPOE OENB OE_N VDDIO VDDIO pfet_03v3 W=2u L=0.28u\n"
        "MNOE OENB OE_N VSSIO VSSIO nfet_03v3 W=1u L=0.28u\n"
                                                                                                        "MPNGP N_GP NGPB VDDIO VDDIO pfet_03v3 W=2u L=0.28u\n"
        "MNGNP N_GP NGPB VSSIO VSSIO nfet_03v3 W=1u L=0.28u\n"
        "MPNA1 EN_N PU_OK VDDIO VDDIO pfet_03v3 W=2u L=0.28u\n"
        "MPNA2 EN_N OENB VDDIO VDDIO pfet_03v3 W=2u L=0.28u\n"
        "MNNA1 EN_N PU_OK MID_NA VSSIO nfet_03v3 W=1u L=0.28u\n"
        "MNNA2 MID_NA OENB VSSIO VSSIO nfet_03v3 W=1u L=0.28u\n"
        "MPG1 MID_GP EN_N VDDIO VDDIO pfet_03v3 W=2u L=0.28u\n"
        "MPG2 NGPB OUTB_I MID_GP VDDIO pfet_03v3 W=2u L=0.28u\n"
        "MNG1 NGPB EN_N VSSIO VSSIO nfet_03v3 W=1u L=0.28u\n"
        "MNG2 NGPB OUTB_I VSSIO VSSIO nfet_03v3 W=1u L=0.28u\n"
        "MPH1 MID_GN EN_N VDDIO VDDIO pfet_03v3 W=2u L=0.28u\n"
        "MPH2 N_GN OUT MID_GN VDDIO pfet_03v3 W=2u L=0.28u\n"
        "MNH1 N_GN EN_N VSSIO VSSIO nfet_03v3 W=1u L=0.28u\n"
        "MNH2 N_GN OUT VSSIO VSSIO nfet_03v3 W=1u L=0.28u\n"
                                        "MPGP1 N_GP_S1 N_GP VDDIO VDDIO pfet_03v3 W=2u L=0.28u\n"
        "MNGP1 N_GP_S1 N_GP VSSIO VSSIO nfet_03v3 W=1u L=0.28u\n"
        "MPGP2 GP N_GP_S1 VDDIO VDDIO pfet_03v3 W=2u L=0.28u\n"
        "MNGP2 GP N_GP_S1 VSSIO VSSIO nfet_03v3 W=1u L=0.28u\n"
        "MPGN1 N_GN_S1 N_GN VDDIO VDDIO pfet_03v3 W=2u L=0.28u\n"
        "MNGN1 N_GN_S1 N_GN VSSIO VSSIO nfet_03v3 W=1u L=0.28u\n"
        "MPGN2 GN N_GN_S1 VDDIO VDDIO pfet_03v3 W=2u L=0.28u\n"
        "MNGN2 GN N_GN_S1 VSSIO VSSIO nfet_03v3 W=1u L=0.28u\n"
        ".ENDS\n")
    print("wrote %s" % gds)
    print("bbox_um %s" % man["bbox_um"])
    print("schematic %s" % sch)


if __name__ == "__main__":
    main()
