// SPDX-License-Identifier: Apache-2.0
// One fresh checker per case. A legal spacing must stay quiet, and the
// same command one clock earlier must stick the matching fault code.
// Commands are on the SDRAM pins. This does not prove the PHY, the pad,
// or any nanosecond path (tAC, tOH, tHZ, setup/hold).

`default_nettype none

module checker_case #(
    parameter integer T_RCD = 2,
    parameter integer T_RP  = 2,
    parameter integer T_RAS = 5,
    parameter integer T_RC  = 7,
    parameter integer T_RRD = 2,
    parameter integer T_RFC = 7,
    parameter integer T_WR  = 2,
    parameter integer T_MRD = 2,
    parameter integer T_CCD = 2
) (
    input  wire        clk,
    input  wire        cke,
    input  wire        cs_n,
    input  wire        ras_n,
    input  wire        cas_n,
    input  wire        we_n,
    input  wire [1:0]  ba,
    input  wire        a10,
    output wire        fault,
    output wire [3:0]  fault_code
);
    sdram_checker #(
        .T_RCD(T_RCD), .T_RP(T_RP), .T_RAS(T_RAS), .T_RC(T_RC),
        .T_RRD(T_RRD), .T_RFC(T_RFC), .T_WR(T_WR), .T_MRD(T_MRD),
        .T_CCD(T_CCD)
    ) u (
        .ck(clk), .cke(cke), .cs_n(cs_n), .ras_n(ras_n), .cas_n(cas_n),
        .we_n(we_n), .ba(ba), .a10(a10), .fault(fault), .fault_code(fault_code)
    );
endmodule

module tb_sdram_checker;
    reg        clk;
    reg        cke;
    reg        cs_n;
    reg        ras_n;
    reg        cas_n;
    reg        we_n;
    reg  [1:0] ba;
    reg        a10;

    wire        f_rcd, f_ras, f_rp, f_rc, f_rrd, f_rfc, f_wr, f_mrd, f_ccd;
    wire [3:0]  c_rcd, c_ras, c_rp, c_rc, c_rrd, c_rfc, c_wr, c_mrd, c_ccd;

    integer errors;

    localparam [3:0] EARLY_RCD = 4'd1;
    localparam [3:0] EARLY_RAS = 4'd2;
    localparam [3:0] EARLY_RP  = 4'd3;
    localparam [3:0] EARLY_RC  = 4'd4;
    localparam [3:0] EARLY_RRD = 4'd5;
    localparam [3:0] EARLY_RFC = 4'd6;
    localparam [3:0] EARLY_WR  = 4'd7;
    localparam [3:0] EARLY_MRD = 4'd8;
    localparam [3:0] EARLY_CCD = 4'd9;

    `define CHECK(cond) \
        if (!(cond)) begin \
            $display("FAIL line %0d: %s", `__LINE__, `"cond`"); \
            errors = errors + 1; \
        end

    // Each instance watches the same pins and ignores every interval but
    // the one under test, so a short gap cannot be blamed on another rule.
    checker_case #(.T_RCD(2), .T_RP(0), .T_RAS(0), .T_RC(0), .T_RRD(0), .T_RFC(0), .T_WR(0), .T_MRD(0), .T_CCD(0)) u_rcd (.clk(clk), .cke(cke), .cs_n(cs_n), .ras_n(ras_n), .cas_n(cas_n), .we_n(we_n), .ba(ba), .a10(a10), .fault(f_rcd), .fault_code(c_rcd));
    checker_case #(.T_RCD(0), .T_RP(0), .T_RAS(3), .T_RC(0), .T_RRD(0), .T_RFC(0), .T_WR(0), .T_MRD(0), .T_CCD(0)) u_ras (.clk(clk), .cke(cke), .cs_n(cs_n), .ras_n(ras_n), .cas_n(cas_n), .we_n(we_n), .ba(ba), .a10(a10), .fault(f_ras), .fault_code(c_ras));
    checker_case #(.T_RCD(0), .T_RP(2), .T_RAS(0), .T_RC(0), .T_RRD(0), .T_RFC(0), .T_WR(0), .T_MRD(0), .T_CCD(0)) u_rp  (.clk(clk), .cke(cke), .cs_n(cs_n), .ras_n(ras_n), .cas_n(cas_n), .we_n(we_n), .ba(ba), .a10(a10), .fault(f_rp),  .fault_code(c_rp));
    checker_case #(.T_RCD(0), .T_RP(0), .T_RAS(0), .T_RC(4), .T_RRD(0), .T_RFC(0), .T_WR(0), .T_MRD(0), .T_CCD(0)) u_rc  (.clk(clk), .cke(cke), .cs_n(cs_n), .ras_n(ras_n), .cas_n(cas_n), .we_n(we_n), .ba(ba), .a10(a10), .fault(f_rc),  .fault_code(c_rc));
    checker_case #(.T_RCD(0), .T_RP(0), .T_RAS(0), .T_RC(0), .T_RRD(2), .T_RFC(0), .T_WR(0), .T_MRD(0), .T_CCD(0)) u_rrd (.clk(clk), .cke(cke), .cs_n(cs_n), .ras_n(ras_n), .cas_n(cas_n), .we_n(we_n), .ba(ba), .a10(a10), .fault(f_rrd), .fault_code(c_rrd));
    checker_case #(.T_RCD(0), .T_RP(0), .T_RAS(0), .T_RC(0), .T_RRD(0), .T_RFC(3), .T_WR(0), .T_MRD(0), .T_CCD(0)) u_rfc (.clk(clk), .cke(cke), .cs_n(cs_n), .ras_n(ras_n), .cas_n(cas_n), .we_n(we_n), .ba(ba), .a10(a10), .fault(f_rfc), .fault_code(c_rfc));
    checker_case #(.T_RCD(0), .T_RP(0), .T_RAS(0), .T_RC(0), .T_RRD(0), .T_RFC(0), .T_WR(2), .T_MRD(0), .T_CCD(0)) u_wr  (.clk(clk), .cke(cke), .cs_n(cs_n), .ras_n(ras_n), .cas_n(cas_n), .we_n(we_n), .ba(ba), .a10(a10), .fault(f_wr),  .fault_code(c_wr));
    checker_case #(.T_RCD(0), .T_RP(0), .T_RAS(0), .T_RC(0), .T_RRD(0), .T_RFC(0), .T_WR(0), .T_MRD(2), .T_CCD(0)) u_mrd (.clk(clk), .cke(cke), .cs_n(cs_n), .ras_n(ras_n), .cas_n(cas_n), .we_n(we_n), .ba(ba), .a10(a10), .fault(f_mrd), .fault_code(c_mrd));
    checker_case #(.T_RCD(0), .T_RP(0), .T_RAS(0), .T_RC(0), .T_RRD(0), .T_RFC(0), .T_WR(0), .T_MRD(0), .T_CCD(2)) u_ccd (.clk(clk), .cke(cke), .cs_n(cs_n), .ras_n(ras_n), .cas_n(cas_n), .we_n(we_n), .ba(ba), .a10(a10), .fault(f_ccd), .fault_code(c_ccd));

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic gap;
        input integer n;
        begin
            cs_n  = 1'b1;
            ras_n = 1'b1;
            cas_n = 1'b1;
            we_n  = 1'b1;
            a10   = 1'b0;
            repeat (n) begin
                @(posedge clk);
                #1;
            end
        end
    endtask

    task automatic cmd;
        input ras;
        input cas;
        input we;
        input [1:0] bank;
        input ap;
        begin
            @(negedge clk);
            #1;
            cke   = 1'b1;
            cs_n  = 1'b0;
            ras_n = ras;
            cas_n = cas;
            we_n  = we;
            ba    = bank;
            a10   = ap;
            @(posedge clk);
            #1;
        end
    endtask

    task automatic act;
        input [1:0] bank;
        begin
            cmd(0, 1, 1, bank, 0);
        end
    endtask

    initial begin
        errors = 0;
        cke = 1'b0;
        ba  = 2'd0;
        a10 = 1'b0;
        gap(1);
        @(negedge clk);
        cke = 1'b1;
        gap(1);

        // tRCD = 2. ACT, one NOP, READ is early. Two NOPs, READ is legal.
        act(0);
        gap(1);
        cmd(1, 0, 1, 0, 0);
        `CHECK(f_rcd === 1'b1 && c_rcd === EARLY_RCD)
        gap(2);
        cmd(1, 0, 1, 0, 0);
        `CHECK(f_rcd === 1'b1 && c_rcd === EARLY_RCD)

        // tRAS = 3. PRE one clock early, then a PRE that lands on the count.
        act(0);
        gap(1);
        cmd(0, 1, 0, 0, 0);
        `CHECK(f_ras === 1'b1 && c_ras === EARLY_RAS)
        act(1);
        gap(2);
        cmd(0, 1, 0, 1, 0);
        `CHECK(f_ras === 1'b0)

        // tRP = 2. The early ACT is bank 0's; bank 1 was never precharged.
        cmd(0, 1, 0, 0, 0);
        gap(1);
        act(0);
        `CHECK(f_rp === 1'b1 && c_rp === EARLY_RP)
        cmd(0, 1, 0, 0, 0);
        gap(2);
        act(0);
        `CHECK(f_rp === 1'b1 && c_rp === EARLY_RP)

        // tRC = 4, same bank. A different bank is not this rule.
        act(0);
        gap(2);
        act(0);
        `CHECK(f_rc === 1'b1 && c_rc === EARLY_RC)
        act(1);
        `CHECK(f_rc === 1'b1 && c_rc === EARLY_RC)

        // tRRD = 2, two banks.
        act(0);
        gap(1);
        act(1);
        `CHECK(f_rrd === 1'b1 && c_rrd === EARLY_RRD)
        act(0);
        gap(2);
        act(1);
        `CHECK(f_rrd === 1'b1 && c_rrd === EARLY_RRD)

        // tRFC = 3. The second REF is the one that counts.
        cmd(0, 0, 1, 0, 0);
        gap(1);
        cmd(0, 0, 1, 0, 0);
        `CHECK(f_rfc === 1'b1 && c_rfc === EARLY_RFC)
        cmd(0, 0, 1, 0, 0);
        gap(3);
        cmd(0, 0, 1, 0, 0);
        `CHECK(f_rfc === 1'b1 && c_rfc === EARLY_RFC)

        // tWR = 2. WRITE then PRE.
        act(0);
        cmd(1, 0, 0, 0, 0);
        gap(1);
        cmd(0, 1, 0, 0, 0);
        `CHECK(f_wr === 1'b1 && c_wr === EARLY_WR)
        act(1);
        cmd(1, 0, 0, 1, 0);
        gap(2);
        cmd(0, 1, 0, 1, 0);
        `CHECK(f_wr === 1'b1 && c_wr === EARLY_WR)

        // tMRD = 2. MRS then ACT.
        cmd(0, 0, 0, 0, 0);
        gap(1);
        act(0);
        `CHECK(f_mrd === 1'b1 && c_mrd === EARLY_MRD)
        cmd(0, 0, 0, 0, 0);
        gap(2);
        act(0);
        `CHECK(f_mrd === 1'b1 && c_mrd === EARLY_MRD)

        // tCCD = 2. Back-to-back READ is one clock early.
        act(0);
        cmd(1, 0, 1, 0, 0);
        gap(1);
        cmd(1, 0, 1, 0, 0);
        `CHECK(f_ccd === 1'b1 && c_ccd === EARLY_CCD)
        cmd(1, 0, 1, 0, 0);
        gap(2);
        cmd(1, 0, 1, 0, 0);
        `CHECK(f_ccd === 1'b1 && c_ccd === EARLY_CCD)

        if (errors == 0) begin
            $display("PASS checker");
            $finish;
        end else begin
            $display("FAIL checker errors=%0d", errors);
            $fatal(1);
        end
    end

    initial begin
        #200000;
        $display("FAIL checker timeout");
        $fatal(1);
    end
endmodule

`default_nettype wire
