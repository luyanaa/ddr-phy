#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Build foundry-backed SG13G2 device masters for the SSTL-2 DQ macro."""
from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal, ROUND_HALF_UP
import hashlib
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

import pya


_GRID_UM = Decimal("0.005")
_DBU_UM = 0.001
_M1 = (8, 0)
_M2 = (10, 0)
_MAGIC_LABEL = (8, 25)

_MOS_DRAWS = {
    "sg13_hv_nmos": "sg13g2::sg13_hv_nmos_draw",
    "sg13_hv_pmos": "sg13g2::sg13_hv_pmos_draw",
    "sg13_lv_nmos": "sg13g2::sg13_lv_nmos_draw",
    "sg13_lv_pmos": "sg13g2::sg13_lv_pmos_draw",
}
_RES_DRAWS = {
    "rppd": "sg13g2::rppd_draw",
    "rhigh": "sg13g2::rhigh_draw",
}
_DIODE_GDS = {
    "diodevdd_2kv": "diodevdd_2kv",
    "diodevss_2kv": "diodevss_2kv",
}
# These are the official PCell terminal-label anchors in the m=1 test master.
# The corresponding crop is copied from the exact IHP recognized test GDS below.
_DIODE_PORTS = {
    "diodevdd_2kv": {
        "PAD": (2, -320, 18535),
        "VDD": (2, 9150, 18990),
        "VSS": (1, 4860, 675),
    },
    "diodevss_2kv": {
        "PAD": (2, -280, 18525),
        "VDD": (1, 4860, 36375),
        # Contact to the inner p+ guard; the M1 ring at the legacy
        # text anchor is the unrelated VDD well contact.
        "VSS": (2, 2155, 3900),
    },
}


@dataclass(frozen=True)
class DeviceShape:
    cell: pya.Cell
    ports: dict[str, tuple[tuple[int, int, int], ...]]


def _grid_um(value) -> Decimal:
    value = Decimal(str(value))
    return (value / _GRID_UM).quantize(Decimal("1"), rounding=ROUND_HALF_UP) * _GRID_UM


def _um_text(value: Decimal) -> str:
    return format(value, ".3f").rstrip("0").rstrip(".") or "0"


def _cell_name(key) -> str:
    return "dq_" + hashlib.sha256(repr(key).encode()).hexdigest()[:12]


def _tcl_brace(value: str) -> str:
    return "{" + value.replace("\\", "\\\\").replace("}", "\\}") + "}"


def _text_shapes(cell: pya.Cell, layer: int) -> list[tuple[str, int, int]]:
    result = []
    iterator = cell.begin_shapes_rec(layer)
    while not iterator.at_end():
        shape = iterator.shape()
        if shape.is_text():
            text = shape.text.transformed(iterator.trans())
            result.append((text.string, int(text.x), int(text.y)))
        iterator.next()
    return result


def _metal_region(cell: pya.Cell, layout: pya.Layout, metal: int) -> pya.Region:
    layer, datatype = _M1 if metal == 1 else _M2
    return pya.Region(cell.begin_shapes_rec(layout.layer(layer, datatype))).merged()


def _inside(region: pya.Region, x: int, y: int) -> bool:
    point = pya.Point(int(x), int(y))
    return any(poly.inside(point) for poly in region.each())


def _strip_text(cell: pya.Cell, layout: pya.Layout) -> None:
    for layer in list(layout.layer_indexes()):
        shapes = cell.shapes(layer)
        info = layout.get_info(layer)
        if info.datatype == 2 and info.layer in (8, 10):
            shapes.clear()
            continue
        text_shapes = [shape for shape in shapes.each() if shape.is_text()]
        for shape in text_shapes:
            shapes.erase(shape)


