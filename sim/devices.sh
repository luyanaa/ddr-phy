#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Device characterization: real ngspice terminal measurement, no mock fallback.
set -e
cd "$(dirname "$0")/.."

if ! command -v ngspice >/dev/null 2>&1; then
    echo "FAIL ngspice not on PATH; extraction cannot run" >&2
    exit 1
fi

python3 generator/extract_devices.py
python3 generator/check_device_extraction.py
echo DEVICES_DONE
