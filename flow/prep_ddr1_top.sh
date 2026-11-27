#!/bin/sh
# Generate the CK=10 ns DDR1 bundle used by the IHP130 full-top harden.
set -eu
cd "$(dirname "$0")/.."
PYTHON=${PYTHON:-python3}
OUT=${1:-flow/runs/ddr1_top_build}
mkdir -p "$OUT"
"$PYTHON" generator/emit_ddr1.py "$OUT" --ck-period-ps 10000
