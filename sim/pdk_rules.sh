#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Verify gf180mcuD PDK rule evidence against the live local PDK and apply
# the verified subset to specs/pads/constraints.yaml.
set -e
cd "$(dirname "$0")/.."
python3 generator/extract_pdk_rules.py
python3 generator/check_device_extraction.py
python3 generator/check_layout.py
echo PDK_RULES_DONE
