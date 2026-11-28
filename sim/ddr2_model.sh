#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
set -eu
cd "$(dirname "$0")/.."

# DDR2 pin-level device model smoke: tb_ddr2_model_smoke checks the MRS/EMR
# init decode, BL4 and BL8 write+read-back, additive latency, bank isolation,
# A10 autoprecharge, DM byte masking and a clean fault line. Recompile every
# run (stale vvp binaries have been the root cause of most debugging pain).
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
log="$work/ddr2_smoke.log"

if ! iverilog -g2012 -s tb_ddr2_model_smoke -o "$work/ddr2_smoke.vvp" \
    sim/ddr2_device_model.sv tb_ddr2_model_smoke.sv; then
    echo "iverilog failed (tb_ddr2_model_smoke)" >&2
    exit 1
fi

vvp "$work/ddr2_smoke.vvp" >"$log" 2>&1 || true
cat "$log"

if ! grep -q '^DDR2_MODEL_SMOKE_PASS' "$log" ||
   grep -q '^DDR2_MODEL_SMOKE_FAIL' "$log"; then
    echo "DDR2 model smoke failed (missing DDR2_MODEL_SMOKE_PASS)" >&2
    exit 1
fi
