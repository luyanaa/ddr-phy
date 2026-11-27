// SPDX-License-Identifier: Apache-2.0
// Pin-level SDR SDRAM behavioral model.
//
// Commands are the usual active-low set. The mode-register fields used
// here are the ones every SDR part documents: A[2:0] burst length
// (1/2/4/8, sequential only), A[6:4] CAS latency (2 or 3). A full-page
// burst is refused. A10 selects all-bank precharge, or auto-precharge
// on a read or write.
//
// This is not a timing checker. tRCD, tRP, tRAS and tRFC are not
// measured. What it does check is the command order a controller can
// get wrong: activate twice, read a closed bank, refresh with a bank
// left open, mode register while a bank is open.
//
// Sampling matches a register-to-register connection. The PHY launches
// a command on edge T; this model sees it on edge T+1. A read accepted
// then is driven CL-1 model clocks later and captured by sdr_phy on the
// next edge. Once the last beat is sampled, the bus returns to Hi-Z.
// Bytes with DM high are left alone.

`default_nettype none

module sdram_model #(
    parameter integer ADDR_BITS = 13,
    parameter integer BANK_BITS = 2,
    parameter integer DATA_BITS = 8,
    parameter integer ROW_BITS  = 4,
    parameter integer COL_BITS  = 4
) (
    input  wire                         ck,
    input  wire                         cke,
    input  wire                         cs_n,
    input  wire                         ras_n,
    input  wire                         cas_n,
    input  wire                         we_n,
    input  wire [BANK_BITS-1:0]         ba,
    input  wire [ADDR_BITS-1:0]         a,
    input  wire [DATA_BITS/8-1:0]       dm,
    inout  wire [DATA_BITS-1:0]         dq,
    output reg                          fault,
    output reg  [2:0]                   fault_code
);

    localparam integer BANKS     = 1 << BANK_BITS;
    localparam integer WORDS     = BANKS * (1 << ROW_BITS) * (1 << COL_BITS);
    localparam integer PIPE      = 9; // CL3 data offset plus eight beats
    localparam integer DM_BITS   = DATA_BITS / 8;

    localparam [2:0] OK         = 3'd0;
    localparam [2:0] BAD_MRS    = 3'd1;
    localparam [2:0] ACT_OPEN   = 3'd2;
    localparam [2:0] RW_CLOSED  = 3'd3;
    localparam [2:0] REF_OPEN   = 3'd4;

    reg [DATA_BITS-1:0] mem [0:WORDS-1];
    reg                 bank_open [0:BANKS-1];
    reg [ROW_BITS-1:0]  bank_row  [0:BANKS-1];

    reg [3:0]           burst_len;
    reg [2:0]           cas_lat;

    reg [DATA_BITS-1:0] slot_d  [0:PIPE-1];
    reg                 slot_oe [0:PIPE-1];
    reg [DATA_BITS-1:0] dq_q;
    reg [DM_BITS-1:0]  oe_q;
    reg [DM_BITS-1:0]  dqm_r1, dqm_r2;

    // Per-byte output enable so read DQM can suppress one byte without
    // releasing the others. dqm_r2 is the DQM sample from two CK edges
    // before the data-out edge, which is the SDR read mask latency.
    genvar g;
    generate
        for (g = 0; g < DM_BITS; g = g + 1) begin : g_dq_byte
            assign dq[8*g +: 8] = oe_q[g] ? dq_q[8*g +: 8] : {8{1'bz}};
        end
    endgenerate

    function automatic integer word_at;
        input integer b;
        input integer r;
        input integer c;
        begin
            word_at = (b << (ROW_BITS + COL_BITS)) | (r << COL_BITS) | c;
        end
    endfunction

    function automatic integer wrap_col;
        input integer base;
        input integer beat;
        input integer bl;
        integer mask;
        begin
            mask = bl - 1;
            wrap_col = (base & ~mask) | ((base + beat) & mask);
        end
    endfunction

    integer i;
    integer beat;
    integer col;
    integer word;
    integer slot;
    integer b;
    integer j;
    reg [DATA_BITS-1:0] nxt_d  [0:PIPE-1];
    reg                 nxt_oe [0:PIPE-1];
    reg [DATA_BITS-1:0] beat_d;
    reg                 any_open;

    // Write-burst continuation state. A WRITE command puts beat 0 on the
    // bus with the command; the remaining beats are sampled on the
    // following CK edges, each with its own DQM.
    reg                    wr_active;
    reg [BANK_BITS-1:0]    wr_bank;
    reg [ROW_BITS-1:0]     wr_row;
    reg [COL_BITS-1:0]     wr_base;
    reg [3:0]              wr_len;
    reg [3:0]              wr_beat;

    initial begin
        fault      = 1'b0;
        fault_code = OK;
        burst_len  = 4'd1;
        cas_lat    = 3'd2;
        oe_q       = {DM_BITS{1'b0}};
        dqm_r1      = {DM_BITS{1'b0}};
        dqm_r2      = {DM_BITS{1'b0}};
        dq_q       = {DATA_BITS{1'b0}};
        wr_active  = 1'b0;
        wr_bank    = {BANK_BITS{1'b0}};
        wr_row     = {ROW_BITS{1'b0}};
        wr_base    = {COL_BITS{1'b0}};
        wr_len     = 4'd1;
        wr_beat    = 4'd0;
        for (i = 0; i < BANKS; i = i + 1)
            bank_open[i] = 1'b0;
        for (i = 0; i < PIPE; i = i + 1)
            slot_oe[i] = 1'b0;
    end

    task automatic raise;
        input [2:0] code;
        begin
            if (!fault) begin
                fault      = 1'b1;
                fault_code = code;
            end
        end
    endtask

    always @(posedge ck) begin
        for (i = 0; i < PIPE-1; i = i + 1) begin
            nxt_d[i]  = slot_d[i+1];
            nxt_oe[i] = slot_oe[i+1];
        end
        nxt_d[PIPE-1]  = {DATA_BITS{1'b0}};
        nxt_oe[PIPE-1] = 1'b0;

        dq_q   <= slot_d[0];
        dqm_r1 <= dm;
        dqm_r2 <= dqm_r1;
        for (j = 0; j < DM_BITS; j = j + 1)
            oe_q[j] <= slot_oe[0] && !dqm_r2[j];

        any_open = 1'b0;
        for (i = 0; i < BANKS; i = i + 1)
            any_open = any_open | bank_open[i];

        // Continue an in-flight write burst. A new WRITE command on this
        // edge restarts the burst instead of consuming a continuation.
        if (cke && wr_active &&
            !(cke && !cs_n && ras_n && !cas_n && !we_n)) begin
            col    = wrap_col(wr_base, wr_beat, wr_len);
            word   = word_at(wr_bank, wr_row, col);
            beat_d = mem[word];
            for (b = 0; b < DM_BITS; b = b + 1)
                if (!dm[b])
                    beat_d[8*b +: 8] = dq[8*b +: 8];
            mem[word] = beat_d;
            if (wr_beat == wr_len - 1) wr_active <= 1'b0;
            else                       wr_beat  <= wr_beat + 4'd1;
        end

        if (cke && !cs_n) begin
            // MRS
            if (!ras_n && !cas_n && !we_n) begin
                if (any_open || ba != {BANK_BITS{1'b0}} || a[3] != 1'b0)
                    raise(BAD_MRS);
                else begin
                    case (a[2:0])
                        3'b000: burst_len <= 4'd1;
                        3'b001: burst_len <= 4'd2;
                        3'b010: burst_len <= 4'd4;
                        3'b011: burst_len <= 4'd8;
                        default: raise(BAD_MRS);
                    endcase
                    case (a[6:4])
                        3'b010: cas_lat <= 3'd2;
                        3'b011: cas_lat <= 3'd3;
                        default: raise(BAD_MRS);
                    endcase
                end
            // ACT
            end else if (!ras_n && cas_n && we_n) begin
                if (bank_open[ba])
                    raise(ACT_OPEN);
                else begin
                    bank_open[ba] <= 1'b1;
                    bank_row[ba]  <= a[ROW_BITS-1:0];
                end
            // READ or WRITE
            end else if (ras_n && !cas_n) begin
                if (!bank_open[ba])
                    raise(RW_CLOSED);
                else begin
                    if (!we_n) begin
                        // WRITE: beat 0 rides with the command. Remaining
                        // beats are sampled by the write pipeline above.
                        col    = wrap_col(a[COL_BITS-1:0], 0, burst_len);
                        word   = word_at(ba, bank_row[ba], col);
                        beat_d = mem[word];
                        for (b = 0; b < DM_BITS; b = b + 1)
                            if (!dm[b])
                                beat_d[8*b +: 8] = dq[8*b +: 8];
                        mem[word] = beat_d;
                        if (burst_len > 1) begin
                            wr_active <= 1'b1;
                            wr_bank   <= ba;
                            wr_row    <= bank_row[ba];
                            wr_base   <= a[COL_BITS-1:0];
                            wr_len    <= burst_len;
                            wr_beat   <= 4'd1;
                        end
                    end else begin
                        // READ: schedule BL 1/2/4/8 beats. Non-beat slots
                        // stay disabled, including after the last beat.
                        for (beat = 0; beat < 8; beat = beat + 1) begin
                            if (beat < burst_len) begin
                                col  = wrap_col(a[COL_BITS-1:0], beat, burst_len);
                                word = word_at(ba, bank_row[ba], col);
                                slot = (cas_lat - 2) + beat;
                                nxt_d[slot]  = mem[word];
                                nxt_oe[slot] = 1'b1;
                            end
                        end
                    end
                    if (a[10])
                        bank_open[ba] <= 1'b0;
                end
            // PRE
            end else if (!ras_n && cas_n && !we_n) begin
                if (a[10]) begin
                    for (i = 0; i < BANKS; i = i + 1)
                        bank_open[i] <= 1'b0;
                end else begin
                    bank_open[ba] <= 1'b0;
                end
            // REF
            end else if (!ras_n && !cas_n && we_n) begin
                if (any_open)
                    raise(REF_OPEN);
            end
        end

        for (i = 0; i < PIPE; i = i + 1) begin
            slot_d[i]  <= nxt_d[i];
            slot_oe[i] <= nxt_oe[i];
        end
    end

endmodule

`default_nettype wire
