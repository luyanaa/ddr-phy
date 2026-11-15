// SPDX-License-Identifier: Apache-2.0
// Behavioral bidirectional LVTTL pad for the generic_sim backend.
//
// Simulation only. There is no transistor here: no drive impedance, no
// slew, no input threshold, no ESD, no level shifter, no supply rail.
// T_OE_ON_PS / T_OE_OFF_PS / T_IN_PS are verification knobs, NOT
// characterized pad delays (those are null in backends/*.yaml).
//
// Power-up Hi-Z: core_oe is gated by power_ok, so the pad cannot drive
// until both supplies are declared present. Contention is detected by
// comparing the resolved pad value against what this cell is driving.

`timescale 1ps/1ps
`default_nettype none

module pad_cell_generic #(
    parameter integer DATA_BITS     = 8,
    parameter integer T_OE_ON_PS    = 0,
    parameter integer T_OE_OFF_PS   = 0,
    parameter integer T_IN_PS       = 0
)(
    input  wire [DATA_BITS-1:0] core_out,
    input  wire                 core_oe,
    output wire [DATA_BITS-1:0] core_in,
    inout  wire [DATA_BITS-1:0] pad,
    input  wire                 power_ok,
    output wire [DATA_BITS-1:0] driving,
    output wire                 contention
);
    wire                    oe_gated = core_oe && power_ok;
    // oe_d is a reg initialised to 0. A continuous assign with a rise/fall
    // delay leaves the wire X until its first delayed transaction, which
    // would falsely report a driven pad during the power-up Hi-Z window.
    reg                     oe_d = 1'b0;
    wire [DATA_BITS-1:0]    out_d;
    wire [DATA_BITS-1:0]    in_d;

    always @(oe_gated) begin
        fork
            begin
                if (oe_gated) #(T_OE_ON_PS)  oe_d = 1'b1;
                else          #(T_OE_OFF_PS) oe_d = 1'b0;
            end
        join_none
    end
    assign #(T_OE_ON_PS) out_d = core_out;
    assign #(T_IN_PS)    in_d  = pad;

    assign pad     = oe_d ? out_d : {DATA_BITS{1'bz}};
    assign core_in = in_d;
    assign driving = {DATA_BITS{oe_d}};

    integer i;
    reg     cont;
    always @* begin
        cont = 1'b0;
        if (oe_d)
            for (i = 0; i < DATA_BITS; i = i + 1)
                if (pad[i] !== out_d[i]) cont = 1'b1;
    end
    assign contention = cont;
endmodule
`default_nettype wire
