// SPDX-License-Identifier: Apache-2.0
// Lint / netlist stub for the GF180 pad tile physical macro.
//
// gf180_pad_tile exists only as layout (GDS) + extracted SPICE + LEF; there
// is no synthesizable RTL.  For Verilator lint and yosys hierarchy checks of
// sdram_chip_top the tile is a black box: ports declared, no behavior.  The
// electrical behavior lives in the pad-ring signoff, not in this file.
`default_nettype none
/* verilator lint_off DECLFILENAME */
module gf180_pad_tile (
    input  wire OUT,
    input  wire OE_N,
    input  wire PU_OK,
    inout  wire PAD,
    output wire IN,
    inout  wire VDDIO,
    inout  wire VSSIO
);
    // black box: intentionally empty
endmodule
