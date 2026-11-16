#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Runnable first-pass characterization slice for the SDR output pad.

This is NOT a signoff flow and NOT an ESD qualification. It takes an
explicitly labelled sizing fixture (meta.status: design_assumption), renders
the shared pad topology with concrete .param values, and measures:

  - tOE_on / tOE_off (from the OE input to the PAD, pre-driver excluded)
  - PAD rise/fall slew into a placeholder 50 ohm / 5 pF load
  - SDR receiver input threshold (PAD -> IN)
  - power-up Hi-Z current with PU_OK low (output stage disabled)

The level shifter and pre-driver are deliberately excluded from this first
slice. The output-stage gates are driven by a behavioural OE control in the
testbench. Every reported number belongs to the fixture, not to a designed
or characterized pad.
"""
import argparse
import glob
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

import emit_pads as ep

ROOT = Path(__file__).resolve().parent.parent
SPECS = ROOT / "specs" / "pads"
REPORTS = ROOT / "reports"
OUT = ROOT / "sim" / "char"
MEASURES = ("t_oe_on", "t_oe_off", "tr_pad", "tf_pad", "vth_pad", "ihiz_max", "iesd_max",
            "t_in", "voh_2ma", "vol_2ma")


def discover_root(dev):
    c = dev.get("char", {})
    pats = sorted(glob.glob(os.path.expanduser(c["root_glob"])))
    must = c.get("root_must_contain")
    for p in pats:
        if must and not (Path(p) / must).exists():
            continue
        return Path(p)
    raise SystemExit("ERROR: no PDK root matched %s" % c.get("root_glob"))


def load_sizing(backend, path):
    f = path or (SPECS / "sizing" / ("%s.first_pass.yaml" % backend))
    d = yaml.safe_load(open(f))
    meta = d.get("meta", {})
    if meta.get("status") != "design_assumption":
        raise SystemExit("ERROR: %s status must be design_assumption" % f)
    if meta.get("backend") != backend:
        raise SystemExit("ERROR: fixture backend mismatch in %s" % f)
    vals = {}
    for p in d.get("params", []):
        if p["id"] in vals:
            raise SystemExit("ERROR: duplicate sizing id %s" % p["id"])
        vals[p["id"]] = p
    return d, vals


def spice_num(value, unit, backend):
    try:
        value = float(value)
    except (TypeError, ValueError):
        raise SystemExit("ERROR: non-numeric sizing value %r" % (value,))
    if unit == "count":
        return str(int(value))
    if unit == "um":
        # sky130 subckts use .option scale=1u, so w/l/area are in microns.
        return ("%gu" % value) if backend != "sky130" else ("%g" % value)
    if unit in ("m", "m2", "A", "V"):
        return "%.6e" % value if unit in ("m", "m2", "A") else ("%g" % value)
    raise SystemExit("ERROR: unknown sizing unit %s" % unit)


def param_block(topo, vals, backend):
    missing = [p["id"] for p in topo["params"] if p["id"] not in vals]
    extra = [k for k in vals if k not in {p["id"] for p in topo["params"]}]
    if missing or extra:
        raise SystemExit("ERROR: sizing missing=%s extra=%s" % (missing, extra))
    lines = [".param " + p["id"] + "=" + spice_num(
        vals[p["id"]]["value"], vals[p["id"]]["unit"], backend)
        for p in topo["params"]]
    return "\n".join(lines)


def model_lines(dev, root, corner="tt"):
    char = dev.get("char", {})
    csec = char.get("corners", {}).get(corner, corner)
    lines = []
    for inc in char.get("includes", []):
        p = (root / inc.get("lib", inc.get("include", ""))).resolve()
        if not p.exists():
            raise SystemExit("ERROR: model file not found: %s" % p)
        if "lib" in inc:
            sec = inc.get("corners", {}).get(corner)
            if sec is None and inc.get("section"):
                sec = csec
            lines.append('.lib "%s" %s' % (p, sec))
        else:
            lines.append('.include "%s"' % p)
    return "\n".join(lines)


def tran_deck(netlist_name, models, vdd, vddio, load_k=1.0, load_pf=1.0, temp=None):
    half = vddio / 2.0
    tline = "" if temp is None else ".temp %g\n" % temp
    return f"""
