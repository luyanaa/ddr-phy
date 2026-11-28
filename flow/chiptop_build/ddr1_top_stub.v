// Blackbox port declaration for the hardened ddr1_top macro (P&R only).
module ddr1_top (
    input  wire        sys_clk, ck, ck90, rst,
    input  wire [0:0]  dqs_capture,
    output wire        init_done, read_error, dfi_error,
    output wire        phy_ready, train_busy, train_failed,
    input  wire [0:0]  dqs_tap_ready,
    output wire [0:0]  dqs_tap_valid,
    output wire [3:0]  dqs_tap_value,
    input  wire        cmd_valid, cmd_we,
    input  wire [22:0] cmd_addr,
    output wire        cmd_ready,
    input  wire [31:0] w_data,
    input  wire [3:0]  w_we,
    output wire        w_ready,
    output wire        r_valid,
    output wire [31:0] r_data,
    output wire        pad_ck, pad_ck_n,
    output wire [12:0] a,
    output wire [1:0]  ba,
    output wire        cke, cs_n, ras_n, cas_n, we_n,
    input  wire [7:0]  dq_i,
    output wire [7:0]  dq_o,
    output wire        dq_oe, dm, dqs_o, dqs_oe
);
endmodule
