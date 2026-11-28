#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Structural connectivity and short checks for the chip-top GDS."""
import os
import sys

import pya

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import emit_chip_top as et  # noqa: E402

GDS = et.OUT_GDS
METALS = ("Metal1", "Metal2", "Metal3", "Metal4", "Metal5")
VIA_LAYERS = ("Via1", "Via2", "Via3", "Via4", "Via5")
CHECK_LAYERS = METALS + VIA_LAYERS


def layer_index(layout, name):
    return layout.find_layer(*et.LAYERS[name])


def region_from_shapes(layout, cell, name):
    region = pya.Region()
    li = layer_index(layout, name)
    if li is None or li < 0:
        return region
    for shape in cell.shapes(li).each():
        if shape.is_text():
            continue
        try:
            region.insert(shape.polygon)
        except Exception:
            pass
    return region


def region_from_gds(path, name, root_trans=None, root_name=None):
    source = pya.Layout()
    source.read(path)
    root = source.top_cell() if root_name is None else source.cell(root_name)
    region = pya.Region()
    if root is None:
        raise RuntimeError("cell %s is absent from %s" % (root_name, path))
    li = layer_index(source, name)
    if li is None or li < 0:
        return region
    iterator = root.begin_shapes_rec(li)
    while not iterator.at_end():
        try:
            polygon = iterator.shape().polygon.transformed(iterator.trans())
            if root_trans is not None:
                polygon = polygon.transformed(root_trans)
            region.insert(polygon)
        except Exception:
            pass
        iterator.next()
    region.merge()
    return region


def point_region(xy):
    x, y = et.dbu(xy[0]), et.dbu(xy[1])
    return pya.Region(pya.Box(x, y, x + 1, y + 1))


def component_at(region, xy):
    query = point_region(xy)
    for polygon in region.merged().each():
        component = pya.Region(polygon)
        if not (component & query).is_empty():
            return component
    return None


def touches(a, b):
    return not (a & b).is_empty()


def require(condition, message, failures):
    if not condition:
        failures.append(message)

def check_route_connectivity(net, regions, endpoints, failures):
    components = {}
    nodes_by_layer = {}
    graph = []
    for layer in CHECK_LAYERS:
        layer_components = [pya.Region(poly)
                            for poly in regions[layer].merged().each()]
        nodes_by_layer[layer] = []
        for component in layer_components:
            node = len(graph)
            graph.append(set())
            components[node] = component
            nodes_by_layer[layer].append(node)

    via_pairs = {
        "Via1": ("Metal1", "Metal2"),
        "Via2": ("Metal2", "Metal3"),
        "Via3": ("Metal3", "Metal4"),
        "Via4": ("Metal4", "Metal5"),
    }
    for via, metals in via_pairs.items():
        for via_node in nodes_by_layer[via]:
            for metal in metals:
                for metal_node in nodes_by_layer[metal]:
                    if not (components[via_node] & components[metal_node]) \
                            .is_empty():
                        graph[via_node].add(metal_node)
                        graph[metal_node].add(via_node)

    roots = []
    for endpoint in endpoints:
        xy = endpoint.get("via_pos", endpoint["pos"])
        query = point_region(xy)
        root = next((node for node in nodes_by_layer["Metal5"]
                     if not (components[node] & query).is_empty()), None)
        require(root is not None,
                "%s %s via point is absent from M5" %
                (net, endpoint["pin"]), failures)
        if root is not None:
            roots.append(root)
    if not roots:
        return
    seen = set()
    frontier = [roots[0]]
    while frontier:
        node = frontier.pop()
        if node in seen:
            continue
        seen.add(node)
        frontier.extend(graph[node] - seen)
    require(all(root in seen for root in roots),
            "%s terminal stacks are not connected across layers" % net,
            failures)
    require(len(seen) == len(graph),
            "%s has floating route-metal/via components" % net, failures)


def label_texts(layout, cell, name):
    li = layer_index(layout, name)
    if li is None or li < 0:
        return []
    return [shape.text.string for shape in cell.shapes(li).each()
            if shape.is_text()]


