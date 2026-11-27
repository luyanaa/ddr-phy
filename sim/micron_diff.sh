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
for cl in 2 3; do
    iverilog -g2012 -I third_party/reference -DINIT_CLEAR_MEM_BANKS -DCL=$cl \
        -o sim/obj/tb_micron_diff_cl$cl \
        rtl/sdr_ctrl.sv rtl/sdr_phy.sv rtl/clock_forward.sv rtl/read_capture_ctrl.sv \
        rtl/read_capture_cdc.sv rtl/dq_turnaround.sv rtl/phy_io_adapter.sv \
        sim/pad_cell_generic.sv rtl/sdram_phy_top.sv sim/sdram_model.sv "$MODEL" \
        tb/tb_micron_diff.sv
    vvp sim/obj/tb_micron_diff_cl$cl > sim/obj/micron_diff_cl$cl.log 2>&1 || {
        cat sim/obj/micron_diff_cl$cl.log >&2
        echo "FAIL micron_diff CL$cl: simulator exit non-zero" >&2
        exit 1
    }
    if grep -q 'ERROR:' sim/obj/micron_diff_cl$cl.log; then
        grep 'ERROR:' sim/obj/micron_diff_cl$cl.log >&2
        echo "FAIL micron_diff CL$cl: Micron model reported timing errors" >&2
        exit 1
    fi
    grep -q 'PASS micron_diff' sim/obj/micron_diff_cl$cl.log
    echo "PASS micron_diff CL$cl"
done

# Model-level burst differential (bypasses the controller, which has no BL>1 path).
iverilog -g2012 -I third_party/reference -DINIT_CLEAR_MEM_BANKS \
    -o sim/obj/tb_micron_burst \
    sim/sdram_model.sv "$MODEL" tb/tb_micron_burst.sv
vvp sim/obj/tb_micron_burst > sim/obj/micron_burst.log 2>&1 || {
    cat sim/obj/micron_burst.log >&2
    echo "FAIL micron_burst: simulator exit non-zero" >&2
    exit 1
}
if grep -q 'ERROR:' sim/obj/micron_burst.log; then
    grep 'ERROR:' sim/obj/micron_burst.log >&2
    echo "FAIL micron_burst: Micron model reported timing errors" >&2
    exit 1
fi
grep -q 'PASS micron_burst' sim/obj/micron_burst.log
echo "PASS micron_burst BL2/4/8"
echo MICRON_DIFF_DONE
