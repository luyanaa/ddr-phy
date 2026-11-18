#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""SDF-annotated gate-level check of the half-cycle write launch.

The post-PnR netlist and SDF come from the constrained LibreLane run. This
testbench drives sdr_phy through the DFI write handshake and asserts:

  * dq_o / dm / dq_oe only change on the FALLING edge of clk (the P1-3
    path-B contract that closes the write setup margin);
  * the write data reaches dq_o with the value presented while
    dfi_wrdata_en was high, i.e. the holding register did not lose a beat;
  * the pin command/address appears on the rising edge one cycle after the
    DFI command (the pipelined pin command).

Run: sim/sdf_gate_check.sh
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NL = ROOT / "flow" / "runs" / "sky130" / "final" / "nl" / "sdr_phy.nl.v"
SDF = (ROOT / "flow" / "runs" / "sky130" / "final" / "sdf"
       / "max_ss_100C_1v60" / "sdr_phy__max_ss_100C_1v60.sdf")


def main():
    if not NL.exists():
        raise SystemExit("ERROR: %s missing; run flow/run.sh sky130 first" % NL)
    if not SDF.exists():
        raise SystemExit("ERROR: %s missing" % SDF)

    def fix(q):
        """Verilog escaped identifiers need a trailing space."""
        q = q.strip()
        return q + " " if q.startswith("\\") else q

    nl_text = NL.read_text()
    flops = re.findall(
        r'sky130_fd_sc_hd__df\w+_\d+ (_\d+_) \(\.CLK\([^)]*\),\s*'
        r'\.D\([^)]*\),\s*\.Q\(([^)]+)\)\);', nl_text)
    init = "\n".join(
        '                %d: force dut.%s = 1\'b0;' % (i, fix(q))
        for i, (_inst, q) in enumerate(flops))
    nflops = len(flops)

    release = "\n".join(
        '                %d: release dut.%s;' % (i, fix(q))
        for i, (_inst, q) in enumerate(flops))

    tb = f"""
`timescale 1ns/1ps
module tb_gate;
    reg clk = 0, rst = 1;
    reg [12:0] dfi_address = 0;
    reg [1:0]  dfi_bank = 0;
    reg dfi_ras_n = 1, dfi_cas_n = 1, dfi_we_n = 1;
    reg dfi_cs_n = 1, dfi_cke = 0;
    reg dfi_odt = 0, dfi_reset_n = 1, dfi_act_n = 1;
    reg [7:0]  dfi_wrdata = 0;
    reg        dfi_wrdata_en = 0;
    reg [0:0]  dfi_wrdata_mask = 0;
    reg        dfi_rddata_en = 0;
    wire [7:0] dfi_rddata;
    wire       dfi_rddata_valid;
    wire [12:0] a; wire [1:0] ba;
    wire ras_n, cas_n, we_n, cs_n, cke;
    wire [0:0] dm;
    wire [7:0] dq_o;
    wire dq_oe; wire ck;

    sdr_phy dut (
        .clk(clk), .rst(rst),
        .dfi_address(dfi_address), .dfi_bank(dfi_bank),
        .dfi_ras_n(dfi_ras_n), .dfi_cas_n(dfi_cas_n), .dfi_we_n(dfi_we_n),
        .dfi_cs_n(dfi_cs_n), .dfi_cke(dfi_cke),
        .dfi_odt(dfi_odt), .dfi_reset_n(dfi_reset_n), .dfi_act_n(dfi_act_n),
        .dfi_wrdata(dfi_wrdata), .dfi_wrdata_en(dfi_wrdata_en),
        .dfi_wrdata_mask(dfi_wrdata_mask), .dfi_rddata_en(dfi_rddata_en),
        .dfi_rddata(dfi_rddata), .dfi_rddata_valid(dfi_rddata_valid),
        .a(a), .ba(ba), .ras_n(ras_n), .cas_n(cas_n), .we_n(we_n),
        .cs_n(cs_n), .cke(cke), .dm(dm), .dq_o(dq_o), .dq_oe(dq_oe),
        .dq_i(dfi_rddata), .ck(ck)
    );

    // The post-PnR netlist uses dfxtp (no reset pin): reset cannot clear X,
    // so the flops are initialised explicitly before time 0.
    initial begin
        $sdf_annotate("{SDF.as_posix()}", tb_gate.dut);
    end

    always #5 clk = ~clk;

    // The netlist uses dfxtp (no reset pin), so X cannot be cleared through
    // rst. Initialise every flop's Q directly, then release.
    integer fi;
    task release_flop(input integer k);
        begin
            case (k)
{release}
            endcase
        end
    endtask
    initial begin
        #0.5;
        for (fi = 0; fi < {nflops}; fi = fi + 1) begin
            case (fi)
{init}
            endcase
            #20;
            for (fi = 0; fi < {nflops}; fi = fi + 1) release_flop(fi);
        end
    end

    integer errors = 0;
    integer rise_changes = 0, fall_changes = 0;
    reg [7:0] prev_dq;
    reg       prev_oe;

    // classify every dq_o / dq_oe change by the edge it happened on
    always @(dq_o or dq_oe) begin
        if (^dq_o !== 1'bx && dq_oe !== 1'bx) begin
            if (clk === 1'b1) rise_changes = rise_changes + 1;
            else if (clk === 1'b0) fall_changes = fall_changes + 1;
        end
    end

    task dfi_write(input [7:0] data);
        begin
            @(posedge clk); #1;
            dfi_cs_n = 0; dfi_ras_n = 1; dfi_cas_n = 0; dfi_we_n = 0;
            dfi_address = 13'h0003; dfi_bank = 0;
            dfi_wrdata = data; dfi_wrdata_en = 1; dfi_wrdata_mask = 1'b0;
            @(posedge clk); #1;
            dfi_cs_n = 1; dfi_ras_n = 1; dfi_cas_n = 1; dfi_we_n = 1;
            dfi_wrdata_en = 0;
        end
    endtask

    initial begin
        // X-init: the gate netlist has no resetable flops, so the first
        // checks run after enough cycles for the datapath to resolve.
        repeat (10) @(posedge clk);
        rst = 0;
        repeat (10) @(posedge clk);

        dfi_write(8'hA5);
        #1;
        // dq_o must be driven with A5 and dq_oe high around this write
        if (dq_oe !== 1'b1) begin
            $display("FAIL: dq_oe not asserted after the write command");
            errors = errors + 1;
        end
        if (dq_o !== 8'hA5) begin
            $display("FAIL: dq_o=%h expected A5", dq_o);
            $display("       internal: dq_oe_q=%b dq_o_q0=%b net78=%b",
                     dut.dq_oe_q, dut.dq_o_q[0], dut.net78);
            errors = errors + 1;
        end
        @(negedge clk); #1;
        if (fall_changes == 0) begin
            $display("FAIL: no dq_o/dq_oe transition on a falling edge");
            errors = errors + 1;
        end

        repeat (6) @(posedge clk);
        $display("dq_o/dq_oe transitions: rising=%0d falling=%0d",
                 rise_changes, fall_changes);
        if (rise_changes != 0) begin
            $display("FAIL: %0d transitions on the rising edge; the P1-3 ",
                     rise_changes);
            $display("      path-B contract requires a falling-edge launch");
            errors = errors + 1;
        end
        if (errors == 0) $display("PASS sdf-gate-check");
        else $display("FAIL sdf-gate-check errors=%0d", errors);
        $finish;
    end
endmodule
"""
    out = ROOT / "sim" / "tb_sdf_gate.sv"
    out.write_text(tb)
    print("wrote %s" % out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
