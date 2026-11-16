#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Packaging-profile closure: profile is a pluggable overlay (PDK-agnostic).
# The dimensional step uses an EXPLICITLY LABELLED synthetic fixture to demo
# the full chain; it is not a signoff result.
set -e
cd "$(dirname "$0")/.."

python3 generator/solve_packaged.py --check-profiles
python3 generator/check_packaging.py

# First closure: real packaging geometry only (partial, honest).
python3 generator/solve_packaged.py --profile wafer_space_gf180_1x1

# Full-chain demo: synthetic fixture, clearly marked, detector must find
# the cell_width_fits_pitch / rail_em conflicts.
python3 generator/solve_packaged.py --profile wafer_space_gf180_1x1 \
    --design-fixture specs/pads/packaging_profiles/wafer_space_gf180_1x1.fixture.yaml

echo PACKAGED_DONE
