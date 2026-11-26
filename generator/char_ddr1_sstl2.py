#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Process-neutral schematic-level DDR1 SSTL-2 pad characterization engine.

This module owns ONLY the parts of characterization that do not depend on the
silicon process: the DC / transient / power-up bench waveforms, the JEDEC /
SSTL-2 derived hard limits, measurement parsing, and pass/fail judgement.

Everything that *does* depend on the process (device model inclusion, corner
section tables, supply voltages, OSDI / spiceinit setup, the cell subckt name
and default netlist path) is injected through a per-process ``profile`` dict.

A process profile supplies:
  subckt        : cell subckt name (port order OUT OE IN PAD VREF PU_OK VDD VSS VDDIO VSSIO)
  default_cell  : repo-relative default source netlist path
  device_yaml   : repo-relative per-PDK device map (specs/pads/devices/<pdk>.yaml)
  cases         : {case_name: (mos_corner, res_corner, temp_C, core_v, io_v)}
  extra_model_lines(pdk, mos_corner) : optional extra .lib/.include lines
  res_model_line(pdk, res_corner)    : .lib/.include for the resistor corner, or ""
  spiceinit                          : spiceinit body template ('@root@' substituted); "" for none
  required_root_files                : files/dirs that must exist under the PDK root
  dc_solver      : solver for the DC sweep of the stock netlist (cell-netlist runs use 'sparse')

