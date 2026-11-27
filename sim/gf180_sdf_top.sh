#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# SDF-annotated gate-level closure for sdram_phy_top + sdram_model.
#
# Two corners:
#   max_ss_125C_3v00  slow silicon, slow clock tree
#   min_ff_n40C_3v60  fast silicon, fast clock tree
#
# The GF180 functional Verilog view has no specify blocks, so Icarus would
# silently drop every SDF annotation.  generator/emit_gf180_timing_models.py
# derives the arcs from the matching Liberty file and writes a model with
# specify paths; the SDF then replaces the placeholder delays.
set -e
cd "$(dirname "$0")/.."

TOP=sdram_phy_core
NL=flow/runs/gf180-as-7t3v3-$TOP/final/nl/$TOP.nl.v
MODELS=pdks/gf180mcuD/libs.ref/gf180mcu_as_sc_mcu7t3v3/verilog/gf180mcu_as_sc_mcu7t3v3.v
LIBDIR=pdks/gf180mcuD/libs.ref/gf180mcu_as_sc_mcu7t3v3/lib

if [ ! -f "$NL" ]; then
    echo "SKIP gf180_sdf_top: run TOP=sdram_phy_core sh flow/run.sh gf180-as-7t3v3 first"
    exit 0
fi

run_corner() {
    corner=$1
    sdf="$2"
    lib="$3"
    tag=$4
    if [ ! -f "$sdf" ]; then
        echo "SKIP gf180_sdf_top $corner: no SDF"
        return 0
    fi
    python3 generator/emit_gf180_timing_models.py \
        --cells "$MODELS" --liberty "$lib" --sdf "$sdf" --netlist "$NL" \
        --out "/tmp/gf180_tm_$tag.v" > "/tmp/gf180_tm_$tag.log"
    iverilog -g2012 -gspecify -o "/tmp/gf180_sdf_$tag" \
        -DFUNCTIONAL -DSDF_FILE="\"$sdf\"" -DCL=2 \
        "/tmp/gf180_tm_$tag.v" "$NL" \
        rtl/sdr_ctrl.sv sim/sdram_model.sv sim/pad_cell_generic.sv tb/tb_phy_top_sdf.sv \
        2>&1 | grep -E ' error' | head -10 || true
    vvp "/tmp/gf180_sdf_$tag" > "reports/gf180_sdf_top_$tag.log" 2>&1 || true
    grep -E "PASS|FAIL|SDF|Warning" "reports/gf180_sdf_top_$tag.log" | tail -8
    if grep -q "PASS phy_top_sdf" "reports/gf180_sdf_top_$tag.log"; then
        echo "PASS gf180_sdf_top $corner"
        return 0
    fi
    echo "FAIL gf180_sdf_top $corner (see reports/gf180_sdf_top_$tag.log)"
    return 1
}

rc=0
run_corner max_ss_125C_3v00 \
    "$PWD/flow/runs/gf180-as-7t3v3-$TOP/final/sdf/max_ss_125C_3v00/${TOP}__max_ss_125C_3v00.sdf" \
    "$LIBDIR/gf180mcu_as_sc_mcu7t3v3__ss_125C_3v00.lib" max_ss || rc=1
run_corner min_ff_n40C_3v60 \
    "$PWD/flow/runs/gf180-as-7t3v3-$TOP/final/sdf/min_ff_n40C_3v60/${TOP}__min_ff_n40C_3v60.sdf" \
    "$LIBDIR/gf180mcu_as_sc_mcu7t3v3__ff_n40C_3v60.lib" min_ff || rc=1

if [ "$rc" -eq 0 ]; then echo GF180_SDF_TOP_DONE; fi
exit "$rc"
