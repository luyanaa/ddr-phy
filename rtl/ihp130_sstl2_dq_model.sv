// SPDX-License-Identifier: Apache-2.0
// Behavioral IHP130 SG13G2 SSTL-2 DQ lane model.
//
// This is a digital co-simulation model, not the transistor-level pad. It
// carries the PEX-measured pad delay into the RTL loop so the controller,
// PHY and DRAM model see a realistic pad boundary. The actual 2.5 V
// SSTL-2 driver/receiver and ESD network remain the SPICE/layout macro.
//
// Delay defaults are the TT PEX numbers from
// results/ihp130/sstl2-dq-route-eco/pex_tt.json. SS values can be selected
// with the parameters below; the model deliberately uses one TX delay for
// both edges and one RX delay for both edges, so it is a functional/timing
// witness, not a rise/fall or SI signoff model.
`timescale 1ps/1ps
`default_nettype none
module ihp130_sstl2_dq_model #(
    parameter integer TX_PS = 1300,
    parameter integer RX_PS = 1300,
    parameter integer OE_PS = 1500
) (
    inout  wire       PAD,
    input  wire       DQ_O,
    input  wire       DQ_OE,
    input  wire       VREF,
    input  wire       PU_OK,
    output wire       DQ_I,
    output wire       PAD_OE
);
    // VREF is part of the pad contract; the digital model only sees 0/1.
    wire drive_en;
    assign #(OE_PS) drive_en = (PU_OK === 1'b1) && (DQ_OE === 1'b1);

    bufif1 #(TX_PS) pad_driver (PAD, DQ_O, drive_en);

    // A high-Z pad reads as 0 in this digital abstraction. The real receiver
    // must not oscillate; that is a pad/PHY boundary requirement.
    assign #(RX_PS) DQ_I = (PAD === 1'b1) ? 1'b1 : 1'b0;
    assign PAD_OE = drive_en;
endmodule
`default_nettype wire
