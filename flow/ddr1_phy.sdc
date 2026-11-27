# SPDX-License-Identifier: Apache-2.0
# IHP130 DDR1 PHY first backend constraints.
#
# This is a bring-up constraint set, not a DDR1 signoff:
# - sys_clk = CK/2 = 50 MHz, ck/ck90 = 100 MHz, ck90 lags ck by 2.5 ns.
# - dqs_capture is a source-synchronous read strobe, not a free-running clock.
# - pad/package/board delays and the IHP130 DQ/CK pad macros are outside this
#   harden; the output/input delays below are placeholders for the core-side
#   boundary, not measured board numbers.
# - The clock groups are asynchronous for this first harden. They must be
#   replaced by the real CDC/source-synchronous constraints before signoff.
set tCK 10.000
set tSYS 20.000
set tUNC 0.200

create_clock -name sys_clk -period $tSYS -waveform {0 10} [get_ports sys_clk]
create_clock -name ck     -period $tCK  -waveform {0 5}  [get_ports ck]
create_clock -name ck90   -period $tCK  -waveform {2.5 7.5} [get_ports ck90]
create_clock -name dqs_capture -period $tCK -waveform {0 5} [get_ports dqs_capture]

create_generated_clock -name pad_ck -source [get_ports ck] -divide_by 1 [get_ports pad_ck]
create_generated_clock -name pad_ck_n -source [get_ports ck] -divide_by 1 -invert [get_ports pad_ck_n]

set_clock_uncertainty -setup $tUNC [get_clocks {sys_clk ck ck90 dqs_capture pad_ck pad_ck_n}]
set_clock_uncertainty -hold 0.050 [get_clocks {sys_clk ck ck90 dqs_capture pad_ck pad_ck_n}]
set_clock_groups -asynchronous -group {sys_clk} -group {ck ck90 pad_ck pad_ck_n} -group {dqs_capture}

# Core-side output boundary placeholders. The pad/board numbers are not
# characterized for this harden; do not read these as DDR1 timing closure.
set ca_ports [get_ports {a[*] ba[*] cke cs_n ras_n cas_n we_n}]
set_output_delay -clock pad_ck -max  0.500 $ca_ports
set_output_delay -clock pad_ck -min 0.000 $ca_ports

set dq_ports [get_ports {dq_o[*] dm dq_oe}]
set_output_delay -clock ck90 -max  0.500 $dq_ports
set_output_delay -clock ck90 -min 0.000 $dq_ports

set dqs_ports [get_ports {dqs_o dqs_oe}]
set_output_delay -clock ck -max  0.500 $dqs_ports
set_output_delay -clock ck -min 0.000 $dqs_ports

set_input_delay -clock dqs_capture -max  0.500 [get_ports {dq_i[*]}]
set_input_delay -clock dqs_capture -min 0.000 [get_ports {dq_i[*]}]

# rst is an asynchronous cold reset; do not create a clock for it.
set_false_path -from [get_ports rst]
