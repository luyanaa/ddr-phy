// SPDX-License-Identifier: Apache-2.0
// Periodic refresh verification: sdr_ctrl with T_REFI enabled must close
// all banks, issue AUTO REFRESH, wait tRFC, and keep data intact. A
// REF_OPEN fault from the model would mean banks were left open.

`timescale 1ns/1ps
`default_nettype none
module tb_refresh;
    localparam integer AB=13, BB=2, DB=8, RB=4, CB=4, UB=10;
    reg clk=0, rst=1;
    always #5 clk = ~clk;

    reg  user_valid=0, user_we=0;
    reg  [UB-1:0] user_addr=0;
    reg  [DB-1:0] user_wdata=0;
    wire user_ready, user_rvalid;
    wire [DB-1:0] user_rdata;

    wire [AB-1:0] dfi_a;
    wire [BB-1:0] dfi_ba;
    wire dfi_ras, dfi_cas, dfi_we, dfi_cs, dfi_cke;
    wire dfi_odt, dfi_reset, dfi_act;
    wire [DB-1:0] dfi_wrdata, dfi_rddata;
    wire [DB/8-1:0] dfi_wrmask;
    wire dfi_wren, dfi_rden, dfi_rdvalid;
    wire [AB-1:0] a;
    wire [BB-1:0] ba;
    wire ras_n, cas_n, we_n, cs_n, cke, ck;
    wire [DB/8-1:0] dm;
    wire [DB-1:0] dq_o, dq_i, dq;
    wire dq_oe, fault;
    wire [2:0] fault_code;

    sdr_ctrl #(.DATA_BITS(DB), .ADDR_BITS(AB), .BANK_BITS(BB),
               .ROW_BITS(RB), .COL_BITS(CB), .CL(2),
               .T_RCD(2), .T_RP(2), .T_RFC(4), .T_REFI(40)) u_ctrl (
        .clk(clk), .rst(rst),
        .user_valid(user_valid), .user_ready(user_ready),
        .user_we(user_we), .user_addr(user_addr), .user_wdata(user_wdata),
        .user_rdata(user_rdata), .user_rvalid(user_rvalid),
        .dfi_address(dfi_a), .dfi_bank(dfi_ba),
        .dfi_ras_n(dfi_ras), .dfi_cas_n(dfi_cas), .dfi_we_n(dfi_we),
        .dfi_cs_n(dfi_cs), .dfi_cke(dfi_cke),
        .dfi_odt(dfi_odt), .dfi_reset_n(dfi_reset), .dfi_act_n(dfi_act),
        .dfi_wrdata(dfi_wrdata), .dfi_wrdata_en(dfi_wren),
        .dfi_wrdata_mask(dfi_wrmask), .dfi_rddata_en(dfi_rden),
        .dfi_rddata(dfi_rddata), .dfi_rddata_valid(dfi_rdvalid),
        .phy_turnaround_busy(1'b0)
    );
    sdr_phy #(.DATA_BITS(DB), .ADDR_BITS(AB), .BANK_BITS(BB), .CL(2)) u_phy (
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
    assign dq   = dq_oe ? dq_o : {DB{1'bz}};
    assign dq_i = dq;
    sdram_model #(.ADDR_BITS(AB), .BANK_BITS(BB), .DATA_BITS(DB),
                  .ROW_BITS(RB), .COL_BITS(CB)) u_dram (
        .ck(clk), .cke(cke), .cs_n(cs_n), .ras_n(ras_n), .cas_n(cas_n),
        .we_n(we_n), .ba(ba), .a(a), .dm(dm), .dq(dq),
        .fault(fault), .fault_code(fault_code)
    );

    // Count AUTO REFRESH only after init (init itself issues two).
    integer ref_count = 0;
    reg init_seen = 0;
    always @(posedge clk) begin
        if (rst) begin ref_count <= 0; init_seen <= 1'b0; end
        else begin
            if (user_ready) init_seen <= 1'b1;
            if (init_seen && dfi_cs === 1'b0 && dfi_ras === 1'b0 &&
                dfi_cas === 1'b0 && dfi_we === 1'b1)
                ref_count <= ref_count + 1;
        end
    end

    integer errors = 0, guard;
    task automatic write_word(input [UB-1:0] ad, input [DB-1:0] d);
        begin
            @(negedge clk);
            user_we=1; user_addr=ad; user_wdata=d; user_valid=1;
            guard=0;
            while (!(user_ready === 1'b1) && guard < 200) begin
                @(posedge clk); #1; guard = guard + 1;
            end
            @(negedge clk); user_valid=0;
        end
    endtask
    task automatic read_word(input [UB-1:0] ad, input [DB-1:0] expected);
        begin
            @(negedge clk);
            user_we=0; user_addr=ad; user_valid=1;
            guard=0;
            while (!(user_ready === 1'b1) && guard < 200) begin
                @(posedge clk); #1; guard = guard + 1;
            end
            @(negedge clk); user_valid=0;
            guard=0;
            while (!(user_rvalid === 1'b1) && guard < 200) begin
                @(posedge clk); #1; guard = guard + 1;
            end
            if (user_rdata === expected) $display("PASS refresh: readback %h", expected);
            else begin $display("FAIL refresh: readback %h exp %h", user_rdata, expected); errors=errors+1; end
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        rst = 1'b0;
        write_word(10'd0, 8'hA5);
        // Let several refresh cycles elapse.
        guard = 0;
        while (ref_count < 3 && guard < 600) begin
            @(posedge clk); #1; guard = guard + 1;
        end
        if (ref_count >= 3) $display("PASS refresh: %0d periodic AUTO REFRESH", ref_count);
        else begin $display("FAIL refresh: only %0d refreshes", ref_count); errors=errors+1; end
        if (fault === 1'b0) $display("PASS refresh: no model fault (banks closed before REF)");
        else begin $display("FAIL refresh: fault_code=%0d", fault_code); errors=errors+1; end
        read_word(10'd0, 8'hA5);
        #20;
        `ifdef MUTATE
        errors = errors + 1;
        $display("MUTATION: injected failure for exit-code test");
        `endif
        if (errors == 0) $display("PASS tb_refresh");
        else             $fatal(1, "FAIL tb_refresh errors=%0d", errors);
        $finish;
    end
endmodule
`default_nettype wire
