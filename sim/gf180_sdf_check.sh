#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# GF180 SDF-annotated gate-level check of the half-cycle write launch.
# Uses the post-PnR netlist and max_ff SDF from sh sim/gf180_pnr.sh.
set -e
cd "$(dirname "$0")/.."

GF=pkgs
NL=flow/runs/gf180-as-7t3v3/final/nl/sdr_phy.nl.v
SDF=flow/runs/gf180-as-7t3v3/final/sdf/max_ff_n40C_3v60/sdr_phy__max_ff_n40C_3v60.sdf
CELLS=pdks/gf180mcuD/libs.ref/gf180mcu_as_sc_mcu7t3v3/verilog/gf180mcu_as_sc_mcu7t3v3.v

if [ ! -f "$NL" ] || [ ! -f "$SDF" ] || [ ! -f "$CELLS" ]; then
    echo "SKIP gf180_sdf_check: run sh sim/gf180_pnr.sh first"
    exit 0
fi

sed "s#@SDF@#$PWD/$SDF#" sim/tb_sdf_gate.sv > /tmp/tb_gf180_sdf.sv

iverilog -g2012 -o /tmp/gf180_sdf \
    "$CELLS" "$NL" /tmp/tb_gf180_sdf.sv 2>&1 | grep -E ' error' | head -5 || true
vvp /tmp/gf180_sdf > reports/gf180_sdf_check.log 2>&1 || true
grep -E 'PASS|FAIL|transitions' reports/gf180_sdf_check.log | tail -6
if grep -q 'PASS sdf-gate-check' reports/gf180_sdf_check.log; then
    echo "PASS gf180_sdf_check"
    echo GF180_SDF_CHECK_DONE
else
    echo "FAIL gf180_sdf_check (see reports/gf180_sdf_check.log)"
    exit 1
fi
