#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Cross-check the clean-room DDR2 x8 device model against the GPL
# OpenSPARC T2 dimm_iverilog golden model. The GPL source is compiled
# directly out of the submodule; it is never copied into this repo.
set -eu
cd "$(dirname "$0")/.."

GOLD=third_party/t2_ddr2/model_verilog/mem/dram/dimm_iverilog.v
if [ ! -f "$GOLD" ]; then
    echo "SKIP ddr2_xcheck: $GOLD not present (git submodule update --init)" >&2
    exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM

iverilog -g2012 -DX4 -s tb_ddr2_gpl_xcheck -o "$work/ddr2_xcheck.vvp" \
    tb_ddr2_gpl_xcheck.sv sim/ddr2_device_model.sv "$GOLD"

if ! vvp "$work/ddr2_xcheck.vvp" >"$work/run.log" 2>&1; then
    cat "$work/run.log" >&2
    echo "FAIL ddr2_xcheck: simulator exit non-zero" >&2
    exit 1
fi

grep -q XCHECK_PASS "$work/run.log" || {
    cat "$work/run.log" >&2
    echo "FAIL ddr2_xcheck: testbench did not report XCHECK_PASS" >&2
    exit 1
}
cat "$work/run.log"
echo "PASS ddr2_xcheck"
