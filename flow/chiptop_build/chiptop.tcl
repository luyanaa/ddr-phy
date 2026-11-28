# SPDX-License-Identifier: Apache-2.0
# OpenROAD chip-top macro-integration flow (generated).
set GF [lindex [glob -nocomplain /home/yanlu/.ciel/ciel/gf180mcu/versions/*/gf180mcuD] end]

# ---- LEF: tech first, then cells, then macros ----
read_lef $GF/libs.ref/gf180mcu_as_sc_mcu7t3v3/techlef/gf180mcu_as_sc_mcu7t3v3__nom.tlef
read_lef $GF/libs.ref/gf180mcu_as_sc_mcu7t3v3/lef/gf180mcu_as_sc_mcu7t3v3.lef
read_lef /grid/ddr-phy/sch/pads/gf180mcuD/pcell/gf180_pad_tile.lef
read_lef /grid/ddr-phy/flow/runs/gf180-as-7t3v3-sdram_phy_core/final/lef/sdram_phy_core.lef

# ---- netlist ----
read_verilog /grid/ddr-phy/flow/chiptop_build/sdram_chip_top_pnr.v
link_design sdram_chip_top_pnr
puts "LINK_OK"

# ---- floorplan: fixed 1800x1800 die ----
initialize_floorplan -die_area {0 0 1800 1800} -core_area {210 210 1590 1590} -site unithd
make_tracks Metal1 -x_offset 0.28 -x_pitch 0.56 -y_offset 0.28 -y_pitch 0.56
make_tracks Metal2 -x_offset 0.28 -x_pitch 0.56 -y_offset 0.28 -y_pitch 0.56
make_tracks Metal3 -x_offset 0.28 -x_pitch 0.56 -y_offset 0.28 -y_pitch 0.56
make_tracks Metal4 -x_offset 0.28 -x_pitch 0.56 -y_offset 0.28 -y_pitch 0.56
make_tracks Metal5 -x_offset 0.45 -x_pitch 0.90 -y_offset 0.45 -y_pitch 0.90
puts "FLOORPLAN_OK"

# ---- macro placement (FIRM, ring + core + inverter) ----
set block [ord::get_db_block]
set inst [$block findInst u_pad_1]
$inst setOrient R0
$inst setLocation 527000 50000
$inst setPlacementStatus FIRM
set inst [$block findInst u_pad_2]
$inst setOrient R0
$inst setLocation 907000 50000
$inst setPlacementStatus FIRM
set inst [$block findInst u_pad_3]
$inst setOrient R0
$inst setLocation 1287000 50000
$inst setPlacementStatus FIRM
set inst [$block findInst u_pad_4]
$inst setOrient R0
$inst setLocation 1667000 50000
$inst setPlacementStatus FIRM
set inst [$block findInst u_pad_5]
$inst setOrient R0
$inst setLocation 2047000 50000
$inst setPlacementStatus FIRM
set inst [$block findInst u_pad_6]
$inst setOrient R0
$inst setLocation 2427000 50000
$inst setPlacementStatus FIRM
set inst [$block findInst u_pad_7]
$inst setOrient R0
$inst setLocation 2807000 50000
$inst setPlacementStatus FIRM
set inst [$block findInst u_pad_9]
$inst setOrient R90
$inst setLocation 3180000 430320
$inst setPlacementStatus FIRM
set inst [$block findInst u_pad_10]
$inst setOrient R90
$inst setLocation 3180000 810320
$inst setPlacementStatus FIRM
set inst [$block findInst u_pad_11]
$inst setOrient R90
$inst setLocation 3180000 1190320
$inst setPlacementStatus FIRM
set inst [$block findInst u_pad_12]
$inst setOrient R90
$inst setLocation 3180000 1570320
$inst setPlacementStatus FIRM
set inst [$block findInst u_pad_13]
$inst setOrient R90
$inst setLocation 3180000 1950320
$inst setPlacementStatus FIRM
set inst [$block findInst u_pad_14]
$inst setOrient R90
$inst setLocation 3180000 2330320
$inst setPlacementStatus FIRM
set inst [$block findInst u_pad_15]
$inst setOrient R90
$inst setLocation 3180000 2710320
$inst setPlacementStatus FIRM
set inst [$block findInst u_pad_16]
$inst setOrient R180
$inst setLocation 3230000 3180000
$inst setPlacementStatus FIRM
set inst [$block findInst u_pad_17]
$inst setOrient R180
$inst setLocation 2850000 3180000
$inst setPlacementStatus FIRM
set inst [$block findInst u_pad_18]
$inst setOrient R180
$inst setLocation 2470000 3180000
$inst setPlacementStatus FIRM
set inst [$block findInst u_pad_19]
$inst setOrient R180
$inst setLocation 2090000 3180000
$inst setPlacementStatus FIRM
set inst [$block findInst u_pad_20]
$inst setOrient R180
$inst setLocation 1710000 3180000
$inst setPlacementStatus FIRM
set inst [$block findInst u_pad_21]
$inst setOrient R180
$inst setLocation 1330000 3180000
$inst setPlacementStatus FIRM
set inst [$block findInst u_pad_22]
$inst setOrient R180
$inst setLocation 950000 3180000
$inst setPlacementStatus FIRM
set inst [$block findInst u_pad_23]
$inst setOrient R180
$inst setLocation 570000 3180000
$inst setPlacementStatus FIRM
set inst [$block findInst u_pad_24]
$inst setOrient R180
$inst setLocation 190000 3180000
$inst setPlacementStatus FIRM
set inst [$block findInst u_pad_25]
$inst setOrient R270
$inst setLocation 50000 2753320
$inst setPlacementStatus FIRM
set inst [$block findInst u_pad_26]
$inst setOrient R270
$inst setLocation 50000 2373320
$inst setPlacementStatus FIRM
set inst [$block findInst u_pad_27]
$inst setOrient R270
$inst setLocation 50000 1993320
$inst setPlacementStatus FIRM
set inst [$block findInst u_pad_28]
$inst setOrient R270
$inst setLocation 50000 1613320
$inst setPlacementStatus FIRM
set inst [$block findInst u_pad_29]
$inst setOrient R270
$inst setLocation 50000 1233320
$inst setPlacementStatus FIRM
set inst [$block findInst u_pad_30]
$inst setOrient R270
$inst setLocation 50000 853320
$inst setPlacementStatus FIRM
set inst [$block findInst u_pad_31]
$inst setOrient R270
$inst setLocation 50000 473320
$inst setPlacementStatus FIRM
set cinst [$block findInst u_core]
$cinst setOrient R0
$cinst setLocation 1525970 1508050
$cinst setPlacementStatus FIRM
set iinst [$block findInst u_dqoe_inv]
$iinst setOrient R0
$iinst setLocation 2084040 1971990
$iinst setPlacementStatus FIRM
puts "PLACE_OK"


# ---- signal routing ----
set_routing_layers -signal Metal1-Metal5 -clock Metal1-Metal5
set_macro_extension 2
global_route -congestion_iterations 50 -verbose
puts "GRT_DONE"
write_def /grid/ddr-phy/flow/chiptop_build/chiptop_grt.def
set_thread_count 8
detailed_route -droute_end_iter 64 -or_seed 42 -verbose 1 -output_drc /grid/ddr-phy/flow/chiptop_build/drt.rpt
puts "DRT_DONE"
write_def /grid/ddr-phy/flow/chiptop_build/chiptop_routed.def
write_db /grid/ddr-phy/flow/chiptop_build/chiptop.odb
puts "DONE"
