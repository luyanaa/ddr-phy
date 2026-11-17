#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Standalone ggNMOS ESD clamp: generate + full DRC + LVS.
set -e
cd "$(dirname "$0")/.."

GF=$(ls -d "$HOME"/.ciel/ciel/gf180mcu/versions/*/gf180mcuD 2>/dev/null | tail -1)
if [ -z "$GF" ]; then echo "SKIP gf180_esd_clamp: PDK not found"; exit 0; fi

klayout -b -r generator/emit_esd_clamp.py

nix-shell /opt/librelane --run "\
  cd '$GF/libs.tech/klayout/tech/drc' && \
  klayout -b -r gf180mcu.drc \
    -rd input=/grid/ddr-phy/sch/pads/gf180mcuD/pcell/gf180_esd_clamp.gds \
    -rd report=/grid/ddr-phy/reports/gf180_esd_clamp_drc.lyrdb \
    -rd topcell=gf180_esd_clamp -rd variant=gf180mcuD \
    -rd run_mode=flat -rd threads=4" \
  > reports/gf180_esd_clamp_drc.log 2>&1
# The only allowed violations are the die-level density rules: a clamp cell
# is instanced inside a die that carries the fill.
n=$(grep -oE "DRC RESULT: FAILURE \(([0-9]+) violation" reports/gf180_esd_clamp_drc.log | grep -oE '[0-9]+' || echo 0)
bad=$(grep -E "^.*:   '" reports/gf180_esd_clamp_drc.log | grep -vE "DCF\.1b|PL\.8|M[0-9]\.4|MT\.3" | wc -l)
if [ "$bad" -ne 0 ]; then
    echo "FAIL gf180_esd_clamp DRC ($bad non-density rule groups)"
    grep -E "^.*:   '" reports/gf180_esd_clamp_drc.log | head -10
    exit 1
fi
echo "PASS gf180_esd_clamp DRC (geometry clean; $n die-level density only)"

cat > /tmp/clamp_sch.spice <<'SP'
.SUBCKT gf180_esd_clamp PAD VSSIO
MCLAMP PAD VSSIO VSSIO VSSIO nfet_03v3 W=80u L=0.28u
.ENDS
SP
( cd "$GF/libs.tech/klayout/tech/lvs" && \
  klayout -b -r gf180mcu.lvs \
    -rd input=/grid/ddr-phy/sch/pads/gf180mcuD/pcell/gf180_esd_clamp.gds \
    -rd schematic=/tmp/clamp_sch.spice \
    -rd target_netlist=/grid/ddr-phy/reports/gf180_esd_clamp_extracted.spice \
    -rd report=/grid/ddr-phy/reports/gf180_esd_clamp_lvs.lyrdb \
    -rd topcell=gf180_esd_clamp -rd run_mode=flat -rd metal_top=11K \
    -rd metal_level=5LM -rd check_ports=false -rd combine=true -rd thr=2 \
    > /grid/ddr-phy/reports/gf180_esd_clamp_lvs.log 2>&1 )
grep -q 'Netlists match' reports/gf180_esd_clamp_lvs.log
echo "PASS gf180_esd_clamp LVS (Netlists match)"
echo GF180_ESD_CLAMP_DONE
