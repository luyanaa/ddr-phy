// SPDX-License-Identifier: Apache-2.0
// DQ bus turnaround guard.
//
// READ->WRITE is where an ideal inout hides contention: the SDRAM may
// still be driving DQ (tHZ) when the PHY enables its own output. This
// module blocks the PHY's OE for GUARD_CYCLES after any read and exposes
// turnaround_busy so the controller can hold off column commands.
//
// It deliberately does NOT insert NOPs on the pins by itself. Per
// checklist 4.4 the guard must be coordinated with controller scheduling;
// turnaround_busy is that coordination signal. GUARD_CYCLES is a design
// parameter, not a characterized tHZ: the real number needs pad timing
// (capability gate G5).

`default_nettype none
module dq_turnaround #(
    // All counts are design parameters, not characterized times. The total
    // must cover the read burst tail, DQM output-off delay and the pad's
    // tOE_off; the real numbers need G5 (pad timing) and the burst mode.
    parameter integer GUARD_CYCLES = 1,
    parameter integer READ_TAIL_CYCLES = 0,
    parameter integer DQM_OFF_CYCLES = 0,
    parameter integer T_OE_OFF_CYCLES = 0
)(
    input  wire clk,
    input  wire rst,
    input  wire wrdata_en,
    input  wire rddata_en,
    output reg  dq_oe_gated,
    output reg  turnaround_busy
);
    localparam integer TOTAL_GUARD = GUARD_CYCLES + READ_TAIL_CYCLES +
                                     DQM_OFF_CYCLES + T_OE_OFF_CYCLES;
    reg [7:0] dead;
    always @(posedge clk) begin
        if (rst) begin
            dead            <= 8'd0;
            dq_oe_gated     <= 1'b0;
            turnaround_busy <= 1'b0;
        end else begin
            if (rddata_en)          dead <= TOTAL_GUARD[7:0];
            else if (dead != 8'd0)  dead <= dead - 8'd1;
            turnaround_busy <= (dead != 8'd0) || rddata_en;
            dq_oe_gated     <= wrdata_en && (dead == 8'd0) && !rddata_en;
        end
    end
endmodule
`default_nettype wire
