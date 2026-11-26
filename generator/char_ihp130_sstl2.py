#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Schematic-level DDR1 pad characterization with real SG13G2 models."""

import argparse
import glob
import json
import math
import os
import tempfile
from pathlib import Path

import yaml

from emit_char_pad import ROOT, SPECS, model_lines, parse_measures, run_ngspice


CELL = ROOT / "sch/pads/ihp130/sstl2_dq.spice"
SUBCKT = "ihp130_sstl2_dq"
MODEL = Path("libs.tech/ngspice/models")
OSDI = ("psp103", "psp103_nqs", "r3_cmc", "mosvar")
# Named schematic witness points, not exhaustive process/voltage/temperature signoff.
# MOS corner, resistor corner, degrees C, core V, I/O V.
CASES = {
    "tt": ("tt", "typ", 27, 1.20, 2.50),
    "ss_low": ("ss", "wcs", 125, 1.08, 2.30),
    "ss_shift": ("ss", "wcs", 125, 1.08, 2.70),
    "ff_high": ("ff", "bcs", -40, 1.32, 2.70),
    "ff_hot": ("ff", "bcs", 125, 1.32, 2.70),
    "sf_shift": ("sf", "wcs", 125, 1.08, 2.70),
    "fs_low_io": ("fs", "wcs", 125, 1.08, 2.30),
}


def pdk_root(dev, override):
    required = [MODEL / "cornerRES.lib"] + [
        Path("libs.tech/ngspice/osdi") / f"{name}.osdi" for name in OSDI
    ]
    candidates = [override] if override else sorted(
        glob.glob(os.path.expanduser(dev["char"]["root_glob"])), reverse=True
    )
    for path in candidates:
        root = Path(path).expanduser().resolve()
        if all((root / item).is_file() for item in required):
            return root
    raise SystemExit("IHP PDK root with matching ngspice models and all four OSDI files required")


def dc_deck(vdd, vddio):
    lines = [f"VDD vdd 0 {vdd}", f"VIO io 0 {vddio}", "VDIFF diff 0 0"]
    measures = []
    for label, ref in (("lo", .49), ("mid", .50), ("hi", .51)):
        lines += [
            f"VREF_{label} ref_{label} 0 {vddio * ref}",
            f"BPAD_{label} pad_{label} 0 V={{v(ref_{label})+v(diff)}}",
            f"XRX_{label} 0 0 rx_{label} pad_{label} ref_{label} io vdd 0 io 0 {SUBCKT}",
        ]
        measures += [
            f".meas dc offset_{label} FIND v(diff) WHEN v(rx_{label})={vdd/2} RISE=1",
            f".meas dc rx_low_{label} FIND v(rx_{label}) AT=-0.15",
            f".meas dc rx_high_{label} FIND v(rx_{label}) AT=0.15",
        ]
    # Sweep the entire legal pad range with OE low, for both core data levels.
    lines += [f"BFORCE force 0 V={{({vddio}/0.8)*(v(diff)+0.4)}}"]
    for k, data in (("l", "0"), ("h", "vdd")):
        lines += [
            f"VSENSE_{k} force z_{k} 0",
            f"XZ_{k} {data} 0 rz_{k} z_{k} ref_mid io vdd 0 io 0 {SUBCKT}",
        ]
        measures += [f".meas dc leak_{k}_{ext.lower()} {ext} i(vsense_{k})" for ext in ("MIN", "MAX")]
    return "\n".join(lines + [".dc VDIFF -0.4 0.4 0.002"] + measures), [m.split()[2] for m in measures]


