// SPDX-License-Identifier: Apache-2.0
//
// DDR1 DQS receive delay line, consumer-side wrapper.
//
// The line is the repaired adpll_gen DDR1_DQS_DELAY_LINE_PHYS: a uniform
// series chain with CELLS_PER_TAP fine cells per exposed tap.  At the IHP130
// / ics55 characterized points this is about 70 ps/tap TT, 122 ps/tap SS and
// 48 ps/tap FF, so 128 taps cover the DDR1 0-5 ns range with a step below
// 200 ps.  The previous PLL_DCDL_TAP_BUS_PHYS (16 single cells) was only
// about 1 ns and could not reach the 600 ps read-capture operating point.
//
// Handshake is the existing request/acknowledge contract:
//   * a request is applied on the first idle SYS edge;
//   * TAP_READY cannot assert until SETTLE_CYCLES full SYS periods have
//     elapsed;
//   * if UPDATE_IDLE drops, the request stays pending and acknowledges on
//     the next idle window without reprogramming;
//   * reset selects code 0 (minimum delay).
//
// DQS_CAPTURE is gated low while a new code settles (settled_q=0).  Updates
// are only legal when UPDATE_IDLE=1, i.e. no read burst and no in-flight
// DQS edge, so the gate cannot cut a real pulse; it is a guard against
// mux-select and pad-receiver bounce during the update.
//
// FIRST_STAGE >= 0; LANES, TAP_BITS, STEP_CELLS, SETTLE_CYCLES > 0;
// FIRST_STAGE + (CODES-1)*STEP_CELLS < LINE_NTAPS.
`default_nettype none
module ddr_dqs_delay_adpll #(
    parameter integer LANES         = 1,
    parameter integer TAP_BITS      = 4,
    parameter integer FIRST_STAGE   = 0,
    parameter integer STEP_CELLS    = 1,
    parameter integer SETTLE_CYCLES = 2,
    // Physical line sizing.  Defaults preserve the old unit-test timing:
    // one 100 ps FINE_DELAY_CELL per tap, structural IMPL=1.
    parameter integer CELLS_PER_TAP = 1,
    parameter integer CELL_PS       = 35,
    parameter integer LINE_NTAPS    = 128,
    parameter integer LINE_IMPL     = 1
) (
    input  wire                       sys_clk, rst, update_idle,
    input  wire [LANES-1:0]           dqs_in,
    output wire [LANES-1:0]           dqs_capture,
    input  wire [LANES-1:0]           tap_valid,
    input  wire [LANES*TAP_BITS-1:0]  tap_value,
    output wire [LANES-1:0]           tap_ready,
    output wire [LANES-1:0]           tap_error
);
    localparam integer CODES = 1 << TAP_BITS;
    localparam integer STAGES = FIRST_STAGE + (CODES-1)*STEP_CELLS + 1;
    localparam integer COUNT_BITS = $clog2(SETTLE_CYCLES+1);

    initial begin
        if (LANES < 1 || TAP_BITS < 1 || STEP_CELLS < 1 ||
            SETTLE_CYCLES < 1 || FIRST_STAGE < 0)
            $error("ddr_dqs_delay_adpll parameter out of legal range");
        if (STAGES > LINE_NTAPS)
            $error("ddr_dqs_delay_adpll: STAGES=%0d exceeds LINE_NTAPS=%0d",
                   STAGES, LINE_NTAPS);
    end

    for (genvar lane = 0; lane < LANES; lane = lane + 1) begin : g_lane
        wire [LINE_NTAPS-1:0] chain_taps;
        wire [CODES-1:0]      code_taps;
        reg  [TAP_BITS-1:0]   select_tap;
        reg  [COUNT_BITS-1:0] settle_left;
        reg                   pending;
        reg                   settled_q;
        reg                   error_q;

        (* keep_hierarchy = "yes", dont_touch = "true" *)
        DDR1_DQS_DELAY_LINE_PHYS #(
            .NTAPS(LINE_NTAPS), .CELLS_PER_TAP(CELLS_PER_TAP),
            .CELL_PS(CELL_PS), .IMPL(LINE_IMPL)
        ) delay_line (
            .CLK_IN(dqs_in[lane]), .TAP(chain_taps)
        );

        for (genvar code = 0; code < CODES; code = code + 1) begin : g_code
            assign code_taps[code] = chain_taps[FIRST_STAGE + code*STEP_CELLS];
        end

        wire mux_out = code_taps[select_tap];
        assign dqs_capture[lane] = settled_q ? mux_out : 1'b0;

        assign tap_ready[lane] = !rst && update_idle && pending &&
                                 (settle_left == 0);

        always @(posedge sys_clk) begin
            if (rst) begin
                select_tap <= '0;
                settle_left <= '0;
                pending <= 1'b0;
                settled_q <= 1'b1;  // code 0 path
                error_q <= 1'b0;
            end else if (pending) begin
                if (settle_left != 0) begin
                    settle_left <= settle_left - 1'b1;
                    if (settle_left == 1)
                        settled_q <= 1'b1;
                end else begin
                    settled_q <= 1'b1;
                    if (tap_valid[lane] && tap_ready[lane])
                        pending <= 1'b0;
                end
            end else if (update_idle && tap_valid[lane]) begin
                select_tap <= tap_value[lane*TAP_BITS +: TAP_BITS];
                settle_left <= COUNT_BITS'(SETTLE_CYCLES);
                pending <= 1'b1;
                settled_q <= 1'b0;
                error_q <= 1'b0;
            end else if (tap_valid[lane]) begin
                // Contract violation: request while a burst is active.
                error_q <= 1'b1;
            end
        end

        assign tap_error[lane] = error_q;
    end
endmodule
`default_nettype wire
