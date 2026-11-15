#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# P0-2: timing-aware read-capture phase sweep and negative/mutation tests.
set -e
cd "$(dirname "$0")/.."

if [ -z "${IN_LIBRELANE_SHELL:-}" ] && [ -f /opt/librelane/shell.nix ]; then
    exec nix-shell /opt/librelane --run "IN_LIBRELANE_SHELL=1 sh sim/sweep.sh"
fi

mkdir -p sim/obj
iverilog -g2012 -o sim/obj/tb_timing_sweep \
    sim/sdram_timing_model.sv sim/read_capture.sv tb/tb_timing_sweep.sv
vvp sim/obj/tb_timing_sweep

iverilog -g2012 -o sim/obj/tb_timing_checks \
    sim/sdram_timing_model.sv sim/read_capture.sv tb/tb_timing_checks.sv
vvp sim/obj/tb_timing_checks

echo SWEEP_DONE
