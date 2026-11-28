// SPDX-License-Identifier: Apache-2.0
// Copy of /grid/adpll_gen/src/ddr1_dqs_delay_line_phys.v for the ddr1_top
// regression bundle.  Keep in sync with the adpll_gen source; it is the
// repaired 128-tap DDR1 DQS line, not the old 16-cell PLL_DCDL_TAP_BUS_PHYS.
`timescale 1ps/1ps
`default_nettype none

module DDR1_DQS_DELAY_CELL_BEH #(
    parameter integer DLY_PS = 55
) (
    input  wire I,
    output wire O
);
    reg d;
    always @(I) d <= #(DLY_PS) I;
    assign O = d;
endmodule

module DDR1_DQS_DELAY_LINE_PHYS #(
    parameter integer NTAPS         = 128,
    parameter integer CELLS_PER_TAP = 2,
    parameter integer CELL_PS       = 35,
    parameter integer IMPL          = 0
) (
    input  wire             CLK_IN,
    output wire [NTAPS-1:0] TAP
);
    initial begin
        if (NTAPS < 2)         $error("NTAPS must be >= 2");
        if (CELLS_PER_TAP < 1) $error("CELLS_PER_TAP must be >= 1");
    end

    genvar g, c;
    generate
        if (IMPL == 0) begin : g_beh
            wire [NTAPS*CELLS_PER_TAP:0] node;
            assign node[0] = CLK_IN;
            for (g = 0; g < NTAPS; g = g + 1) begin : g_elem
                for (c = 0; c < CELLS_PER_TAP; c = c + 1) begin : g_cell
                    DDR1_DQS_DELAY_CELL_BEH #(.DLY_PS(CELL_PS)) u_cell (
                        .I(node[g*CELLS_PER_TAP + c]),
                        .O(node[g*CELLS_PER_TAP + c + 1])
                    );
                end
            end
            for (g = 0; g < NTAPS; g = g + 1) begin : g_tap
                assign TAP[g] = node[g*CELLS_PER_TAP];
            end
        end else begin : g_phys
            wire [NTAPS*CELLS_PER_TAP:0] node;
            assign node[0] = CLK_IN;
            for (g = 0; g < NTAPS*CELLS_PER_TAP; g = g + 1) begin : g_cell
                FINE_DELAY_CELL u_cell (
                    .MUX(1'b1), .IN(node[g]), .OUT(node[g+1])
                );
            end
            for (g = 0; g < NTAPS; g = g + 1) begin : g_tap
                assign TAP[g] = node[g*CELLS_PER_TAP];
            end
        end
    endgenerate
endmodule
`default_nettype wire
