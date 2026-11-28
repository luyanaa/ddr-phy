#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
set -eu
cd "$(dirname "$0")/.."

case "${1:-}" in
    ''|--ics55) ;;
    *) echo "usage: $0 [--ics55]" >&2; exit 2 ;;
esac

adpll=${ADPLL_ROOT:-/grid/adpll_gen}/src
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

iverilog -g2012 -s tb_ddr_dqs_delay_adpll -o "$work/dqs.vvp" \
    rtl/ddr1_dqs_delay_line_phys.v \
    rtl/ddr_dqs_delay_adpll.sv tb/tb_ddr_dqs_delay_adpll.sv
vvp "$work/dqs.vvp"

if [ "${1:-}" = --ics55 ]; then
    # Real cell-library elaboration (no fixture and no PVT timing inference).
    ics55=${ICS55_ROOT:-/grid/ics55}
    iverilog -g2012 -Dfunctional -s ddr_dqs_delay_adpll \
        -Pddr_dqs_delay_adpll.LANES=2 -o "$work/dqs_ics55.vvp" \
        "$ics55/libs.ref/ics55_LLSC_H7CR/verilog/ics55_LLSC_H7CR.v" \
        "$adpll/pll_cells_ics55.v" "$adpll/fine_delay.v" \
        "$adpll/pll_dcdl_tap_bus_phys.v" rtl/ddr_dqs_delay_adpll.sv
    echo DDR_DQS_DELAY_ADPLL_ICS55_ELAB_PASS
fi
