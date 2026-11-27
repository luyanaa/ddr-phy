#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Add specify blocks to the GF180 3.3 V functional cell models.

The CIEL ``gf180mcu_as_sc_mcu7t3v3`` Verilog view is functional only: it
has no specify blocks, so Icarus silently ignores every SDF annotation
(measured: ``warning: Omitting $sdf_annotate() since specify blocks are
being omitted``).  This generator parses the matching Liberty file, derives
the timing arcs (including the data pin of every sequential arc) and
inserts a specify block into each module of the functional view.

The delay values written here are only placeholders; the SDF annotator
replaces them with the per-instance values.  They exist because Icarus
needs a declared path before it can annotate one.

Usage:
    python3 generator/emit_gf180_timing_models.py \
        --cells pdks/.../verilog/gf180mcu_as_sc_mcu7t3v3.v \
        --liberty pdks/.../lib/gf180mcu_as_sc_mcu7t3v3__ss_125C_3v00.lib \
        --sdf flow/runs/.../sdram_phy_top__max_ss_125C_3v00.sdf \
        --out sim/gf180_timing_models_ss.v
"""
import argparse
import re
import sys
from pathlib import Path

TOKEN = re.compile(r'"[^"]*"|[A-Za-z_][A-Za-z0-9_.]*|[+-]?(?:\d+\.?\d*|\.\d+)(?:e[+-]?\d+)?|[{}().:;,=]')


class LibertyParser:
    def __init__(self, text):
        # Liberty uses backslash-newline continuations inside strings/values.
        text = re.sub(r"\\\s*\n", " ", text)
        self.toks = TOKEN.findall(text)
        self.i = 0

    def peek(self):
        return self.toks[self.i] if self.i < len(self.toks) else None

    def take(self):
        t = self.toks[self.i]
        self.i += 1
        return t

    def parse(self):
        return self.parse_group_body(None)

    def parse_group_body(self, name):
        """Parse statements until '}' or EOF. Returns a list of nodes."""
        nodes = []
        while True:
            t = self.peek()
            if t is None:
                break
            if t == "}":
                self.take()
                break
            if t in (";", ","):
                self.take()
                continue
            key = self.take()
            if self.peek() == ":":
                self.take()
                val = []
                while self.peek() not in (";", "}", None):
                    val.append(self.take())
                nodes.append((key, "attr", " ".join(val)))
                continue
            args = []
            if self.peek() == "(":
                self.take()
                depth = 1
                while depth:
                    x = self.take()
                    if x == "(":
                        depth += 1
                    elif x == ")":
                        depth -= 1
                    elif x != ",":
                        args.append(x)
            if self.peek() == "{":
                self.take()
                body = self.parse_group_body(key)
                nodes.append((key, args, body))
            else:
                if self.peek() == ";":
                    self.take()
                nodes.append((key, "attr", " ".join(args)))
        return nodes


def unwrap(x):
    return x.strip('"')


def find(nodes, key):
    return [n for n in nodes if n[0] == key]


def attr(nodes, key, default=None):
    for n in nodes:
        if n[0] == key and n[1] == "attr":
            return n[2]
    return default


def table_value(group, which="cell_rise"):
    """First value of a delay/constraint table (placeholder only)."""
    g = find(group, which)
    if not g:
        return 0.0
    vals = find(g[0][2], "values")
    if not vals:
        return 0.0
    first = vals[0][1]
    m = re.search(r"[+-]?\d+(?:\.\d+)?", first)
    return float(m.group(0)) if m else 0.0


def collect_pins(cell):
    pins = {}
    for n in find(cell, "pin"):
        name = unwrap(n[1][0])
        body = n[2]
        pins[name] = body
    return pins


def pin_direction(body):
    return unwrap(attr(body, "direction", "input"))


def timing_groups(body):
    return [(n[2], n) for n in find(body, "timing")]


def clock_pins(pins):
    out = set()
    for name, body in pins.items():
        if attr(body, "clock") == "true" or name.upper() in ("CLK", "CP", "CK"):
            out.add(name)
    return out


def data_pin_for(pins, clk):
    """The data pin of a CLK->Q arc: the input with a setup arc on CLK."""
    for name, body in pins.items():
        if pin_direction(body) != "input":
            continue
        for tg, _ in timing_groups(body):
            tt = unwrap(attr(tg, "timing_type", ""))
            rel = unwrap(attr(tg, "related_pin", ""))
            if rel == clk and tt in ("setup_rising", "setup_falling", "setup"):
                return name
    # scan flops: SE/SI also have setup arcs; the first non-clock input is
    # a safe fallback for the placeholder path.
    for name, body in pins.items():
        if pin_direction(body) == "input" and name != clk:
            return name
    return None


def build_specify(pins, cell_name):
    lines = []
    seen = set()

    def add(line):
        if line not in seen:
            seen.add(line)
            lines.append("    " + line)

    clks = clock_pins(pins)
    # data pin per sequential cell, keyed by clock pin
    data_for = {c: data_pin_for(pins, c) for c in clks}

    for pname, body in pins.items():
        if pin_direction(body) != "output":
            continue
        for tg, _ in timing_groups(body):
            rel = unwrap(attr(tg, "related_pin", ""))
            if not rel or rel not in pins:
                continue
            tt = unwrap(attr(tg, "timing_type", "combinational"))
            dly = table_value(tg, "cell_rise")
            dly2 = table_value(tg, "cell_fall")
            placeholder = "0.0" if dly == dly2 == 0 else "%.6g, %.6g" % (dly, dly2)
            if tt.startswith("rising_edge") or tt.startswith("falling_edge"):
                data = data_for.get(rel)
                if data:
                    edge = "posedge" if tt.startswith("rising") else "negedge"
                    add("(%s %s => (%s +: %s)) = (%s);" % (edge, rel, pname, data, placeholder))
                else:
                    add("(%s => %s) = (%s);" % (rel, pname, placeholder))
            elif tt.startswith("preset") or tt.startswith("clear"):
                const = "1'b1" if "preset" in tt or "set" in tt else "1'b0"
                add("(posedge %s => (%s +: %s)) = (%s);" % (rel, pname, const, placeholder))
            elif tt in ("combinational", "combinational_rise",
                        "combinational_fall", "three_state_enable",
                        "three_state_disable", "three_state_enable_fall",
                        "three_state_enable_rise", "three_state_disable_rise",
                        "three_state_disable_fall"):
                add("(%s => %s) = (%s);" % (rel, pname, placeholder))
            # timing_type "hold_*/setup_*/recovery_*/removal_*/min_pulse_width_*"
            # live on input pins and are handled below (none on outputs).

    # setup/hold checks: add them so a later SDF SETUP/HOLD section has a
    # declared check to annotate.  0 placeholders never fire.
    for pname, body in pins.items():
        if pin_direction(body) != "input" or pname in clks:
            continue
        for tg, _ in timing_groups(body):
            rel = unwrap(attr(tg, "related_pin", ""))
            tt = unwrap(attr(tg, "timing_type", ""))
            if not rel or rel not in pins:
                continue
            if tt.startswith("setup_rising"):
                add("$setup(%s, posedge %s, 0.0);" % (pname, rel))
            elif tt.startswith("setup_falling"):
                add("$setup(%s, negedge %s, 0.0);" % (pname, rel))
            elif tt.startswith("hold_rising"):
                add("$hold(posedge %s, %s, 0.0);" % (rel, pname))
            elif tt.startswith("hold_falling"):
                add("$hold(negedge %s, %s, 0.0);" % (rel, pname))
    return lines


def module_texts(cells_path):
    text = Path(cells_path).read_text()
    mods = {}
    for m in re.finditer(r"^module\s+([A-Za-z_][A-Za-z0-9_]*)\b(.*?)^endmodule",
                         text, re.S | re.M):
        mods[m.group(1)] = m.group(0)
    return mods


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cells", required=True)
    ap.add_argument("--liberty", required=True)
    ap.add_argument("--sdf", required=True,
                    help="SDF to decide which cells/arcs are needed")
    ap.add_argument("--netlist", default=None,
                    help="gate netlist: include every cell type it instantiates")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    lib = LibertyParser(Path(args.liberty).read_text()).parse()
    lib_body = find(lib, "library")
    lib_body = lib_body[0][2] if lib_body else lib
    cells = {}
    for n in find(lib_body, "cell"):
        cells[unwrap(n[1][0])] = n[2]

    # Cell types and IOPATH arcs actually present in the SDF.
    sdf = Path(args.sdf).read_text()
    needed = set()
    arcs = {}
    cur = None
    for line in sdf.splitlines():
        m = re.search(r'\(CELLTYPE\s+"([^"]+)"', line)
        if m:
            cur = m.group(1)
            needed.add(cur)
            continue
        m = re.search(r'\(IOPATH\s+(\S+)\s+(\S+)', line)
        if m and cur:
            arcs.setdefault(cur, set()).add((m.group(1), m.group(2)))

    if args.netlist:
        nl = Path(args.netlist).read_text()
        needed |= set(re.findall(r"\bgf180mcu_as_sc_mcu7t3v3__[A-Za-z0-9_]+", nl))

    mods = module_texts(args.cells)
    emitted = []
    missing = []
    for cell in sorted(needed):
        if cell not in mods:
            missing.append(cell)
            continue
        if cell not in cells:
            # physical-only cell (fill, tap, ...): functional module, no arcs
            body = mods[cell]
            pos = body.rfind("endmodule")
            body = body[:pos] + "  specify\n  endspecify\n\n" + body[pos:]
            emitted.append(body)
            continue
        pins = collect_pins(cells[cell])
        spec = build_specify(pins, cell)
        # keep only arcs that the SDF actually annotates (all specify paths
        # otherwise become extra delay paths and slow the model down)
        if cell in arcs:
            filtered = []
            for line in spec:
                keep = False
                for a, b in arcs[cell]:
                    if re.search(r"\b%s\b" % re.escape(a), line) and \
                       re.search(r"\b%s\b" % re.escape(b), line):
                        keep = True
                        break
                if keep:
                    filtered.append(line)
            spec = filtered or spec
        body = mods[cell]
        pos = body.rfind("endmodule")
        body = body[:pos] + "  specify\n" + "\n".join(spec) + "\n  endspecify\n\n" + body[pos:]
        emitted.append(body)

    if missing:
        print("WARNING: no Liberty/module for %s" % ", ".join(sorted(missing)),
              file=sys.stderr)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(
        "// Generated by generator/emit_gf180_timing_models.py -- do not edit.\n"
        "// Functional GF180 3.3 V cells + specify arcs so SDF annotation works.\n"
        "`timescale 1ns/1ps\n\n" + "\n\n".join(emitted) + "\n")
    print("wrote %s (%d cells, %d specify lines)" %
          (out, len(emitted), sum(len(b.split("specify", 1)[1].split("endspecify")[0].splitlines())
                                  for b in emitted)))


if __name__ == "__main__":
    main()
