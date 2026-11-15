// SPDX-License-Identifier: Apache-2.0
// P0-4 module tests: capture phase select, CK forwarding, DQ turnaround,
// and SDRAM read-side DQM masking (2-cycle latency) in the layer-1 model.

`timescale 1ns/1ps
`default_nettype none

module tb_phy_enh;
    reg clk = 0;
    always #5 clk = ~clk;

    integer errors = 0;
    task automatic chk(input cond, input [8*56:1] name);
        begin
            if (cond) $display("PASS %0s", name);
            else begin $display("FAIL %0s", name); errors = errors + 1; end
        end
    endtask

    // ---- read_capture_ctrl ----
    reg        rc_rst = 1, rc_valid = 0, rc_ready = 0;
    reg [1:0]  rc_sel = 0;
    reg [3:0]  rc_clks = 4'b0000;
    wire       rc_cap, rc_ready_o;
    wire [1:0] rc_status;
    read_capture_ctrl #(.NPHASES(4), .SEL_W(2)) u_rc (
        .clk(clk), .rst(rc_rst), .phase_clks(rc_clks),
        .phase_clocks_ready(rc_ready), .phase_sel(rc_sel),
        .phase_sel_valid(rc_valid), .cap_clk(rc_cap),
        .phase_sel_status(rc_status), .capture_ready(rc_ready_o)
    );

    // ---- clock_forward ----
    reg        cf_rst = 1, cf_ready = 0, cf_power = 0;
    reg [1:0]  cf_sel = 0;
    reg [3:0]  cf_clks = 4'b0000;
    wire       cf_ck, cf_active, cf_using;
    clock_forward #(.NPHASES(4), .SEL_W(2)) u_cf (
        .clk(clk), .rst(cf_rst), .ck_phase_clks(cf_clks),
        .ck_phase_clocks_ready(cf_ready), .ck_phase_sel(cf_sel),
        .io_power_ok(cf_power), .ck_o(cf_ck), .ck_active(cf_active),
        .using_backend_phase(cf_using)
    );

    // ---- dq_turnaround ----
    reg        dt_rst = 1, dt_wr = 0, dt_rd = 0;
    wire       dt_oe, dt_busy;
    dq_turnaround #(.GUARD_CYCLES(1)) u_dt (
        .clk(clk), .rst(dt_rst), .wrdata_en(dt_wr), .rddata_en(dt_rd),
        .dq_oe_gated(dt_oe), .turnaround_busy(dt_busy)
    );

    // ---- sdram_model DQM read mask ----
    localparam integer AB = 13, BB = 2, RB = 4, CB = 4, DB = 16;
    reg        dram_cke = 1, dram_cs = 1, dram_ras = 1, dram_cas = 1, dram_we = 1;
    reg [BB-1:0]  dram_ba = 0;
    reg [AB-1:0]  dram_a  = 0;
    reg [DB/8-1:0] dram_dm = 0;
    reg        drv_oe = 0;
    reg [DB-1:0] drv_data = 0;
    wire [DB-1:0] dram_dq;
    wire       dram_fault;
    wire [2:0] dram_code;
    assign dram_dq = drv_oe ? drv_data : {DB{1'bz}};
    sdram_model #(.ADDR_BITS(AB), .BANK_BITS(BB), .DATA_BITS(DB),
                  .ROW_BITS(RB), .COL_BITS(CB)) u_dram (
        .ck(clk), .cke(dram_cke), .cs_n(dram_cs), .ras_n(dram_ras),
        .cas_n(dram_cas), .we_n(dram_we), .ba(dram_ba), .a(dram_a),
        .dm(dram_dm), .dq(dram_dq),
        .fault(dram_fault), .fault_code(dram_code)
    );

    // c = {cs_n, ras_n, cas_n, we_n}; present through the negedge,
    // one launching posedge, then settle.
    task automatic step;
        input [3:0] c;
        input [BB-1:0] b;
        input [AB-1:0] ad;
        input [DB/8-1:0] dqm;
        input drv;
        input [DB-1:0] dd;
        begin
            @(negedge clk);
            dram_cs = c[3]; dram_ras = c[2]; dram_cas = c[1]; dram_we = c[0];
            dram_ba = b; dram_a = ad; dram_dm = dqm;
            drv_oe = drv; drv_data = dd;
            @(posedge clk);
            #1;
        end
    endtask

    localparam [3:0] NOP = 4'b1111, MRS = 4'b0000, ACT = 4'b0011,
                     WR  = 4'b0100, RD  = 4'b0101;

    initial begin
        // --- capture phase select ---
        repeat (3) @(posedge clk);
        rc_rst = 0; cf_rst = 0; dt_rst = 0;
        rc_sel = 2'd2; rc_valid = 1'b1; rc_clks = 4'b0000; rc_ready = 1'b1;
        @(posedge clk); #1; rc_valid = 1'b0;
        chk(rc_status === 2'd2, "capture: phase_sel CSR latched");
        rc_clks = 4'b0100;
        #1;
        chk(rc_cap === 1'b1, "capture: selected phase clock drives cap_clk");
        rc_clks = 4'b0000;
        #1;
        chk(rc_cap === 1'b0, "capture: cap_clk follows selected phase");
        rc_ready = 1'b0;
        #1;
        chk(rc_cap === clk, "capture: no backend phase -> fixed-phase fallback");
        chk(rc_ready_o === 1'b0, "capture: capture_ready reflects backend");

        // --- CK forwarding ---
        cf_power = 1'b1; cf_ready = 1'b1; cf_sel = 2'd1; cf_clks = 4'b0010;
        #1;
        chk(cf_ck === 1'b1, "clock_forward: backend CK phase selected");
        chk(cf_active === 1'b1 && cf_using === 1'b1, "clock_forward: active + backend flags");
        cf_power = 1'b0;
        #1;
        chk(cf_ck === 1'b0, "clock_forward: CK held low until io power ok");

        // --- DQ turnaround ---
        dt_rd = 1'b1; dt_wr = 1'b0;
        @(posedge clk); #1;
        chk(dt_busy === 1'b1, "turnaround: busy asserted on read");
        dt_rd = 1'b0; dt_wr = 1'b1;
        @(posedge clk); #1;
        chk(dt_oe === 1'b0, "turnaround: OE gated during guard cycle");
        chk(dt_busy === 1'b1, "turnaround: busy held during guard");
        @(posedge clk); #1;
        chk(dt_oe === 1'b1 && dt_busy === 1'b0, "turnaround: OE released after guard");
        dt_wr = 1'b0;

        // --- SDRAM read DQM masking (CL=2, BL=1) ---
        // Data-out edge for a READ at edge R is R+1; DQM at R-1 masks it.
        step(MRS, 2'd0, 13'h0020, 2'b00, 1'b0, 16'h0000); // CL2, BL1
        step(NOP, 2'd0, 13'h0000, 2'b00, 1'b0, 16'h0000);
        step(ACT, 2'd0, 13'h0000, 2'b00, 1'b0, 16'h0000);
        step(NOP, 2'd0, 13'h0000, 2'b00, 1'b0, 16'h0000);
        step(NOP, 2'd0, 13'h0000, 2'b00, 1'b0, 16'h0000);
        step(WR,  2'd0, 13'h0000, 2'b00, 1'b1, 16'hA55A); // write A55A
        step(NOP, 2'd0, 13'h0000, 2'b11, 1'b0, 16'h0000); // R-1: mask both bytes
        step(RD,  2'd0, 13'h0000, 2'b00, 1'b0, 16'h0000); // R
        step(NOP, 2'd0, 13'h0000, 2'b00, 1'b0, 16'h0000); // R+1: data edge
        chk(dram_dq === {DB{1'bz}}, "DQM read: masked bytes are Hi-Z after 2 cycles");
        step(NOP, 2'd0, 13'h0000, 2'b00, 1'b0, 16'h0000);
        step(NOP, 2'd0, 13'h0000, 2'b00, 1'b0, 16'h0000);
        step(RD,  2'd0, 13'h0000, 2'b00, 1'b0, 16'h0000); // unmasked read
        step(NOP, 2'd0, 13'h0000, 2'b00, 1'b0, 16'h0000);
        chk(dram_dq === 16'hA55A, "DQM read: unmasked read returns written data");
        chk(dram_fault === 1'b0, "DQM read: no protocol fault raised");

        #20;
        if (errors == 0) $display("PASS phy_enh");
        else             $display("FAIL phy_enh errors=%0d", errors);
        $finish;
    end
endmodule
`default_nettype wire
