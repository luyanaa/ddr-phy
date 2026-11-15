// SPDX-License-Identifier: Apache-2.0
// Verification-only phase-adjustable read capture model.
//
// NOT synthesizable. This is the behaviour P0-4 must implement in
// rtl/sdr_phy.sv: a capture FF clocked by a phase-shifted clock, with the
// data-valid window checked. Today's rtl/sdr_phy.sv has neither; it samples
// dq_i on posedge clk with no phase control, which is phase = 0 here.
//
// sample is a strobe whose rising edge is the capture edge. The testbench
// places it at (launch edge + tCK + capture_phase).

`timescale 1ps/1ps
`default_nettype none

module read_capture #(
    parameter integer DATA_BITS = 8
)(
    input  wire                    sample,
    input  wire                    rst,
    input  wire [DATA_BITS-1:0]    dq,
    input  wire                    data_valid,
    output reg  [DATA_BITS-1:0]    q,
    output reg                     timing_error
);
    always @(posedge sample or posedge rst) begin
        if (rst) begin
            q            <= {DATA_BITS{1'b0}};
            timing_error <= 1'b0;
        end else begin
            q            <= dq;
            timing_error <= (data_valid !== 1'b1) || (^dq === 1'bx);
        end
    end
endmodule
`default_nettype wire
