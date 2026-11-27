// SPDX-License-Identifier: Apache-2.0
// SDF-annotated gate-level closure for sdram_phy_top + sdram_model.
//
// The DUT is the post-PnR netlist.  A small SDR controller drives the DFI
// port, the pin-level model is connected to pad_cmd / pad_dq / pad_ck and
// the test covers read, write, masked write, periodic refresh and the
// READ->WRITE turnaround.  SDF is applied to the DUT instance, so the
// checks below run on the placed clock tree, launch flops and capture path.
//
// Build (see sim/gf180_sdf_top.sh):
//   iverilog -g2012 -gspecify -DSDF_FILE='"path/to.sdf"' ...
`timescale 1ns/1ps
`default_nettype none

`ifndef CL
`define CL 2
`endif

module tb_phy_top_sdf;
    localparam integer AB = 13;
    localparam integer BB = 2;
    localparam integer DB = 8;
    localparam integer RB = 4;
    localparam integer CB = 4;
    localparam integer UB = CB + RB + BB;
    localparam integer CL = `CL;
    localparam integer CMD = AB + BB + 6;

    reg clk = 1'b0;
    reg rst = 1'b1;
    always #5 clk = ~clk;

    reg user_valid = 0, user_we = 0;
    wire user_ready;
    reg [UB-1:0] user_addr = 0;
    reg [DB-1:0] user_wdata = 0;
    reg [DB/8-1:0] user_wmask = 0;
    wire [DB-1:0] user_rdata;
    wire user_rvalid;

    wire [AB-1:0] dfi_a;
    wire [BB-1:0] dfi_ba;
    wire dfi_ras, dfi_cas, dfi_we, dfi_cs, dfi_cke;
    wire dfi_odt, dfi_reset, dfi_act;
    wire [DB-1:0] dfi_wrdata;
    wire dfi_wren;
    wire [DB/8-1:0] dfi_wrmask;
    wire dfi_rden;
    wire [DB-1:0] dfi_rddata;
    wire dfi_rdvalid;
    wire turnaround_busy;
    wire [CMD-1:0] pad_cmd;
    wire [DB-1:0] pad_dq;
    wire pad_ck;
    wire cap_clk, capture_ready, pad_ready, contention, ck_active;
    wire latency_error;

    wire [AB-1:0] a;
    wire [BB-1:0] ba;
    wire ras_n, cas_n, we_n, cs_n, cke;
    wire [DB/8-1:0] dm;
    wire fault;
    wire [2:0] fault_code;

    integer errors = 0;
    integer guard;

    // Debug: every command the model actually samples.
    always @(posedge pad_ck) begin
        if (cs_n === 1'b0)
            $display("  [%0t] CMD ras=%b cas=%b we=%b a=%h ba=%h dm=%b dq=%h",
                     $realtime, ras_n, cas_n, we_n, a, ba, dm, pad_dq);
    end

    `define CHECK(cond) \
        if (!(cond)) begin \
            $display("FAIL line %0d: %s", `__LINE__, `"cond`"); \
            errors = errors + 1; \
        end

    sdr_ctrl #(
        .ADDR_BITS(AB), .BANK_BITS(BB), .DATA_BITS(DB),
        .ROW_BITS(RB), .COL_BITS(CB), .CL(CL),
        .T_RCD(2), .T_RP(2), .T_RFC(7), .T_REFI(40)
    ) ctrl (
        .clk(clk), .rst(rst),
        .user_valid(user_valid), .user_ready(user_ready), .user_we(user_we),
        .user_addr(user_addr), .user_wdata(user_wdata),
        .user_wmask(user_wmask),
        .user_rdata(user_rdata), .user_rvalid(user_rvalid),
        .dfi_address(dfi_a), .dfi_bank(dfi_ba),
        .dfi_ras_n(dfi_ras), .dfi_cas_n(dfi_cas), .dfi_we_n(dfi_we),
        .dfi_cs_n(dfi_cs), .dfi_cke(dfi_cke),
        .dfi_odt(dfi_odt), .dfi_reset_n(dfi_reset), .dfi_act_n(dfi_act),
        .dfi_wrdata(dfi_wrdata), .dfi_wrdata_en(dfi_wren),
        .dfi_wrdata_mask(dfi_wrmask), .dfi_rddata_en(dfi_rden),
        .dfi_rddata(dfi_rddata), .dfi_rddata_valid(dfi_rdvalid),
        .phy_turnaround_busy(turnaround_busy)
    );

    wire [DB-1:0] dq_core_o;
    wire          dq_core_oe;
    wire [DB-1:0] dq_core_i;

    // DUT is the core harden (netlist or RTL).  The pad ring is outside it;
    // the behavioral pad below restores the pin-level bidirectional bus so
    // the same TB runs on RTL and on the post-PnR netlist.
    sdram_phy_core dut (
        .clk(clk), .rst(rst),
        .dfi_address(dfi_a), .dfi_bank(dfi_ba),
        .dfi_ras_n(dfi_ras), .dfi_cas_n(dfi_cas), .dfi_we_n(dfi_we),
        .dfi_cs_n(dfi_cs), .dfi_cke(dfi_cke),
        .dfi_odt(dfi_odt), .dfi_reset_n(dfi_reset), .dfi_act_n(dfi_act),
        .dfi_wrdata(dfi_wrdata), .dfi_wrdata_en(dfi_wren),
        .dfi_wrdata_mask(dfi_wrmask), .dfi_rddata_en(dfi_rden),
        .dfi_rddata(dfi_rddata), .dfi_rddata_valid(dfi_rdvalid),
        .io_power_ok(1'b1), .pad_config(8'b0),
        .phase_clks(4'b0), .phase_clocks_ready(1'b0),
        .phase_sel(2'b0), .phase_sel_valid(1'b0),
        .ck_phase_clks(4'b0), .ck_phase_clocks_ready(1'b0),
        .ck_phase_sel(2'b0),
        .cmd_o(pad_cmd), .dq_o(dq_core_o), .dq_oe(dq_core_oe),
        .dq_i(dq_core_i), .ck_o(pad_ck),
        .cap_clk(cap_clk), .capture_ready(capture_ready),
        .turnaround_busy(turnaround_busy), .pad_ready(pad_ready),
        .contention(contention), .ck_active(ck_active),
        .read_latency_error(latency_error)
    );

    pad_cell_generic u_dq (
        .core_out(dq_core_o), .core_oe(dq_core_oe),
        .core_in(dq_core_i), .pad(pad_dq),
        .power_ok(1'b1), .driving(), .contention()
    );

`ifdef SDF_FILE
    initial $sdf_annotate(`SDF_FILE, dut);
`endif

    assign {a, ba, ras_n, cas_n, we_n, cs_n, cke, dm} = pad_cmd;

    sdram_model #(
        .ADDR_BITS(AB), .BANK_BITS(BB), .DATA_BITS(DB),
        .ROW_BITS(RB), .COL_BITS(CB)
    ) model (
        .ck(pad_ck), .cke(cke), .cs_n(cs_n), .ras_n(ras_n),
        .cas_n(cas_n), .we_n(we_n), .ba(ba), .a(a), .dm(dm),
        .dq(pad_dq), .fault(fault), .fault_code(fault_code)
    );

    task automatic write_word;
        input [BB-1:0] bank;
        input [RB-1:0] row;
        input [CB-1:0] col;
        input [DB-1:0] data;
        input [DB/8-1:0] mask;
        begin
            @(negedge clk);
            user_we = 1; user_addr = {bank,row,col}; user_wdata = data;
            user_wmask = mask; user_valid = 1;
            guard = 0;
            while (!(user_ready === 1'b1) && guard < 40) begin
                @(posedge clk); #1; guard = guard + 1;
            end
            `CHECK(user_ready === 1'b1)
            @(negedge clk); user_valid = 0;
        end
    endtask

    task automatic read_word;
        input [BB-1:0] bank;
        input [RB-1:0] row;
        input [CB-1:0] col;
        input [DB-1:0] expected;
        begin
            @(negedge clk);
            user_we = 0; user_addr = {bank,row,col}; user_valid = 1;
            guard = 0;
            while (!(user_ready === 1'b1) && guard < 40) begin
                @(posedge clk); #1; guard = guard + 1;
            end
            `CHECK(user_ready === 1'b1)
            @(negedge clk); user_valid = 0;
            guard = 0;
            while (!(user_rvalid === 1'b1) && guard < 40) begin
                @(posedge clk); #1; guard = guard + 1;
            end
            `CHECK(user_rvalid === 1'b1)
            if (user_rdata !== expected)
                $display("  read b=%0d r=%0d c=%0d exp=%h got=%h",
                         bank, row, col, expected, user_rdata);
            `CHECK(user_rdata === expected)
        end
    endtask

    task automatic read_issue;
        input [BB-1:0] bank;
        input [RB-1:0] row;
        input [CB-1:0] col;
        begin
            @(negedge clk);
            user_we = 0; user_addr = {bank,row,col}; user_valid = 1;
            guard = 0;
            while (!(user_ready === 1'b1) && guard < 40) begin
                @(posedge clk); #1; guard = guard + 1;
            end
            `CHECK(user_ready === 1'b1)
            @(negedge clk); user_valid = 0;
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        @(negedge clk); rst = 0;
        guard = 0;
        while (!(user_ready === 1'b1) && guard < 400) begin
            @(posedge clk); #1; guard = guard + 1;
        end
        `CHECK(user_ready === 1'b1)
        `CHECK(fault === 1'b0)

        write_word(2'd0, 4'd1, 4'd3, 8'hA5, 1'b0);
        read_word (2'd0, 4'd1, 4'd3, 8'hA5);
        write_word(2'd0, 4'd1, 4'd4, 8'h5A, 1'b0);
        read_word (2'd0, 4'd1, 4'd4, 8'h5A);
        write_word(2'd0, 4'd1, 4'd3, 8'h3C, 1'b1); // masked: must not change
        read_word (2'd0, 4'd1, 4'd3, 8'hA5);

        // Two periodic refreshes (T_REFI = 40) must not disturb data.
        guard = 0;
        while (guard < 120) begin @(posedge clk); #1; guard = guard + 1; end
        read_word (2'd0, 4'd1, 4'd3, 8'hA5);

        // READ immediately followed by WRITE: turnaround_busy must hold the
        // write until the read tail is over, and the model must see it.
        read_issue(2'd0, 4'd1, 4'd4);
        write_word(2'd0, 4'd1, 4'd4, 8'hC3, 1'b0);
        read_word (2'd0, 4'd1, 4'd4, 8'hC3);

        `CHECK(fault === 1'b0)
        `CHECK(latency_error === 1'b0)
        `CHECK(contention === 1'b0)
        repeat (4) @(negedge clk);
        if (errors == 0) $display("PASS phy_top_sdf speed=%s",
                                  `ifdef SDF_FILE `SDF_FILE `else "none" `endif);
        else $fatal(1, "FAIL phy_top_sdf errors=%0d", errors);
        $finish;
    end

    initial begin
        #200000;
        $display("FAIL phy_top_sdf timeout");
        $fatal(1);
    end
endmodule
`default_nettype wire
