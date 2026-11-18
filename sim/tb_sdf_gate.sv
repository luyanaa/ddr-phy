`timescale 1ns/1ps
module tb_gate;
    reg clk = 0, rst = 1;
    reg [12:0] dfi_address = 0;
    reg [1:0]  dfi_bank = 0;
    reg dfi_ras_n = 1, dfi_cas_n = 1, dfi_we_n = 1;
    reg dfi_cs_n = 1, dfi_cke = 0;
    reg dfi_odt = 0, dfi_reset_n = 1, dfi_act_n = 1;
    reg [7:0]  dfi_wrdata = 0;
    reg        dfi_wrdata_en = 0;
    reg [0:0]  dfi_wrdata_mask = 0;
    reg        dfi_rddata_en = 0;
    wire [7:0] dfi_rddata;
    wire       dfi_rddata_valid;
    wire [12:0] a; wire [1:0] ba;
    wire ras_n, cas_n, we_n, cs_n, cke;
    wire [0:0] dm;
    wire [7:0] dq_o;
    wire dq_oe; wire ck;

    sdr_phy dut (
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
        .dq_i(dfi_rddata), .ck(ck)
    );

    initial begin
        $sdf_annotate("/grid/ddr-phy/flow/runs/sky130/final/sdf/max_ss_100C_1v60/sdr_phy__max_ss_100C_1v60.sdf", tb_gate.dut);
    end

    always #5 clk = ~clk;

    integer errors = 0;
    integer rise_changes = 0, fall_changes = 0;

    // Classify every dq_o / dq_oe change by the edge it happened on. The
    // pad-side launch flops are clocked from !clk, so any transition while
    // clk is high would mean the half-cycle advance was lost in synthesis.
    always @(dq_o or dq_oe) begin
        if ((^dq_o !== 1'bx) && (dq_oe !== 1'bx)) begin
            if (clk === 1'b1) rise_changes = rise_changes + 1;
            else if (clk === 1'b0) fall_changes = fall_changes + 1;
        end
    end

    task dfi_write(input [7:0] data);
        begin
            @(posedge clk); #1;
            dfi_cs_n = 0; dfi_ras_n = 1; dfi_cas_n = 0; dfi_we_n = 0;
            dfi_address = 13'h0003; dfi_bank = 0;
            dfi_wrdata = data; dfi_wrdata_en = 1; dfi_wrdata_mask = 1'b0;
            @(posedge clk); #1;
            dfi_cs_n = 1; dfi_ras_n = 1; dfi_cas_n = 1; dfi_we_n = 1;
            dfi_wrdata_en = 0;
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        rst = 0;
        repeat (4) @(posedge clk);

        dfi_write(8'hA5);
        // The launch happens on the falling edge, so sample after it. One
        // extra negedge covers the holding-register + launch flop pair.
        @(negedge clk); #1;
        if (dq_oe !== 1'b1) begin
            $display("FAIL: dq_oe not asserted after the write command");
            errors = errors + 1;
        end
        if (dq_o !== 8'hA5) begin
            $display("FAIL: dq_o=%h expected A5", dq_o);
            errors = errors + 1;
        end
        if (fall_changes == 0) begin
            $display("FAIL: no dq_o/dq_oe transition on a falling edge");
            errors = errors + 1;
        end

        repeat (6) @(posedge clk);
        $display("dq_o/dq_oe transitions: rising=%0d falling=%0d",
                 rise_changes, fall_changes);
        if (rise_changes != 0) begin
            $display("FAIL: %0d transitions on the rising edge; the P1-3 "
                     , rise_changes);
            $display("      path-B contract requires a falling-edge launch");
            errors = errors + 1;
        end
        if (errors == 0) $display("PASS sdf-gate-check");
        else $display("FAIL sdf-gate-check errors=%0d", errors);
        $finish;
    end
endmodule
