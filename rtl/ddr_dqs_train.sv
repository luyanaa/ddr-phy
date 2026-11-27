// SPDX-License-Identifier: Apache-2.0
`default_nettype none
module ddr_dqs_train #(
    parameter integer LANES = 1,
    parameter integer TAP_BITS = 4,
    parameter integer SAMPLES_PER_TAP = 2,
    parameter integer MIN_WINDOW = 2,
    parameter integer TIMEOUT_CYCLES = 256
) (
    input  wire                         sys_clk,
    input  wire                         rst,
    input  wire                         start,
    output reg  [LANES-1:0]             tap_valid,
    input  wire [LANES-1:0]             tap_ready,
    output reg  [LANES*TAP_BITS-1:0]    tap_value,
    output reg                          probe_valid,
    input  wire                         probe_ready,
    input  wire                         probe_done,
    input  wire [LANES-1:0]             probe_pass,
    output reg                          busy,
    output reg                          trained,
    output reg                          failed
);
    // All ports share sys_clk. A rising start edge accepted while idle starts a
    // fresh sweep; reset cancels any in-flight work and clears the result.
    // tap_ready means that lane's value is applied and settled, not enqueued.
    // Each tap request remains stable until its lane acknowledges; no READ is
    // issued until every lane has acknowledged. probe_done is consumed only in
    // the cycle(s) after probe_valid && probe_ready.
    //
    // Every tap is tested with SAMPLES_PER_TAP real READs. A lane's tap passes
    // only if every sample passes. The widest ascending, nonwrapping run is
    // retained online; strict length improvement keeps the earlier run on ties,
    // and end - floor(length/2) selects the lower midpoint of even windows.
    // The selected centers are programmed and settled together, then verified
    // by one final READ. A failed final READ latches FAILED without fallback.
    // Each external wait has a fresh TIMEOUT_CYCLES watchdog; partial lane tap
    // acknowledgements do not extend that request's deadline.
    // FAILED/TRAINED remain latched until reset or a new accepted start edge.

    localparam integer LEN_BITS = TAP_BITS + 1;
    localparam integer SAMPLE_BITS = (SAMPLES_PER_TAP < 2) ? 1 : $clog2(SAMPLES_PER_TAP);
    localparam integer TIMEOUT_BITS = (TIMEOUT_CYCLES < 2) ? 1 : $clog2(TIMEOUT_CYCLES);
    localparam [SAMPLE_BITS-1:0] LAST_SAMPLE = SAMPLE_BITS'(SAMPLES_PER_TAP - 1);
    localparam [TIMEOUT_BITS-1:0] LAST_TIMEOUT = TIMEOUT_BITS'(TIMEOUT_CYCLES - 1);

    localparam [3:0] ST_IDLE             = 4'd0;
    localparam [3:0] ST_SWEEP_TAP        = 4'd1;
    localparam [3:0] ST_SWEEP_PROBE_REQ  = 4'd2;
    localparam [3:0] ST_SWEEP_PROBE_WAIT = 4'd3;
    localparam [3:0] ST_DECIDE           = 4'd4;
    localparam [3:0] ST_FINAL_TAP        = 4'd5;
    localparam [3:0] ST_FINAL_PROBE_REQ  = 4'd6;
    localparam [3:0] ST_FINAL_PROBE_WAIT = 4'd7;

    reg [3:0] state;
    reg start_d;
    wire start_edge = start && !start_d;
    reg [TAP_BITS-1:0] sweep_tap;
    reg [LANES-1:0] tap_acked;
    wire [LANES-1:0] tap_ack = tap_valid & tap_ready;
    reg [SAMPLE_BITS-1:0] sample_index;
    reg [LANES-1:0] sample_pass_accum;
    reg [TIMEOUT_BITS-1:0] timeout_count;

    reg [LEN_BITS-1:0] current_run_len [0:LANES-1];
    reg [LEN_BITS-1:0] best_run_len [0:LANES-1];
    reg [TAP_BITS-1:0] best_run_end [0:LANES-1];
    reg [TAP_BITS-1:0] best_center [0:LANES-1];
    reg [LANES-1:0] window_found;
    integer out_lane;
    integer check_lane;
    integer seq_lane;

    always @* begin
        tap_valid = {LANES{1'b0}};
        tap_value = {LANES*TAP_BITS{1'b0}};
        probe_valid = 1'b0;
        case (state)
            ST_SWEEP_TAP: begin
                for (out_lane = 0; out_lane < LANES; out_lane = out_lane + 1) begin
                    tap_valid[out_lane] = !tap_acked[out_lane];
                    tap_value[out_lane*TAP_BITS +: TAP_BITS] = sweep_tap;
                end
            end
            ST_FINAL_TAP: begin
                for (out_lane = 0; out_lane < LANES; out_lane = out_lane + 1) begin
                    tap_valid[out_lane] = !tap_acked[out_lane];
                    tap_value[out_lane*TAP_BITS +: TAP_BITS] = best_center[out_lane];
                end
            end
            ST_SWEEP_PROBE_REQ, ST_FINAL_PROBE_REQ: probe_valid = 1'b1;
            default: ;
        endcase
    end

    always @* begin
        window_found = {LANES{1'b0}};
        for (check_lane = 0; check_lane < LANES; check_lane = check_lane + 1)
            window_found[check_lane] = (best_run_len[check_lane] >= MIN_WINDOW);
    end

    always @(posedge sys_clk or posedge rst) begin
        if (rst) begin
            state <= ST_IDLE;
            start_d <= 1'b0;
            sweep_tap <= {TAP_BITS{1'b0}};
            tap_acked <= {LANES{1'b0}};
            sample_index <= {SAMPLE_BITS{1'b0}};
            sample_pass_accum <= {LANES{1'b0}};
            timeout_count <= {TIMEOUT_BITS{1'b0}};
            busy <= 1'b0;
            trained <= 1'b0;
            failed <= 1'b0;
            for (seq_lane = 0; seq_lane < LANES; seq_lane = seq_lane + 1) begin
                current_run_len[seq_lane] <= {LEN_BITS{1'b0}};
                best_run_len[seq_lane] <= {LEN_BITS{1'b0}};
                best_run_end[seq_lane] <= {TAP_BITS{1'b0}};
                best_center[seq_lane] <= {TAP_BITS{1'b0}};
            end
        end else begin
            start_d <= start;
            case (state)
                ST_IDLE: begin
                    if (start_edge) begin
                        state <= ST_SWEEP_TAP;
                        sweep_tap <= {TAP_BITS{1'b0}};
                        tap_acked <= {LANES{1'b0}};
                        sample_index <= {SAMPLE_BITS{1'b0}};
                        sample_pass_accum <= {LANES{1'b1}};
                        timeout_count <= {TIMEOUT_BITS{1'b0}};
                        busy <= 1'b1;
                        trained <= 1'b0;
                        failed <= 1'b0;
                        for (seq_lane = 0; seq_lane < LANES; seq_lane = seq_lane + 1) begin
                            current_run_len[seq_lane] <= {LEN_BITS{1'b0}};
                            best_run_len[seq_lane] <= {LEN_BITS{1'b0}};
                            best_run_end[seq_lane] <= {TAP_BITS{1'b0}};
                            best_center[seq_lane] <= {TAP_BITS{1'b0}};
                        end
                    end
                end

                ST_SWEEP_TAP: begin
                    if (&(tap_acked | tap_ack)) begin
                        tap_acked <= {LANES{1'b0}};
                        timeout_count <= {TIMEOUT_BITS{1'b0}};
                        state <= ST_SWEEP_PROBE_REQ;
                    end else if (timeout_count == LAST_TIMEOUT) begin
                        state <= ST_IDLE;
                        timeout_count <= {TIMEOUT_BITS{1'b0}};
                        busy <= 1'b0;
                        trained <= 1'b0;
                        failed <= 1'b1;
                    end else begin
                        tap_acked <= tap_acked | tap_ack;
                        timeout_count <= timeout_count + 1'b1;
                    end
                end

                ST_SWEEP_PROBE_REQ: begin
                    if (probe_ready) begin
                        timeout_count <= {TIMEOUT_BITS{1'b0}};
                        state <= ST_SWEEP_PROBE_WAIT;
                    end else if (timeout_count == LAST_TIMEOUT) begin
                        state <= ST_IDLE;
                        timeout_count <= {TIMEOUT_BITS{1'b0}};
                        busy <= 1'b0;
                        trained <= 1'b0;
                        failed <= 1'b1;
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end

                ST_SWEEP_PROBE_WAIT: begin
                    if (probe_done) begin
                        timeout_count <= {TIMEOUT_BITS{1'b0}};
                        if (sample_index != LAST_SAMPLE) begin
                            sample_pass_accum <= sample_pass_accum & probe_pass;
                            sample_index <= sample_index + 1'b1;
                            state <= ST_SWEEP_PROBE_REQ;
                        end else begin
                            for (seq_lane = 0; seq_lane < LANES; seq_lane = seq_lane + 1) begin
                                if (sample_pass_accum[seq_lane] && probe_pass[seq_lane]) begin
                                    if (current_run_len[seq_lane] == {LEN_BITS{1'b0}}) begin
                                        current_run_len[seq_lane] <= LEN_BITS'(1);
                                        if (best_run_len[seq_lane] == {LEN_BITS{1'b0}}) begin
                                            best_run_len[seq_lane] <= LEN_BITS'(1);
                                            best_run_end[seq_lane] <= sweep_tap;
                                            best_center[seq_lane] <= sweep_tap;
                                        end
                                    end else begin
                                        current_run_len[seq_lane] <= current_run_len[seq_lane] + LEN_BITS'(1);
                                        if ((current_run_len[seq_lane] + LEN_BITS'(1)) > best_run_len[seq_lane]) begin
                                            best_run_len[seq_lane] <= current_run_len[seq_lane] + LEN_BITS'(1);
                                            best_run_end[seq_lane] <= sweep_tap;
                                            best_center[seq_lane] <= sweep_tap - ((current_run_len[seq_lane] + LEN_BITS'(1)) >> 1);
                                        end
                                    end
                                end else begin
                                    current_run_len[seq_lane] <= {LEN_BITS{1'b0}};
                                end
                            end

                            if (&sweep_tap) begin
                                state <= ST_DECIDE;
                            end else begin
                                sweep_tap <= sweep_tap + 1'b1;
                                tap_acked <= {LANES{1'b0}};
                                sample_index <= {SAMPLE_BITS{1'b0}};
                                sample_pass_accum <= {LANES{1'b1}};
                                state <= ST_SWEEP_TAP;
                            end
                        end
                    end else if (timeout_count == LAST_TIMEOUT) begin
                        state <= ST_IDLE;
                        timeout_count <= {TIMEOUT_BITS{1'b0}};
                        busy <= 1'b0;
                        trained <= 1'b0;
                        failed <= 1'b1;
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end

                ST_DECIDE: begin
                    if (&window_found) begin
                        tap_acked <= {LANES{1'b0}};
                        timeout_count <= {TIMEOUT_BITS{1'b0}};
                        state <= ST_FINAL_TAP;
                    end else begin
                        state <= ST_IDLE;
                        busy <= 1'b0;
                        trained <= 1'b0;
                        failed <= 1'b1;
                    end
                end

                ST_FINAL_TAP: begin
                    if (&(tap_acked | tap_ack)) begin
                        tap_acked <= {LANES{1'b0}};
                        timeout_count <= {TIMEOUT_BITS{1'b0}};
                        state <= ST_FINAL_PROBE_REQ;
                    end else if (timeout_count == LAST_TIMEOUT) begin
                        state <= ST_IDLE;
                        timeout_count <= {TIMEOUT_BITS{1'b0}};
                        busy <= 1'b0;
                        trained <= 1'b0;
                        failed <= 1'b1;
                    end else begin
                        tap_acked <= tap_acked | tap_ack;
                        timeout_count <= timeout_count + 1'b1;
                    end
                end

                ST_FINAL_PROBE_REQ: begin
                    if (probe_ready) begin
                        timeout_count <= {TIMEOUT_BITS{1'b0}};
                        state <= ST_FINAL_PROBE_WAIT;
                    end else if (timeout_count == LAST_TIMEOUT) begin
                        state <= ST_IDLE;
                        timeout_count <= {TIMEOUT_BITS{1'b0}};
                        busy <= 1'b0;
                        trained <= 1'b0;
                        failed <= 1'b1;
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end

                ST_FINAL_PROBE_WAIT: begin
                    if (probe_done) begin
                        timeout_count <= {TIMEOUT_BITS{1'b0}};
                        busy <= 1'b0;
                        if (&probe_pass) begin
                            state <= ST_IDLE;
                            trained <= 1'b1;
                            failed <= 1'b0;
                        end else begin
                            state <= ST_IDLE;
                            trained <= 1'b0;
                            failed <= 1'b1;
                        end
                    end else if (timeout_count == LAST_TIMEOUT) begin
                        state <= ST_IDLE;
                        timeout_count <= {TIMEOUT_BITS{1'b0}};
                        busy <= 1'b0;
                        trained <= 1'b0;
                        failed <= 1'b1;
                    end else begin
                        timeout_count <= timeout_count + 1'b1;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                    timeout_count <= {TIMEOUT_BITS{1'b0}};
                    busy <= 1'b0;
                    trained <= 1'b0;
                    failed <= 1'b1;
                end
            endcase
        end
    end
endmodule
`default_nettype wire