The port order and the measurement names (rx_rise/rx_fall/tx_rise/tx_fall,
rx_io_bias/rx_core_bias/tx_io_peak, ...) are the cross-process contract that
generator/tune_ddr1.py consumes. Do not rename them.
"""

import argparse
import json
import math
import glob
import os
import tempfile
from pathlib import Path

import yaml

from emit_char_pad import ROOT, model_lines, parse_measures, run_ngspice
from ddr1_xyce import BinnedPad, run_xyce


# --------------------------------------------------------------------------
# Process-independent bench decks. Every node reference is to the fixed cell
# port order; voltages/timings derive from the JEDEC SSTL-2 / Micron stimulus
# and the 5 ns UI allocation, not from any one process.
# --------------------------------------------------------------------------

def dc_deck(subckt, vdd, vddio):
    lines = [f"VDD vdd 0 {vdd}", f"VIO io 0 {vddio}", "VDIFF diff 0 0"]
    measures = []
    for label, ref in (("lo", .49), ("mid", .50), ("hi", .51)):
        lines += [
            f"VREF_{label} ref_{label} 0 {vddio * ref}",
            f"BPAD_{label} pad_{label} 0 V={{v(ref_{label})+v(diff)}}",
            f"XRX_{label} 0 0 rx_{label} pad_{label} ref_{label} io vdd 0 io 0 {subckt}",
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
            f"XZ_{k} {data} 0 rz_{k} z_{k} ref_mid io vdd 0 io 0 {subckt}",
        ]
        measures += [f".meas dc leak_{k}_{ext.lower()} {ext} i(vsense_{k})" for ext in ("MIN", "MAX")]
    return "\n".join(lines + [".dc VDIFF -0.4 0.4 0.002"] + measures), [m.split()[2] for m in measures]


def transient_deck(subckt, vdd, vddio, vtt_offset):
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
XTX data oe rx_tx pad_tx ref ok vdd 0 io 0 {subckt}
CTERM pad_tx 0 5p
RTERM pad_tx term 50
CTXCORE rx_tx 0 30f
VEXT pad_rx 0 PWL(0 {ref-.31} 4n {ref-.31} 4.8n {ref+.31} 14n {ref+.31} 14.8n {ref-.31})
XRX 0 0 rx pad_rx ref ior vr 0 ior 0 {subckt}
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


def power_deck(subckt, vdd, vddio):
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
                f"XP_{k} {data} v{seq} rx_{k} pad_{k} ref_{seq} 0 v{seq} 0 i{seq} 0 {subckt}",
            ]
            for edge in ("MIN", "MAX"):
                measures += [f".meas tran ramp_{k}_{edge.lower()} {edge} i(vsense_{k}) FROM=1n TO=22n"]
            for time in (8, 22):
                measures += [f".meas tran hiz_{k}_{time} FIND i(vsense_{k}) AT={time}n"]
    return "\n".join(lines + [".tran 40p 23n 0 40p"] + measures), [m.split()[2] for m in measures]


# --------------------------------------------------------------------------
# Process-independent JEDEC / SSTL-2 hard limits.
# --------------------------------------------------------------------------

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


# --------------------------------------------------------------------------
# Process injection: profile resolution.
# --------------------------------------------------------------------------

def simulator_for(dev):
    simulator = dev.get("ddr1", {}).get("simulator", "ngspice")
    if simulator not in {"ngspice", "xyce"}:
        raise ValueError(f"unsupported DDR1 simulator: {simulator}")
    return simulator


def temperature_line(simulator, temp):
    return f".options device temp={temp}" if simulator == "xyce" else f".temp {temp}"


def native_corner(profile, dev, pdk, mos, res):
    block = model_lines(dev, pdk, mos)
    extra = profile.get("extra_model_lines")
    if extra:
        block += "\n" + extra(pdk, mos)
    res_line = profile.get("res_model_line")
    return block + "\n" + (res_line(pdk, res) if res_line else "")


def pdk_root_for(profile, dev, override):
    required = [Path(p) for p in profile.get("required_root_files", [])]
    pattern = dev.get("ddr1", {}).get("root_glob", dev["char"]["root_glob"])
    candidates = [override] if override else sorted(
        glob.glob(os.path.expanduser(pattern)), reverse=True
    )
    for path in candidates:
        root = Path(path).expanduser().resolve()
        if all((root / item).exists() for item in required):
            return root
    raise SystemExit(
        f"{profile['name']}: PDK root with required model files not found "
        f"(need: {[str(r) for r in required]})"
    )


def characterize(profile, argv=None):
    parser = argparse.ArgumentParser(description=f"DDR1 SSTL-2 characterization: {profile['name']}")
    parser.add_argument("--pdk-root", help="PDK model root")
    parser.add_argument("--cell-netlist", type=Path,
                        help="simulate an alternate cell netlist with the same port order")
    parser.add_argument("--case", choices=profile["cases"], action="append",
                        help="repeat to select points; default: all")
    parser.add_argument("--vtt-offset-mv", type=int, choices=(-40, 0, 40), default=0,
                        help="termination voltage relative to VREF in mV; default: 0")
    parser.add_argument("--output", type=Path, help="write raw SI measurements and pass/fail JSON")
    args = parser.parse_args(argv)

    subckt = profile["subckt"]
    cases = profile["cases"]
    dev = yaml.safe_load((ROOT / profile["device_yaml"]).read_text())
    pdk = pdk_root_for(profile, dev, args.pdk_root)
    cell = args.cell_netlist.resolve(strict=True) if args.cell_netlist else (ROOT / profile["default_cell"]).resolve()
    # Sparse is more stable than KLU for the DC sweep of the distributed
    # extracted network. No change to equations, thresholds or stimulus.
    dc_solver = "sparse" if args.cell_netlist else profile.get("dc_solver", "klu")

    simulator = simulator_for(dev)
    results = {}
    with tempfile.TemporaryDirectory(prefix=f"{profile['name']}-sstl2-") as work:
        work = Path(work)
        if simulator == "xyce":
            pad = BinnedPad(pdk, dev, cell.read_text(), subckt)
            sim_cell = work / "sstl2_dq.inc"
            sim_cell.write_text(pad.netlist)
        else:
            pad, sim_cell = None, cell
            setup = profile.get("spiceinit", "").replace("@root@", str(pdk))
            (work / ".spiceinit").write_text("set num_threads=1\n" + setup)
        for name in args.case or cases:
            mos, res, temp, vdd, vddio = cases[name]
            models = pad.corner(mos) if pad else native_corner(profile, dev, pdk, mos, res)
            header = (
                f"* {profile['name']} SSTL-2 witness point {name}; signoff=false\n"
                f"{models}\n"
                f'.include "{sim_cell}"\n'
                f"{temperature_line(simulator, temp)}\n"
            )
            measurements = {}
            decks = (
                ("dc", dc_deck(subckt, vdd, vddio)),
                ("transient", transient_deck(subckt, vdd, vddio, args.vtt_offset_mv * 1e-3)),
                ("power", power_deck(subckt, vdd, vddio)),
            )
            runtime = {}
            for bench, (body, expected) in decks:
                deck = work / f"{name}_{bench}.spice"
                if pad:
                    options = ".options timeint reltol=1e-3 abstol=1e-9\n"
                    body = body.replace("v(xrx.rx_level)", "v(xrx:rx_level)")
                    deck.write_text(header + options + body + "\n.end\n")
                    values, runtime[bench] = run_xyce(deck, bench, body, expected)
                else:
                    solver = "" if bench == "dc" and dc_solver == "sparse" else "klu"
                    extra_opts = profile.get("extra_options", "")
                    options = f".options {solver} method=gear maxord=2 {extra_opts}\n"
                    deck.write_text(header + options + body + "\n.end\n")
                    text = run_ngspice(work, deck, dev["char"]["ngspice_flags"], pdk)
                    values = bench_values(deck, bench, expected, text)
                measurements.update(values)
            failures = check(vdd, vddio, measurements)
            results[name] = dict(mos=mos, res=res, temp_c=temp, vdd=vdd, vddio=vddio,
                                 measurements_si=measurements, failures=failures)
            if runtime:
                results[name]["simulator_elapsed_s"] = runtime
            m = measurements
            print(f"{name}: {'FAIL' if failures else 'PASS'}; RX {delay_pair(m, 'rx')} ns "
                  f"TX {delay_pair(m, 'tx')} ns, "
                  f"VOH/VOL {m['tx_high']:.3f}/{m['tx_low']:.3f} V", flush=True)
            if failures:
                print(json.dumps(failures, indent=2), flush=True)
    if args.output:
        args.output.write_text(json.dumps(dict(
            status="custom_netlist" if args.cell_netlist else "schematic_only",
            signoff=False, process=profile["name"], license=profile.get("license", ""),
            pdk=str(pdk), cell=str(cell), vtt_offset_mv=args.vtt_offset_mv,
            simulator=simulator, dc_solver="default" if pad else dc_solver, cases=results,
        ), indent=2) + "\n")
    return int(any(case["failures"] for case in results.values()))
