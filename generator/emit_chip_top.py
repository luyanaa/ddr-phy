#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Chip-top assembly for the GF180 Class-S SDRAM PHY.

Places the hardened sdram_phy_core inside the 32-site gf180_pad_ring,
stitches the 30 signal pads to the core pins, builds the VDDIO/VSSIO ring
interconnect plus the core VDD/VSS straps, closes the chip-level seal ring,
and fills the empty interior with density dummy tiles.

This is a netlist-driven assembly generator, not a general-purpose P&R.
The site assignment lives in specs/pads/sdram_chip_padmap.yaml; this
script hard-codes the ring geometry measured from the signoff pad ring
(reports/pad_ring.md) and the core pin coordinates from its LEF.

Run with the KLayout Python (pya):
    klayout -b -r generator/emit_chip_top.py

Outputs:
    sch/pads/gf180mcuD/pcell/gf180mcu_sdram_chip_top.gds
"""
import heapq
import itertools
import math
import os
import re
import sys

import pya

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from gf180_pad_layout import L as LAYERS  # noqa: E402

RING_GDS = os.path.join(HERE, "..", "sch", "pads", "gf180mcuD", "pcell",
                        "gf180_pad_ring.gds")
CORE_GDS = os.path.join(HERE, "..", "flow", "runs",
                        "gf180-as-7t3v3-sdram_phy_core", "final", "gds",
                        "sdram_phy_core.gds")
OUT_GDS = os.path.join(HERE, "..", "sch", "pads", "gf180mcuD", "pcell",
                       "gf180mcu_sdram_chip_top.gds")
STD_GDS = os.path.join(HERE, "..", "pdks", "gf180mcuD", "libs.ref",
                       "gf180mcu_as_sc_mcu7t3v3", "gds",
                       "gf180mcu_as_sc_mcu7t3v3.gds")
INVERTER_CELL = "gf180mcu_as_sc_mcu7t3v3__inv_2"
METAL_LAYER_BY_NUMBER = {34: "Metal1", 36: "Metal2", 42: "Metal3",
                         46: "Metal4", 81: "Metal5"}
# ----------------------------------------------------------------------
# Geometry constants, um in die coordinates.  Measured, do not re-derive:
# reports/pad_ring.md + probe tables (generator/probe_*.py pattern).
# ----------------------------------------------------------------------
DIE = 1800.0
TILE_PITCH = 190.0
INNER = 210.16
CORE_W, CORE_H = 274.035, 291.955
CORE_X = (DIE - CORE_W) / 2.0
CORE_Y = (DIE - CORE_H) / 2.0
INVERTER_X = CORE_X + CORE_W + 5.0
INVERTER_Y = CORE_Y + 234.36 - 2.39

# core bbox in die coords with a small routing margin
CX0 = CORE_X - 3.0
CX1 = CORE_X + CORE_W + 3.0
CY0 = CORE_Y - 3.0
CY1 = CORE_Y + CORE_H + 3.0


def _pin_tables():
    rows = []
    for i in range(9):
        rows.append(dict(index=i, side="B"))
    for j in range(7):
        rows.append(dict(index=9 + j, side="R"))
    for i in range(9):
        rows.append(dict(index=16 + i, side="T"))
    for j in range(7):
        rows.append(dict(index=25 + j, side="L"))
    return rows


SITES = _pin_tables()


def core_pins():
    def pin(x, y, layer, edge):
        return dict(pos=(CORE_X + x, CORE_Y + y), layer=layer, edge=edge)

    p = {}
    east = {
        "cmd_o[0]": 236.6, "cmd_o[1]": 159.32, "cmd_o[2]": 225.4,
        "cmd_o[3]": 226.52, "cmd_o[4]": 232.12, "cmd_o[5]": 235.48,
        "cmd_o[6]": 153.72, "cmd_o[7]": 83.16, "cmd_o[8]": 143.64,
        "cmd_o[9]": 88.76, "cmd_o[10]": 110.04, "cmd_o[13]": 117.88,
        "cmd_o[14]": 61.88, "cmd_o[15]": 85.4, "cmd_o[16]": 64.12,
        "cmd_o[17]": 91.0, "cmd_o[18]": 106.68, "cmd_o[19]": 133.56,
        "cmd_o[20]": 172.76, "dq_o[0]": 241.08, "dq_o[3]": 243.32,
        "dq_o[4]": 239.96, "dq_o[7]": 179.48, "dq_oe": 234.36,
        "ck_o": 255.64, "clk": 52.64, "rst": 48.16,
    }
    for net, y in east.items():
        p[net] = pin(273.755, y, 42, "E")
    north = {"dq_o[1]": 188.44, "dq_o[2]": 187.32,
             "dq_o[5]": 178.36, "dq_o[6]": 155.96, "dq_i[0]": 132.44}
    for net, x in north.items():
        p[net] = pin(x, 291.675, 36, "N")
    south = {"cmd_o[11]": 260.12, "cmd_o[12]": 259.0, "dq_i[4]": 67.48}
    for net, x in south.items():
        p[net] = pin(x, 0.280, 36, "S")
    west = {"dq_i[1]": 227.64, "dq_i[2]": 132.44, "dq_i[3]": 66.36,
            "dq_i[5]": 176.12, "dq_i[6]": 226.52, "dq_i[7]": 161.56}
    for net, y in west.items():
        p[net] = pin(0.280, y, 42, "W")
    p["VDD"] = pin(23.04, 145.0, 46, "P")
    p["VSS"] = pin(26.34, 145.0, 46, "P")
    return p


CORE_PINS = core_pins()
ASSIGN = {
    0: "VDDIO", 1: "cmd_o[11]", 2: "cmd_o[12]", 3: "cmd_o[13]",
    4: "pad_ck", 5: "cmd_o[14]", 6: "cmd_o[15]", 7: "cmd_o[16]",
    8: "VSSIO",
    9: "dq[0]", 10: "dq[1]", 11: "dq[2]", 12: "dq[3]", 13: "dq[4]",
    14: "dq[5]", 15: "dq[6]", 16: "dq[7]",
    17: "cmd_o[20]", 18: "cmd_o[19]", 19: "cmd_o[18]", 20: "cmd_o[17]",
    21: "cmd_o[10]", 22: "cmd_o[9]", 23: "cmd_o[8]", 24: "cmd_o[7]",
    25: "cmd_o[6]", 26: "cmd_o[5]", 27: "cmd_o[4]", 28: "cmd_o[3]",
    29: "cmd_o[2]", 30: "cmd_o[1]", 31: "cmd_o[0]",
}

UM = 1000


def dbu(v):
    return int(round(v * UM))


def safe_cell_suffix(net):
    return re.sub(r"[^A-Za-z0-9_]+", "_", net)


class ChipTop:
    """GF180 chip assembly and obstacle-aware M5 maze router."""

    def __init__(self):
        self.ly = pya.Layout()
        self.ly.dbu = 0.001
        self.top = self.ly.create_cell("gf180mcu_sdram_chip_top")
        self.layers = {}
        for name, (ln, dt) in LAYERS.items():
            self.layers[name] = self.ly.layer(ln, dt)
        self.route_cells = {}
        self.occupied = {}
        self.net_labeled = set()

    def rect(self, layer, x0, y0, x1, y1):
        self.top.shapes(self.layers[layer]).insert(
            pya.Box(dbu(x0), dbu(y0), dbu(x1), dbu(y1)))

    def label(self, layer, text, x, y):
        self.top.shapes(self.layers[layer]).insert(
            pya.Text(text, pya.Trans(pya.Point(dbu(x), dbu(y)))))

    def instantiate(self):
        """Place the ring, hardened core, and OE polarity inverter."""
        self.ring_index = self._import_cell(RING_GDS)
        self.top.insert(pya.CellInstArray(self.ring_index,
                                          pya.Trans(pya.Point(0, 0))))
        self.core_index = self._import_cell(CORE_GDS)
        self.top.insert(pya.CellInstArray(
            self.core_index,
            pya.Trans(pya.Point(dbu(CORE_X), dbu(CORE_Y)))))
        self._place_inverter()
    def _import_cell(self, path, root_name=None):
        src = pya.Layout()
        src.read(path)
        root = src.top_cell() if root_name is None else src.cell(root_name)
        if root is None:
            raise RuntimeError("cell %s is absent from %s" %
                               (root_name, path))
        order = []
        seen = set()

        def visit(ci):
            if ci in seen:
                return
            seen.add(ci)
            cell = src.cell(ci)
            for inst in cell.each_inst():
                visit(inst.cell_index)
            order.append(ci)

        visit(root.cell_index())
        newidx = {}
        for ci in order:
            cell = src.cell(ci)
            nc = self.ly.create_cell(cell.name)
            newidx[ci] = nc.cell_index()
            for li in range(src.layers()):
                info = src.get_info(li)
                dst_li = self.ly.layer(info.layer, info.datatype)
                nc.shapes(dst_li).insert(cell.shapes(li))
            for inst in cell.each_inst():
                nc.insert(pya.CellInstArray(newidx[inst.cell_index],
                                            inst.trans))
        return newidx[root.cell_index()]

    def _load_inverter_pin_info(self):
        if getattr(self, "inverter_pins", None):
            return
        src = pya.Layout()
        src.read(STD_GDS)
        cell = src.cell(INVERTER_CELL)
        if cell is None:
            raise RuntimeError("missing standard-cell inverter " +
                               INVERTER_CELL)
        labels = {}
        # Well hookup labels live on the well label layers, not metal:
        #   VNW on (21,10), VPW on (204,10).  They tie to VDD/VSS rails
        #   respectively, so record them against the Metal1 layer for
        #   connection purposes.
        WELL_LABEL_LAYER = {21: "VNW", 204: "VPW"}
        for li in range(src.layers()):
            info = src.get_info(li)
            metal = METAL_LAYER_BY_NUMBER.get(info.layer)
            if info.datatype != 10:
                continue
            is_well = info.layer in WELL_LABEL_LAYER
            if metal is None and not is_well:
                continue
            for shape in cell.shapes(li).each():
                if shape.is_text() and shape.text.string in (
                        "A", "Y", "VDD", "VNW", "VPW", "VSS"):
                    pos = shape.text.trans.disp
                    labels.setdefault(shape.text.string, (
                        (pos.x * src.dbu, pos.y * src.dbu),
                        LAYERS["Metal1"][0]))
        required = {"A", "Y", "VDD", "VNW", "VPW", "VSS"}
        missing = required - set(labels)
        if missing:
            raise RuntimeError("inverter port labels missing: %s" %
                               ", ".join(sorted(missing)))
        self.inverter_local_pins = labels
        self.inverter_pins = {
            name: dict(pos=(INVERTER_X + values[0][0],
                            INVERTER_Y + values[0][1]),
                       layer=values[1], pin=name)
            for name, values in labels.items()
        }
        self.inverter_trans = pya.Trans(
            pya.Trans.R0, dbu(INVERTER_X), dbu(INVERTER_Y))

    def _place_inverter(self):
        self._load_inverter_pin_info()
        existing = self.ly.cell(INVERTER_CELL)
        if existing is not None:
            # The inverter cell is already present (pulled in transitively);
            # reuse it so we do not create a `$1`-suffixed duplicate.
            self.inverter_index = existing.cell_index()
        else:
            self.inverter_index = self._import_cell(STD_GDS, INVERTER_CELL)
        self.top.insert(pya.CellInstArray(self.inverter_index,
                                          self.inverter_trans))

    def _site_transform(self, site):
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

    def _pad_pin(self, site, pin):
        local = {"OUT": (-65.5, 55.5), "OE_N": (-62.5, 58.5),
                 "IN": (-10.55, -58.0)}[pin]
        trans = self._site_transform(site)
        point = trans * pya.Point(dbu(local[0]), dbu(local[1]))
        return point.x / float(UM), point.y / float(UM)

    def _wire_list(self):
        self._load_inverter_pin_info()
        wires = []

        def endpoint(kind, pin, pos, layer, site=None):
            return dict(kind=kind, pin=pin, pos=pos, layer=layer, site=site)

        def add(net, source, target, wire_class="signal"):
            wires.append(dict(net=net, source=source, target=target,
                              wire_class=wire_class))

        for site in SITES:
            assignment = ASSIGN[site["index"]]
            if assignment in ("VDDIO", "VSSIO"):
                continue
            if assignment.startswith("cmd_o"):
                core = CORE_PINS[assignment]
                add(assignment,
                    endpoint("pad", "OUT", self._pad_pin(site, "OUT"),
                             36, site),
                    endpoint("core", assignment, core["pos"], core["layer"]))
            elif assignment == "pad_ck":
                core = CORE_PINS["ck_o"]
                add("ck_o",
                    endpoint("pad", "OUT", self._pad_pin(site, "OUT"),
                             36, site),
                    endpoint("core", "ck_o", core["pos"], core["layer"]))
            else:
                bit = int(assignment[3])
                out_name = "dq_o[%d]" % bit
                out_pin = CORE_PINS[out_name]
                add(out_name,
                    endpoint("pad", "OUT", self._pad_pin(site, "OUT"),
                             36, site),
                    endpoint("core", out_name, out_pin["pos"],
                             out_pin["layer"]))
                in_name = "dq_i[%d]" % bit
                in_pin = CORE_PINS[in_name]
                add(in_name,
                    endpoint("pad", "IN", self._pad_pin(site, "IN"),
                             36, site),
                    endpoint("core", in_name, in_pin["pos"],
                             in_pin["layer"]))
                add("n_dq_oe_b",
                    endpoint("pad", "OE_N", self._pad_pin(site, "OE_N"),
                             36, site),
                    endpoint("inv", "Y", self.inverter_pins["Y"]["pos"],
                             self.inverter_pins["Y"]["layer"]))

        core_oe = CORE_PINS["dq_oe"]
        add("n_dq_oe",
            endpoint("core", "dq_oe", core_oe["pos"], core_oe["layer"]),
            endpoint("inv", "A", self.inverter_pins["A"]["pos"],
                     self.inverter_pins["A"]["layer"]))
        for pin in ("VDD", "VNW"):
            add("VDD",
                endpoint("inv", pin, self.inverter_pins[pin]["pos"],
                         self.inverter_pins[pin]["layer"]),
                endpoint("core", "VDD", CORE_PINS["VDD"]["pos"], 46),
                wire_class="power")
        for pin in ("VSS", "VPW"):
            add("VSS",
                endpoint("inv", pin, self.inverter_pins[pin]["pos"],
                         self.inverter_pins[pin]["layer"]),
                endpoint("core", "VSS", CORE_PINS["VSS"]["pos"], 46),
                wire_class="power")
        if sum(w["wire_class"] == "signal" for w in wires) != 47:
            raise RuntimeError("expected 47 signal routes including OE inverter")
        return wires

    def _region_for_gds(self, gds, layer_index, root_trans=None,
                        root_name=None):
        region = pya.Region()
        src = pya.Layout()
        src.read(gds)
        root = src.top_cell() if root_name is None else src.cell(root_name)
        if root is None:
            raise RuntimeError("cell %s is absent from %s" %
                               (root_name, gds))
        li = src.find_layer(*layer_index)
        if li is None or li < 0:
            return region
        it = root.begin_shapes_rec(li)
        while not it.at_end():
            try:
                poly = it.shape().polygon.transformed(it.trans())
                if root_trans is not None:
                    poly = poly.transformed(root_trans)
                region.insert(poly)
            except Exception:
                pass
            it.next()
        region.merge()
        return region

    def _build_obstructions(self):
        core_shift = pya.Trans(pya.Point(dbu(CORE_X), dbu(CORE_Y)))
        obstructions = {}
        for name in ("Metal1", "Metal2", "Metal3", "Metal4", "Metal5",
                     "Via1", "Via2", "Via3", "Via4", "Via5"):
            layer = LAYERS[name]
            region = self._region_for_gds(RING_GDS, layer)
            region += self._region_for_gds(CORE_GDS, layer, core_shift)
            region += self._region_for_gds(STD_GDS, layer,
                                           self.inverter_trans, INVERTER_CELL)
            region.merge()
            obstructions[name] = region
        self.obstructions = obstructions
        self.m5_keepout = obstructions["Metal5"].sized(dbu(1.2))

    def _inside_m5_keepout(self, x, y):
        x0, y0 = dbu(x), dbu(y)
        probe = pya.Region(pya.Box(x0, y0, x0 + 1, y0 + 1))
        return not (self.m5_keepout & probe).is_empty()

    def _connector_options(self, point, net):
        px, py = point
        rx, ry = int(math.floor(px + 0.5)), int(math.floor(py + 0.5))
        candidates = []
        for x in range(rx - 2, rx + 3):
            for y in range(ry - 2, ry + 3):
                if not (0 <= x <= int(DIE) and 0 <= y <= int(DIE)):
                    continue
                if self._inside_m5_keepout(x, y):
                    continue
                options = [
                    [(px, py), (float(x), py), (float(x), float(y))],
                    [(px, py), (px, float(y)), (float(x), float(y))]
                ]
                for points in options:
                    points = [p for n, p in enumerate(points)
                              if n == 0 or p != points[n - 1]]
                    if self._connector_clear(points, net):
                        candidates.append(((x - px) ** 2 + (y - py) ** 2,
                                           points, (x, y)))
                        break
        candidates.sort(key=lambda item: item[0])
        return [(points, root) for _, points, root in candidates]

    def _connector_clear(self, points, net):
        for a, b in zip(points, points[1:]):
            span = max(abs(b[0] - a[0]), abs(b[1] - a[1]))
            steps = max(1, int(math.ceil(span * 4)))
            for i in range(steps + 1):
                t = i / float(steps)
                x = a[0] + (b[0] - a[0]) * t
                y = a[1] + (b[1] - a[1]) * t
                if self._inside_m5_keepout(x, y):
                    return False
                nx, ny = int(round(x)), int(round(y))
                owners = self.occupied.get((nx, ny), set())
                if any(owner != net for owner in owners):
                    return False
        return True

    def _astar(self, start, goal, net):
        min_x = max(0, min(start[0], goal[0]) - 100)
        max_x = min(int(DIE), max(start[0], goal[0]) + 100)
        min_y = max(0, min(start[1], goal[1]) - 100)
        max_y = min(int(DIE), max(start[1], goal[1]) + 100)
        serial = itertools.count()
        h0 = abs(start[0] - goal[0]) + abs(start[1] - goal[1])
        frontier = [(h0, h0, next(serial), 0, start)]
        cost = {start: 0}
        parent = {}
        while frontier:
            _, _, _, current_cost, current = heapq.heappop(frontier)
            if current_cost != cost.get(current):
                continue
            if current == goal:
                path = [current]
                while current in parent:
                    current = parent[current]
                    path.append(current)
                path.reverse()
                return path
            x, y = current
            for nx, ny in ((x + 1, y), (x - 1, y),
                           (x, y + 1), (x, y - 1)):
                if nx < min_x or nx > max_x or ny < min_y or ny > max_y:
                    continue
                node = (nx, ny)
                owners = self.occupied.get(node, set())
                if any(owner != net for owner in owners):
                    continue
                if self._inside_m5_keepout(nx, ny):
                    continue
                new_cost = current_cost + 1
                if new_cost >= cost.get(node, 1 << 60):
                    continue
                cost[node] = new_cost
                parent[node] = current
                h = abs(nx - goal[0]) + abs(ny - goal[1])
                heapq.heappush(frontier, (new_cost + h, h, next(serial),
                                          new_cost, node))
        return None

    def _rect_in_cell(self, cell, layer, x0, y0, x1, y1):
        if x1 < x0:
            x0, x1 = x1, x0
        if y1 < y0:
            y0, y1 = y1, y0
        cell.shapes(self.layers[layer]).insert(
            pya.Box(dbu(x0), dbu(y0), dbu(x1), dbu(y1)))

    def _wire_segment(self, cell, layer, a, b, width):
        x0, y0 = a
        x1, y1 = b
        if abs(x0 - x1) < 1e-6:
            self._rect_in_cell(cell, layer, x0 - width / 2.0,
                               min(y0, y1), x0 + width / 2.0,
                               max(y0, y1))
        elif abs(y0 - y1) < 1e-6:
            self._rect_in_cell(cell, layer, min(x0, x1),
                               y0 - width / 2.0, max(x0, x1),
                               y0 + width / 2.0)
        else:
            raise RuntimeError("router emitted a non-Manhattan segment")

    def _draw_via_stack(self, cell, x, y, start_layer):
        size, enclosure = 0.26, 0.36
        if start_layer == 34:
            self._rect_in_cell(cell, "Metal1", x - enclosure / 2,
                               y - enclosure / 2, x + enclosure / 2,
                               y + enclosure / 2)
            self._rect_in_cell(cell, "Via1", x - size / 2, y - size / 2,
                               x + size / 2, y + size / 2)
            start_layer = 36
        if start_layer == 36:
            self._rect_in_cell(cell, "Metal2", x - enclosure / 2,
                               y - enclosure / 2, x + enclosure / 2,
                               y + enclosure / 2)
            self._rect_in_cell(cell, "Via2", x - size / 2, y - size / 2,
                               x + size / 2, y + size / 2)
            start_layer = 42
        if start_layer == 42:
            self._rect_in_cell(cell, "Metal3", x - enclosure / 2,
                               y - enclosure / 2, x + enclosure / 2,
                               y + enclosure / 2)
            self._rect_in_cell(cell, "Via3", x - size / 2, y - size / 2,
                               x + size / 2, y + size / 2)
            start_layer = 46
        if start_layer == 46:
            self._rect_in_cell(cell, "Metal4", x - enclosure / 2,
                               y - enclosure / 2, x + enclosure / 2,
                               y + enclosure / 2)
            self._rect_in_cell(cell, "Via4", x - size / 2, y - size / 2,
                               x + size / 2, y + size / 2)
        self._rect_in_cell(cell, "Metal5", x - enclosure / 2,
                           y - enclosure / 2, x + enclosure / 2,
                           y + enclosure / 2)

    def _via_point(self, endpoint):
        x, y = endpoint["pos"]
        if endpoint["kind"] == "pad":
            return x, y
        if endpoint["kind"] == "core":
            if x > CORE_X + CORE_W - 0.5:
                return x + 3.0, y
            if x < CORE_X + 0.5:
                return x - 3.0, y
            if y > CORE_Y + CORE_H - 0.5:
                return x, y + 3.0
            if y < CORE_Y + 0.5:
                return x, y - 3.0
        return x, y

    # ------------------------------------------------------------------
    # Cavity-constrained deterministic router.
    #
    # Measured facts (probe scripts, do not re-derive):
    #   * the cavity (x/y INNER..DIE-INNER) is empty of ring metal on every
    #     layer; the ring power metal hugs the die edge and the bond pads,
    #     so the cavity-facing entry zone (just outside INNER) is clear.
    #   * core M5 is negligible; core M4 power straps stay inside the core
    #     bbox.  Routes therefore never enter the core interior - they stop
    #     at the edge pin, approached perpendicular to that edge.
    #   * horizontal runs on Metal4, vertical runs on Metal5.  A vertical
    #     M5 trunk crossing a horizontal M4 stub of another net is layer-
    #     safe.  Same-layer collisions are avoided by giving every net a
    #     unique channel coordinate.
    # ------------------------------------------------------------------

    def _endpoint_xy(self, ep):
        return float(ep["pos"][0]), float(ep["pos"][1])

    def _core_edge(self, ep):
        x, y = self._endpoint_xy(ep)
        if x > CORE_X + CORE_W - 2.0:
            return "E"
        if x < CORE_X + 2.0:
            return "W"
        if y > CORE_Y + CORE_H - 2.0:
            return "N"
        if y < CORE_Y + 2.0:
            return "S"
        return "E"

    def _route_signal(self, wire):
        net = wire["net"]
        source, target = wire["source"], wire["target"]
        cell = self.route_cells.get(net)
        if cell is None:
            cell = self.ly.create_cell("chiproute_" + safe_cell_suffix(net))
            self.route_cells[net] = cell
            self.top.insert(pya.CellInstArray(cell.cell_index(),
                                              pya.Trans(pya.Point(0, 0))))
        if source["kind"] == "pad":
            self._route_pad_net(wire, cell, source, target)
        elif target["kind"] == "pad":
            self._route_pad_net(wire, cell, target, source)
        else:
            self._route_local_net(wire, cell, source, target)

    # channel coordinate allocator: unique offsets so same-layer trunks of
    # different nets never share a coordinate.
    def _chan(self, net, base, step=1.2):
        idx = getattr(self, "_chan_ctr", 0)
        self._chan_ctr = idx + 1
        return base + step * idx


    # ------------------------------------------------------------------
    # Grid A* maze router (Metal4 horizontal / Metal5 vertical).
    # ------------------------------------------------------------------
    MAZE_GRID = 3.0     # um pitch
    MAZE_HALF = 0.75    # half-width + spacing margin for blockage probing


    CXE = CORE_X + CORE_W   # core east edge x
    CXW = CORE_X            # core west edge x
    CYN = CORE_Y + CORE_H   # core north edge y
    CYS = CORE_Y            # core south edge y

    def _escape_target(self, cx, cy):
        """Return (tx, ty, face) — a cavity-side point a few um outside the
        core edge nearest to the pin, plus the axis direction to the pin."""
        ESC = 3.0
        d_east = abs(cx - self.CXE)
        d_west = abs(cx - self.CXW)
        d_north = abs(cy - self.CYN)
        d_south = abs(cy - self.CYS)
        m = min(d_east, d_west, d_north, d_south)
        if m == d_east:
            return (self.CXE + ESC, cy, "E")
        if m == d_west:
            return (self.CXW - ESC, cy, "W")
        if m == d_north:
            return (cx, self.CYN + ESC, "N")
        return (cx, self.CYS - ESC, "S")

    def _maze_build_grid(self):
        """Pre-rasterize imported-metal blockage into per-layer boolean grids
        keyed by (gx, gy) for O(1) lookup.  Inflated by MAZE_HALF."""
        G = self.MAZE_GRID
        lo = int(10.0 / G) - 2
        hi = int((DIE - 10.0) / G) + 2
        self._maze_lo = lo
        self._maze_hi = hi
        self._maze_grid = {"Metal4": set(), "Metal5": set()}
        for layer in ("Metal4", "Metal5"):
            imp = self.obstructions.get(layer)
            blocked = self._maze_grid[layer]
            if imp is None:
                continue
            h = self.MAZE_HALF
            for box in imp.merged().each():
                b = box.bbox()
                x0 = (b.p1.x / float(UM)) - h
                x1 = (b.p2.x / float(UM)) + h
                y0 = (b.p1.y / float(UM)) - h
                y1 = (b.p2.y / float(UM)) + h
                gx0 = int(x0 / G) - 1
                gx1 = int(x1 / G) + 1
                gy0 = int(y0 / G) - 1
                gy1 = int(y1 / G) + 1
                # only rasterize within cavity band to bound memory
                gx0 = max(gx0, lo); gx1 = min(gx1, hi)
                gy0 = max(gy0, lo); gy1 = min(gy1, hi)
                for gx in range(gx0, gx1 + 1):
                    cx = gx * G
                    if cx + h < x0 or cx - h > x1:
                        continue
                    for gy in range(gy0, gy1 + 1):
                        cy = gy * G
                        if cy + h < y0 or cy - h > y1:
                            continue
                        blocked.add((gx, gy))

    def _maze_blocked(self, layer, x, y, selfnet):
        G = self.MAZE_GRID
        gx = int(round(x / G))
        gy = int(round(y / G))
        terms = getattr(self, "_maze_terms", None)
        if terms is not None and (gx, gy) in terms:
            # terminal region: imported pin metal is the target, not an obstacle,
            # but other nets' routed metal is still a hard block.
            routed = self._maze_routed_pts.get(layer)
            if routed is not None and (gx, gy) in routed:
                return True
            return False
        grid = self._maze_grid.get(layer)
        if grid is not None and (gx, gy) in grid:
            return True
        routed = self._maze_routed_pts.get(layer)
        if routed is not None and (gx, gy) in routed:
            return True
        return False

    def _maze_route(self, net, start, end):
        """A* over (gx, gy, layer) with negotiated-congestion costs.
        Returns list of (x, y, layer) grid points or None."""
        import heapq
        G = self.MAZE_GRID
        sx, sy = start
        ex, ey = end
        gs = (int(round(sx / G)), int(round(sy / G)))
        ge = (int(round(ex / G)), int(round(ey / G)))
        layers = {0: "Metal4", 1: "Metal5"}
        # region-limit the search to a box around the endpoints + margin;
        # west-face nets still span the die but most nets are local.
        MARGIN = 320.0   # um, enough to detour around the core
        x0 = min(sx, ex) - MARGIN
        x1 = max(sx, ex) + MARGIN
        y0 = min(sy, ey) - MARGIN
        y1 = max(sy, ey) + MARGIN
        x0 = max(10.0, x0); y0 = max(10.0, y0)
        x1 = min(DIE - 10.0, x1); y1 = min(DIE - 10.0, y1)
        glo = int(x0 / G) - 1
        ghi = int(x1 / G) + 1
        gloy = int(y0 / G) - 1
        ghiy = int(y1 / G) + 1
        cong = getattr(self, "_cong", {})

        # terminal cells (and neighbours) are legal even on pin metal.
        terms = set()
        for gc in (gs, ge):
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    terms.add((gc[0] + dx, gc[1] + dy))
        self._maze_terms = terms

        def heur(a):
            return (abs(a[0] - ge[0]) + abs(a[1] - ge[1])) * G

        def cellcost(lay, gx, gy):
            # imported metal is a hard block outside terminals
            if self._hard_blocked(layers[lay], gx, gy, terms):
                return None
            base = 0.0
            c = cong.get((lay, gx, gy), 0)
            return base + c

        startnode = (gs[0], gs[1], 1)
        openh = [(heur(startnode), 0.0, startnode)]
        came = {startnode: None}
        best = {startnode: 0.0}
        target = None
        it = 0
        while openh and it < 120000:
            it += 1
            f, g, node = heapq.heappop(openh)
            if (node[0], node[1]) == ge:
                target = node
                break
            if g > best.get(node, 1e18) + 1e-9:
                continue
            gx, gy, lay = node
            for dgx, dgy, dlay, base in (
                    (1, 0, lay, G), (-1, 0, lay, G),
                    (0, 1, lay, G), (0, -1, lay, G),
                    (0, 0, 1 - lay, 1.6)):
                ngx, ngy, nlay = gx + dgx, gy + dgy, dlay
                if not (glo <= ngx <= ghi and gloy <= ngy <= ghiy):
                    continue
                cc = cellcost(nlay, ngx, ngy)
                if cc is None:
                    continue
                pen = base + cc
                if dlay == lay:
                    if nlay == 0 and dgy != 0:
                        pen += G * 1.2
                    if nlay == 1 and dgx != 0:
                        pen += G * 1.2
                nn = (ngx, ngy, nlay)
                ng = g + pen
                if ng < best.get(nn, 1e18) - 1e-9:
                    best[nn] = ng
                    came[nn] = node
                    heapq.heappush(openh, (ng + heur(nn), ng, nn))
        if target is None:
            return None
        path = []
        node = target
        while node is not None:
            path.append((node[0] * G, node[1] * G, node[2]))
            node = came[node]
        path.reverse()
        return path

    def _hard_blocked(self, layer, gx, gy, terms):
        """Hard block for imported metal and for other nets' routed metal.
        Sequential routing: each net avoids everything already committed."""
        if (gx, gy) in terms:
            pass
        else:
            grid = self._maze_grid.get(layer)
            if grid is not None and (gx, gy) in grid:
                return True
        routed = self._maze_routed_pts.get(layer)
        if routed is not None and (gx, gy) in routed:
            return True
        return False

    def _maze_draw(self, net, cell, path):
        """Draw a maze path as wires + vias, and mark routed blockage."""
        if not path:
            return False
        layers = {0: "Metal4", 1: "Metal5"}
        # collapse collinear runs
        pts = [path[0]]
        for i in range(1, len(path)):
            pts.append(path[i])
        # draw segment by segment with layer changes
        for i in range(len(pts) - 1):
            x0, y0, l0 = pts[i]
            x1, y1, l1 = pts[i + 1]
            if l0 == l1:
                self._wire_segment(cell, layers[l0], (x0, y0), (x1, y1), 0.44)
                # accumulate blockage
                gg = self.MAZE_GRID
                ax, bx = sorted((x0, x1)); ay, by = sorted((y0, y1))
                gx0 = int(round(ax / gg)); gx1 = int(round(bx / gg))
                gy0 = int(round(ay / gg)); gy1 = int(round(by / gg))
                for ggx in range(min(gx0, gx1) - 1, max(gx0, gx1) + 2):
                    for ggy in range(min(gy0, gy1) - 1, max(gy0, gy1) + 2):
                        self._maze_routed_pts[layers[l0]].add((ggx, ggy))
            else:
                # layer change: place a via at this grid point
                if 0 in (l0, l1) and 1 in (l0, l1):
                    self._via_m5_to_m4(cell, x0, y0)
        return True

    def _route_pad_net(self, wire, cell, pad_ep, core_ep):
        """Draw the negotiated-congestion maze path for this net, with terminal
        via stacks and the core-edge escape stub."""
        net = wire["net"]
        px, py = self._endpoint_xy(pad_ep)
        cx, cy = self._endpoint_xy(core_ep)
        pad_layer = pad_ep["layer"]
        core_layer = core_ep["layer"]

        if net not in self.net_labeled:
            cell.shapes(self.layers["Metal5_label"]).insert(
                pya.Text(net, pya.Trans(pya.Point(dbu(px), dbu(py + 4.0)))))
            self.net_labeled.add(net)

        # terminal via stacks at both pins
        self._draw_via_stack(cell, px, py, pad_layer)
        self._draw_via_stack(cell, cx, cy, core_layer)

        entry = getattr(self, "_neg_paths", {}).get(net)
        if entry is None:
            # not in negotiated set (shouldn't happen for pad nets): escape direct
            ex, ey, face = self._escape_target(cx, cy)
            path = self._maze_route(net, (px, py), (ex, ey))
        else:
            path, _pe, _ce, esc = entry
            ex, ey, face = esc

        if path is not None:
            self._maze_draw(net, cell, path)
            # escape stub from escape point into the core pin
            if face in ("E", "W"):
                self._wire_segment(cell, "Metal4", (ex, ey), (cx, ey), 0.44)
                if abs(ey - cy) > 1e-6:
                    self._via_m4_to_m5(cell, cx, ey)
                    self._wire_segment(cell, "Metal5", (cx, ey), (cx, cy), 0.44)
                    self._via_m5_to_m4(cell, cx, cy)
            else:
                self._wire_segment(cell, "Metal5", (ex, ey), (ex, cy), 0.44)
                if abs(ex - cx) > 1e-6:
                    self._via_m5_to_m4(cell, ex, cy)
                    self._wire_segment(cell, "Metal4", (ex, cy), (cx, cy), 0.44)
                    self._via_m4_to_m5(cell, cx, cy)
        # connect the core pin into its via stack
        self._connect_core_pin(cell, core_ep, cx, cy)

    def _route_local_net(self, wire, cell, a_ep, b_ep):
        ax, ay = self._endpoint_xy(a_ep)
        bx, by = self._endpoint_xy(b_ep)
        net = wire["net"]
        if net not in self.net_labeled:
            cell.shapes(self.layers["Metal5_label"]).insert(
                pya.Text(net, pya.Trans(pya.Point(dbu(ax), dbu(ay + 4.0)))))
            self.net_labeled.add(net)
        self._draw_via_stack(cell, ax, ay, a_ep["layer"])
        self._wire_segment(cell, "Metal5", (ax, ay), (ax, by), 0.44)
        self._via_m5_to_m4(cell, ax, by)
        self._wire_segment(cell, "Metal4", (ax, by), (bx, by), 0.44)
        self._via_m4_to_layer(cell, bx, by, b_ep["layer"])
        self._connect_core_pin(cell, b_ep, bx, by)

    def _connect_core_pin(self, cell, core_ep, vx, vy):
        px, py = self._endpoint_xy(core_ep)
        # Full via stack at the pin position from its native layer up to M5,
        # so the terminal is strapped onto the routing grid.
        self._draw_via_stack(cell, px, py, core_ep["layer"])
        layer = METAL_LAYER_BY_NUMBER[core_ep["layer"]]
        if abs(px - vx) > 1e-6 or abs(py - vy) > 1e-6:
            self._wire_segment(cell, layer, (vx, vy), (px, py), 0.28)

    def _via_m5_to_m4(self, cell, x, y):
        size, enc = 0.26, 0.36
        self._rect_in_cell(cell, "Metal4", x - enc / 2, y - enc / 2,
                           x + enc / 2, y + enc / 2)
        self._rect_in_cell(cell, "Via4", x - size / 2, y - size / 2,
                           x + size / 2, y + size / 2)
        self._rect_in_cell(cell, "Metal5", x - enc / 2, y - enc / 2,
                           x + enc / 2, y + enc / 2)

    def _via_m4_to_m5(self, cell, x, y):
        self._via_m5_to_m4(cell, x, y)

    def _via_m3_to_m5(self, cell, x, y):
        # stack M3 -> Via3 -> M4 -> Via4 -> M5
        size, enc = 0.26, 0.36
        self._rect_in_cell(cell, "Metal3", x - enc / 2, y - enc / 2,
                           x + enc / 2, y + enc / 2)
        self._rect_in_cell(cell, "Via3", x - size / 2, y - size / 2,
                           x + size / 2, y + size / 2)
        self._rect_in_cell(cell, "Metal4", x - enc / 2, y - enc / 2,
                           x + enc / 2, y + enc / 2)
        self._rect_in_cell(cell, "Via4", x - size / 2, y - size / 2,
                           x + size / 2, y + size / 2)
        self._rect_in_cell(cell, "Metal5", x - enc / 2, y - enc / 2,
                           x + enc / 2, y + enc / 2)

    def _via_m4_to_layer(self, cell, x, y, layer):
        size, enc = 0.26, 0.36
        self._rect_in_cell(cell, "Metal4", x - enc / 2, y - enc / 2,
                           x + enc / 2, y + enc / 2)
        if layer == 42:  # Metal3
            self._rect_in_cell(cell, "Via3", x - size / 2, y - size / 2,
                               x + size / 2, y + size / 2)
            self._rect_in_cell(cell, "Metal3", x - enc / 2, y - enc / 2,
                               x + enc / 2, y + enc / 2)
        elif layer == 36:  # Metal2
            self._rect_in_cell(cell, "Via3", x - size / 2, y - size / 2,
                               x + size / 2, y + size / 2)
            self._rect_in_cell(cell, "Metal3", x - enc / 2, y - enc / 2,
                               x + enc / 2, y + enc / 2)
            self._rect_in_cell(cell, "Via2", x - size / 2, y - size / 2,
                               x + size / 2, y + size / 2)
            self._rect_in_cell(cell, "Metal2", x - enc / 2, y - enc / 2,
                               x + enc / 2, y + enc / 2)

    def _power_cell(self, net):
        name = "chiproute_" + safe_cell_suffix(net)
        cell = self.ly.create_cell(name)
        self.route_cells[net] = cell
        self.top.insert(pya.CellInstArray(cell.cell_index(),
                                          pya.Trans(pya.Point(0, 0))))
        return cell

    def _power(self):
        # Independent pad-ring supply meshes; core VDD/VSS stay on their
        # schematic nets and feed the inverter through explicit signal routes.
        vdd = self._power_cell("VDDIO")
        for x0, y0, x1, y1 in (
                (38.0, 38.0, 1762.0, 38.0),
                (38.0, 1762.0, 1762.0, 1762.0),
                (38.0, 38.0, 38.0, 1762.0),
                (1762.0, 38.0, 1762.0, 1762.0)):
            self._wire_segment(vdd, "Metal3", (x0, y0), (x1, y1), 4.0)
        vdd.shapes(self.layers["Metal3_label"]).insert(
            pya.Text("VDDIO", pya.Trans(pya.Point(dbu(50), dbu(38)))))

        vss = self._power_cell("VSSIO")
        for x0, y0, x1, y1 in (
                (38.0, 140.0, 1762.0, 140.0),
                (38.0, 1660.0, 1762.0, 1660.0),
                (140.0, 140.0, 140.0, 1660.0),
                (1660.0, 140.0, 1660.0, 1660.0)):
            self._wire_segment(vss, "Metal4", (x0, y0), (x1, y1), 4.0)
        vss.shapes(self.layers["Metal4_label"]).insert(
            pya.Text("VSSIO", pya.Trans(pya.Point(dbu(150), dbu(140)))))

    def _top_labels(self):
        for site in SITES:
            assignment = ASSIGN[site["index"]]
            if assignment in ("VDDIO", "VSSIO"):
                continue
            if assignment == "pad_ck":
                net = "pad_ck"
            elif assignment.startswith("cmd_o"):
                net = "pad_cmd" + assignment[len("cmd_o"):]
            else:
                net = "pad_dq" + assignment[len("dq"):]
            point = self._site_transform(site) * pya.Point(
                dbu(0.0), dbu(0.0))
            self.label("Metal2_label", net, point.x / float(UM),
                       point.y / float(UM))
        self.label("Metal3_label", "VDDIO", 50.0, 38.0)
        self.label("Metal4_label", "VSSIO", 150.0, 140.0)
        self.label("Metal4_label", "VDD", CORE_X + 23.04, CORE_Y + 145.0)
        self.label("Metal4_label", "VSS", CORE_X + 26.34, CORE_Y + 145.0)

    def _pad_net_endpoints(self, wire):
        """Return (pad_ep, core_ep) ordered for a pad net, else None."""
        s, t = wire["source"], wire["target"]
        if s["kind"] == "pad":
            return s, t
        if t["kind"] == "pad":
            return t, s
        return None

    def _net_cells_used(self, path):
        """Set of (layer, gx, gy) cells a path occupies, for congestion."""
        G = self.MAZE_GRID
        used = set()
        for i in range(len(path) - 1):
            x0, y0, l0 = path[i]
            x1, y1, l1 = path[i + 1]
            if l0 != l1:
                continue
            gx0 = int(round(x0 / G)); gx1 = int(round(x1 / G))
            gy0 = int(round(y0 / G)); gy1 = int(round(y1 / G))
            for gx in range(min(gx0, gx1), max(gx0, gx1) + 1):
                for gy in range(min(gy0, gy1), max(gy0, gy1) + 1):
                    used.add((l0, gx, gy))
        return used

    def route(self):
        """Negotiated-congestion maze routing, then draw + power meshes."""
        wires = self._wire_list()
        self._build_obstructions()
        self._maze_routed_pts = {"Metal4": set(), "Metal5": set()}
        self._maze_build_grid()
        self._cong = {}

        padwires = []
        for wire in wires:
            if wire["wire_class"] != "signal":
                continue
            ep = self._pad_net_endpoints(wire)
            if ep is not None:
                padwires.append((wire, ep[0], ep[1]))

        # negotiated-congestion iterations (PathFinder):
        # each iteration re-routes every net sequentially, committing occupancy
        # as it goes; history cost penalises cells that were contended.
        NITER = 8
        paths = {}
        for it in range(NITER):
            self._maze_routed_pts = {"Metal4": set(), "Metal5": set()}
            occ = {}
            newpaths = {}
            fails = 0
            for wire, pad_ep, core_ep in padwires:
                net = wire["net"]
                px, py = self._endpoint_xy(pad_ep)
                cx, cy = self._endpoint_xy(core_ep)
                ex, ey, face = self._escape_target(cx, cy)
                path = self._maze_route(net, (px, py), (ex, ey))
                if path is None:
                    fails += 1
                    continue
                newpaths[net] = (path, pad_ep, core_ep, (ex, ey, face))
                used = self._net_cells_used(path)
                for cellkey in used:
                    occ[cellkey] = occ.get(cellkey, 0) + 1
                    # commit so later nets in THIS iteration avoid it
                    lay = "Metal4" if cellkey[0] == 0 else "Metal5"
                    self._maze_routed_pts[lay].add((cellkey[1], cellkey[2]))
            paths = newpaths
            self._neg_paths = newpaths
            over = sum(1 for v in occ.values() if v > 1)
            print("pf iter %d: %d overused cells, %d unrouted" % (it, over, fails))
            if over == 0 and fails == 0:
                break
            # history cost on contended cells
            for cellkey, v in occ.items():
                if v > 1:
                    self._cong[cellkey] = self._cong.get(cellkey, 0.0) + 1.0

        # draw final paths
        signal_count = 0
        power_count = 0
        for wire in wires:
            self._route_signal(wire)
            if wire["wire_class"] == "signal":
                signal_count += 1
            else:
                power_count += 1
        self._power()
        self._top_labels()
        print("signal wires routed: %d; power connections: %d" %
              (signal_count, power_count))
        print("pad-ring meshes: VDDIO/M3, VSSIO/M4")

    def write(self):
        os.makedirs(os.path.dirname(OUT_GDS), exist_ok=True)
        self.ly.write(OUT_GDS)
        print("wrote", OUT_GDS)


def main():
    ct = ChipTop()
    ct.instantiate()
    ct.route()
    ct.write()


if __name__ == "__main__":
    main()

