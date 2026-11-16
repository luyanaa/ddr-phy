// SPDX-License-Identifier: Apache-2.0
// Closes sdr_ctrl -> sdr_phy -> the pin-level SDR model and back.
// The controller inserts tRCD, tRP and tRFC as idle cycles. The model does
// not check those times; it only flags an illegal command order on fault.
// A passing run is not a datasheet timing check and not a pad check.

`default_nettype none

`ifndef CL
`define CL 2
`endif

module tb_sdr_loop;
    localparam integer CL        = `CL;
    localparam integer DATA_BITS = 8;
    localparam integer ADDR_BITS = 13;
    localparam integer BANK_BITS = 2;
    localparam integer ROW_BITS  = 4;
    localparam integer COL_BITS  = 4;
    localparam integer T_RCD     = 2;
    localparam integer T_RP      = 2;
    localparam integer T_RFC     = 4;
    localparam integer USER_BITS = COL_BITS + ROW_BITS + BANK_BITS;

    reg                          clk;
    reg                          rst;
    reg                          user_valid;
    wire                         user_ready;
    reg                          user_we;
    reg  [USER_BITS-1:0]         user_addr;
    reg  [DATA_BITS-1:0]         user_wdata;
    wire [DATA_BITS-1:0]         user_rdata;
    wire                         user_rvalid;

    wire [ADDR_BITS-1:0]         dfi_address;
    wire [BANK_BITS-1:0]         dfi_bank;
    wire                         dfi_ras_n;
    wire                         dfi_cas_n;
    wire                         dfi_we_n;
    wire                         dfi_cs_n;
    wire                         dfi_cke;
    wire                         dfi_odt;
    wire                         dfi_reset_n;
    wire                         dfi_act_n;
    wire [DATA_BITS-1:0]         dfi_wrdata;
    wire                         dfi_wrdata_en;
    wire                         dfi_wrdata_mask;
    wire                         dfi_rddata_en;
    wire [DATA_BITS-1:0]         dfi_rddata;
    wire                         dfi_rddata_valid;

    wire [ADDR_BITS-1:0]         a;
    wire [BANK_BITS-1:0]         ba;
    wire                         ras_n;
    wire                         cas_n;
    wire                         we_n;
    wire                         cs_n;
    wire                         cke;
    wire                         dm;
    wire [DATA_BITS-1:0]         dq_o;
    wire                         dq_oe;
    wire [DATA_BITS-1:0]         dq_i;
    wire                         ck;
    wire [DATA_BITS-1:0]         dq;
    wire                         fault;
    wire [2:0]                   fault_code;

    integer errors;
    integer guard;

    `define CHECK(cond) \
        if (!(cond)) begin \
            $display("FAIL line %0d: %s", `__LINE__, `"cond`"); \
            errors = errors + 1; \
        end

    sdr_ctrl #(
        .ADDR_BITS(ADDR_BITS),
        .BANK_BITS(BANK_BITS),
        .DATA_BITS(DATA_BITS),
        .ROW_BITS(ROW_BITS),
        .COL_BITS(COL_BITS),
        .CL(CL),
        .T_RCD(T_RCD),
        .T_RP(T_RP),
        .T_RFC(T_RFC)
    ) ctrl (
        .clk(clk),
        .rst(rst),
        .user_valid(user_valid),
        .user_ready(user_ready),
        .user_we(user_we),
        .user_addr(user_addr),
        .user_wdata(user_wdata),
        .user_wmask(1'b0),
        .user_rdata(user_rdata),
        .user_rvalid(user_rvalid),
        .dfi_address(dfi_address),
        .dfi_bank(dfi_bank),
        .dfi_ras_n(dfi_ras_n),
        .dfi_cas_n(dfi_cas_n),
        .dfi_we_n(dfi_we_n),
        .dfi_cs_n(dfi_cs_n),
        .dfi_cke(dfi_cke),
        .dfi_odt(dfi_odt),
        .dfi_reset_n(dfi_reset_n),
        .dfi_act_n(dfi_act_n),
        .dfi_wrdata(dfi_wrdata),
        .dfi_wrdata_en(dfi_wrdata_en),
        .dfi_wrdata_mask(dfi_wrdata_mask),
        .dfi_rddata_en(dfi_rddata_en),
        .dfi_rddata(dfi_rddata),
        .dfi_rddata_valid(dfi_rddata_valid),
        .phy_turnaround_busy(1'b0)
    );

    sdr_phy #(
        .ADDR_BITS(ADDR_BITS),
        .BANK_BITS(BANK_BITS),
        .DATA_BITS(DATA_BITS),
        .RANKS(1),
        .CL(CL)
    ) phy (
        .clk(clk),
        .rst(rst),
        .dfi_address(dfi_address),
        .dfi_bank(dfi_bank),
        .dfi_ras_n(dfi_ras_n),
        .dfi_cas_n(dfi_cas_n),
        .dfi_we_n(dfi_we_n),
        .dfi_cs_n(dfi_cs_n),
        .dfi_cke(dfi_cke),
        .dfi_odt(dfi_odt),
        .dfi_reset_n(dfi_reset_n),
        .dfi_act_n(dfi_act_n),
        .dfi_wrdata(dfi_wrdata),
        .dfi_wrdata_en(dfi_wrdata_en),
        .dfi_wrdata_mask(dfi_wrdata_mask),
        .dfi_rddata_en(dfi_rddata_en),
        .dfi_rddata(dfi_rddata),
        .dfi_rddata_valid(dfi_rddata_valid),
        .a(a),
        .ba(ba),
        .ras_n(ras_n),
        .cas_n(cas_n),
        .we_n(we_n),
        .cs_n(cs_n),
        .cke(cke),
        .dm(dm),
        .dq_o(dq_o),
        .dq_oe(dq_oe),
        .dq_i(dq_i),
        .ck(ck)
    );

    assign dq   = dq_oe ? dq_o : {DATA_BITS{1'bz}};
    assign dq_i = dq;

    sdram_model #(
        .ADDR_BITS(ADDR_BITS),
        .BANK_BITS(BANK_BITS),
        .DATA_BITS(DATA_BITS),
        .ROW_BITS(ROW_BITS),
        .COL_BITS(COL_BITS)
    ) dram (
        .ck(clk),
        .cke(cke),
        .cs_n(cs_n),
        .ras_n(ras_n),
        .cas_n(cas_n),
        .we_n(we_n),
        .ba(ba),
        .a(a),
        .dm(dm),
        .dq(dq),
        .fault(fault),
        .fault_code(fault_code)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    function automatic [USER_BITS-1:0] pack;
        input [BANK_BITS-1:0] bank;
        input [ROW_BITS-1:0]  row;
        input [COL_BITS-1:0]  col;
        begin
            pack = {bank, row, col};
        end
    endfunction

    task automatic write_word;
        input [BANK_BITS-1:0] bank;
        input [ROW_BITS-1:0]  row;
        input [COL_BITS-1:0]  col;
        input [DATA_BITS-1:0] data;
        begin
            @(negedge clk);
            user_we    = 1'b1;
            user_addr  = pack(bank, row, col);
            user_wdata = data;
            user_valid = 1'b1;
            guard = 0;
            while (!(user_ready === 1'b1) && guard < 40) begin
                @(posedge clk);
                #1;
                guard = guard + 1;
            end
            if (user_ready !== 1'b1) begin
                $display("FAIL write handshake b=%0d r=%0d c=%0d", bank, row, col);
                errors = errors + 1;
            end
            @(negedge clk);
            user_valid = 1'b0;
        end
    endtask

    task automatic read_word;
        input [BANK_BITS-1:0] bank;
        input [ROW_BITS-1:0]  row;
        input [COL_BITS-1:0]  col;
        input [DATA_BITS-1:0] expected;
        begin
            @(negedge clk);
            user_we    = 1'b0;
            user_addr  = pack(bank, row, col);
            user_valid = 1'b1;
            guard = 0;
            while (!(user_ready === 1'b1) && guard < 40) begin
                @(posedge clk);
                #1;
                guard = guard + 1;
            end
            if (user_ready !== 1'b1) begin
                $display("FAIL read handshake b=%0d r=%0d c=%0d", bank, row, col);
                errors = errors + 1;
            end
            @(negedge clk);
            user_valid = 1'b0;
            guard = 0;
            while (!(user_rvalid === 1'b1) && guard < 40) begin
                @(posedge clk);
                #1;
                guard = guard + 1;
            end
            if (user_rvalid !== 1'b1) begin
                $display("FAIL read timeout b=%0d r=%0d c=%0d", bank, row, col);
                errors = errors + 1;
            end else begin
                `CHECK(user_rdata === expected)
            end
        end
    endtask

    initial begin
        errors     = 0;
        rst        = 1'b1;
        user_valid = 1'b0;
        user_we    = 1'b0;
        user_addr  = {USER_BITS{1'b0}};
        user_wdata = {DATA_BITS{1'b0}};

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        guard = 0;
        while (!(user_ready === 1'b1) && guard < 400) begin
            @(posedge clk);
            #1;
            guard = guard + 1;
        end
        if (user_ready !== 1'b1) begin
            $display("FAIL init did not finish");
            $fatal(1);
        end
        `CHECK(fault === 1'b0)

        write_word(2'd0, 4'd1, 4'd3, 8'hA5);
        read_word (2'd0, 4'd1, 4'd3, 8'hA5);

        write_word(2'd0, 4'd1, 4'd4, 8'h5A);
        read_word (2'd0, 4'd1, 4'd3, 8'hA5);
        read_word (2'd0, 4'd1, 4'd4, 8'h5A);

        write_word(2'd1, 4'd2, 4'd1, 8'h3C);
        read_word (2'd1, 4'd2, 4'd1, 8'h3C);
        read_word (2'd0, 4'd1, 4'd3, 8'hA5);

        write_word(2'd0, 4'd2, 4'd3, 8'h77);
        read_word (2'd0, 4'd2, 4'd3, 8'h77);
        read_word (2'd0, 4'd1, 4'd3, 8'hA5);

        `CHECK(fault === 1'b0)

        if (errors == 0) begin
            $display("PASS loop CL=%0d", CL);
            $finish;
        end else begin
            $display("FAIL loop CL=%0d errors=%0d fault_code=%0d", CL, errors, fault_code);
            $fatal(1);
        end
    end

    initial begin
        #200000;
        $display("FAIL loop timeout");
        $fatal(1);
    end
endmodule

`default_nettype wire
