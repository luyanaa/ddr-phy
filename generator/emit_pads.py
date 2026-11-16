#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Reusable pad-schematic generator.

ONE shared topology (specs/pads/topology.yaml) + N per-PDK device maps
(specs/pads/devices/*.yaml) -> N sets of generated artifacts under
sch/pads/<backend>/. No schematic is hand-drawn per PDK: change a device
map or the topology template and re-run this script.

The output is a TOPOLOGY TEMPLATE, not a designed pad. Every numeric
degree of freedom (W/L/NF/R/area/current/offset) stays an unresolved
parameter. The generator refuses to emit a characterized or signoff
claim while any of them is null.
"""
import json
import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
SPECS = ROOT / "specs" / "pads"
TPL = SPECS / "templates"
OUT = ROOT / "sch" / "pads"
REPORTS = ROOT / "reports"

COMPOSITE_SLOTS = {"PREDRIVER", "RX_INV"}
CONDITIONAL_SLOTS = {"NMOS_CORE", "PMOS_CORE"}


def load():
    topo = yaml.safe_load(open(SPECS / "topology.yaml"))
    maps = {}
    for p in sorted((SPECS / "devices").glob("*.yaml")):
        d = yaml.safe_load(open(p))
        maps[d["backend"]] = d
    return topo, maps


def render(text, tokens, conditions):
    def cond(m):
        return m.group(2) if conditions.get(m.group(1), False) else ""
    text = re.sub(r"@if (\w+)@\n?(.*?)@endif@\n?", cond, text, flags=re.S)
    for k, v in tokens.items():
        text = text.replace("@@" + k + "@@", str(v))
    return text


DEFAULT_MOS = "X_{name} {d} {g} {s} {b} {device} w={w} l={l} {fp}={nf} {mp}={m}"
DEFAULT_RES = "X_{name} {p} {q} {b} {device} r_length={l} r_width={w}"
DEFAULT_DIODE = "D_{name} {a} {c} {device} area={area}"


def mos_line(dev, name, slot, d, g, s, b, w, l, nf):
    sp = dev.get("spice", {})
    return sp.get("mos_format", DEFAULT_MOS).format(
        name=name, d=d, g=g, s=s, b=b,
        device="@@DEV_%s@@" % slot,
        w="@@P_%s@@" % w, l="@@P_%s@@" % l, nf="@@P_%s@@" % nf,
        m="@@P_M_DEVICE@@",
        fp=sp.get("finger_param", "nf"), mp=sp.get("mult_param", "m"))


def res_line(dev):
    sp = dev.get("spice", {})
    return sp.get("res_format", DEFAULT_RES).format(
        name="RSER", p="n_pre", q="PAD", b="VSSIO",
        device="@@DEV_RES_SERIES@@",
        w="@@P_W_R_SERIES@@", l="@@P_L_R_SERIES@@",
        m="@@P_M_DEVICE@@")


def diode_line(dev, name, slot, *, a=None, c=None, area, pad=None,
               vdd=None, vss=None):
    sp = dev.get("spice", {})
    return sp.get("diode_format", DEFAULT_DIODE).format(
        name=name, a=a, c=c, device="@@DEV_%s@@" % slot,
        area="@@P_%s@@" % area, pad=pad, vdd=vdd, vss=vss)


def tokens_for(topo, dev):
    t = {}
    t["BACKEND"] = dev["backend"]
    t["PDK"] = dev["pdk"]
    t["TOPOLOGY"] = "specs/pads/topology.yaml v%s" % topo["meta"]["version"]
    t["STATUS"] = dev["status"]
    t["LICENSE"] = dev.get("license", "TBD")
    t["MODEL_INCLUDE"] = dev.get("model_include", "TBD")
    t["DESIGN_INCLUDE"] = dev.get("design_include", "TBD")
    t["DDR1_STATUS"] = dev["ddr1"]["status"]
    t["DDR1_REASON"] = dev["ddr1"].get("reason", dev["ddr1"].get("note", ""))
    t["LEVEL_NOTE"] = dev.get("level_shifter_note", "core and IO rails differ")
    t["SIZE_NOTE"] = dev.get("size_note", "topology params are metres; check the PDK subckt unit convention")
    t["ESD_NOTE"] = dev.get("esd_note", "ESD device area/orientation still needs schematic review")
    t["CHAR_LIST"] = "\n".join("*   - " + c for c in topo["characterization"])
    for p in topo["params"]:
        t["P_" + p["id"]] = p["id"]
    for s in dev["slots"]:
        t["DEV_" + s] = dev["slots"][s].get("device") or "UNBOUND_" + s

    # Per-backend device-instantiation syntax. The shared topology is
    # expressed as line tokens so a PDK can use nf/ng, m/mr, w/l vs
    # r_length/r_width, and a 2-terminal diode model vs a 3-terminal
    # ESD subckt without forking the schematic.
    cond = conditions_for(dev)
    lines = {
        "LS_N_LINE": mos_line(dev, "LS_N", "NMOS_CORE",
                              "n_lsn", "OUT", "VSS", "VSS",
                              "W_N_PDRV", "L_PDRV", "NF_DEVICE"),
        "LS_P_LINE": mos_line(dev, "LS_P", "PMOS_CORE",
                              "n_lsp", "OUT", "VDD", "VDD",
                              "W_P_PDRV", "L_PDRV", "NF_DEVICE"),
        "LS_N2_LINE": mos_line(dev, "LS_N2", "NMOS_IO",
                               "n_lsn", "n_lsp", "VSSIO", "VSSIO",
                               "W_N_PDRV", "L_PDRV", "NF_DEVICE"),
        "LS_P2_LINE": mos_line(dev, "LS_P2", "PMOS_IO",
                               "n_lsp", "n_lsn", "VDDIO", "VDDIO",
                               "W_P_PDRV", "L_PDRV", "NF_DEVICE"),
        "PDRV_N_LINE": mos_line(dev, "PDRV_N", "NMOS_IO",
                                "n_pdrv", "n_gp", "VSSIO", "VSSIO",
                                "W_N_PDRV", "L_PDRV", "NF_DEVICE"),
        "PDRV_P_LINE": mos_line(dev, "PDRV_P", "PMOS_IO",
                                "n_pdrv", "n_gp", "VDDIO", "VDDIO",
                                "W_P_PDRV", "L_PDRV", "NF_DEVICE"),
        "OUT_P_LINE": mos_line(dev, "OUT_P", "PMOS_IO",
                               "n_pre", "n_gp", "VDDIO", "VDDIO",
                               "W_P_OUT", "L_P_OUT", "NF_P_OUT"),
        "OUT_N_LINE": mos_line(dev, "OUT_N", "NMOS_IO",
                               "n_pre", "n_gn", "VSSIO", "VSSIO",
                               "W_N_OUT", "L_N_OUT", "NF_N_OUT"),
        "RX_N_LINE": mos_line(dev, "RX_N", "NMOS_IO",
                              "IN", "PAD", "VSSIO", "VSSIO",
                              "W_RX_N", "L_PDRV", "NF_DEVICE"),
        "RX_P_LINE": mos_line(dev, "RX_P", "PMOS_IO",
                              "IN", "PAD", "VDDIO", "VDDIO",
                              "W_RX_P", "L_PDRV", "NF_DEVICE"),
        "VP_LINE": mos_line(dev, "VP", "NMOS_IO",
                            "n_outp", "PAD", "n_tail", "VSSIO",
                            "W_VREF_N", "L_PDRV", "NF_DEVICE"),
        "VN_LINE": mos_line(dev, "VN", "NMOS_IO",
                            "n_outn", "VREF", "n_tail", "VSSIO",
                            "W_VREF_N", "L_PDRV", "NF_DEVICE"),
        "LP_LINE": mos_line(dev, "LP", "PMOS_IO",
                            "n_outp", "n_outp", "VDDIO", "VDDIO",
                            "W_LOAD", "L_PDRV", "NF_DEVICE"),
        "LN_LINE": mos_line(dev, "LN", "PMOS_IO",
                            "n_outn", "n_outp", "VDDIO", "VDDIO",
                            "W_LOAD", "L_PDRV", "NF_DEVICE"),
        "VRX_N_LINE": mos_line(dev, "RX_N", "NMOS_IO",
                               "IN", "n_outn", "VSSIO", "VSSIO",
                               "W_RX_N", "L_PDRV", "NF_DEVICE"),
        "VRX_P_LINE": mos_line(dev, "RX_P", "PMOS_IO",
                               "IN", "n_outn", "VDDIO", "VDDIO",
                               "W_RX_P", "L_PDRV", "NF_DEVICE"),
        "RES_LINE": res_line(dev),
        "DIODE_UP_LINE": diode_line(dev, "ESD_UP", "DIODE_TO_VDDIO",
                                    a="PAD", c="VDDIO", area="ESD_AREA_UP",
                                    pad="PAD", vdd="VDDIO", vss="VSSIO"),
        "DIODE_DN_LINE": diode_line(dev, "ESD_DN", "DIODE_TO_VSSIO",
                                    a="VSSIO", c="PAD", area="ESD_AREA_DN",
                                    pad="PAD", vdd="VDDIO", vss="VSSIO"),
        "DIODE_CLAMP_LINE": diode_line(dev, "CLAMP", "DIODE_CLAMP",
                                       a="VSSIO", c="VDDIO", area="ESD_CLAMP_W",
                                       pad="VSSIO", vdd="VDDIO", vss="VSSIO"),
        "VREF_UP_LINE": diode_line(dev, "VREF_UP", "DIODE_TO_VDDIO",
                                   a="VREF", c="VDDIO", area="ESD_AREA_UP",
                                   pad="VREF", vdd="VDDIO", vss="VSSIO"),
        "VREF_DN_LINE": diode_line(dev, "VREF_DN", "DIODE_TO_VSSIO",
                                   a="VSSIO", c="VREF", area="ESD_AREA_DN",
                                   pad="VREF", vdd="VDDIO", vss="VSSIO"),
    }
    for k, v in lines.items():
        t[k] = render(v, t, cond)
    return t


def conditions_for(dev):
    ls = bool(dev.get("level_shifter_required", False)) or \
         (dev.get("core_v") != dev.get("vddio_v"))
    return {"LEVEL_SHIFTER": ls, "NO_LEVEL_SHIFTER": not ls, "PREDRIVER": True, "REAL_RSER": True, "IDEAL_RSER": False, "ESD": True, "NO_ESD": False, "RX": True}


def bound(dev, topo):
    cond = conditions_for(dev)
    for s in topo["slots"]:
        sid = s["id"]
        if sid in COMPOSITE_SLOTS:
            continue
        if sid in CONDITIONAL_SLOTS and not cond["LEVEL_SHIFTER"]:
            continue
        if not dev["slots"].get(sid, {}).get("device"):
            return False
    return True


def port_symbols(ports):
    lines = []
    for i, (name, kind) in enumerate(ports):
        x = -260 + (i % 5) * 130
        y = -160 - (i // 5) * 60
        sym = {"in": "devices/ipin.sym", "out": "devices/opin.sym",
               "inout": "devices/iopin.sym", "supply": "devices/ipin.sym"}[kind]
        lines.append("C {%s} %d %d 0 0 {name=p%d lab=%s}" % (sym, x, y, i, name))
    return "\n".join(lines)


def spice_body(text):
    keep = []
    for line in text.splitlines():
        if line.startswith(".subckt") or line.startswith(".ends"):
            continue
        keep.append(line)
    return "\n".join(keep)


def dot_text(topo, dev):
    lines = ["digraph pad_topology {", "  rankdir=LR;",
             '  label="%s - generated topology, NOT characterized";' % dev["backend"],
             '  labelloc=t;', '  node [shape=box];']
    ls = conditions_for(dev)["LEVEL_SHIFTER"]
    edges = [("core OUT/OE_N", "level shifter" if ls else "pre-driver"),
             ("pre-driver", "tri-state output"), ("tri-state output", "series R"),
             ("series R", "PAD"), ("PAD", "ESD diodes + clamp"),
             ("PAD", "SDR CMOS RX"), ("SDR CMOS RX", "core IN")]
    if ls:
        edges.append(("level shifter", "pre-driver"))
    for a, b in edges:
        lines.append('  "%s" -> "%s";' % (a, b))
    lines.append('  "DDR1: PAD/VREF diff pair -> single-ended -> core IN" [shape=note, style=dashed];')
    lines.append("}")
    return "\n".join(lines) + "\n"


def main():
    topo, maps = load()
    if not all(p["value"] is None for p in topo["params"]):
        print("ERROR: a pad parameter has a concrete value", file=sys.stderr)
        return 1
    OUT.mkdir(parents=True, exist_ok=True)
    REPORTS.mkdir(exist_ok=True)

    rows = []
    blockers = []
    for name, dev in sorted(maps.items()):
        outdir = OUT / name
        outdir.mkdir(exist_ok=True)
        tokens = tokens_for(topo, dev)
        conds = conditions_for(dev)
        is_bound = bound(dev, topo)
        files = []

        req = {"generated_by": "generator/emit_pads.py", "backend": name,
               "simulatable": False, "signoff": False,
               "unresolved_params": [p["id"] for p in topo["params"]],
               "params": topo["params"]}
        (outdir / "required_params.json").write_text(json.dumps(req, indent=2) + "\n")
        (outdir / "pad_topology.dot").write_text(dot_text(topo, dev))
        files += ["required_params.json", "pad_topology.dot"]

        chtb = render(open(TPL / "char_tb.spice.tpl").read(), tokens, conds)
        (outdir / "char_tb.spice").write_text(chtb)
        files.append("char_tb.spice")

        if is_bound:
            specs = [("sdr_bidir_pad.spice.tpl", "sdr_bidir_pad.spice", "sdr"),
                     ("vref_receiver.spice.tpl", "vref_receiver.spice", "vref")]
            ports = {
                "sdr": [("OUT","in"),("OE_N","in"),("IN","out"),("PAD","inout"),
                        ("PU_OK","in"),("VDD","supply"),("VSS","supply"),
                        ("VDDIO","supply"),("VSSIO","supply")],
                "vref": [("PAD","in"),("VREF","in"),("IN","out"),("PU_OK","in"),
                         ("VDD","supply"),("VSS","supply"),
                         ("VDDIO","supply"),("VSSIO","supply")],
            }
            for tpl, fname, key in specs:
                body = render(open(TPL / tpl).read(), tokens, conds)
                left = sorted(set(re.findall(r"@@[A-Z0-9_]+@@", body)))
                if left:
                    print("ERROR: unresolved tokens in %s: %s" % (fname, left), file=sys.stderr)
                    return 1
                (outdir / fname).write_text(body)
                files.append(fname)
                sch = render(open(TPL / "cell.sch.tpl").read(), {
                    "PORT_SYMBOLS": port_symbols(ports[key]),
                    "SPICE_BODY": spice_body(body),
                }, {})
                (outdir / fname.replace(".spice", ".sch")).write_text(sch)
                files.append(fname.replace(".spice", ".sch"))
        else:
            (outdir / "DEVICE_MAP_TBD.md").write_text(
                "# %s\n\nDevice map is not yet bound (status: %s). No SPICE or xschem\n"
                "schematic is emitted for this backend, because that would require\n"
                "inventing device names. Verify the PDK device cards first.\n\n"
                "**Blocker:** %s\n"
                % (name, dev["status"], dev.get("blocker", "not recorded")))
            files.append("DEVICE_MAP_TBD.md")

        manifest = {
            "generated_by": "generator/emit_pads.py", "backend": name,
            "pdk": dev["pdk"], "status": dev["status"], "decision": dev["decision"],
            "simulatable": False, "signoff": False, "device_map_bound": is_bound,
            "blocker": dev.get("blocker"),
            "level_shifter": conds["LEVEL_SHIFTER"],
            "core_v": dev.get("core_v"), "vddio_v": dev.get("vddio_v"),
            "sdr": dev.get("sdr", {}), "ddr1": dev.get("ddr1", {}),
            "license": dev.get("license"), "forbidden": dev.get("forbidden", []),
            "slots": dev["slots"],
            "unresolved_param_count": len(topo["params"]), "files": files,
        }
        (outdir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        files.append("manifest.json")

        ddr1 = dev["ddr1"]
        readme = [
            "# %s pad topology (GENERATED - DO NOT EDIT)" % name, "",
            "Generated by generator/emit_pads.py from specs/pads/topology.yaml",
            "and specs/pads/devices/%s.yaml. Regenerate, do not hand-edit." % name, "",
            "**STATUS: %s. NOT SIMULATABLE. NOT A SIGNOFF PAD.**" % dev["status"], "",
            "- All %d sizing parameters are unresolved (required_params.json)." % len(topo["params"]),
            "- PAD_OE_CTRL and the pre-driver stage count are placeholders.",
            "- Diode orientation, bulk ties and guard rings need schematic review.",
            "- Decision: **%s** (see reports/capability_report.md)." % dev["decision"], "",
            "## Supplies", "",
            "- core %.1f V / VDDIO %.1f V; level shifter %s." % (
                dev.get("core_v", 0), dev.get("vddio_v", 0),
                "REQUIRED" if conds["LEVEL_SHIFTER"] else "not required (nominal voltages equal)"),
            "- VDDIO and core VDD are separate rails; VSSIO separate from VSS.", "",
            "## DDR1 / VREF", "",
            "- decision: **%s**" % ddr1["status"],
            "- %s" % ddr1.get("reason", ddr1.get("note", "")), "",
            "## Forbidden", "",
        ] + ["- " + f for f in dev.get("forbidden", [])] + [
            "", "## Files", "",
        ] + ["- " + f for f in files] + [
            "", "## What has NOT happened", "",
            "- No load simulation, no drive-strength or width selection.",
            "- No PVT / min-max SPICE, no PEX, no IBIS, no SI/PI, no DRC/LVS.",
            "- No tOE_on / tOE_off measurement; those capability fields stay null.",
            "- char_tb.spice is a measurement checklist, not a runnable testbench.", "",
        ]
        if ddr1["status"] != "SUPPORTED":
            readme += [
                "## DDR1 / VREF is a long-term plan, not a current deliverable", "",
                "- status: **%s**" % ddr1["status"],
                "- target: %s" % ddr1.get("target_phase", "TBD"),
                "- %s" % ddr1.get("reason", ""),
                "", "The VREF receiver here is a **topology study only**. It is not a",
                "supported DDR1 pad and must not be used for a tapeout claim.", "",
            ]
        (outdir / "README.md").write_text("\n".join(readme) + "\n")
        rows.append((name, dev["decision"], is_bound, len(files)))
        if not is_bound:
            blockers.append((name, dev.get("blocker", "not recorded")))

    rep = ["# Pad generator report", "",
           "Generated by generator/emit_pads.py. One shared topology + per-PDK device maps.",
           "", "**Overall: NO_GO. All outputs are topology templates, not designed pads.**", "",
           "| backend | decision | device map bound | files |", "|---|---|---|---|"]
    for n, d, b, nf in rows:
        rep.append("| %s | %s | %s | %d |" % (n, d, "yes" if b else "no (TBD)", nf))
    if blockers:
        rep += ["", "## Unbound maps", ""]
        rep += ["- **%s**: %s" % (n, why) for n, why in blockers]
    rep += ["", "Unresolved sizing parameters: %d (all null)." % len(topo["params"]), "",
            "Not performed: load simulation, width/finger selection, PVT corners,",
            "PEX/SPICE/IBIS/SI-PI, DRC/LVS, guard-ring rules, ESD qualification.", "",
            "All VREF receivers are topology studies: sky130/IHP DDR1 is TBD (no",
            "characterized 2.5 V IO); gf180mcu DDR1 is DEFERRED_LONG_TERM.", ""]
    (REPORTS / "pad_generator_report.md").write_text("\n".join(rep) + "\n")
    for n, d, b, nf in rows:
        print("%-12s %s  bound=%s  files=%d" % (n, d, b, nf))
    print("report: reports/pad_generator_report.md")
    return 0


if __name__ == "__main__":
    sys.exit(main())
