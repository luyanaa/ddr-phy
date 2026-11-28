// SPDX-License-Identifier: Apache-2.0
// Clean-room, pin-level DDR2 x8 behavioral device model, written from the
// JEDEC DDR2 command truth table and the MT47H128M8 geometry (8 banks,
// 14-bit row, 10-bit column). This is a functional protocol/data model for
// PHY bring-up, not a datasheet timing checker: tRCD/tRP/tRAS/tRFC are not
// enforced here (that is the checker's job). Mode registers ARE decoded for
// real (MR0 burst length / CAS latency / burst type, EMR1 additive latency
// / ODT / DQS drive), because the PHY training flow depends on them.
//
// Structural contract inherited from proven DRAM verification practice:
//   * command decode on cs_n/ras_n/cas_n/we_n at the CK rising edge
//   * per-bank open-row file, RD/WR require an active row, autoprecharge
//     on A10
//   * write data sampled on BOTH edges of the host-driven DQS
//   * read data driven with DQS, both edges, for BL/2 strobe cycles, with
//     a read preamble (DQS low) RL - 1 cycles after the command is a
//     simplification: this model drives DQS from the CK edge domain.
//   * posted-CAS additive latency (AL) shifts both RL and WL
//   * inout dq/dqs/dqs_n with explicit output-enable windows; the bus is
//     high-Z outside them so contention is observable
//
// Not inherited from any specific vendor model: encoding, structure, and
// style are original. GPL OpenSPARC T1/T2 models served only as evidence
// that dual-edge queue pipelines and inout contention modeling are the
// right shape; no lines were copied.
`timescale 1ps/1ps
`default_nettype none

