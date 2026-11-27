// SPDX-License-Identifier: Apache-2.0
`timescale 1ps/1ps
`default_nettype none
module tb_ddr_dqs_delay_adpll;
    reg sys_clk = 0;
    always #5000 sys_clk = ~sys_clk;
    reg rst = 1, update_idle = 0;
    reg [1:0] dqs_in = 0, tap_valid = 0;
    reg [3:0] tap_value = 0;
    wire [1:0] dqs_capture, tap_ready;

    ddr_dqs_delay_adpll #(
        .LANES(2), .TAP_BITS(2), .FIRST_STAGE(1), .STEP_CELLS(3), .SETTLE_CYCLES(3)
    ) dut (
        .sys_clk(sys_clk), .rst(rst), .update_idle(update_idle),
        .dqs_in(dqs_in), .dqs_capture(dqs_capture),
        .tap_valid(tap_valid), .tap_value(tap_value), .tap_ready(tap_ready)
    );

    task automatic expect_ready(input [1:0] expected);
        #1;
        if (tap_ready !== expected)
            $fatal(1, "ready=%b expected=%b at %0t", tap_ready, expected, $time);
    endtask

    task automatic tick(input [1:0] expected);
        @(posedge sys_clk);
        expect_ready(expected);
    endtask

    task automatic check_edges(input bit rising, input time delay0, delay1);
        time start;
        start = $time + 1;
        fork
            begin
                @(dqs_capture[0]);
                if (dqs_capture[0] !== rising || $time != start + delay0)
                    $fatal(1, "lane 0: got %b at %0t, expected %b at %0t",
                           dqs_capture[0], $time, rising, start + delay0);
            end
            begin
                @(dqs_capture[1]);
                if (dqs_capture[1] !== rising || $time != start + 37 + delay1)
                    $fatal(1, "lane 1: got %b at %0t, expected %b at %0t",
                           dqs_capture[1], $time, rising, start + 37 + delay1);
            end
            begin
                #1 dqs_in[0] = rising;
                #37 dqs_in[1] = rising;
            end
        join
    endtask

    initial begin
        #250000;
        $fatal(1, "timed out waiting for delayed edges or acknowledgements");
    end

    initial begin
        tick(2'b00);
        @(negedge sys_clk);
        rst = 0;
        tap_valid = 2'b01;
        tap_value = {2'd3, 2'd1};
        tick(2'b00); // active window: lane 0 must not apply
        check_edges(1, 100, 100);
        #2000;
        check_edges(0, 100, 100);

        @(negedge sys_clk);
        update_idle = 1;
        tick(2'b00); // apply lane 0 code 1
        @(negedge sys_clk);
        tap_valid = 2'b11;
        tick(2'b00); // apply lane 1 code 3 one cycle later
        tick(2'b00);
        tick(2'b01); // exactly three full periods after lane 0 application
        @(negedge sys_clk);
        expect_ready(2'b01); // still high ahead of a possible handshake edge
        update_idle = 0;
        expect_ready(2'b00);
        tick(2'b00); // lane 1 settles, but neither lane may acknowledge
        check_edges(1, 400, 1000);
        #2000;
        check_edges(0, 400, 1000);

        @(negedge sys_clk);
        update_idle = 1;
        expect_ready(2'b11);
        tick(2'b00); // both acknowledgements consumed, no repeated apply
        @(negedge sys_clk);
        update_idle = 0;
        tap_valid = 2'b01;
        tap_value = {2'd0, 2'd2};
        tick(2'b00);
        check_edges(1, 400, 1000); // new code blocked, other lane unaffected
        #2000;
        check_edges(0, 400, 1000);

        @(negedge sys_clk);
        update_idle = 1;
        tick(2'b00);
        tick(2'b00);
        tick(2'b00);
        tick(2'b01);
        tick(2'b00);
        tap_valid = 2'b00;
        update_idle = 0;
        check_edges(1, 700, 1000);
        #2000;
        check_edges(0, 700, 1000);
        $display("DDR_DQS_DELAY_ADPLL_PASS");
        $finish;
    end
endmodule

// Bench-only, deliberately fixed 100 ps per upstream chain stage. This
// exposes tap selection in event simulation and is not a PDK timing model.
module FINE_DELAY_CELL(inout wire VDD, VSS, input wire MUX, IN, output wire OUT);
    assign #100 OUT = IN;
endmodule
`default_nettype wire
