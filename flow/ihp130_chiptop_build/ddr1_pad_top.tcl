# Experimental IHP130 DDR1 chip-top P&R prototype.
# Hard macros only: ddr1_top + 8 x ihp130_sstl2_dq.  No stdcell logic.
set PDK_ROOT /grid/adpll_gen/flow/canary/ihp130_sg13g2_core_a/build/pdk_root
set PDK $PDK_ROOT/ihp-sg13g2

read_lef $PDK/libs.ref/sg13g2_stdcell/lef/sg13g2_tech.lef
read_lef $PDK/libs.ref/sg13g2_stdcell/lef/sg13g2_stdcell.lef
read_lef flow/ihp130_chiptop_build/macro/sstl2_dq.lef
read_lef flow/runs/ihp130-ddr1_top/final/lef/ddr1_top.lef
read_verilog flow/ihp130_chiptop_build/ddr1_pad_top_pnr.v
link_design ddr1_pad_top_pnr
puts "LINK cells=[llength [get_cells]]"

initialize_floorplan -die_area {0 0 1050 950} -core_area {0 0 1050 950} -site CoreSite
make_tracks Metal1 -x_offset 0.28 -x_pitch 0.56 -y_offset 0.28 -y_pitch 0.56
make_tracks Metal2 -x_offset 0.28 -x_pitch 0.56 -y_offset 0.28 -y_pitch 0.56
make_tracks Metal3 -x_offset 0.28 -x_pitch 0.56 -y_offset 0.28 -y_pitch 0.56
make_tracks Metal4 -x_offset 0.28 -x_pitch 0.56 -y_offset 0.28 -y_pitch 0.56
make_tracks Metal5 -x_offset 0.45 -x_pitch 0.90 -y_offset 0.45 -y_pitch 0.90
puts "FLOORPLAN die=[ord::get_die_area]"

set block [ord::get_db_block]
proc place_macro_nm {name x_nm y_nm orient} {
  global block
  set inst [$block findInst $name]
  if {$inst eq "NULL"} { error "missing instance $name" }
  $inst setOrient $orient
  $inst setLocation $x_nm $y_nm
  $inst setPlacementStatus FIRM
  set bbox [$inst getBBox]
  puts "PLACE $name $orient x=[$bbox xMin]..[$bbox xMax] y=[$bbox yMin]..[$bbox yMax]"
}
# core in the middle, leaving 207 um pad row at bottom and 40 um top channel
place_macro_nm u_core 202200 245000 R0
for {set i 0} {$i < 8} {incr i} {
  place_macro_nm u_dq$i [expr {22300 + 125670*$i}] 0 R180
}
puts "PLACE_OK"

set_routing_layers -signal Metal1-Metal4 -clock Metal1-Metal4
set_macro_extension 2
global_route -congestion_iterations 30 -verbose
puts "GRT_DONE"
write_def flow/ihp130_chiptop_build/ddr1_pad_top_grt.def
write_db flow/ihp130_chiptop_build/ddr1_pad_top.odb
puts "DONE"
