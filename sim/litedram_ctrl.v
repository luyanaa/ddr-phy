/* Machine-generated using Migen */
module litedram_ctrl(
	input sys_clk,
	input sys_rst,
	input interface_bank0_valid,
	output interface_bank0_ready,
	input interface_bank0_we,
	input [21:0] interface_bank0_addr,
	output interface_bank0_lock,
	output interface_bank0_wdata_ready,
	output interface_bank0_rdata_valid,
	input [7:0] interface_wdata,
	input interface_wdata_we,
	output [7:0] interface_rdata,
	output [12:0] dfi_p0_address,
	output [1:0] dfi_p0_bank,
	output reg dfi_p0_cas_n,
	output reg dfi_p0_cs_n,
	output reg dfi_p0_ras_n,
	output reg dfi_p0_we_n,
	output dfi_p0_cke,
	output dfi_p0_odt,
	output dfi_p0_reset_n,
	input dfi_p0_act_n,
	output [7:0] dfi_p0_wrdata,
	output reg dfi_p0_wrdata_en,
	output dfi_p0_wrdata_mask,
	output reg dfi_p0_rddata_en,
	input [7:0] dfi_p0_rddata,
	input dfi_p0_rddata_valid
);

reg interface_bank1_valid = 1'd0;
wire interface_bank1_ready;
reg interface_bank1_we = 1'd0;
reg [21:0] interface_bank1_addr = 22'd0;
wire interface_bank1_lock;
wire interface_bank1_wdata_ready;
wire interface_bank1_rdata_valid;
reg interface_bank2_valid = 1'd0;
wire interface_bank2_ready;
reg interface_bank2_we = 1'd0;
reg [21:0] interface_bank2_addr = 22'd0;
wire interface_bank2_lock;
wire interface_bank2_wdata_ready;
wire interface_bank2_rdata_valid;
reg interface_bank3_valid = 1'd0;
wire interface_bank3_ready;
reg interface_bank3_we = 1'd0;
reg [21:0] interface_bank3_addr = 22'd0;
wire interface_bank3_lock;
wire interface_bank3_wdata_ready;
wire interface_bank3_rdata_valid;
reg refresher_cmd_valid;
reg refresher_cmd_ready;
reg refresher_cmd_last;
reg [12:0] refresher_cmd_payload_a = 13'd0;
reg [1:0] refresher_cmd_payload_ba = 2'd0;
reg refresher_cmd_payload_cas = 1'd0;
reg refresher_cmd_payload_ras = 1'd0;
reg refresher_cmd_payload_we = 1'd0;
reg refresher_cmd_payload_is_read = 1'd0;
reg refresher_cmd_payload_is_write = 1'd0;
wire refresher_wants_refresh;
reg refresher_wants_zqcs = 1'd0;
wire refresher_timer_wait;
wire refresher_timer_done0;
wire [9:0] refresher_timer_count0;
wire refresher_timer_done1;
reg [9:0] refresher_timer_count1 = 10'd779;
wire refresher_postponer_req_i;
reg refresher_postponer_req_o = 1'd0;
reg refresher_postponer_count = 1'd0;
reg refresher_sequencer_start0;
wire refresher_sequencer_done0;
wire refresher_sequencer_start1;
reg refresher_sequencer_done1 = 1'd0;
reg [3:0] refresher_sequencer_trigger = 4'd0;
reg refresher_sequencer_count = 1'd0;
wire refresher_zqcs_timer_wait;
wire refresher_zqcs_timer_done0;
wire [26:0] refresher_zqcs_timer_count0;
wire refresher_zqcs_timer_done1;
reg [26:0] refresher_zqcs_timer_count1 = 27'd99999999;
reg refresher_zqcs_executer_start;
reg refresher_zqcs_executer_done = 1'd0;
reg [6:0] refresher_zqcs_executer_trigger = 7'd0;
wire bank_machine_req_valid;
wire bank_machine_req_ready;
wire bank_machine_req_we;
wire [21:0] bank_machine_req_addr;
wire bank_machine_req_lock;
reg bank_machine_req_wdata_ready;
reg bank_machine_req_rdata_valid;
wire bank_machine_record0_valid;
wire bank_machine_record0_ready;
wire bank_machine_record0_we;
wire [21:0] bank_machine_record0_addr;
wire bank_machine_record0_lock;
wire bank_machine_record0_wdata_ready;
wire bank_machine_record0_rdata_valid;
wire bank_machine_record1_valid;
wire bank_machine_record1_ready;
wire bank_machine_record1_we;
wire [21:0] bank_machine_record1_addr;
wire bank_machine_record1_lock;
wire bank_machine_record1_wdata_ready;
wire bank_machine_record1_rdata_valid;
wire bank_machine_record2_valid;
wire bank_machine_record2_ready;
wire bank_machine_record2_we;
wire [21:0] bank_machine_record2_addr;
wire bank_machine_record2_lock;
wire bank_machine_record2_wdata_ready;
wire bank_machine_record2_rdata_valid;
wire bank_machine_record3_valid;
wire bank_machine_record3_ready;
wire bank_machine_record3_we;
wire [21:0] bank_machine_record3_addr;
wire bank_machine_record3_lock;
wire bank_machine_record3_wdata_ready;
wire bank_machine_record3_rdata_valid;
wire bank_machine_refresh_req;
reg bank_machine_refresh_gnt;
reg bank_machine_cmd_valid;
reg bank_machine_cmd_ready;
reg [12:0] bank_machine_cmd_payload_a;
wire [1:0] bank_machine_cmd_payload_ba;
reg bank_machine_cmd_payload_cas;
reg bank_machine_cmd_payload_ras;
reg bank_machine_cmd_payload_we;
reg bank_machine_cmd_payload_is_cmd;
reg bank_machine_cmd_payload_is_read;
reg bank_machine_cmd_payload_is_write;
reg bank_machine_auto_precharge = 1'd0;
wire bank_machine_sink_valid;
wire bank_machine_sink_ready;
reg bank_machine_sink_first = 1'd0;
reg bank_machine_sink_last = 1'd0;
wire bank_machine_sink_payload_we;
wire [21:0] bank_machine_sink_payload_addr;
wire [1:0] bank_machine_sink_payload_bank;
wire bank_machine_source_valid;
wire bank_machine_source_ready;
wire bank_machine_source_first;
wire bank_machine_source_last;
wire bank_machine_source_payload_we;
wire [21:0] bank_machine_source_payload_addr;
wire [1:0] bank_machine_source_payload_bank;
wire bank_machine_re;
reg bank_machine_readable = 1'd0;
wire bank_machine_syncfifo_we;
wire bank_machine_syncfifo_writable;
wire bank_machine_syncfifo_re;
wire bank_machine_syncfifo_readable;
wire [26:0] bank_machine_syncfifo_din;
wire [26:0] bank_machine_syncfifo_dout;
reg [3:0] bank_machine_level0 = 4'd0;
reg bank_machine_replace = 1'd0;
reg [2:0] bank_machine_produce = 3'd0;
reg [2:0] bank_machine_consume = 3'd0;
reg [2:0] bank_machine_wrport_adr;
wire [26:0] bank_machine_wrport_dat_r;
wire bank_machine_wrport_we;
wire [26:0] bank_machine_wrport_dat_w;
wire bank_machine_do_read;
wire [2:0] bank_machine_rdport_adr;
wire [26:0] bank_machine_rdport_dat_r;
wire bank_machine_rdport_re;
wire [3:0] bank_machine_level1;
wire bank_machine_fifo_in_payload_we;
wire [21:0] bank_machine_fifo_in_payload_addr;
wire [1:0] bank_machine_fifo_in_payload_bank;
wire bank_machine_fifo_in_first;
wire bank_machine_fifo_in_last;
wire bank_machine_fifo_out_payload_we;
wire [21:0] bank_machine_fifo_out_payload_addr;
wire [1:0] bank_machine_fifo_out_payload_bank;
wire bank_machine_fifo_out_first;
wire bank_machine_fifo_out_last;
wire bank_machine_sink_sink_valid;
wire bank_machine_sink_sink_ready;
wire bank_machine_sink_sink_first;
wire bank_machine_sink_sink_last;
wire bank_machine_sink_sink_payload_we;
wire [21:0] bank_machine_sink_sink_payload_addr;
wire [1:0] bank_machine_sink_sink_payload_bank;
wire bank_machine_source_source_valid;
wire bank_machine_source_source_ready;
wire bank_machine_source_source_first;
wire bank_machine_source_source_last;
wire bank_machine_source_source_payload_we;
wire [21:0] bank_machine_source_source_payload_addr;
wire [1:0] bank_machine_source_source_payload_bank;
wire bank_machine_pipe_valid_sink_valid;
wire bank_machine_pipe_valid_sink_ready;
wire bank_machine_pipe_valid_sink_first;
wire bank_machine_pipe_valid_sink_last;
wire bank_machine_pipe_valid_sink_payload_we;
wire [21:0] bank_machine_pipe_valid_sink_payload_addr;
wire [1:0] bank_machine_pipe_valid_sink_payload_bank;
reg bank_machine_pipe_valid_source_valid = 1'd0;
wire bank_machine_pipe_valid_source_ready;
reg bank_machine_pipe_valid_source_first = 1'd0;
reg bank_machine_pipe_valid_source_last = 1'd0;
reg bank_machine_pipe_valid_source_payload_we = 1'd0;
reg [21:0] bank_machine_pipe_valid_source_payload_addr = 22'd0;
reg [1:0] bank_machine_pipe_valid_source_payload_bank = 2'd0;
wire [3:0] bank_machine_request;
reg [1:0] bank_machine_grant = 2'd0;
wire bank_machine_ce;
reg [6:0] bank_machine_run = 7'd0;
wire bank_machine_run_end;
reg [3:0] bank_machine_pending0 = 4'd0;
wire bank_machine_push0;
wire bank_machine_pop0;
reg [3:0] bank_machine_pending1 = 4'd0;
wire bank_machine_push1;
wire bank_machine_pop1;
reg [3:0] bank_machine_pending2 = 4'd0;
wire bank_machine_push2;
wire bank_machine_pop2;
reg [3:0] bank_machine_pending3 = 4'd0;
wire bank_machine_push3;
wire bank_machine_pop3;
reg [12:0] bank_machine_row = 13'd0;
reg bank_machine_row_opened = 1'd0;
wire bank_machine_row_hit;
reg bank_machine_row_open;
reg bank_machine_row_close;
reg [1:0] bank_machine_row_bank = 2'd0;
reg bank_machine_row_col_n_addr_sel;
wire bank_machine_twtpcon_valid;
(* no_retiming = "true" *) reg bank_machine_twtpcon_ready = 1'd0;
reg [2:0] bank_machine_twtpcon_count = 3'd0;
wire bank_machine_trccon_valid;
(* no_retiming = "true" *) reg bank_machine_trccon_ready = 1'd0;
reg [2:0] bank_machine_trccon_count = 3'd0;
wire bank_machine_trascon_valid;
(* no_retiming = "true" *) reg bank_machine_trascon_ready = 1'd0;
reg [2:0] bank_machine_trascon_count = 3'd0;
wire bank_machine_trtpcon_valid;
(* no_retiming = "true" *) reg bank_machine_trtpcon_ready = 1'd1;
wire ras_allowed;
wire cas_allowed;
reg choose_cmd_want_reads = 1'd0;
reg choose_cmd_want_writes = 1'd0;
reg choose_cmd_want_cmds = 1'd0;
reg choose_cmd_want_activates = 1'd0;
wire choose_cmd_cmd_valid;
reg choose_cmd_cmd_ready = 1'd0;
wire [12:0] choose_cmd_cmd_payload_a;
wire [1:0] choose_cmd_cmd_payload_ba;
reg choose_cmd_cmd_payload_cas;
reg choose_cmd_cmd_payload_ras;
reg choose_cmd_cmd_payload_we;
wire choose_cmd_cmd_payload_is_cmd;
wire choose_cmd_cmd_payload_is_read;
wire choose_cmd_cmd_payload_is_write;
wire choose_cmd_valids;
wire choose_cmd_request;
wire choose_cmd_grant;
wire choose_cmd_ce;
reg choose_req_want_reads;
reg choose_req_want_writes;
reg choose_req_want_cmds;
reg choose_req_want_activates;
wire choose_req_cmd_valid;
reg choose_req_cmd_ready;
wire [12:0] choose_req_cmd_payload_a;
wire [1:0] choose_req_cmd_payload_ba;
reg choose_req_cmd_payload_cas;
reg choose_req_cmd_payload_ras;
reg choose_req_cmd_payload_we;
wire choose_req_cmd_payload_is_cmd;
wire choose_req_cmd_payload_is_read;
wire choose_req_cmd_payload_is_write;
wire choose_req_valids;
wire choose_req_request;
wire choose_req_grant;
wire choose_req_ce;
reg [12:0] nop_a = 13'd0;
reg [1:0] nop_ba = 2'd0;
reg [1:0] steerer0;
reg steerer1 = 1'd1;
reg steerer2 = 1'd1;
reg [1:0] steerer_bank = 2'd0;
reg [12:0] steerer_address = 13'd0;
wire trrdcon_valid;
(* no_retiming = "true" *) reg trrdcon_ready = 1'd0;
reg trrdcon_count = 1'd0;
wire tfawcon_valid;
(* no_retiming = "true" *) reg tfawcon_ready = 1'd1;
wire tccdcon_valid;
(* no_retiming = "true" *) reg tccdcon_ready = 1'd0;
reg tccdcon_count = 1'd0;
wire twtrcon_valid;
(* no_retiming = "true" *) reg twtrcon_ready = 1'd0;
reg [1:0] twtrcon_count = 2'd0;
wire read_available;
wire write_available;
reg en0;
wire max_time0;
reg [5:0] time0 = 6'd0;
reg en1;
wire max_time1;
reg [4:0] time1 = 5'd0;
wire go_to_refresh;
reg [1:0] refresher_state = 2'd0;
reg [1:0] refresher_next_state;
reg [2:0] bankmachine_state = 3'd0;
reg [2:0] bankmachine_next_state;
reg [3:0] multiplexer_state = 4'd0;
reg [3:0] multiplexer_next_state;
reg rhs_self0;
reg rhs_self1;
reg [21:0] rhs_self2;
reg rhs_self3;
reg [12:0] rhs_self4;
reg [1:0] rhs_self5;
reg rhs_self6;
reg rhs_self7;
reg rhs_self8;
reg t_self0;
reg t_self1;
reg t_self2;
reg rhs_self9;
reg [12:0] rhs_self10;
reg [1:0] rhs_self11;
reg rhs_self12;
reg rhs_self13;
reg rhs_self14;
reg t_self3;
reg t_self4;
reg t_self5;
reg [1:0] self0;
reg [12:0] self1;
reg self2;
reg self3;
reg self4;
reg self5;
reg self6;

