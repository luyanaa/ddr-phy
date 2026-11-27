# SPDX-License-Identifier: Apache-2.0
"""Build the SG13G2 DQ macro and its device-level LVS reference.

Run with KLayout's Python (pya). Geometry coordinates are integer nm; the
SG13G2 drawing grid is 5 nm. M1 is local device metal, M2 collects the
fingers, M3 escapes each terminal to its row's M4 channel, and M5 joins rows.
"""

import json
import os
import re
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from statistics import median

import pya

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from ihp130_dq_devices import build_devices

TOP = "ihp130_sstl2_dq"
SCHEMATIC = HERE.parent / "sch/pads/ihp130/sstl2_dq.spice"
SCHEMATIC_PORTS = "OUT OE IN PAD VREF PU_OK VDD VSS VDDIO VSSIO".split()
PORTS = [p for p in SCHEMATIC_PORTS if p != "VSS"]
PORT_EDGE_TOP = {"PAD", "VSSIO", "VDDIO"}
DRIVE_NETS = {"DRIVER", "PAD", "VDDIO", "VSSIO"}
DRIVE_ROWS = {"XDRVH", "XESDHI"}
RX_LOCAL = {"RX_LEVEL", "SENSE", "MIRROR", "DEC_B"}
WIDE_RISER = 1260
VIA_PITCH = 430
METAL = {1: 8, 2: 10, 3: 30, 4: 50, 5: 67}
VIA = {1: 19, 2: 29, 3: 49, 4: 66}
TERMINALS = {
    **{f"sg13_{oxide}_{pol}mos": ("D", "G", "S", "B")
       for oxide in ("hv", "lv") for pol in ("n", "p")},
    "rhigh": ("R1", "R2", "B"),
    "rppd": ("R1", "R2", "B"),
    "diodevdd_2kv": ("VDD", "PAD", "VSS"),
    "diodevss_2kv": ("VDD", "PAD", "VSS"),
}
# Circuit-aware placement: keep the differential devices and the last
# predrivers beside their loads. Every instance must belong to one row.
ROWS = (
    ("XRDOWN", "XDOWN", "XRXB0", "XRXB1"),
    ("XRBIAS", "XBIAS", "XTAIL", "XRP", "XRR", "XLP", "XLR", "XDET"),
    ("XDATA", "XOE"),
    ("XUP", "XDN", "XGUARD", "XEN"),
    ("XPPRE", "XPG", "XNG"),
    ("XDRVH", "XRDRIVER", "XDRVL"),
    ("XESDHI", "XESDLO"),
)


@dataclass(frozen=True)
class Instance:
    path: tuple[str, ...]
    key: tuple[str, float, float, int]
    nets: tuple[str, ...]


def fields(tokens):
    args = []
    params = {}
    for tok in tokens:
        if "=" in tok:
            key, val = tok.split("=", 1)
            params[key.lower()] = val.lower()
        elif tok.lower() != "params:":
            args.append(tok)
    return args, params


def microns(text):
    match = re.fullmatch(r"(\d+(?:\.\d*)?|\.\d+)([un])", text)
    if not match:
        raise ValueError(f"expected a dimension with a u/n suffix, got {text!r}")
    return float(match[1]) / (1000 if match[2] == "n" else 1)


