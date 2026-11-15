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
    parameter integer GUARD_CYCLES = 1
)(
    input  wire clk,
    input  wire rst,
    input  wire wrdata_en,
    input  wire rddata_en,
    output reg  dq_oe_gated,
    output reg  turnaround_busy
);
    reg [7:0] dead;
    always @(posedge clk) begin
        if (rst) begin
            dead            <= 8'd0;
            dq_oe_gated     <= 1'b0;
            turnaround_busy <= 1'b0;
        end else begin
            if (rddata_en)          dead <= GUARD_CYCLES[7:0];
            else if (dead != 8'd0)  dead <= dead - 8'd1;
            turnaround_busy <= (dead != 8'd0) || rddata_en;
            dq_oe_gated     <= wrdata_en && (dead == 8'd0) && !rddata_en;
        end
    end
endmodule
`default_nettype wire
