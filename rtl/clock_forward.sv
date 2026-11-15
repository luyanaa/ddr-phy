// SPDX-License-Identifier: Apache-2.0
// Dedicated SDRAM CK forwarding path.
//
// rtl/sdr_phy.sv:77 is 'assign ck = clk': SDRAM CK is an ordinary
// combinational output and synthesis/CTS are free to move it relative to
// the command and DQ registers. docs/TIMING_BUDGET.md section 5 shows the
// consequence: write setup margin degenerates to tCLK,fwd - tDQ,tx - tDS.
//
// This module makes the path explicit and provides a hook for a backend
// selected CK phase. It does NOT create that phase: ck_phase_clks comes
// from a characterized backend resource (capability gate G6). CK is held
// low until io_power_ok.
//
// STA obligation: create_generated_clock on ck_o (see flow/sdr_phy.sdc).

`default_nettype none
module clock_forward #(
    parameter integer NPHASES = 4,
    parameter integer SEL_W   = 2
)(
    input  wire                    clk,
    input  wire                    rst,
    input  wire [NPHASES-1:0]      ck_phase_clks,
    input  wire                    ck_phase_clocks_ready,
    input  wire [SEL_W-1:0]        ck_phase_sel,
    input  wire                    io_power_ok,
    output wire                    ck_o,
    output wire                    ck_active,
    output wire                    using_backend_phase
);
    wire ck_src = ck_phase_clocks_ready ? ck_phase_clks[ck_phase_sel] : clk;
    assign ck_o                = io_power_ok ? ck_src : 1'b0;
    assign ck_active           = io_power_ok;
    assign using_backend_phase = ck_phase_clocks_ready;
endmodule
`default_nettype wire