* TRANSIENT SLICE: OE timing and PAD slew. Fixture values, not signoff.
{models}
{tline}.include "{netlist_name}"
VDD VDD 0 {vdd:g}
VSS VSS 0 0
VDDIO VDDIO 0 {vddio:g}
VSSIO VSSIO 0 0
VPU PU_OK 0 PWL(0 0 1n 0 1.1n {vddio:g} 24n {vddio:g})
VOE OE_N 0 PWL(0 {vddio:g} 3.9n {vddio:g} 4.0n 0 17.9n 0 18.0n {vddio:g} 24n {vddio:g})
VOUT OUT 0 PWL(0 {vdd:g} 5.9n {vdd:g} 6.0n 0 11.9n 0 12.0n {vdd:g} 24n {vdd:g})
VTT VTT 0 1.65
RLOAD PAD VTT {load_k:g}k
CLOAD PAD 0 {load_pf:g}p
* simulation-only bleed resistor; not a design element
RIN IN VSSIO 1G
X_DUT OUT OE_N IN PAD PU_OK VDD VSS VDDIO VSSIO sdr_bidir_pad
.tran 20p 24n
.options trtol=10 reltol=1e-3
.meas tran t_oe_on TRIG v(OE_N) VAL={half:g} FALL=1 TARG v(PAD) VAL=2.9 RISE=1
.meas tran t_oe_off TRIG v(OE_N) VAL={half:g} RISE=1 TARG v(PAD) VAL=1.8 FALL=2
.meas tran tr_pad TRIG v(PAD) VAL=0.33 RISE=1 TARG v(PAD) VAL=2.9 RISE=2
.meas tran tf_pad TRIG v(PAD) VAL=2.9 FALL=1 TARG v(PAD) VAL=0.33 FALL=1
.end
"""


def dc_deck(netlist_name, models, vdd, vddio, temp=None):
    tline = "" if temp is None else ".temp %g\n" % temp
    return f"""
* DC SLICE: receiver threshold and power-up Hi-Z current. Fixture values.
{models}
{tline}.include "{netlist_name}"
VDD VDD 0 {vdd:g}
VSS VSS 0 0
VDDIO VDDIO 0 {vddio:g}
VSSIO VSSIO 0 0
VPU PU_OK 0 0
VOE OE_N 0 {vddio:g}
VOUT OUT 0 0
VEXT PAD 0 0
* simulation-only bleed resistor; not a design element
RIN IN VSSIO 1G
X_DUT OUT OE_N IN PAD PU_OK VDD VSS VDDIO VSSIO sdr_bidir_pad
.dc VEXT 0 3.3 0.02
.meas dc vth_pad FIND v(PAD) WHEN v(IN)=1.65
.meas dc ihiz_max MAX i(VEXT)
.end
"""


def esd_deck(netlist_name, models, vdd, vddio, temp=None):
    tline = "" if temp is None else ".temp %g\n" % temp
    return f"""
* ESD LEAKAGE SLICE: reverse-biased diodes only, not ESD qualification.
{models}
{tline}.include "{netlist_name}"
VDD VDD 0 {vdd:g}
VSS VSS 0 0
VDDIO VDDIO 0 {vddio:g}
VSSIO VSSIO 0 0
VPU PU_OK 0 0
VOE OE_N 0 {vddio:g}
VOUT OUT 0 0
VEXT PAD 0 0
X_DUT OUT OE_N IN PAD PU_OK VDD VSS VDDIO VSSIO sdr_bidir_pad
.dc VEXT 0 3.3 0.02
.meas dc iesd_max MAX i(VEXT)
.end
"""


def tin_deck(netlist_name, models, vdd, vddio, temp=None):
    tline = "" if temp is None else ".temp %g\n" % temp
    return f"""
* INPUT DELAY: PAD pulse to receiver IN. Fixture values, not signoff.
{models}
{tline}
.include "{netlist_name}"
VDD VDD 0 {vdd:g}
VSS VSS 0 0
VDDIO VDDIO 0 {vddio:g}
VSSIO VSSIO 0 0
VPU PU_OK 0 {vddio:g}
VOE OE_N 0 {vddio:g}
VOUT OUT 0 0
VEXT PAD 0 PWL(0 0 2n 0 2.1n {vddio:g} 8n {vddio:g} 8.1n 0 12n 0)
RIN IN VSSIO 1G
X_DUT OUT OE_N IN PAD PU_OK VDD VSS VDDIO VSSIO sdr_bidir_pad
.tran 10p 14n
.meas tran t_in TRIG v(PAD) VAL={vddio/2:g} RISE=1 TARG v(IN) VAL={vddio/2:g} RISE=1
.end
"""


def ioh_deck(netlist_name, models, vdd, vddio, temp=None):
    tline = "" if temp is None else ".temp %g\n" % temp
    return f"""
