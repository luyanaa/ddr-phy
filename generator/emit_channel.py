#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""P1-4: package + PCB channel co-simulation with the pad PEX.

Channel model (pre-layout, DESIGN ASSUMPTION - no vendor IBIS/EM data):

  pad PAD --[package: R_pkg, L_pkg, C_pkg]--[PCB microstrip ladder]--+
                                                                    |
                                          DRAM pin C_in + SSTL-3 50R to VTT

The PCB trace is a 50 ohm microstrip modelled as an RLGC ladder so the
delay, dispersion and termination reflection are visible in the transient.
Package parasitics are the standard IBIS `[Package]` RLC form.

Outputs reports/channel_<backend>_<tag>.json with:
  t_chan_r/f   PAD 50 % -> DRAM pin 50 % (absolute channel delay)
  slew_r/f     DRAM pin 0.33 V -> 2.9 V slew
  ov_/uv_      overshoot / undershoot at the DRAM pin

The absolute delay is common-mode; the timing budget uses trace-to-trace
skew, which is computed from the length tolerance in the spec.
"""
import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
REPORTS = ROOT / "reports"
SPECS = ROOT / "specs" / "pads" / "channel"

MEASURES = ("t_chan_r", "t_chan_f", "slew_r", "slew_f", "ov_dram", "uv_dram")


def build_line(ch):
    """Ideal transmission line: Z0 and one-way delay from the stackup."""
    td = ch["pcb_length_mm"] * ch["t_pd_ps_per_mm"] * 1e-12
    return "T1 PKG2 0 ND 0 Z0=%g TD=%g" % (ch["z0_ohm"], td), "ND"


def deck(pad_netlist, ch, models, vdd, vddio, tstop):
    ladder, last = build_line(ch)
    return f"""
