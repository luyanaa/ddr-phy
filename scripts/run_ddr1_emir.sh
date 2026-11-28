#!/usr/bin/env bash
# Vectorless OpenROAD power / IR / EM baseline for the hardened ddr1_top.
# One process per PVT corner; ODB is the opt6 final database.
set -euo pipefail
ROOT=${ROOT:-/grid/ddr-phy}
PDK_ROOT=${PDK_ROOT:-/grid/adpll_gen/flow/canary/ihp130_sg13g2_core_a/build/pdk_root}
PDK=$PDK_ROOT/ihp-sg13g2
OPENROAD=${OPENROAD:-/nix/store/6qbn5zjnnnyna6md4rsmiqw4y26y8556-openroad-26Q3/bin/openroad}
ODB=$ROOT/flow/runs/ihp130-ddr1_top/final/odb/ddr1_top.odb
OUT=$ROOT/reports/ddr1/emir
mkdir -p "$OUT"

run_corner () {
  local tag=$1 lib=$2 volt=$3
  $OPENROAD -no_init -exit <<EOF >"$OUT/power_ir_em_${tag}.log" 2>&1
read_db $ODB
read_liberty $PDK/libs.ref/sg13g2_stdcell/lib/${lib}
link_design -hier ddr1_top
report_power > $OUT/power_${tag}.rpt
report_power -highest_power_instances 15 > $OUT/power_instances_${tag}.rpt
set_pdnsim_net_voltage -net VPWR -voltage $volt
set_pdnsim_net_voltage -net VGND -voltage 0.0
analyze_power_grid -net VPWR -source_type FULL -enable_em -em_outfile $OUT/em_vpwr_${tag}.rpt -error_file $OUT/ir_vpwr_${tag}.rpt
analyze_power_grid -net VGND -source_type FULL -error_file $OUT/ir_vgnd_${tag}.rpt
EOF
}

run_corner typ sg13g2_stdcell_typ_1p20V_25C.lib 1.20
run_corner slow sg13g2_stdcell_slow_1p08V_125C.lib 1.08
run_corner fast sg13g2_stdcell_fast_1p32V_m40C.lib 1.32
echo "done -> $OUT"
