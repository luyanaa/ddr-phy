// SPDX-License-Identifier: Apache-2.0
// Verification stub for the gf180_pad_tile physical macro.
// Ports match sch/pads/gf180mcuD/pcell/gf180_pad_tile.lef and the LVS
// schematic sch/pads/gf180mcuD/pcell/gf180_pad_tile.spice.  This module is
// only a lint/Elaboration boundary: it has no timing and no drive strength.
`default_nettype none
module gf180_pad_tile (
    input  wire OUT,    // core-side output data into the pad driver
    input  wire OE_N,   // active-low output enable
    output wire PU_OK,  // power-ok status out of the pad
    inout  wire PAD,    // bond pad
    output wire IN,     // receiver output toward the core
    inout  wire VDDIO,
    inout  wire VSSIO
);
    assign PAD   = OE_N ? 1'bz : OUT;
    assign IN    = PAD;
    assign PU_OK = 1'b1;
endmodule
`default_nettype wire
