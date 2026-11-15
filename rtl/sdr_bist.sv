// SPDX-License-Identifier: Apache-2.0
// BIST / DFT for the SDR PHY loop.
//
// Writes a PRBS-8 pattern through the sdr_ctrl user interface, reads it
// back, compares, and counts errors. Phase scan steps phase_sel after each
// completed run when scan_en is set. This is a diagnostic aid, not a
// replacement for timing sign-off, and it does not implement any DRAM
// training sequence.
//
// The user interface is issued one cycle before sdr_ctrl samples it:
// sdr_ctrl registers user_valid on posedge clk, so a nonblocking assign
// made on that same edge would be invisible. S_*_WAIT holds the request
// stable for one edge, then deasserts.

`default_nettype none
module sdr_bist #(
    parameter integer DATA_BITS  = 8,
    parameter integer USER_BITS  = 10,
    parameter integer SEL_W      = 2,
    parameter integer NPATTERNS  = 16
)(
    input  wire                    clk,
    input  wire                    rst,
    input  wire                    start,
    input  wire                    scan_en,
    input  wire [SEL_W-1:0]        phase_min,
    input  wire [SEL_W-1:0]        phase_max,

    output reg  [SEL_W-1:0]        phase_sel,
    output reg                     phase_scan_done,
    output reg  [31:0]             error_count,
    output reg  [31:0]             pattern_count,
    output reg                     bist_busy,
    output reg                     bist_pass,

    output reg                     user_valid,
    output reg                     user_we,
    output reg  [USER_BITS-1:0]    user_addr,
    output reg  [DATA_BITS-1:0]    user_wdata,
    input  wire                    user_ready,
    input  wire [DATA_BITS-1:0]    user_rdata,
    input  wire                    user_rvalid
);
    localparam integer WORDS = NPATTERNS;
    localparam [2:0] S_IDLE = 3'd0, S_WR = 3'd1, S_WR_WAIT = 3'd2,
                     S_RD = 3'd3, S_RD_WAIT = 3'd4, S_DONE = 3'd5;

    reg [2:0]   state;
    reg [31:0]  lfsr;
    reg [31:0]  expected [0:WORDS-1];
    reg [31:0]  waddr, raddr, rdata_idx;
    reg [31:0]  run_errors;
    // sdr_ctrl registers user_ready, so it stays high for one edge after
    // accepting a request. Without a gap BIST would issue again into that
    // stale-high window and the request would be silently dropped.
    reg [2:0]   gap;
    integer     i;

    wire [31:0] lfsr_next = {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE; lfsr <= 32'hA5A5A5A5;
            waddr <= 0; raddr <= 0; rdata_idx <= 0;
            gap <= 3'd0;
            error_count <= 0; pattern_count <= 0; run_errors <= 0;
            phase_sel <= {SEL_W{1'b0}}; phase_scan_done <= 1'b0;
            bist_busy <= 1'b0; bist_pass <= 1'b0;
            user_valid <= 1'b0; user_we <= 1'b0; user_addr <= 0; user_wdata <= 0;
            for (i = 0; i < WORDS; i = i + 1) expected[i] <= 32'd0;
        end else begin
            // Returned read data is counted on its own strobe, independent
            // of which issue state the FSM is in.
            if (user_rvalid) begin
                if (user_rdata !== expected[rdata_idx][DATA_BITS-1:0])
                    run_errors <= run_errors + 1;
                rdata_idx <= rdata_idx + 1;
            end

            case (state)
                S_IDLE: begin
                    bist_busy <= 1'b0;
                    if (start) begin
                        state           <= S_WR;
                        waddr           <= 0;
                        raddr           <= 0;
                        rdata_idx       <= 0;
                        lfsr            <= 32'hA5A5A5A5;
                        run_errors      <= 0;
                        bist_busy       <= 1'b1;
                        bist_pass       <= 1'b0;
                        phase_scan_done <= 1'b0;
                        phase_sel       <= phase_min;
                        user_valid      <= 1'b0;
                    end
                end
                S_WR: begin
                    if (gap != 3'd0) gap <= gap - 3'd1;
                    else if (user_ready) begin
                        user_valid      <= 1'b1;
                        user_we         <= 1'b1;
                        user_addr       <= waddr[USER_BITS-1:0];
                        user_wdata      <= lfsr[DATA_BITS-1:0];
                        expected[waddr] <= lfsr[DATA_BITS-1:0];
                        lfsr            <= lfsr_next;
                        state           <= S_WR_WAIT;
                    end
                end
                S_WR_WAIT: begin
                    user_valid    <= 1'b0;
                    gap           <= 3'd3;
                    waddr         <= waddr + 1;
                    pattern_count <= pattern_count + 1;
                    state         <= (waddr == WORDS - 1) ? S_RD : S_WR;
                end
                S_RD: begin
                    if (gap != 3'd0) gap <= gap - 3'd1;
                    if (rdata_idx == WORDS) begin
                        state <= S_DONE;
                    end else if (gap == 3'd0 && user_ready && raddr < WORDS) begin
                        user_valid <= 1'b1;
                        user_we    <= 1'b0;
                        user_addr  <= raddr[USER_BITS-1:0];
                        state      <= S_RD_WAIT;
                    end
                end
                S_RD_WAIT: begin
                    user_valid <= 1'b0;
                    gap        <= 3'd3;
                    raddr      <= raddr + 1;
                    state      <= S_RD;
                end
                S_DONE: begin
                    error_count <= error_count + run_errors;
                    bist_pass   <= (run_errors == 0);
                    bist_busy   <= 1'b0;
                    if (scan_en && phase_sel < phase_max) begin
                        phase_sel  <= phase_sel + 1;
                        state      <= S_WR;
                        waddr      <= 0;
                        raddr      <= 0;
                        rdata_idx  <= 0;
                        gap        <= 3'd0;
                        lfsr       <= 32'hA5A5A5A5;
                        run_errors <= 0;
                        bist_busy  <= 1'b1;
                    end else begin
                        phase_scan_done <= scan_en;
                        state           <= S_IDLE;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
