#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Focused native-device witness for the IHP SG13G2 DDR1 SSTL-2 VREF source.

This is an illustrative schematic study, not qualification or signoff. The
fixture uses a 16-input proxy: 16 pF to VSSIO and 62.5 Mohm to each rail (16 x
1 Gohm per rail), plus a 160 fF capacitive kickback proxy and a 50 uA switched
resistive load step. A separate 50 uA resistive load checks source and sink.
"""

import argparse
import glob
import json
import math
import os
import tempfile
from pathlib import Path

import yaml

from emit_char_pad import ROOT, SPECS, model_lines, parse_measures, run_ngspice

CELL = ROOT / "sch/pads/ihp130/sstl2_vref.spice"
SUBCKT = "ihp130_sstl2_vref"
MODEL = Path("libs.tech/ngspice/models")
OSDI = ("psp103", "psp103_nqs", "r3_cmc", "mosvar")

# Exact witness tuples used by char_ihp130_sstl2.py.
CASES = {
    "tt": ("tt", "typ", 27, 1.20, 2.50),
    "ss_low": ("ss", "wcs", 125, 1.08, 2.30),
    "ss_shift": ("ss", "wcs", 125, 1.08, 2.70),
    "ff_high": ("ff", "bcs", -40, 1.32, 2.70),
    "ff_hot": ("ff", "bcs", 125, 1.32, 2.70),
    "sf_shift": ("sf", "wcs", 125, 1.08, 2.70),
    "fs_low_io": ("fs", "wcs", 125, 1.08, 2.30),
}
DEFAULT_CASES = ("ss_low", "tt", "ff_high")
X16_CAP_F = 16e-12
X16_LEAK_OHM = 62.5e6
KICK_CAP_F = 160e-15
LOAD_A = 50e-6
LOAD_STEP_A = 50e-6
RATIO_LIMIT = 0.01  # VREF error as a fraction of VDDIO; illustrative only.


def pdk_root(dev, override):
    required = [MODEL / "cornerRES.lib", MODEL / "cornerCAP.lib"] + [
        Path("libs.tech/ngspice/osdi") / f"{name}.osdi" for name in OSDI
    ]
    candidates = [override] if override else sorted(
        glob.glob(os.path.expanduser(dev["char"]["root_glob"])), reverse=True
    )
    for path in candidates:
        root = Path(path).expanduser().resolve()
        if all((root / item).is_file() for item in required):
            return root
    raise SystemExit("IHP PDK root with matching ngspice models, capacitor corner, and OSDI required")


def header(dev, pdk, cell, mos, resistor, temp):
    return f'''* IHP130 DDR1 local VREF schematic witness
{model_lines(dev, pdk, f"mos_{mos}")}
.lib "{pdk / MODEL / 'cornerRES.lib'}" res_{resistor}
.lib "{pdk / MODEL / 'cornerCAP.lib'}" cap_typ
.include "{cell}"
.temp {temp}
'''


def fixture_loads(vddio, load):
    lines = [
        f"RLEAK_HI VDDIO VREF {X16_LEAK_OHM:g}",
        f"RLEAK_LO VREF VSSIO {X16_LEAK_OHM:g}",
        f"CIN16 VREF VSSIO {X16_CAP_F:g}",
    ]
    if load == "source":
        lines.append(f"RLOAD VREF VSSIO {vddio / (2 * LOAD_A):.12g}")
    elif load == "sink":
        lines.append(f"RLOAD VDDIO VREF {vddio / (2 * LOAD_A):.12g}")
    return "\n".join(lines)


def dc_deck(cell, dev, pdk, mos, resistor, temp, vddio, load):
    body = f'''VDDIO VDDIO 0 {vddio}
VSSIO VSSIO 0 0
XREF VREF VDDIO VSSIO {SUBCKT}
{fixture_loads(vddio, load)}
VCTRL CTRL 0 0
.dc VCTRL 0 1m 1m
.meas dc vref FIND v(VREF) AT=0
.meas dc vssio FIND v(VSSIO) AT=0
.meas dc ivddio FIND i(VDDIO) AT=0
'''
    return header(dev, pdk, cell, mos, resistor, temp) + body + ".end\n"


def kick_deck(cell, dev, pdk, mos, resistor, temp, vddio):
    low_band = vddio / 2 - RATIO_LIMIT * vddio
    load_r = vddio / (2 * LOAD_STEP_A)
    body = f'''VDDIO VDDIO 0 {vddio}
VSSIO VSSIO 0 0
VAGGR AGGR 0 PWL(0 0 2u 0 2.1u {vddio} 3u {vddio} 3.1u 0 5u 0)
VLOADCTL LOADCTL 0 PWL(0 0 1.99u 0 2u 1 2.99u 1 3u 0 5u 0)
XREF VREF VDDIO VSSIO {SUBCKT}
{fixture_loads(vddio, "none")}
CKICK VREF AGGR {KICK_CAP_F:g}
SLOAD VREF LOADNODE LOADCTL 0 STEPLOAD
RLOADSTEP LOADNODE VSSIO {load_r:.12g}
.model STEPLOAD SW(Ron=1 Roff=1e12 Vt=0.5 Vh=0.1)
.tran 20p 5u 0 20p
.meas tran pre_kick FIND v(VREF) AT=1.9u
.meas tran quiet_min MIN v(VREF) FROM=1.5u TO=1.9u
.meas tran quiet_max MAX v(VREF) FROM=1.5u TO=1.9u
.meas tran kick_min MIN v(VREF) FROM=2u TO=4u
.meas tran kick_max MAX v(VREF) FROM=2u TO=4u
.meas tran loaded_end FIND v(VREF) AT=2.9u
.meas tran recovered FIND v(VREF) AT=4u
.meas tran kick_recovery TRIG v(VREF) VAL={low_band} FALL=1 TD=1.9u TARG v(VREF) VAL={low_band} RISE=1 TD=1.9u
.meas tran ivddio_quiet FIND i(VDDIO) AT=1.9u
'''
    return header(dev, pdk, cell, mos, resistor, temp) + body + ".end\n"


def rail_deck(cell, dev, pdk, mos, resistor, temp, vddio):
    body = f'''VDDIO VDDIO 0 PWL(0 0 10n 0 1.01u {vddio} 2.51u {vddio} 3.51u 0 4.51u 0)
VSSIO VSSIO 0 0
XREF VREF VDDIO VSSIO {SUBCKT}
{fixture_loads(vddio, "none")}
.tran 10n 4.51u 0 10n
.meas tran vddio_high FIND v(VDDIO) AT=2u
.meas tran vref_high FIND v(VREF) AT=2u
.meas tran vddio_fall FIND v(VDDIO) AT=4u
.meas tran vref_fall FIND v(VREF) AT=4u
.meas tran vssio_high FIND v(VSSIO) AT=2u
'''
    return header(dev, pdk, cell, mos, resistor, temp) + body + ".end\n"


def run_bench(work, name, text, expected, flags, pdk, optional=()):
    deck = work / f"{name}.spice"
    deck.write_text(text)
    output = run_ngspice(work, deck, flags, pdk)
    if "run simulation(s) aborted" in output.lower():
        raise SystemExit(f"{deck.name}: ngspice analysis aborted\n{output}")
    values = parse_measures(output)
    missing = [key for key in expected if key not in values or not math.isfinite(values[key])]
    if missing:
        raise SystemExit(f"{deck.name}: missing measurements {missing}\n{output}")
    return {key: values[key] for key in (*expected, *optional) if key in values}


def ratio_metric(vref, vddio):
    error_v = vref - vddio / 2
    return {
        "vref_v": vref,
        "error_v": error_v,
        "error_fraction_of_vddio": error_v / vddio,
        "within_illustrative_1pct_vddio": abs(error_v) <= RATIO_LIMIT * vddio,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pdk-root", help="SG13G2 root with ngspice models and OSDI")
    parser.add_argument("--cell-netlist", type=Path, help="alternate local VREF netlist")
    parser.add_argument("--case", choices=CASES, action="append", help="repeat to select points")
    parser.add_argument("--output", type=Path, help="write SI measurements and witness status JSON")
    args = parser.parse_args()

    dev = yaml.safe_load((SPECS / "devices/ihp130.yaml").read_text())
    pdk = pdk_root(dev, args.pdk_root)
    cell = args.cell_netlist.resolve(strict=True) if args.cell_netlist else CELL
    selected = args.case or DEFAULT_CASES
    results = {}
    with tempfile.TemporaryDirectory(prefix="ihp130-vref-") as td:
        work = Path(td)
        setup = dev["char"]["spiceinit"].replace("@root@", str(pdk))
        (work / ".spiceinit").write_text("set num_threads=1\n" + setup)
        for name in selected:
            mos, resistor, temp, vdd, vddio = CASES[name]
            result = {"mos_corner": mos, "resistor_corner": resistor, "temp_c": temp,
                      "vdd_v": vdd, "vddio_v": vddio, "dc": {}, "failures": []}
            models = dict(cell=cell, dev=dev, pdk=pdk, mos=mos, resistor=resistor, temp=temp)
            for load in ("none", "source", "sink"):
                values = run_bench(work, f"{name}_dc_{load}",
                                   dc_deck(**models, vddio=vddio, load=load),
                                   ("vref", "vssio", "ivddio"), dev["char"]["ngspice_flags"], pdk)
                metric = ratio_metric(values["vref"], vddio)
                load_ohm = vddio / (2 * LOAD_A)
                actual_load_a = (values["vref"] / load_ohm if load == "source" else
                                 (vddio - values["vref"]) / load_ohm if load == "sink" else 0.0)
                metric.update(vssio_v=values["vssio"],
                              vddio_current_a=values["ivddio"],
                              vddio_current_draw_a=-values["ivddio"],
                              proxy_load_a=actual_load_a,
                              proxy_load_resistance_ohm=load_ohm if load != "none" else None)
                result["dc"][load] = metric
                if not metric["within_illustrative_1pct_vddio"]:
                    result["failures"].append(f"dc_{load}_ratio")
            kick = run_bench(work, f"{name}_kick", kick_deck(**models, vddio=vddio),
                             ("pre_kick", "quiet_min", "quiet_max", "kick_min", "kick_max",
                              "loaded_end", "recovered", "ivddio_quiet"),
                             dev["char"]["ngspice_flags"], pdk, optional=("kick_recovery",))
            kick.update(
                quiet_pp_v=kick["quiet_max"] - kick["quiet_min"],
                max_abs_deviation_v=max(abs(kick["kick_min"] - vddio / 2),
                                        abs(kick["kick_max"] - vddio / 2)),
                kick_excursion_from_unloaded_v=max(abs(kick["kick_min"] - kick["pre_kick"]),
                                                   abs(kick["kick_max"] - kick["pre_kick"])),
                load_step_a=LOAD_STEP_A,
                recovery_s=kick.get("kick_recovery"),
                recovered_to_unloaded_by_4us=abs(kick["recovered"] - kick["pre_kick"]) <= 1e-3,
            )
            if not kick["recovered_to_unloaded_by_4us"]:
                result["failures"].append("transient_recovery")
            result["transient"] = kick

            rail = run_bench(work, f"{name}_rail", rail_deck(**models, vddio=vddio),
                             ("vddio_high", "vref_high", "vddio_fall", "vref_fall", "vssio_high"),
                             dev["char"]["ngspice_flags"], pdk)
            rail["high_ratio"] = ratio_metric(rail["vref_high"], rail["vddio_high"])
            rail["fall_ratio"] = (rail["vref_fall"] / rail["vddio_fall"]
                                   if abs(rail["vddio_fall"]) > 1e-9 else None)
            rail["vssio_high_v"] = rail.pop("vssio_high")
            rail["high_within_1pct"] = rail["high_ratio"]["within_illustrative_1pct_vddio"]
            if not rail["high_within_1pct"]:
                result["failures"].append("rail_ramp_ratio")
            result["rail"] = rail
            results[name] = result
            print(f"{name}: {'FAIL' if result['failures'] else 'PASS'} "
                  f"dc_err_mV={{{', '.join(k + ':' + format(v['error_v']*1e3, '.3f') for k,v in result['dc'].items())}}} "
                  f"transient_delta_mV={kick['kick_excursion_from_unloaded_v']*1e3:.3f} "
                  f"recovery_us={'n/a' if kick['recovery_s'] is None else format(kick['recovery_s']*1e6, '.3f')} "
                  f"rail_err_mV={rail['high_ratio']['error_v']*1e3:.3f}", flush=True)

    failed = any(case["failures"] for case in results.values())
    report = {
        "status": "fail_witness" if failed else "pass_witness",
        "signoff": False,
        "cell": str(cell),
        "pdk_root": str(pdk),
        "input_proxy": {"fanout": 16, "capacitance_f": X16_CAP_F,
                        "coupling_kickback_f": KICK_CAP_F,
                        "leakage_ohm_per_rail": X16_LEAK_OHM,
                        "leakage_model": "16 x 1 Gohm input-to-each-rail equivalents"},
        "load_proxy_a_each_direction": LOAD_A,
        "transient_load_step_a": LOAD_STEP_A,
        "illustrative_limit": {"abs_vref_error_fraction_of_vddio": RATIO_LIMIT,
                               "qualification": False},
        "limitations": ["no resistor/MOS mismatch", "no layout or PEX", "no dynamic signoff",
                        "no foundry characterization at DDR1 VDDIO", "RX comparator at 2.5 V is uncharacterized"],
        "pu_ok_guidance": "An external supervisor should hold PU_OK low until both rails are valid and VREF has settled; deassert before either rail falls. This cell provides no supervisor or PU_OK signal.",
        "cases": results,
    }
    if args.output:
        args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(f"status={report['status']} signoff=false", flush=True)
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
