
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

    // The post-PnR netlist uses dfxtp (no reset pin): reset cannot clear X,
    // so the flops are initialised explicitly before time 0.
    initial begin
        $sdf_annotate("/grid/ddr-phy/flow/runs/sky130/final/sdf/max_ss_100C_1v60/sdr_phy__max_ss_100C_1v60.sdf", tb_gate.dut);
    end

    always #5 clk = ~clk;

    // The netlist uses dfxtp (no reset pin), so X cannot be cleared through
    // rst. Initialise every flop's Q directly, then release.
    integer fi;
    task release_flop(input integer k);
        begin
            case (k)
                0: release dut.\dq_o_q[0] ;
                1: release dut.\dq_o_q[1] ;
                2: release dut.\dq_o_q[2] ;
                3: release dut.\dq_o_q[3] ;
                4: release dut.\dq_o_q[4] ;
                5: release dut.\dq_o_q[5] ;
                6: release dut.\dq_o_q[6] ;
                7: release dut.\dq_o_q[7] ;
                8: release dut.dm_q;
                9: release dut.dq_oe_q;
                10: release dut.net41;
                11: release dut.net45;
                12: release dut.net46;
                13: release dut.net47;
                14: release dut.net48;
                15: release dut.net49;
                16: release dut.net50;
                17: release dut.net51;
                18: release dut.net52;
                19: release dut.net53;
                20: release dut.net42;
                21: release dut.net43;
                22: release dut.net44;
                23: release dut.net60;
                24: release dut.net61;
                25: release dut.net62;
                26: release dut.net63;
                27: release dut.net64;
                28: release dut.net65;
                29: release dut.net66;
                30: release dut.net67;
                31: release dut.net68;
                32: release dut.net54;
                33: release dut.net55;
                34: release dut.net79;
                35: release dut.net56;
                36: release dut.net80;
                37: release dut.net59;
                38: release dut.net58;
                39: release dut.\rd_en_sr[0] ;
                40: release dut.\rd_en_sr[1] ;
                41: release dut.\rd_en_sr[2] ;
                42: release dut.\rd_en_sr[3] ;
                43: release dut.net69;
                44: release dut.net70;
                45: release dut.net71;
                46: release dut.net72;
                47: release dut.net73;
                48: release dut.net74;
                49: release dut.net75;
                50: release dut.net76;
                51: release dut.net77;
                52: release dut.net78;
            endcase
        end
    endtask
    initial begin
        #0.5;
        for (fi = 0; fi < 53; fi = fi + 1) begin
            case (fi)
                0: force dut.\dq_o_q[0]  = 1'b0;
                1: force dut.\dq_o_q[1]  = 1'b0;
                2: force dut.\dq_o_q[2]  = 1'b0;
                3: force dut.\dq_o_q[3]  = 1'b0;
                4: force dut.\dq_o_q[4]  = 1'b0;
                5: force dut.\dq_o_q[5]  = 1'b0;
                6: force dut.\dq_o_q[6]  = 1'b0;
                7: force dut.\dq_o_q[7]  = 1'b0;
                8: force dut.dm_q = 1'b0;
                9: force dut.dq_oe_q = 1'b0;
                10: force dut.net41 = 1'b0;
                11: force dut.net45 = 1'b0;
                12: force dut.net46 = 1'b0;
                13: force dut.net47 = 1'b0;
                14: force dut.net48 = 1'b0;
                15: force dut.net49 = 1'b0;
                16: force dut.net50 = 1'b0;
                17: force dut.net51 = 1'b0;
                18: force dut.net52 = 1'b0;
                19: force dut.net53 = 1'b0;
                20: force dut.net42 = 1'b0;
                21: force dut.net43 = 1'b0;
                22: force dut.net44 = 1'b0;
                23: force dut.net60 = 1'b0;
                24: force dut.net61 = 1'b0;
                25: force dut.net62 = 1'b0;
                26: force dut.net63 = 1'b0;
                27: force dut.net64 = 1'b0;
                28: force dut.net65 = 1'b0;
                29: force dut.net66 = 1'b0;
                30: force dut.net67 = 1'b0;
                31: force dut.net68 = 1'b0;
                32: force dut.net54 = 1'b0;
                33: force dut.net55 = 1'b0;
                34: force dut.net79 = 1'b0;
                35: force dut.net56 = 1'b0;
                36: force dut.net80 = 1'b0;
                37: force dut.net59 = 1'b0;
                38: force dut.net58 = 1'b0;
                39: force dut.\rd_en_sr[0]  = 1'b0;
                40: force dut.\rd_en_sr[1]  = 1'b0;
                41: force dut.\rd_en_sr[2]  = 1'b0;
                42: force dut.\rd_en_sr[3]  = 1'b0;
                43: force dut.net69 = 1'b0;
                44: force dut.net70 = 1'b0;
                45: force dut.net71 = 1'b0;
                46: force dut.net72 = 1'b0;
                47: force dut.net73 = 1'b0;
                48: force dut.net74 = 1'b0;
                49: force dut.net75 = 1'b0;
                50: force dut.net76 = 1'b0;
                51: force dut.net77 = 1'b0;
                52: force dut.net78 = 1'b0;
            endcase
            #20;
            for (fi = 0; fi < 53; fi = fi + 1) release_flop(fi);
        end
    end

    integer errors = 0;
    integer rise_changes = 0, fall_changes = 0;
    reg [7:0] prev_dq;
    reg       prev_oe;

    // classify every dq_o / dq_oe change by the edge it happened on
    always @(dq_o or dq_oe) begin
        if (^dq_o !== 1'bx && dq_oe !== 1'bx) begin
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
        // X-init: the gate netlist has no resetable flops, so the first
        // checks run after enough cycles for the datapath to resolve.
        repeat (10) @(posedge clk);
        rst = 0;
        repeat (10) @(posedge clk);

        dfi_write(8'hA5);
        #1;
        // dq_o must be driven with A5 and dq_oe high around this write
        if (dq_oe !== 1'b1) begin
            $display("FAIL: dq_oe not asserted after the write command");
            errors = errors + 1;
        end
        if (dq_o !== 8'hA5) begin
            $display("FAIL: dq_o=%h expected A5", dq_o);
            $display("       internal: dq_oe_q=%b dq_o_q0=%b net78=%b",
                     dut.dq_oe_q, dut.dq_o_q[0], dut.net78);
            errors = errors + 1;
        end
        @(negedge clk); #1;
        if (fall_changes == 0) begin
            $display("FAIL: no dq_o/dq_oe transition on a falling edge");
            errors = errors + 1;
        end

        repeat (6) @(posedge clk);
        $display("dq_o/dq_oe transitions: rising=%0d falling=%0d",
                 rise_changes, fall_changes);
        if (rise_changes != 0) begin
            $display("FAIL: %0d transitions on the rising edge; the P1-3 ",
                     rise_changes);
            $display("      path-B contract requires a falling-edge launch");
            errors = errors + 1;
        end
        if (errors == 0) $display("PASS sdf-gate-check");
        else $display("FAIL sdf-gate-check errors=%0d", errors);
        $finish;
    end
endmodule
