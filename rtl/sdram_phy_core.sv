// SPDX-License-Identifier: Apache-2.0
// Core-side integration top for the Class S SDR PHY.
//
// The pad ring lives outside this harden: cmd_o / dq_o / dq_oe / ck_o are
// core-side pins, dq_i is the receiver input.  sdram_phy_top wraps this
// module with the behavioral pad for RTL simulation; the silicon chip top
// wraps it with gf180_pad_core macros.
//
// Forward CK on its dedicated path. Qualify writes at the DFI edge, then
// launch DQ, DQM and OE together on the falling edge before the SDRAM
// samples WRITE. The controller must not issue WRITE while busy.
//
// With the baseline forwarded CK, a READ presented at sys edge N reaches
// the SDRAM command edge N+1. The first beat starts tAC after N+CL
// (CL-1 cycles after that command). Capture on the N+CL+1 cap_clk edge.
// Phase selection is static during traffic; the chosen phase must meet the
// read eye and the capture FIFO's clock-crossing timing.

`default_nettype none
module sdram_phy_core #(
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

    // Core side (pad ring is outside this harden)
    output wire [CMD_BITS-1:0]         cmd_o,
    output wire [DATA_BITS-1:0]        dq_o,
    output wire                        dq_oe,
    input  wire [DATA_BITS-1:0]        dq_i,
    output wire                        ck_o,

    // Status / coordination
    output wire                        cap_clk,
    output wire                        capture_ready,
    output wire                        turnaround_busy,
    output wire                        pad_ready,
    output wire                        contention,
    output wire                        ck_active,
    output wire                        read_latency_error
);
    wire [ADDR_BITS-1:0]     a;
    wire [BANK_BITS-1:0]     ba;
    wire                     ras_n, cas_n, we_n, ck_unused;
    wire [RANKS-1:0]         cs_n, cke;
    wire [DM_BITS-1:0]       dm;
    wire [DATA_BITS-1:0]     dq_pad_i = dq_i;
    wire [DATA_BITS-1:0]     rddata_unused;
    wire                     rdvalid_unused;
    wire                     ck_fwd;

    wire [CMD_BITS-1:0] core_cmd = {a, ba, ras_n, cas_n, we_n, cs_n, cke, dm};

    wire write_cmd = dfi_ras_n && !dfi_cas_n && !dfi_we_n;
    wire write_en = dfi_wrdata_en && !turnaround_busy;
    wire [RANKS-1:0] cmd_cs_n = (write_cmd && !write_en) ? {RANKS{1'b1}} : dfi_cs_n;

    sdr_phy #(
        .ADDR_BITS(ADDR_BITS), .BANK_BITS(BANK_BITS),
        .DATA_BITS(DATA_BITS), .RANKS(RANKS), .CL(CL)
    ) u_core (
        .clk(clk), .rst(rst),
        .dfi_address(dfi_address), .dfi_bank(dfi_bank),
        .dfi_ras_n(dfi_ras_n), .dfi_cas_n(dfi_cas_n), .dfi_we_n(dfi_we_n),
        .dfi_cs_n(cmd_cs_n), .dfi_cke(dfi_cke),
        .dfi_odt(dfi_odt), .dfi_reset_n(dfi_reset_n), .dfi_act_n(dfi_act_n),
        .dfi_wrdata(dfi_wrdata), .dfi_wrdata_en(write_en),
        .dfi_wrdata_mask(dfi_wrdata_mask), .dfi_rddata_en(dfi_rddata_en),
        .dfi_rddata(rddata_unused), .dfi_rddata_valid(rdvalid_unused),
        .a(a), .ba(ba), .ras_n(ras_n), .cas_n(cas_n), .we_n(we_n),
        .cs_n(cs_n), .cke(cke), .dm(dm), .dq_o(dq_o), .dq_oe(dq_oe),
        .dq_i(dq_pad_i), .ck(ck_unused)
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

    // Phase-adjustable capture clock supplied by the backend.
    wire [SEL_W-1:0] cap_phase_status;
    read_capture_ctrl #(.NPHASES(NPHASES), .SEL_W(SEL_W)) u_cap (
        .clk(clk), .rst(rst),
        .phase_clks(phase_clks), .phase_clocks_ready(phase_clocks_ready),
        .phase_sel(phase_sel), .phase_sel_valid(phase_sel_valid),
        .cap_clk(cap_clk), .phase_sel_status(cap_phase_status),
        .capture_ready(capture_ready)
    );

    // read_capture_cdc captures three cycles after accepting its request.
    // Delay the DFI request by CL-2: capture at N+CL+1, return at
    // N+CL-2+CDC_LATENCY+1 on dfi_rddata_valid (the registered valid output
    // adds one cycle to the FIFO's nominal CDC_LATENCY). sdr_phy constrains
    // CL to 2 or 3.
    wire capture_req;
    generate
        if (CL == 2) begin : g_capture_cl2
            assign capture_req = dfi_rddata_en;
        end else begin : g_capture_cl3
            reg req_q;
            always @(posedge clk)
                req_q <= !rst && dfi_rddata_en;
            assign capture_req = req_q;
        end
    endgenerate

    wire [DATA_BITS-1:0] cdc_rddata;
    wire                 cdc_rdvalid;
    read_capture_cdc #(.DATA_BITS(DATA_BITS), .LATENCY(CDC_LATENCY)) u_cdc (
        .clk(clk), .rst(rst), .cap_clk(cap_clk),
        .capture_req(capture_req), .dq_i(dq_pad_i),
        .rddata(cdc_rddata), .rddata_valid(cdc_rdvalid),
        .latency_error(read_latency_error)
    );
    assign dfi_rddata       = cdc_rddata;
    assign dfi_rddata_valid = cdc_rdvalid;

    // Hold off new writes through the read data tail and release guard.
    dq_turnaround #(
        .GUARD_CYCLES(GUARD_CYCLES),
        .READ_TAIL_CYCLES(READ_TAIL_CYCLES),
        .DQM_OFF_CYCLES(DQM_OFF_CYCLES),
        .T_OE_OFF_CYCLES(T_OE_OFF_CYCLES)
    ) u_turn (
        .clk(clk), .rst(rst), .rddata_en(dfi_rddata_en),
        .turnaround_busy(turnaround_busy)
    );

    assign cmd_o        = core_cmd;
    assign ck_o         = ck_fwd;
    assign pad_ready    = io_power_ok;
    assign contention   = 1'b0;
    wire _pad_config_unused = &{1'b0, pad_config};
endmodule
`default_nettype wire
