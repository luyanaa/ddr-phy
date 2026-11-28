// SPDX-License-Identifier: Apache-2.0
// Self-checking smoke for sim/ddr2_device_model.sv: the DDR2 command and
// data-path behaviour the PHY bring-up flow depends on, exercised over the
// pins. DDR2-400: CK = 5000 ps, `timescale 1ps/1ps`.
//
// Protocol notes these tests rely on (do not "fix" them by trial):
//   * commands launch on the negedge so they are stable at the sampling
//     posedge; the command task returns on the negedge after that posedge;
//   * a write arms WL ck after the command edge: the host drives dq first,
//     toggles dqs 500 ps later, and issues EXACTLY BL strobe edges. The
//     model consumes one beat per host-driven edge while armed, so extra
//     preamble/postamble toggles would steal beats;
//   * a read is edge aligned (JEDEC): the model raises the z->0 preamble one
//     half cycle before beat 0, then one strobe edge per beat, then lets the
//     bus go. The receiver skips the preamble edge and samples dq 100 ps
//     after each following strobe edge (same-edge NBA has settled by then);
//     never `wait (dq !== 8'hzz)` — that releases during the preamble gap;
//   * the sparse CAM store: unwritten columns read back as x, so only
//     written columns are compared (the DM case deliberately expects x).
//
// Coverage: (a) MRS/EMR init decode, (b) BL4 write+read-back, (c) BL8,
// (d) additive latency, (e) bank isolation, (f) A10 autoprecharge, (g) DM
// byte masking, (h) clean fault line.
`timescale 1ps/1ps
`default_nettype none