def _run_magic(layout: pya.Layout, work: Path, pdk: Path, key, cell_name: str) -> pya.Cell:
    model, total_w_um, l_um, ng_value = key
    ng = int(ng_value)
    if ng < 1 or ng != ng_value:
        raise ValueError("%s requires a positive integer ng, got %r" % (model, ng_value))

    magic_rc = pdk / "libs.tech/magic/ihp-sg13g2.magicrc"
    if not magic_rc.is_file():
        raise FileNotFoundError("IHP Magic startup file not found: %s" % magic_rc)
    magic = shutil.which("magic")
    if magic is None:
        raise RuntimeError("Magic must be available on PATH")

    if model in _MOS_DRAWS:
        finger_w = _grid_um(Decimal(str(total_w_um)) / Decimal(ng))
        drawn_l = _grid_um(l_um)
        if finger_w <= 0 or drawn_l <= 0:
            raise ValueError("invalid MOS dimensions for %r" % (key,))
        draw_proc = _MOS_DRAWS[model]
        params = {
            "w": _um_text(finger_w),
            "l": _um_text(drawn_l),
            "ng": str(ng),
            "m": "1",
            "guard": "1",
            "conn_gates": "1",
            "doports": "1",
            "topc": "1",
            "botc": "0",
            "doverlap": "1",
            "ccols": "1",
            "gate_ring": "0",
            "full_metal": "1",
            "viasrc": "0",
            "viadrn": "0",
            "viagate": "100",
            "viagb": "100",
        }
    elif model in _RES_DRAWS:
        if ng != 1:
            raise ValueError("%s resistor keys must use ng=1" % model)
        drawn_w = _grid_um(total_w_um)
        drawn_l = _grid_um(l_um)
        if drawn_w <= 0 or drawn_l <= 0:
            raise ValueError("invalid resistor dimensions for %r" % (key,))
        draw_proc = _RES_DRAWS[model]
        params = {
            "w": _um_text(drawn_w),
            "l": _um_text(drawn_l),
            "m": "1",
            "nx": "1",
            "guard": "1",
            "doports": "1",
            "vias": "0",
            "bar": "1",
            "full_metal": "1",
        }
    else:
        raise ValueError("unsupported Magic device model %r" % model)

    dict_text = " ".join("%s {%s}" % (name, value) for name, value in params.items())
    with tempfile.TemporaryDirectory(prefix="ihp130_dq_magic_", dir=str(work)) as temp_name:
        temp = Path(temp_name)
        gds_path = temp / (cell_name + ".gds")
        # `cellname create` does not select the created cell in Magic.
        runset = "\n".join((
            "load %s -silent" % _tcl_brace(cell_name),
            "box values 0 0 0 0",
            "%s [dict merge [sg13g2::%s_defaults] [dict create %s]]" % (draw_proc, model, dict_text),
            "save",
            "gds write %s" % _tcl_brace(str(gds_path)),
            "quit -noprompt",
            "",
        ))
        proc = subprocess.run(
            [magic, "-dnull", "-noconsole", "-rcfile", str(magic_rc)],
            cwd=str(temp), input=runset, capture_output=True, text=True, check=False,
        )
        mag_path = temp / (cell_name + ".mag")
        if proc.returncode != 0 or not gds_path.is_file() or gds_path.stat().st_size == 0 or not mag_path.is_file():
            detail = (proc.stdout + "\n" + proc.stderr)[-6000:]
            raise RuntimeError("Magic did not generate %s geometry (exit %d):\n%s" % (model, proc.returncode, detail))
        layout.read(str(gds_path))

    cell = layout.cell(cell_name)
    if cell is None:
        raise RuntimeError("Magic GDS did not contain requested cell %s" % cell_name)
    return cell


