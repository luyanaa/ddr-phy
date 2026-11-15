// SPDX-License-Identifier: Apache-2.0
// 1:1 SDR PHY. Same DFI geometry and latency as LiteDRAM's GENSDRPHY
// (litedram/phy/gensdrphy.py): one phase, write_latency 0, read_latency
// CL+1. The CL cycles belong to the DRAM; the extra cycle is this
// module's DQ input register.
//
// Command, DQ and DM each go through one flip-flop, so a DFI value stable
// before an edge is on the pads after that edge. rddata_en shifts through
// a CL+1 bit register; rddata_valid is the bit that shifts out, and
// dfi_rddata is dq_i sampled on that same edge.
//
// The output tristate is not in this netlist. A standard-cell core cannot
// be the pad driver. dq_o / dq_oe / dq_i are the core side of a later pad.
// ck is this same clock, forwarded to that pad. It is not a second PLL and
// it is not divided. odt, reset_n and act_n are on the DFI and unused:
// SDR has none of those pins.

`default_nettype none

module sdr_phy #(
    parameter integer ADDR_BITS = 13,
    parameter integer BANK_BITS = 2,
    parameter integer DATA_BITS = 8,
    parameter integer RANKS     = 1,
    parameter integer CL        = 2
) (
    input  wire                          clk,
    input  wire                          rst,

    input  wire [ADDR_BITS-1:0]          dfi_address,
    input  wire [BANK_BITS-1:0]          dfi_bank,
    input  wire                          dfi_ras_n,
    input  wire                          dfi_cas_n,
    input  wire                          dfi_we_n,
    input  wire [RANKS-1:0]              dfi_cs_n,
    input  wire [RANKS-1:0]              dfi_cke,
    input  wire [RANKS-1:0]              dfi_odt,
    input  wire                          dfi_reset_n,
    input  wire                          dfi_act_n,
    input  wire [DATA_BITS-1:0]          dfi_wrdata,
    input  wire                          dfi_wrdata_en,
    input  wire [DATA_BITS/8-1:0]        dfi_wrdata_mask,
    input  wire                          dfi_rddata_en,
    output reg  [DATA_BITS-1:0]          dfi_rddata,
    output reg                           dfi_rddata_valid,

    output reg  [ADDR_BITS-1:0]          a,
    output reg  [BANK_BITS-1:0]          ba,
    output reg                           ras_n,
    output reg                           cas_n,
    output reg                           we_n,
    output reg  [RANKS-1:0]              cs_n,
    output reg  [RANKS-1:0]              cke,
    output reg  [DATA_BITS/8-1:0]        dm,
    output reg  [DATA_BITS-1:0]          dq_o,
    output reg                           dq_oe,
    input  wire [DATA_BITS-1:0]          dq_i,
    output wire                          ck
);

    localparam integer READ_LATENCY = CL + 1;
    localparam integer DM_BITS      = DATA_BITS / 8;

    generate
        if (!(CL == 2 || CL == 3)) begin : g_bad_cl
            invalid_cl_parameter this_module_does_not_exist();
        end
        if (DATA_BITS % 8 != 0 || DATA_BITS < 8) begin : g_bad_dq
            invalid_data_width this_module_does_not_exist();
        end
        if (RANKS < 1) begin : g_bad_ranks
            invalid_rank_count this_module_does_not_exist();
        end
    endgenerate

    // LSB is the newest rddata_en sample. valid is the oldest bit, consumed
    // on the same edge that shifts it out, which is CL+1 edges after the
    // enabling sample.
    reg [READ_LATENCY-1:0] rd_en_sr;

    assign ck = clk;

    wire unused_dfi = &{1'b0, dfi_odt, dfi_reset_n, dfi_act_n};
    wire _unused_ok = unused_dfi;

    // Synchronous set, not a reset to zero. A reset value of 0 on ras_n,
    // cas_n, we_n and cs_n is an illegal command, not a NOP. Every library
    // here has a flop with a synchronous set; writing the idle value in the
    // reset branch leaves the choice of set versus reset to the synthesizer.
    always @(posedge clk) begin
        a                <= rst ? {ADDR_BITS{1'b0}} : dfi_address;
        ba               <= rst ? {BANK_BITS{1'b0}} : dfi_bank;
        ras_n            <= rst ? 1'b1 : dfi_ras_n;
        cas_n            <= rst ? 1'b1 : dfi_cas_n;
        we_n             <= rst ? 1'b1 : dfi_we_n;
        cs_n             <= rst ? {RANKS{1'b1}} : dfi_cs_n;
        cke              <= rst ? {RANKS{1'b0}} : dfi_cke;
        dm               <= rst ? {DM_BITS{1'b0}}
                                : ({DM_BITS{dfi_wrdata_en}} & dfi_wrdata_mask);
        dq_o             <= rst ? {DATA_BITS{1'b0}} : dfi_wrdata;
        dq_oe            <= rst ? 1'b0 : dfi_wrdata_en;
        rd_en_sr         <= rst ? {READ_LATENCY{1'b0}}
                                : {rd_en_sr[READ_LATENCY-2:0], dfi_rddata_en};
        dfi_rddata_valid <= rst ? 1'b0 : rd_en_sr[READ_LATENCY-1];
        dfi_rddata       <= rst ? {DATA_BITS{1'b0}} : dq_i;
    end

endmodule

`default_nettype wire
