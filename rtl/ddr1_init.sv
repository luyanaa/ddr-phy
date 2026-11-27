// SPDX-License-Identifier: Apache-2.0
`default_nettype none
module ddr1_init (
    input  wire        sys_clk, rst,
    output wire        cke, cs_n,
    output reg  [2:0]  opcode,
    output reg  [1:0]  bank,
    output reg  [12:0] address,
    output reg         done
);
`include "ddr1_init_params.vh"
    localparam integer WAIT_BITS = $clog2(INIT_MAX_CYCLES + 1);
    localparam integer STEP_BITS = $clog2(INIT_STEPS + 1);
    reg [STEP_BITS-1:0] step;
    reg [WAIT_BITS-1:0] remaining, interval;
    reg selected;

    // Step 0 raises CKE with DESELECT, after the cold power-up interval. For a
    // step with interval N the command occupies one sys_clk when the counter
    // hits zero, followed by N full idle cycles before the next command.
    // Every selected command is presented in phase 0 for exactly one cycle.
    assign cke = !rst && (step != 0 || remaining == 0);
    assign cs_n = rst || !selected || remaining != 0;
    always @* begin
        {selected, opcode, bank, address, interval} = {1'b0, 3'b111, 15'd0, WAIT_BITS'(1)};
        case (step)
`include "ddr1_init_steps.vh"
            default: ;
        endcase
    end

    always @(posedge sys_clk or posedge rst) begin
        if (rst) begin
            step <= '0;
            remaining <= WAIT_BITS'(INIT_POWERUP_CYCLES);
            done <= 1'b0;
        end else if (remaining != 0) begin
            remaining <= remaining - 1'b1;
        end else if (step == STEP_BITS'(INIT_STEPS)) begin
            done <= 1'b1;
        end else begin
            step <= step + 1'b1;
            remaining <= interval;
        end
    end
endmodule
`default_nettype wire