def _mos_ports(cell: pya.Cell, layout: pya.Layout, ng: int) -> dict[str, tuple[tuple[int, int, int], ...]]:
    labels = _text_shapes(cell, layout.layer(*_MAGIC_LABEL))
    m1 = _metal_region(cell, layout, 1)
    m2 = _metal_region(cell, layout, 2)
    diffusion = {"D": set(), "S": set()}
    gates = set()
    bodies = set()

    for name, x, y in labels:
        if name == "G":
            if not _inside(m2, x, y):
                raise RuntimeError("MOS G label is not on M2 at (%d,%d)" % (x, y))
            gates.add((x, y))
        elif name == "B":
            if not _inside(m2, x, y):
                raise RuntimeError("MOS B label is not on M2 at (%d,%d)" % (x, y))
            bodies.add((x, y))
        else:
            match = re.fullmatch(r"([DS])\d*", name)
            if match:
                terminal = match.group(1)
                if not _inside(m1, x, y):
                    raise RuntimeError("MOS %s contact label is not on M1 at (%d,%d)" % (name, x, y))
                diffusion[terminal].add((x, y))

    if not gates or not bodies:
        raise RuntimeError("Magic MOS is missing its gate or guard-ring label")
    if not diffusion["D"] or not diffusion["S"]:
        raise RuntimeError("Magic MOS is missing drain or source contact labels")

    contacts = sorted(diffusion["D"] | diffusion["S"])
    expected = ng + 1
    if len(contacts) == ng and ng % 2 == 0:
        # PDK mos_draw labels shared alternating contacts and omits the outer
        # right drain for even ng.  Extrapolate the measured contact pitch,
        # then require the predicted point to lie on actual M1 geometry.
        xs = [x for x, _ in contacts]
        pitches = sorted(xs[i + 1] - xs[i] for i in range(len(xs) - 1))
        pitch = pitches[len(pitches) // 2]
        if pitch <= 0 or pitch % 5 != 0 or any(abs(value - pitch) > 5 for value in pitches):
            raise RuntimeError("cannot verify even-ng diffusion-contact pitch: %r" % xs)
        ys = {y for _, y in contacts}
        if len(ys) != 1:
            raise RuntimeError("MOS diffusion contacts are not on a common row: %r" % contacts)
        edge = (xs[-1] + pitch, next(iter(ys)))
        if not _inside(m1, *edge):
            raise RuntimeError("extrapolated edge drain is not on M1 at %r" % (edge,))
        diffusion["D"].add(edge)
        contacts = sorted(diffusion["D"] | diffusion["S"])

    if len(contacts) != expected:
        raise RuntimeError("MOS ng=%d has %d verified D/S contacts, expected %d" % (ng, len(contacts), expected))

    # conn_gates=1 must put every labeled gate landing on the same M2 region.
    gate_polygons = tuple(m2.each())
    gate_components = set()
    for x, y in gates:
        for index, poly in enumerate(gate_polygons):
            if poly.inside(pya.Point(x, y)):
                gate_components.add(index)
                break
    if len(gate_components) != 1:
        raise RuntimeError("Magic conn_gates=1 gate landings are not one connected M2 region")

    return {
        "D": tuple((1, x, y) for x, y in sorted(diffusion["D"])),
        "S": tuple((1, x, y) for x, y in sorted(diffusion["S"])),
        "G": tuple((2, x, y) for x, y in sorted(gates)),
        "B": tuple((2, x, y) for x, y in sorted(bodies)),
    }


def _resistor_ports(cell: pya.Cell, layout: pya.Layout) -> dict[str, tuple[tuple[int, int, int], ...]]:
    labels = _text_shapes(cell, layout.layer(*_MAGIC_LABEL))
    m1 = _metal_region(cell, layout, 1)
    ports = {"R1": set(), "R2": set(), "B": set()}
    for name, x, y in labels:
        if name in ports:
            if not _inside(m1, x, y):
                raise RuntimeError("resistor %s label is not on M1 at (%d,%d)" % (name, x, y))
            ports[name].add((x, y))
    if any(not points for points in ports.values()):
        raise RuntimeError("Magic resistor is missing an R1, R2, or guard-ring B contact")
    return {name: tuple((1, x, y) for x, y in sorted(points)) for name, points in ports.items()}


def _diode_cell(layout: pya.Layout, pdk: Path, model: str, cell_name: str) -> pya.Cell:
    gds = pdk / "libs.tech/klayout/tech/lvs/testing/testcases/unit/esd_devices/layout" / (_DIODE_GDS[model] + ".gds")
    if not gds.is_file():
        raise FileNotFoundError("IHP recognized ESD GDS not found: %s" % gds)
    source = pya.Layout()
    source.read(str(gds))
    if abs(source.dbu - layout.dbu) > 1e-12:
        raise RuntimeError("diode GDS dbu %.6g does not match target layout dbu %.6g" % (source.dbu, layout.dbu))
    root = source.top_cell()
    if root is None:
        raise RuntimeError("diode GDS has no top cell: %s" % gds)

    target = layout.create_cell(cell_name)
    # The official unit GDS top is flat and contains m=1/2/4 witnesses.
    # This crop selects only the verified origin m=1 master; every selected
    # physical shape, including the Recog.esd marker, is copied unmodified.
    crop = pya.Box(-2500, -10, 12900, 37100)
    copied = 0
    for source_layer in source.layer_indexes():
        info = source.get_info(source_layer)
        if info.datatype == 2 and info.layer in (8, 10):
            continue
        target_layer = layout.layer(info)
        iterator = root.begin_shapes_rec(source_layer)
        while not iterator.at_end():
            shape = iterator.shape()
            bounds = iterator.trans() * shape.bbox()
            if not shape.is_text() and (crop & bounds) == bounds:
                target.shapes(target_layer).insert(shape, iterator.trans())
                copied += 1
            iterator.next()
    if copied == 0:
        raise RuntimeError("m=1 diode crop was empty for %s" % model)
    return target


def _diode_ports(cell: pya.Cell, layout: pya.Layout, model: str) -> dict[str, tuple[tuple[int, int, int], ...]]:
    m1 = _metal_region(cell, layout, 1)
    m2 = _metal_region(cell, layout, 2)
    result = {}
    for name, (level, x, y) in _DIODE_PORTS[model].items():
        region = m1 if level == 1 else m2
        if not _inside(region, x, y):
            raise RuntimeError("%s %s landing (%d,%d) is not on M%d" % (model, name, x, y, level))
        result[name] = ((level, x, y),)
    return result


def build_devices(layout: pya.Layout, work: Path, pdk: Path, keys) -> dict[tuple, DeviceShape]:
    """Return one foundry-drawn cell and verified local access points per key."""
    if abs(layout.dbu - _DBU_UM) > 1e-12:
        raise ValueError("IHP DQ device cells require layout dbu=0.001 um, got %.6g" % layout.dbu)
    work = Path(work).resolve()
    pdk = Path(pdk).resolve()
    work.mkdir(parents=True, exist_ok=True)

    result = {}
    for key in sorted(set(tuple(item) for item in keys), key=lambda item: (str(item[0]), str(item[1]), str(item[2]), int(item[3]))):
        if len(key) != 4:
            raise ValueError("device keys must be (model,total_w_um,l_um,ng): %r" % (key,))
        model = str(key[0])
        cell_name = _cell_name(key)
        if model in _DIODE_GDS:
            cell = _diode_cell(layout, pdk, model, cell_name)
            ports = _diode_ports(cell, layout, model)
        elif model in _MOS_DRAWS:
            cell = _run_magic(layout, work, pdk, key, cell_name)
            ports = _mos_ports(cell, layout, int(key[3]))
            _strip_text(cell, layout)
        elif model in _RES_DRAWS:
            cell = _run_magic(layout, work, pdk, key, cell_name)
            ports = _resistor_ports(cell, layout)
            _strip_text(cell, layout)
        else:
            raise ValueError("unsupported SG13G2 DQ device model %r" % model)
        result[key] = DeviceShape(cell=cell, ports=ports)
    return result
