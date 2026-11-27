// SPDX-License-Identifier: Apache-2.0
// Portable DDR edge-output wrapper. Each payload half is captured on only
// one edge; q is selected from the two distinct registers.
`default_nettype none
module ddr_edge_out #(
    parameter integer WIDTH = 1
) (
    input  wire             clk,
    input  wire             rst,
    input  wire [WIDTH-1:0] fall_d,
    input  wire [WIDTH-1:0] rise_d,
    output wire [WIDTH-1:0] q
);
    reg [WIDTH-1:0] fall_q, rise_q;

    always @(posedge clk or posedge rst) begin
        if (rst) fall_q <= '0;
        else     fall_q <= fall_d;
    end

    always @(negedge clk or posedge rst) begin
        if (rst) rise_q <= '0;
        else     rise_q <= rise_d;
    end

    assign q = clk ? rise_q : fall_q;
endmodule
`default_nettype wire
