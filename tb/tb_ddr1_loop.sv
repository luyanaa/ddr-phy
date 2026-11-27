// SPDX-License-Identifier: Apache-2.0
`timescale 1ps/1ps
`include "ddr1_timing.vh"
`default_nettype none
module tb_ddr1_loop #(
    parameter integer READ_DQS_JITTER_PS = 0,
    parameter integer READ_DQ_SKEW_PS = 0,
    parameter integer READ_SSO_PS = 0
);
    localparam integer CK_PS = `DDR1_TCK_PS;
    localparam integer STREAM = 16;
    localparam [22:0] BANK1 = 23'h000100, ROW1 = 23'h000400;
    reg ck = 0, sys_clk = 0, rst = 0;
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
    integer offset_ps = 0;
    wire init_done;

    wire pad_ck, cke, cs_n, ras_n, cas_n, we_n, dm;
    wire [12:0] a;
    wire [1:0] ba;
    wire [7:0] dq_o;
    wire dq_oe, dqs_o, dqs_oe, dqs_capture, read_error, dfi_error;
    tri [7:0] dq;
    tri dqs;
    assign dq = dq_oe ? dq_o : 8'bz;
    assign dqs = dqs_oe ? dqs_o : 1'bz;
    assign #(CK_PS/4) dqs_capture = (dqs === 1'b1);

    ddr1_top dut (
        .sys_clk(sys_clk), .ck(ck), .ck90(ck90), .rst(rst), .init_done(init_done),
        .cmd_valid(cmd_valid), .cmd_ready(cmd_ready), .cmd_we(cmd_we), .cmd_addr(cmd_addr),
        .w_ready(w_ready), .w_data(w_data), .w_we(w_we),
        .r_valid(r_valid), .r_data(r_data),
        .pad_ck(pad_ck), .pad_ck_n(), .a(a), .ba(ba),
        .cke(cke), .cs_n(cs_n), .ras_n(ras_n), .cas_n(cas_n), .we_n(we_n),
        .dq_i(dq), .dq_o(dq_o), .dq_oe(dq_oe), .dm(dm), .dqs_o(dqs_o), .dqs_oe(dqs_oe),
        .dqs_capture(dqs_capture), .read_error(read_error), .dfi_error(dfi_error)
    );

    wire dram_dq_oe, dram_dqs_oe, dram_fault, dram_initialized;
    wire [7:0] dram_fault_code;
    ddr1_device_model #(
        .READ_DQS_JITTER_PS(READ_DQS_JITTER_PS),
        .READ_DQ_SKEW_PS(READ_DQ_SKEW_PS),
        .READ_SSO_PS(READ_SSO_PS)
    ) dram (
        .ck(pad_ck), .cke(cke), .cs_n(cs_n), .ras_n(ras_n), .cas_n(cas_n),
        .we_n(we_n), .a(a), .ba(ba), .dq(dq), .dm(dm), .dqs(dqs), .read_offset_ps(offset_ps),
        .read_dq_oe(dram_dq_oe), .read_dqs_oe(dram_dqs_oe),
        .fault(dram_fault), .fault_code(dram_fault_code), .initialized(dram_initialized)
    );
    wire timing_fault;
    wire [3:0] timing_fault_code;
    ddr1_timing_checker pin_timing (
        .ck(pad_ck), .cke(cke), .cs_n(cs_n), .ras_n(ras_n), .cas_n(cas_n),
        .we_n(we_n), .ba(ba), .a10(a[10]), .fault(timing_fault), .fault_code(timing_fault_code)
    );
    always @(posedge timing_fault) begin
        #1;
        $fatal(1, "DDR1 pin timing fault code=%0d at %0t", timing_fault_code, $time);
    end
    always @(dq_oe or dqs_oe or dram_dq_oe or dram_dqs_oe) begin
        if ((dq_oe && dram_dq_oe) || (dqs_oe && dram_dqs_oe))
            $fatal(1, "DDR1 host and DRAM outputs overlap at %0t", $time);
    end
    always @(posedge dram_fault) begin
        #1;
        $fatal(1, "DDR1 device fault code=%0d at %0t", dram_fault_code, $time);
    end

    integer pin_writes = 0, pin_reads = 0, pin_refreshes = 0;
    integer adjacent_writes = 0, adjacent_reads = 0;
    time wr_at [0:63];
    time last_read_at = 0;
    always @(posedge pad_ck) begin
        if (!rst && cke && !cs_n) begin
            case ({ras_n, cas_n, we_n})
                3'b100: begin
                    if (pin_writes != 0 && $time - wr_at[pin_writes-1] == `DDR1_SYS_PS)
                        adjacent_writes = adjacent_writes + 1;
                    wr_at[pin_writes] = $time;
                    pin_writes = pin_writes + 1;
                end
                3'b101: begin
                    if (last_read_at != 0 && $time - last_read_at == `DDR1_SYS_PS)
                        adjacent_reads = adjacent_reads + 1;
                    last_read_at = $time;
                    pin_reads = pin_reads + 1;
                end
                3'b001: pin_refreshes = pin_refreshes + 1;
                default: ;
            endcase
        end
    end

    // Independent native-to-pin scoreboard. A matching TX/RX permutation
    // cannot pass: check every actual DQ/DM beat before trusting readback.
    reg [31:0] expected_writes [0:63];
    reg [3:0] expected_wes [0:63];
    integer native_writes = 0, pin_beats = 0;
    reg [3:0] read_due = 0;
    reg expected_valid;
    always @(posedge sys_clk) begin
        if (!rst && init_done === 1'b0 && {cmd_ready, w_ready, r_valid} !== 3'b000)
            $fatal(1, "DDR1 Native interface exposed before initialization at %0t", $time);
        if (init_done) begin
            if (w_ready) begin
                expected_writes[native_writes] = w_data;
                expected_wes[native_writes] = w_we;
                native_writes = native_writes + 1;
            end
            expected_valid = read_due[3];
            read_due = {read_due[2:0], dut.dfi_rddata_en[1]};
            #1;
            if (read_error !== 1'b0 || dfi_error !== 1'b0)
                $fatal(1, "PHY fault read=%b DFI=%b at %0t", read_error, dfi_error, $time);
            if (dut.dfi_rddata_valid !== {2{expected_valid}})
                $fatal(1, "DFI read deadline expected=%b got=%b at %0t",
                       expected_valid, dut.dfi_rddata_valid, $time);
        end
    end

    time dq_changed_at = 0, dqs_sample_at = 0, dqs_enabled_at = 0;
    reg previous_dqs = 1'bz, first_strobe = 0;
    always @(dq or dm or dq_oe) begin
        if (dqs_sample_at != 0 && $time - dqs_sample_at < `DDR1_T_DH_PS)
            $fatal(1, "DDR1 write tDH violated at %0t", $time);
        dq_changed_at = $time;
    end
    always @(posedge dqs_oe) begin
        dqs_enabled_at = $time;
        first_strobe = 1;
    end
    always @(negedge dqs_oe) begin
        if (!rst && dqs_sample_at != 0 &&
            (5*($time - dqs_sample_at) < 2*CK_PS || 5*($time - dqs_sample_at) > 3*CK_PS))
            $fatal(1, "DDR1 write postamble at %0t", $time);
    end
    always @(dqs) begin
        if (dqs_oe && ((previous_dqs === 1'b0 && dqs === 1'b1) ||
                       (previous_dqs === 1'b1 && dqs === 1'b0))) begin
            if (first_strobe && ($time - dqs_enabled_at < CK_PS/4))
                $fatal(1, "DDR1 write preamble at %0t", $time);
            first_strobe = 0;
            if (pin_beats / 4 >= native_writes || !dq_oe)
                $fatal(1, "extra write beat or missing DQ drive at %0t", $time);
            if ((pin_beats % 4 == 0) && (pin_beats / 4 >= pin_writes ||
                $time - wr_at[pin_beats/4] < 3*CK_PS/4 || $time - wr_at[pin_beats/4] > 5*CK_PS/4))
                $fatal(1, "DDR1 write tDQSS violation at %0t", $time);
            if (dq !== expected_writes[pin_beats/4][8*(pin_beats%4) +: 8] ||
                dm !== ~expected_wes[pin_beats/4][pin_beats%4])
                $fatal(1, "write beat %0d incorrect DQ=%h DM=%b", pin_beats, dq, dm);
            if ($time - dq_changed_at < `DDR1_T_DS_PS) $fatal(1, "DDR1 write tDS violated at %0t", $time);
            dqs_sample_at = $time;
            pin_beats = pin_beats + 1;
        end
        previous_dqs = dqs;
    end

    task automatic issue(input wr, input [22:0] word_addr);
        @(negedge sys_clk);
        cmd_valid = 1; cmd_we = wr; cmd_addr = word_addr;
        do @(posedge sys_clk); while (cmd_ready !== 1'b1);
        #1; cmd_valid = 0;
    endtask
    task automatic data_write(input [31:0] value, input [3:0] enables);
        @(negedge sys_clk);
        w_data = value; w_we = enables;
        do @(posedge sys_clk); while (w_ready !== 1'b1);
    endtask
    task automatic expect_read(input [31:0] value);
        do @(posedge sys_clk); while (r_valid !== 1'b1);
        if (r_data !== value) $fatal(1, "native read got=%h expected=%h at %0t", r_data, value, $time);
    endtask
    task automatic write_word(input [22:0] word_addr, input [31:0] value, input [3:0] enables);
        fork
            issue(1, word_addr);
            data_write(value, enables);
        join
    endtask
    task automatic read_word(input [22:0] word_addr, input [31:0] value);
        fork
            issue(0, word_addr);
            expect_read(value);
        join
    endtask
    function automatic [31:0] pattern(input integer index);
        reg [7:0] k;
        begin
            k = 8'(13*index + 3);
            pattern = {k ^ 8'h39, k ^ 8'hc0, ~k, k};
        end
    endfunction

    integer refresh_before, read_corner = 0;
    initial begin
        if ($value$plusargs("READ_CORNER=%d", read_corner) && (read_corner < -1 || read_corner > 1))
            $fatal(1, "READ_CORNER must be -1, 0 or 1");
        offset_ps = read_corner * `DDR1_T_DQSCK_PS;
        #20 rst = 1;
        repeat (3) @(negedge sys_clk);
        #1 rst = 0;
        cmd_valid = 1; // Neither the Native port nor the memory may accept this during power-up.
        repeat (4) @(negedge sys_clk);
        cmd_valid = 0;
        wait (init_done === 1'b1);
        if (dram_initialized !== 1'b1) $fatal(1, "DDR1 device did not accept initialization");

        // Same open row, sustained writes and reads through the native port.
        fork
            for (integer i = 0; i < STREAM; i = i + 1) issue(1, 23'(i));
            for (integer i = 0; i < STREAM; i = i + 1) data_write(pattern(i), 4'hf);
        join
        fork
            for (integer i = 0; i < STREAM; i = i + 1) issue(0, 23'(i));
            for (integer i = 0; i < STREAM; i = i + 1) expect_read(pattern(i));
        join

        // READ-to-WRITE turnaround, a byte mask crossing both DFI phases,
        // and separate row/bank locations whose low column bits all match.
        write_word(0, 32'h88776655, 4'b0101);
        read_word(0, (pattern(0) & 32'hff00ff00) | 32'h00770055);
        write_word(BANK1, 32'h12345678, 4'hf);
        write_word(ROW1, 32'hd6702143, 4'hf);
        read_word(BANK1, 32'h12345678);
        read_word(ROW1, 32'hd6702143);
        read_word(1, pattern(1));

        refresh_before = pin_refreshes;
        wait (pin_refreshes > refresh_before);
        read_word(0, (pattern(0) & 32'hff00ff00) | 32'h00770055);
        repeat (5) @(negedge sys_clk);
        if (pin_writes != STREAM + 3 || pin_beats != 4*pin_writes ||
            pin_reads != STREAM + 5 || adjacent_writes < 4 || adjacent_reads < 4)
            $fatal(1, "coverage: writes=%0d beats=%0d reads=%0d adjacent=%0d/%0d",
                   pin_writes, pin_beats, pin_reads, adjacent_writes, adjacent_reads);
        $display("DDR1_LOOP_PASS ck=%0dps offset=%0dps writes=%0d reads=%0d adjacent=%0d/%0d refresh=%0d",
                 CK_PS, offset_ps, pin_writes, pin_reads, adjacent_writes, adjacent_reads, pin_refreshes);
        $finish;
    end
    initial begin
        #1_000_000_000;
        $fatal(1, "DDR1 native loop timed out at %0t: writes=%0d beats=%0d reads=%0d",
               $time, pin_writes, pin_beats, pin_reads);
    end
endmodule
`default_nettype wire
