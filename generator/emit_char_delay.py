#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Characterize the pad data-path delays used by the P1-3 timing budget.

Measures, on the same sized slice as `emit_char_pad.py`:

  tpd_out_f / tpd_out_r   OUT -> PAD, 50 % -> 50 % (OE enabled)
  tpd_in_f  / tpd_in_r    PAD -> IN,  50 % -> 50 % (OE disabled)

The receiver is an inverting CMOS stage (`sdr_bidir_pad.spice`: IN = !PAD),
so `tpd_in_f` triggers on the PAD rising edge and targets the IN falling
edge. `emit_char_pad.py`'s original `t_in` measure triggered on IN RISE and
therefore reported the *falling* PAD edge (about tCK/2 later); that number
is not a delay and is not used here.

Output: reports/pad_delay_<backend><tag>.json
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import emit_char_pad as cp  # noqa: E402
import emit_pads as ep  # noqa: E402

REPORTS = cp.REPORTS
SPECS = cp.SPECS
OUT = cp.OUT

MEASURES = ("tpd_out_f", "tpd_out_r", "tpd_in_f", "tpd_in_r")


def out_deck(netlist_name, models, vdd, vddio, load_k, load_pf, temp):
    half = vddio / 2.0
    tline = "" if temp is None else ".temp %g\n" % temp
    return f"""
* OUTPUT DELAY: OUT -> PAD, OE enabled. DESIGN ASSUMPTION, NOT SIGNOFF.
{models}
{tline}.include "{netlist_name}"
VDD VDD 0 {vdd:g}
VSS VSS 0 0
VDDIO VDDIO 0 {vddio:g}
VSSIO VSSIO 0 0
VPU PU_OK 0 {vddio:g}
* OE enabled from t=0 so the only PAD edges are the data edges
VOE OE_N 0 0
VOUT OUT 0 PWL(0 {vdd:g} 5.9n {vdd:g} 6.0n 0 11.9n 0 12.0n {vdd:g} 24n {vdd:g})
VTT VTT 0 {half:g}
RLOAD PAD VTT {load_k:g}k
CLOAD PAD 0 {load_pf:g}p
RIN IN VSSIO 1G
X_DUT OUT OE_N IN PAD PU_OK VDD VSS VDDIO VSSIO sdr_bidir_pad
.tran 10p 24n
.options trtol=10 reltol=1e-3
.meas tran tpd_out_f TRIG v(OUT) VAL={vdd/2:g} FALL=1 TARG v(PAD) VAL={half:g} FALL=1
.meas tran tpd_out_r TRIG v(OUT) VAL={vdd/2:g} RISE=1 TARG v(PAD) VAL={half:g} RISE=1
.end
"""


