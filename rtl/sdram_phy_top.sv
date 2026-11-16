// SPDX-License-Identifier: Apache-2.0
// Integration top for the Class S SDR PHY.
//
// This is the wiring that P0-4 left open: the external CK pin is driven by
// clock_forward (a dedicated, power-gated, phase-selectable path), NOT by
// rtl/sdr_phy.sv:77 'assign ck = clk'. The DQ pins go through
// dq_turnaround and phy_io_adapter; the command bus is packed into one
// flat CMD bus.
//
// cap_clk from read_capture_ctrl now clocks a real first-stage capture FF
// on the pad input; sdr_phy then registers that captured value on clk.
// This makes phase_sel change the effective sampling point for a phase that
// LEADS the core edge. A late phase, a Read FIFO/CDC and the resulting
// latency change are still TBD; phase selection must be static during
// traffic. The phase source itself is still a backend obligation (G6).
//
// turnaround_busy MUST be consumed by the controller as a write-accept
// condition; rtl/sdr_ctrl.sv does so via phy_turnaround_busy. Without that
// connection the controller can issue WRITE while the PHY is still guarding
// a READ->WRITE turnaround.
//
// The sdr_phy .ck output is deliberately left unconnected: the pad-side
// clock comes from clock_forward through the adapter.

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
    parameter integer READ_TAIL_CYCLES = 0,
    parameter integer DQM_OFF_CYCLES = 0,
    parameter integer T_OE_OFF_CYCLES = 0,
    parameter integer BACKEND       = 0,
    parameter integer T_OE_ON_PS    = 0,
    parameter integer T_OE_OFF_PS   = 0,
    parameter integer DM_BITS       = DATA_BITS / 8,
    parameter integer CMD_BITS      = ADDR_BITS + BANK_BITS + 3 + 2*RANKS + DM_BITS
)(
    input  wire                        clk,
    input  wire                        rst,

    // DFI (pass-through to sdr_phy)
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

    // Backend / power configuration
    input  wire                        io_power_ok,
    input  wire [7:0]                  pad_config,
    input  wire [NPHASES-1:0]          phase_clks,
    input  wire                        phase_clocks_ready,
    input  wire [SEL_W-1:0]            phase_sel,
    input  wire                        phase_sel_valid,
    input  wire [NPHASES-1:0]          ck_phase_clks,
    input  wire                        ck_phase_clocks_ready,
    input  wire [SEL_W-1:0]            ck_phase_sel,

    // Pad side
    output wire [CMD_BITS-1:0]         pad_cmd,
    inout  wire [DATA_BITS-1:0]        pad_dq,
    output wire                        pad_ck,

    // Status / coordination
    output wire                        cap_clk,
    output wire                        capture_ready,
    output wire                        turnaround_busy,
    output wire                        pad_ready,
    output wire                        contention,
    output wire                        ck_active
);
    wire [ADDR_BITS-1:0]     a;
    wire [BANK_BITS-1:0]     ba;
    wire                     ras_n, cas_n, we_n, ck_unused;
    wire [RANKS-1:0]         cs_n, cke;
    wire [DM_BITS-1:0]       dm;
    wire [DATA_BITS-1:0]     dq_o, dq_pad_i, dq_core;
    wire                     dq_oe, dq_oe_gated;
    wire                     ck_fwd;

    wire [CMD_BITS-1:0] core_cmd = {a, ba, ras_n, cas_n, we_n, cs_n, cke, dm};

    sdr_phy #(
        .ADDR_BITS(ADDR_BITS), .BANK_BITS(BANK_BITS),
        .DATA_BITS(DATA_BITS), .RANKS(RANKS), .CL(CL)
    ) u_core (
        .clk(clk), .rst(rst),
        .dfi_address(dfi_address), .dfi_bank(dfi_bank),
        .dfi_ras_n(dfi_ras_n), .dfi_cas_n(dfi_cas_n), .dfi_we_n(dfi_we_n),
        .dfi_cs_n(dfi_cs_n), .dfi_cke(dfi_cke),
        .dfi_odt(dfi_odt), .dfi_reset_n(dfi_reset_n), .dfi_act_n(dfi_act_n),
        .dfi_wrdata(dfi_wrdata), .dfi_wrdata_en(dfi_wrdata_en),
        .dfi_wrdata_mask(dfi_wrdata_mask), .dfi_rddata_en(dfi_rddata_en),
        .dfi_rddata(dfi_rddata), .dfi_rddata_valid(dfi_rddata_valid),
        .a(a), .ba(ba), .ras_n(ras_n), .cas_n(cas_n), .we_n(we_n),
        .cs_n(cs_n), .cke(cke), .dm(dm), .dq_o(dq_o), .dq_oe(dq_oe),
        .dq_i(dq_core), .ck(ck_unused)
    );
    wire _ck_unused = ck_unused;

    // Dedicated forwarded clock. ck_active / pad_ck are power gated.
    clock_forward #(.NPHASES(NPHASES), .SEL_W(SEL_W)) u_ckfwd (
        .clk(clk), .rst(rst),
        .ck_phase_clks(ck_phase_clks),
        .ck_phase_clocks_ready(ck_phase_clocks_ready),
        .ck_phase_sel(ck_phase_sel),
        .io_power_ok(io_power_ok),
        .ck_o(ck_fwd), .ck_active(ck_active),
        .using_backend_phase()
    );

    // Phase-adjustable capture reference (interface only; see header).
    wire [SEL_W-1:0] cap_phase_status;
    read_capture_ctrl #(.NPHASES(NPHASES), .SEL_W(SEL_W)) u_cap (
        .clk(clk), .rst(rst),
        .phase_clks(phase_clks), .phase_clocks_ready(phase_clocks_ready),
        .phase_sel(phase_sel), .phase_sel_valid(phase_sel_valid),
        .cap_clk(cap_clk), .phase_sel_status(cap_phase_status),
        .capture_ready(capture_ready)
    );

    // First-stage static capture: a real FF in the cap_clk domain samples
    // the pad input before the core edge. Phase 0 is a bypass (cap_clk is
    // the core clock). This assumes the selected phase LEADS the core edge;
    // a late phase needs the Read FIFO/CDC and a latency adjustment, which
    // is still TBD. Phase selection must be locked during traffic.
    reg [DATA_BITS-1:0] dq_cap;
    always @(posedge cap_clk) dq_cap <= dq_pad_i;
    wire use_capture = capture_ready && (cap_phase_status != {SEL_W{1'b0}});
    assign dq_core = use_capture ? dq_cap : dq_pad_i;

    // READ->WRITE turnaround guard on the PHY's own output enable.
    dq_turnaround #(
        .GUARD_CYCLES(GUARD_CYCLES),
        .READ_TAIL_CYCLES(READ_TAIL_CYCLES),
        .DQM_OFF_CYCLES(DQM_OFF_CYCLES),
        .T_OE_OFF_CYCLES(T_OE_OFF_CYCLES)
    ) u_turn (
        .clk(clk), .rst(rst),
        .wrdata_en(dfi_wrdata_en), .rddata_en(dfi_rddata_en),
        .dq_oe_gated(dq_oe_gated), .turnaround_busy(turnaround_busy)
    );

    phy_io_adapter #(
        .DATA_BITS(DATA_BITS), .CMD_BITS(CMD_BITS), .BACKEND(BACKEND),
        .T_OE_ON_PS(T_OE_ON_PS), .T_OE_OFF_PS(T_OE_OFF_PS)
    ) u_pad (
        .core_cmd(core_cmd),
        .core_dq_o(dq_o), .core_dq_oe(dq_oe_gated), .core_dq_i(dq_pad_i),
        .core_ck(ck_fwd),
        .pad_cmd(pad_cmd), .pad_dq(pad_dq), .pad_ck(pad_ck),
        .io_power_ok(io_power_ok), .pad_config(pad_config),
        .pad_ready(pad_ready), .contention(contention)
    );
endmodule
`default_nettype wire
