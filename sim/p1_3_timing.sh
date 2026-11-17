#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# P1-3: CK output + end-to-end timing margins.
#
#   1. pad data-path delay characterization across the P1-1 PVT points
#   2. yosys synthesis of sdram_phy_top with the GF180 standard cells
#   3. OpenSTA at tt/ss/ff for the digital clk->pad and pad->FF paths
#   4. margin computation into reports/p1_3_margins.json + .md
#
# The STA netlist is unplaced and has no wire load: the numbers are
# pre-layout estimates, not signoff. Pad delays come from SPICE.
set -e
cd "$(dirname "$0")/.."

if [ -z "${IN_LIBRELANE_SHELL:-}" ] && [ -f /opt/librelane/shell.nix ]; then
    exec nix-shell /opt/librelane --run "IN_LIBRELANE_SHELL=1 sh sim/p1_3_timing.sh"
fi

GF=$(ls -d "$HOME"/.ciel/ciel/gf180mcu/versions/*/gf180mcuD 2>/dev/null | tail -1)
if [ -z "$GF" ] || [ ! -d "$GF/libs.ref/gf180mcu_fd_sc_mcu7t5v0/lib" ]; then
    echo "SKIP p1_3_timing: local gf180mcuD PDK not found"
    exit 0
fi
LIBDIR="$GF/libs.ref/gf180mcu_fd_sc_mcu7t5v0/lib"
mkdir -p reports/sta

echo "== 1/4 pad delay characterization"
for ct in "tt 27" "ss 125" "ff -40"; do
    set -- $ct
    python3 generator/emit_char_delay.py --backend gf180mcuD \
        --corner "$1" --temp "$2" --tag "_$1_$2"
done
for v in 2.97 3.63; do
    python3 generator/emit_char_delay.py --backend gf180mcuD \
        --corner tt --temp 27 --vdd "$v" --vddio "$v" --tag "_tt_27_v$v"
done

echo "== 2/4 synthesis"
LIB_TT="$LIBDIR/gf180mcu_fd_sc_mcu7t5v0__tt_025C_3v30.lib"
NET=reports/sta/sdram_phy_top.v
yosys -q -p "read_liberty -lib $LIB_TT; read_verilog -sv sim/pad_cell_sta_stub.sv rtl/clock_forward.sv \
rtl/dq_turnaround.sv rtl/phy_io_adapter.sv rtl/read_capture_cdc.sv \
rtl/read_capture_ctrl.sv rtl/sdr_phy.sv rtl/sdr_ctrl.sv rtl/sdram_phy_top.sv; \
synth -top sdram_phy_top -flatten; dfflibmap -liberty $LIB_TT; \
abc -liberty $LIB_TT; write_verilog -noattr $NET"
# yosys wraps the port list across lines; OpenSTA's reader needs it on one.
python3 - "$NET" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1]); s = p.read_text()
i = s.index('module sdram_phy_top(')
j = s.index(');', i)
p.write_text(s[:i] + s[i:j].replace('\n', ' ') + s[j:])
PY

echo "== 3/4 OpenSTA"
for ct in "tt gf180mcu_fd_sc_mcu7t5v0__tt_025C_3v30" \
          "ss gf180mcu_fd_sc_mcu7t5v0__ss_125C_3v00" \
          "ff gf180mcu_fd_sc_mcu7t5v0__ff_n40C_3v60"; do
    set -- $ct
    LIB="$LIBDIR/$2.lib"
    TCL=reports/sta/p1_3_$1.tcl
    cat > "$TCL" <<EOF
read_liberty $LIB
read_verilog $NET
link_design sdram_phy_top
create_clock -name clk -period 10 [get_ports clk]
set_output_delay 0 -clock clk [get_ports pad_ck]
set_output_delay 0 -clock clk [get_ports pad_cmd[*]]
set_output_delay 0 -clock clk [get_ports pad_dq[*]]
set_input_delay 0 -clock clk [get_ports pad_dq[*]]
puts "== ck_max"
report_checks -path_delay max -to [get_ports pad_ck] -digits 6
puts "== ck_min"
report_checks -path_delay min -to [get_ports pad_ck] -digits 6
puts "== cmd_max"
report_checks -path_delay max -to [get_ports pad_cmd[*]] -digits 6
puts "== cmd_min"
report_checks -path_delay min -to [get_ports pad_cmd[*]] -digits 6
puts "== dqo_max"
report_checks -path_delay max -to [get_ports pad_dq[*]] -digits 6
puts "== dqo_min"
report_checks -path_delay min -to [get_ports pad_dq[*]] -digits 6
puts "== dqi_max"
report_checks -path_delay max -from [get_ports pad_dq[*]] -digits 6
puts "== dqi_min"
report_checks -path_delay min -from [get_ports pad_dq[*]] -digits 6
exit
EOF
    sta -no_init -exit "$TCL" > "reports/sta/p1_3_$1.log" 2>&1
done
python3 generator/p1_3_margins.py
echo P1_3_TIMING_DONE
