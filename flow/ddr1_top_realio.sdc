# SPDX-License-Identifier: Apache-2.0
# IHP130 DDR1 full-top (LiteDRAM controller + init + PHY) constraint set.
#
# This replaces the first bring-up set's two biggest placeholders:
# - sys_clk / ck / ck90 are now one synchronous 50/100/100 MHz family; only
#   the source-synchronous dqs_capture is asynchronous to the core.
# - I/O delays now carry the measured single-DQ pad + QFN48 package budget
#   from results/ihp130 (SS PEX), not a generic 0.5 ns placeholder.
#
# Still not a DDR1 signoff: the top has no pad ring/level shifters, the CK/CA
# pad is not extracted, and the 0.400 ns DQS-OE advance is a design budget.
set tCK 10.000
set tSYS 20.000
set tUNC_SETUP 0.200
set tUNC_HOLD 0.050

# CK is the board clock; sys_clk is the half-rate controller clock and ck90
# is the 90-degree PHY clock. They are related, not asynchronous groups.
create_clock -name ck      -period $tCK  -waveform {0 5}   [get_ports ck]
create_clock -name sys_clk -period $tSYS -waveform {0 10}  [get_ports sys_clk]
create_clock -name ck90    -period $tCK  -waveform {2.5 7.5} [get_ports ck90]
create_clock -name dqs_capture -period $tCK -waveform {0 5} [get_ports dqs_capture]
create_generated_clock -name pad_ck   -source [get_ports ck] -divide_by 1         [get_ports pad_ck]
create_generated_clock -name pad_ck_n -source [get_ports ck] -divide_by 1 -invert [get_ports pad_ck_n]

set_propagated_clock [all_clocks]

# sg13g2 liberty has default_max_fanout = 8; SDC cannot relax it.  The two
# 16-load CTS roots are split into 2 x buf_8 by flow/patches/librelane-3.0.17-cts.patch.
# MAX_FANOUT_CONSTRAINT=16 is kept for synthesis only, not as a PNR signoff claim.
set_clock_uncertainty -setup $tUNC_SETUP [get_clocks {sys_clk ck ck90 dqs_capture pad_ck pad_ck_n}]
set_clock_uncertainty -hold  $tUNC_HOLD  [get_clocks {sys_clk ck ck90 dqs_capture pad_ck pad_ck_n}]
set_clock_groups -asynchronous -group {dqs_capture} \
                                 -group {sys_clk ck ck90 pad_ck pad_ck_n}

# Measured SG13G2 single-DQ pad, SS PEX (results/ihp130/sstl2-dq-route-eco):
#   TX rise/fall 1.865 / 2.201 ns; RX rise/fall 1.615 / 1.967 ns.
# QFN48 package flight is a first-order 0.050 ns budget.
set PAD_TX_SLOW 2.201
set PAD_TX_FAST 1.865
set PAD_RX_SLOW 1.967
set PAD_RX_FAST 1.615
set PKG_FLIGHT  0.050
set DQS_OE_ADVANCE 0.400

# CK/CA use the same ihp130_sstl2_dq pad macro and the same 50 ohm / 5 pF
# load as DQ, so the opt1 PEX TX numbers apply: SS rise/fall 1.865/1.980 ns.
# Package flight is the same 0.050 ns first-order budget.
set CA_PAD_TX_SLOW 1.980
set CA_PAD_TX_FAST 1.865
set CA_TX_MAX [expr {$CA_PAD_TX_SLOW + $PKG_FLIGHT}]
set CA_TX_MIN [expr {$CA_PAD_TX_FAST + $PKG_FLIGHT}]

set ca_ports [get_ports {a[*] ba[*] cke cs_n ras_n cas_n we_n}]
set_output_delay -clock pad_ck -max $CA_TX_MAX $ca_ports
set_output_delay -clock pad_ck -min $CA_TX_MIN $ca_ports

# DQ/DM/OE use the measured DQ pad. DQS is deliberately 0.400 ns later so
# the DQ write data/OE leads the DQS edge at the package pin.
set dq_ports [get_ports {dq_o[*] dm dq_oe}]
set_output_delay -clock ck90 -max [expr {$PAD_TX_SLOW + $PKG_FLIGHT}] $dq_ports
set_output_delay -clock ck90 -min [expr {$PAD_TX_FAST + $PKG_FLIGHT}] $dq_ports

set dqs_ports [get_ports {dqs_o dqs_oe}]
set_output_delay -clock ck -max [expr {$PAD_TX_SLOW + $PKG_FLIGHT + $DQS_OE_ADVANCE}] $dqs_ports
set_output_delay -clock ck -min [expr {$PAD_TX_FAST + $PKG_FLIGHT + $DQS_OE_ADVANCE}] $dqs_ports

# Read data reaches the PHY before the delayed DQS capture strobe by the
# DQS-OE advance; the resulting input delays are negative by design.
set dq_in_ports [get_ports {dq_i[*]}]
set_input_delay -clock dqs_capture -max [expr {$PAD_RX_SLOW - $PAD_TX_SLOW - $DQS_OE_ADVANCE}] $dq_in_ports
set_input_delay -clock dqs_capture -min [expr {$PAD_RX_FAST - $PAD_TX_FAST - $DQS_OE_ADVANCE}] $dq_in_ports

# System-side control/data ports. The board/SoC budget is not characterized yet;
# 0.5 ns is a placeholder that at least keeps these ports from being unconstrained.
set sys_in_ports [get_ports {cmd_valid cmd_we cmd_addr[*] w_data[*] w_we[*]}]
set_input_delay -clock sys_clk -max 0.500 $sys_in_ports
set_input_delay -clock sys_clk -min 0.000 $sys_in_ports

set sys_out_ports [get_ports {init_done read_error dfi_error phy_ready train_busy train_failed cmd_ready w_ready r_valid r_data[*] dqs_tap_valid dqs_tap_value[*]}]
set_output_delay -clock sys_clk -max 0.500 $sys_out_ports
set_output_delay -clock sys_clk -min 0.000 $sys_out_ports

# CK outputs are generated clocks; annotate them as zero-delay clock outputs.
set_output_delay -clock ck -max 0.000 [get_ports {pad_ck pad_ck_n}]
set_output_delay -clock ck -min 0.000 [get_ports {pad_ck pad_ck_n}]

# rst and dqs_tap_ready still get an annotation so check_setup is clean;
# they are false-pathed below.
set_input_delay -clock sys_clk -max 0.500 [get_ports {rst dqs_tap_ready}]
set_input_delay -clock sys_clk -min 0.000 [get_ports {rst dqs_tap_ready}]

# rst is an asynchronous cold reset; do not create a clock for it.
set_false_path -from [get_ports rst]

# DQS tap bus is a static/async control interface to the AD-PLL delay line.
set_false_path -from [get_ports dqs_tap_ready]
set_false_path -to [get_ports {dqs_tap_valid dqs_tap_value[*]}]
