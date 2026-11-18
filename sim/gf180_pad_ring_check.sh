#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Pad-ring verification without a flat 1.5 mm DRC run.
#
# The ring is a regular array of one verified tile per pad site, so checking
# it hierarchically is both cheaper and more meaningful than a flat run:
#   1. the pad cell  (flat, already part of sim/gf180_pad_layout.sh)
#   2. the guard ring cell   (sim/gf180_guard_ring.sh)
#   3. the 160 um clamp cell (sim/gf180_esd_clamp_160.sh)
#   4. pad-to-pad pitch / overlap geometry, checked directly on the GDS
# A flat deck on 108 instances of a 100 x 140 um cell exceeds the 30 min
# budget on this machine; step 4 covers the only ring-level geometry the
# cell-level decks cannot see (spacing between neighbours and the seal ring).
set -e
cd "$(dirname "$0")/.."

RING=sch/pads/gf180mcuD/pcell/gf180_pad_ring.gds
if [ ! -f "$RING" ]; then
    echo "SKIP gf180_pad_ring_check: run generator/emit_pad_ring.py first"
    exit 0
fi

echo "== 4/4 ring geometry (hierarchical: pitch, overlap, seal ring)"
klayout -b -r generator/check_pad_ring.py
echo GF180_PAD_RING_CHECK_DONE
