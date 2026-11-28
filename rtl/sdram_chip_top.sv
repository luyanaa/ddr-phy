// SPDX-License-Identifier: Apache-2.0
// Silicon chip top: hardened sdram_phy_core + 30 gf180_pad_tile sites
// inside the 32-site gf180_pad_ring.  Class S SDR PHY, x8, CL=2.
//
// This is the structural netlist that the chip-top layout implements and
// the reference that hierarchical LVS signs off against.  It is a netlist
// module, not a simulation top: gf180_pad_tile is a physical macro with a
// SPICE/LEF view, and every DFI / configuration input of the core is tied
// to a constant (pad_ring.md decision "1b: tie-off netlist"), so the die
// is the electrical PHY test vehicle of the LiteDRAM co-sim configuration
// (read_latency = CL-2+CDC_LATENCY+1 = 7, reports/litedram_cosim.md).
//
// Tie-off values mirror tb/tb_litedram_cosim.sv exactly:
//   io_power_ok=1, pad_config=0, phase_clks=0, phase_clocks_ready=0,
//   phase_sel=0, phase_sel_valid=0, ck_phase_*=0.  With phase_clocks_ready
//   low both clock_forward and read_capture_ctrl fall back to clk, which
//   is itself tied low, so the logic is static; the signoff targets are
//   connectivity, DRC and density, not full-chip function.
//
// Pad ordering: the 30 signals occupy 30 of the 32 ring sites; the two
// corner-most bottom-row sites are left as VDDIO/VSSIO power positions.
// The exact site assignment lives in specs/pads/sdram_chip_padmap.yaml
// and generator/emit_chip_top.py; this module only fixes connectivity.
//
// cmd bit map (rtl/sdram_phy_core.sv:97):
//   cmd_o[20:8] = a[12:0], cmd_o[7:6] = ba[1:0], cmd_o[5] = ras_n,
//   cmd_o[4] = cas_n, cmd_o[3] = we_n, cmd_o[2] = cs_n, cmd_o[1] = cke,
//   cmd_o[0] = dm.
`default_nettype none
module sdram_chip_top #(
    parameter integer ADDR_BITS = 13,
    parameter integer BANK_BITS = 2,
    parameter integer DATA_BITS = 8,
    parameter integer RANKS     = 1,
    parameter integer DM_BITS   = DATA_BITS / 8,
    parameter integer CMD_BITS  = ADDR_BITS + BANK_BITS + 3 + 2*RANKS + DM_BITS
)(
    // Bond pads, in die pad-ring order.  a[12] is the MSB of the address.
    inout  wire [CMD_BITS-1:0] pad_cmd,
    inout  wire [DATA_BITS-1:0] pad_dq,
    inout  wire                pad_ck,
    // Supplies.  VDDIO/VSSIO feed every pad site; VDD/VSS feed the core.
    inout  wire                VDDIO,
    inout  wire                VSSIO,
    inout  wire                VDD,
    inout  wire                VSS
);
    // Core-side wires.
    wire [CMD_BITS-1:0]  cmd_o;
    wire [DATA_BITS-1:0] dq_o;
    wire                 dq_oe;
    wire [DATA_BITS-1:0] dq_i;
    wire                 ck_o;

    // Unused core status outputs: no pins, tied off inside the core wrapper
    // scope so the netlist has no dangling driverless nets.
    wire cap_clk, capture_ready, turnaround_busy, pad_ready;
    wire contention, ck_active, read_latency_error;

    sdram_phy_core #(
        .ADDR_BITS(ADDR_BITS), .BANK_BITS(BANK_BITS),
        .DATA_BITS(DATA_BITS), .RANKS(RANKS), .CL(2), .CDC_LATENCY(6)
    ) u_core (
        .clk(1'b0), .rst(1'b1),
        .dfi_address({ADDR_BITS{1'b0}}), .dfi_bank({BANK_BITS{1'b0}}),
        .dfi_ras_n(1'b1), .dfi_cas_n(1'b1), .dfi_we_n(1'b1),
        .dfi_cs_n({RANKS{1'b1}}), .dfi_cke({RANKS{1'b0}}),
        .dfi_odt({RANKS{1'b0}}), .dfi_reset_n(1'b1), .dfi_act_n(1'b1),
        .dfi_wrdata({DATA_BITS{1'b0}}), .dfi_wrdata_en(1'b0),
        .dfi_wrdata_mask({DM_BITS{1'b0}}), .dfi_rddata_en(1'b0),
        .dfi_rddata(), .dfi_rddata_valid(),
        .io_power_ok(1'b1), .pad_config(8'b0),
        .phase_clks(4'b0), .phase_clocks_ready(1'b0),
        .phase_sel(2'b0), .phase_sel_valid(1'b0),
        .ck_phase_clks(4'b0), .ck_phase_clocks_ready(1'b0),
        .ck_phase_sel(2'b0),
        .cmd_o(cmd_o), .dq_o(dq_o), .dq_oe(dq_oe), .dq_i(dq_i),
        .ck_o(ck_o),
        .cap_clk(cap_clk), .capture_ready(capture_ready),
        .turnaround_busy(turnaround_busy), .pad_ready(pad_ready),
        .contention(contention), .ck_active(ck_active),
        .read_latency_error(read_latency_error)
    );

    // 21 command pads.  The command bits are single-ended outputs, so the
    // pad IN receiver output is left unconnected at the core (no core pin
    // consumes it); OE_N is tied low through the pad's own power-ok logic.
    genvar i;
    generate
        for (i = 0; i < CMD_BITS; i = i + 1) begin : g_cmd_pad
            gf180_pad_tile u_pad (
                .OUT(cmd_o[i]),
                .OE_N(1'b0),
                .PU_OK(),
                .PAD(pad_cmd[i]),
                .IN(),
                .VDDIO(VDDIO),
                .VSSIO(VSSIO)
            );
        end

        // 8 DQ pads: bidirectional.  OE is active-low at the pad, so the
        // core's active-high dq_oe is inverted per bit inside the adapter;
        // here the inversion is explicit per pad.
        for (i = 0; i < DATA_BITS; i = i + 1) begin : g_dq_pad
            gf180_pad_tile u_pad (
                .OUT(dq_o[i]),
                .OE_N(~dq_oe),
                .PU_OK(),
                .PAD(pad_dq[i]),
                .IN(dq_i[i]),
                .VDDIO(VDDIO),
                .VSSIO(VSSIO)
            );
        end
    endgenerate

    // Forwarded clock pad.
    gf180_pad_tile u_ck_pad (
        .OUT(ck_o),
        .OE_N(1'b0),
        .PU_OK(),
        .PAD(pad_ck),
        .IN(),
        .VDDIO(VDDIO),
        .VSSIO(VSSIO)
    );
endmodule
`default_nettype wire
