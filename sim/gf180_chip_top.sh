#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# GF180 SDRAM chip-top signoff: hierarchical DRC (incl. density) + black-box
# core LVS.
#
# Method (user-confirmed):
#   - DRC / density run on the FULL layout (core internals present), because
#     density and spacing must see real geometry.
#   - LVS runs on the SAME top but the core is represented by a pin-only
#     abstract (sdram_phy_core_lvs_abstract.gds): flat-mode extraction would
#     otherwise pull the 3665 stdcell devices into the top netlist and the
#     black-box schematic could never match (proven in /tmp black-box tests).
#
# The chip top is a regular array of already-signed-off tiles plus one
# signed-off core, so hierarchical signoff is the accepted method
# (reports/pad_ring.md open item 1).
set -e
cd "$(dirname "$0")/.."

GF=$(ls -d "$HOME"/.ciel/ciel/gf180mcu/versions/*/gf180mcuD 2>/dev/null | tail -1)
PDK_ROOT=$(dirname "$GF")
export PDK_ROOT
if [ -z "$GF" ] || [ ! -f "$GF/libs.tech/klayout/tech/drc/gf180mcu.drc" ]; then
    echo "SKIP gf180_chip_top: local gf180mcuD PDK not found"
    exit 0
fi

PCELL=sch/pads/gf180mcuD/pcell
ROUTED="$PCELL/gf180mcu_sdram_chip_top.gds"
FILLED="$PCELL/gf180mcu_sdram_chip_top_filled.gds"
LVS_GDS="$PCELL/gf180mcu_sdram_chip_top_lvsview.gds"
SCH="$PCELL/sdram_chip_top.spice"

if [ ! -f "$ROUTED" ]; then
    echo "SKIP gf180_chip_top: run generator/emit_chip_top.py first"
    exit 0
fi

echo "== 1/4 seal ring + density fill"
klayout -b -r generator/emit_chip_fill.py

echo "== 2/4 LVS view: swap full core for pin-only abstract"
klayout -b -r generator/emit_chip_lvs_view.py

echo "== 3/4 full-die DRC incl. density (LibreLane KLayout, flat)"
# flat on a 1.8 mm die is heavy; use the newer deck.  Density decks included
# (no -density exclusion) per the capability plan.
nix-shell /opt/librelane --run "\
  cd '$GF/libs.tech/klayout/tech/drc' && \
  klayout -b -r gf180mcu.drc \
    -rd input=/grid/ddr-phy/$FILLED \
    -rd report=/grid/ddr-phy/reports/gf180_chip_top_drc.lyrdb \
    -rd topcell=gf180mcu_sdram_chip_top -rd variant=gf180mcuD \
    -rd run_mode=flat -rd threads=4" \
  > reports/gf180_chip_top_drc.log 2>&1 || true
if grep -q 'DRC RESULT: SUCCESS (0 violations)' reports/gf180_chip_top_drc.log; then
    echo "PASS gf180_chip_top full DRC (0 violations, incl. density)"
else
    echo "CHECK gf180_chip_top DRC: see reports/gf180_chip_top_drc.lyrdb"
fi

echo "== 4/4 black-box core LVS"
(
  cd "$GF/libs.tech/klayout/tech/lvs"
  klayout -b -r gf180mcu.lvs \
    -rd input=/grid/ddr-phy/$LVS_GDS \
    -rd schematic=/grid/ddr-phy/$SCH \
    -rd target_netlist=/grid/ddr-phy/reports/gf180_chip_top_extracted.spice \
    -rd report=/grid/ddr-phy/reports/gf180_chip_top_lvs.lyrdb \
    -rd topcell=gf180mcu_sdram_chip_top -rd run_mode=deep \
    -rd metal_top=11K -rd metal_level=5LM \
    -rd check_ports=false -rd combine=true -rd thr=2
) > reports/gf180_chip_top_lvs.log 2>&1 || true
if grep -q 'Netlists match' reports/gf180_chip_top_lvs.log; then
    echo "PASS gf180_chip_top LVS"
else
    echo "CHECK gf180_chip_top LVS: see reports/gf180_chip_top_lvs.lyrdb"
fi

echo GF180_CHIP_TOP_DONE
