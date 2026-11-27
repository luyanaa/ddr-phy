#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Fold a transient DQ waveform into a DDR1 UI eye and render it with gnuplot."""

import argparse
import subprocess
from pathlib import Path


def read_wave(path):
    rows = []
    for line in path.read_text().splitlines():
        parts = line.split()
        if len(parts) != 2:
            continue
        try:
            t_ns = float(parts[0]) * 1e9
            v = float(parts[1])
        except ValueError:
            continue
        rows.append((t_ns, v))
    if not rows:
        raise SystemExit(f"no waveform points in {path}")
    return rows


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--csv", type=Path, required=True)
    ap.add_argument("--png", type=Path, required=True)
    ap.add_argument("--folded", type=Path, help="write folded (phase, voltage) CSV")
    ap.add_argument("--ui-ns", type=float, default=5.0)
    ap.add_argument("--start-ns", type=float, default=10.0)
    ap.add_argument("--ui-count", type=int, help="number of UI windows; default: all available")
    ap.add_argument("--vref", type=float, default=1.25)
    ap.add_argument("--title", default="IHP130 DDR1 DQ write eye")
    args = ap.parse_args()

    rows = read_wave(args.csv)
    t_end = rows[-1][0]
    n_ui = args.ui_count or int((t_end - args.start_ns) // args.ui_ns)
    if n_ui < 4:
        raise SystemExit("waveform shorter than four UI")

    folded = []
    for i in range(n_ui):
        t0 = args.start_ns + i * args.ui_ns
        for t, v in rows:
            if t0 <= t < t0 + args.ui_ns:
                folded.append((t - t0, v, i))
    if not folded:
        raise SystemExit("no points inside UI windows")

    # Central 40% of the UI: exclude transition tails when reporting height.
    lo = 0.30 * args.ui_ns
    hi = 0.70 * args.ui_ns
    center = [v for ph, v, _ in folded if lo <= ph <= hi]
    high = [v for v in center if v > args.vref + 0.05]
    low = [v for v in center if v < args.vref - 0.05]
    v_high_min = min(high) if high else float("nan")
    v_low_max = max(low) if low else float("nan")
    height_mv = (v_high_min - v_low_max) * 1e3

    if args.folded:
        args.folded.parent.mkdir(parents=True, exist_ok=True)
        with args.folded.open("w") as f:
            f.write("phase_ns,voltage\n")
            for ph, v, _ in folded:
                f.write(f"{ph:.6f},{v:.6f}\n")

    plot_csv = args.folded or args.png.with_suffix(".folded.csv")
    if not args.folded:
        with plot_csv.open("w") as f:
            f.write("phase_ns,voltage\n")
            for ph, v, _ in folded:
                f.write(f"{ph:.6f},{v:.6f}\n")

    gnuplot = f"""
set datafile separator ","
set terminal pngcairo size 1600,900 enhanced font "DejaVu Sans,12"
set output "{args.png.resolve()}"
set title "{args.title}\\n{len(rows)} samples, {n_ui} UI overlays, central eye height {height_mv:.0f} mV" font "DejaVu Sans,14"
set xlabel "Time within UI (ns)"
set ylabel "QFN48 package lead voltage (V)"
set xrange [0:{args.ui_ns:g}]
set yrange [0.45:1.95]
set grid xtics ytics lc rgb "#d0d0d0"
set border 3
set tics nomirror
set style line 1 lc rgb "#0b5394" lw 0.8
set arrow 1 from 0,{args.vref:g} to {args.ui_ns:g},{args.vref:g} nohead dt 2 lc rgb "#999999"
set arrow 2 from {args.ui_ns/2:g},0.45 to {args.ui_ns/2:g},1.95 nohead dt 2 lc rgb "#bbbbbb"
set label 1 sprintf("VREF = %.2f V", {args.vref:g}) at 0.08,{args.vref+0.06:g} left font "DejaVu Sans,10" tc rgb "#666666"
plot "{plot_csv.resolve()}" using 1:2 with lines ls 1 notitle
"""
    script = args.png.with_suffix(".gnuplot")
    script.write_text(gnuplot)
    subprocess.run(["gnuplot", str(script)], check=True)
    print(f"{args.png}: {n_ui} UI, VOH_min={v_high_min:.3f} V, VOL_max={v_low_max:.3f} V, height={height_mv:.0f} mV")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
