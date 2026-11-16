// SPDX-License-Identifier: Apache-2.0
// First-stage read-capture phase test.
//
// A real capture FF in sdram_phy_top samples the pad input on cap_clk
// before the core edge. With phase 0 (cap_clk = clk) the path bypasses the
// capture FF; with phase 1 (cap_clk leads clk by 2 ns) the FF captures the
// earlier value. The test drives the pad through an external model and
// changes it between the early edge and the core edge, so the two phases
// must return different data.
//
// This is a static-phase slice. It does not test a late phase, a Read
// FIFO/CDC, or dynamic phase changes during traffic.

`timescale 1ns/1ps
`default_nettype none

module tb_read_capture_phase;
    localparam integer AB = 13;
    localparam integer BB = 2;
    localparam integer DB = 8;
    localparam integer CMD = 21;

    reg clk = 1'b0;
    reg clk_early = 1'b0;
    reg rst = 1'b1;
    always #5 clk = ~clk;
    initial begin #3; forever #5 clk_early = ~clk_early; end

    reg [AB-1:0] dfi_a = 0;
    reg [BB-1:0] dfi_ba = 0;
    reg dfi_ras = 1, dfi_cas = 1, dfi_we = 1, dfi_cs = 1, dfi_cke = 0;
    reg dfi_odt = 0, dfi_reset = 1, dfi_act = 1;
    reg [DB-1:0] dfi_wrdata = 0;
    reg dfi_wren = 0, dfi_wrmask = 0, dfi_rden = 0;
    wire [DB-1:0] dfi_rddata;
    wire dfi_rdvalid;
    reg io_power_ok = 0;
    reg [7:0] pad_config = 0;
    reg [3:0] phase_clks;
    reg phase_ready = 1, phase_valid = 1;
    reg [1:0] phase_sel = 0;
    reg [3:0] ck_phase_clks = 0;
    reg ck_phase_ready = 0;
    reg [1:0] ck_phase_sel = 0;
    wire [CMD-1:0] pad_cmd;
    wire [DB-1:0] pad_dq;
    wire pad_ck, cap_clk, capture_ready, turnaround_busy, pad_ready, contention, ck_active;

    reg [DB-1:0] ext_dq = 0;
    reg ext_oe = 0;
    assign pad_dq = ext_oe ? ext_dq : {DB{1'bz}};

    always @(*) phase_clks = {2'b00, clk_early, clk};

    integer errors = 0;
    task automatic chk(input cond, input [8*64:1] name);
        begin
            if (cond) $display("PASS %0s", name);
            else begin $display("FAIL %0s", name); errors = errors + 1; end
        end
    endtask

    sdram_phy_top #(
        .ADDR_BITS(AB), .BANK_BITS(BB), .DATA_BITS(DB), .RANKS(1),
        .CL(2), .NPHASES(4), .SEL_W(2), .BACKEND(0)
    ) u_top (
        .clk(clk), .rst(rst),
        .dfi_address(dfi_a), .dfi_bank(dfi_ba),
        .dfi_ras_n(dfi_ras), .dfi_cas_n(dfi_cas), .dfi_we_n(dfi_we),
        .dfi_cs_n(dfi_cs), .dfi_cke(dfi_cke),
        .dfi_odt(dfi_odt), .dfi_reset_n(dfi_reset), .dfi_act_n(dfi_act),
        .dfi_wrdata(dfi_wrdata), .dfi_wrdata_en(dfi_wren),
        .dfi_wrdata_mask(dfi_wrmask), .dfi_rddata_en(dfi_rden),
        .dfi_rddata(dfi_rddata), .dfi_rddata_valid(dfi_rdvalid),
        .io_power_ok(io_power_ok), .pad_config(pad_config),
        .phase_clks(phase_clks), .phase_clocks_ready(phase_ready),
        .phase_sel(phase_sel), .phase_sel_valid(phase_valid),
        .ck_phase_clks(ck_phase_clks), .ck_phase_clocks_ready(ck_phase_ready),
        .ck_phase_sel(ck_phase_sel),
        .pad_cmd(pad_cmd), .pad_dq(pad_dq), .pad_ck(pad_ck),
        .cap_clk(cap_clk), .capture_ready(capture_ready),
        .turnaround_busy(turnaround_busy), .pad_ready(pad_ready),
        .contention(contention), .ck_active(ck_active)
    );

    task automatic read_with_split;
        input [DB-1:0] early_value;
        input [DB-1:0] late_value;
        output [DB-1:0] got;
        begin
            @(negedge clk);
            ext_oe = 1'b1;
            ext_dq = early_value;
            dfi_rden = 1'b1;
            @(posedge clk); #1;              // command edge
            @(posedge clk); #1;              // P1
            @(posedge clk); #1;              // P2
            @(posedge clk_early); #1;        // early edge before the valid edge
            ext_dq = late_value;
            @(posedge clk); #1;              // core valid edge
            got = dfi_rddata;
            if (dfi_rdvalid !== 1'b1) begin
                $display("FAIL read_capture_phase: rddata_valid missing");
                errors = errors + 1;
            end
            dfi_rden = 1'b0;
            @(posedge clk);
        end
    endtask

    reg [DB-1:0] got0, got1;

    initial begin
        repeat (3) @(posedge clk);
        @(negedge clk); rst = 1'b0;
        io_power_ok = 1'b1;
        phase_sel = 2'd0;
        @(posedge clk); #1;
        chk(cap_clk === clk, "phase: cap_clk = clk at phase 0");
        chk(capture_ready === 1'b1, "phase: capture_ready high");

        read_with_split(8'hA5, 8'h5A, got0);
        chk(got0 === 8'h5A, "phase 0 bypass returns the late value");

        @(negedge clk); phase_sel = 2'd1;
        @(posedge clk); #1;
        chk(cap_clk === clk_early, "phase 1 selects the early clock");
        read_with_split(8'hA5, 8'h5A, got1);
        chk(got1 === 8'hA5, "phase 1 capture returns the early value");
        chk(got1 !== got0, "phase selection changes captured data");

        #20;
        `ifdef MUTATE
        errors = errors + 1;
        $display("MUTATION: injected failure for exit-code test");
        `endif
        if (errors == 0) $display("PASS read_capture_phase");
        else             $fatal(1, "FAIL read_capture_phase errors=%0d", errors);
        $finish;
    end
endmodule

`default_nettype wire
