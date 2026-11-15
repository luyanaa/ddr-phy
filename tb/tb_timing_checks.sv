// SPDX-License-Identifier: Apache-2.0
// Negative / mutation tests for the layer-2 timing environment.
//
// A testbench that only passes good designs proves nothing. Each case here
// injects a fault and asserts the model or monitor rejects it. These are
// detection-capability tests, not protocol coverage.

`timescale 1ps/1ps
`default_nettype none

module tb_timing_checks;
    parameter integer DATA_BITS = 8;

    reg [31:0] t_ck=10000, t_ac=6000, t_oh=3000, t_hz=6000, t_lz=1000;
    reg [31:0] t_ds=1500, t_dh=800, t_board=0, t_skew=0, t_unc=0;
    reg        clk=0, launch=0, phy_oe=0, clear_errors=0, sample=0;
    reg [7:0]  launch_data=8'hA5, phy_dq=8'h00;
    wire [7:0] dq, cap_q;
    wire       model_oe, data_valid, contention, in_sv, in_hv, cap_err;

    sdram_timing_model #(.DATA_BITS(DATA_BITS)) u_model (
        .ck(clk), .launch(launch), .launch_data(launch_data),
        .phy_oe(phy_oe), .phy_dq(phy_dq), .clear_errors(clear_errors),
        .t_ck(t_ck), .t_ac(t_ac), .t_oh(t_oh), .t_hz(t_hz), .t_lz(t_lz),
        .t_ds(t_ds), .t_dh(t_dh), .t_board(t_board), .t_skew(t_skew),
        .t_unc(t_unc),
        .dq(dq), .model_oe(model_oe), .data_valid(data_valid),
        .contention(contention), .in_setup_violation(in_sv),
        .in_hold_violation(in_hv)
    );
    read_capture #(.DATA_BITS(DATA_BITS)) u_cap (
        .sample(sample), .rst(1'b0), .dq(dq), .data_valid(data_valid),
        .q(cap_q), .timing_error(cap_err)
    );

    assign dq = phy_oe ? phy_dq : {DATA_BITS{1'bz}};
    always #(t_ck/2) clk = ~clk;

    integer errors = 0;
    reg     one_pass;

    task automatic run_capture(input [31:0] ph);
        begin
            @(posedge clk);
            launch_data = 8'hA5; launch = 1'b1;
            @(posedge clk); launch = 1'b0;
            #(ph + 2);
            sample = 1'b1; #1 sample = 1'b0; #5;
            one_pass = (!cap_err) && (cap_q === 8'hA5);
            #(t_board + t_hz + 2*t_ck);
        end
    endtask

    task automatic chk(input cond, input [8*40:1] name);
        begin
            if (cond) $display("PASS %0s", name);
            else begin $display("FAIL %0s", name); errors = errors + 1; end
        end
    endtask

    initial begin
        #(t_ck * 3);

        // 1. Control: correct parameters, fixed phase, B=0 -> must pass.
        run_capture(0);
        chk(one_pass, "control: good design passes");

        // 2. Mutation: tAC inflated past tCK -> data not valid at capture.
        t_ac = 11000;
        run_capture(0);
        chk(!one_pass, "mutation: inflated tAC rejected");
        t_ac = 6000;

        // 3. Mutation: tOH collapsed to 0 with a late capture -> hold fail.
        t_oh = 0;
        run_capture(2000);
        chk(!one_pass, "mutation: collapsed tOH rejected");
        t_oh = 3000;

        // 4. Mutation: bit skew pushes MSB past the capture edge.
        t_skew = t_ck;
        run_capture(0);
        chk(!one_pass, "mutation: excessive DQ bit skew rejected");
        t_skew = 0;

        // 5. Bus contention: PHY drives while SDRAM still drives DQ.
        // Measure the delay from the launch edge, not from the next CK edge:
        // oe_r falls at T0 + tCK + tHZ, so waiting tAC after the second
        // posedge would land after the SDRAM has already released DQ.
        @(posedge clk); launch = 1'b1; launch_data = 8'hA5;
        #1 launch = 1'b0;
        #(t_lz + 100);
        phy_dq = 8'h00; phy_oe = 1'b1;
        #10;
        chk(contention === 1'b1, "contention: both drivers detected");
        phy_oe = 1'b0;
        #(t_ck + t_hz + 2*t_ck);

        // 6. Write input hold (tDH): DQ changes too soon after CK edge.
        clear_errors = 1'b1; #1 clear_errors = 1'b0;
        phy_dq = 8'h00; phy_oe = 1'b1;
        @(posedge clk);
        #(t_dh / 2);
        phy_dq = 8'hFF;
        #10;
        chk(in_hv === 1'b1, "tDH: early DQ change rejected");
        phy_oe = 1'b0;

        // 7. Write input setup (tDS): DQ changes too close to next CK edge.
        clear_errors = 1'b1; #1 clear_errors = 1'b0;
        phy_dq = 8'h00; phy_oe = 1'b1;
        @(posedge clk);
        #(t_ck - t_ds / 2);
        phy_dq = 8'hFF;
        #10;
        chk(in_sv === 1'b1, "tDS: late DQ change rejected");
        phy_oe = 1'b0;

        #(t_ck * 3);
        if (errors == 0) $display("PASS timing_checks");
        else             $display("FAIL timing_checks errors=%0d", errors);
        $finish;
    end
endmodule
`default_nettype wire
