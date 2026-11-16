// SPDX-License-Identifier: Apache-2.0
// Controller-side turnaround contract:
//   - a WRITE request is not accepted (user_ready low) while the PHY is busy
//   - no WRITE command reaches the DFI while busy
//   - after busy deasserts the write is accepted and issued once
//   - a READ may proceed while busy
// This is a controller unit test; dq_turnaround's OE gating is covered by
// tb_phy_top. Together they close the contract.

`default_nettype none

module tb_turnaround_ctrl;
    localparam integer DB = 8;
    localparam integer AB = 13;
    localparam integer BB = 2;
    localparam integer RB = 4;
    localparam integer CB = 4;
    localparam integer UB = CB + RB + BB;
    localparam integer T_RCD = 2;
    localparam integer T_RP  = 2;
    localparam integer T_RFC = 4;

    reg                 clk = 1'b0;
    reg                 rst = 1'b1;
    reg                 user_valid = 1'b0;
    wire                user_ready;
    reg                 user_we = 1'b0;
    reg  [UB-1:0]       user_addr = {UB{1'b0}};
    reg  [DB-1:0]       user_wdata = {DB{1'b0}};
    wire [DB-1:0]       user_rdata;
    wire                user_rvalid;
    wire [AB-1:0]       dfi_address;
    wire [BB-1:0]       dfi_bank;
    wire                dfi_ras_n, dfi_cas_n, dfi_we_n, dfi_cs_n, dfi_cke;
    wire                dfi_odt, dfi_reset_n, dfi_act_n;
    wire [DB-1:0]       dfi_wrdata;
    wire                dfi_wrdata_en;
    wire [DB/8-1:0]     dfi_wrdata_mask;
    wire                dfi_rddata_en;
    wire [DB-1:0]       dfi_rddata;
    wire                dfi_rddata_valid;
    reg                 phy_busy = 1'b0;

    integer errors = 0;
    integer guard;

    always #5 clk = ~clk;

    sdr_ctrl #(
        .ADDR_BITS(AB), .BANK_BITS(BB), .DATA_BITS(DB),
        .ROW_BITS(RB), .COL_BITS(CB), .CL(2),
        .T_RCD(T_RCD), .T_RP(T_RP), .T_RFC(T_RFC)
    ) dut (
        .clk(clk), .rst(rst),
        .user_valid(user_valid), .user_ready(user_ready), .user_we(user_we),
        .user_addr(user_addr), .user_wdata(user_wdata),
        .user_wmask(1'b0),
        .user_rdata(user_rdata), .user_rvalid(user_rvalid),
        .dfi_address(dfi_address), .dfi_bank(dfi_bank),
        .dfi_ras_n(dfi_ras_n), .dfi_cas_n(dfi_cas_n), .dfi_we_n(dfi_we_n),
        .dfi_cs_n(dfi_cs_n), .dfi_cke(dfi_cke),
        .dfi_odt(dfi_odt), .dfi_reset_n(dfi_reset_n), .dfi_act_n(dfi_act_n),
        .dfi_wrdata(dfi_wrdata), .dfi_wrdata_en(dfi_wrdata_en),
        .dfi_wrdata_mask(dfi_wrdata_mask), .dfi_rddata_en(dfi_rddata_en),
        .dfi_rddata(dfi_rddata), .dfi_rddata_valid(dfi_rddata_valid),
        .phy_turnaround_busy(phy_busy)
    );

    function automatic is_write_cmd;
        input dummy;
        begin
            is_write_cmd = (dfi_cs_n === 1'b0) && (dfi_cas_n === 1'b0) &&
                           (dfi_we_n === 1'b0) && (dfi_wrdata_en === 1'b1);
        end
    endfunction

    function automatic is_read_cmd;
        input dummy;
        begin
            is_read_cmd = (dfi_cs_n === 1'b0) && (dfi_cas_n === 1'b0) &&
                          (dfi_we_n === 1'b1) && (dfi_rddata_en === 1'b1);
        end
    endfunction

    task automatic wait_ready;
        begin
            guard = 0;
            while ((user_ready !== 1'b1) && (guard < 40)) begin
                @(posedge clk); #1;
                guard = guard + 1;
            end
            if (user_ready !== 1'b1) begin
                $display("FAIL turnaround: init/ready timeout");
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        @(negedge clk); rst = 1'b0;
        wait_ready();

        // 1. Write while PHY busy must not be accepted or issued.
        @(negedge clk);
        phy_busy   = 1'b1;
        user_we    = 1'b1;
        user_addr  = {2'd0, 4'd1, 4'd3};
        user_wdata = 8'hA5;
        user_valid = 1'b1;
        repeat (4) begin
            @(posedge clk); #1;
            if (user_ready === 1'b1) begin
                $display("FAIL turnaround: write accepted while busy");
                errors = errors + 1;
            end
            if (is_write_cmd(1'b0)) begin
                $display("FAIL turnaround: WRITE command issued while busy");
                errors = errors + 1;
            end
        end

        // 2. Release busy: the write is accepted and issued once.
        @(negedge clk); phy_busy = 1'b0;
        wait_ready();
        @(negedge clk); user_valid = 1'b0;
        guard = 0;
        while (!is_write_cmd(1'b0) && (guard < 30)) begin
            @(posedge clk); #1; guard = guard + 1;
        end
        if (!is_write_cmd(1'b0)) begin
            $display("FAIL turnaround: WRITE was not issued after busy cleared");
            errors = errors + 1;
        end else if (dfi_wrdata !== 8'hA5) begin
            $display("FAIL turnaround: wrong write data %h", dfi_wrdata);
            errors = errors + 1;
        end

        // 3. A READ may proceed while the PHY is busy.
        wait_ready();
        @(negedge clk);
        phy_busy   = 1'b1;
        user_we    = 1'b0;
        user_addr  = {2'd0, 4'd1, 4'd3};
        user_valid = 1'b1;
        wait_ready();
        @(negedge clk); user_valid = 1'b0;
        guard = 0;
        while (!is_read_cmd(1'b0) && (guard < 30)) begin
            @(posedge clk); #1; guard = guard + 1;
        end
        if (!is_read_cmd(1'b0)) begin
            $display("FAIL turnaround: READ was blocked while busy");
            errors = errors + 1;
        end
        phy_busy = 1'b0;

        #20;
        `ifdef MUTATE
        errors = errors + 1;
        $display("MUTATION: injected failure for exit-code test");
        `endif
        if (errors == 0) $display("PASS turnaround_ctrl");
        else             $fatal(1, "FAIL turnaround_ctrl errors=%0d", errors);
        $finish;
    end
endmodule

`default_nettype wire
