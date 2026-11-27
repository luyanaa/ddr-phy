// SPDX-License-Identifier: Apache-2.0
// RTL / simulation wrapper around sdram_phy_core.
//
// The harden is sdram_phy_core: it stops at the core-side pins
// (cmd_o / dq_o / dq_oe / dq_i / ck_o).  This wrapper adds the behavioral
// generic pad so the RTL regressions keep a pin-level DUT.  It is NOT
// synthesizable (pad_cell_generic uses fork/join_none); the silicon chip
// top instantiates gf180_pad_core instead.
`default_nettype none
module sdram_phy_top #(
    parameter integer ADDR_BITS     = 13,
    parameter integer BANK_BITS     = 2,
    parameter integer DATA_BITS     = 8,
    parameter integer RANKS         = 1,
    parameter integer CL            = 2,
    parameter integer NPHASES       = 4,
    parameter integer SEL_W         = 2,
    parameter integer GUARD_CYCLES  = 1,
    parameter integer READ_TAIL_CYCLES = CL + 1,
    parameter integer DQM_OFF_CYCLES = 0,
    parameter integer T_OE_OFF_CYCLES = 0,
    parameter integer CDC_LATENCY   = 6,
    parameter integer BACKEND       = 0,
    parameter integer T_OE_ON_PS    = 0,
    parameter integer T_OE_OFF_PS   = 0,
    parameter integer T_IN_PS       = 0,
    parameter integer DM_BITS       = DATA_BITS / 8,
    parameter integer CMD_BITS      = ADDR_BITS + BANK_BITS + 3 + 2*RANKS + DM_BITS
)(
    input  wire                        clk,
    input  wire                        rst,

    input  wire [ADDR_BITS-1:0]        dfi_address,
    input  wire [BANK_BITS-1:0]        dfi_bank,
    input  wire                        dfi_ras_n,
    input  wire                        dfi_cas_n,
    input  wire                        dfi_we_n,
    input  wire [RANKS-1:0]            dfi_cs_n,
    input  wire [RANKS-1:0]            dfi_cke,
    input  wire [RANKS-1:0]            dfi_odt,
    input  wire                        dfi_reset_n,
    input  wire                        dfi_act_n,
    input  wire [DATA_BITS-1:0]        dfi_wrdata,
    input  wire                        dfi_wrdata_en,
    input  wire [DATA_BITS/8-1:0]      dfi_wrdata_mask,
    input  wire                        dfi_rddata_en,
    output wire [DATA_BITS-1:0]        dfi_rddata,
    output wire                        dfi_rddata_valid,

    input  wire                        io_power_ok,
    input  wire [7:0]                  pad_config,
    input  wire [NPHASES-1:0]          phase_clks,
    input  wire                        phase_clocks_ready,
    input  wire [SEL_W-1:0]            phase_sel,
    input  wire                        phase_sel_valid,
    input  wire [NPHASES-1:0]          ck_phase_clks,
    input  wire                        ck_phase_clocks_ready,
    input  wire [SEL_W-1:0]            ck_phase_sel,

    output wire [CMD_BITS-1:0]         pad_cmd,
    inout  wire [DATA_BITS-1:0]        pad_dq,
    output wire                        pad_ck,

    output wire                        cap_clk,
    output wire                        capture_ready,
    output wire                        turnaround_busy,
    output wire                        pad_ready,
    output wire                        contention,
    output wire                        ck_active,
    output wire                        read_latency_error
);
    wire [DATA_BITS-1:0] dq_o_core;
    wire                 dq_oe_core;
    wire [DATA_BITS-1:0] dq_i_core;

    sdram_phy_core #(
        .ADDR_BITS(ADDR_BITS), .BANK_BITS(BANK_BITS),
        .DATA_BITS(DATA_BITS), .RANKS(RANKS), .CL(CL),
        .NPHASES(NPHASES), .SEL_W(SEL_W),
        .GUARD_CYCLES(GUARD_CYCLES),
        .READ_TAIL_CYCLES(READ_TAIL_CYCLES),
        .DQM_OFF_CYCLES(DQM_OFF_CYCLES),
        .T_OE_OFF_CYCLES(T_OE_OFF_CYCLES),
        .CDC_LATENCY(CDC_LATENCY)
    ) u_core (
        .clk(clk), .rst(rst),
        .dfi_address(dfi_address), .dfi_bank(dfi_bank),
        .dfi_ras_n(dfi_ras_n), .dfi_cas_n(dfi_cas_n), .dfi_we_n(dfi_we_n),
        .dfi_cs_n(dfi_cs_n), .dfi_cke(dfi_cke),
        .dfi_odt(dfi_odt), .dfi_reset_n(dfi_reset_n), .dfi_act_n(dfi_act_n),
        .dfi_wrdata(dfi_wrdata), .dfi_wrdata_en(dfi_wrdata_en),
        .dfi_wrdata_mask(dfi_wrdata_mask), .dfi_rddata_en(dfi_rddata_en),
        .dfi_rddata(dfi_rddata), .dfi_rddata_valid(dfi_rddata_valid),
        .io_power_ok(io_power_ok), .pad_config(pad_config),
        .phase_clks(phase_clks), .phase_clocks_ready(phase_clocks_ready),
        .phase_sel(phase_sel), .phase_sel_valid(phase_sel_valid),
        .ck_phase_clks(ck_phase_clks),
        .ck_phase_clocks_ready(ck_phase_clocks_ready),
        .ck_phase_sel(ck_phase_sel),
        .cmd_o(pad_cmd), .dq_o(dq_o_core), .dq_oe(dq_oe_core),
        .dq_i(dq_i_core), .ck_o(pad_ck),
        .cap_clk(cap_clk), .capture_ready(capture_ready),
        .turnaround_busy(turnaround_busy), .pad_ready(pad_ready),
        .contention(contention), .ck_active(ck_active),
        .read_latency_error(read_latency_error)
    );

    pad_cell_generic #(
        .DATA_BITS(DATA_BITS),
        .T_OE_ON_PS(T_OE_ON_PS),
        .T_OE_OFF_PS(T_OE_OFF_PS),
        .T_IN_PS(T_IN_PS)
    ) u_dq (
        .core_out(dq_o_core), .core_oe(dq_oe_core),
        .core_in(dq_i_core), .pad(pad_dq),
        .power_ok(io_power_ok), .driving(), .contention()
    );
endmodule
`default_nettype wire
