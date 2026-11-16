// SPDX-License-Identifier: Apache-2.0
// Optional Micron SDR reference-model differential test.
//
// The model is NOT committed (third_party/reference/mt48lc16m16a2.v is
// gitignored). It is Micron -7E / PC133 CL2, not the project's -75 CL2/CL3
// contract; a pass here is behavioural evidence only, not timing signoff.
//
// Two PHYs receive the same DFI traffic: one drives the in-repo
// sim/sdram_model.sv, the other drives the Micron mt48lc16m16a2 (x16, lower
// byte used with DQM[0]). Read data and valid are compared cycle by cycle.

`timescale 1ns/1ps
`default_nettype none

module tb_micron_diff;
    localparam integer AB = 13;
    localparam integer BB = 2;
    localparam integer DB = 8;
    localparam integer RB = 4;
    localparam integer CB = 4;
    localparam integer UB = CB + RB + BB;

    reg clk = 1'b0;
    reg rst = 1'b1;
    always #5 clk = ~clk;

    reg user_valid = 0, user_we = 0;
    wire user_ready;
    reg [UB-1:0] user_addr = 0;
    reg [DB-1:0] user_wdata = 0;
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
    wire [DB-1:0] dfi_rddata_own, dfi_rddata_ref;
    wire dfi_rdvalid_own, dfi_rdvalid_ref;

    wire [DB-1:0] dq_own, dq_ref_lo;
    wire [15:0] dq_ref;
    wire [DB-1:0] dq_o_own, dq_i_own;
    wire dq_oe_own;
    wire [AB-1:0] a_own;
    wire [BB-1:0] ba_own;
    wire ras_own, cas_own, we_own, cs_own, cke_own, dm_own;
    wire [DB-1:0] dq_o_ref, dq_i_ref;
    wire dq_oe_ref;
    wire fault_own;
    wire [2:0] fault_code_own;

    integer errors = 0;
    integer guard;

    `define CHECK(cond) \
        if (!(cond)) begin \
            $display("FAIL line %0d: %s", `__LINE__, `"cond`"); \
            errors = errors + 1; \
        end

    sdr_ctrl #(
        .ADDR_BITS(AB), .BANK_BITS(BB), .DATA_BITS(DB),
        .ROW_BITS(RB), .COL_BITS(CB), .CL(2),
        .T_RCD(2), .T_RP(2), .T_RFC(7)
    ) ctrl (
        .clk(clk), .rst(rst),
        .user_valid(user_valid), .user_ready(user_ready), .user_we(user_we),
        .user_addr(user_addr), .user_wdata(user_wdata),
        .user_rdata(user_rdata), .user_rvalid(user_rvalid),
        .dfi_address(dfi_a), .dfi_bank(dfi_ba),
        .dfi_ras_n(dfi_ras), .dfi_cas_n(dfi_cas), .dfi_we_n(dfi_we),
        .dfi_cs_n(dfi_cs), .dfi_cke(dfi_cke),
        .dfi_odt(dfi_odt), .dfi_reset_n(dfi_reset), .dfi_act_n(dfi_act),
        .dfi_wrdata(dfi_wrdata), .dfi_wrdata_en(dfi_wren),
        .dfi_wrdata_mask(dfi_wrmask), .dfi_rddata_en(dfi_rden),
        .dfi_rddata(dfi_rddata_own), .dfi_rddata_valid(dfi_rdvalid_own),
        .phy_turnaround_busy(1'b0)
    );

    sdr_phy #(.ADDR_BITS(AB), .BANK_BITS(BB), .DATA_BITS(DB), .RANKS(1), .CL(2)) phy_own (
        .clk(clk), .rst(rst),
        .dfi_address(dfi_a), .dfi_bank(dfi_ba),
        .dfi_ras_n(dfi_ras), .dfi_cas_n(dfi_cas), .dfi_we_n(dfi_we),
        .dfi_cs_n(dfi_cs), .dfi_cke(dfi_cke),
        .dfi_odt(dfi_odt), .dfi_reset_n(dfi_reset), .dfi_act_n(dfi_act),
        .dfi_wrdata(dfi_wrdata), .dfi_wrdata_en(dfi_wren),
        .dfi_wrdata_mask(dfi_wrmask), .dfi_rddata_en(dfi_rden),
        .dfi_rddata(dfi_rddata_own), .dfi_rddata_valid(dfi_rdvalid_own),
        .a(a_own), .ba(ba_own), .ras_n(ras_own), .cas_n(cas_own),
        .we_n(we_own), .cs_n(cs_own), .cke(cke_own), .dm(dm_own),
        .dq_o(dq_o_own), .dq_oe(dq_oe_own), .dq_i(dq_i_own), .ck()
    );

    // The command and DQ pins are shared; only the data path is duplicated.
    assign dq_own = dq_oe_own ? dq_o_own : {DB{1'bz}};
    assign dq_i_own = dq_own;

    sdram_model #(
        .ADDR_BITS(AB), .BANK_BITS(BB), .DATA_BITS(DB),
        .ROW_BITS(RB), .COL_BITS(CB)
    ) own (
        .ck(clk), .cke(cke_own), .cs_n(cs_own), .ras_n(ras_own),
        .cas_n(cas_own), .we_n(we_own), .ba(ba_own), .a(a_own),
        .dm(dm_own), .dq(dq_own), .fault(fault_own),
        .fault_code(fault_code_own)
    );

    sdr_phy #(.ADDR_BITS(AB), .BANK_BITS(BB), .DATA_BITS(DB), .RANKS(1), .CL(2)) phy_ref (
        .clk(clk), .rst(rst),
        .dfi_address(dfi_a), .dfi_bank(dfi_ba),
        .dfi_ras_n(dfi_ras), .dfi_cas_n(dfi_cas), .dfi_we_n(dfi_we),
        .dfi_cs_n(dfi_cs), .dfi_cke(dfi_cke),
        .dfi_odt(dfi_odt), .dfi_reset_n(dfi_reset), .dfi_act_n(dfi_act),
        .dfi_wrdata(dfi_wrdata), .dfi_wrdata_en(dfi_wren),
        .dfi_wrdata_mask(dfi_wrmask), .dfi_rddata_en(dfi_rden),
        .dfi_rddata(dfi_rddata_ref), .dfi_rddata_valid(dfi_rdvalid_ref),
        .a(), .ba(), .ras_n(), .cas_n(), .we_n(), .cs_n(), .cke(), .dm(),
        .dq_o(dq_o_ref), .dq_oe(dq_oe_ref), .dq_i(dq_i_ref), .ck()
    );

    assign dq_ref[7:0]  = dq_oe_ref ? dq_o_ref : 8'bz;
    assign dq_ref[15:8] = 8'bz;
    assign dq_i_ref = dq_ref[7:0];

    mt48lc16m16a2 micron (
        .Dq(dq_ref), .Addr(a_own), .Ba(ba_own), .Clk(clk),
        .Cke(cke_own), .Cs_n(cs_own), .Ras_n(ras_own), .Cas_n(cas_own),
        .We_n(we_own), .Dqm({1'b0, dm_own})
    );

    // Cycle-by-cycle differential check.
    always @(posedge clk) begin
        #1;
        if (!rst && (dfi_rdvalid_own !== dfi_rdvalid_ref)) begin
            $display("FAIL micron_diff: valid mismatch own=%b ref=%b", dfi_rdvalid_own, dfi_rdvalid_ref);
            errors = errors + 1;
        end
        if (!rst && dfi_rdvalid_own && dfi_rdvalid_ref &&
            (dfi_rddata_own !== dfi_rddata_ref)) begin
            $display("FAIL micron_diff: data mismatch own=%h ref=%h",
                     dfi_rddata_own, dfi_rddata_ref);
            errors = errors + 1;
        end
    end

    task automatic write_word;
        input [BB-1:0] bank;
        input [RB-1:0] row;
        input [CB-1:0] col;
        input [DB-1:0] data;
        begin
            @(negedge clk);
            user_we = 1; user_addr = {bank,row,col}; user_wdata = data; user_valid = 1;
            guard = 0;
            while (!(user_ready === 1'b1) && guard < 40) begin @(posedge clk); #1; guard = guard + 1; end
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
            while (!(user_ready === 1'b1) && guard < 40) begin @(posedge clk); #1; guard = guard + 1; end
            `CHECK(user_ready === 1'b1)
            @(negedge clk); user_valid = 0;
            guard = 0;
            while (!(user_rvalid === 1'b1) && guard < 40) begin @(posedge clk); #1; guard = guard + 1; end
            `CHECK(user_rvalid === 1'b1)
            `CHECK(user_rdata === expected)
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        @(negedge clk); rst = 0;
        guard = 0;
        while (!(user_ready === 1'b1) && guard < 400) begin @(posedge clk); #1; guard = guard + 1; end
        `CHECK(user_ready === 1'b1)
        `CHECK(fault_own === 1'b0)

        write_word(2'd0, 4'd1, 4'd3, 8'hA5);
        read_word (2'd0, 4'd1, 4'd3, 8'hA5);
        write_word(2'd0, 4'd1, 4'd4, 8'h5A);
        read_word (2'd0, 4'd1, 4'd4, 8'h5A);
        read_word (2'd0, 4'd1, 4'd3, 8'hA5);
        `CHECK(fault_own === 1'b0)

        #20;
        `ifdef MUTATE
        errors = errors + 1;
        $display("MUTATION: injected failure for exit-code test");
        `endif
        if (errors == 0) $display("PASS micron_diff");
        else             $fatal(1, "FAIL micron_diff errors=%0d", errors);
        $finish;
    end

    initial begin
        #200000;
        $display("FAIL micron_diff timeout");
        $fatal(1);
    end
endmodule

`default_nettype wire
