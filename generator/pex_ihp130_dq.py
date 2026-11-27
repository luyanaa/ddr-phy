#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Bind the two LVS-proven diode models at their Magic RC terminal nodes.

Magic extracts their wiring and other geometry, but its SG13G2 technology
has no compact extraction class for diodevdd_2kv or diodevss_2kv. The
unaltered Magic RC file and unaltered KLayout device extraction are inputs.
"""

import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path

TOP = "ihp130_sstl2_dq"
SCHEMATIC_PINS = "OUT OE IN PAD VREF PU_OK VDD VSS VDDIO VSSIO".split()
PHYSICAL_PINS = set(SCHEMATIC_PINS) - {"VSS"}
ESD = {"DH": "diodevdd_2kv", "DL": "diodevss_2kv"}
ESD_PINS = ("VDDIO", "PAD", "VSSIO")
PROBES = {f"{tag}_{pin}" for tag in ESD for pin in ESD_PINS} | {"RX_LEVEL"}


def statements(text):
    out = []
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("+"):
            out[-1] += " " + stripped[1:]
        else:
            out.append(line)
    return out


def diode_checks(text):
    devices = Counter()
    for line in statements(text):
        words = line.split()
        if not words or words[0][0].upper() != "D" or len(words) < 5:
            continue
        model = words[4].lower()
        if model in ESD.values():
            if {n.upper() for n in words[1:4]} != set(ESD_PINS):
                raise ValueError(f"ESD extraction does not reach the three physical ports: {line}")
            devices[model] += 1
    if devices != Counter(ESD.values()):
        raise ValueError(f"expected one of each exact PDK ESD device, got {dict(devices)}")


def x_node_end(words):
    return next((i for i, word in enumerate(words) if "=" in word), len(words)) - 1


def reduce_passives(lines):
    """Collapse exact shorts and eliminate purely capacitive floating nodes.

    A floating node cannot draw net current. Replacing its incident
    capacitances C_i by pairwise C_i*C_j/sum(C_i) preserves terminal
    current without a fictitious DC shunt or a changed time constant.
    """
    records = [line.split() for line in lines if line.strip() and not line.lstrip().startswith("*")]
    aliases = {}

    def root(node):
        node = node.upper()
        while node in aliases:
            node = aliases[node]
        return node

    short_count = 0
    keep = PHYSICAL_PINS | {"RX_LEVEL", "0"}
    for words in records:
        if words[0][0].upper() == "R" and float(words[3]) == 0:
            a, b = sorted((root(words[1]), root(words[2])), key=lambda n: (n not in keep, n))
            if a != b:
                if b in keep:
                    raise ValueError(f"unexpected zero-ohm short between {a} and {b}")
                aliases[b] = a
            short_count += 1

    caps = defaultdict(dict)
    physical = keep.copy()
    elements = []
    cap_scales = {"f": 1e-15, "p": 1e-12, "n": 1e-9, "u": 1e-6, "m": 1e-3}

    def add_cap(a, b, val):
        if a != b and val:
            new = caps[a].get(b, 0) + val
            caps[a][b] = caps[b][a] = new

    for words in records:
        kind = words[0][0].upper()
        if kind == "X":
            end = x_node_end(words)
            words[1:end] = map(root, words[1:end])
            physical.update(words[1:end])
        elif kind in ("R", "C"):
            words[1:3] = a, b = tuple(map(root, words[1:3]))
            if kind == "C":
                raw = words[3].lower()
                val = float(raw[:-1]) * cap_scales[raw[-1]] if raw[-1] in cap_scales else float(raw)
                if val < 0:
                    raise ValueError(f"negative extracted capacitance: {' '.join(words)}")
                add_cap(a, b, val)
                continue
            if a == b:
                continue
            physical.update((a, b))
        else:
            raise ValueError(f"unsupported Magic RC record: {' '.join(words)}")
        elements.append(" ".join(words))

    floating = sorted(caps.keys() - physical)
    for node in floating:
        branches = tuple(caps.pop(node).items())
        total = sum(c for _, c in branches)
        for i, (a, ca) in enumerate(branches):
            del caps[a][node]
            for b, cb in branches[i + 1:]:
                add_cap(a, b, ca * cb / total)
    for a, neighbors in caps.items():
        for b, capacitance in neighbors.items():
            if a < b:
                elements.append(f"CP{len(elements)} {a} {b} {capacitance:.15g}")
    return elements, {"short_aliases": short_count, "capacitive_only_nodes": floating}


def simulation_view(raw, lvs):
    diode_checks(lvs)
    lines = statements(raw)
    sub = [i for i, line in enumerate(lines) if line.lower().startswith(".subckt ")]
    ends = [i for i, line in enumerate(lines) if line.lower().startswith(".ends")]
    if len(sub) != 1 or len(ends) != 1 or sub[0] >= ends[0]:
        raise ValueError("Magic RC must contain one flattened named subcircuit")
    low, high = sub[0], ends[0]
    ports = lines[low].split()[2:]
    port_set = PHYSICAL_PINS | PROBES
    if {n.upper() for n in ports} != port_set or len(ports) != len(port_set):
        raise ValueError(f"Magic RC ports differ from the physical ports and tap markers: {ports}")
    if any(model in raw.lower() for model in ESD.values()):
        raise ValueError("Magic RC already includes an ESD diode model")
    nodes = set()
    counts = Counter()
    links = defaultdict(set)
    for line in lines[low + 1:high]:
        words = line.split()
        if not words or words[0].startswith("*"):
            continue
        kind = words[0][0].upper()
        counts[kind] += 1
        if kind in ("R", "C"):
            nodes.update(w.upper() for w in words[1:3])
            if kind == "R":
                a, b = (w.upper() for w in words[1:3])
                links[a].add(b)
                links[b].add(a)
        elif kind == "X":
            nodes.update(w.upper() for w in words[1:x_node_end(words)])
    if missing := (PROBES | PHYSICAL_PINS) - nodes:
        raise ValueError(f"RC export lost required physical probe nodes: {', '.join(sorted(missing))}")
    if not (counts["R"] and counts["C"] and counts["X"]):
        raise ValueError(f"expected extracted devices plus R and C, got {dict(counts)}")
    # Prove each local diode contact reaches the intended macro port
    # through the actual extracted conductor/resistor network.
    for tag in ESD:
        for pin in ESD_PINS:
            todo = [f"{tag}_{pin}"]
            seen = set()
            while todo:
                node = todo.pop()
                if node not in seen:
                    seen.add(node)
                    todo.extend(links[node] - seen)
            if seen & PHYSICAL_PINS != {pin}:
                raise ValueError(f"{tag}_{pin} has inconsistent extracted rail/PAD connectivity")
    models = [f"X{tag} {' '.join(f'{tag}_{p}' for p in ESD_PINS)} {model}" for tag, model in ESD.items()]
    reduced, reductions = reduce_passives([*lines[low + 1:high], *models])
    return "\n".join([
        "* SG13G2 physical RC; the common return is VSSIO (VSS must be tied to it externally).",
        "* Native ESD junctions are compact models at the six physically extracted terminals.",
        f".subckt {TOP} {' '.join(SCHEMATIC_PINS)}", *reduced, f".ends {TOP}", "",
    ]), dict(counts), reductions


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("directory", type=Path, help="output directory of sim/ihp130_dq_layout.sh")
    work = ap.parse_args().directory
    try:
        deck, counts, reductions = simulation_view((work / "sstl2_dq_rc.spice").read_text(),
                                                   (work / "sstl2_dq_extracted.cir").read_text())
    except ValueError as exc:
        ap.exit(1, f"{exc}\n")
    target = work / "sstl2_dq_pex.spice"
    target.write_text(deck)
    print(json.dumps({"netlist": str(target), "raw_elements": counts, "reductions": reductions,
                      "esd_models": list(ESD.values())}))


if __name__ == "__main__":
    main()
