// SPDX-License-Identifier: Apache-2.0
// Parameter shell around the sky130-mapped netlist sim/obj/sdr_phy_sky130.v.
// The netlist is elaborated at ADDR 13, BANK 2, DATA 8, RANKS 1, CL 2.
// Passing any other parameter is a compile failure. This is not a second PHY.

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
    output wire [DATA_BITS-1:0]          dfi_rddata,
    output wire                          dfi_rddata_valid,
    output wire [ADDR_BITS-1:0]          a,
    output wire [BANK_BITS-1:0]          ba,
    output wire                          ras_n,
    output wire                          cas_n,
    output wire                          we_n,
    output wire [RANKS-1:0]              cs_n,
    output wire [RANKS-1:0]              cke,
    output wire [DATA_BITS/8-1:0]        dm,
    output wire [DATA_BITS-1:0]          dq_o,
    output wire                          dq_oe,
    input  wire [DATA_BITS-1:0]          dq_i,
    output wire                          ck
);

    generate
        if (!(ADDR_BITS == 13 && BANK_BITS == 2 && DATA_BITS == 8 &&
              RANKS == 1 && CL == 2)) begin : g_not_this_netlist
            gate_netlist_is_cl2_x8_only this_module_does_not_exist();
        end
    endgenerate

    sdr_phy_g u (
        .clk(clk),
        .rst(rst),
        .dfi_address(dfi_address),
        .dfi_bank(dfi_bank),
        .dfi_ras_n(dfi_ras_n),
        .dfi_cas_n(dfi_cas_n),
        .dfi_we_n(dfi_we_n),
        .dfi_cs_n(dfi_cs_n),
        .dfi_cke(dfi_cke),
        .dfi_odt(dfi_odt),
        .dfi_reset_n(dfi_reset_n),
        .dfi_act_n(dfi_act_n),
        .dfi_wrdata(dfi_wrdata),
        .dfi_wrdata_en(dfi_wrdata_en),
        .dfi_wrdata_mask(dfi_wrdata_mask),
        .dfi_rddata_en(dfi_rddata_en),
        .dfi_rddata(dfi_rddata),
        .dfi_rddata_valid(dfi_rddata_valid),
        .a(a),
        .ba(ba),
        .ras_n(ras_n),
        .cas_n(cas_n),
        .we_n(we_n),
        .cs_n(cs_n),
        .cke(cke),
        .dm(dm),
        .dq_o(dq_o),
        .dq_oe(dq_oe),
        .dq_i(dq_i),
        .ck(ck)
    );

endmodule

`default_nettype wire