def main():
    ly = pya.Layout()
    ly.read(GDS)
    top = ly.cell("gf180mcu_sdram_chip_top")
    if top is None:
        raise RuntimeError("chip-top cell is absent from " + GDS)

    router = et.ChipTop()
    wires = router._wire_list()
    signal_wires = [wire for wire in wires if wire["wire_class"] == "signal"]
    power_wires = [wire for wire in wires if wire["wire_class"] == "power"]
    nets = set(wire["net"] for wire in wires) | {"VDDIO", "VSSIO"}
    route_cells = {
        cell.name[len("chiproute_"):]: cell
        for cell in ly.each_cell() if cell.name.startswith("chiproute_")
    }
    stdcell = ly.cell(et.INVERTER_CELL)
    inverter_present = stdcell is not None and any(
        ly.cell(inst.cell_index).name == et.INVERTER_CELL and
        inst.trans.disp.x == et.dbu(et.INVERTER_X) and
        inst.trans.disp.y == et.dbu(et.INVERTER_Y)
        for inst in top.each_inst())

    def route_cell(net):
        return route_cells.get(et.safe_cell_suffix(net))

    core_shift = pya.Trans(pya.Point(et.dbu(et.CORE_X), et.dbu(et.CORE_Y)))
    inverter_trans = pya.Trans(pya.Trans.R0, et.dbu(et.INVERTER_X),
                               et.dbu(et.INVERTER_Y))
    imported = {
        "ring": {name: region_from_gds(et.RING_GDS, name)
                 for name in CHECK_LAYERS},
        "core": {name: region_from_gds(et.CORE_GDS, name, core_shift)
                 for name in CHECK_LAYERS},
        "inv": {name: region_from_gds(et.STD_GDS, name, inverter_trans,
                                      et.INVERTER_CELL)
                for name in CHECK_LAYERS},
    }
    obstructions = {
        name: imported["ring"][name] + imported["core"][name] +
        imported["inv"][name]
        for name in CHECK_LAYERS
    }
    route_regions = {}
    for net in nets:
        cell = route_cell(net)
        if cell is not None:
            route_regions[net] = {
                name: region_from_shapes(ly, cell, name)
                for name in CHECK_LAYERS
            }

    failures = []
    require(inverter_present,
            "placed OE inverter instance is missing from chip top", failures)
    require(len(signal_wires) == 47,
            "expected 47 signal routes including inverter connections, got %d"
            % len(signal_wires), failures)
    require(len(power_wires) == 4,
            "expected four inverter power/well connections, got %d" %
            len(power_wires), failures)
    require(route_cell("VDDIO") is not None and route_cell("VSSIO") is not None,
            "missing pad-ring power mesh cell", failures)
    for net in nets:
        require(route_cell(net) is not None, "missing route cell for " + net,
                failures)

    metal2_labels = {}
    label_layer = layer_index(ly, "Metal2_label")
    if label_layer is not None and label_layer >= 0:
        for shape in top.shapes(label_layer).each():
            if shape.is_text():
                pos = shape.text.trans.disp
                metal2_labels[shape.text.string] = (pos.x, pos.y)
    pad_label_count = 0
    for site in et.SITES:
        assignment = et.ASSIGN[site["index"]]
        if assignment in ("VDDIO", "VSSIO"):
            continue
        if assignment == "pad_ck":
            name = "pad_ck"
        elif assignment.startswith("cmd_o"):
            name = "pad_cmd" + assignment[len("cmd_o"):]
        else:
            name = "pad_dq" + assignment[len("dq"):]
        point = router._site_transform(site) * pya.Point(
            et.dbu(0.0), et.dbu(0.0))
        xy = (point.x / float(et.UM), point.y / float(et.UM))
        require(metal2_labels.get(name) == (point.x, point.y),
                "%s top-level M2 label missing at pad opening %r" %
                (name, xy), failures)
        require(component_at(imported["ring"]["Metal2"], xy) is not None,
                "%s pad opening does not land on ring M2 metal" % name,
                failures)
        pad_label_count += 1
    require(pad_label_count == 30, "expected 30 labeled signal pad openings",
            failures)

    allowed = {net: {name: pya.Region() for name in CHECK_LAYERS}
               for net in nets}
    for wire in wires:
        net = wire["net"]
        cell = route_cell(net)
        if cell is None:
            continue
        regions = route_regions[net]
        for endpoint in (wire["source"], wire["target"]):
            kind = endpoint["kind"]
            layer_name = et.METAL_LAYER_BY_NUMBER[endpoint["layer"]]
            source_region = imported[{"pad": "ring", "core": "core",
                                      "inv": "inv"}[kind]][layer_name]
            pin = component_at(source_region, endpoint["pos"])
            require(pin is not None,
                    "%s %s terminal missing from %s %s" %
                    (net, endpoint["pin"], kind, layer_name), failures)
            if pin is None:
                continue
            allowed[net][layer_name] += pin
            require(touches(regions[layer_name], pin),
                    "%s route misses %s terminal on %s" %
                    (net, endpoint["pin"], layer_name), failures)

            via_pos = endpoint.get("via_pos", endpoint["pos"])
            stack = {
                34: ("Via1", "Via2", "Via3", "Via4"),
                36: ("Via2", "Via3", "Via4"),
                42: ("Via3", "Via4"),
                46: ("Via4",),
            }[endpoint["layer"]]
            for via in stack:
                require(not (regions[via] & point_region(via_pos)).is_empty(),
                        "%s %s stack misses %s" %
                        (net, endpoint["pin"], via), failures)
            m5_component = component_at(regions["Metal5"], via_pos)
            require(m5_component is not None,
                    "%s %s via landing has no M5" %
                    (net, endpoint["pin"]), failures)

        require(net in label_texts(ly, cell, "Metal5_label"),
                "%s route lacks an M5 net label" % net, failures)

    # Each net must form one continuous M5 component across all of its pins.
    for net in nets - {"VDDIO", "VSSIO"}:
        regions = route_regions.get(net)
        if regions is None:
            continue
        # NOTE: no single-layer M5 continuity check here.  The router uses
        # M4 horizontal + M5 vertical, so M5 is intentionally discontinuous;
        # vias bridge the layers.  True connectivity is validated by the
        # multi-layer graph check below (check_route_connectivity).
        endpoints = [endpoint for wire in wires if wire["net"] == net
                     for endpoint in (wire["source"], wire["target"])]
        check_route_connectivity(net, regions, endpoints, failures)

    # Explicitly validate the active-low OE inverter topology.
    oe_input = [w for w in signal_wires if w["net"] == "n_dq_oe"]
    oe_outputs = [w for w in signal_wires if w["net"] == "n_dq_oe_b"]
    require(len(oe_input) == 1 and
            oe_input[0]["source"]["pin"] == "dq_oe" and
            oe_input[0]["target"]["pin"] == "A",
            "core dq_oe does not connect to inverter A", failures)
    require(len(oe_outputs) == 8 and
            all(w["source"]["pin"] == "OE_N" and
                w["target"]["pin"] == "Y" for w in oe_outputs),
            "inverter Y does not fan out to all eight OE_N pads", failures)

    # Pad-ring VDDIO/VSSIO meshes make contact with each tile's measured rail.
    vdd_regions = route_regions.get("VDDIO")
    vss_regions = route_regions.get("VSSIO")
    for site in et.SITES:
        trans = router._site_transform(site)
        p = trans * pya.Point(et.dbu(-57.7), et.dbu(-52.3))
        xy = (p.x / float(et.UM), p.y / float(et.UM))
        pin = component_at(imported["ring"]["Metal3"], xy)
        require(pin is not None and vdd_regions is not None and
                touches(vdd_regions["Metal3"], pin),
                "VDDIO mesh misses tile %d M3 strap" % site["index"],
                failures)
        if pin is not None:
            allowed["VDDIO"]["Metal3"] += pin
        p = trans * pya.Point(et.dbu(35.3), et.dbu(47.9))
        xy = (p.x / float(et.UM), p.y / float(et.UM))
        pin = component_at(imported["ring"]["Metal4"], xy)
        require(pin is not None and vss_regions is not None and
                touches(vss_regions["Metal4"], pin),
                "VSSIO mesh misses tile %d M4 strap" % site["index"],
                failures)
        if pin is not None:
            allowed["VSSIO"]["Metal4"] += pin
    if vdd_regions is not None:
        require(len(list(vdd_regions["Metal3"].merged().each())) == 1,
                "VDDIO mesh is not one connected M3 component", failures)
    if vss_regions is not None:
        require(len(list(vss_regions["Metal4"].merged().each())) == 1,
                "VSSIO mesh is not one connected M4 component", failures)

    if vdd_regions is not None:
        require("VDDIO" in label_texts(ly, route_cell("VDDIO"),
                                       "Metal3_label"),
                "VDDIO mesh lacks label", failures)
    if vss_regions is not None:
        require("VSSIO" in label_texts(ly, route_cell("VSSIO"),
                                       "Metal4_label"),
                "VSSIO mesh lacks label", failures)

    for label_layer_name, net, xy in (
            ("Metal3_label", "VDDIO", (50.0, 38.0)),
            ("Metal4_label", "VSSIO", (150.0, 140.0)),
            ("Metal4_label", "VDD",
             (et.CORE_X + 23.04, et.CORE_Y + 145.0)),
            ("Metal4_label", "VSS",
             (et.CORE_X + 26.34, et.CORE_Y + 145.0))):
        li = layer_index(ly, label_layer_name)
        expected = (et.dbu(xy[0]), et.dbu(xy[1]))
        present = li is not None and li >= 0 and any(
            shape.is_text() and shape.text.string == net and
            (shape.text.trans.disp.x, shape.text.trans.disp.y) == expected
            for shape in top.shapes(li).each())
        require(present, "%s top-level power label missing on %s" %
                (net, label_layer_name), failures)
        metal = "Metal3" if label_layer_name == "Metal3_label" else "Metal4"
        source = route_regions[net][metal] if net in ("VDDIO", "VSSIO") \
            else imported["core"][metal]
        require(not (source & point_region(xy)).is_empty(),
                "%s label position does not touch %s metal" %
                (net, metal), failures)

    # Different nets may neither touch nor overlap on any conductor layer.
    route_nets = sorted(route_regions)
    for i, net_a in enumerate(route_nets):
        for net_b in route_nets[i + 1:]:
            for layer in CHECK_LAYERS:
                a, b = route_regions[net_a][layer], route_regions[net_b][layer]
                require((a & b).is_empty(),
                        "%s and %s intersect on %s" %
                        (net_a, net_b, layer), failures)

    # Except for intentional terminal contacts, no new route metal may cross
    # imported ring/core/inverter geometry on the same layer.
    for net, regions in route_regions.items():
        for layer in METALS:
            overlap = (regions[layer] - allowed[net][layer]) & obstructions[layer]
            require(overlap.is_empty(),
                    "%s route crosses imported %s metal (%g um^2)" %
                    (net, layer, overlap.area() * ly.dbu * ly.dbu), failures)
        for via in VIA_LAYERS:
            require((regions[via] & obstructions[via]).is_empty(),
                    "%s via stack overlaps imported %s" % (net, via),
                    failures)

    if failures:
        for failure in failures:
            print("FAIL:", failure)
        raise RuntimeError("%d structural checks failed" % len(failures))
    print("PASS: %d signal wires across %d logical nets" %
          (len(signal_wires), len(set(w["net"] for w in signal_wires))))
    print("PASS: inverter A input, Y fanout to eight OE_N pads, and power")
    print("PASS: VDDIO/VSSIO meshes contact all 32 tile straps")
    print("PASS: no different-net intersections or imported-metal crossings")


main()