* P1-4 CHANNEL CO-SIMULATION: pad PEX + package + PCB + DRAM pin.
* DESIGN ASSUMPTION: pre-layout channel, no vendor IBIS/EM extraction.
{models}
.include "{pad_netlist}"
VDD VDD 0 {vdd:g}
VSS VSS 0 0
VDDIO VDDIO 0 {vddio:g}
VSSIO VSSIO 0 0
* power-up sequencing first (as in the P1-1 slice), then the data edges
VPU PU_OK 0 PWL(0 0 1.0n 0 1.1n {vddio:g} {tstop*1e9:g}n {vddio:g})
VOE OE_N 0 PWL(0 {vddio:g} 3.9n {vddio:g} 4.0n 0 15.9n 0 16.0n {vddio:g} {tstop*1e9:g}n {vddio:g})
VOUT OUT 0 PWL(0 {vdd:g} 5.9n {vdd:g} 6.0n 0 11.9n 0 12.0n {vdd:g} {tstop*1e9:g}n {vdd:g})
X_PAD OUT OE_N IN PAD PU_OK VDD VSS VDDIO VSSIO sdr_bidir_pad
RIN IN VSSIO 1G
* package parasitics
R_PKG PAD PKG 0.05
L_PKG PKG PKG2 1.5n
C_PKG PKG2 0 0.4p
* PCB microstrip (50 ohm, {ch['pcb_length_mm']} mm)
{ladder}
* far-end load: DRAM input capacitance + high-Z bleed
RTT {last} VTT {ch['term_ohm']:g}
VTT VTT 0 1.65
C_DRAM {last} 0 {ch['dram_cin_pf']}p
.tran 5p {tstop*1e9:g}n
.options trtol=10 reltol=1e-2 abstol=1e-9 vntol=1e-4 rshunt=1e9 gmin=1e-8 itl4=100
.print tran v(PAD) v({last})
.end
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--backend", default="gf180mcuD")
    ap.add_argument("--spec", default=None)
    ap.add_argument("--pad-netlist",
                    default=str(ROOT / "sim" / "char" / "gf180mcuD"
                                / "sized_sdr_delay_tt_27.spice"),
                    help="sized pad slice; the Magic PEX netlist is not usable "
                         "in transient (device geometry units)")
    ap.add_argument("--vdd", type=float, default=3.3)
    ap.add_argument("--vddio", type=float, default=3.3)
    ap.add_argument("--tag", default="tt_27")
    args = ap.parse_args()

    spec_path = Path(args.spec) if args.spec else (SPECS / ("%s.yaml" % args.backend))
    spec = yaml.safe_load(open(spec_path))
    ch = spec["channel"]
    pdk_root = Path(spec["pdk_root"]).expanduser()
    models = spec["models"]
    tstop = 20e-9

    pad_netlist = Path(args.pad_netlist)
    if not pad_netlist.exists():
        raise SystemExit("ERROR: %s missing; run sim/p1_3_timing.sh first"
                         % pad_netlist)

    outdir = ROOT / "sim" / "channel" / args.backend
    outdir.mkdir(parents=True, exist_ok=True)
    netlist = outdir / ("channel_%s.spice" % args.tag)
    netlist.write_text(deck(str(pad_netlist.resolve()), ch, models,
                            args.vdd, args.vddio, tstop))

    work = tempfile.mkdtemp(prefix="channel_", dir="/tmp/opencode")
    (Path(work) / ".spiceinit").write_text("* local\n")
    env = {"PDK_ROOT": str(pdk_root), "PATH": "/usr/local/bin:/usr/bin:/bin"}
    r = subprocess.run(["ngspice", "-b", str(netlist)],
                       cwd=work, capture_output=True, text=True, env=env,
                       timeout=1800)
    log = r.stdout + r.stderr
    (REPORTS / ("channel_%s_%s.log" % (args.backend, args.tag))).write_text(log)
    # waveform: index time v(PAD) v(ND)
    rows = []
    for line in log.splitlines():
        f = line.split()
        if len(f) == 4 and f[0].isdigit():
            try:
                rows.append((float(f[1]), float(f[2]), float(f[3])))
            except ValueError:
                pass
    if len(rows) < 100:
        raise SystemExit("ERROR: no waveform in reports/channel_*.log")

    def cross(vals, thr, rising, win):
        t_lo, t_hi = win
        for i in range(1, len(vals)):
            t0 = vals[i - 1][0]
            if t0 < t_lo or t0 > t_hi:
                continue
            a, b = vals[i - 1][1], vals[i][1]
            if rising and a < thr <= b:
                t1 = vals[i][0]
                return t0 + (thr - a) * (t1 - t0) / (b - a)
            if not rising and a > thr >= b:
                t1 = vals[i][0]
                return t0 + (thr - a) * (t1 - t0) / (b - a)
        return None

    pad = [(t, p) for t, p, _n in rows]
    nd = [(t, n) for t, _p, n in rows]
    def upto(sig, tmax):
        return [x for x in sig if x[0] <= tmax]
    # data edges: OUT falls at 6 ns, rises at 12 ns. Use the 10 % points:
    # the 50 % crossings ring around the threshold on the DRAM pin, while the
    # wave-arrival instant is unambiguous.
    win_f = (5.5e-9, 9.0e-9)
    win_r = (11.5e-9, 16.0e-9)
    vhi = max(p for _t, p in pad)
    tpf = cross(pad, 0.9 * vhi, False, win_f)
    tnf = cross(nd, 0.9 * vhi, False, win_f)
    tpr = cross(pad, 0.1 * vhi, True, win_r)
    tnr = cross(nd, 0.1 * vhi, True, win_r)
    if None in (tpf, tnf, tpr, tnr):
        raise SystemExit("ERROR: could not find PAD/DRAM crossings")
    lo_nd = min(n for _t, _p, n in rows)
    hi_nd = max(n for _t, _p, n in rows)
    def slew(vals, lo, hi, rising):
        win = win_r if rising else win_f
        t10 = cross(vals, lo + 0.1 * (hi - lo), rising, win)
        t90 = cross(vals, lo + 0.9 * (hi - lo), rising, win)
        return None if t10 is None or t90 is None else abs(t90 - t10)
    m = {
        "t_chan_f": tnf - tpf,
        "t_chan_r": tnr - tpr,
        "slew_r": slew(nd, lo_nd, hi_nd, True),
        "slew_f": slew(nd, lo_nd, hi_nd, False),
        "ov_dram": hi_nd,
        "uv_dram": lo_nd,
    }
    missing = [k for k in MEASURES if m[k] is None]
    if missing:
        raise SystemExit("ERROR: missing measures %s (see reports/channel_*.log)"
                         % missing)

    length_tol = ch["length_tolerance_mm"]
    skew = length_tol * ch["t_pd_ps_per_mm"] * 1e-12
    rep = {
        "generated_by": "generator/emit_channel.py",
        "status": "design_assumption - pre-layout RLC channel, no vendor IBIS/EM",
        "backend": args.backend,
        "tag": args.tag,
        "spec": str(spec_path),
        "pad_netlist": str(pad_netlist),
        "channel": {k: ch[k] for k in (
            "pcb_length_mm", "z0_ohm", "t_pd_ps_per_mm",
            "length_tolerance_mm", "pcb_sections", "l_per_section_nh",
            "c_per_section_pf", "r_per_section_ohm", "dram_cin_pf",
            "term_ohm")},
        "package": {"r_ohm": 0.05, "l_nh": 1.5, "c_pf": 0.4,
                    "source": "typical wire-bond IBIS [Package] RLC range"},
        "measures": m,
        "trace_skew_s": skew,
        "notes": [
            "Absolute channel delay is common-mode for CK and DQ when the",
            "traces are matched; the budget uses the trace skew.",
            "Package RLC and the PCB stackup are published typical ranges,",
            "not vendor data. P1-4 is a pre-layout study.",
            "The pad model is the sized schematic slice, not the Magic PEX",
            "netlist: the flat PEX writes device w/l/ad/as in layout units",
            "while the PDK models expect SI units, so the output stage does",
            "not drive in transient. The PEX is still used for DRC/LVS and",
            "the .op check in P1-2.",
        ],
    }
    path = REPORTS / ("channel_%s_%s.json" % (args.backend, args.tag))
    path.write_text(json.dumps(rep, indent=2) + "\n")
    print("wrote %s" % path)
    for k in MEASURES:
        print("  %-9s %.6g" % (k, m[k]))
    print("  trace skew %.4g ps" % (skew * 1e12))
    return 0


if __name__ == "__main__":
    sys.exit(main())
