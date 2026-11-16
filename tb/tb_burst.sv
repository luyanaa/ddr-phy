// SPDX-License-Identifier: Apache-2.0
// BL=2/4/8 write-burst verification against the pin-level SDRAM model.
// Beat 0 rides with the WRITE command; the remaining beats are sampled on
// following CK edges. A BL=4/8 READ then returns all beats in order.

`timescale 1ns/1ps
`default_nettype none
module tb_burst;
    localparam integer AB=13, BB=2, RB=4, CB=4, DB=8;
    reg clk = 0;
    always #5 clk = ~clk;

    reg        cke=1, cs=1, ras=1, cas=1, we=1;
    reg [BB-1:0] ba=0;
    reg [AB-1:0] a=0;
    reg [DB/8-1:0] dm=0;
    reg        drv=0;
    reg [DB-1:0] drv_data=0;
    wire [DB-1:0] dq;
    wire       fault;
    wire [2:0] fault_code;
    assign dq = drv ? drv_data : {DB{1'bz}};

    sdram_model #(.ADDR_BITS(AB), .BANK_BITS(BB), .DATA_BITS(DB),
                  .ROW_BITS(RB), .COL_BITS(CB)) u_dram (
        .ck(clk), .cke(cke), .cs_n(cs), .ras_n(ras), .cas_n(cas),
        .we_n(we), .ba(ba), .a(a), .dm(dm), .dq(dq),
        .fault(fault), .fault_code(fault_code)
    );

    localparam [3:0] NOP=4'b1111, MRS=4'b0000, ACT=4'b0011,
                     WR=4'b0100, RD=4'b0101, PRE=4'b0010;
    integer errors=0, i, j, bl;
    reg [7:0] exp [0:7];
    reg [DB-1:0] got;
    reg [AB-1:0] mr;
    reg [1:0] bl_code;

    task automatic step(input [3:0] c, input [BB-1:0] b, input [AB-1:0] ad,
                        input [DB/8-1:0] m, input d, input [DB-1:0] dd);
        begin
            @(negedge clk);
            cs=c[3]; ras=c[2]; cas=c[1]; we=c[0];
            ba=b; a=ad; dm=m; drv=d; drv_data=dd;
            @(posedge clk); #1;
        end
    endtask

    initial begin
        exp[0]=8'h11; exp[1]=8'h22; exp[2]=8'h33; exp[3]=8'h44;
        exp[4]=8'h55; exp[5]=8'h66; exp[6]=8'h77; exp[7]=8'h88;
        for (i=0;i<3;i=i+1) begin
            case (i)
                0: begin bl=2; bl_code=2'd1; end
                1: begin bl=4; bl_code=2'd2; end
                2: begin bl=8; bl_code=2'd3; end
            endcase
            mr = 13'h0020 | {11'd0, bl_code};   // CL=2, sequential burst
            step(PRE, 0, 13'h0400, 1'b0, 0, 0);   // precharge all banks
            step(NOP, 0, 0, 0, 0, 0);
            step(MRS, 0, mr, 0, 0, 0);
            step(NOP, 0, 0, 0, 0, 0);
            step(NOP, 0, 0, 0, 0, 0);
            step(ACT, 0, 13'h0000, 0, 0, 0);      // bank 0, row 0
            step(NOP, 0, 0, 0, 0, 0);
            step(NOP, 0, 0, 0, 0, 0);             // tRCD
            step(WR,  0, 13'h0000, 1'b0, 1, exp[0]);  // beat 0
            for (j=1;j<bl;j=j+1)
                step(NOP, 0, 0, 1'b0, 1, exp[j]);     // continuation beats
            step(NOP, 0, 0, 0, 0, 0);
            step(NOP, 0, 0, 0, 0, 0);
            step(RD,  0, 13'h0000, 0, 0, 0);
            for (j=0;j<bl;j=j+1) begin
                step(NOP, 0, 0, 0, 0, 0);
                got = dq;
                if (got !== exp[j]) begin
                    $display("FAIL BL=%0d beat=%0d got=%h exp=%h", bl, j, got, exp[j]);
                    errors = errors + 1;
                end
            end
            if (fault !== 1'b0) begin
                $display("FAIL BL=%0d fault_code=%0d", bl, fault_code);
                errors = errors + 1;
            end else
                $display("PASS BL=%0d write+read burst", bl);
            step(NOP, 0, 0, 0, 0, 0);
        end
        #20;
        `ifdef MUTATE
        errors = errors + 1;
        $display("MUTATION: injected failure for exit-code test");
        `endif
        if (errors == 0) $display("PASS burst");
        else             $fatal(1, "FAIL burst errors=%0d", errors);
        $finish;
    end
endmodule
`default_nettype wire