def in_deck(netlist_name, models, vdd, vddio, temp):
    half = vddio / 2.0
    tline = "" if temp is None else ".temp %g\n" % temp
    return f"""
* INPUT DELAY: PAD -> IN, OE disabled (receiver only). NOT SIGNOFF.
{models}
{tline}.include "{netlist_name}"
VDD VDD 0 {vdd:g}
VSS VSS 0 0
VDDIO VDDIO 0 {vddio:g}
VSSIO VSSIO 0 0
VPU PU_OK 0 {vddio:g}
VOE OE_N 0 {vddio:g}
VOUT OUT 0 0
VEXT PAD 0 PWL(0 0 2n 0 3n {vddio:g} 8n {vddio:g} 9n 0 14n 0)
RIN IN VSSIO 1G
CIN IN 0 10f
X_DUT OUT OE_N IN PAD PU_OK VDD VSS VDDIO VSSIO sdr_bidir_pad
.tran 10p 16n
.meas tran tpd_in_f TRIG v(PAD) VAL={half:g} RISE=1 TARG v(IN) VAL={half:g} FALL=1
.meas tran tpd_in_r TRIG v(PAD) VAL={half:g} FALL=1 TARG v(IN) VAL={half:g} RISE=1
.end
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--backend", default="gf180mcuD")
    ap.add_argument("--sizing")
    ap.add_argument("--corner", default="tt")
    ap.add_argument("--temp", type=float)
    ap.add_argument("--vdd", type=float)
    ap.add_argument("--vddio", type=float)
    ap.add_argument("--load-kohm", type=float, default=1.0)
    ap.add_argument("--load-pf", type=float, default=1.0)
    ap.add_argument("--tag", default="")
    args = ap.parse_args()

    topo, maps = ep.load()
    dev = maps[args.backend]
    if not ep.bound(dev, topo):
        raise SystemExit("ERROR: %s device map is not bound" % args.backend)
    if not dev.get("char"):
        raise SystemExit("ERROR: %s has no machine-readable char wiring" % args.backend)

    _, vals = cp.load_sizing(args.backend, args.sizing)
    root = cp.discover_root(dev)
    outdir = OUT / args.backend
    outdir.mkdir(parents=True, exist_ok=True)
    suffix = args.tag or ""

    tokens = ep.tokens_for(topo, dev)
    fixture = args.sizing or (SPECS / "sizing" / ("%s.first_pass.yaml" % args.backend))
    char_meta = cp.yaml.safe_load(open(fixture))["meta"].get("char", {})
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
    body = ep.render(tpl, tokens, conds)
    body = body.replace(".subckt sdr_bidir_pad",
                        ep.oe_ctrl_spice(dev, tokens) + "\n.subckt sdr_bidir_pad", 1)
    header = "\n".join([
        "* SIZED DELAY SLICE - DESIGN ASSUMPTION, NOT SIGNOFF",
        "* backend: %s" % args.backend,
        "* sizing: %s" % fixture,
        "* excluded: level shifter, package/PCB, PVT signoff, ESD qualification",
        cp.param_block(topo, vals, args.backend),
        "",
    ])
    netlist = outdir / ("sized_sdr_delay%s.spice" % suffix)
    netlist.write_text(header + "\n" + body)
    models = cp.model_lines(dev, root, args.corner)
    flags = dev["char"].get("ngspice_flags", [])

    decks = {}
    with tempfile.TemporaryDirectory(prefix="pad_delay_") as td:
        cwd_rel = dev["char"].get("cwd") or ""
        run_cwd = (root / cwd_rel) if cwd_rel else Path(td)
        if run_cwd == Path(td):
            (run_cwd / ".spiceinit").write_text(
                dev["char"].get("spiceinit", "* local\n").replace("@root@", str(root)))
        for name, text in (
            ("char_tpd_out%s.spice" % suffix,
             out_deck(str(netlist.resolve()), models, vdd, vddio,
                      args.load_kohm, args.load_pf, temp)),
            ("char_tpd_in%s.spice" % suffix,
             in_deck(str(netlist.resolve()), models, vdd, vddio, temp)),
        ):
            p = outdir / name
            p.write_text(text)
            decks[name] = cp.parse_measures(cp.run_ngspice(run_cwd, p, flags, root))

    measures = {}
    for d in decks.values():
        measures.update({k: v for k, v in d.items() if k in MEASURES})
    missing = [m for m in MEASURES if m not in measures]
    if missing:
        raise SystemExit("ERROR: missing measurements %s\n%s"
                         % (missing, json.dumps(decks, indent=2)))

    rep = {
        "generated_by": "generator/emit_char_delay.py",
        "backend": args.backend,
        "status": "design_assumption - no signoff",
        "sizing_fixture": str(fixture),
        "pdk_root": str(root),
        "ngspice": next((l.strip().lstrip("* ").strip() for l in subprocess.run(
            ["ngspice", "--version"], capture_output=True, text=True
        ).stdout.splitlines() if "ngspice" in l.lower()), "unknown"),
        "corner": args.corner,
        "temp_c": temp,
        "vdd_v": float(vdd),
        "vddio_v": float(vddio),
        "load": "%g kohm to VDDIO/2 + %g pF" % (args.load_kohm, args.load_pf),
        "series_r_ohm": float(series_r),
        "receiver_inverting": True,
        "excluded": ["package/PCB RLC", "PVT signoff", "ESD qualification"],
        "measures": measures,
    }
    path = REPORTS / ("pad_delay_%s%s.json" % (args.backend, suffix))
    path.write_text(json.dumps(rep, indent=2) + "\n")
    print("wrote %s" % path)
    for k in MEASURES:
        print("  %-10s %.6g s" % (k, measures[k]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
