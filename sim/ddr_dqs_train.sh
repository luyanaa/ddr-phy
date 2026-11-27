#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
set -eu
cd "$(dirname "$0")/.."

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM

iverilog -g2012 -s tb_ddr_dqs_train -o "$work/ddr_dqs_train.vvp" \
    rtl/ddr_dqs_train.sv tb/tb_ddr_dqs_train.sv

if command -v yosys >/dev/null 2>&1; then
    yosys -Q -q -p 'read_verilog -sv rtl/ddr_dqs_train.sv; hierarchy -check -top ddr_dqs_train; proc; check -assert'
else
    echo 'SKIP Yosys elaboration check (yosys not installed)' >&2
fi

if ! vvp "$work/ddr_dqs_train.vvp" >"$work/run.log" 2>&1; then
    cat "$work/run.log" >&2
    exit 1
fi
grep -q '^DDR_DQS_TRAIN_PASS$' "$work/run.log" || {
    cat "$work/run.log" >&2
    echo 'training testbench did not report its PASS marker' >&2
    exit 1
}
cat "$work/run.log"
