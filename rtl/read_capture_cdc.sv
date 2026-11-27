// SPDX-License-Identifier: Apache-2.0
// SDR read capture into a Gray-pointer FIFO. cap_clk is a static 1:1 phase
// of clk. Its capture edge must lie inside the clk falling-edge boundaries
// with setup/hold margin; do not switch or stop it during traffic.
//
// For a request sampled at clk cycle N, launch its toggle on the following
// falling edge. Both leading and lagging cap_clk phases then see it first
// at the cycle N+1 cap edge, and capture DQ at N+3 after synchronization.
// The clk domain delivers the word at N+LATENCY in the FIFO and at
// N+LATENCY+1 on the registered rddata_valid output, in request order.

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

    // At most one request per cycle. Before the first dequeue has crossed
    // back to cap_clk, the writer can see up to LATENCY occupied slots.
    localparam integer ADDR_W = $clog2(LATENCY);
    localparam integer DEPTH = 1 << ADDR_W;
    localparam integer PTR_W = ADDR_W + 1;

    generate
        if (LATENCY < 6) begin : g_bad_latency
            read_capture_latency_must_be_at_least_six invalid();
        end
    endgenerate
    reg req_q, req_toggle;
    wire clk_n = ~clk;
    always @(posedge clk)
        req_q <= !rst && capture_req;

    always @(posedge clk_n) begin
        if (rst) req_toggle <= 1'b0;
        else     req_toggle <= req_toggle ^ req_q;
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
    reg [PTR_W-1:0] wbin, wgray, rbin, rgray;
    (* ASYNC_REG = "TRUE" *) reg [PTR_W-1:0] rgray_meta, rgray_sync;
    reg [DATA_BITS-1:0] mem [0:DEPTH-1];
    reg overflow;

    wire [PTR_W-1:0] wbin_next = wbin + 1'b1;
    wire [PTR_W-1:0] wgray_next = wbin_next ^ (wbin_next >> 1);
    wire wfull = (wgray == {~rgray_sync[PTR_W-1:PTR_W-2], rgray_sync[PTR_W-3:0]});
    wire capture = (req_sync != req_seen);

    always @(posedge cap_clk)
        if (!rst && capture && !wfull)
            mem[wbin[ADDR_W-1:0]] <= dq_i;

    always @(posedge cap_clk) begin
        if (rst) begin
            req_meta     <= 1'b0;
            req_sync     <= 1'b0;
            req_seen     <= 1'b0;
            wbin         <= '0;
            wgray        <= '0;
            rgray_meta   <= '0;
            rgray_sync   <= '0;
            overflow     <= 1'b0;
        end else begin
            req_meta    <= req_toggle;
            req_sync    <= req_meta;
            rgray_meta  <= rgray;
            rgray_sync  <= rgray_meta;
            if (capture) begin
                req_seen <= req_sync;
                if (!wfull) begin
                    wbin         <= wbin_next;
                    wgray        <= wgray_next;
                end else begin
                    overflow <= 1'b1;
                end
            end
        end
    end

    // ---- clk read side ----
    (* ASYNC_REG = "TRUE" *) reg [PTR_W-1:0] wgray_meta, wgray_sync;
    (* ASYNC_REG = "TRUE" *) reg overflow_meta, overflow_sync;
    wire empty = (rgray == wgray_sync);
    wire [PTR_W-1:0] rbin_next = rbin + 1'b1;
    wire [PTR_W-1:0] rgray_next = rbin_next ^ (rbin_next >> 1);

    always @(posedge clk) begin
        if (rst) begin
            wgray_meta    <= '0;
            wgray_sync    <= '0;
            overflow_meta <= 1'b0;
            overflow_sync <= 1'b0;
            rbin         <= '0;
            rgray        <= '0;
            rddata        <= {DATA_BITS{1'b0}};
            rddata_valid  <= 1'b0;
            latency_error <= 1'b0;
        end else begin
            wgray_meta <= wgray;
            wgray_sync <= wgray_meta;
            overflow_meta <= overflow;
            overflow_sync <= overflow_meta;
            rddata_valid  <= 1'b0;
            // After either domain loses a beat, future FIFO words cannot
            // be matched safely to requests until both sides are reset.
            if (overflow_sync || (lat_valid && empty)) begin
                latency_error <= 1'b1;
            end else if (lat_valid && !latency_error) begin
                rddata        <= mem[rbin[ADDR_W-1:0]];
                rddata_valid  <= 1'b1;
                rbin          <= rbin_next;
                rgray         <= rgray_next;
            end
        end
    end
endmodule
`default_nettype wire
