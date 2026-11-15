#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# P0-4: enhanced PHY modules, DQM read mask, BIST loop (x8 and x16).
set -e
cd "$(dirname "$0")/.."

if [ -z "${IN_LIBRELANE_SHELL:-}" ] && [ -f /opt/librelane/shell.nix ]; then
    exec nix-shell /opt/librelane --run "IN_LIBRELANE_SHELL=1 sh sim/phy.sh"
fi

mkdir -p sim/obj
iverilog -g2012 -o sim/obj/tb_phy_enh \
    rtl/read_capture_ctrl.sv rtl/clock_forward.sv rtl/dq_turnaround.sv \
    sim/sdram_model.sv tb/tb_phy_enh.sv
vvp sim/obj/tb_phy_enh

iverilog -g2012 -Ptb_bist_loop.DATA_BITS=8 -o sim/obj/tb_bist_x8 \
    rtl/sdr_bist.sv rtl/sdr_ctrl.sv rtl/sdr_phy.sv sim/sdram_model.sv tb/tb_bist_loop.sv
vvp sim/obj/tb_bist_x8

iverilog -g2012 -Ptb_bist_loop.DATA_BITS=16 -o sim/obj/tb_bist_x16 \
    rtl/sdr_bist.sv rtl/sdr_ctrl.sv rtl/sdr_phy.sv sim/sdram_model.sv tb/tb_bist_loop.sv
vvp sim/obj/tb_bist_x16

echo PHY_DONE