// synthesis translate_off
reg dummy_s;
initial dummy_s <= 1'd0;
// synthesis translate_on

assign bank_machine_record0_valid = interface_bank0_valid;
assign interface_bank0_ready = bank_machine_record0_ready;
assign bank_machine_record0_we = interface_bank0_we;
assign bank_machine_record0_addr = interface_bank0_addr;
assign interface_bank0_lock = bank_machine_record0_lock;
assign interface_bank0_wdata_ready = bank_machine_record0_wdata_ready;
assign interface_bank0_rdata_valid = bank_machine_record0_rdata_valid;
assign bank_machine_record1_valid = interface_bank1_valid;
assign interface_bank1_ready = bank_machine_record1_ready;
assign bank_machine_record1_we = interface_bank1_we;
assign bank_machine_record1_addr = interface_bank1_addr;
assign interface_bank1_lock = bank_machine_record1_lock;
assign interface_bank1_wdata_ready = bank_machine_record1_wdata_ready;
assign interface_bank1_rdata_valid = bank_machine_record1_rdata_valid;
assign bank_machine_record2_valid = interface_bank2_valid;
assign interface_bank2_ready = bank_machine_record2_ready;
assign bank_machine_record2_we = interface_bank2_we;
assign bank_machine_record2_addr = interface_bank2_addr;
assign interface_bank2_lock = bank_machine_record2_lock;
assign interface_bank2_wdata_ready = bank_machine_record2_wdata_ready;
assign interface_bank2_rdata_valid = bank_machine_record2_rdata_valid;
assign bank_machine_record3_valid = interface_bank3_valid;
assign interface_bank3_ready = bank_machine_record3_ready;
assign bank_machine_record3_we = interface_bank3_we;
assign bank_machine_record3_addr = interface_bank3_addr;
assign interface_bank3_lock = bank_machine_record3_lock;
assign interface_bank3_wdata_ready = bank_machine_record3_wdata_ready;
assign interface_bank3_rdata_valid = bank_machine_record3_rdata_valid;
assign refresher_timer_wait = (~refresher_timer_done0);
assign refresher_postponer_req_i = refresher_timer_done0;
assign refresher_wants_refresh = refresher_postponer_req_o;
assign refresher_zqcs_timer_wait = (~refresher_zqcs_executer_done);
assign refresher_timer_done1 = (refresher_timer_count1 == 1'd0);
assign refresher_timer_done0 = refresher_timer_done1;
assign refresher_timer_count0 = refresher_timer_count1;
assign refresher_sequencer_start1 = (refresher_sequencer_start0 | (refresher_sequencer_count != 1'd0));
assign refresher_sequencer_done0 = (refresher_sequencer_done1 & (refresher_sequencer_count == 1'd0));
assign refresher_zqcs_timer_done1 = (refresher_zqcs_timer_count1 == 1'd0);
assign refresher_zqcs_timer_done0 = refresher_zqcs_timer_done1;
assign refresher_zqcs_timer_count0 = refresher_zqcs_timer_count1;

// synthesis translate_off
reg dummy_d;
// synthesis translate_on
always @(*) begin
	refresher_cmd_valid <= 1'd0;
	refresher_cmd_last <= 1'd0;
	refresher_sequencer_start0 <= 1'd0;
	refresher_zqcs_executer_start <= 1'd0;
	refresher_next_state <= 2'd0;
	refresher_next_state <= refresher_state;
	case (refresher_state)
		1'd1: begin
			refresher_cmd_valid <= 1'd1;
			if (refresher_cmd_ready) begin
				refresher_sequencer_start0 <= 1'd1;
				refresher_next_state <= 2'd2;
			end
		end
		2'd2: begin
			refresher_cmd_valid <= 1'd1;
			if (refresher_sequencer_done0) begin
				if (refresher_wants_zqcs) begin
					refresher_zqcs_executer_start <= 1'd1;
					refresher_next_state <= 2'd3;
				end else begin
					refresher_cmd_valid <= 1'd0;
					refresher_cmd_last <= 1'd1;
					refresher_next_state <= 1'd0;
				end
			end
		end
		2'd3: begin
			refresher_cmd_valid <= 1'd1;
			if (refresher_zqcs_executer_done) begin
				refresher_cmd_valid <= 1'd0;
				refresher_cmd_last <= 1'd1;
				refresher_next_state <= 1'd0;
			end
		end
		default: begin
			if (1'd0) begin
				if (refresher_wants_refresh) begin
					refresher_next_state <= 1'd1;
				end
			end
		end
	endcase
// synthesis translate_off
	dummy_d <= dummy_s;
// synthesis translate_on
end
assign bank_machine_sink_valid = bank_machine_req_valid;
assign bank_machine_req_ready = bank_machine_sink_ready;
assign bank_machine_sink_payload_we = bank_machine_req_we;
assign bank_machine_sink_payload_addr = bank_machine_req_addr;
assign bank_machine_sink_sink_valid = bank_machine_source_valid;
assign bank_machine_source_ready = bank_machine_sink_sink_ready;
assign bank_machine_sink_sink_first = bank_machine_source_first;
assign bank_machine_sink_sink_last = bank_machine_source_last;
assign bank_machine_sink_sink_payload_we = bank_machine_source_payload_we;
assign bank_machine_sink_sink_payload_addr = bank_machine_source_payload_addr;
assign bank_machine_sink_sink_payload_bank = bank_machine_source_payload_bank;
assign bank_machine_source_source_ready = (bank_machine_req_wdata_ready | bank_machine_req_rdata_valid);
assign bank_machine_req_lock = (bank_machine_source_valid | bank_machine_source_source_valid);
assign bank_machine_run_end = ((bank_machine_req_valid & bank_machine_req_ready) & (bank_machine_run == 6'd63));
assign bank_machine_request = {bank_machine_record3_valid, bank_machine_record2_valid, bank_machine_record1_valid, bank_machine_record0_valid};
assign bank_machine_ce = ((~bank_machine_req_valid) | bank_machine_run_end);
assign bank_machine_req_valid = rhs_self0;
assign bank_machine_req_we = rhs_self1;
assign bank_machine_req_addr = rhs_self2;
assign bank_machine_sink_payload_bank = bank_machine_grant;
assign bank_machine_record0_ready = (bank_machine_req_ready & (bank_machine_grant == 1'd0));
assign bank_machine_record0_wdata_ready = (bank_machine_req_wdata_ready & (bank_machine_source_source_payload_bank == 1'd0));
assign bank_machine_record0_rdata_valid = (bank_machine_req_rdata_valid & (bank_machine_source_source_payload_bank == 1'd0));
assign bank_machine_push0 = (bank_machine_record0_valid & bank_machine_record0_ready);
assign bank_machine_pop0 = ((bank_machine_req_wdata_ready | bank_machine_req_rdata_valid) & (bank_machine_source_source_payload_bank == 1'd0));
assign bank_machine_record0_lock = (bank_machine_pending0 != 1'd0);
assign bank_machine_record1_ready = (bank_machine_req_ready & (bank_machine_grant == 1'd1));
assign bank_machine_record1_wdata_ready = (bank_machine_req_wdata_ready & (bank_machine_source_source_payload_bank == 1'd1));
assign bank_machine_record1_rdata_valid = (bank_machine_req_rdata_valid & (bank_machine_source_source_payload_bank == 1'd1));
assign bank_machine_push1 = (bank_machine_record1_valid & bank_machine_record1_ready);
assign bank_machine_pop1 = ((bank_machine_req_wdata_ready | bank_machine_req_rdata_valid) & (bank_machine_source_source_payload_bank == 1'd1));
assign bank_machine_record1_lock = (bank_machine_pending1 != 1'd0);
assign bank_machine_record2_ready = (bank_machine_req_ready & (bank_machine_grant == 2'd2));
assign bank_machine_record2_wdata_ready = (bank_machine_req_wdata_ready & (bank_machine_source_source_payload_bank == 2'd2));
assign bank_machine_record2_rdata_valid = (bank_machine_req_rdata_valid & (bank_machine_source_source_payload_bank == 2'd2));
assign bank_machine_push2 = (bank_machine_record2_valid & bank_machine_record2_ready);
assign bank_machine_pop2 = ((bank_machine_req_wdata_ready | bank_machine_req_rdata_valid) & (bank_machine_source_source_payload_bank == 2'd2));
assign bank_machine_record2_lock = (bank_machine_pending2 != 1'd0);
assign bank_machine_record3_ready = (bank_machine_req_ready & (bank_machine_grant == 2'd3));
assign bank_machine_record3_wdata_ready = (bank_machine_req_wdata_ready & (bank_machine_source_source_payload_bank == 2'd3));
assign bank_machine_record3_rdata_valid = (bank_machine_req_rdata_valid & (bank_machine_source_source_payload_bank == 2'd3));
assign bank_machine_push3 = (bank_machine_record3_valid & bank_machine_record3_ready);
assign bank_machine_pop3 = ((bank_machine_req_wdata_ready | bank_machine_req_rdata_valid) & (bank_machine_source_source_payload_bank == 2'd3));
assign bank_machine_record3_lock = (bank_machine_pending3 != 1'd0);
assign bank_machine_row_hit = ((bank_machine_row == bank_machine_source_source_payload_addr[21:9]) & (bank_machine_row_bank == bank_machine_source_source_payload_bank));
assign bank_machine_cmd_payload_ba = (1'd0 + (bank_machine_row_col_n_addr_sel ? bank_machine_source_source_payload_bank : bank_machine_row_bank));

// synthesis translate_off
reg dummy_d_1;
// synthesis translate_on
always @(*) begin
	bank_machine_cmd_payload_a <= 13'd0;
	if (bank_machine_row_col_n_addr_sel) begin
		bank_machine_cmd_payload_a <= bank_machine_source_source_payload_addr[21:9];
	end else begin
		bank_machine_cmd_payload_a <= ((bank_machine_auto_precharge <<< 4'd10) | {bank_machine_source_source_payload_addr[8:0], {0{1'd0}}});
	end
// synthesis translate_off
	dummy_d_1 <= dummy_s;
// synthesis translate_on
end
assign bank_machine_twtpcon_valid = ((bank_machine_cmd_valid & bank_machine_cmd_ready) & bank_machine_cmd_payload_is_write);
assign bank_machine_trccon_valid = ((bank_machine_cmd_valid & bank_machine_cmd_ready) & bank_machine_row_open);
assign bank_machine_trascon_valid = ((bank_machine_cmd_valid & bank_machine_cmd_ready) & bank_machine_row_open);
assign bank_machine_trtpcon_valid = ((bank_machine_cmd_valid & bank_machine_cmd_ready) & bank_machine_cmd_payload_is_read);
assign bank_machine_syncfifo_din = {bank_machine_fifo_in_last, bank_machine_fifo_in_first, bank_machine_fifo_in_payload_bank, bank_machine_fifo_in_payload_addr, bank_machine_fifo_in_payload_we};
assign {bank_machine_fifo_out_last, bank_machine_fifo_out_first, bank_machine_fifo_out_payload_bank, bank_machine_fifo_out_payload_addr, bank_machine_fifo_out_payload_we} = bank_machine_syncfifo_dout;
assign bank_machine_sink_ready = bank_machine_syncfifo_writable;
assign bank_machine_syncfifo_we = bank_machine_sink_valid;
assign bank_machine_fifo_in_first = bank_machine_sink_first;
assign bank_machine_fifo_in_last = bank_machine_sink_last;
assign bank_machine_fifo_in_payload_we = bank_machine_sink_payload_we;
assign bank_machine_fifo_in_payload_addr = bank_machine_sink_payload_addr;
assign bank_machine_fifo_in_payload_bank = bank_machine_sink_payload_bank;
assign bank_machine_source_valid = bank_machine_readable;
assign bank_machine_source_first = bank_machine_fifo_out_first;
assign bank_machine_source_last = bank_machine_fifo_out_last;
assign bank_machine_source_payload_we = bank_machine_fifo_out_payload_we;
assign bank_machine_source_payload_addr = bank_machine_fifo_out_payload_addr;
assign bank_machine_source_payload_bank = bank_machine_fifo_out_payload_bank;
assign bank_machine_re = bank_machine_source_ready;
assign bank_machine_syncfifo_re = (bank_machine_syncfifo_readable & ((~bank_machine_readable) | bank_machine_re));
assign bank_machine_level1 = (bank_machine_level0 + bank_machine_readable);

// synthesis translate_off
reg dummy_d_2;
// synthesis translate_on
always @(*) begin
	bank_machine_wrport_adr <= 3'd0;
	if (bank_machine_replace) begin
		bank_machine_wrport_adr <= (bank_machine_produce - 1'd1);
	end else begin
		bank_machine_wrport_adr <= bank_machine_produce;
	end
// synthesis translate_off
	dummy_d_2 <= dummy_s;
// synthesis translate_on
end
assign bank_machine_wrport_dat_w = bank_machine_syncfifo_din;
assign bank_machine_wrport_we = (bank_machine_syncfifo_we & (bank_machine_syncfifo_writable | bank_machine_replace));
assign bank_machine_do_read = (bank_machine_syncfifo_readable & bank_machine_syncfifo_re);
assign bank_machine_rdport_adr = bank_machine_consume;
assign bank_machine_syncfifo_dout = bank_machine_rdport_dat_r;
assign bank_machine_rdport_re = bank_machine_do_read;
assign bank_machine_syncfifo_writable = (bank_machine_level0 != 4'd8);
assign bank_machine_syncfifo_readable = (bank_machine_level0 != 1'd0);
assign bank_machine_pipe_valid_sink_ready = ((~bank_machine_pipe_valid_source_valid) | bank_machine_pipe_valid_source_ready);
assign bank_machine_pipe_valid_sink_valid = bank_machine_sink_sink_valid;
assign bank_machine_sink_sink_ready = bank_machine_pipe_valid_sink_ready;
assign bank_machine_pipe_valid_sink_first = bank_machine_sink_sink_first;
assign bank_machine_pipe_valid_sink_last = bank_machine_sink_sink_last;
assign bank_machine_pipe_valid_sink_payload_we = bank_machine_sink_sink_payload_we;
assign bank_machine_pipe_valid_sink_payload_addr = bank_machine_sink_sink_payload_addr;
assign bank_machine_pipe_valid_sink_payload_bank = bank_machine_sink_sink_payload_bank;
assign bank_machine_source_source_valid = bank_machine_pipe_valid_source_valid;
assign bank_machine_pipe_valid_source_ready = bank_machine_source_source_ready;
assign bank_machine_source_source_first = bank_machine_pipe_valid_source_first;
assign bank_machine_source_source_last = bank_machine_pipe_valid_source_last;
assign bank_machine_source_source_payload_we = bank_machine_pipe_valid_source_payload_we;
assign bank_machine_source_source_payload_addr = bank_machine_pipe_valid_source_payload_addr;
assign bank_machine_source_source_payload_bank = bank_machine_pipe_valid_source_payload_bank;

// synthesis translate_off
reg dummy_d_3;
// synthesis translate_on
always @(*) begin
	bank_machine_req_wdata_ready <= 1'd0;
	bank_machine_req_rdata_valid <= 1'd0;
	bank_machine_refresh_gnt <= 1'd0;
	bank_machine_cmd_valid <= 1'd0;
	bank_machine_cmd_payload_cas <= 1'd0;
	bank_machine_cmd_payload_ras <= 1'd0;
	bank_machine_cmd_payload_we <= 1'd0;
	bank_machine_cmd_payload_is_cmd <= 1'd0;
	bank_machine_cmd_payload_is_read <= 1'd0;
	bank_machine_cmd_payload_is_write <= 1'd0;
	bank_machine_row_open <= 1'd0;
	bank_machine_row_close <= 1'd0;
	bank_machine_row_col_n_addr_sel <= 1'd0;
	bankmachine_next_state <= 3'd0;
	bankmachine_next_state <= bankmachine_state;
	case (bankmachine_state)
		1'd1: begin
			if (((bank_machine_twtpcon_ready & bank_machine_trtpcon_ready) & bank_machine_trascon_ready)) begin
				bank_machine_cmd_valid <= 1'd1;
				if (bank_machine_cmd_ready) begin
					bankmachine_next_state <= 3'd5;
				end
				bank_machine_cmd_payload_ras <= 1'd1;
				bank_machine_cmd_payload_we <= 1'd1;
				bank_machine_cmd_payload_is_cmd <= 1'd1;
			end
			bank_machine_row_close <= 1'd1;
		end
		2'd2: begin
			if (((bank_machine_twtpcon_ready & bank_machine_trtpcon_ready) & bank_machine_trascon_ready)) begin
				bankmachine_next_state <= 3'd5;
			end
			bank_machine_row_close <= 1'd1;
		end
		2'd3: begin
			if (bank_machine_trccon_ready) begin
				bank_machine_row_col_n_addr_sel <= 1'd1;
				bank_machine_row_open <= 1'd1;
				bank_machine_cmd_valid <= 1'd1;
				bank_machine_cmd_payload_is_cmd <= 1'd1;
				if (bank_machine_cmd_ready) begin
					bankmachine_next_state <= 3'd6;
				end
				bank_machine_cmd_payload_ras <= 1'd1;
			end
		end
		3'd4: begin
			if (((bank_machine_twtpcon_ready & bank_machine_trtpcon_ready) & bank_machine_trascon_ready)) begin
				bank_machine_refresh_gnt <= 1'd1;
			end
			bank_machine_row_close <= 1'd1;
			bank_machine_cmd_payload_is_cmd <= 1'd1;
			if ((~bank_machine_refresh_req)) begin
				bankmachine_next_state <= 1'd0;
			end
		end
		3'd5: begin
			bankmachine_next_state <= 2'd3;
		end
		3'd6: begin
			bankmachine_next_state <= 1'd0;
		end
		default: begin
			if (bank_machine_refresh_req) begin
				bankmachine_next_state <= 3'd4;
			end else begin
				if (bank_machine_source_source_valid) begin
					if (bank_machine_row_opened) begin
						if (bank_machine_row_hit) begin
							bank_machine_cmd_valid <= 1'd1;
							if (bank_machine_source_source_payload_we) begin
								bank_machine_req_wdata_ready <= bank_machine_cmd_ready;
								bank_machine_cmd_payload_is_write <= 1'd1;
								bank_machine_cmd_payload_we <= 1'd1;
							end else begin
								bank_machine_req_rdata_valid <= bank_machine_cmd_ready;
								bank_machine_cmd_payload_is_read <= 1'd1;
							end
							bank_machine_cmd_payload_cas <= 1'd1;
							if ((bank_machine_cmd_ready & bank_machine_auto_precharge)) begin
								bankmachine_next_state <= 2'd2;
							end
						end else begin
							bankmachine_next_state <= 1'd1;
						end
					end else begin
						bankmachine_next_state <= 2'd3;
					end
				end
			end
		end
	endcase
// synthesis translate_off
	dummy_d_3 <= dummy_s;
// synthesis translate_on
end
assign trrdcon_valid = ((choose_req_cmd_valid & choose_req_cmd_ready) & ((choose_req_cmd_payload_ras & (~choose_req_cmd_payload_cas)) & (~choose_req_cmd_payload_we)));
assign tfawcon_valid = ((choose_req_cmd_valid & choose_req_cmd_ready) & ((choose_req_cmd_payload_ras & (~choose_req_cmd_payload_cas)) & (~choose_req_cmd_payload_we)));
assign ras_allowed = (trrdcon_ready & tfawcon_ready);
assign tccdcon_valid = ((choose_req_cmd_valid & choose_req_cmd_ready) & (choose_req_cmd_payload_is_write | choose_req_cmd_payload_is_read));
assign cas_allowed = tccdcon_ready;
assign twtrcon_valid = ((choose_req_cmd_valid & choose_req_cmd_ready) & choose_req_cmd_payload_is_write);
assign read_available = (bank_machine_cmd_valid & bank_machine_cmd_payload_is_read);
assign write_available = (bank_machine_cmd_valid & bank_machine_cmd_payload_is_write);
assign max_time0 = (time0 == 1'd0);
assign max_time1 = (time1 == 1'd0);
assign bank_machine_refresh_req = refresher_cmd_valid;
assign go_to_refresh = bank_machine_refresh_gnt;
assign interface_rdata = {dfi_p0_rddata};
assign {dfi_p0_wrdata} = interface_wdata;
assign {dfi_p0_wrdata_mask} = (~interface_wdata_we);
assign choose_cmd_valids = (bank_machine_cmd_valid & ((((bank_machine_cmd_payload_is_cmd & choose_cmd_want_cmds) & ((~((bank_machine_cmd_payload_ras & (~bank_machine_cmd_payload_cas)) & (~bank_machine_cmd_payload_we))) | choose_cmd_want_activates)) | (bank_machine_cmd_payload_is_read & choose_cmd_want_reads)) | (bank_machine_cmd_payload_is_write & choose_cmd_want_writes)));
assign choose_cmd_request = choose_cmd_valids;
assign choose_cmd_cmd_valid = rhs_self3;
assign choose_cmd_cmd_payload_a = rhs_self4;
assign choose_cmd_cmd_payload_ba = rhs_self5;
assign choose_cmd_cmd_payload_is_read = rhs_self6;
assign choose_cmd_cmd_payload_is_write = rhs_self7;
assign choose_cmd_cmd_payload_is_cmd = rhs_self8;

// synthesis translate_off
reg dummy_d_4;
// synthesis translate_on
always @(*) begin
	choose_cmd_cmd_payload_cas <= 1'd0;
	if (choose_cmd_cmd_valid) begin
		choose_cmd_cmd_payload_cas <= t_self0;
	end
// synthesis translate_off
	dummy_d_4 <= dummy_s;
// synthesis translate_on
end

// synthesis translate_off
reg dummy_d_5;
// synthesis translate_on
always @(*) begin
	choose_cmd_cmd_payload_ras <= 1'd0;
	if (choose_cmd_cmd_valid) begin
		choose_cmd_cmd_payload_ras <= t_self1;
	end
// synthesis translate_off
	dummy_d_5 <= dummy_s;
// synthesis translate_on
end

// synthesis translate_off
reg dummy_d_6;
// synthesis translate_on
always @(*) begin
	choose_cmd_cmd_payload_we <= 1'd0;
	if (choose_cmd_cmd_valid) begin
		choose_cmd_cmd_payload_we <= t_self2;
	end
// synthesis translate_off
	dummy_d_6 <= dummy_s;
// synthesis translate_on
end
assign choose_cmd_ce = (choose_cmd_cmd_ready | (~choose_cmd_cmd_valid));
assign choose_cmd_grant = 1'd0;
assign choose_req_valids = (bank_machine_cmd_valid & ((((bank_machine_cmd_payload_is_cmd & choose_req_want_cmds) & ((~((bank_machine_cmd_payload_ras & (~bank_machine_cmd_payload_cas)) & (~bank_machine_cmd_payload_we))) | choose_req_want_activates)) | (bank_machine_cmd_payload_is_read & choose_req_want_reads)) | (bank_machine_cmd_payload_is_write & choose_req_want_writes)));
assign choose_req_request = choose_req_valids;
assign choose_req_cmd_valid = rhs_self9;
assign choose_req_cmd_payload_a = rhs_self10;
assign choose_req_cmd_payload_ba = rhs_self11;
assign choose_req_cmd_payload_is_read = rhs_self12;
assign choose_req_cmd_payload_is_write = rhs_self13;
assign choose_req_cmd_payload_is_cmd = rhs_self14;

// synthesis translate_off
reg dummy_d_7;
// synthesis translate_on
always @(*) begin
	choose_req_cmd_payload_cas <= 1'd0;
	if (choose_req_cmd_valid) begin
		choose_req_cmd_payload_cas <= t_self3;
	end
// synthesis translate_off
	dummy_d_7 <= dummy_s;
// synthesis translate_on
end

// synthesis translate_off
reg dummy_d_8;
// synthesis translate_on
always @(*) begin
	choose_req_cmd_payload_ras <= 1'd0;
	if (choose_req_cmd_valid) begin
		choose_req_cmd_payload_ras <= t_self4;
	end
// synthesis translate_off
	dummy_d_8 <= dummy_s;
// synthesis translate_on
end

// synthesis translate_off
reg dummy_d_9;
// synthesis translate_on
always @(*) begin
	choose_req_cmd_payload_we <= 1'd0;
	if (choose_req_cmd_valid) begin
		choose_req_cmd_payload_we <= t_self5;
	end
// synthesis translate_off
	dummy_d_9 <= dummy_s;
// synthesis translate_on
end

// synthesis translate_off
reg dummy_d_10;
// synthesis translate_on
always @(*) begin
	bank_machine_cmd_ready <= 1'd0;
	if (((choose_cmd_cmd_valid & choose_cmd_cmd_ready) & (choose_cmd_grant == 1'd0))) begin
		bank_machine_cmd_ready <= 1'd1;
	end
	if (((choose_req_cmd_valid & choose_req_cmd_ready) & (choose_req_grant == 1'd0))) begin
		bank_machine_cmd_ready <= 1'd1;
	end
// synthesis translate_off
	dummy_d_10 <= dummy_s;
// synthesis translate_on
end
assign choose_req_ce = (choose_req_cmd_ready | (~choose_req_cmd_valid));
assign choose_req_grant = 1'd0;
assign dfi_p0_reset_n = 1'd1;
assign dfi_p0_cke = {1{steerer1}};
assign dfi_p0_odt = {1{steerer2}};
assign dfi_p0_bank = steerer_bank;
assign dfi_p0_address = steerer_address;

// synthesis translate_off
reg dummy_d_11;
// synthesis translate_on
always @(*) begin
	refresher_cmd_ready <= 1'd0;
	choose_req_want_reads <= 1'd0;
	choose_req_want_writes <= 1'd0;
	choose_req_want_cmds <= 1'd0;
	choose_req_want_activates <= 1'd0;
	choose_req_cmd_ready <= 1'd0;
	steerer0 <= 2'd0;
	en0 <= 1'd0;
	en1 <= 1'd0;
	multiplexer_next_state <= 4'd0;
	choose_req_want_cmds <= 1'd1;
	choose_req_want_activates <= ras_allowed;
	multiplexer_next_state <= multiplexer_state;
	case (multiplexer_state)
		1'd1: begin
			en1 <= 1'd1;
			choose_req_want_writes <= 1'd1;
			if (1'd1) begin
				choose_req_cmd_ready <= (cas_allowed & ((~((choose_req_cmd_payload_ras & (~choose_req_cmd_payload_cas)) & (~choose_req_cmd_payload_we))) | ras_allowed));
			end else begin
				choose_req_want_cmds <= 1'd1;
				choose_req_want_activates <= ras_allowed;
				choose_req_cmd_ready <= ((~((choose_req_cmd_payload_ras & (~choose_req_cmd_payload_cas)) & (~choose_req_cmd_payload_we))) | ras_allowed);
				choose_req_cmd_ready <= cas_allowed;
			end
			steerer0 <= 1'd0;
			if (1'd1) begin
				steerer0 <= 2'd2;
			end
			if (1'd1) begin
				steerer0 <= 1'd1;
			end
			if (read_available) begin
				if (((~write_available) | max_time1)) begin
					multiplexer_next_state <= 2'd3;
				end
			end
			if (go_to_refresh) begin
				multiplexer_next_state <= 2'd2;
			end
		end
		2'd2: begin
			steerer0 <= 2'd3;
			refresher_cmd_ready <= 1'd1;
			if (refresher_cmd_last) begin
				if ((write_available & (~read_available))) begin
					multiplexer_next_state <= 1'd1;
				end else begin
					multiplexer_next_state <= 1'd0;
				end
			end
		end
		2'd3: begin
			if (twtrcon_ready) begin
				multiplexer_next_state <= 1'd0;
			end
		end
		3'd4: begin
			multiplexer_next_state <= 3'd5;
		end
		3'd5: begin
			multiplexer_next_state <= 3'd6;
		end
		3'd6: begin
			multiplexer_next_state <= 3'd7;
		end
		3'd7: begin
			multiplexer_next_state <= 4'd8;
		end
		4'd8: begin
			multiplexer_next_state <= 4'd9;
		end
		4'd9: begin
			multiplexer_next_state <= 1'd1;
		end
		default: begin
			en0 <= 1'd1;
			choose_req_want_reads <= 1'd1;
			if (1'd1) begin
				choose_req_cmd_ready <= (cas_allowed & ((~((choose_req_cmd_payload_ras & (~choose_req_cmd_payload_cas)) & (~choose_req_cmd_payload_we))) | ras_allowed));
			end else begin
				choose_req_want_cmds <= 1'd1;
				choose_req_want_activates <= ras_allowed;
				choose_req_cmd_ready <= ((~((choose_req_cmd_payload_ras & (~choose_req_cmd_payload_cas)) & (~choose_req_cmd_payload_we))) | ras_allowed);
				choose_req_cmd_ready <= cas_allowed;
			end
			steerer0 <= 1'd0;
			if (1'd1) begin
				steerer0 <= 2'd2;
			end
			if (1'd1) begin
				steerer0 <= 1'd1;
			end
			if (write_available) begin
				if (((~read_available) | max_time0)) begin
					multiplexer_next_state <= 3'd4;
				end
			end
			if (go_to_refresh) begin
				multiplexer_next_state <= 2'd2;
			end
		end
	endcase
// synthesis translate_off
	dummy_d_11 <= dummy_s;
// synthesis translate_on
end

// synthesis translate_off
reg dummy_d_12;
// synthesis translate_on
always @(*) begin
	rhs_self0 <= 1'd0;
	case (bank_machine_grant)
		1'd0: begin
			rhs_self0 <= bank_machine_record0_valid;
		end
		1'd1: begin
			rhs_self0 <= bank_machine_record1_valid;
		end
		2'd2: begin
			rhs_self0 <= bank_machine_record2_valid;
		end
		default: begin
			rhs_self0 <= bank_machine_record3_valid;
		end
	endcase
// synthesis translate_off
	dummy_d_12 <= dummy_s;
// synthesis translate_on
end

// synthesis translate_off
reg dummy_d_13;
// synthesis translate_on
always @(*) begin
	rhs_self1 <= 1'd0;
	case (bank_machine_grant)
		1'd0: begin
			rhs_self1 <= bank_machine_record0_we;
		end
		1'd1: begin
			rhs_self1 <= bank_machine_record1_we;
		end
		2'd2: begin
			rhs_self1 <= bank_machine_record2_we;
		end
		default: begin
			rhs_self1 <= bank_machine_record3_we;
		end
	endcase
// synthesis translate_off
	dummy_d_13 <= dummy_s;
// synthesis translate_on
end

// synthesis translate_off
reg dummy_d_14;
// synthesis translate_on
always @(*) begin
	rhs_self2 <= 22'd0;
	case (bank_machine_grant)
		1'd0: begin
			rhs_self2 <= bank_machine_record0_addr;
		end
		1'd1: begin
			rhs_self2 <= bank_machine_record1_addr;
		end
		2'd2: begin
			rhs_self2 <= bank_machine_record2_addr;
		end
		default: begin
			rhs_self2 <= bank_machine_record3_addr;
		end
	endcase
// synthesis translate_off
	dummy_d_14 <= dummy_s;
// synthesis translate_on
end

// synthesis translate_off
reg dummy_d_15;
// synthesis translate_on
always @(*) begin
	rhs_self3 <= 1'd0;
	case (choose_cmd_grant)
		default: begin
			rhs_self3 <= choose_cmd_valids;
		end
	endcase
// synthesis translate_off
	dummy_d_15 <= dummy_s;
// synthesis translate_on
end

// synthesis translate_off
reg dummy_d_16;
// synthesis translate_on
always @(*) begin
	rhs_self4 <= 13'd0;
	case (choose_cmd_grant)
		default: begin
			rhs_self4 <= bank_machine_cmd_payload_a;
		end
	endcase
// synthesis translate_off
	dummy_d_16 <= dummy_s;
// synthesis translate_on
end

// synthesis translate_off
reg dummy_d_17;
// synthesis translate_on
always @(*) begin
	rhs_self5 <= 2'd0;
	case (choose_cmd_grant)
		default: begin
			rhs_self5 <= bank_machine_cmd_payload_ba;
		end
	endcase
// synthesis translate_off
	dummy_d_17 <= dummy_s;
// synthesis translate_on
end

// synthesis translate_off
reg dummy_d_18;
// synthesis translate_on
always @(*) begin
	rhs_self6 <= 1'd0;
	case (choose_cmd_grant)
		default: begin
			rhs_self6 <= bank_machine_cmd_payload_is_read;
		end
	endcase
// synthesis translate_off
	dummy_d_18 <= dummy_s;
// synthesis translate_on
end

// synthesis translate_off
reg dummy_d_19;
// synthesis translate_on
always @(*) begin
	rhs_self7 <= 1'd0;
	case (choose_cmd_grant)
		default: begin
			rhs_self7 <= bank_machine_cmd_payload_is_write;
		end
	endcase
// synthesis translate_off
	dummy_d_19 <= dummy_s;
// synthesis translate_on
end

// synthesis translate_off
reg dummy_d_20;
// synthesis translate_on
always @(*) begin
	rhs_self8 <= 1'd0;
	case (choose_cmd_grant)
		default: begin
			rhs_self8 <= bank_machine_cmd_payload_is_cmd;
		end
	endcase
// synthesis translate_off
	dummy_d_20 <= dummy_s;
// synthesis translate_on
end

// synthesis translate_off
reg dummy_d_21;
// synthesis translate_on
always @(*) begin
	t_self0 <= 1'd0;
	case (choose_cmd_grant)
		default: begin
			t_self0 <= bank_machine_cmd_payload_cas;
		end
	endcase
// synthesis translate_off
	dummy_d_21 <= dummy_s;
// synthesis translate_on
end

// synthesis translate_off
reg dummy_d_22;
// synthesis translate_on
always @(*) begin
	t_self1 <= 1'd0;
	case (choose_cmd_grant)
		default: begin
			t_self1 <= bank_machine_cmd_payload_ras;
		end
	endcase
// synthesis translate_off
	dummy_d_22 <= dummy_s;
// synthesis translate_on
end

// synthesis translate_off
reg dummy_d_23;
// synthesis translate_on
always @(*) begin
	t_self2 <= 1'd0;
	case (choose_cmd_grant)
		default: begin
			t_self2 <= bank_machine_cmd_payload_we;
		end
	endcase
// synthesis translate_off
	dummy_d_23 <= dummy_s;
// synthesis translate_on
end

// synthesis translate_off
reg dummy_d_24;
// synthesis translate_on
always @(*) begin
	rhs_self9 <= 1'd0;
	case (choose_req_grant)
		default: begin
			rhs_self9 <= choose_req_valids;
		end
	endcase
// synthesis translate_off
	dummy_d_24 <= dummy_s;
// synthesis translate_on
end

// synthesis translate_off
reg dummy_d_25;
// synthesis translate_on
always @(*) begin
	rhs_self10 <= 13'd0;
	case (choose_req_grant)
		default: begin
			rhs_self10 <= bank_machine_cmd_payload_a;
		end
	endcase
// synthesis translate_off
	dummy_d_25 <= dummy_s;
// synthesis translate_on
end

// synthesis translate_off
reg dummy_d_26;
// synthesis translate_on
always @(*) begin
	rhs_self11 <= 2'd0;
	case (choose_req_grant)
		default: begin
			rhs_self11 <= bank_machine_cmd_payload_ba;
		end
	endcase
// synthesis translate_off
	dummy_d_26 <= dummy_s;
// synthesis translate_on
end

// synthesis translate_off
reg dummy_d_27;
// synthesis translate_on
always @(*) begin
	rhs_self12 <= 1'd0;
	case (choose_req_grant)
		default: begin
			rhs_self12 <= bank_machine_cmd_payload_is_read;
		end
	endcase
// synthesis translate_off
	dummy_d_27 <= dummy_s;
// synthesis translate_on
end

// synthesis translate_off
reg dummy_d_28;
// synthesis translate_on
always @(*) begin
	rhs_self13 <= 1'd0;
	case (choose_req_grant)
		default: begin
			rhs_self13 <= bank_machine_cmd_payload_is_write;
		end
	endcase
// synthesis translate_off
	dummy_d_28 <= dummy_s;
// synthesis translate_on
end

// synthesis translate_off
reg dummy_d_29;
// synthesis translate_on
always @(*) begin
	rhs_self14 <= 1'd0;
	case (choose_req_grant)
		default: begin
			rhs_self14 <= bank_machine_cmd_payload_is_cmd;
		end
	endcase
// synthesis translate_off
	dummy_d_29 <= dummy_s;
// synthesis translate_on
end

// synthesis translate_off
reg dummy_d_30;
// synthesis translate_on
always @(*) begin
	t_self3 <= 1'd0;
	case (choose_req_grant)
		default: begin
			t_self3 <= bank_machine_cmd_payload_cas;
		end
	endcase
// synthesis translate_off
	dummy_d_30 <= dummy_s;
// synthesis translate_on
end

// synthesis translate_off
reg dummy_d_31;
// synthesis translate_on
always @(*) begin
	t_self4 <= 1'd0;
	case (choose_req_grant)
		default: begin
			t_self4 <= bank_machine_cmd_payload_ras;
		end
	endcase
// synthesis translate_off
	dummy_d_31 <= dummy_s;
// synthesis translate_on
end

// synthesis translate_off
reg dummy_d_32;
// synthesis translate_on
always @(*) begin
	t_self5 <= 1'd0;
	case (choose_req_grant)
		default: begin
			t_self5 <= bank_machine_cmd_payload_we;
		end
	endcase
// synthesis translate_off
	dummy_d_32 <= dummy_s;
// synthesis translate_on
end

// synthesis translate_off
reg dummy_d_33;
// synthesis translate_on
always @(*) begin
	self0 <= 2'd0;
	case (steerer0)
		1'd0: begin
			self0 <= nop_ba[1:0];
		end
		1'd1: begin
			self0 <= choose_req_cmd_payload_ba[1:0];
		end
		2'd2: begin
			self0 <= choose_req_cmd_payload_ba[1:0];
		end
		default: begin
			self0 <= refresher_cmd_payload_ba[1:0];
		end
	endcase
// synthesis translate_off
	dummy_d_33 <= dummy_s;
// synthesis translate_on
end

// synthesis translate_off
reg dummy_d_34;
// synthesis translate_on
always @(*) begin
	self1 <= 13'd0;
	case (steerer0)
		1'd0: begin
			self1 <= nop_a;
		end
		1'd1: begin
			self1 <= choose_req_cmd_payload_a;
		end
		2'd2: begin
			self1 <= choose_req_cmd_payload_a;
		end
		default: begin
			self1 <= refresher_cmd_payload_a;
		end
	endcase
// synthesis translate_off
	dummy_d_34 <= dummy_s;
// synthesis translate_on
end

// synthesis translate_off
reg dummy_d_35;
// synthesis translate_on
always @(*) begin
	self2 <= 1'd0;
	case (steerer0)
		1'd0: begin
			self2 <= 1'd0;
		end
		1'd1: begin
			self2 <= ((choose_req_cmd_valid & choose_req_cmd_ready) & choose_req_cmd_payload_cas);
		end
		2'd2: begin
			self2 <= ((choose_req_cmd_valid & choose_req_cmd_ready) & choose_req_cmd_payload_cas);
		end
		default: begin
			self2 <= ((refresher_cmd_valid & refresher_cmd_ready) & refresher_cmd_payload_cas);
		end
	endcase
// synthesis translate_off
	dummy_d_35 <= dummy_s;
// synthesis translate_on
end

// synthesis translate_off
reg dummy_d_36;
// synthesis translate_on
always @(*) begin
	self3 <= 1'd0;
	case (steerer0)
		1'd0: begin
			self3 <= 1'd0;
		end
		1'd1: begin
			self3 <= ((choose_req_cmd_valid & choose_req_cmd_ready) & choose_req_cmd_payload_ras);
		end
		2'd2: begin
			self3 <= ((choose_req_cmd_valid & choose_req_cmd_ready) & choose_req_cmd_payload_ras);
		end
		default: begin
			self3 <= ((refresher_cmd_valid & refresher_cmd_ready) & refresher_cmd_payload_ras);
		end
	endcase
// synthesis translate_off
	dummy_d_36 <= dummy_s;
// synthesis translate_on
end

// synthesis translate_off
reg dummy_d_37;
// synthesis translate_on
always @(*) begin
	self4 <= 1'd0;
	case (steerer0)
		1'd0: begin
			self4 <= 1'd0;
		end
		1'd1: begin
			self4 <= ((choose_req_cmd_valid & choose_req_cmd_ready) & choose_req_cmd_payload_we);
		end
		2'd2: begin
			self4 <= ((choose_req_cmd_valid & choose_req_cmd_ready) & choose_req_cmd_payload_we);
		end
		default: begin
			self4 <= ((refresher_cmd_valid & refresher_cmd_ready) & refresher_cmd_payload_we);
		end
	endcase
// synthesis translate_off
	dummy_d_37 <= dummy_s;
// synthesis translate_on
end

// synthesis translate_off
reg dummy_d_38;
// synthesis translate_on
always @(*) begin
	self5 <= 1'd0;
	case (steerer0)
		1'd0: begin
			self5 <= 1'd0;
		end
		1'd1: begin
			self5 <= ((choose_req_cmd_valid & choose_req_cmd_ready) & choose_req_cmd_payload_is_read);
		end
		2'd2: begin
			self5 <= ((choose_req_cmd_valid & choose_req_cmd_ready) & choose_req_cmd_payload_is_read);
		end
		default: begin
			self5 <= ((refresher_cmd_valid & refresher_cmd_ready) & refresher_cmd_payload_is_read);
		end
	endcase
// synthesis translate_off
	dummy_d_38 <= dummy_s;
// synthesis translate_on
end

// synthesis translate_off
reg dummy_d_39;
// synthesis translate_on
always @(*) begin
	self6 <= 1'd0;
	case (steerer0)
		1'd0: begin
			self6 <= 1'd0;
		end
		1'd1: begin
			self6 <= ((choose_req_cmd_valid & choose_req_cmd_ready) & choose_req_cmd_payload_is_write);
		end
		2'd2: begin
			self6 <= ((choose_req_cmd_valid & choose_req_cmd_ready) & choose_req_cmd_payload_is_write);
		end
		default: begin
			self6 <= ((refresher_cmd_valid & refresher_cmd_ready) & refresher_cmd_payload_is_write);
		end
	endcase
// synthesis translate_off
	dummy_d_39 <= dummy_s;
// synthesis translate_on
end

always @(posedge sys_clk) begin
	if (refresher_zqcs_timer_done0) begin
		refresher_wants_zqcs <= 1'd1;
	end else begin
		if (refresher_zqcs_executer_start) begin
			refresher_wants_zqcs <= 1'd0;
		end
	end
	if ((refresher_timer_wait & (~refresher_timer_done0))) begin
		refresher_timer_count1 <= (refresher_timer_count1 - 1'd1);
	end else begin
		refresher_timer_count1 <= 10'd779;
	end
	refresher_postponer_req_o <= 1'd0;
	if (refresher_postponer_req_i) begin
		refresher_postponer_count <= (refresher_postponer_count - 1'd1);
		if ((refresher_postponer_count == 1'd0)) begin
			refresher_postponer_count <= 1'd0;
			refresher_postponer_req_o <= 1'd1;
		end
	end
	if (refresher_sequencer_start0) begin
		refresher_sequencer_count <= 1'd0;
	end else begin
		if (refresher_sequencer_done1) begin
			if ((refresher_sequencer_count != 1'd0)) begin
				refresher_sequencer_count <= (refresher_sequencer_count - 1'd1);
			end
		end
	end
	refresher_cmd_payload_a <= 1'd0;
	refresher_cmd_payload_ba <= 1'd0;
	refresher_cmd_payload_cas <= 1'd0;
	refresher_cmd_payload_ras <= 1'd0;
	refresher_cmd_payload_we <= 1'd0;
	refresher_sequencer_done1 <= 1'd0;
	if ((refresher_sequencer_start1 & (refresher_sequencer_trigger == 1'd0))) begin
		refresher_cmd_payload_a <= 11'd1024;
		refresher_cmd_payload_ba <= 1'd0;
		refresher_cmd_payload_cas <= 1'd0;
		refresher_cmd_payload_ras <= 1'd1;
		refresher_cmd_payload_we <= 1'd1;
	end
	if ((refresher_sequencer_trigger == 2'd2)) begin
		refresher_cmd_payload_a <= 11'd1024;
		refresher_cmd_payload_ba <= 1'd0;
		refresher_cmd_payload_cas <= 1'd1;
		refresher_cmd_payload_ras <= 1'd1;
		refresher_cmd_payload_we <= 1'd0;
	end
	if ((refresher_sequencer_trigger == 4'd9)) begin
		refresher_cmd_payload_a <= 1'd0;
		refresher_cmd_payload_ba <= 1'd0;
		refresher_cmd_payload_cas <= 1'd0;
		refresher_cmd_payload_ras <= 1'd0;
		refresher_cmd_payload_we <= 1'd0;
		refresher_sequencer_done1 <= 1'd1;
	end
	if ((refresher_sequencer_trigger == 4'd9)) begin
		refresher_sequencer_trigger <= 1'd0;
	end else begin
		if ((refresher_sequencer_trigger != 1'd0)) begin
			refresher_sequencer_trigger <= (refresher_sequencer_trigger + 1'd1);
		end else begin
			if (refresher_sequencer_start1) begin
				refresher_sequencer_trigger <= 1'd1;
			end
		end
	end
	if ((refresher_zqcs_timer_wait & (~refresher_zqcs_timer_done0))) begin
		refresher_zqcs_timer_count1 <= (refresher_zqcs_timer_count1 - 1'd1);
	end else begin
		refresher_zqcs_timer_count1 <= 27'd99999999;
	end
	refresher_zqcs_executer_done <= 1'd0;
	if ((refresher_zqcs_executer_start & (refresher_zqcs_executer_trigger == 1'd0))) begin
		refresher_cmd_payload_a <= 11'd1024;
		refresher_cmd_payload_ba <= 1'd0;
		refresher_cmd_payload_cas <= 1'd0;
		refresher_cmd_payload_ras <= 1'd1;
		refresher_cmd_payload_we <= 1'd1;
	end
	if ((refresher_zqcs_executer_trigger == 2'd2)) begin
		refresher_cmd_payload_a <= 1'd0;
		refresher_cmd_payload_ba <= 1'd0;
		refresher_cmd_payload_cas <= 1'd0;
		refresher_cmd_payload_ras <= 1'd0;
		refresher_cmd_payload_we <= 1'd1;
	end
	if ((refresher_zqcs_executer_trigger == 7'd66)) begin
		refresher_cmd_payload_a <= 1'd0;
		refresher_cmd_payload_ba <= 1'd0;
		refresher_cmd_payload_cas <= 1'd0;
		refresher_cmd_payload_ras <= 1'd0;
		refresher_cmd_payload_we <= 1'd0;
		refresher_zqcs_executer_done <= 1'd1;
	end
	if ((refresher_zqcs_executer_trigger == 7'd66)) begin
		refresher_zqcs_executer_trigger <= 1'd0;
	end else begin
		if ((refresher_zqcs_executer_trigger != 1'd0)) begin
			refresher_zqcs_executer_trigger <= (refresher_zqcs_executer_trigger + 1'd1);
		end else begin
			if (refresher_zqcs_executer_start) begin
				refresher_zqcs_executer_trigger <= 1'd1;
			end
		end
	end
	refresher_state <= refresher_next_state;
	if (bank_machine_ce) begin
		bank_machine_run <= 1'd0;
	end else begin
		if ((bank_machine_req_valid & bank_machine_req_ready)) begin
			bank_machine_run <= (bank_machine_run + 1'd1);
		end
	end
	if ((bank_machine_push0 & (~bank_machine_pop0))) begin
		bank_machine_pending0 <= (bank_machine_pending0 + 1'd1);
	end else begin
		if (((~bank_machine_push0) & bank_machine_pop0)) begin
			bank_machine_pending0 <= (bank_machine_pending0 - 1'd1);
		end
	end
	if ((bank_machine_push1 & (~bank_machine_pop1))) begin
		bank_machine_pending1 <= (bank_machine_pending1 + 1'd1);
	end else begin
		if (((~bank_machine_push1) & bank_machine_pop1)) begin
			bank_machine_pending1 <= (bank_machine_pending1 - 1'd1);
		end
	end
	if ((bank_machine_push2 & (~bank_machine_pop2))) begin
		bank_machine_pending2 <= (bank_machine_pending2 + 1'd1);
	end else begin
		if (((~bank_machine_push2) & bank_machine_pop2)) begin
			bank_machine_pending2 <= (bank_machine_pending2 - 1'd1);
		end
	end
	if ((bank_machine_push3 & (~bank_machine_pop3))) begin
		bank_machine_pending3 <= (bank_machine_pending3 + 1'd1);
	end else begin
		if (((~bank_machine_push3) & bank_machine_pop3)) begin
			bank_machine_pending3 <= (bank_machine_pending3 - 1'd1);
		end
	end
	if (bank_machine_row_open) begin
		bank_machine_row_bank <= bank_machine_source_source_payload_bank;
	end
	if (bank_machine_row_close) begin
		bank_machine_row_opened <= 1'd0;
	end else begin
		if (bank_machine_row_open) begin
			bank_machine_row_opened <= 1'd1;
			bank_machine_row <= bank_machine_source_source_payload_addr[21:9];
		end
	end
	if (bank_machine_syncfifo_re) begin
		bank_machine_readable <= 1'd1;
	end else begin
		if (bank_machine_re) begin
			bank_machine_readable <= 1'd0;
		end
	end
	if (((bank_machine_syncfifo_we & bank_machine_syncfifo_writable) & (~bank_machine_replace))) begin
		bank_machine_produce <= (bank_machine_produce + 1'd1);
	end
	if (bank_machine_do_read) begin
		bank_machine_consume <= (bank_machine_consume + 1'd1);
	end
	if (((bank_machine_syncfifo_we & bank_machine_syncfifo_writable) & (~bank_machine_replace))) begin
		if ((~bank_machine_do_read)) begin
			bank_machine_level0 <= (bank_machine_level0 + 1'd1);
		end
	end else begin
		if (bank_machine_do_read) begin
			bank_machine_level0 <= (bank_machine_level0 - 1'd1);
		end
	end
	if (((~bank_machine_pipe_valid_source_valid) | bank_machine_pipe_valid_source_ready)) begin
		bank_machine_pipe_valid_source_valid <= bank_machine_pipe_valid_sink_valid;
		bank_machine_pipe_valid_source_first <= bank_machine_pipe_valid_sink_first;
		bank_machine_pipe_valid_source_last <= bank_machine_pipe_valid_sink_last;
		bank_machine_pipe_valid_source_payload_we <= bank_machine_pipe_valid_sink_payload_we;
		bank_machine_pipe_valid_source_payload_addr <= bank_machine_pipe_valid_sink_payload_addr;
		bank_machine_pipe_valid_source_payload_bank <= bank_machine_pipe_valid_sink_payload_bank;
	end
	if (bank_machine_ce) begin
		case (bank_machine_grant)
			1'd0: begin
				if (bank_machine_request[1]) begin
					bank_machine_grant <= 1'd1;
				end else begin
					if (bank_machine_request[2]) begin
						bank_machine_grant <= 2'd2;
					end else begin
						if (bank_machine_request[3]) begin
							bank_machine_grant <= 2'd3;
						end
					end
				end
			end
			1'd1: begin
				if (bank_machine_request[2]) begin
					bank_machine_grant <= 2'd2;
				end else begin
					if (bank_machine_request[3]) begin
						bank_machine_grant <= 2'd3;
					end else begin
						if (bank_machine_request[0]) begin
							bank_machine_grant <= 1'd0;
						end
					end
				end
			end
			2'd2: begin
				if (bank_machine_request[3]) begin
					bank_machine_grant <= 2'd3;
				end else begin
					if (bank_machine_request[0]) begin
						bank_machine_grant <= 1'd0;
					end else begin
						if (bank_machine_request[1]) begin
							bank_machine_grant <= 1'd1;
						end
					end
				end
			end
			2'd3: begin
				if (bank_machine_request[0]) begin
					bank_machine_grant <= 1'd0;
				end else begin
					if (bank_machine_request[1]) begin
						bank_machine_grant <= 1'd1;
					end else begin
						if (bank_machine_request[2]) begin
							bank_machine_grant <= 2'd2;
						end
					end
				end
			end
		endcase
	end
	if (bank_machine_twtpcon_valid) begin
		bank_machine_twtpcon_count <= 3'd4;
		if (1'd0) begin
			bank_machine_twtpcon_ready <= 1'd1;
		end else begin
			bank_machine_twtpcon_ready <= 1'd0;
		end
	end else begin
		if ((~bank_machine_twtpcon_ready)) begin
			bank_machine_twtpcon_count <= (bank_machine_twtpcon_count - 1'd1);
			if ((bank_machine_twtpcon_count == 1'd1)) begin
				bank_machine_twtpcon_ready <= 1'd1;
			end
		end
	end
	if (bank_machine_trccon_valid) begin
		bank_machine_trccon_count <= 3'd5;
		if (1'd0) begin
			bank_machine_trccon_ready <= 1'd1;
		end else begin
			bank_machine_trccon_ready <= 1'd0;
		end
	end else begin
		if ((~bank_machine_trccon_ready)) begin
			bank_machine_trccon_count <= (bank_machine_trccon_count - 1'd1);
			if ((bank_machine_trccon_count == 1'd1)) begin
				bank_machine_trccon_ready <= 1'd1;
			end
		end
	end
	if (bank_machine_trascon_valid) begin
		bank_machine_trascon_count <= 3'd4;
		if (1'd0) begin
			bank_machine_trascon_ready <= 1'd1;
		end else begin
			bank_machine_trascon_ready <= 1'd0;
		end
	end else begin
		if ((~bank_machine_trascon_ready)) begin
			bank_machine_trascon_count <= (bank_machine_trascon_count - 1'd1);
			if ((bank_machine_trascon_count == 1'd1)) begin
				bank_machine_trascon_ready <= 1'd1;
			end
		end
	end
	bankmachine_state <= bankmachine_next_state;
	if ((~en0)) begin
		time0 <= 6'd63;
	end else begin
		if ((~max_time0)) begin
			time0 <= (time0 - 1'd1);
		end
	end
	if ((~en1)) begin
		time1 <= 5'd31;
	end else begin
		if ((~max_time1)) begin
			time1 <= (time1 - 1'd1);
		end
	end
	dfi_p0_cs_n <= 1'd0;
	steerer_bank <= self0;
	steerer_address <= self1;
	dfi_p0_cas_n <= (~self2);
	dfi_p0_ras_n <= (~self3);
	dfi_p0_we_n <= (~self4);
	dfi_p0_rddata_en <= self5;
	dfi_p0_wrdata_en <= self6;
	if (trrdcon_valid) begin
		trrdcon_count <= 1'd1;
		if (1'd0) begin
			trrdcon_ready <= 1'd1;
		end else begin
			trrdcon_ready <= 1'd0;
		end
	end else begin
		if ((~trrdcon_ready)) begin
			trrdcon_count <= (trrdcon_count - 1'd1);
			if ((trrdcon_count == 1'd1)) begin
				trrdcon_ready <= 1'd1;
			end
		end
	end
	if (tccdcon_valid) begin
		tccdcon_count <= 1'd0;
		if (1'd1) begin
			tccdcon_ready <= 1'd1;
		end else begin
			tccdcon_ready <= 1'd0;
		end
	end else begin
		if ((~tccdcon_ready)) begin
			tccdcon_count <= (tccdcon_count - 1'd1);
			if ((tccdcon_count == 1'd1)) begin
				tccdcon_ready <= 1'd1;
			end
		end
	end
	if (twtrcon_valid) begin
		twtrcon_count <= 2'd3;
		if (1'd0) begin
			twtrcon_ready <= 1'd1;
		end else begin
			twtrcon_ready <= 1'd0;
		end
	end else begin
		if ((~twtrcon_ready)) begin
			twtrcon_count <= (twtrcon_count - 1'd1);
			if ((twtrcon_count == 1'd1)) begin
				twtrcon_ready <= 1'd1;
			end
		end
	end
	multiplexer_state <= multiplexer_next_state;
	if (sys_rst) begin
		dfi_p0_cas_n <= 1'd1;
		dfi_p0_cs_n <= 1'd1;
		dfi_p0_ras_n <= 1'd1;
		dfi_p0_we_n <= 1'd1;
		dfi_p0_wrdata_en <= 1'd0;
		dfi_p0_rddata_en <= 1'd0;
		refresher_cmd_payload_a <= 13'd0;
		refresher_cmd_payload_ba <= 2'd0;
		refresher_cmd_payload_cas <= 1'd0;
		refresher_cmd_payload_ras <= 1'd0;
		refresher_cmd_payload_we <= 1'd0;
		refresher_wants_zqcs <= 1'd0;
		refresher_timer_count1 <= 10'd779;
		refresher_postponer_req_o <= 1'd0;
		refresher_postponer_count <= 1'd0;
		refresher_sequencer_done1 <= 1'd0;
		refresher_sequencer_trigger <= 4'd0;
		refresher_sequencer_count <= 1'd0;
		refresher_zqcs_timer_count1 <= 27'd99999999;
		refresher_zqcs_executer_done <= 1'd0;
		refresher_zqcs_executer_trigger <= 7'd0;
		bank_machine_readable <= 1'd0;
		bank_machine_level0 <= 4'd0;
		bank_machine_produce <= 3'd0;
		bank_machine_consume <= 3'd0;
		bank_machine_pipe_valid_source_valid <= 1'd0;
		bank_machine_pipe_valid_source_payload_we <= 1'd0;
		bank_machine_pipe_valid_source_payload_addr <= 22'd0;
		bank_machine_pipe_valid_source_payload_bank <= 2'd0;
		bank_machine_grant <= 2'd0;
		bank_machine_run <= 7'd0;
		bank_machine_pending0 <= 4'd0;
		bank_machine_pending1 <= 4'd0;
		bank_machine_pending2 <= 4'd0;
		bank_machine_pending3 <= 4'd0;
		bank_machine_row_opened <= 1'd0;
		bank_machine_twtpcon_ready <= 1'd0;
		bank_machine_twtpcon_count <= 3'd0;
		bank_machine_trccon_ready <= 1'd0;
		bank_machine_trccon_count <= 3'd0;
		bank_machine_trascon_ready <= 1'd0;
		bank_machine_trascon_count <= 3'd0;
		trrdcon_ready <= 1'd0;
		trrdcon_count <= 1'd0;
		tccdcon_ready <= 1'd0;
		tccdcon_count <= 1'd0;
		twtrcon_ready <= 1'd0;
		twtrcon_count <= 2'd0;
		time0 <= 6'd0;
		time1 <= 5'd0;
		refresher_state <= 2'd0;
		bankmachine_state <= 3'd0;
		multiplexer_state <= 4'd0;
	end
end

reg [26:0] storage[0:7];
reg [26:0] memdat;
reg [26:0] memdat_1;
always @(posedge sys_clk) begin : mem_write_block
	if (bank_machine_wrport_we)
		storage[bank_machine_wrport_adr] <= bank_machine_wrport_dat_w;
	memdat <= storage[bank_machine_wrport_adr];
end

always @(posedge sys_clk) begin : mem_write_block_1
	if (bank_machine_rdport_re)
		memdat_1 <= storage[bank_machine_rdport_adr];
end

assign bank_machine_wrport_dat_r = memdat;
assign bank_machine_rdport_dat_r = memdat_1;

endmodule

