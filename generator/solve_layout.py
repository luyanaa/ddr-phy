#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Composite-constraint pad layout solver.

Inputs: 31 design params (specs/pads/topology.yaml), 10 PDK rule inputs
(specs/pads/constraints.yaml), and the generated pad netlist.
Output: derived-quantity evaluation, composite constraint statuses, a
layout placement plan, a dependency graph and a KLayout drawing script.

Default mode is SYMBOLIC: all sizing params are null, so the solver emits
a clearly labelled topology-only GDS and refuses a DRC-clean claim.
With --params FILE concrete values are used for dimensional geometry,
but a DRC-clean claim is still refused because PDK rules remain TBD.

No expression evaluation on file data: derived ops come from a closed
whitelist. No DRC deck, no signoff, no invented numbers.
"""
import argparse
import json
import math
import subprocess
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
SPECS = ROOT / "specs" / "pads"
OUT = ROOT / "sch" / "pads"
REPORTS = ROOT / "reports"

OPS = {
    "sum":     lambda a, f: sum(a),
    "product": lambda a, f: math.prod(a),
    "scale":   lambda a, f: a[0] * f,
    "sqrt":    lambda a, f: math.sqrt(a[0]),
    "div":     lambda a, f: (a[0] / a[1]) if a[1] else None,
    "max":     lambda a, f: max(a),
    "min":     lambda a, f: min(a),
}
LAYERS = {"device": [1, 0], "rail": [2, 0], "guard_ring": [3, 0],
          "pad": [4, 0], "label": [5, 0]}


def load():
    topo = yaml.safe_load(open(SPECS / "topology.yaml"))
    cons = yaml.safe_load(open(SPECS / "constraints.yaml"))
    return topo, cons


def values_for(topo, cons, params_file):
    v = {p["id"]: p["value"] for p in topo["params"]}
    v.update({p["id"]: p["value"] for p in cons["pdk_rules"]})
    if params_file:
        extra = json.load(open(params_file))
        unknown = [k for k in extra if k not in v]
        if unknown:
            raise KeyError("unknown params in --params: " + ", ".join(sorted(unknown)))
        v.update(extra)
    return v


def evaluate(v, cons):
    derived, unresolved = {}, {}
    for d in cons["derived"]:
        args, missing = [], []
        for a in d["args"]:
            x = derived[a] if a in derived else v.get(a)
            if x is None:
                missing.append(a)
            args.append(x)
        if missing:
            derived[d["id"]] = None
            unresolved[d["id"]] = missing
        else:
            try:
                derived[d["id"]] = OPS[d["op"]](args, d.get("factor", 1))
            except (ValueError, ZeroDivisionError, OverflowError) as e:
                derived[d["id"]] = None
                unresolved[d["id"]] = ["op error: " + str(e)]
    ns = dict(v)
    ns.update(derived)
    return derived, unresolved, ns


def upstream(name, cons, visiting=None):
    visiting = set() if visiting is None else set(visiting)
    if name in visiting:
        return set()
    visiting.add(name)
    d = next((x for x in cons["derived"] if x["id"] == name), None)
    if d is None:
        return {name}
    out = set()
    for a in d["args"]:
        out |= upstream(a, cons, visiting)
    return out


def check_constraint(c, ns, cons):
    base = {"id": c["id"], "class": c["class"], "severity": c["severity"],
            "check": c["check"], "note": c.get("note", "")}
    if c["check"] == "structural":
        base.update({"status": "structural", "upstream": []})
        return base
    l, r = ns.get(c["lhs"]), ns.get(c["rhs"])
    up = sorted(upstream(c["lhs"], cons) | upstream(c["rhs"], cons))
    base["upstream"] = up
    base["lhs"], base["rhs"] = c["lhs"], c["rhs"]
    if l is None or r is None:
        base["status"] = "unresolved"
        base["unresolved_operands"] = [k for k, x in (("lhs", l), ("rhs", r)) if x is None]
        return base
    ok = {"le": l <= r, "ge": l >= r, "eq": l == r}[c["check"]]
    base.update({"status": "satisfied" if ok else "violated",
                 "lhs_value": l, "rhs_value": r})
    return base


def parse_netlist(path):
    inst = []
    for line in open(path):
        t = line.strip().split()
        if not t or t[0][0] not in ("X", "D", "I"):
            continue
        if "*" in t[0]:
            continue
        rest = [x for x in t[1:] if "=" not in x]
        if len(rest) < 2:
            continue
        inst.append({"name": t[0], "device": rest[-1], "nets": rest[:-1],
                     "kind": "diode" if t[0][0] == "D" else "instance"})
    return inst


def placement_for(backend, netlist, ns, mode):
    insts = parse_netlist(netlist)
    boxes = []
    for i, x in enumerate(insts):
        col, row = i % 3, i // 3
        sym = [col * 25, row * 15, 20, 10]
        box = sym if mode == "symbolic" else None
        item = dict(x)
        item["symbolic_box"] = sym
        item["bbox_um"] = box if mode == "dimensional" else None
        boxes.append(item)
    resolved = ns.get("CELL_WIDTH") is not None and ns.get("CELL_HEIGHT") is not None
    return {
        "generated_by": "generator/solve_layout.py",
        "backend": backend, "cell": "sdr_bidir_pad", "mode": mode,
        "status": "NOT_DRC_CLEAN",
        "drc_clean": False,
        "note": "Symbolic topology sketch, not a designed layout. All sizing params are unresolved."
                if mode == "symbolic" else
                "Dimensional geometry from concrete params, but PDK DRC rules are still TBD.",
        "layers": LAYERS,
        "instances": boxes,
        "nets": sorted({n for x in boxes for n in x["nets"]}),
        "rails": ["VDD", "VSS", "VDDIO", "VSSIO"],
        "guard_ring": {"present": True, "spacing_um": ns.get("GUARD_RING_SPACING"),
                       "width_um": ns.get("GUARD_RING_WIDTH")},
        "cell_width_um": ns.get("CELL_WIDTH"),
        "cell_height_um": ns.get("CELL_HEIGHT"),
        "bbox_um": None,
        "labels": ["TOPOLOGY ONLY", "NOT DRC CLEAN", "SIZES TBD"],
        "resolved_geometry": resolved,
    }


def dot_graph(cons, results):
    lines = ["digraph composite_constraints {", "  rankdir=LR;",
             '  label="composite constraint graph (one param drives several classes)";',
             "  labelloc=t;", "  node [shape=box];"]
    for d in cons["derived"]:
        lines.append('  "%s" [shape=ellipse];' % d["id"])
        for a in d["args"]:
            lines.append('  "%s" -> "%s";' % (a, d["id"]))
    for r in results:
        lines.append('  "%s" [shape=diamond,style=filled,fillcolor=lightgrey];' % r["id"])
        for u in r.get("upstream", [])[:6]:
            lines.append('  "%s" -> "%s" [style=dotted];' % (u, r["id"]))
    lines.append("}")
    return "\n".join(lines) + "\n"


def klayout_script(placement_path, gds_path, mode):
    return '''# GENERATED by generator/solve_layout.py -- DO NOT EDIT BY HAND
# KLayout batch script: python3 -m klayout? use: klayout -b -r this_file.py
import pya, json
PLACEMENT = %r
OUT_GDS = %r
d = json.load(open(PLACEMENT))
lay = pya.Layout()
suffix = "TOPOLOGY_ONLY" if d["mode"] == "symbolic" else "DIMENSIONAL_NOT_DRC_CLEAN"
top = lay.create_cell(d["cell"] + "_" + suffix)
layers = {k: lay.layer(v[0], v[1]) for k, v in d["layers"].items()}
for x in d["instances"]:
    b = x["symbolic_box"] if d["mode"] == "symbolic" else x["bbox_um"]
    if b is None:
        continue
    top.shapes(layers["device" if x["kind"] == "instance" else "guard_ring"]).insert(
        pya.Box(b[0], b[1], b[0] + b[2], b[1] + b[3]))
# rails and pad outline are symbolic rectangles only
top.shapes(layers["rail"]).insert(pya.Box(-5, -5, 80, -3))
top.shapes(layers["rail"]).insert(pya.Box(-5, 65, 80, 67))
top.shapes(layers["guard_ring"]).insert(pya.Box(-10, -10, 85, 72))
top.shapes(layers["pad"]).insert(pya.Box(30, 25, 50, 45))
try:
    top.shapes(layers["label"]).insert(pya.Text(" / ".join(d["labels"]), pya.Trans(0, -20)))
except Exception as e:
    print("LABEL_SKIPPED", e)
lay.write(OUT_GDS)
print("GDS_WRITTEN", OUT_GDS, "MODE", d["mode"], "DRC_CLEAN", d["drc_clean"])
''' % (str(placement_path), str(gds_path))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--params", help="JSON file with concrete sizing values (test only)")
    ap.add_argument("--no-gds", action="store_true", help="skip running KLayout")
    args = ap.parse_args()

    topo, cons = load()
    v = values_for(topo, cons, args.params)
    derived, unresolved, ns = evaluate(v, cons)
    results = [check_constraint(c, ns, cons) for c in cons["constraints"]]

    unresolved_params = sorted([k for k, x in v.items() if x is None])
    mode = "symbolic" if unresolved_params else "dimensional"
    counts = {}
    for r in results:
        counts[r["status"]] = counts.get(r["status"], 0) + 1

    backend = "gf180mcuD"
    outdir = OUT / backend / "layout"
    outdir.mkdir(parents=True, exist_ok=True)
    # Never leave a GDS from the other mode behind: a dimensional run with
    # synthetic params must not be mistaken for the committed default.
    other = outdir / ("sdr_bidir_pad_dimensional.gds" if mode == "symbolic"
                      else "sdr_bidir_pad_topology.gds")
    if other.exists():
        other.unlink()
    netlist = OUT / backend / "sdr_bidir_pad.spice"

    lc = {"generated_by": "generator/solve_layout.py", "backend": backend,
          "mode": mode, "drc_clean": False,
          "unresolved_param_count": len(unresolved_params),
          "unresolved_params": unresolved_params,
          "derived": derived, "derived_unresolved": unresolved,
          "constraints": results, "constraint_status_counts": counts,
          "pdk_rule_inputs": cons["pdk_rules"]}
    (outdir / "layout_constraints.json").write_text(json.dumps(lc, indent=2) + "\n")

    pl = placement_for(backend, netlist, ns, mode)
    (outdir / "placement.json").write_text(json.dumps(pl, indent=2) + "\n")
    (outdir / "constraint_graph.dot").write_text(dot_graph(cons, results))

    script = klayout_script(outdir / "placement.json",
                            outdir / ("sdr_bidir_pad_topology.gds" if mode == "symbolic"
                                      else "sdr_bidir_pad_dimensional.gds"), mode)
    (outdir / "draw_layout.py").write_text(script)

    plan = ["# %s layout plan (GENERATED)" % backend, "",
            "Mode: **%s**. drc_clean: **false**. NOT A TAPEOUT LAYOUT." % mode, "",
            "## Composite constraint status", "",
            "| constraint | class | severity | status | upstream inputs |",
            "|---|---|---|---|---|"]
    for r in results:
        plan.append("| %s | %s | %s | %s | %s |" % (
            r["id"], r["class"], r["severity"], r["status"],
            ", ".join(r.get("upstream", [])[:4]) or "-"))
    plan += ["", "Unresolved inputs: %d (of %d)." % (len(unresolved_params), len(v)),
             "Derived quantities unresolved: %d." % len(unresolved), "",
             "## Why composite", "",
             "CELL_WIDTH and CELL_HEIGHT are derived from W/NF/M, guard-ring",
             "spacing/width, rail width and ESD diode sides. One parameter",
             "therefore drives geometry, ESD, latch-up and power-EM checks",
             "at the same time; see constraint_graph.dot.", "",
             "## Files", "",
             "- layout_constraints.json - evaluated composite constraints",
             "- placement.json - device instances, nets, rails, symbolic boxes",
             "- constraint_graph.dot - composite dependency graph",
             "- draw_layout.py - KLayout batch script (pya)",
             "- sdr_bidir_pad_topology.gds - symbolic topology sketch only", "",
             "## Not a layout yet", ""]
    plan += ["- " + x for x in cons["not_yet"]] + [""]
    (outdir / "layout_plan.md").write_text("\n".join(plan) + "\n")

    gds = None
    if not args.no_gds:
        target = outdir / ("sdr_bidir_pad_topology.gds" if mode == "symbolic"
                           else "sdr_bidir_pad_dimensional.gds")
        try:
            r = subprocess.run(["klayout", "-b", "-r", str(outdir / "draw_layout.py")],
                               capture_output=True, text=True, timeout=90)
            if target.exists():
                gds = target
            else:
                print("WARNING: KLayout did not write GDS: " + r.stdout[-300:], file=sys.stderr)
        except (FileNotFoundError, subprocess.TimeoutExpired) as e:
            print("WARNING: KLayout run skipped: " + str(e), file=sys.stderr)

    rep = ["# Layout solver report", "",
           "Generated by generator/solve_layout.py.", "",
           "**Overall: NOT DRC CLEAN. Symbolic topology sketch only.**", "",
           "| backend | mode | resolved params | constraints | status counts | GDS |",
           "|---|---|---|---|---|---|",
           "| %s | %s | %d/%d | %d | %s | %s |" % (
               backend, mode, len(v) - len(unresolved_params), len(v), len(results),
               json.dumps(counts), gds.name if gds else "none"), "",
           "Composite classes: " + ", ".join(cons["meta"]["classes"]) + ".", "",
           "No PDK DRC/ESD/EM rule is certified; 10 rule inputs are all TBD.",
           "No sizing parameter has a concrete value by default.", "",
           "gf180mcu DDR1 remains DEFERRED_LONG_TERM (long-term plan).", ""]
    REPORTS.mkdir(exist_ok=True)
    (REPORTS / "layout_solver_report.md").write_text("\n".join(rep) + "\n")

    print("backend=%s mode=%s unresolved=%d/%d constraints=%d %s gds=%s" % (
        backend, mode, len(unresolved_params), len(v), len(results), counts,
        gds.name if gds else "none"))
    print("report: reports/layout_solver_report.md")
    return 0


if __name__ == "__main__":
    sys.exit(main())
