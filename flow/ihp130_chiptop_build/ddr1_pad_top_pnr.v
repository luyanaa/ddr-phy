// SPDX-License-Identifier: Apache-2.0
// Experimental chip-top P&R wrapper: hardened ddr1_top + 8 SSTL2 DQ pad macros.
// Only the DQ group is populated; DQS/DM/CA/CK pad macros do not exist yet.
module ddr1_pad_top_pnr;
  wire [7:0] dq_i, dq_o;
  wire       dq_oe;

  ddr1_top u_core (
    .sys_clk(1'b0), .ck(1'b0), .ck90(1'b0), .rst(1'b1),
    .dqs_capture(1'b0),
    .init_done(), .read_error(), .dfi_error(),
    .phy_ready(), .train_busy(), .train_failed(),
    .dqs_tap_ready(1'b0), .dqs_tap_valid(), .dqs_tap_value(),
    .cmd_valid(1'b0), .cmd_we(1'b0), .cmd_addr(23'b0), .cmd_ready(),
    .w_data(32'b0), .w_we(4'b0), .w_ready(), .r_valid(), .r_data(),
    .pad_ck(), .pad_ck_n(), .a(), .ba(),
    .cke(), .cs_n(), .ras_n(), .cas_n(), .we_n(),
    .dq_i(dq_i), .dq_o(dq_o), .dq_oe(dq_oe),
    .dm(), .dqs_o(), .dqs_oe()
  );

  ihp130_sstl2_dq u_dq0 (
    .OUT(dq_o[0]), .IN(dq_i[0]), .OE(dq_oe),
    .PAD(), .VREF(1'b0), .PU_OK(1'b1),
    .VDD(), .VDDIO(), .VSSIO()
  );
  ihp130_sstl2_dq u_dq1 (
    .OUT(dq_o[1]), .IN(dq_i[1]), .OE(dq_oe),
    .PAD(), .VREF(1'b0), .PU_OK(1'b1),
    .VDD(), .VDDIO(), .VSSIO()
  );
  ihp130_sstl2_dq u_dq2 (
    .OUT(dq_o[2]), .IN(dq_i[2]), .OE(dq_oe),
    .PAD(), .VREF(1'b0), .PU_OK(1'b1),
    .VDD(), .VDDIO(), .VSSIO()
  );
  ihp130_sstl2_dq u_dq3 (
    .OUT(dq_o[3]), .IN(dq_i[3]), .OE(dq_oe),
    .PAD(), .VREF(1'b0), .PU_OK(1'b1),
    .VDD(), .VDDIO(), .VSSIO()
  );
  ihp130_sstl2_dq u_dq4 (
    .OUT(dq_o[4]), .IN(dq_i[4]), .OE(dq_oe),
    .PAD(), .VREF(1'b0), .PU_OK(1'b1),
    .VDD(), .VDDIO(), .VSSIO()
  );
  ihp130_sstl2_dq u_dq5 (
    .OUT(dq_o[5]), .IN(dq_i[5]), .OE(dq_oe),
    .PAD(), .VREF(1'b0), .PU_OK(1'b1),
    .VDD(), .VDDIO(), .VSSIO()
  );
  ihp130_sstl2_dq u_dq6 (
    .OUT(dq_o[6]), .IN(dq_i[6]), .OE(dq_oe),
    .PAD(), .VREF(1'b0), .PU_OK(1'b1),
    .VDD(), .VDDIO(), .VSSIO()
  );
  ihp130_sstl2_dq u_dq7 (
    .OUT(dq_o[7]), .IN(dq_i[7]), .OE(dq_oe),
    .PAD(), .VREF(1'b0), .PU_OK(1'b1),
    .VDD(), .VDDIO(), .VSSIO()
  );
endmodule
