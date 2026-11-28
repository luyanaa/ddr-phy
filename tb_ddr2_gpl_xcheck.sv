// SPDX-License-Identifier: Apache-2.0
// Cross-validation testbench: the clean-room DDR2 x8 device model
// (sim/ddr2_device_model.sv, Apache-2.0) is driven in lockstep with the GPL
// OpenSPARC T2 functional DIMM model (dimm_iverilog.v, compiled from
// third_party/ straight out of the submodule; no GPL source is copied into
// this repo). Both models see the same logical command stream; each one is
// captured on its own strobe and the ordered read-beat sequences are
// compared, so a mismatch is a behavioural difference rather than a TB
// timing artifact.
//
// Model A is pin-level DDR2 x8 with a real MRS/EMR decode. Model B has no
// MRS: its "Setup" command programs BurstLen = 1<<addr[2:0] and
// CasLat = addr[6:4] (ba=0) and AlignLat = addr[5:3] (ba=1). The two are
// therefore aligned to BL4 / CL3 / AL0 before any traffic: A via a real
// EMR2/EMR3/EMR1/MR0 sequence, B via Setup commands.
//
// Command pin mapping: B's {cs_d[0], ras, cas, we} decode is literally the
// active-low command encoding of A's {cs_n, ras_n, cas_n, we_n} bus
// (0101=Read, 0100=Write, 0011=ACT, 0000=Setup/MRS), so the same pin levels
// are presented to both models and only the address/bank fields differ
// during init. cs is low to select on both (B: cs=2'b00).
//
// B is x4 and A is x8, so only the low nibble is compared: A drives dq[7:4]
// with zeros during writes and the capture compares dq[3:0].
//
// Timing is deliberately NOT compared cycle-exactly: the two pipelines have
// different constants (B registers its command inputs on the CK edge). For
// each model the first strobe edge after the READ command is measured and
// only checked against that model's own latency contract; the ordered beat
// sequences are compared exactly.
`timescale 1ps/1ps
`default_nettype none