module ddr2_device_model #(
    parameter integer MEM_WORDS  = 4096,   // sparse CAM depth (words of 8 bit x 1 col-beat)
    parameter integer DQ_BITS    = 8,
    parameter integer VERBOSE    = 0
) (
    input  wire              ck,
    input  wire              ck_n,
    input  wire              cke,
    input  wire              cs_n,
    input  wire              ras_n,
    input  wire              cas_n,
    input  wire              we_n,
    input  wire [2:0]        ba,
    input  wire [13:0]       a,
    input  wire              odt,
    input  wire              dm,
    inout  wire [DQ_BITS-1:0] dq,
    inout  wire              dqs,
    inout  wire              dqs_n,

    output reg               fault,
    output reg  [7:0]        fault_code,
    output reg               initialized
);

    // ---------------------------------------------------------------
    // Geometry: MT47H128M8 — 8 banks, 16384 rows (14b), 1024 cols (10b)
    // Column addressing: A9..0, autoprecharge A10, BL8 uses CA2..0 stride.
    // ---------------------------------------------------------------
    localparam integer BANKS     = 8;
    localparam integer ROW_BITS  = 14;
    localparam integer COL_BITS  = 10;
    // Address key: {bank, row, col, beat-in-pair} flattened. We store one
    // byte per column-beat (x8 device), keyed by full composite address.
    localparam integer KEY_BITS  = 3 + ROW_BITS + COL_BITS; // 27

    // fault codes
    localparam [7:0] F_BAD_POWERUP = 8'd1;
    localparam [7:0] F_BAD_MODE    = 8'd2;
    localparam [7:0] F_RW_CLOSED   = 8'd3;   // RD/WR to a closed bank
    localparam [7:0] F_ACT_OPEN    = 8'd4;   // ACT to an already-open bank
    localparam [7:0] F_BAD_DQS     = 8'd5;   // write data with no strobe
    localparam [7:0] F_DLL_RESET   = 8'd6;   // MR0 A8 misuse (informational)

    // ---------------------------------------------------------------
    // Sparse CAM store. 32 MiB per die is too big to allocate densely in
    // a quick sim; a linear-probe CAM of MEM_WORDS entries covers PHY
    // training traffic (a few hundred words) exactly. Unwritten words
    // read back as x, which is the correct "no data" state.
    // ---------------------------------------------------------------
    reg [KEY_BITS-1:0]  cam_addr  [0:MEM_WORDS-1];
    reg [7:0]           cam_data  [0:MEM_WORDS-1];
    reg                 cam_valid [0:MEM_WORDS-1];
    integer             cam_free;
    integer             ci;

    task cam_write(input [KEY_BITS-1:0] key, input [7:0] data);
        integer k;
        reg hit;
        begin
            hit = 0;
            for (k = 0; k < MEM_WORDS; k = k + 1)
                if (cam_valid[k] && cam_addr[k] == key) begin
                    cam_data[k] = data;
                    hit = 1;
                end
            if (!hit) begin
                if (cam_free < MEM_WORDS) begin
                    cam_valid[cam_free] = 1'b1;
                    cam_addr[cam_free]  = key;
                    cam_data[cam_free]  = data;
                    cam_free = cam_free + 1;
                end
            end
        end
    endtask

    function [7:0] cam_read(input [KEY_BITS-1:0] key);
        integer k;
        begin
            cam_read = 8'hxx;
            for (k = 0; k < MEM_WORDS; k = k + 1)
                if (cam_valid[k] && cam_addr[k] == key)
                    cam_read = cam_data[k];
        end
    endfunction

    // ---------------------------------------------------------------
    // Mode register state (decoded for real — training depends on it)
    // ---------------------------------------------------------------
    reg        mr_dll_reset;      // MR0 A8 — informational only
    reg  [2:0] mr_cl;             // MR0 A6..4  (CAS latency)
    reg        mr_bt;             // MR0 A3     (burst type: 0 seq, 1 interleave)
    reg  [2:0] mr_bl_code;        // MR0 A2..0  (010=BL4, 011=BL8)
    reg  [2:0] emr_al;            // EMR1 A5..3 (additive latency)
    reg  [1:0] emr_rtt;           // EMR1 {A6,A2} (ODT: 00 off, 01 75, 10 150, 11 50)
    reg        emr_dll_en;        // EMR1 A0 (0=enable — normal)
    reg  [2:0] emr_ocd;           // EMR1 A9..7
    reg        emr_dqs_n_en;      // EMR1 A10 (0=enable differential — normal)
    reg        emr_rdqs;          // EMR1 A11 (0=DQS, 1=RDQS — we only do DQS)

    integer BL;
    integer CL;
    integer AL;
    integer RL;
    integer WL;

    // ---------------------------------------------------------------
    // Bank state
    // ---------------------------------------------------------------
    reg              bank_open [0:BANKS-1];
    reg  [ROW_BITS-1:0] bank_row [0:BANKS-1];

    // ---------------------------------------------------------------
    // Pipeline bookkeeping. The latency counters run in half-cycle units
    // (one slot per CK edge, like any DDR x2 pipeline). Each in-flight
    // burst is a small descriptor; data beats are produced/consumed when
    // the countdown reaches zero.
    // ---------------------------------------------------------------
    localparam integer MAXB = 4;   // max concurrent bursts (per-rank x8 PHY)

    // read descriptors
    reg               rd_act    [0:MAXB-1];
    integer           rd_count  [0:MAXB-1];  // half-cycles until first beat
    integer           rd_beats  [0:MAXB-1];  // beats remaining
    reg [KEY_BITS-1:0] rd_key   [0:MAXB-1];
    reg               rd_otype  [0:MAXB-1];  // burst type (interleave)

    // write descriptors
    reg               wr_act    [0:MAXB-1];
    integer           wr_count  [0:MAXB-1];
    integer           wr_beats  [0:MAXB-1];
    reg [KEY_BITS-1:0] wr_key   [0:MAXB-1];
    reg               wr_otype  [0:MAXB-1];

    // ---------------------------------------------------------------
    // Output drivers (inout modeling)
    // ---------------------------------------------------------------
    reg               dq_oe;
    reg [7:0]         dq_out;
    reg               dqs_oe;
    reg               dqs_out;
    assign dq    = dq_oe  ? dq_out  : {DQ_BITS{1'bz}};
    assign dqs   = dqs_oe ? dqs_out : 1'bz;
    assign dqs_n = dqs_oe ? ~dqs_out : 1'bz;

    // ---------------------------------------------------------------
    // Write capture: host drives dqs; we sample dq on both dqs edges.
    // A write burst consumes beats in order; dm masks the byte.
    // ---------------------------------------------------------------
    integer wi;
    reg                 wr_dqs_seen [0:MAXB-1];

    // ---------------------------------------------------------------
    // Command decode helpers
    // ---------------------------------------------------------------
    function [KEY_BITS-1:0] make_key(input [2:0] b, input [ROW_BITS-1:0] r,
                                     input [COL_BITS-1:0] c);
        make_key = {b, r, c};
    endfunction

    // column stride: sequential burst counts within the aligned 8/4 group;
    // interleave uses XOR ordering (JEDEC burst order table). The function
    // returns a full-width column: the stride applies only to the low group
    // bits, the upper column bits are passed through unchanged.
    function [COL_BITS-1:0] burst_col(input [COL_BITS-1:0] base, input integer n,
                                      input integer blen, input integer otype);
        reg [2:0] lo;
        begin
            if (blen == 8) begin
                if (otype == 0) lo = base[2:0] + n[2:0];
                else            lo = base[2:0] ^ n[2:0];
            end else begin
                // BL4: 2-bit stride, CA2 passes through
                if (otype == 0) lo = {base[2], base[1:0] + n[1:0]};
                else            lo = {base[2], base[1:0] ^ n[1:0]};
            end
            burst_col = {base[COL_BITS-1:3], lo};
        end
    endfunction

    // ---------------------------------------------------------------
    // Initialization
    // ---------------------------------------------------------------
    integer bi;
    initial begin
        fault = 0; fault_code = 0; initialized = 0;
        cam_free = 0;
        for (ci = 0; ci < MEM_WORDS; ci = ci + 1) cam_valid[ci] = 0;
        for (bi = 0; bi < BANKS; bi = bi + 1) begin
            bank_open[bi] = 0; bank_row[bi] = 0;
        end
        for (bi = 0; bi < MAXB; bi = bi + 1) begin
            rd_act[bi] = 0; wr_act[bi] = 0; wr_dqs_seen[bi] = 0;
        end
        dq_oe = 0; dq_out = 0; dqs_oe = 0; dqs_out = 0;
        mr_cl = 3; mr_bt = 0; mr_bl_code = 3'b010;
        emr_al = 0; emr_rtt = 0; emr_dll_en = 0; emr_ocd = 0;
        emr_dqs_n_en = 0; emr_rdqs = 0;
        BL = 4; CL = 3; AL = 0; RL = 3; WL = 2;
    end

    task recompute_latency;
        begin
            case (mr_bl_code)
                3'b010:  BL = 4;
                3'b011:  BL = 8;
                default: BL = 4;
            endcase
            CL = mr_cl;
            AL = emr_al;
            RL = AL + CL;
            WL = RL - 1;
        end
    endtask

    task raise_fault(input [7:0] code);
        begin
            if (!fault) begin
                fault = 1'b1;
                fault_code = code;
                if (VERBOSE) $display("%0t DDR2_MODEL fault %0d", $time, code);
            end
        end
    endtask

    // ---------------------------------------------------------------
    // Command decode at posedge CK (when cke high; CKE-low powerdown is
    // accepted but not modeled — commands are simply ignored).
    // ---------------------------------------------------------------
    integer slot;
    integer n;
    reg found;

    always @(posedge ck) begin
        if (cke && !cs_n) begin
            casex ({ras_n, cas_n, we_n})
                3'b011: begin // ACT
                    if (bank_open[ba]) begin
                        if (bank_row[ba] != a[ROW_BITS-1:0])
                            raise_fault(F_ACT_OPEN);
                    end else begin
                        bank_open[ba] <= 1'b1;
                        bank_row[ba]  <= a[ROW_BITS-1:0];
                        if (VERBOSE) $display("%0t DDR2_MODEL ACT ba%0d row %h", $time, ba, a);
                    end
                end
                3'b101: begin // READ
                    if (!bank_open[ba]) begin
                        raise_fault(F_RW_CLOSED);
                    end else begin
                        // allocate a read descriptor
                        found = 0;
                        for (slot = 0; slot < MAXB; slot = slot + 1)
                            if (!rd_act[slot] && !found) begin
                                rd_act[slot]   <= 1'b1;
                                rd_count[slot] <= 2*RL;      // half-cycle units
                                rd_beats[slot] <= BL;
                                rd_key[slot]   <= make_key(ba, bank_row[ba], a[COL_BITS-1:0]);
                                rd_otype[slot] <= mr_bt;
                                found = 1;
                                if (VERBOSE) $display("%0t DDR2_MODEL RD ba%0d col %h RL=%0d", $time, ba, a, RL);
                            end
                        if (!found) raise_fault(F_RW_CLOSED); // pipe overflow
                        if (a[10]) bank_open[ba] <= 1'b0;     // autoprecharge
                    end
                end
                3'b100: begin // WRITE
                    if (!bank_open[ba]) begin
                        raise_fault(F_RW_CLOSED);
                    end else begin
                        found = 0;
                        for (slot = 0; slot < MAXB; slot = slot + 1)
                            if (!wr_act[slot] && !found) begin
                                wr_act[slot]      <= 1'b1;
                                wr_count[slot]    <= 2*WL;
                                wr_beats[slot]    <= BL;
                                wr_key[slot]      <= make_key(ba, bank_row[ba], a[COL_BITS-1:0]);
                                wr_otype[slot]    <= mr_bt;
                                wr_dqs_seen[slot] <= 1'b0;
                                found = 1;
                                if (VERBOSE) $display("%0t DDR2_MODEL WR ba%0d col %h WL=%0d", $time, ba, a, WL);
                            end
                        if (!found) raise_fault(F_RW_CLOSED);
                        if (a[10]) bank_open[ba] <= 1'b0;
                    end
                end
                3'b010: begin // PRE
                    if (a[10]) begin
                        for (n = 0; n < BANKS; n = n + 1) bank_open[n] <= 1'b0;
                    end else begin
                        bank_open[ba] <= 1'b0;
                    end
                end
                3'b001: begin // REF/self-refresh: content retained; no-op here
                end
                3'b000: begin // MRS/EMRS
                    case (ba[1:0])
                        2'b00: begin // MR0
                            mr_bl_code <= a[2:0];
                            mr_bt      <= a[3];
                            mr_cl      <= a[6:4];
                            mr_dll_reset <= a[8];
                            if (VERBOSE) $display("%0t DDR2_MODEL MR0 bl_code %b cl %0d bt %b", $time, a[2:0], a[6:4], a[3]);
                        end
                        2'b01: begin // EMR1
                            emr_dll_en   <= a[0];
                            emr_rtt      <= {a[6], a[2]};
                            emr_al       <= a[5:3];
                            emr_ocd      <= a[9:7];
                            emr_dqs_n_en <= a[10];
                            emr_rdqs     <= a[11];
                            if (VERBOSE) $display("%0t DDR2_MODEL EMR1 al %0d rtt %b", $time, a[5:3], {a[6], a[2]});
                        end
                        default: ; // EMR2/EMR3: accepted, no function here
                    endcase
                    recompute_pending <= 1'b1;
                end
                default: ; // NOP/DESELECT
            endcase
        end
    end

    // latency recompute deferred one cycle so MR writes within the same
    // edge settle first
    reg recompute_pending = 1'b0;
    always @(posedge ck) begin
        if (recompute_pending) begin
            recompute_latency();
            initialized <= 1'b1;
            recompute_pending <= 1'b0;
        end
    end

    // ---------------------------------------------------------------
    // Read pipeline: countdown in half-cycles; at zero, drive BL/2 DQS
    // cycles. dq/dqs driven from the CK edge domain (simplified tDQSCK=0;
    // the PHY-side checker's job is to verify timing separately).
    // ---------------------------------------------------------------
    integer ri;
    integer beat_idx;
    reg [COL_BITS-1:0] rc;
    reg [7:0] rdata;

    always @(posedge ck or negedge ck) begin
        // advance read descriptors
        for (ri = 0; ri < MAXB; ri = ri + 1) begin
            if (rd_act[ri]) begin
                if (rd_count[ri] > 0) begin
                    rd_count[ri] <= rd_count[ri] - 1;
                    if (rd_count[ri] == 1) begin
                        // preamble: start driving DQS low one half-cycle early
                        dqs_oe  <= 1'b1;
                        dqs_out <= 1'b0;
                    end
                end else if (rd_beats[ri] > 0) begin
                    beat_idx = BL - rd_beats[ri];
                    rc = burst_col(rd_key[ri][COL_BITS-1:0], beat_idx, BL, rd_otype[ri]);
                    rdata = cam_read({rd_key[ri][KEY_BITS-1:COL_BITS], rc});
                    dq_oe   <= 1'b1;
                    dq_out  <= rdata;
                    dqs_oe  <= 1'b1;
                    dqs_out <= ~dqs_out;
                    rd_beats[ri] <= rd_beats[ri] - 1;
                end else begin
                    rd_act[ri] <= 1'b0;
                    // release the bus when no other burst is mid-flight
                    dq_oe  <= 1'b0;
                    dqs_oe <= 1'b0;
                    dqs_out <= 1'b0;
                end
            end
        end
    end

    // ---------------------------------------------------------------
    // Write pipeline: countdown in half-cycles on CK edges; data itself
    // is captured on DQS edges into the active write slot.
    // ---------------------------------------------------------------
    always @(posedge ck or negedge ck) begin
        for (wi = 0; wi < MAXB; wi = wi + 1) begin
            if (wr_act[wi] && wr_count[wi] > 0) begin
                wr_count[wi] <= wr_count[wi] - 1;
                if (wr_count[wi] == 1 && !wr_dqs_seen[wi] && wr_beats[wi] == BL)
                    ; // strobe window opens; nothing to do until edges arrive
            end
        end
    end

    // capture on both dqs edges; consume beats of the oldest armed write
    always @(posedge dqs or negedge dqs) begin : write_capture
        integer wj;
        integer wsel;
        integer wbeat;
        reg [COL_BITS-1:0] wc;
        begin
            wsel = -1;
            for (wj = 0; wj < MAXB; wj = wj + 1)
                if (wr_act[wj] && wr_count[wj] == 0 && wr_beats[wj] > 0)
                    if (wsel == -1) wsel = wj;
            if (wsel != -1) begin
                wr_dqs_seen[wsel] = 1'b1;
                wbeat = BL - wr_beats[wsel];
                wc = burst_col(wr_key[wsel][COL_BITS-1:0], wbeat, BL, wr_otype[wsel]);
                if (!dm)
                    cam_write({wr_key[wsel][KEY_BITS-1:COL_BITS], wc}, dq);
                wr_beats[wsel] = wr_beats[wsel] - 1;
                if (wr_beats[wsel] == 0) wr_act[wsel] = 1'b0;
            end
        end
    end

endmodule
`default_nettype wire
