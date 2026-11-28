// SPDX-License-Identifier: Apache-2.0
// Flattened structural chip-top P&R netlist for OpenROAD macro integration.
// Power pins omitted (bound via add_global_connection + pdngen).


module sdram_chip_top_pnr ();
  wire dq_oe, n_dq_oe;
  wire [20:0] cmd_o;
  wire [7:0] dq_o;
  wire [7:0] dq_i;
  wire ck_o;

  gf180mcu_as_sc_mcu7t3v3__inv_2 u_dqoe_inv (.A(dq_oe), .Y(n_dq_oe));

  sdram_phy_core u_core (
    .cmd_o(cmd_o), .dq_o(dq_o), .dq_i(dq_i), .dq_oe(dq_oe), .ck_o(ck_o)
  );

  gf180_pad_tile u_pad_1 (.OUT(cmd_o[11]), .IN(), .OE_N(), .PU_OK(), .PAD());
  gf180_pad_tile u_pad_2 (.OUT(cmd_o[12]), .IN(), .OE_N(), .PU_OK(), .PAD());
  gf180_pad_tile u_pad_3 (.OUT(cmd_o[13]), .IN(), .OE_N(), .PU_OK(), .PAD());
  gf180_pad_tile u_pad_4 (.OUT(ck_o), .IN(), .OE_N(), .PU_OK(), .PAD());
  gf180_pad_tile u_pad_5 (.OUT(cmd_o[14]), .IN(), .OE_N(), .PU_OK(), .PAD());
  gf180_pad_tile u_pad_6 (.OUT(cmd_o[15]), .IN(), .OE_N(), .PU_OK(), .PAD());
  gf180_pad_tile u_pad_7 (.OUT(cmd_o[16]), .IN(), .OE_N(), .PU_OK(), .PAD());
  gf180_pad_tile u_pad_9 (.OUT(dq_o[0]), .IN(dq_i[0]), .OE_N(n_dq_oe), .PU_OK(), .PAD());
  gf180_pad_tile u_pad_10 (.OUT(dq_o[1]), .IN(dq_i[1]), .OE_N(n_dq_oe), .PU_OK(), .PAD());
  gf180_pad_tile u_pad_11 (.OUT(dq_o[2]), .IN(dq_i[2]), .OE_N(n_dq_oe), .PU_OK(), .PAD());
  gf180_pad_tile u_pad_12 (.OUT(dq_o[3]), .IN(dq_i[3]), .OE_N(n_dq_oe), .PU_OK(), .PAD());
  gf180_pad_tile u_pad_13 (.OUT(dq_o[4]), .IN(dq_i[4]), .OE_N(n_dq_oe), .PU_OK(), .PAD());
  gf180_pad_tile u_pad_14 (.OUT(dq_o[5]), .IN(dq_i[5]), .OE_N(n_dq_oe), .PU_OK(), .PAD());
  gf180_pad_tile u_pad_15 (.OUT(dq_o[6]), .IN(dq_i[6]), .OE_N(n_dq_oe), .PU_OK(), .PAD());
  gf180_pad_tile u_pad_16 (.OUT(dq_o[7]), .IN(dq_i[7]), .OE_N(n_dq_oe), .PU_OK(), .PAD());
  gf180_pad_tile u_pad_17 (.OUT(cmd_o[20]), .IN(), .OE_N(), .PU_OK(), .PAD());
  gf180_pad_tile u_pad_18 (.OUT(cmd_o[19]), .IN(), .OE_N(), .PU_OK(), .PAD());
  gf180_pad_tile u_pad_19 (.OUT(cmd_o[18]), .IN(), .OE_N(), .PU_OK(), .PAD());
  gf180_pad_tile u_pad_20 (.OUT(cmd_o[17]), .IN(), .OE_N(), .PU_OK(), .PAD());
  gf180_pad_tile u_pad_21 (.OUT(cmd_o[10]), .IN(), .OE_N(), .PU_OK(), .PAD());
  gf180_pad_tile u_pad_22 (.OUT(cmd_o[9]), .IN(), .OE_N(), .PU_OK(), .PAD());
  gf180_pad_tile u_pad_23 (.OUT(cmd_o[8]), .IN(), .OE_N(), .PU_OK(), .PAD());
  gf180_pad_tile u_pad_24 (.OUT(cmd_o[7]), .IN(), .OE_N(), .PU_OK(), .PAD());
  gf180_pad_tile u_pad_25 (.OUT(cmd_o[6]), .IN(), .OE_N(), .PU_OK(), .PAD());
  gf180_pad_tile u_pad_26 (.OUT(cmd_o[5]), .IN(), .OE_N(), .PU_OK(), .PAD());
  gf180_pad_tile u_pad_27 (.OUT(cmd_o[4]), .IN(), .OE_N(), .PU_OK(), .PAD());
  gf180_pad_tile u_pad_28 (.OUT(cmd_o[3]), .IN(), .OE_N(), .PU_OK(), .PAD());
  gf180_pad_tile u_pad_29 (.OUT(cmd_o[2]), .IN(), .OE_N(), .PU_OK(), .PAD());
  gf180_pad_tile u_pad_30 (.OUT(cmd_o[1]), .IN(), .OE_N(), .PU_OK(), .PAD());
  gf180_pad_tile u_pad_31 (.OUT(cmd_o[0]), .IN(), .OE_N(), .PU_OK(), .PAD());
endmodule
