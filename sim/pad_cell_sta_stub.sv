// SPDX-License-Identifier: Apache-2.0
// STA-only stub for sim/pad_cell_generic.sv.
//
// The simulation model uses fork/join_none and #delay assignments, which
// yosys cannot parse. For synthesis and STA the pad is outside the chip:
// the digital timing stops at the pad boundary, so a zero-delay wire model
// is the correct abstraction. Pad delays are characterized separately in
// SPICE (generator/emit_char_delay.py) and combined in
// generator/p1_3_margins.py.
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
    assign pad        = (core_oe && power_ok) ? core_out : {DATA_BITS{1'bz}};
    assign core_in    = pad;
    assign driving    = power_ok ? (core_oe ? core_out : {DATA_BITS{1'b0}})
                                 : {DATA_BITS{1'b0}};
    assign contention = 1'b0;
endmodule
`default_nettype wire
