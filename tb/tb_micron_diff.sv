// SPDX-License-Identifier: Apache-2.0
// Optional Micron SDR reference-model differential test.
//
// The model is NOT committed (third_party/reference/mt48lc16m16a2.v is
// gitignored). It is Micron -7E / PC133 CL2, not the project's -75 CL2/CL3
// contract; a pass here is behavioural evidence only, not timing signoff.
//
// Compare the bare PHY with the in-tree model to the integrated PHY with
// the Micron mt48lc16m16a2 (lower byte). Align the different DFI latencies.

`timescale 1ns/1ps
`default_nettype none

`ifndef CL
`define CL 2
`endif

module tb_micron_diff;
    localparam integer AB = 13;
    localparam integer CL = `CL;
    localparam integer BB = 2;
    localparam integer DB = 8;
    localparam integer RB = 4;
    localparam integer CB = 4;
    localparam integer UB = CB + RB + BB;
    localparam integer REF_PIPE = 3; // (CL + 4) - (CL + 1)

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
    wire [DB-1:0] dfi_rddata_own, dfi_rddata_ref;
    wire dfi_rdvalid_own, dfi_rdvalid_ref;

    wire [DB-1:0] dq_own;
    wire [15:0] dq_ref;
    wire [DB-1:0] dq_o_own, dq_i_own;
    wire dq_oe_own;
    wire [AB-1:0] a_own;
    wire [BB-1:0] ba_own;
    wire ras_own, cas_own, we_own, cs_own, cke_own, dm_own;
    wire [AB+BB+6-1:0] pad_cmd_ref;
    wire pad_ck_ref, ref_error, ref_contention;
    wire [AB-1:0] a_ref;
    wire [BB-1:0] ba_ref;
    wire ras_ref, cas_ref, we_ref, cs_ref, cke_ref, dm_ref;
    wire fault_own;
    wire [2:0] fault_code_own;
    wire turnaround_busy;
    reg [REF_PIPE-1:0] expected_valid = '0;
    reg [DB-1:0] expected_data [0:REF_PIPE-1];

    integer errors = 0;
    integer guard;

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
        .dfi_rddata(dfi_rddata_own), .dfi_rddata_valid(dfi_rdvalid_own),
        .phy_turnaround_busy(turnaround_busy)
    );

    sdr_phy #(.ADDR_BITS(AB), .BANK_BITS(BB), .DATA_BITS(DB), .RANKS(1), .CL(CL)) phy_own (
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

    sdram_phy_top #(.ADDR_BITS(AB), .BANK_BITS(BB), .DATA_BITS(DB), .RANKS(1), .CL(CL)) phy_ref (
        .clk(clk), .rst(rst),
        .dfi_address(dfi_a), .dfi_bank(dfi_ba),
        .dfi_ras_n(dfi_ras), .dfi_cas_n(dfi_cas), .dfi_we_n(dfi_we),
        .dfi_cs_n(dfi_cs), .dfi_cke(dfi_cke),
        .dfi_odt(dfi_odt), .dfi_reset_n(dfi_reset), .dfi_act_n(dfi_act),
        .dfi_wrdata(dfi_wrdata), .dfi_wrdata_en(dfi_wren),
        .dfi_wrdata_mask(dfi_wrmask), .dfi_rddata_en(dfi_rden),
        .dfi_rddata(dfi_rddata_ref), .dfi_rddata_valid(dfi_rdvalid_ref),
        .io_power_ok(1'b1), .pad_config(8'b0),
        .phase_clks(4'b0), .phase_clocks_ready(1'b0),
        .phase_sel(2'b0), .phase_sel_valid(1'b0),
        .ck_phase_clks(4'b0), .ck_phase_clocks_ready(1'b0), .ck_phase_sel(2'b0),
        .pad_cmd(pad_cmd_ref), .pad_dq(dq_ref[7:0]), .pad_ck(pad_ck_ref),
        .turnaround_busy(turnaround_busy), .read_latency_error(ref_error),
        .contention(ref_contention)
    );

    assign dq_ref[15:8] = 8'bz;
    assign {a_ref, ba_ref, ras_ref, cas_ref, we_ref, cs_ref, cke_ref, dm_ref} = pad_cmd_ref;

    mt48lc16m16a2 micron (
        .Dq(dq_ref), .Addr(a_ref), .Ba(ba_ref), .Clk(pad_ck_ref),
        .Cke(cke_ref), .Cs_n(cs_ref), .Ras_n(ras_ref), .Cas_n(cas_ref),
        .We_n(we_ref), .Dqm({1'b0, dm_ref})
    );

    always @(posedge clk) begin
        expected_valid <= rst ? '0 : {expected_valid[REF_PIPE-2:0], dfi_rdvalid_own};
        expected_data[0] <= dfi_rddata_own;
        for (integer i = 1; i < REF_PIPE; i = i + 1)
            expected_data[i] <= expected_data[i-1];

        #1;
        if (!rst) begin
            `CHECK(ref_error === 1'b0)
            `CHECK(ref_contention === 1'b0)
            if (dfi_rdvalid_ref !== expected_valid[REF_PIPE-1]) begin
                $display("FAIL micron_diff: valid mismatch expected=%b ref=%b",
                         expected_valid[REF_PIPE-1], dfi_rdvalid_ref);
                errors = errors + 1;
            end
            if (expected_valid[REF_PIPE-1] && dfi_rddata_ref !== expected_data[REF_PIPE-1]) begin
                $display("FAIL micron_diff: data mismatch expected=%h ref=%h",
                         expected_data[REF_PIPE-1], dfi_rddata_ref);
                errors = errors + 1;
            end
        end
    end

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

    task automatic read_issue;
        input [BB-1:0] bank;
        input [RB-1:0] row;
        input [CB-1:0] col;
        begin
            @(negedge clk);
            user_we = 0; user_addr = {bank,row,col}; user_valid = 1;
            guard = 0;
            while (!(user_ready === 1'b1) && guard < 40) begin @(posedge clk); #1; guard = guard + 1; end
            `CHECK(user_ready === 1'b1)
            @(negedge clk); user_valid = 0;
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        @(negedge clk); rst = 0;
        guard = 0;
        while (!(user_ready === 1'b1) && guard < 400) begin @(posedge clk); #1; guard = guard + 1; end
        `CHECK(user_ready === 1'b1)
        `CHECK(fault_own === 1'b0)

        write_word(2'd0, 4'd1, 4'd3, 8'hA5, 1'b0);
        read_word (2'd0, 4'd1, 4'd3, 8'hA5);
        write_word(2'd0, 4'd1, 4'd4, 8'h5A, 1'b0);
        read_word (2'd0, 4'd1, 4'd4, 8'h5A);
        write_word(2'd0, 4'd1, 4'd3, 8'h5A, 1'b1); // masked write must not change
        read_word (2'd0, 4'd1, 4'd3, 8'hA5);

        // Let at least two periodic refreshes elapse; the controller closes
        // banks first. The Micron model's tRFC checks are caught by the
        // script's ERROR grep.
        guard = 0;
        while (guard < 120) begin @(posedge clk); #1; guard = guard + 1; end
        read_word (2'd0, 4'd1, 4'd3, 8'hA5);

        // Back-to-back READ then WRITE: the controller must hold the write
        // until turnaround_busy clears, and both models must see the write.
        read_issue(2'd0, 4'd1, 4'd4);
        write_word(2'd0, 4'd1, 4'd4, 8'hC3, 1'b0);
        read_word (2'd0, 4'd1, 4'd4, 8'hC3);
        `CHECK(fault_own === 1'b0)

        repeat (REF_PIPE + 1) @(negedge clk);
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