module tb_ddr2_gpl_xcheck;
    localparam integer TCK     = 5000;    // 200 MHz, 1ps/1ps for both models
    localparam integer TSTROBE = TCK / 20; // 250 ps data -> strobe setup

    // ---------------------------------------------------------------
    // Clock: one free-running CK. A samples it on posedge, B uses clk[0]
    // on both edges for its queue pipeline.
    // ---------------------------------------------------------------
    reg  ck = 1'b0;
    always #(TCK/2) ck = ~ck;
    wire ck_n = ~ck;

    // ---------------------------------------------------------------
    // DUT A: clean-room DDR2 x8 device model
    // ---------------------------------------------------------------
    reg         a_cs_n = 1'b1, a_ras_n = 1'b1, a_cas_n = 1'b1, a_we_n = 1'b1;
    reg         a_cke  = 1'b1, a_odt = 1'b0, a_dm = 1'b0;
    reg  [2:0]  a_ba   = 3'd0;
    reg  [13:0] a_a    = 14'd0;
    wire [7:0]  a_dq;
    wire        a_dqs, a_dqs_n;
    wire        a_fault, a_initialized;
    wire [7:0]  a_fault_code;

    reg  [7:0]  a_dq_drv  = 8'h00;
    reg         a_dq_oe   = 1'b0;
    reg         a_dqs_drv = 1'b0;
    reg         a_dqs_oe  = 1'b0;
    assign a_dq    = a_dq_oe   ? a_dq_drv   : 8'hzz;
    assign a_dqs   = a_dqs_oe  ? a_dqs_drv  : 1'bz;
    assign a_dqs_n = a_dqs_oe  ? ~a_dqs_drv : 1'bz;

    ddr2_device_model dut_a (
        .ck(ck), .ck_n(ck_n), .cke(a_cke), .cs_n(a_cs_n),
        .ras_n(a_ras_n), .cas_n(a_cas_n), .we_n(a_we_n),
        .ba(a_ba), .a(a_a), .odt(a_odt), .dm(a_dm),
        .dq(a_dq), .dqs(a_dqs), .dqs_n(a_dqs_n),
        .fault(a_fault), .fault_code(a_fault_code), .initialized(a_initialized)
    );

    // ---------------------------------------------------------------
    // DUT B: GPL OpenSPARC T2 dimm_iverilog golden model (x4)
    // ---------------------------------------------------------------
    wire [2:0]  b_clk;
    reg  [1:0]  b_cs    = 2'b11;
    reg         b_ras   = 1'b0, b_cas = 1'b0, b_we = 1'b0;
    reg  [2:0]  b_ba    = 3'd0;
    reg  [16:0] b_addr  = 17'd0;
    reg  [7:0]  b_cs_sel = 8'h01;
    wire [3:0]  b_dataq;
    wire [7:0]  b_ecc;
    wire        b_dqs, b_dm_rdqs;

    reg  [3:0]  b_dataq_drv = 4'h0;
    reg         b_dataq_oe  = 1'b0;
    reg         b_dqs_drv   = 1'b0;
    reg         b_dqs_oe    = 1'b0;
    assign b_clk   = {3{ck}};
    assign b_dataq = b_dataq_oe ? b_dataq_drv : 4'hzz;
    assign b_dqs   = b_dqs_oe   ? b_dqs_drv   : 1'bz;
    // dm_rdqs / ecc: model-driven during reads, left undriven by the TB.

    dimm_iverilog dut_b (
        .clk(b_clk), .cs(b_cs), .ras(b_ras), .cas(b_cas), .we(b_we),
        .ba(b_ba), .addr(b_addr), .cs_sel(b_cs_sel),
        .dataq(b_dataq), .ecc(b_ecc), .dqs(b_dqs), .dm_rdqs(b_dm_rdqs)
    );

    // ---------------------------------------------------------------
    // Independent beat capture. One sample per strobe edge, taken 1ps
    // after the edge so the model's same-edge NBA update of the data
    // bus has definitely settled. The read preamble drives DQS low while
    // the data bus is still high-Z, so high-Z samples are skipped; that
    // drops the preamble transition and keeps any real X (a store miss)
    // which then fails the comparison.
    // ---------------------------------------------------------------
    reg  [3:0] a_cap  [0:7];
    reg  [3:0] b_cap  [0:7];
    integer    a_cap_n = 0;
    integer    b_cap_n = 0;
    reg        a_cap_en = 1'b0;
    reg        b_cap_en = 1'b0;
    time       a_first_t = 0;
    time       b_first_t = 0;
    time       a_t [0:7];
    time       b_t [0:7];

    always @(posedge a_dqs or negedge a_dqs) begin
        if (a_cap_en) begin
            #1;
            if (a_cap_n < 8 && a_dq[3:0] !== 4'bzzzz) begin
                if (a_cap_n == 0) a_first_t = $time;
                a_t[a_cap_n] = $time;
                a_cap[a_cap_n] = a_dq[3:0];
                a_cap_n = a_cap_n + 1;
            end
        end
    end

    always @(posedge b_dqs or negedge b_dqs) begin
        if (b_cap_en) begin
            #1;
            if (b_cap_n < 8 && b_dataq !== 4'bzzzz) begin
                if (b_cap_n == 0) b_first_t = $time;
                b_t[b_cap_n] = $time;
                b_cap[b_cap_n] = b_dataq;
                b_cap_n = b_cap_n + 1;
            end
        end
    end

    // ---------------------------------------------------------------
    // Command driver: present the command on BOTH buses at a negedge so
    // both models sample it at the following posedge (t_cmd), then hold
    // for exactly one CK cycle and deselect. Holding longer would make
    // each model re-decode the same command every cycle.
    //   s/r/c/w are the raw command pin levels: for A they are
    //   cs_n/ras_n/cas_n/we_n, for B they are cs[0]/ras/cas/we -- the two
    //   encodings are identical (0101 Read, 0100 Write, 0011 ACT, 0000 MRS
    //   or Setup).
    // ---------------------------------------------------------------
    time t_cmd;

    task issue(input s, input r, input c, input w,
               input [2:0] aba, input [13:0] aa,
               input [2:0] bba, input [16:0] baddr);
        begin
            @(negedge ck);
            a_cs_n = s; a_ras_n = r; a_cas_n = c; a_we_n = w;
            a_ba = aba; a_a = aa;
            b_cs = {2{s}}; b_ras = r; b_cas = c; b_we = w;
            b_ba = bba; b_addr = baddr;
            @(posedge ck);              // both models sample here
            t_cmd = $time;
            #(TCK/50);                  // 100 ps hold
            a_cs_n = 1'b1; a_ras_n = 1'b1; a_cas_n = 1'b1; a_we_n = 1'b1;
            b_cs = 2'b11; b_ras = 1'b0; b_cas = 1'b0; b_we = 1'b0;
        end
    endtask

    task nop;
        begin
            issue(1'b1, 1'b1, 1'b1, 1'b1, 3'd0, 14'd0, 3'd0, 17'd0);
        end
    endtask

    // ---------------------------------------------------------------
    // Write data phase (proven pattern, adapted to both models):
    //   WL = 2 CK, so the first beat is presented 2 CK after the WRITE
    //   command is sampled, one beat per CK edge (4 beats = 4 edges).
    //   Data changes at the CK edge, the strobe toggles TSTROBE later.
    //     A samples dq on both strobe edges once its WL counter has
    //     expired (t_cmd+2CK), i.e. all four edges land in the window.
    //     B samples dataq on the same edges and consumes the delayed
    //     sample at write_queue[2] (t_cmd+2.5CK +n*0.5CK), which is
    //     1850 ps after the corresponding sample and 650 ps before the
    //     next one -- no races either way.
    // ---------------------------------------------------------------
    task wr_beats(input [15:0] pat);
        integer i;
        begin
            a_dq_oe = 1'b1; a_dqs_oe = 1'b1; a_dqs_drv = 1'b0;
            b_dataq_oe = 1'b1; b_dqs_oe = 1'b1; b_dqs_drv = 1'b0;
            a_dq_drv = {4'h0, pat[3:0]};
            b_dataq_drv = pat[3:0];
            #(t_cmd + 2*TCK - $time);   // t_cmd + 2 CK: beat 0
            for (i = 0; i < 4; i = i + 1) begin
                a_dq_drv    = {4'h0, pat[4*i +: 4]};
                b_dataq_drv = pat[4*i +: 4];
                #(TSTROBE);
                a_dqs_drv = ~a_dqs_drv;
                b_dqs_drv = ~b_dqs_drv;
                #(TCK/2 - TSTROBE);     // next beat is a CK edge away
            end
            // strobe parked low (even number of toggles) -> releasing it
            // raises no edge; park the data buses too.
            a_dq_oe = 1'b0; a_dqs_oe = 1'b0;
            b_dataq_oe = 1'b0; b_dqs_oe = 1'b0;
        end
    endtask

    task issue_read(input [9:0] col);
        begin
            // release the TB drivers so the models own the buses
            a_dq_oe = 1'b0; a_dqs_oe = 1'b0; a_dqs_drv = 1'b0;
            b_dataq_oe = 1'b0; b_dqs_oe = 1'b0; b_dqs_drv = 1'b0;
            a_cap_n = 0; b_cap_n = 0;
            a_first_t = 0; b_first_t = 0;
            issue(1'b0, 1'b1, 1'b0, 1'b1, 3'd0, {4'h0, col},
                  3'd0, {7'h0, col});   // READ: cs low, RAS high, CAS low, WE high
            a_cap_en = 1'b1;
            b_cap_en = 1'b1;
        end
    endtask

    // ---------------------------------------------------------------
    // Comparison
    // ---------------------------------------------------------------
    integer errors = 0;
    integer lat_a, lat_b;

    task check_beats(input [15:0] exp, input integer col);
        integer i;
        begin
            if (a_cap_n != 4) begin
                errors = errors + 1;
                $display("XCHECK_FAIL col %0h: model A captured %0d beats (expected 4)",
                         col, a_cap_n);
            end
            if (b_cap_n != 4) begin
                errors = errors + 1;
                $display("XCHECK_FAIL col %0h: model B captured %0d beats (expected 4)",
                         col, b_cap_n);
            end
            for (i = 0; i < 4; i = i + 1) begin
                if (a_cap[i] !== exp[4*i +: 4]) begin
                    errors = errors + 1;
                    $display("XCHECK_FAIL col %0h: model A beat %0d = %h, expected %h",
                             col, i, a_cap[i], exp[4*i +: 4]);
                end
                if (b_cap[i] !== exp[4*i +: 4]) begin
                    errors = errors + 1;
                    $display("XCHECK_FAIL col %0h: model B beat %0d = %h, expected %h",
                             col, i, b_cap[i], exp[4*i +: 4]);
                end
                if (a_cap_n == 4 && b_cap_n == 4 && a_cap[i] !== b_cap[i]) begin
                    errors = errors + 1;
                    $display("XCHECK_FAIL col %0h: model A beat %0d = %h but model B beat %0d = %h",
                             col, i, a_cap[i], i, b_cap[i]);
                end
            end

            // Per-model first-strobe latency (reported; checked only
            // against each model's own contract, never against the other).
            if (a_first_t == 0 || b_first_t == 0) begin
                errors = errors + 1;
                $display("XCHECK_FAIL col %0h: missing strobe edge (A=%0t B=%0t)",
                         col, a_first_t, b_first_t);
            end else begin
                lat_a = ((a_first_t - t_cmd) * 10) / TCK;
                lat_b = ((b_first_t - t_cmd) * 10) / TCK;
                $display("XCHECK_INFO col %0h first strobe edge: A = %0d.%0d CK, B = %0d.%0d CK after READ",
                         col, lat_a / 10, lat_a % 10, lat_b / 10, lat_b % 10);
                // A: RL = CL+AL = 3, DQS driven from the CK edge domain ->
                // first strobe edge lands in RL .. RL+1 CK.
                if (lat_a < 25 || lat_a > 45) begin
                    errors = errors + 1;
                    $display("XCHECK_FAIL col %0h: model A first strobe edge %0d.%0d CK violates RL=3",
                             col, lat_a / 10, lat_a % 10);
                end
                // B: ReadLat = AL+CL = 3 in full CK with its one-cycle
                // input registration; its own pipeline puts the first data
                // edge at 2.5 CK from the command.
                if (lat_b < 15 || lat_b > 35) begin
                    errors = errors + 1;
                    $display("XCHECK_FAIL col %0h: model B first strobe edge %0d.%0d CK outside its ReadLat=3 contract",
                             col, lat_b / 10, lat_b % 10);
                end
            end
        end
    endtask

    // ---------------------------------------------------------------
    // Main sequence
    // ---------------------------------------------------------------
    initial begin : main
        // 1. init both models to BL4 / CL3 / AL0
        //    A: real EMR2/EMR3/EMR1/MRS sequence, B: Setup commands
        //    (B: BurstLen = 1<<addr[2:0] -> addr[2:0]=010 gives BL4,
        //     CasLat = addr[6:4] -> 011 gives CL3; AlignLat = addr[5:3])
        issue(1'b0, 1'b0, 1'b0, 1'b0, 3'd2, 14'h0000, 3'd0, 17'h00032);
        issue(1'b0, 1'b0, 1'b0, 1'b0, 3'd3, 14'h0000, 3'd1, 17'h00000);
        issue(1'b0, 1'b0, 1'b0, 1'b0, 3'd1, 14'h0000, 3'd3, 17'h00000);
        issue(1'b0, 1'b0, 1'b0, 1'b0, 3'd0, 14'h0032, 3'd0, 17'h00032);
        nop();
        nop();

        // 2. ACT bank 0, row 0x0100 on both
        issue(1'b0, 1'b0, 1'b1, 1'b1, 3'd0, 14'h0100, 3'd0, 17'h00100);
        nop();

        // 3. WRITE col 0x004, 4 beats on the low nibble
        issue(1'b0, 1'b1, 1'b0, 1'b0, 3'd0, 14'h0004, 3'd0, 17'h00004);
        wr_beats(16'hEBAD);         // beats D A B E
        nop();

        // 4. READ col 0x004, capture on each model's own strobe
        issue_read(10'h004);
        repeat (9) @(posedge ck);   // A finishes its burst at t+5 CK
        a_cap_en = 1'b0;
        b_cap_en = 1'b0;
        $display("XCHECK_INFO read col 004: A beats %h %h %h %h, B beats %h %h %h %h",
                 a_cap[0], a_cap[1], a_cap[2], a_cap[3],
                 b_cap[0], b_cap[1], b_cap[2], b_cap[3]);
        check_beats(16'hEBAD, 16'h004);

        // 5. WRITE col 0x008 with a different pattern, read it back
        nop();
        issue(1'b0, 1'b1, 1'b0, 1'b0, 3'd0, 14'h0008, 3'd0, 17'h00008);
        wr_beats(16'hA5C3);         // beats 3 C 5 A
        nop();
        issue_read(10'h008);
        repeat (9) @(posedge ck);
        a_cap_en = 1'b0;
        b_cap_en = 1'b0;
        $display("XCHECK_INFO read col 008: A beats %h %h %h %h, B beats %h %h %h %h",
                 a_cap[0], a_cap[1], a_cap[2], a_cap[3],
                 b_cap[0], b_cap[1], b_cap[2], b_cap[3]);
        check_beats(16'hA5C3, 16'h008);

        // 6. final status
        if (a_fault) begin
            errors = errors + 1;
            $display("XCHECK_FAIL model A raised fault, code %0d", a_fault_code);
        end
        if (!a_initialized) begin
            errors = errors + 1;
            $display("XCHECK_FAIL model A never reported initialized after MRS");
        end
        $display("XCHECK_INFO model A stores used: %0d, model B stores used: %0d",
                 dut_a.cam_free, dut_b.mem_free);
        if (dut_a.cam_free < 8) begin
            errors = errors + 1;
            $display("XCHECK_FAIL model A stored only %0d words for two 4-beat writes",
                     dut_a.cam_free);
        end
        if (dut_b.mem_free < 8) begin
            errors = errors + 1;
            $display("XCHECK_FAIL model B stored only %0d nibbles for two 4-beat writes",
                     dut_b.mem_free);
        end

        if (errors == 0) begin
            $display("XCHECK_INFO both models returned identical beat sequences");
            $display("XCHECK_PASS");
        end else begin
            $display("XCHECK_FAIL %0d mismatches", errors);
        end
        $finish;
    end

    initial begin
        #5000000;                   // 5 us watchdog
        $display("XCHECK_FAIL watchdog timeout");
        $finish;
    end
endmodule
`default_nettype wire
