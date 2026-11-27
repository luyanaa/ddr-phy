// SPDX-License-Identifier: Apache-2.0
// Check DQ and DQM against the actual forwarded WRITE CK edge, including
// setup/hold, consecutive writes and a rejected write during turnaround.

`timescale 1ns/1ps
`default_nettype none
module tb_phy_top;
    localparam integer AB=13, BB=2, DB=8, CMD=21;
    localparam [3:0] NOP = 4'b1111, READ = 4'b0101, WRITE = 4'b0100;
    localparam real T_DS = 1.5, T_DH = 0.8; // Micron -75, ns
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
        .contention(contention), .ck_active(ck_active), .read_latency_error()
    );

    integer errors=0;
    task automatic chk(input cond, input [8*56:1] name);
        begin
            if (cond) $display("PASS %0s", name);
            else begin $display("FAIL %0s", name); errors=errors+1; end
        end
    endtask

    task automatic drive(input [3:0] cmd, input [DB-1:0] data, input mask);
        @(negedge clk); #1;
        {dfi_cs, dfi_ras, dfi_cas, dfi_we} = cmd;
        dfi_wren = (cmd == WRITE);
        dfi_rden = (cmd == READ);
        dfi_wrdata = data;
        dfi_wrmask = mask;
    endtask

    integer writes = 0;
    reg [DB:0] expected_write;
    realtime pins_changed = 0;
    always @(pad_dq or pad_cmd[0]) pins_changed = $realtime;

    always @(posedge pad_ck) begin
        if ({pad_cmd[2], pad_cmd[5:3]} === WRITE) begin
            chk(writes < 2, "no extra WRITE reached the SDRAM");
            expected_write = (writes == 0) ? {1'b0, 8'hA5} : {1'b1, 8'h3C};
            chk({pad_cmd[0], pad_dq} === expected_write, "WRITE CK samples matching DQM and DQ");
            chk($realtime - pins_changed >= T_DS, "DQM and DQ meet tDS before WRITE CK");
            #(T_DH);
            chk({pad_cmd[0], pad_dq} === expected_write, "DQM and DQ still driven at tDH");
            writes = writes + 1;
        end
    end

    initial begin
        repeat (3) @(posedge clk);
        @(negedge clk); #1; rst = 1'b0;
        chk(pad_ck === 1'b0 && ck_active === 1'b0, "top: CK held low before io power ok");
        chk(cap_clk === clk, "top: cap_clk falls back to clk without backend phase");
        chk(capture_ready === 1'b0, "top: capture_ready reflects backend");
        io_power_ok = 1'b1;
        @(posedge clk); #1;
        chk(pad_ready === 1'b1 && ck_active === 1'b1, "top: pad ready after power ok");
        chk(pad_ck === clk, "top: pad_ck from dedicated forwarding path");

        // An early WRITE during the read guard must reach neither CMD nor DQ.
        drive(READ, 0, 0);
        @(posedge clk); #1;
        chk(turnaround_busy === 1'b1, "read asserts turnaround_busy");
        drive(WRITE, 8'hFF, 1);
        @(negedge clk); #1;
        chk(pad_dq === {DB{1'bz}}, "blocked write leaves DQ undriven");
        drive(NOP, 0, 0);
        repeat (2) @(posedge clk);
        #1;
        chk(writes == 0, "blocked write never reached the SDRAM");
        chk(turnaround_busy === 1'b0, "turnaround clears after the read tail");

        // Opposite masks and unrelated data catch stale or shifted beats.
        drive(WRITE, 8'hA5, 0);
        drive(WRITE, 8'h3C, 1);
        drive(NOP, 0, 0);
        repeat (2) @(negedge clk);
        #1;
        chk(writes == 2, "both consecutive writes reached the SDRAM");
        chk(pad_dq === {DB{1'bz}}, "DQ released after the final rising-edge hold window");
        chk(contention === 1'b0, "no contention");

        #20;
        `ifdef MUTATE
        errors = errors + 1;
        $display("MUTATION: injected failure for exit-code test");
        `endif
        if (errors == 0) $display("PASS phy_top");
        else             $fatal(1, "FAIL phy_top errors=%0d", errors);
        $finish;
    end
endmodule
`default_nettype wire
