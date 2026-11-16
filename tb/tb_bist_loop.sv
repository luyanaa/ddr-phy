// SPDX-License-Identifier: Apache-2.0
// BIST against the real sdr_ctrl + sdr_phy + sdram_model loop.
// Compiled twice by sim/phy.sh: DATA_BITS=8 and DATA_BITS=16, so this
// also verifies the x16 closed loop that sdr_ctrl previously rejected.

`timescale 1ns/1ps
`default_nettype none

module tb_bist_loop;
    parameter integer DATA_BITS = 8;
    localparam integer AB=13, BB=2, RB=4, CB=4, UB=10, NW=8;

    reg clk = 0, rst = 1, start = 0;
    always #5 clk = ~clk;

    wire [UB-1:0]     u_addr;
    wire [DATA_BITS-1:0] u_wdata, u_rdata;
    wire              u_valid, u_we, u_ready, u_rvalid;
    wire [31:0]       err_count, pat_count;
    wire [1:0]        phase_sel;
    wire              busy, pass, scan_done;

    wire [AB-1:0]  dfi_a;
    wire [BB-1:0]  dfi_ba;
    wire           dfi_ras, dfi_cas, dfi_we, dfi_cs, dfi_cke;
    wire           dfi_odt, dfi_reset, dfi_act;
    wire [DATA_BITS-1:0]   dfi_wrdata, dfi_rddata;
    wire [DATA_BITS/8-1:0] dfi_wrmask;
    wire           dfi_wren, dfi_rden, dfi_rdvalid;

    wire [AB-1:0]  a;
    wire [BB-1:0]  ba;
    wire           ras_n, cas_n, we_n, cs_n, cke, ck;
    wire [DATA_BITS/8-1:0] dm;
    wire [DATA_BITS-1:0]   dq_o, dq_i, dq;
    wire           dq_oe;
    wire           fault;
    wire [2:0]     fault_code;

    sdr_bist #(.DATA_BITS(DATA_BITS), .USER_BITS(UB), .NPATTERNS(NW)) u_bist (
        .clk(clk), .rst(rst), .start(start), .scan_en(1'b0),
        .phase_min(2'd0), .phase_max(2'd0),
        .phase_sel(phase_sel), .phase_scan_done(scan_done),
        .error_count(err_count), .pattern_count(pat_count),
        .bist_busy(busy), .bist_pass(pass),
        .user_valid(u_valid), .user_we(u_we), .user_addr(u_addr),
        .user_wdata(u_wdata), .user_ready(u_ready),
        .user_rdata(u_rdata), .user_rvalid(u_rvalid)
    );

    sdr_ctrl #(.DATA_BITS(DATA_BITS), .ADDR_BITS(AB), .BANK_BITS(BB),
               .ROW_BITS(RB), .COL_BITS(CB), .CL(2)) u_ctrl (
        .clk(clk), .rst(rst),
        .user_valid(u_valid), .user_ready(u_ready), .user_we(u_we),
        .user_addr(u_addr), .user_wdata(u_wdata),
        .user_rdata(u_rdata), .user_rvalid(u_rvalid),
        .dfi_address(dfi_a), .dfi_bank(dfi_ba),
        .dfi_ras_n(dfi_ras), .dfi_cas_n(dfi_cas), .dfi_we_n(dfi_we),
        .dfi_cs_n(dfi_cs), .dfi_cke(dfi_cke),
        .dfi_odt(dfi_odt), .dfi_reset_n(dfi_reset), .dfi_act_n(dfi_act),
        .dfi_wrdata(dfi_wrdata), .dfi_wrdata_en(dfi_wren),
        .dfi_wrdata_mask(dfi_wrmask), .dfi_rddata_en(dfi_rden),
        .dfi_rddata(dfi_rddata), .dfi_rddata_valid(dfi_rdvalid),
        .phy_turnaround_busy(1'b0)
    );

    sdr_phy #(.DATA_BITS(DATA_BITS), .ADDR_BITS(AB), .BANK_BITS(BB),
              .CL(2)) u_phy (
        .clk(clk), .rst(rst),
        .dfi_address(dfi_a), .dfi_bank(dfi_ba),
        .dfi_ras_n(dfi_ras), .dfi_cas_n(dfi_cas), .dfi_we_n(dfi_we),
        .dfi_cs_n(dfi_cs), .dfi_cke(dfi_cke),
        .dfi_odt(dfi_odt), .dfi_reset_n(dfi_reset), .dfi_act_n(dfi_act),
        .dfi_wrdata(dfi_wrdata), .dfi_wrdata_en(dfi_wren),
        .dfi_wrdata_mask(dfi_wrmask), .dfi_rddata_en(dfi_rden),
        .dfi_rddata(dfi_rddata), .dfi_rddata_valid(dfi_rdvalid),
        .a(a), .ba(ba), .ras_n(ras_n), .cas_n(cas_n), .we_n(we_n),
        .cs_n(cs_n), .cke(cke), .dm(dm), .dq_o(dq_o), .dq_oe(dq_oe),
        .dq_i(dq_i), .ck(ck)
    );

    assign dq   = dq_oe ? dq_o : {DATA_BITS{1'bz}};
    assign dq_i = dq;

    sdram_model #(.ADDR_BITS(AB), .BANK_BITS(BB), .DATA_BITS(DATA_BITS),
                  .ROW_BITS(RB), .COL_BITS(CB)) u_dram (
        .ck(clk), .cke(cke), .cs_n(cs_n), .ras_n(ras_n), .cas_n(cas_n),
        .we_n(we_n), .ba(ba), .a(a), .dm(dm), .dq(dq),
        .fault(fault), .fault_code(fault_code)
    );

    integer errors = 0, guard = 0;
    initial begin
        repeat (4) @(posedge clk);
        rst = 1'b0;
        @(posedge clk); #1; start = 1'b1;
        @(posedge clk); #1; start = 1'b0;
        guard = 0;
        while (!pass && guard < 4000) begin
            @(posedge clk); #1;
            guard = guard + 1;
        end
        if (pass)                    $display("PASS bist_loop x%0d: completed", DATA_BITS);
        else begin                    $display("FAIL bist_loop x%0d: timeout", DATA_BITS); errors = errors + 1; end
        if (err_count === 32'd0)     $display("PASS bist_loop x%0d: zero errors", DATA_BITS);
        else begin                    $display("FAIL bist_loop x%0d: errors=%0d", DATA_BITS, err_count); errors = errors + 1; end
        if (pat_count === NW)        $display("PASS bist_loop x%0d: %0d patterns", DATA_BITS, NW);
        else begin                    $display("FAIL bist_loop x%0d: patterns=%0d", DATA_BITS, pat_count); errors = errors + 1; end
        if (fault === 1'b0)          $display("PASS bist_loop x%0d: model fault clear", DATA_BITS);
        else begin                    $display("FAIL bist_loop x%0d: fault_code=%0d", DATA_BITS, fault_code); errors = errors + 1; end
        #20;
        `ifdef MUTATE
        errors = errors + 1;
        $display("MUTATION: injected failure for exit-code test");
        `endif
        if (errors == 0) $display("PASS bist_loop x%0d", DATA_BITS);
        else             $fatal(1, "FAIL bist_loop x%0d errors=%0d", DATA_BITS, errors);
        $finish;
    end
endmodule
`default_nettype wire
