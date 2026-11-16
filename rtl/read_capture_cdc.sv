// SPDX-License-Identifier: Apache-2.0
// Single-entry read-capture CDC between cap_clk and the core clk.
//
// capture_req is a TOGGLE in the clk domain. It is synchronized into
// cap_clk (two flops); on a detected change the cap_clk domain samples
// dq_i into cap_data and toggles ack_toggle. The clk domain synchronizes
// ack_toggle and, on a change, presents cap_data with a one-cycle valid.
//
// This is a handshake for ONE outstanding read. It is not a FIFO: a second
// capture before the core consumes the first will overwrite cap_data. The
// current sdr_ctrl has one outstanding read (read_busy), so this matches
// today's DFI contract. Back-to-back/burst reads need the FIFO follow-up.
//
// The data bus is stable from capture until the next capture; the clk side
// samples it after the ack synchronizer, so no bit-wise synchronizer is
// used on the data. This is a source-synchronous hold, not a general
// asynchronous data crossing.

`default_nettype none
module read_capture_cdc #(
    parameter integer DATA_BITS = 8
)(
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     cap_clk,
    input  wire                     capture_req, // toggle in clk domain
    input  wire [DATA_BITS-1:0]     dq_i,
    output reg  [DATA_BITS-1:0]     rddata,
    output reg                      rddata_valid
);
    // clk domain: request toggle
    reg req_toggle;
    always @(posedge clk) begin
        if (rst) req_toggle <= 1'b0;
        else     req_toggle <= req_toggle ^ capture_req;
    end

    // cap_clk domain: synchronize the request toggle, capture once per change.
    (* ASYNC_REG = "TRUE" *) reg req_meta, req_sync;
    reg req_seen;
    reg [DATA_BITS-1:0] cap_data;
    reg ack_toggle;
    always @(posedge cap_clk) begin
        if (rst) begin
            req_meta   <= 1'b0;
            req_sync   <= 1'b0;
            req_seen   <= 1'b0;
            cap_data   <= {DATA_BITS{1'b0}};
            ack_toggle <= 1'b0;
        end else begin
            req_meta <= req_toggle;
            req_sync <= req_meta;
            if (req_sync != req_seen) begin
                req_seen   <= req_sync;
                cap_data   <= dq_i;
                ack_toggle <= ack_toggle ^ 1'b1;
            end
        end
    end

    // clk domain: synchronize the ack toggle, present the held data.
    (* ASYNC_REG = "TRUE" *) reg ack_meta, ack_sync;
    reg ack_seen;
    always @(posedge clk) begin
        if (rst) begin
            ack_meta     <= 1'b0;
            ack_sync     <= 1'b0;
            ack_seen     <= 1'b0;
            rddata       <= {DATA_BITS{1'b0}};
            rddata_valid <= 1'b0;
        end else begin
            ack_meta     <= ack_toggle;
            ack_sync     <= ack_meta;
            rddata_valid <= 1'b0;
            if (ack_sync != ack_seen) begin
                ack_seen     <= ack_sync;
                rddata       <= cap_data;
                rddata_valid <= 1'b1;
            end
        end
    end
endmodule
`default_nettype wire
