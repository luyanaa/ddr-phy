// SPDX-License-Identifier: Apache-2.0
// 1:1 SDR controller for sdr_phy. Not LiteDRAM, and it does not instantiate
// LiteDRAM. Two contracts are copied from it:
//
//   * DFI phase 0 timing of GENSDRPHY (litedram/phy/gensdrphy.py):
//     write_latency 0, so the write data, enable and mask are presented on
//     the same cycle as the WRITE command; read_latency CL+1, so
//     dfi_rddata_en is asserted on the same cycle as the READ command and
//     dfi_rddata is sampled when dfi_rddata_valid rises. This module adds
//     no read-data delay of its own.
//   * SDR init order of get_sdr_phy_init_sequence (litedram/init.py) with
//     nphases=1, so BL=1 and the mode register is CL<<4. The 20000-cycle
//     CKE pause and the 200-cycle MRS pause are shortened; the command
//     order is not.
//
// One row stays open per bank. A request to a different row of that bank
// precharges, then activates. tRCD, tRP and tRFC are inserted as idle
// cycles, not checked against a datasheet.
//
// T_REFI = 0 (default) disables periodic refresh, preserving the original
// closed-loop tests. With T_REFI > 0 the controller closes all banks,
// issues AUTO REFRESH and waits tRFC every T_REFI sys clocks after init.
//
// phy_turnaround_busy (from dq_turnaround) blocks WRITE acceptance and
// WRITE issue; READ may proceed. This prevents the controller from issuing
// a WRITE whose DQ OE the PHY would then gate during the guard window.

