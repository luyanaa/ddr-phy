// SPDX-License-Identifier: Apache-2.0
// sdr_phy against the pin-level SDRAM model.
// One bank, one column: program the mode register, activate, write,
// mask that write, read it back. valid must rise on the CL+1 edge and
// not on the edges before it. A read of a closed bank must stick fault.

`default_nettype none

`ifndef CL
`define CL 2
`endif

module tb_sdram_model;
    localparam integer CL        = `CL;
    localparam integer DATA_BITS = 8;
    localparam integer ADDR_BITS = 13;
    localparam integer BANK_BITS = 2;
    localparam integer ROW_BITS  = 4;
    localparam integer COL_BITS  = 4;

    reg                          clk;
    reg                          rst;
    reg  [ADDR_BITS-1:0]         dfi_address;
    reg  [BANK_BITS-1:0]         dfi_bank;
    reg                          dfi_ras_n;
    reg                          dfi_cas_n;
    reg                          dfi_we_n;
    reg                          dfi_cs_n;
    reg                          dfi_cke;
    reg                          dfi_odt;
    reg                          dfi_reset_n;
    reg                          dfi_act_n;
    reg  [DATA_BITS-1:0]         dfi_wrdata;
    reg                          dfi_wrdata_en;
    reg                          dfi_wrdata_mask;
    reg                          dfi_rddata_en;
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
    integer wait_n;
    integer saw_valid;

    `define CHECK(cond) \
        if (!(cond)) begin \
            $display("FAIL line %0d: %s", `__LINE__, `"cond`"); \
            errors = errors + 1; \
        end

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

    task idle;
        begin
            dfi_address     = {ADDR_BITS{1'b0}};
            dfi_bank        = {BANK_BITS{1'b0}};
            dfi_ras_n       = 1'b1;
            dfi_cas_n       = 1'b1;
            dfi_we_n        = 1'b1;
            dfi_cs_n        = 1'b1;
            dfi_wrdata_en   = 1'b0;
            dfi_rddata_en   = 1'b0;
            dfi_wrdata_mask = 1'b0;
        end
    endtask

    // Present `setup` through the negedge, then one launching posedge.
    task step;
        begin
            @(negedge clk);
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        errors = 0;
        rst = 1'b1;
        dfi_cke = 1'b0;
        dfi_odt = 1'b0;
        dfi_reset_n = 1'b1;
        dfi_act_n = 1'b1;
        dfi_wrdata = 8'h00;
        idle();

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        dfi_cke = 1'b1;
        step();
        step();
        `CHECK(fault === 1'b0)

        // PRECHARGE all.
        dfi_cs_n = 1'b0;
        dfi_ras_n = 1'b0;
        dfi_cas_n = 1'b1;
        dfi_we_n = 1'b0;
        dfi_address = 13'h0400;
        step();
        idle();
        step();

        // Two refreshes.
        dfi_cs_n = 1'b0;
        dfi_ras_n = 1'b0;
        dfi_cas_n = 1'b0;
        dfi_we_n = 1'b1;
        step();
        step();
        idle();
        step();

        // MRS. CL2 -> A=0x20, CL3 -> A=0x30. BL=1, sequential.
        dfi_cs_n = 1'b0;
        dfi_ras_n = 1'b0;
        dfi_cas_n = 1'b0;
        dfi_we_n = 1'b0;
        dfi_address = (CL == 2) ? 13'h0020 : 13'h0030;
        step();
        idle();
        step();
        `CHECK(fault === 1'b0)

        // ACT bank 0, row 1.
        dfi_cs_n = 1'b0;
        dfi_ras_n = 1'b0;
        dfi_cas_n = 1'b1;
        dfi_we_n = 1'b1;
        dfi_address = 13'h0001;
        dfi_bank = 2'd0;
        step();
        idle();
        step();

        // WRITE column 3, 0xA5.
        dfi_cs_n = 1'b0;
        dfi_ras_n = 1'b1;
        dfi_cas_n = 1'b0;
        dfi_we_n = 1'b0;
        dfi_address = 13'h0003;
        dfi_wrdata = 8'hA5;
        dfi_wrdata_en = 1'b1;
        dfi_wrdata_mask = 1'b0;
        step();
        idle();
        step();

        // Masked write of 0xFF must leave 0xA5 in place.
        dfi_cs_n = 1'b0;
        dfi_ras_n = 1'b1;
        dfi_cas_n = 1'b0;
        dfi_we_n = 1'b0;
        dfi_address = 13'h0003;
        dfi_wrdata = 8'hFF;
        dfi_wrdata_en = 1'b1;
        dfi_wrdata_mask = 1'b1;
        step();
        idle();
        step();
        `CHECK(fault === 1'b0)

        // READ column 3. The command register adds one cycle to the
        // SDRAM's CAS latency, so valid is CL+1 edges after the DFI READ.
        dfi_cs_n = 1'b0;
        dfi_ras_n = 1'b1;
        dfi_cas_n = 1'b0;
        dfi_we_n = 1'b1;
        dfi_address = 13'h0003;
        dfi_rddata_en = 1'b1;
        step();
        `CHECK(dfi_rddata_valid === 1'b0)
        idle();

        saw_valid = 0;
        for (wait_n = 1; wait_n <= CL + 4; wait_n = wait_n + 1) begin
            step();
            if (dfi_rddata_valid) begin
                saw_valid = saw_valid + 1;
                `CHECK(wait_n == CL + 1)
                `CHECK(dfi_rddata === 8'hA5)
            end
        end
        `CHECK(saw_valid == 1)
        `CHECK(fault === 1'b0)

        // Close the bank, then read it. The model must flag that.
        dfi_cs_n = 1'b0;
        dfi_ras_n = 1'b0;
        dfi_cas_n = 1'b1;
        dfi_we_n = 1'b0;
        dfi_address = 13'h0400;
        step();
        idle();
        step();
        dfi_cs_n = 1'b0;
        dfi_ras_n = 1'b1;
        dfi_cas_n = 1'b0;
        dfi_we_n = 1'b1;
        dfi_address = 13'h0003;
        step();
        idle();
        step();
        step();
        `CHECK(fault === 1'b1)
        `CHECK(fault_code === 3'd3)

        if (errors == 0) begin
            $display("PASS model CL=%0d", CL);
            $finish;
        end else begin
            $display("FAIL model CL=%0d errors=%0d fault_code=%0d", CL, errors, fault_code);
            $fatal(1);
        end
    end

    initial begin
        #20000;
        $display("FAIL model timeout");
        $fatal(1);
    end
endmodule

`default_nettype wire
