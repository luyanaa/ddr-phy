read_db /tmp/ddr1_pad_top_nonets.odb
set_routing_layers -signal Metal1-Metal4 -clock Metal1-Metal4
set_thread_count 8
detailed_route -droute_end_iter 64 -or_seed 42 -verbose 1 -output_drc flow/ihp130_chiptop_build/ddr1_pad_top_drc.rpt
write_def flow/ihp130_chiptop_build/ddr1_pad_top_routed.def
write_db flow/ihp130_chiptop_build/ddr1_pad_top_routed.odb
puts "DRT_DONE"