def instances():
    circuits = {}
    active = None
    for line in SCHEMATIC.read_text().splitlines():
        if not line.strip() or line.lstrip().startswith("*"):
            continue
        tokens = line.split()
        if tokens[0].lower() == ".subckt":
            pins, params = fields(tokens[2:])
            active = []
            circuits[tokens[1].lower()] = (pins, params, active)
        elif tokens[0].lower() == ".ends" and active is not None:
            active = None
        elif active is not None and tokens[0].upper().startswith("X"):
            args, params = fields(tokens[1:])
            active.append((tokens[0], args[:-1], args[-1].lower(), params))
        else:
            raise ValueError(f"unsupported schematic record: {line!r}")

    def expand(model, path, nets, overrides):
        pins, defaults, calls = circuits[model]
        if len(pins) != len(nets) or not overrides.keys() <= defaults.keys():
            raise ValueError(f"wrong subcircuit pins/parameters at {path}")
        mapped = dict(zip(pins, nets))
        defaults = defaults | overrides
        for name, nodes, called, raw in calls:
            here = (*path, name)
            args = tuple(mapped.get(n, "_".join((*path, n))) for n in nodes)
            params = {p: defaults[v[1:-1]] if v.startswith("{") else v for p, v in raw.items()}
            if called in circuits:
                yield from expand(called, here, args, params)
            else:
                if len(args) != len(TERMINALS[called]) or params.keys() - {"w", "l", "ng"}:
                    raise ValueError(f"wrong device pins/parameters at {here}")
                key = (called, microns(params["w"]), microns(params["l"]), int(params.get("ng", "1"))) \
                    if params else (called, 0., 0., 1)
                yield Instance(here, key, args)

    if circuits[TOP][0] != SCHEMATIC_PORTS:
        raise ValueError("DQ schematic pin contract changed")
    # The original fixture connects VSS and VSSIO together. Expose their
    # actual common substrate return, not two implicitly shorted LVS pins.
    return list(expand(TOP, (), ["VSSIO" if p == "VSS" else p for p in SCHEMATIC_PORTS], {}))


def physical_fingers(devices):
    """Split fractional finger widths without changing total channel width."""
    for dev in devices:
        model, width, length, fingers = dev.key
        if not model.endswith("mos"):
            yield dev
            continue
        # Magic draws a centered channel: both edges are on the 5 nm grid.
        slots, remainder = divmod(round(width * 100), fingers)
        if not remainder:
            yield dev
            continue
        groups = ((slots, fingers - remainder), (slots + 1, remainder))
        for i, (finger_width, count) in enumerate(groups):
            yield Instance((*dev.path, f"grid{i}"),
                           (model, finger_width * count / 100, length, count),
                           dev.nets)


def cdl_reference(devices):
    text = ["* Golden DQ schematic flattened to SG13G2 LVS device syntax.",
            "* VSS and VSSIO share the physical VSSIO port.",
            f".SUBCKT {TOP} {' '.join(PORTS)}"]
    for dev in devices:
        model, width, length, _ = dev.key
        if model.endswith("mos"):
            kind, opts = "M", f"W={width:g}u L={length:g}u"
        elif model.startswith("diode"):
            kind, opts = "D", "m=1"
        else:
            kind, opts = "R", f"w={width:g}u l={length:g}u m=1"
        text.append(f"{kind}{'_'.join(dev.path)} {' '.join(dev.nets)} {model} {opts}")
    return "\n".join([*text, f".ENDS {TOP}", ""])


def grid(n):
    return 5 * round(n / 5)


def wide(net):
    return {"VSSIO": 2800, "VDDIO": 2200, "VDD": 1200, "PAD": 1800, "DRIVER": 1800}.get(net, 520)


def channel_width(net, drive_row):
    if drive_row and net in DRIVE_NETS:
        return 1960
    return min(1100, wide(net))


