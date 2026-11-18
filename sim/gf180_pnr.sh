#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# GF180 3.3 V harden: sdr_phy (core) and sdram_phy_top (integrated).
#
#   sh sim/gf180_pnr.sh            # core
#   sh sim/gf180_pnr.sh top        # sdram_phy_top
#
# The 3.3 V standard cells come from the gf180mcu_as_sc_mcu7t3v3 library
# (107 cells, Liberty/LEF/GDS/SPICE complete). sim/../pdks/gf180mcuD links
# the local gf180mcuD view so LibreLane's --manual-pdk path resolves.
set -e
cd "$(dirname "$0")/.."

if [ ! -d pdks/gf180mcuD/libs.ref/gf180mcu_as_sc_mcu7t3v3 ]; then
    echo "SKIP gf180_pnr: pdks/gf180mcuD/libs.ref/gf180mcu_as_sc_mcu7t3v3 missing"
    echo "  create it with: mkdir -p pdks/gf180mcuD && ln -s <gf180mcuD>/libs.{ref,tech} pdks/gf180mcuD/"
    exit 0
fi

if [ "$1" = "top" ]; then
    TOP=sdram_phy_top timeout 7200 sh flow/run.sh gf180-as-7t3v3
    python3 generator/check_pnr.py --spec gf180-as-7t3v3 --top sdram_phy_top
else
    timeout 7200 sh flow/run.sh gf180-as-7t3v3
    python3 generator/check_pnr.py --spec gf180-as-7t3v3
fi
echo GF180_PNR_DONE
