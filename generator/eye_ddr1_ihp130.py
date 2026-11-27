#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""IHP130 DDR1 DQ eye from the transistor-level SSTL-2 pad + QFN48 package.

The data pattern is the same 16-word pattern used by tb_ddr1_ihp130_loop;
this is a pad/package electrical eye, not a full LiteDRAM co-simulation.
"""

import argparse
import math
import tempfile
from pathlib import Path

import yaml

from char_ihp130_sstl2 import CASES, CELL, MODEL, OSDI, SUBCKT, pdk_root, run_ngspice
from emit_char_pad import ROOT, SPECS, model_lines


def pattern_word(index):
    k = (13 * index + 3) & 0xff
    return bytes((k ^ 0x39, k ^ 0xc0, (~k) & 0xff, k))


def dq_bits(lane, words):
    bits = []
    for i in range(words):
        word = pattern_word(i)
        for byte in word:
            bits.append((byte >> lane) & 1)
    return bits


def pwl(bits, ui_ns, start_ns, vdd, edge_ns=0.30):
    pts = ["0 0"]
    prev = 0.0
    for i, bit in enumerate(bits):
        t = start_ns + i * ui_ns
        v = vdd if bit else 0.0
        pts.append(f"{t:g}n {prev:.3f}")
        pts.append(f"{t + edge_ns:g}n {v:.3f}")
        prev = v
    return "PWL(" + " ".join(pts) + ")"


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--pdk-root")
    ap.add_argument("--case", default="tt", choices=CASES)
    ap.add_argument("--lane", type=int, default=0, choices=range(8))
    ap.add_argument("--words", type=int, default=16)
    ap.add_argument("--ui-ns", type=float, default=5.0, help="DDR1 UI = CK/2 = 5 ns")
    ap.add_argument("--output", type=Path, default=Path("results/ihp130/ddr1_eye.csv"))
    ap.add_argument("--deck", type=Path, help="keep the generated SPICE deck here")
    args = ap.parse_args()

    dev = yaml.safe_load((SPECS / "devices/ihp130.yaml").read_text())
    pdk = pdk_root(dev, args.pdk_root)
    mos, res, temp_c, vdd, vddio = CASES[args.case]
    vref = vddio / 2
    args.output.parent.mkdir(parents=True, exist_ok=True)
    bits = dq_bits(args.lane, args.words)
    # Two extra UIs let the last bit settle before .tran stops.
    stop_ns = 10.0 + (len(bits) + 2) * args.ui_ns

    deck = f"""* IHP130 DDR1 DQ eye: {args.words} words, lane {args.lane}, case {args.case}, UI {args.ui_ns} ns
{model_lines(dev, pdk, mos)}
.lib "{pdk / MODEL / 'cornerRES.lib'}" res_{res}
.include "{CELL}"
.include "{ROOT / 'spice/package/qfn48_pkg.spice'}"
.temp {temp_c}
.options klu method=gear maxord=2
VDD vdd 0 {vdd}
VDDIO io 0 {vddio}
VREF ref 0 {vref}
VTT term 0 {vref}
VPU ok 0 {vddio}
VOE oe 0 PWL(0 0 5n 0 5.3n {vdd} {stop_ns:g}n {vdd})
VDATA data 0 {pwl(bits, args.ui_ns, 10.0, vdd)}
XTX data oe rx_tx pad_tx ref ok vdd 0 io 0 {SUBCKT}
XPKG pad_tx pkg_out qfn48_pkg L=3.037n R=0.142 C=0.1p
RTERM pkg_out term 50
CTERM pkg_out 0 5p
.tran 5p {stop_ns:g}n 0 5p
.control
run
set wr_vecnames
wrdata {args.output.resolve()} v(pkg_out)
.endc
.end
"""

    if args.deck:
        args.deck.parent.mkdir(parents=True, exist_ok=True)
        args.deck.write_text(deck)
    with tempfile.TemporaryDirectory(prefix="ihp130-eye-") as work:
        work = Path(work)
        (work / ".spiceinit").write_text("set num_threads=1\n" + dev["char"]["spiceinit"].replace("@root@", str(pdk)))
        deck_path = work / "eye.spice"
        deck_path.write_text(deck)
        text = run_ngspice(work, deck_path, dev["char"]["ngspice_flags"], pdk)
        if "run simulation(s) aborted" in text.lower():
            raise SystemExit(text[-3000:])
    print(f"wrote {args.output} ({len(bits)} bits, {stop_ns:g} ns, case {args.case}, VREF {vref} V)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
