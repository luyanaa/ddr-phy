// SPDX-License-Identifier: Apache-2.0
// Command-interval checker for one SDR SDRAM rank, four banks. It does not
// store data and it does not drive DQ. The memory model can be wrong about
// the array and this checker still flags a command that arrived too soon.
//
// Intervals are clocks, not nanoseconds. The controller (or the test)
// converts a datasheet minimum with ceil(ns / tCK) and passes that count.
// A count of 0 disables that one check. The defaults are the -75 column of
// Micron 256Mb_sdr.pdf Rev. W (05/15), Table 12 and Table 13, at tCK = 10 ns
// so CL = 2 is legal (tCK(2) min is 10 ns, tCK(3) min is 7.5 ns):
//
//   tRCD 20 ns -> 2    tRP 20 ns -> 2    tRAS 44 ns -> 5
//   tRC  66 ns -> 7    tRFC 66 ns -> 7   tRRD 15 ns -> 2
//   tWR is "1 CLK + 7.5 ns" (note 13, auto precharge) and also 15 ns
//   (note 14, precharge). tDPL is 2 tCK (Table 13). The checker uses 2.
//   tMRD is 2 tCK. Table 13 note 21 says JEDEC and PC100 specify 3.
//   tCCD is 1 tCK.
//
// Same clocks from IS42/45S16160J Rev. C4 (09/17/2020), speed -7, the
// 133 MHz grade (CL = 2 at 7.5 ns). Its nanosecond column is not this
// part: tRCD/tRP are 15 ns, tRAS min is 37 ns, and refresh recovery is
// trc = 60 ns with no separate tRFC. Do not mix the two tables.
//
// Not checked, because a clock-counting model cannot see them: tAC, tOH,
// tHZ, tLZ, tDS/tDH, tAS/tAH, tCMS/tCMH, pad slew, package, PCB. DQM
// latency (tDQD/tDQM = 0 on a write, tDQZ = 2 on a read) is a data-path
// rule and is left to the memory model.
//
// Ages are plain vectors. Under Icarus 13 a nonblocking write in the age
// block is dropped, a memory word passed into a function reads back as 0,
// and a blocking write of an output does not appear on the port. The age
// block therefore only writes the counters, with blocking assignments.
// The fault is a continuous compare of those counters, not a value written
// inside the age block. ACT on edge T loads 1. Later idle edges step a
// counter until it sticks: tRAS sticks at its count, and every other
// counter sticks one short of its count, because the compare on a command
// edge still sees the age from before that edge's update. A limit of 0 or
// 1 neither steps nor clears that counter. The command edge is the last
// clock of the interval. CKE low is not an idle edge. PRE clears the live
// tRAS counter, so that compare reads a copy taken on the previous falling
// edge; an early precharge would otherwise be gone by the time the test
// samples the fault.

