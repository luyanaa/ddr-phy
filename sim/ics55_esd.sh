#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# ics55 3.3 V ESD prototype: topology only, no sizes, no signoff.
set -e
cd "$(dirname "$0")/.."
python3 generator/emit_ics55_esd.py
python3 generator/check_ics55_esd.py
echo ICS55_ESD_DONE
