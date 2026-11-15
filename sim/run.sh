#!/bin/sh
# SDR PHY and the pin-level SDRAM model. Tools come from nix-shell /opt/librelane.
set -e
cd "$(dirname "$0")/.."

if [ -z "${IN_LIBRELANE_SHELL:-}" ] && [ -f /opt/librelane/shell.nix ]; then
    exec nix-shell /opt/librelane --run "IN_LIBRELANE_SHELL=1 sh sim/run.sh"
fi

mkdir -p sim/obj
yosys -q -p 'read_verilog -sv rtl/sdr_phy.sv; synth -top sdr_phy; stat'

run_one() {
    cl=$1
    bits=$2
    out="sim/obj/tb_cl${cl}_dq${bits}"
    iverilog -g2012 -DCL="$cl" -DDATA_BITS="$bits" \
        -o "$out" rtl/sdr_phy.sv tb/tb_sdr_phy.sv
    vvp "$out"
}

run_model() {
    cl=$1
    out="sim/obj/tb_model_cl${cl}"
    iverilog -g2012 -DCL="$cl" \
        -o "$out" rtl/sdr_phy.sv sim/sdram_model.sv tb/tb_sdram_model.sv
    vvp "$out"
}

run_loop() {
    cl=$1
    out="sim/obj/tb_loop_cl${cl}"
    iverilog -g2012 -DCL="$cl" \
        -o "$out" rtl/sdr_ctrl.sv rtl/sdr_phy.sv sim/sdram_model.sv tb/tb_sdr_loop.sv
    vvp "$out"
}

run_checker() {
    out="sim/obj/tb_checker"
    iverilog -g2012 -o "$out" sim/sdram_checker.sv tb/tb_sdram_checker.sv
    vvp "$out"
}

run_one 2 8
run_one 2 16
run_one 3 8
run_one 3 16
run_model 2
run_model 3
run_loop 2
run_loop 3
run_checker
