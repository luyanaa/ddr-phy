#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# GF180 pad-only PCell + selected DRC decks. NOT the full pad macro and
# NOT LVS/PEX signoff.
set -e
cd "$(dirname "$0")/.."

GF=$(ls -d "$HOME"/.ciel/ciel/gf180mcu/versions/*/gf180mcuD 2>/dev/null | tail -1)
if [ -z "$GF" ] || [ ! -f "$GF/libs.tech/klayout/tech/drc/gf180mcu.drc" ]; then
    echo "SKIP gf180_pad_pcell: local gf180mcuD KLayout DRC deck not found"
    exit 0
fi

klayout -b -r generator/gf180_pad_pcell.py
mkdir -p reports
DECK="$GF/libs.tech/klayout/tech/drc/gf180mcu.drc"
ROOT=$(pwd)
GDS=sch/pads/gf180mcuD/pcell/gf180_pad_pcell.gds
run_deck() {
    d=$1
    ( cd "$GF/libs.tech/klayout/tech/drc" && \
      klayout -b -r gf180mcu.drc \
        -rd input="$ROOT/$GDS" \
        -rd report="$ROOT/reports/gf180_pad_pcell_drc_${d}.lyrdb" \
        -rd variant=gf180mcuD -rd decks="$d" -rd run_mode=flat -rd threads=1 ) \
      > "reports/gf180_pad_pcell_drc_${d}.log" 2>&1
    grep -q 'DRC RESULT: SUCCESS (0 violations)' "reports/gf180_pad_pcell_drc_${d}.log"
    echo "PASS gf180_pad_pcell DRC ${d}"
}
run_deck metal
run_deck via
run_deck geom
echo GF180_PAD_PCELL_DONE
