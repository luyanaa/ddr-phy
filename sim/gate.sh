#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
#
# Functional simulation of sdr_phy after mapping onto sky130 HD standard
# cells. The cell models are the functional view (FUNCTIONAL). No SDF is
# applied. This is not a timing simulation, not a pad simulation, and not
# a sign-off: wire delay, derating and the pad are absent.
#
# dfxtp's functional model has one UNIT_DELAY on the flop, then a zero-delay
# buf. lpflow_isobufsrc sits on the D pin (reset isolation) and its
# functional model is combinational, so it does not add a second delay.
# Every pad except ck is a flop Q; ck is assigned from clk. The testbench
# samples #1 after the edge, so UNIT_DELAY must be shorter than that or the
# sample races the cell. #0.1 is still not a timing number.
#
# The netlist is elaborated at the module defaults (x8, CL 2, one rank).
# sim/sdr_phy_gate.v is a parameter shell around that netlist so the
# existing testbench can still override parameters; any other setting is
# a compile error, not a silent mismatch.
set -e
cd "$(dirname "$0")/.."

if [ -z "${IN_LIBRELANE_SHELL:-}" ] && [ -f /opt/librelane/shell.nix ]; then
    exec nix-shell /opt/librelane --run "IN_LIBRELANE_SHELL=1 sh sim/gate.sh"
fi

if [ -z "${SCL_ROOT:-}" ]; then
    base=$HOME/.ciel/ciel/sky130/versions
    ver=$(ls -1 "$base" | sort | tail -1)
    SCL_ROOT=$base/$ver/sky130A/libs.ref/sky130_fd_sc_hd
fi
CELL_LIB=$SCL_ROOT/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
CELL_V=$SCL_ROOT/verilog/sky130_fd_sc_hd.v
PRIMS=$SCL_ROOT/verilog/primitives.v

mkdir -p sim/obj

yosys -p "read_verilog -sv rtl/sdr_phy.sv; synth -top sdr_phy; dfflibmap -liberty $CELL_LIB; abc -liberty $CELL_LIB; clean; rename sdr_phy sdr_phy_g; write_verilog -noattr -noexpr -nohex sim/obj/sdr_phy_sky130.v"

iverilog -g2012 -DCL=2 -DDATA_BITS=8 -DFUNCTIONAL -DUNIT_DELAY='#0.1' \
    -o sim/obj/tb_gate_cl2 \
    "$PRIMS" "$CELL_V" sim/obj/sdr_phy_sky130.v sim/sdr_phy_gate.v tb/tb_sdr_phy.sv
vvp sim/obj/tb_gate_cl2
echo GATE_DONE
