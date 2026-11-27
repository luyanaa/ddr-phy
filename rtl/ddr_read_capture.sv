// SPDX-License-Identifier: Apache-2.0
// Per-byte source-synchronous DQS capture. Capture/clear_slot are timed
// controls from the SYS scheduler, not clocks and not asynchronous FIFO flags.
`default_nettype none
module ddr_read_capture #(
    parameter integer LANES = 1,
    parameter integer SLOTS = 4
) (
    input  wire                         rst,
    input  wire [LANES-1:0]              dqs_capture,
    input  wire [8*LANES-1:0]            dq_i,
    input  wire [SLOTS-1:0]              capture,
    input  wire [SLOTS-1:0]              clear_slot,
    input  wire [$clog2(SLOTS)-1:0]      return_slot,
    output wire [32*LANES-1:0]           word,
    output wire [LANES-1:0]              good
);
    reg [1:0] rise_count [0:LANES-1][0:SLOTS-1];
    reg [1:0] fall_count [0:LANES-1][0:SLOTS-1];
    reg [7:0] beat       [0:LANES-1][0:SLOTS-1][0:3];
    wire [SLOTS-1:0] slot_reset;

    genvar lane, slot;
    generate
        for (slot = 0; slot < SLOTS; slot = slot + 1) begin : g_slot_reset
            assign slot_reset[slot] = rst | clear_slot[slot];
        end
        for (lane = 0; lane < LANES; lane = lane + 1) begin : g_lane
            assign word[32*lane +: 32] = {
                beat[lane][return_slot][3], beat[lane][return_slot][2],
                beat[lane][return_slot][1], beat[lane][return_slot][0]
            };
            assign good[lane] = (rise_count[lane][return_slot] == 2'd2) &&
                                (fall_count[lane][return_slot] == 2'd2);

            for (slot = 0; slot < SLOTS; slot = slot + 1) begin : g_slot
                // Rising and falling edge counters are independent. A count
                // of three means the window had an extra edge and is invalid.
                always @(posedge dqs_capture[lane] or posedge slot_reset[slot]) begin
                    if (slot_reset[slot]) begin
                        rise_count[lane][slot] <= 2'd0;
                    end else if (capture[slot]) begin
                        case (rise_count[lane][slot])
                            2'd0: begin
                                beat[lane][slot][0] <= dq_i[8*lane +: 8];
                                rise_count[lane][slot] <= 2'd1;
                            end
                            2'd1: begin
                                beat[lane][slot][2] <= dq_i[8*lane +: 8];
                                rise_count[lane][slot] <= 2'd2;
                            end
                            default: rise_count[lane][slot] <= 2'd3;
                        endcase
                    end
                end

                always @(negedge dqs_capture[lane] or posedge slot_reset[slot]) begin
                    if (slot_reset[slot]) begin
                        fall_count[lane][slot] <= 2'd0;
                    end else if (capture[slot]) begin
                        case (fall_count[lane][slot])
                            2'd0: begin
                                beat[lane][slot][1] <= dq_i[8*lane +: 8];
                                fall_count[lane][slot] <= 2'd1;
                            end
                            2'd1: begin
                                beat[lane][slot][3] <= dq_i[8*lane +: 8];
                                fall_count[lane][slot] <= 2'd2;
                            end
                            default: fall_count[lane][slot] <= 2'd3;
                        endcase
                    end
                end
            end
        end
    endgenerate
endmodule
`default_nettype wire
