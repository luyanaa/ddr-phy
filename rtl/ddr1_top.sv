// SPDX-License-Identifier: Apache-2.0
// Generated bundle top. The board/PDK supplies settled CK/sys/CK90, delayed
// receive DQS, and SSTL-2 drivers; rst is the cold initialization request.
`default_nettype none
module ddr1_top #(
    parameter integer TRAIN_ENABLE = 0,
    parameter integer TAP_BITS = 4,
    parameter [22:0] TRAIN_ADDR = 23'h7fffff
) (
    input  wire        sys_clk, ck, ck90, rst,
    input  wire [0:0]  dqs_capture,
    output wire        init_done, read_error, dfi_error,
    output wire        phy_ready, train_busy, train_failed,
    input  wire [0:0]  dqs_tap_ready,
    output wire [0:0]  dqs_tap_valid,
    output wire [TAP_BITS-1:0] dqs_tap_value,

    input  wire        cmd_valid, cmd_we,
    input  wire [22:0] cmd_addr,
    output wire        cmd_ready,
    // Fixed-schedule Native data: supply data at w_ready, take data at r_valid.
    input  wire [31:0] w_data,
    input  wire [3:0]  w_we,
    output wire        w_ready,
    output wire        r_valid,
    output wire [31:0] r_data,

    output wire        pad_ck, pad_ck_n,
    output wire [12:0] a,
    output wire [1:0]  ba,
    output wire        cke, cs_n, ras_n, cas_n, we_n,
    input  wire [7:0]  dq_i,
    output wire [7:0]  dq_o,
    output wire        dq_oe, dm, dqs_o, dqs_oe
);
    localparam [31:0] TRAIN_PATTERN = 32'hd35ac629;

    wire        init_cke, init_cs_n;
    wire [2:0]  init_opcode;
    wire [1:0]  init_bank;
    wire [12:0] init_address;
    ddr1_init init (
        .sys_clk(sys_clk), .rst(rst), .done(init_done),
        .cke(init_cke), .cs_n(init_cs_n), .opcode(init_opcode),
        .bank(init_bank), .address(init_address)
    );

    wire [25:0] ctl_address;
    wire [3:0]  ctl_bank, wrmask;
    wire [1:0]  ctl_cke, ctl_cs_n, ctl_ras_n, ctl_cas_n, ctl_we_n;
    wire [1:0]  ctl_wren, ctl_rden, dfi_rddata_valid;
    wire [31:0] wrdata, rddata;
    wire        ctl_cmd_ready, ctl_w_ready, ctl_r_valid;
    wire        controller_reset = rst || !init_done;

    wire [0:0]  trainer_tap_valid;
    wire [TAP_BITS-1:0] trainer_tap_value;
    wire trainer_probe_valid, trainer_probe_ready;
    wire        trainer_busy, trainer_trained, trainer_failed;
    wire        trainer_start;
    wire        training_active = TRAIN_ENABLE && init_done &&
                                 !trainer_trained && !trainer_failed;
    wire        training_write_cmd = training_active && !scratch_cmd_sent;
    wire        training_write_data = training_active && !scratch_data_sent;
    wire        trainer_probe_accept = trainer_probe_valid && trainer_probe_ready;
    wire        ctl_cmd_valid_int = controller_reset ? 1'b0 :
                                    training_write_cmd ? 1'b1 :
                                    trainer_probe_accept ? 1'b1 :
                                    (phy_ready && cmd_valid);
    wire        ctl_cmd_we_int = training_write_cmd ? 1'b1 :
                                 trainer_probe_accept ? 1'b0 : cmd_we;
    wire [22:0] ctl_cmd_addr_int = (training_write_cmd || trainer_probe_accept) ?
                                   TRAIN_ADDR : cmd_addr;
    wire [31:0] ctl_w_data_int = training_write_data ? TRAIN_PATTERN : w_data;
    wire [3:0]  ctl_w_we_int = training_write_data ? 4'hf : w_we;
    wire        train_write_cmd_fire = training_write_cmd && ctl_cmd_ready;
    wire        train_write_data_fire = training_write_data && ctl_w_ready;
    wire        phy_probe_mode = training_active && scratch_cmd_sent && scratch_data_sent;
    wire        phy_frame_done;
    wire [0:0]  phy_frame_good;
    wire [31:0] phy_frame_data;
    wire [0:0]  phy_dq_oe, phy_dm, phy_dqs_o, phy_dqs_oe;
    wire        training_ready = !controller_reset && trainer_trained &&
                                 !trainer_failed && !read_error && !dfi_error;

    assign cmd_ready = phy_ready && ctl_cmd_ready;
    assign w_ready = phy_ready && ctl_w_ready;
    assign r_valid = phy_ready && ctl_r_valid &&
                     ((TRAIN_ENABLE == 0) || (!read_error && !dfi_error));
    assign phy_ready = !controller_reset &&
                       ((TRAIN_ENABLE == 0) || training_ready);

    ddr1_controller ctl (
        .sys_clk(sys_clk), .sys_rst(controller_reset),
        .cmd_valid(ctl_cmd_valid_int), .cmd_we(ctl_cmd_we_int),
        .cmd_addr(ctl_cmd_addr_int), .cmd_ready(ctl_cmd_ready),
        .w_data(ctl_w_data_int), .w_we(ctl_w_we_int), .w_ready(ctl_w_ready),
        .r_valid(ctl_r_valid), .r_data(r_data),
        .dfi_address(ctl_address), .dfi_bank(ctl_bank), .dfi_cke(ctl_cke),
        .dfi_cs_n(ctl_cs_n), .dfi_ras_n(ctl_ras_n), .dfi_cas_n(ctl_cas_n), .dfi_we_n(ctl_we_n),
        .dfi_wrdata(wrdata), .dfi_wrdata_mask(wrmask), .dfi_wrdata_en(ctl_wren),
        .dfi_rddata_en(ctl_rden), .dfi_rddata(rddata), .dfi_rddata_valid(dfi_rddata_valid)
    );

    wire [1:0] dfi_rddata_en = controller_reset ? 2'b00 : ctl_rden;
    ddr1_phy #(.DQ_WIDTH(8), .LANES(1), .CAPTURE_SLOTS(4)) phy (
        .sys_clk(sys_clk), .ck(ck), .ck90(ck90), .rst(rst),
        .dfi_address(controller_reset ? {13'd0, init_address} : ctl_address),
        .dfi_bank(controller_reset ? {2'd0, init_bank} : ctl_bank),
        .dfi_cke(controller_reset ? {2{init_cke}} : ctl_cke),
        .dfi_cs_n(controller_reset ? {1'b1, init_cs_n} : ctl_cs_n),
        .dfi_ras_n(controller_reset ? {1'b1, init_opcode[2]} : ctl_ras_n),
        .dfi_cas_n(controller_reset ? {1'b1, init_opcode[1]} : ctl_cas_n),
        .dfi_we_n(controller_reset ? {1'b1, init_opcode[0]} : ctl_we_n),
        .dfi_wrdata(wrdata), .dfi_wrdata_mask(wrmask),
        .dfi_wrdata_en(controller_reset ? 2'b00 : ctl_wren),
        .dfi_rddata_en(dfi_rddata_en),
        .dfi_rddata(rddata), .dfi_rddata_valid(dfi_rddata_valid),
        .pad_ck(pad_ck), .pad_ck_n(pad_ck_n), .a(a), .ba(ba), .cke(cke),
        .cs_n(cs_n), .ras_n(ras_n), .cas_n(cas_n), .we_n(we_n),
        .dq_i(dq_i), .dq_o(dq_o), .dq_oe(phy_dq_oe), .dm(phy_dm),
        .dqs_o(phy_dqs_o), .dqs_oe(phy_dqs_oe), .dqs_capture(dqs_capture),
        .probe_mode(phy_probe_mode), .read_frame_done(phy_frame_done),
        .read_frame_good(phy_frame_good), .read_frame_data(phy_frame_data),
        .read_error(read_error), .dfi_error(dfi_error)
    );
    assign dq_oe = phy_dq_oe[0];
    assign dm = phy_dm[0];
    assign dqs_o = phy_dqs_o[0];
    assign dqs_oe = phy_dqs_oe[0];

    reg scratch_cmd_sent, scratch_data_sent, trainer_start_sent;
    reg probe_pending, native_seen, capture_seen;
    reg [31:0] native_probe_data, capture_probe_data;
    reg [0:0] capture_probe_good;
    reg probe_done_reg;
    reg [0:0] probe_pass_reg;
    wire native_probe_return = probe_pending && ctl_r_valid;
    wire capture_probe_return = probe_pending && phy_frame_done;
    wire [31:0] final_native_data = native_probe_return ? r_data : native_probe_data;
    wire [31:0] final_capture_data = capture_probe_return ? phy_frame_data : capture_probe_data;
    wire [0:0] final_capture_good = capture_probe_return ? phy_frame_good : capture_probe_good;

    assign trainer_start = TRAIN_ENABLE && init_done && scratch_cmd_sent &&
                           scratch_data_sent && !trainer_start_sent;
    assign trainer_probe_ready = TRAIN_ENABLE && init_done && scratch_cmd_sent &&
                                 scratch_data_sent && !probe_pending &&
                                 !controller_reset && ctl_cmd_ready;

    always @(posedge sys_clk or posedge rst) begin
        if (rst) begin
            scratch_cmd_sent <= 1'b0;
            scratch_data_sent <= 1'b0;
            trainer_start_sent <= 1'b0;
            probe_pending <= 1'b0;
            native_seen <= 1'b0;
            capture_seen <= 1'b0;
            native_probe_data <= '0;
            capture_probe_data <= '0;
            capture_probe_good <= '0;
            probe_done_reg <= 1'b0;
            probe_pass_reg <= '0;
        end else begin
            probe_done_reg <= 1'b0;
            if (train_write_cmd_fire) scratch_cmd_sent <= 1'b1;
            if (train_write_data_fire) scratch_data_sent <= 1'b1;
            if (trainer_start) trainer_start_sent <= 1'b1;

            if (trainer_probe_accept) begin
                probe_pending <= 1'b1;
                native_seen <= 1'b0;
                capture_seen <= 1'b0;
            end
            if (probe_pending && ctl_r_valid) begin
                native_seen <= 1'b1;
                native_probe_data <= r_data;
            end
            if (probe_pending && phy_frame_done) begin
                capture_seen <= 1'b1;
                capture_probe_data <= phy_frame_data;
                capture_probe_good <= phy_frame_good;
            end
            if (probe_pending &&
                (native_seen || ctl_r_valid) &&
                (capture_seen || phy_frame_done)) begin
                probe_done_reg <= 1'b1;
                probe_pass_reg[0] <= final_capture_good[0] &&
                                     final_capture_data == TRAIN_PATTERN &&
                                     final_native_data == TRAIN_PATTERN;
                probe_pending <= 1'b0;
            end
        end
    end

    generate
        if (TRAIN_ENABLE != 0) begin : g_trainer
            ddr_dqs_train #(
                .LANES(1), .TAP_BITS(TAP_BITS), .SAMPLES_PER_TAP(2),
                .MIN_WINDOW(2), .TIMEOUT_CYCLES(256)
            ) train (
                .sys_clk(sys_clk), .rst(rst), .start(trainer_start),
                .tap_valid(trainer_tap_valid), .tap_ready(dqs_tap_ready),
                .tap_value(trainer_tap_value), .probe_valid(trainer_probe_valid),
                .probe_ready(trainer_probe_ready), .probe_done(probe_done_reg),
                .probe_pass(probe_pass_reg), .busy(trainer_busy),
                .trained(trainer_trained), .failed(trainer_failed)
            );
            assign dqs_tap_valid = trainer_tap_valid;
            assign dqs_tap_value = trainer_tap_value;
            assign train_busy = trainer_busy;
            assign train_failed = trainer_failed;
        end else begin : g_no_trainer
            assign dqs_tap_valid = 1'b0;
            assign dqs_tap_value = {TAP_BITS{1'b0}};
            assign train_busy = 1'b0;
            assign train_failed = 1'b0;
            assign trainer_tap_valid = 1'b0;
            assign trainer_tap_value = {TAP_BITS{1'b0}};
            assign trainer_probe_valid = 1'b0;
            assign trainer_busy = 1'b0;
            assign trainer_trained = 1'b1;
            assign trainer_failed = 1'b0;
        end
    endgenerate
endmodule
`default_nettype wire