module tb_ddr2_model_smoke;

   localparam integer HALF_PS = 2500;   // DDR2-400 half CK

   // ---- device pins ------------------------------------------------
   reg         ck = 0, ck_n = 1;
   reg         cke = 1, cs_n = 1, ras_n = 1, cas_n = 1, we_n = 1, odt = 0;
   reg  [2:0]  ba = 0;
   reg  [13:0] a  = 0;
   reg         dm_drv = 0;
   wire        dm = dm_drv;
   wire [7:0]  dq;
   wire        dqs, dqs_n;
   wire        fault, initialized;
   wire [7:0]  fault_code;

   // host drivers for the shared buses (model drives dq/dqs on reads)
   reg         host_oe     = 0;
   reg  [7:0]  host_dq     = 0;
   reg         host_dqs_oe = 0;
   reg         host_dqs    = 0;
   assign dq  = host_oe     ? host_dq  : 8'hzz;
   assign dqs = host_dqs_oe ? host_dqs : 1'bz;

   ddr2_device_model #(.VERBOSE(1)) dut (
      .ck(ck), .ck_n(ck_n), .cke(cke), .cs_n(cs_n),
      .ras_n(ras_n), .cas_n(cas_n), .we_n(we_n),
      .ba(ba), .a(a), .odt(odt), .dm(dm),
      .dq(dq), .dqs(dqs), .dqs_n(dqs_n),
      .fault(fault), .fault_code(fault_code), .initialized(initialized));

   always #(HALF_PS) begin ck = ~ck; ck_n = ~ck_n; end

   integer errors = 0;
   integer bad    = 0;
   integer i;

   reg [7:0] wdat  [0:7];   // beats the host drives
   reg [7:0] exdat [0:7];   // beats expected back from the model
   reg       wdm   [0:7];   // per-beat DM mask
   reg [7:0] rdat  [0:7];   // beats captured on the model's strobes

   initial begin
      for (i = 0; i < 8; i = i + 1) begin
         wdat[i] = 8'h00; exdat[i] = 8'h00; wdm[i] = 1'b0; rdat[i] = 8'h00;
      end
   end

   // one PASS/FAIL line per checklist item; failures bump `errors`
   task item(input integer ok, input [8*64:1] label);
      begin
         if (ok) $display("PASS %0s", label);
         else begin
            $display("FAIL %0s", label);
            errors = errors + 1;
         end
      end
   endtask

   // compare the captured beats against exdat; report each mismatch
   task cmp(input integer n);
      integer j;
      begin
         for (j = 0; j < n; j = j + 1)
            if (rdat[j] !== exdat[j]) begin
               $display("  beat%0d got %h exp %h", j, rdat[j], exdat[j]);
               bad = bad + 1;
            end
      end
   endtask

   // command issued on the negedge, sampled by the model on the posedge
   task cmd(input [2:0] rcw, input [2:0] b, input [13:0] ad);
      begin
         @(negedge ck);
         cs_n = 0; {ras_n, cas_n, we_n} = rcw; ba = b; a = ad;
         @(negedge ck);
         cs_n = 1; {ras_n, cas_n, we_n} = 3'b111;
      end
   endtask

   task act(input [2:0] b, input [13:0] row);
      cmd(3'b011, b, row);
   endtask

   task mrs(input [2:0] b, input [13:0] ad);
      cmd(3'b000, b, ad);
   endtask

   // Write burst: exactly `bl` strobe edges, one per beat, at half-cycle
   // cadence. The descriptor arms WL ck after the command posedge, so wait
   // `wl` full cycles past the command's returning negedge first, then set
   // each data beat up 500 ps before its strobe edge.
   task wr_burst(input [2:0] b, input [13:0] col, input integer bl,
                 input integer wl, input ap);
      integer j;
      begin
         cmd(3'b100, b, ap ? {3'b000, 1'b1, col[9:0]} : {4'b0000, col[9:0]});
         host_oe = 1; host_dqs_oe = 1; host_dqs = 0;
         for (j = 0; j < wl; j = j + 1) begin
            @(posedge ck);
            @(negedge ck);
         end
         for (j = 0; j < bl; j = j + 1) begin
            host_dq = wdat[j];
            dm_drv  = wdm[j];
            #500 host_dqs = ~host_dqs;
            @(negedge ck);
         end
         host_oe = 0; host_dqs_oe = 0; host_dq = 8'h00; dm_drv = 0;
      end
   endtask

   // Read burst: skip the preamble edge, then sample dq 100 ps after each
   // strobe edge of the burst.
   task rd_burst(input [2:0] b, input [13:0] col, input integer bl,
                 input ap);
      integer j;
      begin
         cmd(3'b101, b, ap ? {3'b000, 1'b1, col[9:0]} : {4'b0000, col[9:0]});
         @(posedge dqs or negedge dqs);            // read preamble z->0
         for (j = 0; j < bl; j = j + 1) begin
            @(posedge dqs or negedge dqs);         // beat strobe edge
            #100 rdat[j] = dq;                     // same-edge NBA settled
         end
      end
   endtask

   initial begin : main
      // ---- (a) init sequence ---------------------------------------
      repeat (4) @(negedge ck);
      mrs(3'b010, 14'h0000);   // EMR2
      mrs(3'b011, 14'h0000);   // EMR3
      mrs(3'b001, 14'h0000);   // EMR1: AL=0, DLL on, differential DQS
      mrs(3'b000, 14'h0032);   // MR0: CL=3 (a[6:4]), seq, BL4 (a[2:0])
      repeat (3) @(negedge ck);
      if (initialized === 1'b1 && dut.BL === 4 && dut.CL === 3 &&
          dut.AL === 0 && dut.RL === 3 && dut.WL === 2)
         $display("PASS [a] init: BL=%0d CL=%0d AL=%0d RL=%0d WL=%0d",
                  dut.BL, dut.CL, dut.AL, dut.RL, dut.WL);
      else begin
         $display("FAIL [a] init: initialized=%b BL=%0d CL=%0d AL=%0d RL=%0d WL=%0d",
                  initialized, dut.BL, dut.CL, dut.AL, dut.RL, dut.WL);
         errors = errors + 1;
      end

      // ---- (b) BL4 write + read-back (reference scenario) ----------
      act(3'b000, 14'h0100);                       // open bank0 row 0x100
      wdat[0] = 8'h12; wdat[1] = 8'h34;
      wdat[2] = 8'h56; wdat[3] = 8'h78;
      for (i = 0; i < 4; i = i + 1) begin exdat[i] = wdat[i]; wdm[i] = 0; end
      wr_burst(3'b000, 14'h004, 4, dut.WL, 1'b0);
      rd_burst(3'b000, 14'h004, 4, 1'b0);
      bad = 0;
      cmp(4);
      item(bad == 0, "[b] BL4 write/read col 0x004");

      // ---- (c) BL8 --------------------------------------------------
      mrs(3'b000, 14'h0033);                       // MR0 BL=8 (a[2:0]=011)
      repeat (3) @(negedge ck);
      act(3'b000, 14'h0100);
      for (i = 0; i < 8; i = i + 1) begin
         wdat[i] = 8'hA0 + i[7:0];
         exdat[i] = wdat[i];
         wdm[i] = 0;
      end
      wr_burst(3'b000, 14'h008, 8, dut.WL, 1'b0);
      rd_burst(3'b000, 14'h008, 8, 1'b0);
      bad = 0;
      if (dut.BL !== 8) begin
         $display("  BL=%0d exp 8", dut.BL);
         bad = bad + 1;
      end
      cmp(8);
      item(bad == 0, "[c] BL8 write/read col 0x008");

      // ---- (d) additive latency ------------------------------------
      mrs(3'b000, 14'h0032);                       // MR0 back to BL=4
      mrs(3'b001, 14'h0008);                       // EMR1 AL=1 (a[5:3]=001)
      repeat (3) @(negedge ck);
      act(3'b000, 14'h0100);
      for (i = 0; i < 4; i = i + 1) begin
         wdat[i] = 8'h5A + i[7:0];
         exdat[i] = wdat[i];
         wdm[i] = 0;
      end
      // WL is now one ck longer; wr_burst reads it from the model
      wr_burst(3'b000, 14'h010, 4, dut.WL, 1'b0);
      rd_burst(3'b000, 14'h010, 4, 1'b0);
      bad = 0;
      if (dut.AL !== 1 || dut.RL !== dut.CL + 1 || dut.WL !== dut.CL) begin
         $display("  AL=%0d CL=%0d RL=%0d WL=%0d exp AL=1 RL=CL+1 WL=CL",
                  dut.AL, dut.CL, dut.RL, dut.WL);
         bad = bad + 1;
      end
      cmp(4);
      item(bad == 0, "[d] AL=1: RL=CL+1 WL=CL, BL4 write/read col 0x010");

      // ---- (e) bank isolation --------------------------------------
      act(3'b000, 14'h0100);
      act(3'b010, 14'h0200);                       // open bank2 row 0x200
      wdat[0] = 8'hC0; wdat[1] = 8'hC1;
      wdat[2] = 8'hC2; wdat[3] = 8'hC3;
      for (i = 0; i < 4; i = i + 1) begin exdat[i] = wdat[i]; wdm[i] = 0; end
      wr_burst(3'b000, 14'h020, 4, dut.WL, 1'b0);
      wdat[0] = 8'h0C; wdat[1] = 8'h1C;            // same column, other bank
      wdat[2] = 8'h2C; wdat[3] = 8'h3C;
      wr_burst(3'b010, 14'h020, 4, dut.WL, 1'b0);
      rd_burst(3'b000, 14'h020, 4, 1'b0);          // bank0 must see C0..C3
      bad = 0;
      cmp(4);
      exdat[0] = 8'h0C; exdat[1] = 8'h1C;          // bank2 must see 0C..3C
      exdat[2] = 8'h2C; exdat[3] = 8'h3C;
      rd_burst(3'b010, 14'h020, 4, 1'b0);
      cmp(4);
      item(bad == 0, "[e] bank isolation: bank0 col 0x020 vs bank2 col 0x020");

      // ---- (f) autoprecharge on A10 --------------------------------
      act(3'b000, 14'h0100);
      wdat[0] = 8'hF0; wdat[1] = 8'hF1;
      wdat[2] = 8'hF2; wdat[3] = 8'hF3;
      for (i = 0; i < 4; i = i + 1) begin exdat[i] = wdat[i]; wdm[i] = 0; end
      wr_burst(3'b000, 14'h040, 4, dut.WL, 1'b1);  // WRITE with a[10]=1
      bad = 0;
      if (dut.bank_open[0] !== 1'b0) begin
         $display("  bank_open[0] still set after WRITE A10=1");
         bad = bad + 1;
      end
      act(3'b010, 14'h0200);
      wdat[0] = 8'hE0; wdat[1] = 8'hE1;
      wdat[2] = 8'hE2; wdat[3] = 8'hE3;
      for (i = 0; i < 4; i = i + 1) begin exdat[i] = wdat[i]; wdm[i] = 0; end
      wr_burst(3'b010, 14'h024, 4, dut.WL, 1'b0);
      rd_burst(3'b010, 14'h024, 4, 1'b1);          // READ with a[10]=1
      cmp(4);                                      // data still returns
      if (dut.bank_open[2] !== 1'b0) begin
         $display("  bank_open[2] still set after READ A10=1");
         bad = bad + 1;
      end
      item(bad == 0, "[f] A10 autoprecharge clears bank_open (read intact)");

      // ---- (g) DM byte masking -------------------------------------
      act(3'b000, 14'h0100);                       // closed by (f): re-ACT
      wdat[0] = 8'hB1; wdat[1] = 8'hB2;
      wdat[2] = 8'hB3; wdat[3] = 8'hB4;
      for (i = 0; i < 4; i = i + 1) begin exdat[i] = wdat[i]; wdm[i] = 0; end
      wdm[2] = 1'b1;                               // mask beat 2
      exdat[2] = 8'hxx;                            // never stored -> reads x
      wr_burst(3'b000, 14'h030, 4, dut.WL, 1'b0);
      wdm[2] = 1'b0;
      rd_burst(3'b000, 14'h030, 4, 1'b0);
      bad = 0;
      cmp(4);
      item(bad == 0, "[g] DM masks beat 2 (reads x), beats 0/1/3 stored");

      // ---- (h) fault line ------------------------------------------
      repeat (4) @(negedge ck);
      if (fault !== 1'b0)
         $display("  fault_code=%0d", fault_code);
      item(fault === 1'b0, "[h] dut.fault clear after the clean flow");

      if (errors == 0) $display("DDR2_MODEL_SMOKE_PASS");
      else             $display("DDR2_MODEL_SMOKE_FAIL %0d", errors);
      $finish;
   end

   initial begin
      #20000000;
      $display("TIMEOUT at %0t", $time);
      $display("DDR2_MODEL_SMOKE_FAIL timeout");
      $finish;
   end

endmodule
`default_nettype wire
