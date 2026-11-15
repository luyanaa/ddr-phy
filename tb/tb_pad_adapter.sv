// SPDX-License-Identifier: Apache-2.0
// Pad adapter contract tests. Compile with BACKEND=1 to verify that an
// unsupported backend fails loudly instead of falling back to core cells.

`timescale 1ps/1ps
`default_nettype none

module tb_pad_adapter;
    parameter integer BACKEND = 0;
    parameter integer DATA_BITS = 8;
    parameter integer CMD_BITS  = 22;
    parameter integer T_OE_ON   = 1000;
    parameter integer T_OE_OFF  = 2000;

    reg [CMD_BITS-1:0]  core_cmd = {CMD_BITS{1'b0}};
    reg [DATA_BITS-1:0] core_dq_o = 8'h00;
    reg                 core_dq_oe = 0;
    reg                 core_ck = 0;
    reg                 io_power_ok = 0;
    reg [7:0]           pad_config = 8'h00;
    reg [DATA_BITS-1:0] ext_drive = 8'h00;
    reg                 ext_oe = 0;

    wire [DATA_BITS-1:0] core_dq_i;
    wire [CMD_BITS-1:0]  pad_cmd;
    wire [DATA_BITS-1:0] pad_dq;
    wire                 pad_ck;
    wire                 pad_ready, contention;

    phy_io_adapter #(
        .DATA_BITS(DATA_BITS), .CMD_BITS(CMD_BITS), .BACKEND(BACKEND),
        .T_OE_ON_PS(T_OE_ON), .T_OE_OFF_PS(T_OE_OFF)
    ) u_adapter (
        .core_cmd(core_cmd), .core_dq_o(core_dq_o), .core_dq_oe(core_dq_oe),
        .core_dq_i(core_dq_i), .core_ck(core_ck),
        .pad_cmd(pad_cmd), .pad_dq(pad_dq), .pad_ck(pad_ck),
        .io_power_ok(io_power_ok), .pad_config(pad_config),
        .pad_ready(pad_ready), .contention(contention)
    );

    assign pad_dq = ext_oe ? ext_drive : {DATA_BITS{1'bz}};

    integer errors = 0;
    task automatic chk(input cond, input [8*48:1] name);
        begin
            if (cond) $display("PASS %0s", name);
            else begin $display("FAIL %0s", name); errors = errors + 1; end
        end
    endtask

    initial begin
        // 1. Power-up Hi-Z: no drive until io_power_ok, even with OE high.
        core_dq_o = 8'hA5; core_dq_oe = 1'b1;
        #(T_OE_ON + 500);
        chk(pad_dq === {DATA_BITS{1'bz}}, "power-up Hi-Z holds DQ at Z");
        chk(pad_ready === 1'b0, "pad_ready low before power ok");

        // 2. Release power: OE rising is delayed by T_OE_ON.
        io_power_ok = 1'b1;
        #(T_OE_ON / 2);
        chk(pad_dq === {DATA_BITS{1'bz}}, "OE rising not instantaneous");
        #(T_OE_ON / 2 + 100);
        chk(pad_dq === 8'hA5, "DQ driven after T_OE_ON");

        // 3. Input direction: external driver visible on core side.
        core_dq_oe = 1'b0;
        #(T_OE_OFF + 100);
        ext_drive = 8'h5A; ext_oe = 1'b1;
        #100;
        chk(core_dq_i === 8'h5A, "external DQ reaches core input");
        ext_oe = 1'b0;
        #100;

        // 4. OE falling is delayed by T_OE_OFF.
        core_dq_oe = 1'b1;
        #(T_OE_ON + 100);
        core_dq_oe = 1'b0;
        #(T_OE_OFF / 2);
        chk(pad_dq === 8'hA5, "OE falling not instantaneous");
        #(T_OE_OFF / 2 + 100);
        chk(pad_dq === {DATA_BITS{1'bz}}, "DQ released after T_OE_OFF");

        // 5. Contention: both sides driving different values.
        core_dq_oe = 1'b1;
        #(T_OE_ON + 100);
        ext_drive = 8'hFF; ext_oe = 1'b1;
        #100;
        chk(contention === 1'b1, "contention detected on both drivers");
        ext_oe = 1'b0; core_dq_oe = 1'b0;
        #(T_OE_OFF + 100);

        if (errors == 0) $display("PASS pad_adapter");
        else             $display("FAIL pad_adapter errors=%0d", errors);
        $finish;
    end
endmodule
`default_nettype wire
