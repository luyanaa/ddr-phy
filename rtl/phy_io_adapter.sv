// SPDX-License-Identifier: Apache-2.0
// Digital-side pad adapter. It separates the core (VDD) from the pins
// (VDDIO) and binds the PHY to one I/O backend.
//
// BACKEND 0 = generic_sim : behavioral pad, verification only.
// BACKEND 1 = asic_pad    : REQUIRES a qualified IO macro supplied by the
//                          integrator. Not provided here.
// BACKEND 2 = fpga_io     : out of scope for this ASIC project.
//
// There is deliberately NO fallback that wires core standard cells
// straight to an external DQ. Selecting an unsupported backend fails
// loudly instead of silently producing a core-only netlist that cannot
// drive SDRAM. See reports/capability_report.md (all silicon backends
// are NO_GO until gates G1/G5/G6 close).
//
// CMD_BITS packs command/address/DQM so the adapter has one flat bus;
// rtl/sdram_phy_top.sv does the packing. The command and CK pins still
// need real output pads in an asic_pad backend - this module only makes
// that obligation explicit, it does not discharge it.

`default_nettype none

module phy_io_adapter #(
    parameter integer DATA_BITS    = 8,
    parameter integer CMD_BITS     = 22,
    parameter integer BACKEND      = 0,
    parameter integer T_OE_ON_PS   = 0,
    parameter integer T_OE_OFF_PS  = 0,
    parameter integer T_IN_PS      = 0
)(
    // Core side: digital, core voltage domain
    input  wire [CMD_BITS-1:0]    core_cmd,
    input  wire [DATA_BITS-1:0]   core_dq_o,
    input  wire                   core_dq_oe,
    output wire [DATA_BITS-1:0]   core_dq_i,
    input  wire                   core_ck,

    // Pad side: external pins, VDDIO domain
    output wire [CMD_BITS-1:0]    pad_cmd,
    inout  wire [DATA_BITS-1:0]   pad_dq,
    output wire                   pad_ck,

    // Pad / power configuration
    input  wire                   io_power_ok,
    input  wire [7:0]             pad_config,
    output wire                   pad_ready,
    output wire                   contention
);
    // pad_config is backend-specific (drive strength, slew, pull-ups).
    // generic_sim has no analog knobs, so it is intentionally unused.
    wire _pad_config_unused = &{1'b0, pad_config};

    generate
        if (BACKEND == 0) begin : g_generic_sim
            pad_cell_generic #(
                .DATA_BITS(DATA_BITS),
                .T_OE_ON_PS(T_OE_ON_PS),
                .T_OE_OFF_PS(T_OE_OFF_PS),
                .T_IN_PS(T_IN_PS)
            ) u_dq (
                .core_out(core_dq_o),
                .core_oe(core_dq_oe),
                .core_in(core_dq_i),
                .pad(pad_dq),
                .power_ok(io_power_ok),
                .driving(),
                .contention(contention)
            );
            assign pad_cmd   = core_cmd;
            assign pad_ck    = core_ck;
            assign pad_ready = io_power_ok;
        end else begin : g_no_backend
            initial begin
                $display("FATAL phy_io_adapter: BACKEND=%0d has no qualified IO macro.", BACKEND);
                $display("See reports/capability_report.md (NO_GO). Do not wire core cells to a pad.");
                $finish;
            end
            assign pad_cmd   = {CMD_BITS{1'bz}};
            assign pad_ck    = 1'bz;
            assign core_dq_i = {DATA_BITS{1'bz}};
            assign pad_ready = 1'b0;
            assign contention = 1'b0;
        end
    endgenerate
endmodule
`default_nettype wire
