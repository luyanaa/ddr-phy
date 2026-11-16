#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Exit-code mutation test: compile each TB with -DMUTATE, inject one error,
# and require a non-zero simulator exit. This proves set -e is not hiding
# FAIL-only testbenches.
set -e
cd "$(dirname "$0")/.."

if [ -z "${IN_LIBRELANE_SHELL:-}" ] && [ -f /opt/librelane/shell.nix ]; then
    exec nix-shell /opt/librelane --run "IN_LIBRELANE_SHELL=1 sh sim/mutation.sh"
fi

mkdir -p sim/obj

expect_fail() {
    name=$1
    shift
    iverilog -g2012 -DMUTATE "$@" -o "sim/obj/mut_$name"
    if vvp "sim/obj/mut_$name" >"sim/obj/mut_$name.log" 2>&1; then
        echo "FAIL mutation $name returned 0" >&2
        exit 1
    fi
    if ! grep -q 'MUTATION: injected failure' "sim/obj/mut_$name.log"; then
        echo "FAIL mutation $name did not hit the injected branch" >&2
        exit 1
    fi
    echo "PASS mutation $name"
}

expect_fail burst sim/sdram_model.sv tb/tb_burst.sv
expect_fail refresh rtl/sdr_ctrl.sv rtl/sdr_phy.sv sim/sdram_model.sv tb/tb_refresh.sv
expect_fail phy_top rtl/sdr_phy.sv rtl/clock_forward.sv rtl/read_capture_ctrl.sv \
    rtl/dq_turnaround.sv rtl/phy_io_adapter.sv sim/pad_cell_generic.sv \
    rtl/sdram_phy_top.sv tb/tb_phy_top.sv
expect_fail phy_enh rtl/read_capture_ctrl.sv rtl/clock_forward.sv rtl/dq_turnaround.sv \
    sim/sdram_model.sv tb/tb_phy_enh.sv
expect_fail pad_adapter rtl/phy_io_adapter.sv sim/pad_cell_generic.sv tb/tb_pad_adapter.sv
expect_fail timing_checks sim/sdram_timing_model.sv sim/read_capture.sv tb/tb_timing_checks.sv
expect_fail turnaround_ctrl rtl/sdr_ctrl.sv tb/tb_turnaround_ctrl.sv

iverilog -g2012 -DMUTATE -Ptb_bist_loop.DATA_BITS=8 -o sim/obj/mut_bist_x8 \
    rtl/sdr_bist.sv rtl/sdr_ctrl.sv rtl/sdr_phy.sv sim/sdram_model.sv tb/tb_bist_loop.sv
if vvp sim/obj/mut_bist_x8 >sim/obj/mut_bist_x8.log 2>&1; then
    echo "FAIL mutation bist_x8 returned 0" >&2
    exit 1
fi
grep -q 'MUTATION: injected failure' sim/obj/mut_bist_x8.log
echo "PASS mutation bist_x8"

echo MUTATION_DONE