`default_nettype none

module sdr_ctrl #(
    parameter integer ADDR_BITS = 13,
    parameter integer BANK_BITS = 2,
    parameter integer DATA_BITS = 8,
    parameter integer ROW_BITS  = 4,
    parameter integer COL_BITS  = 4,
    parameter integer CL        = 2,
    parameter integer T_RCD     = 2,
    parameter integer T_RP      = 2,
    parameter integer T_RFC     = 4,
    parameter integer T_REFI    = 0
) (
    input  wire                     clk,
    input  wire                     rst,

    input  wire                     user_valid,
    output reg                      user_ready,
    input  wire                     user_we,
    input  wire [COL_BITS+ROW_BITS+BANK_BITS-1:0] user_addr,
    input  wire [DATA_BITS-1:0]     user_wdata,
    input  wire [DATA_BITS/8-1:0]   user_wmask,
    output reg  [DATA_BITS-1:0]     user_rdata,
    output reg                      user_rvalid,

    output reg  [ADDR_BITS-1:0]     dfi_address,
    output reg  [BANK_BITS-1:0]     dfi_bank,
    output reg                      dfi_ras_n,
    output reg                      dfi_cas_n,
    output reg                      dfi_we_n,
    output reg                      dfi_cs_n,
    output reg                      dfi_cke,
    output wire                     dfi_odt,
    output wire                     dfi_reset_n,
    output wire                     dfi_act_n,
    output reg  [DATA_BITS-1:0]     dfi_wrdata,
    output reg                      dfi_wrdata_en,
    output reg  [DATA_BITS/8-1:0]     dfi_wrdata_mask,
    output reg                      dfi_rddata_en,
    input  wire [DATA_BITS-1:0]     dfi_rddata,
    input  wire                     dfi_rddata_valid,

    // From dq_turnaround: a WRITE must not be issued while the PHY is
    // still guarding a READ->WRITE turnaround. Reads may proceed.
    input  wire                     phy_turnaround_busy
);

    localparam integer BANKS     = 1 << BANK_BITS;
    localparam integer USER_BITS = COL_BITS + ROW_BITS + BANK_BITS;
    // get_sdr_phy_init_sequence waits 20000 cycles after CKE and 200 after
    // MRS. The behavioral model has no CKE timer, so the command order is
    // kept and the pauses are shortened to a length a test can run.
    localparam integer CKE_WAIT  = 8;
    localparam integer MRS_WAIT  = 4;
    localparam integer MR_VALUE  = CL << 4;
    localparam integer MR_RESET  = MR_VALUE | (1 << 8);

    localparam [3:0] S_CKE   = 4'd0;
    localparam [3:0] S_PRE1  = 4'd1;
    localparam [3:0] S_MRS1  = 4'd2;
    localparam [3:0] S_PRE2  = 4'd3;
    localparam [3:0] S_REF1  = 4'd4;
    localparam [3:0] S_REF2  = 4'd5;
    localparam [3:0] S_MRS2  = 4'd6;
    localparam [3:0] S_IDLE  = 4'd7;
    localparam [3:0] S_PRE   = 4'd8;
    localparam [3:0] S_ACT   = 4'd9;
    localparam [3:0] S_WAIT  = 4'd10;
    localparam [3:0] S_RFSH_PRE = 4'd11;
    localparam [3:0] S_RFSH_CMD = 4'd12;

    generate
        if (!(CL == 2 || CL == 3)) begin : g_bad_cl
            invalid_cl_parameter this_module_does_not_exist();
        end
        if (DATA_BITS % 8 != 0 || DATA_BITS < 8) begin : g_bad_dq
            invalid_data_width this_module_does_not_exist();
        end
        if (COL_BITS < 1 || COL_BITS > 10) begin : g_bad_col
            invalid_column_bits this_module_does_not_exist();
        end
        if (ROW_BITS < 1 || BANK_BITS < 1) begin : g_bad_geom
            invalid_geometry this_module_does_not_exist();
        end
        if (ADDR_BITS <= 10) begin : g_bad_addr
            invalid_address_bits this_module_does_not_exist();
        end
        if (T_RCD < 1 || T_RP < 1 || T_RFC < 1) begin : g_bad_timing
            invalid_timing_parameter this_module_does_not_exist();
        end
        if (T_REFI < 0) begin : g_bad_refi
            invalid_refi_parameter this_module_does_not_exist();
        end
    endgenerate

    assign dfi_odt     = 1'b0;
    assign dfi_reset_n = 1'b1;
    assign dfi_act_n   = 1'b1;

    reg [3:0]              state;
    reg [3:0]              wait_next;
    reg [7:0]              wait_n;
    reg                    init_done;
    reg                    read_busy;
    reg                    have_req;
    reg                    req_we;
    reg [BANK_BITS-1:0]    req_ba;
    reg [ROW_BITS-1:0]     req_row;
    reg [COL_BITS-1:0]     req_col;
    reg [DATA_BITS-1:0]    req_wdata;
    reg [DATA_BITS/8-1:0]  req_wmask;
    reg                    bank_open [0:BANKS-1];
    reg [ROW_BITS-1:0]     bank_row  [0:BANKS-1];
    reg [31:0]             ref_cnt;

    integer bi;

    wire [COL_BITS-1:0]  user_col  = user_addr[COL_BITS-1:0];
    wire [ROW_BITS-1:0]  user_row  = user_addr[COL_BITS +: ROW_BITS];
    wire [BANK_BITS-1:0] user_bank = user_addr[COL_BITS+ROW_BITS +: BANK_BITS];

    wire hit = bank_open[req_ba] && (bank_row[req_ba] == req_row);
    wire refresh_due = (T_REFI > 0) && init_done && (ref_cnt >= T_REFI);

    // Synchronous set, not a reset to zero. A reset value of 0 on ras_n,
    // cas_n, we_n and cs_n is an illegal command, not a NOP.
    always @(posedge clk) begin
        if (rst) begin
            state          <= S_CKE;
            wait_next      <= S_CKE;
            wait_n         <= 8'd0;
            init_done      <= 1'b0;
            read_busy      <= 1'b0;
            have_req       <= 1'b0;
            req_we         <= 1'b0;
            req_ba         <= {BANK_BITS{1'b0}};
            req_row        <= {ROW_BITS{1'b0}};
            req_col        <= {COL_BITS{1'b0}};
            req_wdata      <= {DATA_BITS{1'b0}};
            req_wmask      <= {(DATA_BITS/8){1'b0}};
            user_ready     <= 1'b0;
            user_rdata     <= {DATA_BITS{1'b0}};
            user_rvalid    <= 1'b0;
            dfi_address    <= {ADDR_BITS{1'b0}};
            dfi_bank       <= {BANK_BITS{1'b0}};
            dfi_ras_n      <= 1'b1;
            dfi_cas_n      <= 1'b1;
            dfi_we_n       <= 1'b1;
            dfi_cs_n       <= 1'b1;
            dfi_cke        <= 1'b0;
            dfi_wrdata     <= {DATA_BITS{1'b0}};
            dfi_wrdata_en  <= 1'b0;
            dfi_wrdata_mask<= {(DATA_BITS/8){1'b0}};
            dfi_rddata_en  <= 1'b0;
            ref_cnt        <= 32'd0;
            for (bi = 0; bi < BANKS; bi = bi + 1)
                bank_open[bi] <= 1'b0;
        end else begin
            // Default is a NOP with CKE held where init left it.
            dfi_address     <= {ADDR_BITS{1'b0}};
            dfi_bank        <= {BANK_BITS{1'b0}};
            dfi_ras_n       <= 1'b1;
            dfi_cas_n       <= 1'b1;
            dfi_we_n        <= 1'b1;
            dfi_cs_n        <= 1'b1;
            dfi_wrdata_en   <= 1'b0;
            dfi_wrdata_mask <= {(DATA_BITS/8){1'b0}};
            dfi_rddata_en   <= 1'b0;
            user_rvalid     <= 1'b0;

            if (init_done && T_REFI > 0)
                ref_cnt <= ref_cnt + 32'd1;

            if (dfi_rddata_valid) begin
                user_rdata <= dfi_rddata;
                user_rvalid<= 1'b1;
                read_busy  <= 1'b0;
            end

            // Accept one request while idle. The column command is the
            // cycle after this, or later if the row has to be opened.
            // ready stays high for the whole idle cycle so a request can
            // be presented without a combinational ready/valid loop.
            user_ready <= (state == S_IDLE) && init_done && !have_req &&
                            !read_busy && !refresh_due &&
                            (!user_we || !phy_turnaround_busy);
            if (init_done && !have_req && !read_busy && !refresh_due &&
                (!user_we || !phy_turnaround_busy) &&
                user_valid && state == S_IDLE) begin
                have_req  <= 1'b1;
                req_we    <= user_we;
                req_ba    <= user_bank;
                req_row   <= user_row;
                req_col   <= user_col;
                req_wdata <= user_wdata;
                req_wmask <= user_wmask;
            end

            case (state)
                S_CKE: begin
                    dfi_cke   <= 1'b1;
                    state     <= S_WAIT;
                    wait_next <= S_PRE1;
                    wait_n    <= CKE_WAIT[7:0];
                end
                S_PRE1: begin
                    dfi_cke            <= 1'b1;
                    dfi_cs_n           <= 1'b0;
                    dfi_ras_n          <= 1'b0;
                    dfi_we_n           <= 1'b0;
                    dfi_address[10]    <= 1'b1;
                    state              <= S_WAIT;
                    wait_next          <= S_MRS1;
                    wait_n             <= T_RP[7:0];
                end
                S_MRS1: begin
                    dfi_cke     <= 1'b1;
                    dfi_cs_n    <= 1'b0;
                    dfi_ras_n   <= 1'b0;
                    dfi_cas_n   <= 1'b0;
                    dfi_we_n    <= 1'b0;
                    dfi_address <= MR_RESET[ADDR_BITS-1:0];
                    state       <= S_WAIT;
                    wait_next   <= S_PRE2;
                    wait_n      <= MRS_WAIT[7:0];
                end
                S_PRE2: begin
                    dfi_cke         <= 1'b1;
                    dfi_cs_n        <= 1'b0;
                    dfi_ras_n       <= 1'b0;
                    dfi_we_n        <= 1'b0;
                    dfi_address[10] <= 1'b1;
                    state           <= S_WAIT;
                    wait_next       <= S_REF1;
                    wait_n          <= T_RP[7:0];
                end
                S_REF1: begin
                    dfi_cke   <= 1'b1;
                    dfi_cs_n  <= 1'b0;
                    dfi_ras_n <= 1'b0;
                    dfi_cas_n <= 1'b0;
                    state     <= S_WAIT;
                    wait_next <= S_REF2;
                    wait_n    <= T_RFC[7:0];
                end
                S_REF2: begin
                    dfi_cke   <= 1'b1;
                    dfi_cs_n  <= 1'b0;
                    dfi_ras_n <= 1'b0;
                    dfi_cas_n <= 1'b0;
                    state     <= S_WAIT;
                    wait_next <= S_MRS2;
                    wait_n    <= T_RFC[7:0];
                end
                S_MRS2: begin
                    dfi_cke     <= 1'b1;
                    dfi_cs_n    <= 1'b0;
                    dfi_ras_n   <= 1'b0;
                    dfi_cas_n   <= 1'b0;
                    dfi_we_n    <= 1'b0;
                    dfi_address <= MR_VALUE[ADDR_BITS-1:0];
                    state       <= S_WAIT;
                    wait_next   <= S_IDLE;
                    wait_n      <= MRS_WAIT[7:0];
                    init_done   <= 1'b1;
                end
                S_IDLE: begin
                    dfi_cke <= 1'b1;
                    if (refresh_due && !have_req && !read_busy) begin
                        state <= S_RFSH_PRE;
                    end else if (have_req && !read_busy &&
                                 (!req_we || !phy_turnaround_busy)) begin
                        if (!hit && bank_open[req_ba])
                            state <= S_PRE;
                        else if (!hit)
                            state <= S_ACT;
                        else begin
                            dfi_cs_n  <= 1'b0;
                            dfi_cas_n <= 1'b0;
                            dfi_bank  <= req_ba;
                            dfi_address <= {{(ADDR_BITS-COL_BITS){1'b0}}, req_col};
                            if (req_we) begin
                                dfi_we_n      <= 1'b0;
                                dfi_wrdata      <= req_wdata;
                                dfi_wrdata_en   <= 1'b1;
                                dfi_wrdata_mask <= req_wmask;
                            end else begin
                                dfi_rddata_en <= 1'b1;
                                read_busy     <= 1'b1;
                            end
                            have_req <= 1'b0;
                        end
                    end
                end
                S_RFSH_PRE: begin
                    // Close every bank before AUTO REFRESH: the SDRAM model
                    // raises REF_OPEN if any row is still active.
                    dfi_cke            <= 1'b1;
                    dfi_cs_n           <= 1'b0;
                    dfi_ras_n          <= 1'b0;
                    dfi_we_n           <= 1'b0;
                    dfi_address[10]    <= 1'b1;
                    for (bi = 0; bi < BANKS; bi = bi + 1)
                        bank_open[bi] <= 1'b0;
                    state     <= S_WAIT;
                    wait_next <= S_RFSH_CMD;
                    wait_n    <= T_RP[7:0];
                end
                S_RFSH_CMD: begin
                    dfi_cke   <= 1'b1;
                    dfi_cs_n  <= 1'b0;
                    dfi_ras_n <= 1'b0;
                    dfi_cas_n <= 1'b0;
                    ref_cnt   <= 32'd0;
                    state     <= S_WAIT;
                    wait_next <= S_IDLE;
                    wait_n    <= T_RFC[7:0];
                end
                S_PRE: begin
                    dfi_cke   <= 1'b1;
                    dfi_cs_n  <= 1'b0;
                    dfi_ras_n <= 1'b0;
                    dfi_we_n  <= 1'b0;
                    dfi_bank  <= req_ba;
                    bank_open[req_ba] <= 1'b0;
                    state     <= S_WAIT;
                    wait_next <= S_ACT;
                    wait_n    <= T_RP[7:0];
                end
                S_ACT: begin
                    dfi_cke     <= 1'b1;
                    dfi_cs_n    <= 1'b0;
                    dfi_ras_n   <= 1'b0;
                    dfi_bank    <= req_ba;
                    dfi_address <= {{(ADDR_BITS-ROW_BITS){1'b0}}, req_row};
                    bank_open[req_ba] <= 1'b1;
                    bank_row[req_ba]  <= req_row;
                    state     <= S_WAIT;
                    wait_next <= S_IDLE;
                    wait_n    <= T_RCD[7:0];
                end
                S_WAIT: begin
                    dfi_cke <= 1'b1;
                    if (wait_n <= 8'd1)
                        state <= wait_next;
                    else
                        wait_n <= wait_n - 8'd1;
                end
                default: state <= S_CKE;
            endcase
        end
    end

endmodule

`default_nettype wire
