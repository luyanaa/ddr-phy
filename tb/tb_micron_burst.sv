// SPDX-License-Identifier: Apache-2.0
// OPTIONAL model-level burst differential: own sdram_model vs Micron -7E.
// This bypasses the PHY/controller and checks BL=2/4/8 command/data order.
// The model is gitignored and -7E, not the project -75 contract.

`timescale 1ns/1ps
`default_nettype none

module tb_micron_burst;
    localparam integer AB=13, BB=2, DB=8;
    reg clk = 0;
    always #5 clk = ~clk;

    reg cke=1, cs=1, ras=1, cas=1, we=1;
    reg [BB-1:0] ba=0;
    reg [AB-1:0] a=0;
    reg dm=0, drv=0;
    reg [DB-1:0] drv_data=0;
    wire [DB-1:0] dq_own;
    wire [15:0] dq_ref;
    wire fault;
    wire [2:0] fault_code;

    assign dq_own = drv ? drv_data : {DB{1'bz}};
    assign dq_ref[7:0] = drv ? drv_data : 8'bz;
    assign dq_ref[15:8] = 8'bz;

    sdram_model #(.ADDR_BITS(AB), .BANK_BITS(BB), .DATA_BITS(DB),
                  .ROW_BITS(4), .COL_BITS(4)) u_own (
        .ck(clk), .cke(cke), .cs_n(cs), .ras_n(ras), .cas_n(cas),
        .we_n(we), .ba(ba), .a(a), .dm(dm), .dq(dq_own),
        .fault(fault), .fault_code(fault_code)
    );

    mt48lc16m16a2 u_ref (
        .Dq(dq_ref), .Addr(a), .Ba(ba), .Clk(clk),
        .Cke(cke), .Cs_n(cs), .Ras_n(ras), .Cas_n(cas),
        .We_n(we), .Dqm({1'b0, dm})
    );

    localparam [3:0] NOP=4'b1111, MRS=4'b0000, REF=4'b0001, ACT=4'b0011,
                     WR=4'b0100, RD=4'b0101, PRE=4'b0010;
    integer errors=0, i, j, bl;
    reg [DB-1:0] exp [0:7];
    reg [DB-1:0] own_beats [0:7];
    reg [DB-1:0] ref_beats [0:7];
    reg [DB-1:0] got_own, got_ref;
    reg [AB-1:0] mr;
    reg [1:0] bl_code;

    task automatic step(input [3:0] c, input [BB-1:0] b, input [AB-1:0] ad,
                        input m, input d, input [DB-1:0] dd);
        begin
            @(negedge clk);
            cs=c[3]; ras=c[2]; cas=c[1]; we=c[0];
            ba=b; a=ad; dm=m; drv=d; drv_data=dd;
            @(posedge clk); #1;
        end
    endtask

    initial begin
        repeat (8) @(posedge clk);
        exp[0]=8'h11; exp[1]=8'h22; exp[2]=8'h33; exp[3]=8'h44;
        exp[4]=8'h55; exp[5]=8'h66; exp[6]=8'h77; exp[7]=8'h88;
        for (i=0;i<3;i=i+1) begin
            case (i)
                0: begin bl=2; bl_code=2'd1; end
                1: begin bl=4; bl_code=2'd2; end
                2: begin bl=8; bl_code=2'd3; end
            endcase
            mr = 13'h0020 | {11'd0, bl_code};
            step(PRE, 0, 13'h0400, 0, 0, 0);
            step(NOP, 0, 0, 0, 0, 0);
            step(NOP, 0, 0, 0, 0, 0);
            step(REF, 0, 0, 0, 0, 0);
            for (j=0;j<7;j=j+1) step(NOP, 0, 0, 0, 0, 0);
            step(REF, 0, 0, 0, 0, 0);
            for (j=0;j<7;j=j+1) step(NOP, 0, 0, 0, 0, 0);
            step(MRS, 0, mr, 0, 0, 0);
            step(NOP, 0, 0, 0, 0, 0);
            step(NOP, 0, 0, 0, 0, 0);
            step(ACT, 0, 13'h0000, 0, 0, 0);
            step(NOP, 0, 0, 0, 0, 0);
            step(NOP, 0, 0, 0, 0, 0);
            step(WR,  0, 13'h0000, 0, 1, exp[0]);
            for (j=1;j<bl;j=j+1)
                step(NOP, 0, 0, 0, 1, exp[j]);
            step(NOP, 0, 0, 0, 0, 0);
            step(NOP, 0, 0, 0, 0, 0);
            // Own model: one NOP per beat after the READ command.
            step(RD,  0, 13'h0000, 0, 0, 0);
            for (j=0;j<bl;j=j+1) begin
                step(NOP, 0, 0, 0, 0, 0);
                own_beats[j] = dq_own;
            end
            step(NOP, 0, 0, 0, 0, 0);
            // Micron model: its output lags one cycle; read the same row again.
            step(RD,  0, 13'h0000, 0, 0, 0);
            step(NOP, 0, 0, 0, 0, 0);
            for (j=0;j<bl;j=j+1) begin
                step(NOP, 0, 0, 0, 0, 0);
                ref_beats[j] = dq_ref[7:0];
            end
            for (j=0;j<bl;j=j+1) begin
                if (own_beats[j] !== exp[j] || ref_beats[j] !== exp[j]) begin
                    $display("FAIL BL=%0d beat=%0d own=%h ref=%h exp=%h",
                             bl, j, own_beats[j], ref_beats[j], exp[j]);
                    errors = errors + 1;
                end
            end
            if (fault !== 1'b0) begin
                $display("FAIL BL=%0d own fault_code=%0d", bl, fault_code);
                errors = errors + 1;
            end else
                $display("PASS micron_burst BL=%0d", bl);
            step(NOP, 0, 0, 0, 0, 0);
        end
        #20;
        `ifdef MUTATE
        errors = errors + 1;
        $display("MUTATION: injected failure for exit-code test");
        `endif
        if (errors == 0) $display("PASS micron_burst");
        else             $fatal(1, "FAIL micron_burst errors=%0d", errors);
        $finish;
    end
endmodule

`default_nettype wire
