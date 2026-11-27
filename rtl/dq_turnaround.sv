// SPDX-License-Identifier: Apache-2.0
// DQ bus turnaround guard.
//
// The controller may not issue a write while turnaround_busy is high.
// Qualify the command and its DQ enable together before their launch stages;
// never use this guard to change pad OE after a write has been accepted.
// The guard counts are interface timing parameters, not pad characterization.

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
    input  wire rddata_en,
    output wire turnaround_busy
);
    localparam integer TOTAL_GUARD = GUARD_CYCLES + READ_TAIL_CYCLES +
                                     DQM_OFF_CYCLES + T_OE_OFF_CYCLES;
    localparam integer COUNT_W = (TOTAL_GUARD > 0) ? $clog2(TOTAL_GUARD + 1) : 1;
    reg [COUNT_W-1:0] dead;

    assign turnaround_busy = rst || rddata_en || (dead != '0);

    always @(posedge clk) begin
        if (rst)          dead <= '0;
        else if (rddata_en) dead <= COUNT_W'(TOTAL_GUARD);
        else if (dead != '0) dead <= dead - 1'b1;
    end
endmodule
`default_nettype wire