def transient_deck(vdd, vddio, vtt_offset):
    ref = vddio / 2
    vtt = ref + vtt_offset
    lines = f"""VCORE_TX vdd 0 {vdd}
VCORE_RX vr 0 {vdd}
VTX io 0 {vddio}
VRX ior 0 {vddio}
VREF ref 0 {ref}
VTT term 0 {vtt}
VDATA data 0 PWL(0 0 14n 0 14.3n {vdd} 19n {vdd} 19.3n 0 34n 0 34.3n {vdd} 69n {vdd} 69.3n 0)
VOE oe 0 PWL(0 0 5n 0 5.3n {vdd} 30n {vdd} 30.3n 0 40n 0 40.3n {vdd} 47n {vdd} 47.3n 0 55n 0 55.3n {vdd})
VOK ok 0 PWL(0 {vddio} 65n {vddio} 65.3n 0 72n 0 72.3n {vddio} 80n {vddio} 80.3n 0)
XTX data oe rx_tx pad_tx ref ok vdd 0 io 0 {SUBCKT}
CTERM pad_tx 0 5p
RTERM pad_tx term 50
CTXCORE rx_tx 0 30f
VEXT pad_rx 0 PWL(0 {ref-.31} 4n {ref-.31} 4.8n {ref+.31} 14n {ref+.31} 14.8n {ref-.31})
XRX 0 0 rx pad_rx ref ior vr 0 ior 0 {SUBCKT}
CRXCORE rx 0 30f
.tran 20p 85n 0 20p
"""
    # Propagation is to the receiving logic window (not an arbitrary 50% PAD swing).
    # Release-to-VTT uses the loaded PAD voltage, separate from DC Hi-Z leakage.
    specs = (
        ("rx_rise", 3, "pad_rx", ref, "RISE", "rx", .8*vdd, "RISE"),
        ("rx_fall", 13, "pad_rx", ref, "FALL", "rx", .2*vdd, "FALL"),
        ("tx_rise", 13, "data", .5*vdd, "RISE", "pad_tx", ref+.31, "RISE"),
        ("tx_fall", 18, "data", .5*vdd, "FALL", "pad_tx", ref-.31, "FALL"),
        ("oe_on_l", 4, "oe", .5*vdd, "RISE", "pad_tx", ref-.31, "FALL"),
        ("oe_on_h", 39, "oe", .5*vdd, "RISE", "pad_tx", ref+.31, "RISE"),
        ("oe_off_l", 29, "oe", .5*vdd, "FALL", "pad_tx", vtt-.05, "RISE"),
        ("oe_off_h", 46, "oe", .5*vdd, "FALL", "pad_tx", vtt+.05, "FALL"),
        ("guard_off_h", 64, "ok", ref, "FALL", "pad_tx", vtt+.05, "FALL"),
        ("guard_off_l", 79, "ok", ref, "FALL", "pad_tx", vtt-.05, "RISE"),
    )
    measures = [f".meas tran {n} TRIG v({a}) VAL={av} TD={d}n {ae}=1 "
                f"TARG v({b}) VAL={bv} TD={d}n {be}=1" for n, d, a, av, ae, b, bv, be in specs]
    measures += [
        ".meas tran tx_low FIND v(pad_tx) AT=12n",
        ".meas tran tx_high FIND v(pad_tx) AT=18n",
        ".meas tran tx_enable_high FIND v(pad_tx) AT=61n",
        ".meas tran rx_io_bias FIND i(vrx) AT=12n",
        ".meas tran rx_core_bias FIND i(vcore_rx) AT=20n",
        ".meas tran tx_io_peak MIN i(vtx) FROM=4n TO=85n",
        ".meas tran rx_level_min MIN v(xrx.rx_level)",
        ".meas tran rx_level_max MAX v(xrx.rx_level)",
    ]
    return lines + "\n".join(measures), [m.split()[2] for m in measures]


def power_deck(vdd, vddio):
    lines = [
        f"VCORE_A va 0 PWL(0 0 1n 0 6n {vdd})",
        f"VIO_A ia 0 PWL(0 0 9n 0 14n {vddio})",
        f"VCORE_B vb 0 PWL(0 0 9n 0 14n {vdd})",
        f"VIO_B ib 0 PWL(0 0 1n 0 6n {vddio})",
    ]
    measures = []
    for seq in ("a", "b"):
        lines += [f"BREF_{seq} ref_{seq} 0 V={{v(i{seq})/2}}"]
        # OE follows the core rail (requests drive as soon as possible), but
        # the I/O-domain supervisor never releases PU_OK during power-up.
        for direction, data, frac in (("h", f"v{seq}", .1), ("l", "0", .9)):
            k = seq + direction
            lines += [
                f"BFORCE_{k} force_{k} 0 V={{{frac}*v(i{seq})}}",
                f"VSENSE_{k} force_{k} pad_{k} 0",
                f"XP_{k} {data} v{seq} rx_{k} pad_{k} ref_{seq} 0 v{seq} 0 i{seq} 0 {SUBCKT}",
            ]
            for edge in ("MIN", "MAX"):
                measures += [f".meas tran ramp_{k}_{edge.lower()} {edge} i(vsense_{k}) FROM=1n TO=22n"]
            for time in (8, 22):
                measures += [f".meas tran hiz_{k}_{time} FIND i(vsense_{k}) AT={time}n"]
    return "\n".join(lines + [".tran 40p 23n 0 40p"] + measures), [m.split()[2] for m in measures]


def check(vdd, vddio, m):
    ref = vddio / 2
    bounds = {}
    for group in ("lo", "mid", "hi"):
        bounds[f"offset_{group}"] = (-.10, .10)
        bounds[f"rx_low_{group}"] = (-.05, .2*vdd)
        bounds[f"rx_high_{group}"] = (.8*vdd, vdd+.05)
    # Local allocation for a 5 ns UI; these are not the DRAM's setup/hold specs.
    bounds.update({key: (0, 1.5e-9) for key in ("rx_rise", "rx_fall", "tx_rise", "tx_fall")})
    bounds.update({key: (0, 2.5e-9) for key in (
        "oe_on_l", "oe_on_h", "oe_off_l", "oe_off_h", "guard_off_l", "guard_off_h",
    )})
    bounds["tx_low"] = (0, ref-.31)
    bounds["tx_high"] = bounds["tx_enable_high"] = (ref+.31, vddio)
    # Screen feed-through at the first low-voltage gate; not an oxide lifetime test.
    bounds["rx_level_min"] = bounds["rx_level_max"] = (-.10, vdd+.10)
    for key in m:
        if key.startswith(("leak_", "hiz_")):
            bounds[key] = (-5e-6, 5e-6)
        if key.startswith("ramp_"):
            # Ramp current includes capacitance; plateau leakage has the separate gate above.
            bounds[key] = (-.5e-3, .5e-3)
    failures = {}
    for key, (lo, hi) in bounds.items():
        value = m[key]
        if value is None:
            failures[key] = {"actual": None, "limit": [lo, hi], "reason": "no_target_crossing"}
        elif not lo <= value <= hi:
            failures[key] = {"actual": value, "limit": [lo, hi]}
    return failures


