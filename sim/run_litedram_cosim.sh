#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Regenerate the LiteDRAM controller and run the DFI co-simulation.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
PYTHONPATH="$ROOT/third_party/litedram" /tmp/litedram-venv/bin/python \
    sim/gen_litedram_ctrl.py
BUILD=${TMPDIR:-/tmp}/litedram_cosim_build
rm -rf "$BUILD"; mkdir -p "$BUILD"
verilator --binary --timing -j 4 -Wno-fatal -Wno-lint -Wno-style \
    --top-module tb_litedram_cosim -sv \
    sim/litedram_ctrl.v rtl/sdram_phy_core.sv rtl/sdr_phy.sv \
    rtl/clock_forward.sv rtl/read_capture_ctrl.sv rtl/read_capture_cdc.sv \
    rtl/dq_turnaround.sv sim/sdram_model.sv sim/pad_cell_generic.sv \
    tb/tb_litedram_cosim.sv --Mdir "$BUILD" >"$BUILD/build.log" 2>&1
timeout 60 "$BUILD/Vtb_litedram_cosim"
