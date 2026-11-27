// SPDX-License-Identifier: Apache-2.0
`timescale 1ps/1ps
`include "ddr1_timing.vh"
`default_nettype none
module tb_ddr1_train #(parameter integer FAIL_MODE = 0);
    localparam integer CK_PS = `DDR1_TCK_PS;
    localparam integer TAP_STEP_PS = CK_PS / 32;
    localparam [22:0] USER_ADDR = 23'h000123;
    localparam [31:0] USER_PATTERN = 32'h5aa5c33c;

    reg ck = 0, sys_clk = 0, rst = 1;
    always #(CK_PS/2) ck = ~ck;
    always @(posedge ck) sys_clk <= ~sys_clk;
    wire ck90;
    assign #(CK_PS/4) ck90 = ck;

    reg cmd_valid = 0, cmd_we = 0;
    reg [22:0] cmd_addr = 0;
    reg [31:0] w_data = 0;
    reg [3:0] w_we = 0;
    wire cmd_ready, w_ready, r_valid;
    wire [31:0] r_data;
    wire init_done, phy_ready, train_busy, train_failed;
    wire read_error, dfi_error;
    wire pad_ck, pad_ck_n, cke, cs_n, ras_n, cas_n, we_n, dm;
    wire [12:0] a;
    wire [1:0] ba;
    wire [7:0] dq_o;
    wire dq_oe, dqs_o, dqs_oe;
    tri [7:0] dq;
    tri dqs;
    assign dq = dq_oe ? dq_o : 8'bz;
    assign dqs = dqs_oe ? dqs_o : 1'bz;

    wire [0:0] dqs_tap_valid;
    wire [3:0] dqs_tap_value;
    reg [0:0] dqs_tap_ready = 0;
    reg [3:0] selected_tap = 0;
    reg tap_applied = 0;
    integer tap_requests = 0;
    wire [15:0] dqs_capture_taps;
    wire [0:0] dqs_capture;
    reg gate_noise = 0, noise_used = 0;
    generate
        for (genvar tap = 0; tap < 16; tap = tap + 1) begin : g_tap_model
            localparam integer TAP_DELAY_PS = FAIL_MODE ? 4*CK_PS :
                                                        CK_PS/8 + tap*TAP_STEP_PS;
            assign #(TAP_DELAY_PS) dqs_capture_taps[tap] = (dqs === 1'b1);
        end
    endgenerate
    assign dqs_capture[0] = dqs_capture_taps[selected_tap] | gate_noise;

    // Model a real applied-tap handshake: selected_tap changes first, then
    // ready is asserted on the following SYS edge and held through acceptance.
    always @(posedge sys_clk or posedge rst) begin
        if (rst) begin
            dqs_tap_ready <= 1'b0;
            selected_tap <= 4'd0;
            tap_applied <= 1'b0;
            tap_requests <= 0;
        end else if (!dqs_tap_valid[0]) begin
            dqs_tap_ready <= 1'b0;
            tap_applied <= 1'b0;
        end else if (!tap_applied) begin
            selected_tap <= dqs_tap_value;
            tap_applied <= 1'b1;
            tap_requests <= tap_requests + 1;
        end else begin
            dqs_tap_ready <= 1'b1;
        end
    end

    // One deliberately noisy tap adds an extra edge inside the active window.
    always @(posedge sys_clk) begin
        if (rst) begin
            gate_noise <= 1'b0;
            noise_used <= 1'b0;
        end else if (!dut.phy.capture_frame) begin
            gate_noise <= 1'b0;
            noise_used <= 1'b0;
        end else if (!noise_used && selected_tap == 4'd6) begin
            noise_used <= 1'b1;
            #100 gate_noise = 1'b1;
            #100 gate_noise = 1'b0;
        end
    end

    ddr1_top #(.TRAIN_ENABLE(1), .TAP_BITS(4)) dut (
        .sys_clk(sys_clk), .ck(ck), .ck90(ck90), .rst(rst),
        .dqs_capture(dqs_capture), .init_done(init_done),
        .read_error(read_error), .dfi_error(dfi_error), .phy_ready(phy_ready),
        .train_busy(train_busy), .train_failed(train_failed),
        .dqs_tap_ready(dqs_tap_ready), .dqs_tap_valid(dqs_tap_valid),
        .dqs_tap_value(dqs_tap_value), .cmd_valid(cmd_valid), .cmd_we(cmd_we),
        .cmd_addr(cmd_addr), .cmd_ready(cmd_ready), .w_data(w_data), .w_we(w_we),
        .w_ready(w_ready), .r_valid(r_valid), .r_data(r_data),
        .pad_ck(pad_ck), .pad_ck_n(pad_ck_n), .a(a), .ba(ba), .cke(cke),
        .cs_n(cs_n), .ras_n(ras_n), .cas_n(cas_n), .we_n(we_n),
        .dq_i(dq), .dq_o(dq_o), .dq_oe(dq_oe), .dm(dm),
        .dqs_o(dqs_o), .dqs_oe(dqs_oe)
    );

    integer offset_ps = 0;
    wire dram_dq_oe, dram_dqs_oe, dram_fault, dram_initialized;
    wire [7:0] dram_fault_code;
    ddr1_device_model dram (
        .ck(pad_ck), .cke(cke), .cs_n(cs_n), .ras_n(ras_n), .cas_n(cas_n),
        .we_n(we_n), .a(a), .ba(ba), .dq(dq), .dm(dm), .dqs(dqs),
        .read_offset_ps(offset_ps), .read_dq_oe(dram_dq_oe),
        .read_dqs_oe(dram_dqs_oe), .fault(dram_fault),
        .fault_code(dram_fault_code), .initialized(dram_initialized)
    );
    wire timing_fault;
    wire [3:0] timing_fault_code;
    ddr1_timing_checker pin_timing (
        .ck(pad_ck), .cke(cke), .cs_n(cs_n), .ras_n(ras_n), .cas_n(cas_n),
        .we_n(we_n), .ba(ba), .a10(a[10]), .fault(timing_fault),
        .fault_code(timing_fault_code)
    );

    integer pin_writes = 0, pin_reads = 0, pin_refreshes = 0;
    always @(posedge pad_ck) begin
        if (!rst && cke && !cs_n) begin
            case ({ras_n, cas_n, we_n})
                3'b100: pin_writes = pin_writes + 1;
                3'b101: pin_reads = pin_reads + 1;
                3'b001: pin_refreshes = pin_refreshes + 1;
                default: ;
            endcase
        end
    end
    always @(posedge dram_fault) begin
        #1;
        $fatal(1, "DDR1 train device fault code=%0d at %0t", dram_fault_code, $time);
    end
    always @(posedge timing_fault) begin
        #1;
        $fatal(1, "DDR1 train timing fault code=%0d at %0t", timing_fault_code, $time);
    end
    always @(dq_oe or dqs_oe or dram_dq_oe or dram_dqs_oe) begin
        if ((dq_oe && dram_dq_oe) || (dqs_oe && dram_dqs_oe))
            $fatal(1, "DDR1 train host/DRAM output overlap at %0t", $time);
    end

    integer cycles;
    reg cmd_sent, data_sent;
    initial begin
        repeat (8) @(posedge sys_clk);
        @(negedge sys_clk) rst = 1'b0;
        cycles = 0;
        while (init_done !== 1'b1 && cycles < 20000) begin
            @(negedge sys_clk);
            cycles = cycles + 1;
        end
        if (init_done !== 1'b1) $fatal(1, "DDR1 train init timeout");
        if (phy_ready !== 1'b0) $fatal(1, "phy_ready preceded training");

        @(negedge sys_clk);
        cmd_valid = 1'b1;
        cmd_we = 1'b1;
        cmd_addr = USER_ADDR;
        w_data = USER_PATTERN;
        w_we = 4'hf;
        cycles = 0;
        while (phy_ready !== 1'b1 && train_failed !== 1'b1 && cycles < 20000) begin
            if (cmd_ready !== 1'b0 || w_ready !== 1'b0 || r_valid !== 1'b0)
                $fatal(1, "Native traffic exposed while DDR1 training");
            @(negedge sys_clk);
            cycles = cycles + 1;
        end
        if (FAIL_MODE != 0) begin
            if (train_failed !== 1'b1 || phy_ready !== 1'b0)
                $fatal(1, "expected bounded DDR1 training failure");
            if (cmd_ready !== 1'b0 || w_ready !== 1'b0 || r_valid !== 1'b0)
                $fatal(1, "Native traffic exposed after training failure");
            if (read_error !== 1'b0 || dfi_error !== 1'b0)
                $fatal(1, "probe failure incorrectly became sticky PHY fault");
            if (pin_writes != 1 || tap_requests == 0)
                $fatal(1, "training failure wrote user data or skipped tap sweep");
            cmd_valid = 1'b0;
            $display("DDR1_TRAIN_PASS mode=fail taps=%0d cycles=%0d", tap_requests, cycles);
            $finish;
        end

        if (phy_ready !== 1'b1 || train_failed !== 1'b0 || train_busy !== 1'b0)
            $fatal(1, "DDR1 training did not reach ready");
        if (read_error !== 1'b0 || dfi_error !== 1'b0)
            $fatal(1, "successful probe left sticky PHY fault");
        if (pin_writes != 1 || tap_requests < 2)
            $fatal(1, "training scratch/tap activity missing writes=%0d taps=%0d",
                   pin_writes, tap_requests);

        cmd_sent = 1'b0;
        data_sent = 1'b0;
        cycles = 0;
        while (!cmd_sent || !data_sent) begin
            @(posedge sys_clk);
            if (!cmd_sent && cmd_ready === 1'b1) cmd_sent = 1'b1;
            if (!data_sent && w_ready === 1'b1) data_sent = 1'b1;
            #1;
            if (cmd_sent) cmd_valid = 1'b0;
            if (data_sent) w_we = 4'b0000;
            cycles = cycles + 1;
            if (cycles > 1000) $fatal(1, "DDR1 trained user write timeout");
        end

        @(negedge sys_clk);
        cmd_valid = 1'b1;
        cmd_we = 1'b0;
        cmd_addr = USER_ADDR;
        do @(posedge sys_clk); while (cmd_ready !== 1'b1);
        #1 cmd_valid = 1'b0;
        cycles = 0;
        while (r_valid !== 1'b1 && cycles < 1000) begin
            @(posedge sys_clk);
            cycles = cycles + 1;
        end
        if (r_valid !== 1'b1 || r_data !== USER_PATTERN)
            $fatal(1, "DDR1 trained Native read got=%h expected=%h", r_data, USER_PATTERN);
        if (pin_writes != 2 || pin_reads < 2 || pin_refreshes == 0)
            $fatal(1, "DDR1 training/user traffic accounting writes=%0d reads=%0d refresh=%0d",
                   pin_writes, pin_reads, pin_refreshes);
        $display("DDR1_TRAIN_PASS mode=active taps=%0d cycles=%0d", tap_requests, cycles);
        $finish;
    end
endmodule
`default_nettype wire
