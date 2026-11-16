#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# OPTIONAL Micron SDR reference-model differential test.
# The model is Micron -7E, not the project -75 contract; a pass is
# behavioural evidence only. The model is gitignored and may be absent.
set -e
cd "$(dirname "$0")/.."

MODEL=third_party/reference/mt48lc16m16a2.v
if [ ! -f "$MODEL" ]; then
    echo "SKIP micron_diff: $MODEL not present (fetch with docs/DRAM_MODEL_REFERENCES.md)"
    exit 0
fi

mkdir -p sim/obj
iverilog -g2012 -I third_party/reference -DINIT_CLEAR_MEM_BANKS \
    -o sim/obj/tb_micron_diff \
    rtl/sdr_ctrl.sv rtl/sdr_phy.sv sim/sdram_model.sv "$MODEL" \
    tb/tb_micron_diff.sv
vvp sim/obj/tb_micron_diff > sim/obj/micron_diff.log 2>&1 || {
    cat sim/obj/micron_diff.log >&2
    echo "FAIL micron_diff: simulator exit non-zero" >&2
    exit 1
}
if grep -q 'ERROR:' sim/obj/micron_diff.log; then
    grep 'ERROR:' sim/obj/micron_diff.log >&2
    echo "FAIL micron_diff: Micron model reported timing errors" >&2
    exit 1
fi
grep -q 'PASS micron_diff' sim/obj/micron_diff.log
echo "PASS micron_diff: own model and Micron -7E agree on the tested trace"
echo MICRON_DIFF_DONE