def bench_values(deck, bench, expected, text):
    values = parse_measures(text)
    if "run simulation(s) aborted" in text.lower():
        raise SystemExit(f"{deck.name}: analysis aborted\n{text}")
    # A simulated waveform that never reaches its target is an electrical
    # failure, not a valid zero delay and not grounds to skip the rail test.
    missed = set()
    if bench == "transient":
        for line in text.splitlines():
            words = line.split()
            if words[:2] == ["Error:", "measure"] and "trig(TARG)" in words and line.endswith("out of interval"):
                missed.add(words[2])
    missing = [k for k in expected if k not in missed and (k not in values or not math.isfinite(values[k]))]
    if missing:
        raise SystemExit(f"{deck.name}: missing measurements {missing}\n{text}")
    return {k: None if k in missed else values[k] for k in expected}


def delay_pair(values, start):
    pair = [values[f"{start}_{edge}"] for edge in ("rise", "fall")]
    return "/".join("no-cross" if x is None else f"{x*1e9:.3f}" for x in pair)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pdk-root", help="SG13G2 root with ngspice models and OSDI")
    parser.add_argument("--cell-netlist", type=Path,
                        help="simulate an alternate ihp130_sstl2_dq netlist with the same port order")
    parser.add_argument("--case", choices=CASES, action="append", help="repeat to select points; default: all")
    parser.add_argument("--vtt-offset-mv", type=int, choices=(-40, 0, 40), default=0,
                        help="termination voltage relative to VREF in mV; default: 0")
    parser.add_argument("--output", type=Path, help="write raw SI measurements and pass/fail JSON")
    args = parser.parse_args()
    dev = yaml.safe_load((SPECS / "devices/ihp130.yaml").read_text())
    pdk = pdk_root(dev, args.pdk_root)
    cell = args.cell_netlist.resolve(strict=True) if args.cell_netlist else CELL
    # Sparse is more stable than KLU for the DC sweep of the distributed
    # extracted network. No change to equations, thresholds or stimulus.
    dc_solver = "sparse" if args.cell_netlist else "klu"
    results = {}
    with tempfile.TemporaryDirectory(prefix="ihp130-sstl2-") as work:
        work = Path(work)
        # Small disconnected witnesses lose time to OSDI/OpenMP fan-out.
        setup = dev["char"]["spiceinit"].replace("@root@", str(pdk))
        (work / ".spiceinit").write_text("set num_threads=1\n" + setup)
        for name in args.case or CASES:
            mos, res, temp, vdd, vddio = CASES[name]
            header = f'''* IHP130 SSTL-2 witness point {name}
{model_lines(dev, pdk, f"mos_{mos}")}
.lib "{pdk / MODEL / 'cornerRES.lib'}" res_{res}
.include "{cell}"
.temp {temp}
'''
            measurements = {}
            decks = (
                ("dc", dc_deck(vdd, vddio)),
                ("transient", transient_deck(vdd, vddio, args.vtt_offset_mv * 1e-3)),
                ("power", power_deck(vdd, vddio)),
            )
            for bench, (body, expected) in decks:
                deck = work / f"{name}_{bench}.spice"
                solver = "" if bench == "dc" and dc_solver == "sparse" else "klu"
                options = f".options {solver} method=gear maxord=2\n"
                deck.write_text(header + options + body + "\n.end\n")
                text = run_ngspice(work, deck, dev["char"]["ngspice_flags"], pdk)
                measurements.update(bench_values(deck, bench, expected, text))
            failures = check(vdd, vddio, measurements)
            results[name] = dict(mos=mos, res=res, temp_c=temp, vdd=vdd, vddio=vddio,
                                 measurements_si=measurements, failures=failures)
            m = measurements
            print(f"{name}: {'FAIL' if failures else 'PASS'}; RX {delay_pair(m, 'rx')} ns "
                  f"TX {delay_pair(m, 'tx')} ns, "
                  f"VOH/VOL {m['tx_high']:.3f}/{m['tx_low']:.3f} V", flush=True)
            if failures:
                print(json.dumps(failures, indent=2), flush=True)
    if args.output:
        args.output.write_text(json.dumps(dict(
            status="custom_netlist" if args.cell_netlist else "schematic_only",
            signoff=False, pdk=str(pdk), cell=str(cell), vtt_offset_mv=args.vtt_offset_mv,
            dc_solver=dc_solver, cases=results,
        ), indent=2) + "\n")
    return int(any(case["failures"] for case in results.values()))


if __name__ == "__main__":
    raise SystemExit(main())
