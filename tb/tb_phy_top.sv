// SPDX-License-Identifier: Apache-2.0
// Integration-top smoke test: CK comes from the dedicated forwarding path,
// cap_clk falls back to clk with no backend phase, turnaround gates OE,
// and a DFI write reaches the pad DQ bus.

`timescale 1ns/1ps
`default_nettype none
module tb_phy_top;
    localparam integer AB=13, BB=2, DB=8, CMD=21;
    reg clk=0, rst=1;
    always #5 clk = ~clk;

    reg [AB-1:0] dfi_a=0;
    reg [BB-1:0] dfi_ba=0;
    reg dfi_ras=1, dfi_cas=1, dfi_we=1, dfi_cs=1, dfi_cke=0;
    reg dfi_odt=0, dfi_reset=1, dfi_act=1;
    reg [DB-1:0] dfi_wrdata=0;
    reg dfi_wren=0, dfi_wrmask=0, dfi_rden=0;
    wire [DB-1:0] dfi_rddata;
    wire dfi_rdvalid;
    reg io_power_ok=0;
    reg [7:0] pad_config=0;
    reg [3:0] phase_clks=0, ck_phase_clks=0;
    reg phase_ready=0, phase_valid=0, ck_phase_ready=0;
    reg [1:0] phase_sel=0, ck_phase_sel=0;
    wire [CMD-1:0] pad_cmd;
    wire [DB-1:0] pad_dq;
    wire pad_ck, cap_clk, capture_ready, turnaround_busy, pad_ready, contention, ck_active;

    sdram_phy_top #(.ADDR_BITS(AB), .BANK_BITS(BB), .DATA_BITS(DB),
                    .RANKS(1), .CL(2), .NPHASES(4)) u_top (
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

    integer errors=0;
    task automatic chk(input cond, input [8*56:1] name);
        begin
            if (cond) $display("PASS %0s", name);
            else begin $display("FAIL %0s", name); errors=errors+1; end
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        rst = 1'b0;
        chk(pad_ck === 1'b0 && ck_active === 1'b0, "top: CK held low before io power ok");
        chk(cap_clk === clk, "top: cap_clk falls back to clk without backend phase");
        chk(capture_ready === 1'b0, "top: capture_ready reflects backend");
        io_power_ok = 1'b1;
        @(posedge clk); #1;
        chk(pad_ready === 1'b1 && ck_active === 1'b1, "top: pad ready after power ok");
        chk(pad_ck === clk, "top: pad_ck from dedicated forwarding path");

        // DFI write reaches pad DQ through turnaround guard + adapter.
        @(negedge clk);
        dfi_wrdata = 8'hA5; dfi_wren = 1'b1;
        @(posedge clk); #1;
        chk(pad_dq === 8'hA5, "top: DFI write visible on pad DQ");
        chk(contention === 1'b0, "top: no contention in single-driver write");
        @(negedge clk); dfi_wren = 1'b0;

        // A read asserts turnaround_busy and gates OE.
        @(negedge clk); dfi_rden = 1'b1;
        @(posedge clk); #1;
        chk(turnaround_busy === 1'b1, "top: read asserts turnaround_busy");
        @(negedge clk); dfi_rden = 1'b0; dfi_wren = 1'b1;
        @(posedge clk); #1;
        chk(pad_dq === {DB{1'bz}}, "top: OE gated during turnaround guard");
        @(negedge clk); dfi_wren = 1'b0;

        #20;
        if (errors == 0) $display("PASS phy_top");
        else             $display("FAIL phy_top errors=%0d", errors);
        $finish;
    end
endmodule
`default_nettype wire
