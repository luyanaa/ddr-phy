#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# SDF-annotated gate-level check of the half-cycle write launch.
#
# Uses the post-PnR netlist and the max_ss SDF from the constrained
# LibreLane run. Verifies the P1-3 path-B contract on real placed delays:
# dq_o / dm / dq_oe may only change on a falling edge, and the write data
# reaches the pin.
set -e
cd "$(dirname "$0")/.."

SKY=$(ls -d "$HOME"/.ciel/ciel/sky130/versions/*/sky130A 2>/dev/null | tail -1)
if [ -z "$SKY" ]; then echo "SKIP sdf_gate_check: sky130A not found"; exit 0; fi
NL=flow/runs/sky130/final/nl/sdr_phy.nl.v
SDF=flow/runs/sky130/final/sdf/max_ss_100C_1v60/sdr_phy__max_ss_100C_1v60.sdf
if [ ! -f "$NL" ] || [ ! -f "$SDF" ]; then
    echo "SKIP sdf_gate_check: run sh flow/run.sh sky130 first"
    exit 0
fi

python3 generator/emit_sdf_tb.py

iverilog -g2012 -o /tmp/sdf_gate \
    -I "$SKY/libs.ref/sky130_fd_sc_hd/verilog" \
    "$SKY/libs.ref/sky130_fd_sc_hd/verilog/primitives.v" \
    "$SKY/libs.ref/sky130_fd_sc_hd/verilog/sky130_fd_sc_hd.v" \
    "$NL" sim/tb_sdf_gate.sv 2>&1 | grep -vE 'warning|^$' | head -5 || true

vvp /tmp/sdf_gate > reports/sdf_gate_check.log 2>&1 || true
grep -E 'PASS|FAIL|transitions' reports/sdf_gate_check.log | tail -6
if grep -q 'PASS sdf-gate-check' reports/sdf_gate_check.log; then
    echo "PASS sdf_gate_check"
    echo SDF_GATE_CHECK_DONE
else
    echo "FAIL sdf_gate_check (see reports/sdf_gate_check.log)"
    exit 1
fi
