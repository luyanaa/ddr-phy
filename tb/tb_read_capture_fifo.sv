// SPDX-License-Identifier: Apache-2.0
// Read-capture FIFO with a nondefault response latency and a shifted
// cap_clk. The pin-level sustained-rate coverage is in tb_read_capture_phase.

`timescale 1ns/1ps
`default_nettype none

module tb_read_capture_fifo;
    localparam integer DB = 8;
    localparam integer LAT = 8;
    reg clk = 0, clk_early = 0, rst = 1;
    always #5 clk = ~clk;
    initial begin #3; forever #5 clk_early = ~clk_early; end
    reg cap_running = 1'b1;
    wire cap_clk = clk_early && cap_running;

    reg req = 0;
    reg [DB-1:0] dq = 0;
    wire [DB-1:0] rd;
    wire v, err;

    read_capture_cdc #(.DATA_BITS(DB), .LATENCY(LAT)) dut (
        .clk(clk), .rst(rst), .cap_clk(cap_clk),
        .capture_req(req), .dq_i(dq),
        .rddata(rd), .rddata_valid(v), .latency_error(err)
    );

    integer errors = 0;
    integer guard;
    reg [DB-1:0] got0, got1;

    task automatic issue(input [DB-1:0] data);
        begin
            @(negedge clk);
            dq = data;
            req = 1;
            @(negedge clk);
            req = 0;
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        @(negedge clk); rst = 0;

        issue(8'hA5);
        repeat (2) @(negedge clk);
        issue(8'h5A);

        guard = 0;
        while (!(v === 1'b1) && guard < 30) begin @(posedge clk); #1; guard = guard + 1; end
        got0 = rd;
        if (v !== 1'b1) begin $display("FAIL fifo: first valid missing"); errors = errors + 1; end
        @(posedge clk); #1;  // let the first valid pulse end

        guard = 0;
        while (!(v === 1'b1) && guard < 15) begin @(posedge clk); #1; guard = guard + 1; end
        got1 = rd;
        if (v !== 1'b1) begin $display("FAIL fifo: second valid missing"); errors = errors + 1; end

        if (got0 !== 8'hA5) begin $display("FAIL fifo: first=%h exp=A5", got0); errors = errors + 1; end
        if (got1 !== 8'h5A) begin $display("FAIL fifo: second=%h exp=5A", got1); errors = errors + 1; end
        if (err !== 1'b0) begin $display("FAIL fifo: latency_error"); errors = errors + 1; end

        // If a clock fault prevents a capture, do not return the last word
        // as a valid response at the next request's deadline.
        @(negedge clk_early);
        cap_running = 1'b0;
        issue(8'hC3);
        repeat (LAT - 1) @(posedge clk);
        #1;
        if (v !== 1'b0 || err !== 1'b0) $fatal(1, "FIFO fault reported before the deadline");
        @(posedge clk); #1;
        if (v !== 1'b0 || err !== 1'b1) $fatal(1, "missing capture not reported at the deadline");

        // The late word will enter the FIFO on resumption. It must not
        // be returned on a subsequent request's slot.
        @(negedge clk_early);
        cap_running = 1'b1;
        repeat (4) @(posedge clk); #1;
        issue(8'h96);
        repeat (LAT + 1) begin
            @(posedge clk); #1;
            if (v !== 1'b0 || err !== 1'b1) $fatal(1, "late capture was not quarantined");
        end

        $display("PASS read_capture_fifo first=%h second=%h", got0, got1);
        `ifdef MUTATE
        errors = errors + 1;
        $display("MUTATION: injected failure for exit-code test");
        `endif
        if (errors == 0) $display("PASS fifo");
        else             $fatal(1, "FAIL fifo errors=%0d", errors);
        $finish;
    end
endmodule

`default_nettype wire
