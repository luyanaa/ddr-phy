// SPDX-License-Identifier: Apache-2.0
// Cycle-accurate check of sdr_phy against the GENSDRPHY contract.
// Drive DFI on negedge. Pads update on the following posedge.
// A read enables rddata_en on the same edge as the READ command.
// dfi_rddata_valid is high CL+1 edges later, with dfi_rddata equal to
// the dq_i sampled on that edge.

`default_nettype none

`ifndef CL
`define CL 2
`endif
`ifndef DATA_BITS
`define DATA_BITS 8
`endif

module tb_sdr_phy;
    localparam integer CL        = `CL;
    localparam integer DATA_BITS = `DATA_BITS;
    localparam integer ADDR_BITS = 13;
    localparam integer BANK_BITS = 2;
    localparam integer DM_BITS   = DATA_BITS / 8;
    localparam integer READ_LATENCY = CL + 2;  // P1-3 path B

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
    reg  [DM_BITS-1:0]           dfi_wrdata_mask;
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
    wire [DM_BITS-1:0]           dm;
    wire [DATA_BITS-1:0]         dq_o;
    wire                         dq_oe;
    reg  [DATA_BITS-1:0]         dq_i;
    wire                         ck;

    integer errors;
    integer k;

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
    ) dut (
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

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task idle_dfi;
        begin
            dfi_address     = {ADDR_BITS{1'b0}};
            dfi_bank        = {BANK_BITS{1'b0}};
            dfi_ras_n       = 1'b1;
            dfi_cas_n       = 1'b1;
            dfi_we_n        = 1'b1;
            dfi_cs_n        = 1'b1;
            dfi_wrdata_en   = 1'b0;
            dfi_rddata_en   = 1'b0;
            dfi_wrdata_mask = {DM_BITS{1'b0}};
        end
    endtask

    task check_nop_pads;
        begin
            // P1-3 path B: dq_oe/dm are launched on the falling edge, so
            // sample after the negedge before declaring the pads idle.
            @(negedge clk);
            #1;
            `CHECK(cs_n === 1'b1)
            `CHECK(ras_n === 1'b1)
            `CHECK(cas_n === 1'b1)
            `CHECK(we_n === 1'b1)
            `CHECK(dq_oe === 1'b0)
            `CHECK(dm === {DM_BITS{1'b0}})
            `CHECK(dfi_rddata_valid === 1'b0)
        end
    endtask

    wire [DATA_BITS-1:0] wr_pat  = 16'hBEEF;
    wire [DATA_BITS-1:0] rd_pat  = 16'h1234;
    wire [DM_BITS-1:0]   wr_mask = 2'b01;

    initial begin
        errors = 0;
        rst = 1'b1;
        dq_i = {DATA_BITS{1'b0}};
        dfi_cke = 1'b0;
        dfi_odt = 1'b0;
        dfi_reset_n = 1'b0;
        dfi_act_n = 1'b0;
        dfi_wrdata = {DATA_BITS{1'b1}};
        idle_dfi();
        // Hostile DFI during reset must not reach the pads.
        dfi_cs_n = 1'b0;
        dfi_ras_n = 1'b0;
        dfi_cas_n = 1'b0;
        dfi_we_n = 1'b0;
        dfi_wrdata_en = 1'b1;

        repeat (3) @(posedge clk);
        #1;
        check_nop_pads();
        `CHECK(cke === 1'b0)
        `CHECK(ck === clk)

        @(negedge clk);
        rst = 1'b0;
        idle_dfi();
        dfi_cke = 1'b1;
        dfi_odt = 1'b1;
        dfi_reset_n = 1'b0;
        dfi_act_n = 1'b0;
        @(posedge clk);
        #1;
        `CHECK(cke === 1'b1)
        `CHECK(ck === clk)
        check_nop_pads();

        // WRITE column 0x5A, bank 1. Mask only while the beat is driven.
        @(negedge clk);
        dfi_cs_n = 1'b0;
        dfi_ras_n = 1'b1;
        dfi_cas_n = 1'b0;
        dfi_we_n = 1'b0;
        dfi_address = 13'h005A;
        dfi_bank = 2'd1;
        dfi_wrdata = wr_pat;
        dfi_wrdata_mask = wr_mask;
        dfi_wrdata_en = 1'b1;
        @(posedge clk);
        #1;
        `CHECK(cs_n === 1'b0)
        `CHECK(ras_n === 1'b1)
        `CHECK(cas_n === 1'b0)
        `CHECK(we_n === 1'b0)
        `CHECK(a === 13'h005A)
        `CHECK(ba === 2'd1)
        `CHECK(cke === 1'b1)
        `CHECK(dq_oe === 1'b1)
        `CHECK(dq_o === wr_pat)
        `CHECK(dm === wr_mask)

        @(negedge clk);
        idle_dfi();
        dfi_wrdata_mask = {DM_BITS{1'b1}};
        @(posedge clk);
        #1;
        check_nop_pads();
        `CHECK(cke === 1'b1)

        // READ. valid is CL+1 edges after this enabling edge.
        // dq_i is junk until the sampling edge, and must not raise valid.
        @(negedge clk);
        dfi_cs_n = 1'b0;
        dfi_ras_n = 1'b1;
        dfi_cas_n = 1'b0;
        dfi_we_n = 1'b1;
        dfi_address = 13'h005A;
        dfi_bank = 2'd1;
        dfi_rddata_en = 1'b1;
        dq_i = {DATA_BITS{1'b1}};
        @(posedge clk);
        #1;
        `CHECK(cs_n === 1'b0)
        `CHECK(ras_n === 1'b1)
        `CHECK(cas_n === 1'b0)
        `CHECK(we_n === 1'b1)
        `CHECK(a === 13'h005A)
        `CHECK(ba === 2'd1)
        `CHECK(dq_oe === 1'b0)
        `CHECK(dfi_rddata_valid === 1'b0)

        @(negedge clk);
        idle_dfi();

        for (k = 1; k <= CL + 1; k = k + 1) begin
            dq_i = {DATA_BITS{1'b0}};
            @(posedge clk);
            #1;
            `CHECK(dfi_rddata_valid === 1'b0)
        end

        dq_i = rd_pat;
        @(posedge clk);
        #1;
        `CHECK(dfi_rddata_valid === 1'b1)
        `CHECK(dfi_rddata === rd_pat)

        dq_i = {DATA_BITS{1'b0}};
        @(posedge clk);
        #1;
        `CHECK(dfi_rddata_valid === 1'b0)

        if (errors == 0) begin
            $display("PASS CL=%0d DATA_BITS=%0d read_latency=%0d", CL, DATA_BITS, READ_LATENCY);
            $finish;
        end else begin
            $display("FAIL CL=%0d DATA_BITS=%0d errors=%0d", CL, DATA_BITS, errors);
            $fatal(1);
        end
    end

    initial begin
        #10000;
        $display("FAIL timeout");
        $fatal(1);
    end
endmodule

`default_nettype wire