class Drawing:
    def __init__(self, layout, top):
        self.layout, self.top = layout, top
        self.rc_labels = {}

    def box(self, number, x0, y0, x1, y1, dtype=0):
        self.top.shapes(self.layout.layer(number, dtype)).insert(pya.Box(x0, y0, x1, y1))

    def wire(self, metal, x0, y0, x1, y1, width, min_length=0):
        assert x0 == x1 or y0 == y1, "non-Manhattan route"
        r = width // 2
        xa, xb = sorted((x0, x1))
        ya, yb = sorted((y0, y1))
        if ya == yb:
            stretch = max(0, (min_length - (xb - xa) - width + 9) // 10 * 5)
            xa, xb = xa - stretch, xb + stretch
        self.box(METAL[metal], xa - r, ya - r, xb + r, yb + r)

    def cut(self, metal, x, y):
        self.box(VIA[metal], x - 95, y - 95, x + 95, y + 95)

    def cut_array(self, metal, x, y, columns, rows):
        for c in range(columns):
            for r in range(rows):
                self.cut(metal, x + (2*c - columns + 1) * VIA_PITCH // 2,
                         y + (2*r - rows + 1) * VIA_PITCH // 2)

    def probe(self, net, metal, x, y):
        if net in self.rc_labels:
            raise ValueError(f"duplicate RC probe {net}")
        self.rc_labels[net] = (x, y, metal)

    def pin(self, net, x, y, width):
        layer = METAL[5]
        r = width // 2
        self.wire(5, x, y, x, y, width)
        self.box(layer, x - r, y - r, x + r, y + r, 2)
        self.top.shapes(self.layout.layer(layer, 25)).insert(pya.Text(net, pya.Trans(x, y)))

    def guard(self, left, bottom, right, top, ground_x):
        # Continuous contacted p+ outside the device wells. No connection is
        # inferred from its name; the ground drop is real at both ends.
        for layer, width in ((1, 800), (14, 1400), (8, 960)):
            r = width // 2
            self.box(layer, left - r, bottom - r, right + r, bottom + r)
            self.box(layer, left - r, top - r, right + r, top + r)
            self.box(layer, left - r, bottom - r, left + r, top + r)
            self.box(layer, right - r, bottom - r, right + r, top + r)
        for x in range(left + 500, right - 499, 500):
            for y in (bottom, top):
                self.box(6, x - 80, y - 80, x + 80, y + 80)
        for y in range(bottom + 500, top - 499, 500):
            for x in (left, right):
                self.box(6, x - 80, y - 80, x + 80, y + 80)
        for y in (bottom, top):
            for m in range(1, 5):
                for dx in (-430, 0, 430):
                    self.cut(m, ground_x + dx, y)
                self.wire(m + 1, ground_x - 430, y, ground_x + 430, y, 430)


def pick(pins, x):
    return min(pins, key=lambda p: (abs(p[1] - x), p[1], p[2]))


def lift(drawing, pin, x_out):
    level, x, y = pin
    if level == 1:
        drawing.cut(1, x, y)
    drawing.wire(2, x, y, x_out, y, 300, min_length=500)
    drawing.cut(2, x_out, y)
    return x_out, y, 380


def lift_driver_resistor(drawing, pins, center):
    """Collect current along each native M1 terminal with multiple cuts."""
    access = {}
    for term, direction in (("R1", -1), ("R2", 1)):
        _, x, y = pins[term][0]
        x_out = center + direction * 2350
        # The compact resistor has closely spaced terminals in Y. Parallel
        # pickups are along X and the broad landing opens only on its side.
        pickup = x + direction * 1360
        drawing.wire(2, pickup, y, x_out, y, 380)
        drawing.cut_array(1, pickup, y, 5, 1)
        drawing.wire(2, x_out, y, x_out + direction * VIA_PITCH, y, 860)
        drawing.cut_array(2, x_out, y, 2, 2)
        access[term] = x_out, y, WIDE_RISER
    access["B"] = lift(drawing, pins["B"][0], center + 710)
    return access


def device_access(drawing, dev, shape, dx, dy):
    model = dev.key[0]
    pins = {t: tuple((m, x + dx, y + dy) for m, x, y in ps) for t, ps in shape.ports.items()}
    center = grid(dx + shape.cell.bbox().center().x)
    if model.endswith("mos"):
        heavy = dev.path[0] in ("XDRVH", "XDRVL")
        pitch = 1440 if heavy else 700
        slot = {t: center + int(i * pitch) for t, i in zip(("B", "D", "G", "S"), (-1.5, -.5, .5, 1.5))}
        # The PDK M2 rail has small jogs around via enclosures. Extend
        # the whole rail to the pickup, not a narrow tongue into a jog.
        m2 = drawing.layout.layer(METAL[2], 0)
        rails = tuple(pya.Region(shape.cell.begin_shapes_rec(m2)).merged().each())
        access = {}
        for term in ("G", "B"):
            x_out = slot[term]
            _, x, y = pick(pins[term], x_out)
            pt = pya.Point(x - dx, y - dy)
            b = next(r.bbox() for r in rails if r.inside(pt)).moved(dx, dy)
            drawing.box(METAL[2], min(b.left, x_out - 150), min(b.bottom, y - 150),
                        max(b.right, x_out + 150), max(b.top, y + 150))
            drawing.cut(2, x_out, y)
            access[term] = x_out, y, 380
        for t, direction in (("D", 1), ("S", -1)):
            width, riser = (1440, WIDE_RISER) if heavy else (300, 380)
            y = pins[t][0][2] + direction * (1080 if heavy else 300)
            lo = min(slot[t], *(p[1] for p in pins[t]))
            hi = max(slot[t], *(p[1] for p in pins[t]))
            drawing.wire(2, lo, y, hi, y, width, min_length=500)
            for level, x, _ in pins[t]:
                if level != 1:
                    raise ValueError(f"expected M1 diffusion pickup on {dev.path}")
                for offset in ((-510, 0, 510) if heavy else (0,)):
                    drawing.cut(1, x, y + offset)
            drawing.cut_array(2, slot[t], y, 3 if heavy else 1, 3 if heavy else 1)
            access[t] = slot[t], y, riser
        return access
    if model.startswith("diode"):
        tag = "DH" if model == "diodevdd_2kv" else "DL"
        access = {}
        for term, net in zip(TERMINALS[model], dev.nets):
            p = pins[term][0]
            drawing.probe(f"{tag}_{net}", *p)
            access[term] = lift(drawing, p, p[1])
        return access
    if dev.path[0] == "XRDRIVER":
        return lift_driver_resistor(drawing, pins, center)
    return {t: lift(drawing, pins[t][0], center + offset)
            for t, offset in zip(("R1", "R2", "B"), (-710, 0, 710))}


def physical_layout(devices):
    by_block = defaultdict(list)
    for dev in devices:
        by_block[dev.path[0]].append(dev)
    names = [name for row in ROWS for name in row]
    if len(names) != len(set(names)) or set(names) != by_block.keys():
        raise ValueError("physical rows do not cover the schematic blocks")
    return [[dev for name in row for dev in by_block[name]] for row in ROWS]


def allocate_trunks(pad_rows):
    tracks = defaultdict(list)
    for row, pins in enumerate(pad_rows):
        for net, pts in pins.items():
            tracks[net].append((row, [p[0] for p in pts]))
    result = {}
    spacing = 400
    for net, rows in sorted(tracks.items(), key=lambda kv: (-wide(kv[0]), -len(kv[1]), kv[0])):
        if len(rows) == 1 and net not in PORTS:
            continue
        x0 = grid(median(x for _, xs in rows for x in xs) / 100) * 100
        used = result.items()
        for step in range(0, 2000):
            dx = ((step + 1) // 2) * 100 * (1 if step % 2 else -1)
            x = x0 + dx
            if all(abs(x - old_x) >= (wide(net) + wide(old)) // 2 + spacing for old, old_x in used):
                result[net] = x
                break
        else:
            raise RuntimeError(f"no M5 track for {net}")
    return result


def build(out, pdk):
    devices = instances()
    drawn = list(physical_fingers(devices))
    layout = pya.Layout()
    layout.dbu = .001
    top = layout.create_cell(TOP)
    shapes = build_devices(layout, out / "primitives", pdk, {dev.key for dev in drawn})
    drawing = Drawing(layout, top)
    pin_rows = []
    channel_y = []
    drive_rows = []
    placed = {}
    base_y = 0
    for row in physical_layout(drawn):
        drive_row = row[0].path[0] in DRIVE_ROWS
        drive_rows.append(drive_row)
        cursor, row_top = 0, base_y
        landings = defaultdict(list)
        for dev in row:
            shape = shapes[dev.key]
            bbox = shape.cell.bbox()
            dx, dy = grid(cursor - bbox.left), grid(base_y - bbox.bottom)
            top.insert(pya.CellInstArray(shape.cell.cell_index(), pya.Trans(dx, dy)))
            placed[".".join(dev.path)] = [bbox.left + dx, bbox.bottom + dy, bbox.right + dx, bbox.top + dy]
            access = device_access(drawing, dev, shape, dx, dy)
            for terminal, net in zip(TERMINALS[dev.key[0]], dev.nets):
                landings[net].append(access[terminal])
            cursor = grid(dx + bbox.right + 2400)
            row_top = max(row_top, grid(dy + bbox.top))
        pin_rows.append(landings)
        channel_y.append(row_top + 1440)
        base_y = row_top + 3800 + sum(channel_width(n, drive_row) + 440 for n in landings)

    trunks = allocate_trunks(pin_rows)
    trunk_ys = defaultdict(list)
    for i, landings in enumerate(pin_rows):
        y0 = channel_y[i]
        # Keep the receiver's high-impedance nets just above their pickups
        # instead of sending them up long risers beyond the tall resistors.
        local_y = max((ypin for net in RX_LOCAL & landings.keys()
                       for _, ypin, _ in landings[net]), default=0) + 700
        for net, points in landings.items():
            width = channel_width(net, drive_rows[i])
            y = y0 + width // 2
            if net in RX_LOCAL:
                y = local_y
                local_y += width + 440
            xs = [x for x, _, _ in points]
            for x, ypin, rise_width in points:
                drawing.wire(3, x, ypin, x, y, rise_width)
                if rise_width == WIDE_RISER:
                    drawing.cut_array(3, x, y, 3, 3)
                else:
                    drawing.cut(3, x, y)
            if net in trunks:
                x = trunks[net]
                xs.append(x)
                if drive_rows[i] and net in DRIVE_NETS:
                    drawing.cut_array(4, x, y, 3, 3)
                else:
                    drawing.cut_array(4, x, y, 1, 2 if width >= 900 else 1)
                trunk_ys[net].append(y)
            drawing.wire(4, min(xs), y, max(xs), y, width, min_length=520)
            if net == "RX_LEVEL" and "RX_LEVEL" not in drawing.rc_labels:
                drawing.probe("RX_LEVEL", 4, xs[0], y)
            y0 += width + 440

    yb, yt = -3300, base_y + 900
    for net, x in trunks.items():
        ends = trunk_ys[net][:]
        if net in PORTS:
            y = yt if net in PORT_EDGE_TOP else yb
            ends.append(y)
            drawing.pin(net, x, y, wide(net))
        if net == "VSSIO":
            ends.append(yb)
        drawing.wire(5, x, min(ends), x, max(ends), wide(net))
    box = top.bbox()
    drawing.guard(grid(box.left - 3900), yb, grid(box.right + 3900), yt, trunks["VSSIO"])
    box = top.bbox()
    drawing.box(189, box.left - 200, box.bottom - 200, box.right + 200, box.top + 200)

    (out / "sstl2_dq_lvs.spice").write_text(cdl_reference(devices))
    top.flatten(-1, True)
    layout.write(str(out / "sstl2_dq.gds"))
    # Same mask geometry, with additional extraction-only terminal
    # markers. Magic uses explicit pin boxes to retain the RC tap nodes.
    for net, (x, y, m) in drawing.rc_labels.items():
        drawing.box(METAL[m], x - 40, y - 40, x + 40, y + 40, 2)
        top.shapes(layout.layer(METAL[m], 25)).insert(pya.Text(net, pya.Trans(x, y)))
    layout.write(str(out / "sstl2_dq_rc.gds"))
    bounds = top.bbox()
    info = {"top": TOP, "devices": len(devices), "ports": PORTS, "common_return": "VSSIO",
            "bbox_um": [bounds.width() * layout.dbu, bounds.height() * layout.dbu],
            "device_boxes_nm": placed, "rc_labels": drawing.rc_labels}
    (out / "layout_metadata.json").write_text(json.dumps(info, indent=2) + "\n")
    print(json.dumps(info))


if __name__ == "__main__":
    build(Path(os.environ["IHP_LAYOUT_OUT"]).resolve(), Path(os.environ["IHP_PDK"]).resolve())
