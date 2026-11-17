read_liberty /home/yanlu/.ciel/ciel/gf180mcu/versions/792ef67037d74c8c51811eab3ce23cf793491296/gf180mcuD/libs.ref/gf180mcu_fd_sc_mcu7t5v0/lib/gf180mcu_fd_sc_mcu7t5v0__tt_025C_3v30.lib
read_verilog reports/sta/sdram_phy_top.v
link_design sdram_phy_top
create_clock -name clk -period 10 [get_ports clk]
set_output_delay 0 -clock clk [get_ports pad_ck]
set_output_delay 0 -clock clk [get_ports pad_cmd[*]]
set_output_delay 0 -clock clk [get_ports pad_dq[*]]
set_input_delay 0 -clock clk [get_ports pad_dq[*]]
puts "== ck_max"
report_checks -path_delay max -to [get_ports pad_ck] -digits 6
puts "== ck_min"
report_checks -path_delay min -to [get_ports pad_ck] -digits 6
puts "== cmd_max"
report_checks -path_delay max -to [get_ports pad_cmd[*]] -digits 6
puts "== cmd_min"
report_checks -path_delay min -to [get_ports pad_cmd[*]] -digits 6
puts "== dqo_max"
report_checks -path_delay max -to [get_ports pad_dq[*]] -digits 6
puts "== dqo_min"
report_checks -path_delay min -to [get_ports pad_dq[*]] -digits 6
puts "== dqi_max"
report_checks -path_delay max -from [get_ports pad_dq[*]] -digits 6
puts "== dqi_min"
report_checks -path_delay min -from [get_ports pad_dq[*]] -digits 6
exit
