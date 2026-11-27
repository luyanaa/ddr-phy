// SPDX-License-Identifier: Apache-2.0
// Check integrated SDR capture against the pin-level READ command and
// datasheet-sized data window, not against a value held across every edge.
// Exercise a single read and sustained one-beat-per-cycle reads with
// fixed, leading and lagging capture phases.

`timescale 1ns/1ps
`default_nettype none

module tb_read_capture_phase #(parameter integer CL = 2);
    localparam integer AB = 13;
    localparam integer BB = 2;
    localparam integer DB = 8;
    localparam integer CMD = 21;
    localparam integer READ_LATENCY = CL + 4;
    localparam integer DRAM_PIPE = CL - 1;
    localparam real T_AC = (CL == 2) ? 6.0 : 5.4; // Micron -75, ns
    localparam real T_OH = 3.0;
    localparam [3:0] READ = 4'b0101;

    reg clk = 1'b0;
    reg clk_early = 1'b0;
    reg clk_late = 1'b0;
    reg rst = 1'b1;
    always #5 clk = ~clk;
    initial begin #3; forever begin clk_early = 1; #5; clk_early = 0; #5; end end
    initial begin #7; forever begin clk_late  = 1; #5; clk_late  = 0; #5; end end

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
    wire [3:0] phase_clks = {1'b0, clk_late, clk_early, clk};
    reg phase_ready = 0, phase_valid = 1;
    reg [1:0] phase_sel = 0;
    reg [3:0] ck_phase_clks = 0;
    reg ck_phase_ready = 0;
    reg [1:0] ck_phase_sel = 0;
    wire [CMD-1:0] pad_cmd;
    wire [DB-1:0] pad_dq;
    wire pad_ck, cap_clk, capture_ready, turnaround_busy, pad_ready, contention;
    wire read_latency_error;

    wire dram_read = ({pad_cmd[2], pad_cmd[5:3]} === READ);
    wire [AB-1:0] dram_addr = pad_cmd[CMD-1 -: AB];
    reg [DRAM_PIPE-1:0] dram_valid = '0;
    reg [DB-1:0] dram_data [0:DRAM_PIPE-1];
    reg [DB-1:0] dram_dq = 'z;
    assign pad_dq = dram_dq;

    // Micron SDR drives the first beat at tAC after the (CL-1)th CK
    // after READ. After the last beat, keep it only through next CK + tOH.
    always @(posedge pad_ck) begin
        dram_valid <= (dram_valid << 1) | DRAM_PIPE'(dram_read);
        dram_data[0] <= dram_addr[DB-1:0];
        for (integer i = 1; i < DRAM_PIPE; i = i + 1)
            dram_data[i] <= dram_data[i-1];
        if (dram_valid[DRAM_PIPE-1]) dram_dq <= #(T_AC) dram_data[DRAM_PIPE-1];
        else                  dram_dq <= #(T_OH) 'z;
    end

    reg [READ_LATENCY-1:0] due_pipe = '0;
    reg [DB-1:0] expected_pipe [0:READ_LATENCY-1];
    reg due;
    reg [DB-1:0] expected;
    integer returned = 0;
    always @(posedge clk) if (!rst) begin
        due = due_pipe[READ_LATENCY-1];
        expected = expected_pipe[READ_LATENCY-1];
        due_pipe = {due_pipe[READ_LATENCY-2:0], dfi_rden};
        for (integer i = READ_LATENCY - 1; i > 0; i = i - 1)
            expected_pipe[i] = expected_pipe[i-1];
        expected_pipe[0] = dfi_a[DB-1:0];
        #0.001;
        if (read_latency_error !== 1'b0 || dfi_rdvalid !== due ||
            (due && dfi_rddata !== expected))
            $fatal(1, "CL=%0d phase=%0d valid=%b expected_valid=%b DQ=%h expected=%h latency_error=%b",
                   CL, phase_sel, dfi_rdvalid, due, dfi_rddata, expected, read_latency_error);
        if (due) returned = returned + 1;
    end

    sdram_phy_top #(
        .ADDR_BITS(AB), .BANK_BITS(BB), .DATA_BITS(DB), .RANKS(1),
        .CL(CL), .NPHASES(4), .SEL_W(2), .BACKEND(0)
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
        .contention(contention), .ck_active(), .read_latency_error(read_latency_error)
    );

    task automatic drive_read(input enable, input [DB-1:0] value);
        @(negedge clk); #1;
        dfi_a = {{(AB-DB){1'b0}}, value};
        dfi_cs = !enable;
        dfi_cas = !enable;
        dfi_rden = enable;
    endtask

    task automatic check_phase(input ready, input [1:0] sel);
        integer start_count;
        @(negedge clk); #1;
        phase_ready = ready;
        phase_sel = sel;
        repeat (3) @(negedge clk);
        if (sel == 1) begin
            @(posedge clk_early); #0.001;
            if (cap_clk !== 1'b1 || clk !== 1'b0) $fatal(1, "leading capture phase not selected");
        end else if (sel == 2) begin
            @(posedge clk); #0.001;
            if (cap_clk !== 1'b0) $fatal(1, "lagging capture phase rose before its edge");
            @(posedge clk_late); #0.001;
            if (cap_clk !== 1'b1) $fatal(1, "lagging capture phase not selected");
        end
        start_count = returned;

        drive_read(1, 8'hA5);
        drive_read(0, 0);
        repeat (READ_LATENCY + 1) @(negedge clk);
        if (returned != start_count + 1) $fatal(1, "single READ did not return");

        // Go around both FIFO pointers several times without an idle cycle.
        for (integer i = 0; i < 24; i = i + 1)
            drive_read(1, 8'h5A ^ 8'(i));
        drive_read(0, 0);
        repeat (READ_LATENCY + 1) @(negedge clk);
        if (returned != start_count + 25) $fatal(1, "pipelined READ lost data");
        $display("PASS read capture CL=%0d phase=%0d: single + 24 consecutive reads", CL, sel);
    endtask

    initial begin
        repeat (3) @(posedge clk);
        @(negedge clk); #1;
        rst = 1'b0;
        io_power_ok = 1'b1;
        dfi_cke = 1'b1;
        check_phase(0, 0);
        check_phase(1, 1);
        check_phase(1, 2);

        #20;
        `ifdef MUTATE
        $fatal(1, "MUTATION: injected failure for exit-code test");
        `endif
        $display("PASS read_capture_phase");
        $finish;
    end
endmodule

`default_nettype wire
