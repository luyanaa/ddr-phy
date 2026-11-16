// SPDX-License-Identifier: Apache-2.0
// Two-entry asynchronous read-capture FIFO with a fixed/parameterized
// read latency.
//
// cap_clk domain: capture_req is a one-cycle request in the clk domain,
// converted to a toggle and synchronized into cap_clk. On a detected
// request the FIFO writes dq_i and advances the Gray write pointer.
//
// clk domain: capture_req is also shifted through a LATENCY-deep pipe.
// When the oldest request reaches the end and the FIFO is not empty, the
// oldest entry is presented with rddata_valid for one cycle. If the pipe
// says data is due but the FIFO is empty, latency_error pulses.
//
// Depth 2 supports two outstanding captures; the current controller has
// one outstanding read, so this is an extension, not a requirement.
// The data bus is stable between capture and read; no bit-wise data
// synchronizer is used.

`default_nettype none
module read_capture_cdc #(
    parameter integer DATA_BITS = 8,
    parameter integer LATENCY   = 6
)(
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     cap_clk,
    input  wire                     capture_req, // one-cycle pulse in clk domain
    input  wire [DATA_BITS-1:0]     dq_i,
    output reg  [DATA_BITS-1:0]     rddata,
    output reg                      rddata_valid,
    output reg                      latency_error
);
    // request toggle in clk domain
    reg req_toggle;
    always @(posedge clk) begin
        if (rst) req_toggle <= 1'b0;
        else     req_toggle <= req_toggle ^ capture_req;
    end

    // fixed-latency request pipe
    reg [LATENCY-1:0] valid_pipe;
    wire lat_valid = valid_pipe[LATENCY-1];
    always @(posedge clk) begin
        if (rst) valid_pipe <= {LATENCY{1'b0}};
        else     valid_pipe <= {valid_pipe[LATENCY-2:0], capture_req};
    end

    // ---- cap_clk write side ----
    (* ASYNC_REG = "TRUE" *) reg req_meta, req_sync;
    reg req_seen;
    reg [1:0] wbin, wgray;
    reg [1:0] rbin, rgray;   // declared here: rgray is sampled by the cap side
    reg [1:0] rgray_sync0, rgray_sync1;
    reg [DATA_BITS-1:0] mem [0:1];
    reg overflow;

    wire [1:0] wbin_next = wbin + 2'd1;
    wire [1:0] wgray_next = {wbin_next[1], wbin_next[1] ^ wbin_next[0]};
    wire wfull = (wgray == {~rgray_sync1[1], ~rgray_sync1[0]});

    always @(posedge cap_clk) begin
        if (rst) begin
            req_meta     <= 1'b0;
            req_sync     <= 1'b0;
            req_seen     <= 1'b0;
            wbin         <= 2'd0;
            wgray        <= 2'd0;
            rgray_sync0  <= 2'd0;
            rgray_sync1  <= 2'd0;
            overflow     <= 1'b0;
            mem[0]       <= {DATA_BITS{1'b0}};
            mem[1]       <= {DATA_BITS{1'b0}};
        end else begin
            req_meta    <= req_toggle;
            req_sync    <= req_meta;
            rgray_sync0 <= rgray;
            rgray_sync1 <= rgray_sync0;
            if (req_sync != req_seen) begin
                req_seen <= req_sync;
                if (!wfull) begin
                    mem[wbin[0]] <= dq_i;
                    wbin         <= wbin_next;
                    wgray        <= wgray_next;
                end else begin
                    overflow <= 1'b1;
                end
            end
        end
    end

    // ---- clk read side ----
    (* ASYNC_REG = "TRUE" *) reg [1:0] wgray_meta, wgray_sync;
    wire empty = (rgray == wgray_sync);
    wire [1:0] rbin_next = rbin + 2'd1;
    wire [1:0] rgray_next = {rbin_next[1], rbin_next[1] ^ rbin_next[0]};

    always @(posedge clk) begin
        if (rst) begin
            wgray_meta <= 2'd0;
            wgray_sync <= 2'd0;
            rbin       <= 2'd0;
            rgray      <= 2'd0;
            rddata        <= {DATA_BITS{1'b0}};
            rddata_valid  <= 1'b0;
            latency_error <= 1'b0;
        end else begin
            wgray_meta <= wgray;
            wgray_sync <= wgray_meta;
            rddata_valid  <= 1'b0;
            latency_error <= 1'b0;
            if (lat_valid) begin
                if (!empty) begin
                    rddata       <= mem[rbin[0]];
                    rddata_valid <= 1'b1;
                    rbin         <= rbin_next;
                    rgray        <= rgray_next;
                end else begin
                    latency_error <= 1'b1;
                end
            end
        end
    end

    wire _unused = &{1'b0, overflow, LATENCY, DATA_BITS};
endmodule
`default_nettype wire
