// SPDX-License-Identifier: Apache-2.0
// Read capture phase selection. This is an INTERFACE, not a phase generator.
//
// P0-2 showed that a positive capture delay delta_t_capture is required as
// soon as the round-trip placeholder B exceeds tCK - tAC. This module
// exposes that knob. The phase-shifted clocks themselves must come from a
// characterized PLL/DLL/delay line supplied by the I/O backend
// (capability gate G6 in reports/capability_report.md). Today no backend
// provides them, so phase_clocks_ready is expected to be 0 and cap_clk
// falls back to the core clock (delta = 0), reproducing today's fixed
// phase.
//
// The clock select is a plain mux. A real ASIC needs a glitch-free clock
// mux cell from the PDK; that is a backend obligation, not RTL.

`default_nettype none
module read_capture_ctrl #(
    parameter integer NPHASES = 4,
    parameter integer SEL_W   = 2
)(
    input  wire                    clk,
    input  wire                    rst,
    input  wire [NPHASES-1:0]      phase_clks,
    input  wire                    phase_clocks_ready,
    input  wire [SEL_W-1:0]        phase_sel,
    input  wire                    phase_sel_valid,
    output wire                    cap_clk,
    output reg  [SEL_W-1:0]        phase_sel_status,
    output wire                    capture_ready
);
    always @(posedge clk) begin
        if (rst)                    phase_sel_status <= {SEL_W{1'b0}};
        else if (phase_sel_valid)   phase_sel_status <= phase_sel;
    end

    assign cap_clk       = phase_clocks_ready ? phase_clks[phase_sel_status] : clk;
    assign capture_ready = phase_clocks_ready;
endmodule
`default_nettype wire
