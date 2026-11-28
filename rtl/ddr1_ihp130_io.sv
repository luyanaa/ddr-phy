// SPDX-License-Identifier: Apache-2.0
// DDR1 x8 top with IHP130 SSTL-2 pad boundary.
//
// This wrapper puts the behavioral IHP130 DQ pad model around every signal
// that leaves the digital core. It is a co-simulation boundary, not the final
// pad ring: DQ/DQS use the bidirectional lane model, CA/CK/DM use the same
// lane with OE tied high. Replace the models with the extracted pad macros
// for physical signoff.
`default_nettype none
module ddr1_ihp130_io #(
    parameter integer TRAIN_ENABLE = 0,
    parameter integer TAP_BITS = 7,
    parameter [22:0] TRAIN_ADDR = 23'h7fffff,
    parameter integer PAD_TX_PS = 1300,
    parameter integer PAD_RX_PS = 1300,
    parameter integer PAD_OE_PS = 1500,
    // Kept for compatibility; the ideal #delay is no longer used.
    parameter integer DQS_CAPTURE_DELAY_PS = 1500,
    parameter integer DQS_TAP_CODE = 9,
    parameter integer DQS_LINE_CELL_PS = 35,
    parameter integer DQS_LINE_IMPL = 0,
    // Per-lane overrides. -1 keeps the legacy single PAD_* value.
    parameter integer DQ_TX_PS = -1,
    parameter integer DQ_RX_PS = -1,
    parameter integer DQ_OE_PS = -1,
    parameter integer DQS_TX_PS = -1,
    parameter integer DQS_RX_PS = -1,
    parameter integer DQS_OE_PS = -1
) (
    input  wire        sys_clk, ck, ck90, rst,
    output wire        init_done, read_error, dfi_error,
    output wire        phy_ready, train_busy, train_failed,
    input  wire [0:0]  dqs_tap_ready,
    output wire [0:0]  dqs_tap_valid,
    output wire [TAP_BITS-1:0] dqs_tap_value,

    input  wire        cmd_valid, cmd_we,
    input  wire [22:0] cmd_addr,
    output wire        cmd_ready,
    input  wire [31:0] w_data,
    input  wire [3:0]  w_we,
    output wire        w_ready,
    output wire        r_valid,
    output wire [31:0] r_data,

    inout  wire [7:0]  PAD_DQ,
    inout  wire        PAD_DQS,
    output wire        PAD_DM,
    output wire        PAD_CK,
    output wire        PAD_CK_N,
    output wire [12:0] PAD_A,
    output wire [1:0]  PAD_BA,
    output wire        PAD_CKE,
    output wire        PAD_CS_N,
    output wire        PAD_RAS_N,
    output wire        PAD_CAS_N,
    output wire        PAD_WE_N,
    input  wire        VREF,
    input  wire        PU_OK,
    output wire        DQ_OE,
    output wire        DQS_OE,
    output wire        PAD_DQS_OE
);
    localparam integer DQ_TX_DLY = (DQ_TX_PS < 0) ? PAD_TX_PS : DQ_TX_PS;
    localparam integer DQ_RX_DLY = (DQ_RX_PS < 0) ? PAD_RX_PS : DQ_RX_PS;
    localparam integer DQ_OE_DLY = (DQ_OE_PS < 0) ? PAD_OE_PS : DQ_OE_PS;
    localparam integer DQS_TX_DLY = (DQS_TX_PS < 0) ? PAD_TX_PS : DQS_TX_PS;
    localparam integer DQS_RX_DLY = (DQS_RX_PS < 0) ? PAD_RX_PS : DQS_RX_PS;
    localparam integer DQS_OE_DLY = (DQS_OE_PS < 0) ? PAD_OE_PS : DQS_OE_PS;

    wire [12:0] a_int;
    wire [1:0]  ba_int;
    wire        cke_int, cs_n_int, ras_n_int, cas_n_int, we_n_int;
    wire        pad_ck_int, pad_ck_n_int;
    wire        dm_int, dqs_o_int, dqs_oe_int;
    wire [7:0]  dq_o_int, dq_i_int;
    wire        dq_oe_int, dqs_capture_int, dqs_pad_i;
    wire        read_capture_busy_int;
    wire        dqs_tap_ready_line;
    wire        dqs_tap_error;

    ddr1_top #(
        .TRAIN_ENABLE(TRAIN_ENABLE), .TAP_BITS(TAP_BITS),
        .TRAIN_ADDR(TRAIN_ADDR), .DQS_TAP_CODE(DQS_TAP_CODE)
    ) u_top (
        .sys_clk(sys_clk), .ck(ck), .ck90(ck90), .rst(rst),
        .dqs_capture(dqs_capture_int),
        .init_done(init_done), .read_error(read_error), .dfi_error(dfi_error),
        .phy_ready(phy_ready), .train_busy(train_busy), .train_failed(train_failed),
        .dqs_tap_ready(dqs_tap_ready_line), .dqs_tap_valid(dqs_tap_valid),
        .dqs_tap_value(dqs_tap_value), .read_capture_busy(read_capture_busy_int),
        .cmd_valid(cmd_valid), .cmd_we(cmd_we), .cmd_addr(cmd_addr),
        .cmd_ready(cmd_ready), .w_data(w_data), .w_we(w_we),
        .w_ready(w_ready), .r_valid(r_valid), .r_data(r_data),
        .pad_ck(pad_ck_int), .pad_ck_n(pad_ck_n_int),
        .a(a_int), .ba(ba_int), .cke(cke_int), .cs_n(cs_n_int),
        .ras_n(ras_n_int), .cas_n(cas_n_int), .we_n(we_n_int),
        .dq_i(dq_i_int), .dq_o(dq_o_int), .dq_oe(dq_oe_int),
        .dm(dm_int), .dqs_o(dqs_o_int), .dqs_oe(dqs_oe_int)
    );

    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : g_dq_pad
            ihp130_sstl2_dq_model #(
                .TX_PS(DQ_TX_DLY), .RX_PS(DQ_RX_DLY), .OE_PS(DQ_OE_DLY)
            ) dq_pad (
                .PAD(PAD_DQ[i]), .DQ_O(dq_o_int[i]), .DQ_OE(dq_oe_int),
                .VREF(VREF), .PU_OK(PU_OK), .DQ_I(dq_i_int[i])
            );
        end
    endgenerate

    ihp130_sstl2_dq_model #(
        .TX_PS(DQS_TX_DLY), .RX_PS(DQS_RX_DLY), .OE_PS(DQS_OE_DLY)
    ) dqs_pad (
        .PAD(PAD_DQS), .DQ_O(dqs_o_int), .DQ_OE(dqs_oe_int),
        .VREF(VREF), .PU_OK(PU_OK), .DQ_I(dqs_pad_i),
        .PAD_OE(PAD_DQS_OE)
    );

    ihp130_sstl2_dq_model #(
        .TX_PS(PAD_TX_PS), .RX_PS(PAD_RX_PS), .OE_PS(PAD_OE_PS)
    ) dm_pad (
        .PAD(PAD_DM), .DQ_O(dm_int), .DQ_OE(1'b1),
        .VREF(VREF), .PU_OK(PU_OK), .DQ_I()
    );

    ihp130_sstl2_dq_model #(
        .TX_PS(PAD_TX_PS), .RX_PS(PAD_RX_PS), .OE_PS(PAD_OE_PS)
    ) ck_pad (
        .PAD(PAD_CK), .DQ_O(pad_ck_int), .DQ_OE(1'b1),
        .VREF(VREF), .PU_OK(PU_OK), .DQ_I()
    );

    ihp130_sstl2_dq_model #(
        .TX_PS(PAD_TX_PS), .RX_PS(PAD_RX_PS), .OE_PS(PAD_OE_PS)
    ) ck_n_pad (
        .PAD(PAD_CK_N), .DQ_O(pad_ck_n_int), .DQ_OE(1'b1),
        .VREF(VREF), .PU_OK(PU_OK), .DQ_I()
    );

    generate
        for (i = 0; i < 13; i = i + 1) begin : g_a_pad
            ihp130_sstl2_dq_model #(
                .TX_PS(PAD_TX_PS), .RX_PS(PAD_RX_PS), .OE_PS(PAD_OE_PS)
            ) a_pad (
                .PAD(PAD_A[i]), .DQ_O(a_int[i]), .DQ_OE(1'b1),
                .VREF(VREF), .PU_OK(PU_OK), .DQ_I()
            );
        end
        for (i = 0; i < 2; i = i + 1) begin : g_ba_pad
            ihp130_sstl2_dq_model #(
                .TX_PS(PAD_TX_PS), .RX_PS(PAD_RX_PS), .OE_PS(PAD_OE_PS)
            ) ba_pad (
                .PAD(PAD_BA[i]), .DQ_O(ba_int[i]), .DQ_OE(1'b1),
                .VREF(VREF), .PU_OK(PU_OK), .DQ_I()
            );
        end
    endgenerate

    ihp130_sstl2_dq_model #(
        .TX_PS(PAD_TX_PS), .RX_PS(PAD_RX_PS), .OE_PS(PAD_OE_PS)
    ) cke_pad (
        .PAD(PAD_CKE), .DQ_O(cke_int), .DQ_OE(1'b1),
        .VREF(VREF), .PU_OK(PU_OK), .DQ_I()
    );
    ihp130_sstl2_dq_model #(
        .TX_PS(PAD_TX_PS), .RX_PS(PAD_RX_PS), .OE_PS(PAD_OE_PS)
    ) cs_pad (
        .PAD(PAD_CS_N), .DQ_O(cs_n_int), .DQ_OE(1'b1),
        .VREF(VREF), .PU_OK(PU_OK), .DQ_I()
    );
    ihp130_sstl2_dq_model #(
        .TX_PS(PAD_TX_PS), .RX_PS(PAD_RX_PS), .OE_PS(PAD_OE_PS)
    ) ras_pad (
        .PAD(PAD_RAS_N), .DQ_O(ras_n_int), .DQ_OE(1'b1),
        .VREF(VREF), .PU_OK(PU_OK), .DQ_I()
    );
    ihp130_sstl2_dq_model #(
        .TX_PS(PAD_TX_PS), .RX_PS(PAD_RX_PS), .OE_PS(PAD_OE_PS)
    ) cas_pad (
        .PAD(PAD_CAS_N), .DQ_O(cas_n_int), .DQ_OE(1'b1),
        .VREF(VREF), .PU_OK(PU_OK), .DQ_I()
    );
    ihp130_sstl2_dq_model #(
        .TX_PS(PAD_TX_PS), .RX_PS(PAD_RX_PS), .OE_PS(PAD_OE_PS)
    ) we_pad (
        .PAD(PAD_WE_N), .DQ_O(we_n_int), .DQ_OE(1'b1),
        .VREF(VREF), .PU_OK(PU_OK), .DQ_I()
    );

    // Repaired adpll_gen DDR1 DQS line: 128 x 2 fine cells, 7-bit code,
    // output settle gate.  The old ideal #delay is removed.  update_idle is
    // asserted only when no read burst is in flight and neither DQ nor DQS
    // is being driven.
    ddr_dqs_delay_adpll #(
        .LANES(1), .TAP_BITS(TAP_BITS), .FIRST_STAGE(0), .STEP_CELLS(1),
        .SETTLE_CYCLES(2), .CELLS_PER_TAP(2), .CELL_PS(DQS_LINE_CELL_PS),
        .LINE_NTAPS(128), .LINE_IMPL(DQS_LINE_IMPL)
    ) u_dqs_delay (
        .sys_clk(sys_clk), .rst(rst),
        .update_idle(!read_capture_busy_int && !dqs_oe_int && !dq_oe_int),
        .dqs_in(dqs_pad_i), .dqs_capture(dqs_capture_int),
        .tap_valid(dqs_tap_valid), .tap_value(dqs_tap_value),
        .tap_ready(dqs_tap_ready_line), .tap_error(dqs_tap_error)
    );

    assign DQ_OE  = dq_oe_int;
    assign DQS_OE = dqs_oe_int;
endmodule
`default_nettype wire