* OUTPUT HIGH DRIVE: VOH at IOH=2 mA. Fixture/design assumption.
{models}
{tline}
.include "{netlist_name}"
VDD VDD 0 {vdd:g}
VSS VSS 0 0
VDDIO VDDIO 0 {vddio:g}
VSSIO VSSIO 0 0
VPU PU_OK 0 {vddio:g}
VOE OE_N 0 0
VOUT OUT 0 {vdd:g}
ILOAD PAD 0 0
X_DUT OUT OE_N IN PAD PU_OK VDD VSS VDDIO VSSIO sdr_bidir_pad
.dc ILOAD 0 3m 0.1m
.meas dc voh_2ma FIND v(PAD) WHEN i(ILOAD)=2m
.end
"""


def iol_deck(netlist_name, models, vdd, vddio, temp=None):
    tline = "" if temp is None else ".temp %g\n" % temp
    return f"""
* OUTPUT LOW DRIVE: VOL at IOL=2 mA. Fixture/design assumption.
{models}
{tline}
.include "{netlist_name}"
VDD VDD 0 {vdd:g}
VSS VSS 0 0
VDDIO VDDIO 0 {vddio:g}
VSSIO VSSIO 0 0
VPU PU_OK 0 {vddio:g}
VOE OE_N 0 0
VOUT OUT 0 0
ILOAD VDDIO PAD 0
X_DUT OUT OE_N IN PAD PU_OK VDD VSS VDDIO VSSIO sdr_bidir_pad
.dc ILOAD 0 3m 0.1m
.meas dc vol_2ma FIND v(PAD) WHEN i(ILOAD)=2m
.end
"""


def run_ngspice(workdir, deck, flags, pdk_root):
    env = dict(os.environ)
    env["PDK_ROOT"] = str(pdk_root)
    cmd = ["ngspice", "-b"] + list(flags) + [str(deck.resolve())]
    r = subprocess.run(cmd, cwd=str(workdir), capture_output=True, text=True,
                       env=env, timeout=600)
    text = r.stdout + "\n" + r.stderr
    if r.returncode != 0:
        raise SystemExit("ERROR: ngspice failed in %s\n%s" % (deck, text[-3000:]))
    return text


def parse_measures(text):
    out = {}
    for line in text.splitlines():
        m = re.match(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([-+0-9.eE]+)", line)
        if m:
            out[m.group(1)] = float(m.group(2))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--backend", default="gf180mcuD")
    ap.add_argument("--sizing", help="sizing fixture YAML")
    ap.add_argument("--corner", default="tt", help="tt/ss/ff (device map corners)")
    ap.add_argument("--temp", type=float, help="simulation temperature in C")
    ap.add_argument("--vdd", type=float, help="core supply override")
    ap.add_argument("--vddio", type=float, help="IO supply override")
    ap.add_argument("--load-kohm", type=float, default=1.0)
    ap.add_argument("--load-pf", type=float, default=1.0)
    ap.add_argument("--tag", default="", help="report/netlist suffix")
    args = ap.parse_args()

    topo, maps = ep.load()
    dev = maps[args.backend]
    if not ep.bound(dev, topo):
        raise SystemExit("ERROR: %s device map is not bound" % args.backend)
    if not dev.get("char"):
        raise SystemExit("ERROR: %s has no machine-readable char wiring" % args.backend)

    _, vals = load_sizing(args.backend, args.sizing)
    root = discover_root(dev)
    workdir = root / dev["char"].get("cwd", ".")
    outdir = OUT / args.backend
    outdir.mkdir(parents=True, exist_ok=True)
    suffix = args.tag or ""

    # Render the shared topology with the char conditions: no level shifter,
    # no pre-driver. The output stage and receiver remain.
    tokens = ep.tokens_for(topo, dev)
    char_meta = yaml.safe_load(open(args.sizing or (SPECS / "sizing" / ("%s.first_pass.yaml" % args.backend))))["meta"].get("char", {})
    series_r = char_meta.get("series_r_ohm")
    vdd = args.vdd if args.vdd is not None else char_meta.get("vdd_v")
    vddio = args.vddio if args.vddio is not None else char_meta.get("vddio_v")
    temp = args.temp if args.temp is not None else dev["char"].get("temps", {}).get(args.corner)
    if series_r is None or vdd is None or vddio is None:
        raise SystemExit("ERROR: fixture meta.char needs series_r_ohm, vdd_v, vddio_v")
    tokens["R_SERIES_IDEAL"] = "%g" % float(series_r)
    conds = {"LEVEL_SHIFTER": False, "NO_LEVEL_SHIFTER": True,
             "PREDRIVER": True, "REAL_RSER": False, "IDEAL_RSER": True,
             "ESD": False, "NO_ESD": True, "RX": True}
    pdrv_stages = int(vals["PDRV_STAGES"]["value"])
    if pdrv_stages < 1 or pdrv_stages % 2:
        raise SystemExit("ERROR: PDRV_STAGES must be a positive even number")
    tokens["PDRV_CHAIN_LINES"] = ep.render(
        ep.pdrv_chain(dev, pdrv_stages), tokens, conds)
    tpl = (SPECS / "templates" / "sdr_bidir_pad.spice.tpl").read_text()
    conds_tran = dict(conds, RX=False)
    oe = ep.oe_ctrl_spice(dev, tokens)
    body_tran = ep.render(tpl, tokens, conds_tran)
    body_dc = ep.render(tpl, tokens, conds)
    body_esd = ep.render(tpl, tokens, dict(conds, ESD=True, NO_ESD=False, RX=False))
    for _name, _body in (("tran", body_tran), ("dc", body_dc), ("esd", body_esd)):
        pass
    body_tran = body_tran.replace(".subckt sdr_bidir_pad", oe + "\n.subckt sdr_bidir_pad", 1)
    body_dc = body_dc.replace(".subckt sdr_bidir_pad", oe + "\n.subckt sdr_bidir_pad", 1)
    body_esd = body_esd.replace(".subckt sdr_bidir_pad", oe + "\n.subckt sdr_bidir_pad", 1)
    header = "\n".join([
        "* SIZED CHARACTERIZATION SLICE - DESIGN ASSUMPTION, NOT SIGNOFF",
        "* backend: %s" % args.backend,
        "* sizing: %s" % (args.sizing or "specs/pads/sizing/%s.first_pass.yaml" % args.backend),
        "* excluded: level shifter, pre-driver, package/PCB, PVT, ESD qualification",
        "* ESD diodes omitted from this electrical slice; ESD is a separate gate.",
        param_block(topo, vals, args.backend),
        "",
    ])
    netlist_tran = outdir / ("sized_sdr_tran%s.spice" % suffix)
    netlist_dc = outdir / ("sized_sdr_dc%s.spice" % suffix)
    netlist_esd = outdir / ("sized_sdr_esd%s.spice" % suffix)
    netlist_tran.write_text(header + "\n" + body_tran)
    netlist_dc.write_text(header + "\n" + body_dc)
    netlist_esd.write_text(header + "\n" + body_esd)
    models = model_lines(dev, root, args.corner)

    flags = dev["char"].get("ngspice_flags", [])
    decks = {}
    with tempfile.TemporaryDirectory(prefix="pad_char_") as td:
        cwd_rel = dev["char"].get("cwd") or ""
        run_cwd = (root / cwd_rel) if cwd_rel else Path(td)
        # A PDK-owned cwd must not be polluted; a local .spiceinit
        # neutralizes the user's ~/.spiceinit for temp-dir runs.
        if run_cwd == Path(td):
            (run_cwd / ".spiceinit").write_text(
                dev["char"].get("spiceinit", "* local\n").replace("@root@", str(root)))
        dcpath = str(netlist_dc.resolve())
        for name, text in (
            ("char_tran%s.spice" % suffix, tran_deck(str(netlist_tran.resolve()), models, vdd, vddio,
                                                     args.load_kohm, args.load_pf, temp)),
            ("char_dc%s.spice" % suffix, dc_deck(dcpath, models, vdd, vddio, temp)),
            ("char_esd%s.spice" % suffix, esd_deck(str(netlist_esd.resolve()), models, vdd, vddio, temp)),
            ("char_tin%s.spice" % suffix, tin_deck(dcpath, models, vdd, vddio, temp)),
            ("char_ioh%s.spice" % suffix, ioh_deck(dcpath, models, vdd, vddio, temp)),
            ("char_iol%s.spice" % suffix, iol_deck(dcpath, models, vdd, vddio, temp)),
        ):
            p = outdir / name
            p.write_text(text)
            decks[name] = parse_measures(run_ngspice(run_cwd, p, flags, root))

    measures = {}
    for d in decks.values():
        measures.update({k: v for k, v in d.items() if k in MEASURES})
    missing = [m for m in MEASURES if m not in measures]
    if missing:
        raise SystemExit("ERROR: missing measurements %s\n%s" % (missing, json.dumps(decks, indent=2)))

    rep = {
        "generated_by": "generator/emit_char_pad.py",
        "backend": args.backend,
        "status": "design_assumption - no signoff, no ESD qualification",
        "sizing_fixture": str(args.sizing or "specs/pads/sizing/%s.first_pass.yaml" % args.backend),
        "pdk_root": str(root),
        "ngspice": next((l.strip().lstrip("* ").strip() for l in subprocess.run(
            ["ngspice", "--version"], capture_output=True, text=True
        ).stdout.splitlines() if "ngspice" in l.lower()), "unknown"),
        "corner": args.corner,
        "temp_c": temp,
        "vdd_v": float(vdd),
        "vddio_v": float(vddio),
        "load": "%g kohm to VDDIO/2 + %g pF (light first-pass load)" % (args.load_kohm, args.load_pf),
        "series_r_ohm": float(series_r),
        "control_domains": {"OUT": "core", "OE_N": "io", "PU_OK": "io", "PAD": "io"},
        "excluded": ["full PVT signoff", "package/PCB RLC", "SDF/PEX",
                     "ESD stress/qualification"],
        "measures": measures,
    }
    (REPORTS / ("pad_char_%s%s.json" % (args.backend, suffix))).write_text(json.dumps(rep, indent=2) + "\n")

    units = {"t_oe_on": "s", "t_oe_off": "s", "tr_pad": "s", "tf_pad": "s",
             "vth_pad": "V", "ihiz_max": "A", "iesd_max": "A",
             "t_in": "s", "voh_2ma": "V", "vol_2ma": "V"}
    md = ["# Pad first-pass characterization: %s" % args.backend, "",
          "Generated by generator/emit_char_pad.py. **DESIGN ASSUMPTION, NOT SIGNOFF.**",
          "The sizing fixture and load are placeholders; ESD is not qualified.", "",
          "- fixture: `%s` (status: design_assumption)" % rep["sizing_fixture"],
          "- corner: %s; temp: %s C; VDD = %g V; VDDIO = %g V" % (
              rep["corner"], rep["temp_c"], rep["vdd_v"], rep["vddio_v"]),
          "- load: %s; ideal series R = %g ohm" % (rep["load"], rep["series_r_ohm"]),
          "- ESD: reverse leakage measured in a separate DC deck; stress/qualification not done",
          "- domains: OUT=core (level-shifted for sky130/IHP); OE_N/PU_OK=IO 3.3 V; PAD=IO", "",
          "| measure | value | unit |", "|---|---|---|"]
    for k in MEASURES:
        md.append("| %s | %.6g | %s |" % (k, measures[k], units[k]))
    md += ["", "`t_oe_on` / `t_oe_off` include the real IO-domain OE logic, pre-driver",
           "and the OUT core->IO level shifter when present. `tr_pad` / `tf_pad` are 0.33 V -> 2.9 V slews.",
           "`ihiz_max` is a swept external-source current with PU_OK low.",
           "`iesd_max` is reverse-biased ESD plus off-state output leakage, not an ESD qualification.",
           "`t_in` is PAD 1.65 V -> IN 1.65 V with the receiver and a 1 Gohm bleed.",
           "`voh_2ma` / `vol_2ma` are at a 2 mA design-assumption load.", "",
           "Excluded: full PVT signoff, package/PCB RLC, SDF/PEX,",
           "and ESD stress/qualification.", ""]
    (REPORTS / ("pad_char_%s%s.md" % (args.backend, suffix))).write_text("\n".join(md) + "\n")
    print("backend=%s corner=%s temp=%s measures=%s" % (args.backend, args.corner, temp, json.dumps(measures)))
    print("report: reports/pad_char_%s%s.md" % (args.backend, suffix))
    return 0


if __name__ == "__main__":
    sys.exit(main())