`default_nettype none

module sdram_checker #(
    parameter integer BANK_BITS = 2,
    parameter integer T_RCD     = 2,
    parameter integer T_RP      = 2,
    parameter integer T_RAS     = 5,
    parameter integer T_RC      = 7,
    parameter integer T_RRD     = 2,
    parameter integer T_RFC     = 7,
    parameter integer T_WR      = 2,
    parameter integer T_MRD     = 2,
    parameter integer T_CCD     = 1
) (
    input  wire                     ck,
    input  wire                     cke,
    input  wire                     cs_n,
    input  wire                     ras_n,
    input  wire                     cas_n,
    input  wire                     we_n,
    input  wire [BANK_BITS-1:0]     ba,
    input  wire                     a10,
    output wire                     fault,
    output wire [3:0]               fault_code
);

    localparam [3:0] OK        = 4'd0;
    localparam [3:0] EARLY_RCD = 4'd1;
    localparam [3:0] EARLY_RAS = 4'd2;
    localparam [3:0] EARLY_RP  = 4'd3;
    localparam [3:0] EARLY_RC  = 4'd4;
    localparam [3:0] EARLY_RRD = 4'd5;
    localparam [3:0] EARLY_RFC = 4'd6;
    localparam [3:0] EARLY_WR  = 4'd7;
    localparam [3:0] EARLY_MRD = 4'd8;
    localparam [3:0] EARLY_CCD = 4'd9;

    // 0 means nothing of that kind is outstanding. A counter that has
    // stuck stays legal. tRCD and tRAS are separate: a test that enables
    // only one of them must not age, or clear, the other.
    reg [15:0] a_act0, a_act1, a_act2, a_act3;
    reg [15:0] a_ras0, a_ras1, a_ras2, a_ras3;
    reg [15:0] a_pre0, a_pre1, a_pre2, a_pre3;
    reg [15:0] a_rc0,  a_rc1,  a_rc2,  a_rc3;
    reg [15:0] a_wr0,  a_wr1,  a_wr2,  a_wr3;
    reg [15:0] a_rrd, a_rfc, a_mrd, a_ccd;

    reg [15:0] n_act0, n_act1, n_act2, n_act3;
    reg [15:0] n_ras0, n_ras1, n_ras2, n_ras3;
    reg [15:0] n_pre0, n_pre1, n_pre2, n_pre3;
    reg [15:0] n_rc0,  n_rc1,  n_rc2,  n_rc3;
    reg [15:0] n_wr0,  n_wr1,  n_wr2,  n_wr3;
    reg [15:0] n_rrd, n_rfc, n_mrd, n_ccd;

    // PRE clears the live tRAS counter on the command edge, so that
    // one compare uses the copy taken on the previous falling edge.
    reg [15:0] h_ras0, h_ras1, h_ras2, h_ras3;
    wire [15:0] s_act = ba == 0 ? a_act0 : ba == 1 ? a_act1 : ba == 2 ? a_act2 : a_act3;
    // PRE clears a_ras on the command edge. The compare has to use the
    // copy taken on the previous falling edge, or the sample after that
    // edge sees a cleared counter and misses an early precharge.
    wire [15:0] s_ras = ba == 0 ? h_ras0 : ba == 1 ? h_ras1 : ba == 2 ? h_ras2 : h_ras3;
    wire [15:0] s_pre = ba == 0 ? a_pre0 : ba == 1 ? a_pre1 : ba == 2 ? a_pre2 : a_pre3;
    wire [15:0] s_rc  = ba == 0 ? a_rc0  : ba == 1 ? a_rc1  : ba == 2 ? a_rc2  : a_rc3;
    wire [15:0] s_wr  = ba == 0 ? a_wr0  : ba == 1 ? a_wr1  : ba == 2 ? a_wr2  : a_wr3;
    wire [15:0] s_rrd = a_rrd;
    wire [15:0] s_rfc = a_rfc;
    wire [15:0] s_mrd = a_mrd;
    wire [15:0] s_ccd = a_ccd;
    wire is_act = cke && !cs_n && !ras_n && cas_n && we_n;
    wire is_rw  = cke && !cs_n && ras_n && !cas_n;
    wire is_pre = cke && !cs_n && !ras_n && cas_n && !we_n;
    wire is_ref = cke && !cs_n && !ras_n && !cas_n && we_n;
    wire is_mrs = cke && !cs_n && !ras_n && !cas_n && !we_n;
    wire gap_act = (T_RCD > 1 && s_act != 0 && s_act < T_RCD);
    wire gap_ras = (T_RAS > 1 && s_ras != 0 && s_ras < T_RAS);
    wire gap_rp  = (T_RP  > 1 && s_pre != 0 && s_pre < T_RP);
    wire gap_rc  = (T_RC  > 1 && s_rc  != 0 && s_rc  < T_RC);
    wire gap_rrd = (T_RRD > 1 && s_rrd != 0 && s_rrd < T_RRD);
    wire gap_rfc = (T_RFC > 1 && s_rfc != 0 && s_rfc < T_RFC);
    wire gap_wr  = (T_WR  > 1 && s_wr  != 0 && s_wr  < T_WR);
    wire gap_mrd = (T_MRD > 1 && s_mrd != 0 && s_mrd < T_MRD);
    wire gap_ccd = (T_CCD > 1 && s_ccd != 0 && s_ccd < T_CCD);
    wire pre_open = (T_RP > 1) && (
        (a_pre0 != 0 && a_pre0 < T_RP) || (a_pre1 != 0 && a_pre1 < T_RP) ||
        (a_pre2 != 0 && a_pre2 < T_RP) || (a_pre3 != 0 && a_pre3 < T_RP));
    wire ras_open = (T_RAS > 1) && (
        (h_ras0 != 0 && h_ras0 < T_RAS) || (h_ras1 != 0 && h_ras1 < T_RAS) ||
        (h_ras2 != 0 && h_ras2 < T_RAS) || (h_ras3 != 0 && h_ras3 < T_RAS));
    wire wr_open = (T_WR > 1) && (
        (a_wr0 != 0 && a_wr0 < T_WR) || (a_wr1 != 0 && a_wr1 < T_WR) ||
        (a_wr2 != 0 && a_wr2 < T_WR) || (a_wr3 != 0 && a_wr3 < T_WR));
    wire e_rc  = is_act && gap_rc;
    wire e_rp  = (is_act && gap_rp) || ((is_ref || is_mrs) && pre_open);
    wire e_rrd = is_act && gap_rrd;
    wire e_rfc = (is_act || is_rw || is_pre || is_ref || is_mrs) && gap_rfc;
    wire e_mrd = (is_act || is_rw || is_pre || is_ref || is_mrs) && gap_mrd;
    wire e_rcd = is_rw && gap_act;
    wire e_ccd = is_rw && gap_ccd;
    wire e_ras = is_pre && (a10 ? ras_open : gap_ras);
    wire e_wr  = is_pre && (a10 ? wr_open : gap_wr);
    // First match is the code the test expects. A later rule on the same
    // command does not replace it.
    assign fault = e_rc | e_rp | e_rrd | e_rfc | e_mrd | e_rcd | e_ccd | e_ras | e_wr;
    assign fault_code = e_rc ? EARLY_RC : e_rp ? EARLY_RP : e_rrd ? EARLY_RRD
                      : e_rfc ? EARLY_RFC : e_mrd ? EARLY_MRD : e_rcd ? EARLY_RCD
                      : e_ccd ? EARLY_CCD : e_ras ? EARLY_RAS : e_wr ? EARLY_WR : OK;


    initial begin
        a_act0 = 0; a_act1 = 0; a_act2 = 0; a_act3 = 0;
        a_ras0 = 0; a_ras1 = 0; a_ras2 = 0; a_ras3 = 0;
        a_pre0 = 0; a_pre1 = 0; a_pre2 = 0; a_pre3 = 0;
        a_rc0 = 0; a_rc1 = 0; a_rc2 = 0; a_rc3 = 0;
        a_wr0 = 0; a_wr1 = 0; a_wr2 = 0; a_wr3 = 0;
        a_rrd = 0; a_rfc = 0; a_mrd = 0; a_ccd = 0;
        h_ras0 = 0; h_ras1 = 0; h_ras2 = 0; h_ras3 = 0;
    end

    // After the test has presented the command, and before the next
    // rising edge. A blocking write inside the age block does not reach
    // this compare under Icarus 13, so the copy stays in its own block.
    always @(negedge ck) begin
        h_ras0 = a_ras0; h_ras1 = a_ras1; h_ras2 = a_ras2; h_ras3 = a_ras3;
    end

    always @(posedge ck) begin
        // Stick one short of the limit. The command edge itself is the
        // last clock of the interval, and under Icarus 13 the compare
        // reads the age after this block has stepped it.
        n_act0 = (T_RCD <= 1 || a_act0 == 0) ? a_act0 : (a_act0 >= T_RCD - 1 ? a_act0 : a_act0 + 16'd1);
        n_act1 = (T_RCD <= 1 || a_act1 == 0) ? a_act1 : (a_act1 >= T_RCD - 1 ? a_act1 : a_act1 + 16'd1);
        n_act2 = (T_RCD <= 1 || a_act2 == 0) ? a_act2 : (a_act2 >= T_RCD - 1 ? a_act2 : a_act2 + 16'd1);
        n_act3 = (T_RCD <= 1 || a_act3 == 0) ? a_act3 : (a_act3 >= T_RCD - 1 ? a_act3 : a_act3 + 16'd1);
        // tRAS reaches its limit. One idle after ACT leaves it short;
        // the next idle is the first count a precharge may use. Other
        // counters stick one short, because their command does not clear
        // them and the compare would otherwise treat that idle as enough.
        n_ras0 = (T_RAS <= 1 || a_ras0 == 0) ? a_ras0 : (a_ras0 >= T_RAS ? a_ras0 : a_ras0 + 16'd1);
        n_ras1 = (T_RAS <= 1 || a_ras1 == 0) ? a_ras1 : (a_ras1 >= T_RAS ? a_ras1 : a_ras1 + 16'd1);
        n_ras2 = (T_RAS <= 1 || a_ras2 == 0) ? a_ras2 : (a_ras2 >= T_RAS ? a_ras2 : a_ras2 + 16'd1);
        n_ras3 = (T_RAS <= 1 || a_ras3 == 0) ? a_ras3 : (a_ras3 >= T_RAS ? a_ras3 : a_ras3 + 16'd1);
        n_pre0 = (T_RP  <= 1 || a_pre0 == 0) ? a_pre0 : (a_pre0 >= T_RP  - 1 ? a_pre0 : a_pre0 + 16'd1);
        n_pre1 = (T_RP  <= 1 || a_pre1 == 0) ? a_pre1 : (a_pre1 >= T_RP  - 1 ? a_pre1 : a_pre1 + 16'd1);
        n_pre2 = (T_RP  <= 1 || a_pre2 == 0) ? a_pre2 : (a_pre2 >= T_RP  - 1 ? a_pre2 : a_pre2 + 16'd1);
        n_pre3 = (T_RP  <= 1 || a_pre3 == 0) ? a_pre3 : (a_pre3 >= T_RP  - 1 ? a_pre3 : a_pre3 + 16'd1);
        n_rc0  = (T_RC  <= 1 || a_rc0  == 0) ? a_rc0  : (a_rc0  >= T_RC  - 1 ? a_rc0  : a_rc0  + 16'd1);
        n_rc1  = (T_RC  <= 1 || a_rc1  == 0) ? a_rc1  : (a_rc1  >= T_RC  - 1 ? a_rc1  : a_rc1  + 16'd1);
        n_rc2  = (T_RC  <= 1 || a_rc2  == 0) ? a_rc2  : (a_rc2  >= T_RC  - 1 ? a_rc2  : a_rc2  + 16'd1);
        n_rc3  = (T_RC  <= 1 || a_rc3  == 0) ? a_rc3  : (a_rc3  >= T_RC  - 1 ? a_rc3  : a_rc3  + 16'd1);
        n_wr0  = (T_WR  <= 1 || a_wr0  == 0) ? a_wr0  : (a_wr0  >= T_WR  - 1 ? a_wr0  : a_wr0  + 16'd1);
        n_wr1  = (T_WR  <= 1 || a_wr1  == 0) ? a_wr1  : (a_wr1  >= T_WR  - 1 ? a_wr1  : a_wr1  + 16'd1);
        n_wr2  = (T_WR  <= 1 || a_wr2  == 0) ? a_wr2  : (a_wr2  >= T_WR  - 1 ? a_wr2  : a_wr2  + 16'd1);
        n_wr3  = (T_WR  <= 1 || a_wr3  == 0) ? a_wr3  : (a_wr3  >= T_WR  - 1 ? a_wr3  : a_wr3  + 16'd1);
        n_rrd  = (T_RRD <= 1 || a_rrd  == 0) ? a_rrd  : (a_rrd  >= T_RRD - 1 ? a_rrd  : a_rrd  + 16'd1);
        n_rfc  = (T_RFC <= 1 || a_rfc  == 0) ? a_rfc  : (a_rfc  >= T_RFC - 1 ? a_rfc  : a_rfc  + 16'd1);
        n_mrd  = (T_MRD <= 1 || a_mrd  == 0) ? a_mrd  : (a_mrd  >= T_MRD - 1 ? a_mrd  : a_mrd  + 16'd1);
        n_ccd  = (T_CCD <= 1 || a_ccd  == 0) ? a_ccd  : (a_ccd  >= T_CCD - 1 ? a_ccd  : a_ccd  + 16'd1);

        // Age updates only. The held copies live in their own block so
        // this block's blocking writes cannot replace them. ACT on T loads
        // 1; the command on T+need is the first legal one.
        if (cke && cs_n) begin
            if (T_RCD > 0) begin a_act0 = n_act0; a_act1 = n_act1; a_act2 = n_act2; a_act3 = n_act3; end
            if (T_RAS > 0) begin a_ras0 = n_ras0; a_ras1 = n_ras1; a_ras2 = n_ras2; a_ras3 = n_ras3; end
            if (T_RP  > 0) begin a_pre0 = n_pre0; a_pre1 = n_pre1; a_pre2 = n_pre2; a_pre3 = n_pre3; end
            if (T_RC  > 0) begin a_rc0  = n_rc0;  a_rc1  = n_rc1;  a_rc2  = n_rc2;  a_rc3  = n_rc3;  end
            if (T_WR  > 0) begin a_wr0  = n_wr0;  a_wr1  = n_wr1;  a_wr2  = n_wr2;  a_wr3  = n_wr3;  end
            if (T_RRD > 0) a_rrd = n_rrd;
            if (T_RFC > 0) a_rfc = n_rfc;
            if (T_MRD > 0) a_mrd = n_mrd;
            if (T_CCD > 0) a_ccd = n_ccd;
        end else if (cke && !cs_n && !ras_n && cas_n && we_n) begin
            // ACT
            if (ba == 0) begin a_act0 = 16'd1; a_rc0 = 16'd1; a_ras0 = 16'd1; end
            if (ba == 1) begin a_act1 = 16'd1; a_rc1 = 16'd1; a_ras1 = 16'd1; end
            if (ba == 2) begin a_act2 = 16'd1; a_rc2 = 16'd1; a_ras2 = 16'd1; end
            if (ba == 3) begin a_act3 = 16'd1; a_rc3 = 16'd1; a_ras3 = 16'd1; end
            a_rrd = 16'd1;
        end else if (cke && !cs_n && ras_n && !cas_n) begin
            // READ (we_n high) or WRITE (we_n low)
            a_ccd = 16'd1;
            if (!we_n) begin
                if (ba == 0) a_wr0 = 16'd1;
                if (ba == 1) a_wr1 = 16'd1;
                if (ba == 2) a_wr2 = 16'd1;
                if (ba == 3) a_wr3 = 16'd1;
            end
            if (a10) begin
                // Auto precharge starts the precharge age at this command,
                // earlier than the end of a BL>1 burst. BL>1 is therefore
                // conservative; BL=1 matches the command.
                if (ba == 0) begin a_pre0 = 16'd1; a_act0 = 16'd0; a_ras0 = 16'd0; end
                if (ba == 1) begin a_pre1 = 16'd1; a_act1 = 16'd0; a_ras1 = 16'd0; end
                if (ba == 2) begin a_pre2 = 16'd1; a_act2 = 16'd0; a_ras2 = 16'd0; end
                if (ba == 3) begin a_pre3 = 16'd1; a_act3 = 16'd0; a_ras3 = 16'd0; end
            end
        end else if (cke && !cs_n && !ras_n && cas_n && !we_n) begin
            // PRE. A10 precharges every bank.
            if (a10) begin
                a_pre0 = 16'd1; a_act0 = 16'd0; a_ras0 = 16'd0;
                a_pre1 = 16'd1; a_act1 = 16'd0; a_ras1 = 16'd0;
                a_pre2 = 16'd1; a_act2 = 16'd0; a_ras2 = 16'd0;
                a_pre3 = 16'd1; a_act3 = 16'd0; a_ras3 = 16'd0;
            end else begin
                if (ba == 0) begin a_pre0 = 16'd1; a_act0 = 16'd0; a_ras0 = 16'd0; end
                if (ba == 1) begin a_pre1 = 16'd1; a_act1 = 16'd0; a_ras1 = 16'd0; end
                if (ba == 2) begin a_pre2 = 16'd1; a_act2 = 16'd0; a_ras2 = 16'd0; end
                if (ba == 3) begin a_pre3 = 16'd1; a_act3 = 16'd0; a_ras3 = 16'd0; end
            end
        end else if (cke && !cs_n && !ras_n && !cas_n && we_n) begin
            // REF
            a_rfc = 16'd1;
        end else if (cke && !cs_n && !ras_n && !cas_n && !we_n) begin
            // MRS
            a_mrd = 16'd1;
        end
    end

endmodule

`default_nettype wire
