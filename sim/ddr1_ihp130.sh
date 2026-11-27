#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
set -eu
cd "$(dirname "$0")/.."

# IHP130 pad-boundary DDR1 loop regression.
#
# PAD_PROFILE=tt (default): TT PEX pad delays 1300/1300/1500 ps.
# PAD_PROFILE=ss: SS PEX pad delays 1865/1615/2332 ps. The SS profile exposes
# the pad-induced write tDS loss; DQ_OE_PS can advance the DQ driver enable
# relative to DQS, and DQS_CAPTURE_DELAY_PS trims the read capture point.
python=${PYTHON:-python3}
if ! "$python" -c 'import migen, litex' 2>/dev/null; then
    echo 'Install migen==0.9.2 and litex==2024.12 in the PYTHON environment.' >&2
    exit 1
fi
export PYTHONDONTWRITEBYTECODE=1

profile=${PAD_PROFILE:-tt}
dq_oe_ps=${DQ_OE_PS:--1}
dqs_oe_ps=${DQS_OE_PS:--1}
cap_ps=${DQS_CAPTURE_DELAY_PS:-1500}
dq_tx_ps=${DQ_TX_PS:--1}
dq_rx_ps=${DQ_RX_PS:--1}
dqs_tx_ps=${DQS_TX_PS:--1}
dqs_rx_ps=${DQS_RX_PS:--1}
case "$profile" in
    tt) pad_tx=1300; pad_rx=1300; pad_oe=1500 ;;
    ss) pad_tx=1865; pad_rx=1615; pad_oe=2332 ;;
    *) echo "PAD_PROFILE must be tt or ss" >&2; exit 1 ;;
esac

fail=0
for ck in 10000 11000 12000; do
    work=$(mktemp -d)
    if ! "$python" generator/emit_ddr1.py "$work" --ck-period-ps "$ck"; then
        echo "emit_ddr1 failed at CK=$ck" >&2
        rm -rf "$work"
        exit 1
    fi
    if ! (cd "$work" && yosys -Q -q -p '
        read_verilog ddr1_controller.v
        prep -top ddr1_controller
        scc -expect 0
        check -assert
        write_verilog -noattr ddr1_controller_net.v
    '); then
        echo "yosys failed at CK=$ck" >&2
        rm -rf "$work"
        exit 1
    fi
    if ! iverilog -g2012 -I "$work" -s tb_ddr1_ihp130_loop \
        -Ptb_ddr1_ihp130_loop.PAD_TX_PS="$pad_tx" \
        -Ptb_ddr1_ihp130_loop.PAD_RX_PS="$pad_rx" \
        -Ptb_ddr1_ihp130_loop.PAD_OE_PS="$pad_oe" \
        -Ptb_ddr1_ihp130_loop.DQ_OE_PS="$dq_oe_ps" \
        -Ptb_ddr1_ihp130_loop.DQS_OE_PS="$dqs_oe_ps" \
        -Ptb_ddr1_ihp130_loop.DQS_CAPTURE_DELAY_PS="$cap_ps" \
        -Ptb_ddr1_ihp130_loop.DQ_TX_PS="$dq_tx_ps" \
        -Ptb_ddr1_ihp130_loop.DQ_RX_PS="$dq_rx_ps" \
        -Ptb_ddr1_ihp130_loop.DQS_TX_PS="$dqs_tx_ps" \
        -Ptb_ddr1_ihp130_loop.DQS_RX_PS="$dqs_rx_ps" \
        -o "$work/ddr1_pad.vvp" \
        "$work/ddr1_controller_net.v" "$work/ddr1_top.sv" "$work/ddr1_init.sv" \
        "$work/ddr1_phy.sv" "$work/ddr_edge_out.sv" "$work/ddr_read_capture.sv" \
        "$work/ddr_dqs_train.sv" rtl/ihp130_sstl2_dq_model.sv rtl/ddr1_ihp130_io.sv \
        sim/ddr1_device_model.sv sim/ddr1_timing_checker.sv tb/tb_ddr1_ihp130_loop.sv; then
        echo "iverilog failed at CK=$ck pad=$profile" >&2
        rm -rf "$work"
        exit 1
    fi
    for corner in 0 -1 1; do
        if ! vvp "$work/ddr1_pad.vvp" "+READ_CORNER=$corner" >"$work/pad.$corner.log" 2>&1; then
            echo "FAIL CK=$ck corner=$corner pad=$profile:" >&2
            cat "$work/pad.$corner.log" >&2
            fail=1
        elif ! grep -q '^DDR1_LOOP_PASS' "$work/pad.$corner.log"; then
            echo "FAIL CK=$ck corner=$corner pad=$profile (missing pass marker):" >&2
            cat "$work/pad.$corner.log" >&2
            fail=1
        else
            cat "$work/pad.$corner.log"
        fi
    done
    rm -rf "$work"
done
exit "$fail"
