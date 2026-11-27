// SPDX-License-Identifier: Apache-2.0
`default_nettype none
module ddr_dqs_delay_adpll #(
    parameter integer LANES = 1,
    parameter integer TAP_BITS = 4,
    parameter integer FIRST_STAGE = 0,
    parameter integer STEP_CELLS = 1,
    parameter integer SETTLE_CYCLES = 2
) (
    input  wire                       sys_clk, rst, update_idle,
    input  wire [LANES-1:0]           dqs_in,
    output wire [LANES-1:0]           dqs_capture,
    input  wire [LANES-1:0]           tap_valid,
    input  wire [LANES*TAP_BITS-1:0]  tap_value,
    output wire [LANES-1:0]           tap_ready
);
    // SYS-domain request/acknowledgement: hold each lane's valid and value
    // through a rising edge with ready. A request is applied on the first idle
    // SYS edge and ready cannot assert until SETTLE_CYCLES full SYS periods
    // have elapsed. If idle drops, acknowledgement waits for the next idle
    // window without reprogramming. Reset is synchronous and selects code 0.
    //
    // The scheduler must keep capture quiescent during cold reset and from
    // tap application through acknowledgement (including any in-flight bus
    // activity). update_idle is not a DQS gate. dqs_in must come from a pad
    // receiver with defined behavior when the bus is high-Z, not a raw pad.
    //
    // FIRST_STAGE >= 0; LANES, TAP_BITS, STEP_CELLS and SETTLE_CYCLES > 0.
    // Physical implementation must preserve the chain and characterize the
    // routed tap loads, MUX path matching/skew and delay range over PVT. STA,
    // the source-synchronous capture/CDC constraints and metastability are
    // not addressed by the settle counter or by this structural RTL.
    localparam integer CODES = 1 << TAP_BITS;
    localparam integer STAGES = FIRST_STAGE + (CODES-1)*STEP_CELLS + 1;
    localparam integer COUNT_BITS = $clog2(SETTLE_CYCLES+1);

    for (genvar lane = 0; lane < LANES; lane = lane + 1) begin : g_lane
        wire [STAGES-1:0] chain_taps;
        wire [CODES-1:0] code_taps;
        reg [TAP_BITS-1:0] select_tap;
        reg [COUNT_BITS-1:0] settle_left;
        reg pending;

        (* keep_hierarchy = "yes", dont_touch = "true" *)
        PLL_DCDL_TAP_BUS_PHYS #(.NTAPS(STAGES)) delay_line (
            .CLK_IN(dqs_in[lane]), .TAP(chain_taps)
        );
        for (genvar code = 0; code < CODES; code = code + 1) begin : g_code
            assign code_taps[code] = chain_taps[FIRST_STAGE + code*STEP_CELLS];
        end
        assign dqs_capture[lane] = code_taps[select_tap];

        assign tap_ready[lane] = !rst && update_idle && pending && (settle_left == 0);
        always @(posedge sys_clk) begin
            if (rst) begin
                select_tap <= '0;
                settle_left <= '0;
                pending <= 1'b0;
            end else if (pending) begin
                if (settle_left != 0)
                    settle_left <= settle_left - 1'b1;
                else if (tap_valid[lane] && tap_ready[lane])
                    pending <= 1'b0;
            end else if (update_idle && tap_valid[lane]) begin
                select_tap <= tap_value[lane*TAP_BITS +: TAP_BITS];
                settle_left <= COUNT_BITS'(SETTLE_CYCLES);
                pending <= 1'b1;
            end
        end
    end
endmodule
`default_nettype wire
