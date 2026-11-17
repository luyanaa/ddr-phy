#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Guard-ring cell: generate + full DRC (KLayout 0.30.7).
set -e
cd "$(dirname "$0")/.."

GF=$(ls -d "$HOME"/.ciel/ciel/gf180mcu/versions/*/gf180mcuD 2>/dev/null | tail -1)
if [ -z "$GF" ]; then echo "SKIP gf180_guard_ring: PDK not found"; exit 0; fi

klayout -b -r generator/emit_guard_ring.py
nix-shell /opt/librelane --run "\
  cd '$GF/libs.tech/klayout/tech/drc' && \
  klayout -b -r gf180mcu.drc \
    -rd input=/grid/ddr-phy/sch/pads/gf180mcuD/pcell/gf180_guard_ring.gds \
    -rd report=/grid/ddr-phy/reports/gf180_guard_ring_drc.lyrdb \
    -rd topcell=gf180_guard_ring -rd variant=gf180mcuD \
    -rd run_mode=flat -rd threads=4" \
  > reports/gf180_guard_ring_drc.log 2>&1
grep -q 'DRC RESULT: SUCCESS (0 violations)' reports/gf180_guard_ring_drc.log
echo "PASS gf180_guard_ring full DRC (0 violations)"
echo GF180_GUARD_RING_DONE
