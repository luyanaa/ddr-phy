// SPDX-License-Identifier: Apache-2.0
// Read-capture phase sweep against the layer-2 timing model.
//
// Sweeps (device corner) x (T_BOARD round-trip placeholder) x (capture
// phase). For each T_BOARD it reports the phase window in which the capture
// lands inside the SDRAM data-valid window, and whether phase = 0 (today's
// rtl/sdr_phy.sv, which samples dq_i on posedge clk with no phase control)
// is inside that window.
//
// This is a feasibility study. T_BOARD stands in for the TBD terms in
// specs/timing_contract.yaml; it is NOT a characterized board delay. No STA,
// no min/max PVT pairing, no package/PCB model, no sign-off.

`timescale 1ps/1ps
`default_nettype none

module tb_timing_sweep;
    parameter integer DATA_BITS     = 8;
    parameter integer PHASE_STEPS   = 30;
    parameter integer BOARD_MAX_PS  = 6000;
    parameter integer BOARD_STEP_PS = 500;

    reg [31:0] t_ck    = 10000;
    reg [31:0] t_ac    = 6000;
    reg [31:0] t_oh    = 3000;
    reg [31:0] t_hz    = 6000;
    reg [31:0] t_lz    = 1000;
    reg [31:0] t_ds    = 1500;
    reg [31:0] t_dh    = 800;
    reg [31:0] t_board = 0;
    reg [31:0] t_skew  = 0;
    reg [31:0] t_unc   = 0;
    reg [31:0] phase   = 0;

    reg        clk = 0;
    reg        launch = 0;
    reg [7:0]  launch_data = 8'hA5;
    reg        phy_oe = 0;
    reg [7:0]  phy_dq = 8'h00;
    reg        clear_errors = 0;
    reg        sample = 0;
    wire [7:0] dq;
    wire       model_oe, data_valid, contention, in_sv, in_hv;
    wire [7:0] cap_q;
    wire       cap_err;

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

    integer ci, bi, pi;
    integer pass_lo, pass_hi, npass, zero_ok;
    reg [31:0] bd, ph;
    reg        one_pass;

    // One measurement. launch is asserted at a CK rising edge (T0); the
    // capture strobe is placed at T0 + tCK + phase (+2 ps strobe offset,
    // negligible against ns-scale windows). Then flush before next launch.
    task automatic run_one;
        begin
            @(posedge clk);
            launch_data = 8'hA5;
            launch      = 1'b1;
            @(posedge clk);
            launch      = 1'b0;
            #(phase + 2);
            sample      = 1'b1;
            #1 sample   = 1'b0;
            #5;
            one_pass = (!cap_err) && (cap_q === 8'hA5);
            #(t_board + t_hz + 2*t_ck);
        end
    endtask

    initial begin
        $display("=== P0-2 read-capture phase sweep ===");
        $display("T_BOARD = round-trip placeholder for TBD terms, NOT a characterized delay.");
        for (ci = 0; ci < 3; ci = ci + 1) begin
            case (ci)
                0: begin t_ck=10000; t_ac=6000; t_oh=3000; t_hz=6000; t_lz=1000; end
                1: begin t_ck=7500;  t_ac=5400; t_oh=3000; t_hz=5400; t_lz=1000; end
                2: begin t_ck=7500;  t_ac=5400; t_oh=2500; t_hz=5400; t_lz=0;    end
            endcase
            t_ds = 1500; t_dh = 800; t_skew = 0; t_unc = 0;
            #(t_ck * 5);
            case (ci)
                0: $display("--- corner A: Micron -75, 100 MHz CL2, tAC=6.0 tOH=3.0 ---");
                1: $display("--- corner B: Micron -75, 133 MHz CL3, tAC=5.4 tOH=3.0 ---");
                2: $display("--- corner C: ISSI -7, 133 MHz CL2, tAC=5.4 tOH=2.5 ---");
            endcase
            $display("  fixed-phase limit from P0-1: B <= %0d ps (tCK - tAC)", t_ck - t_ac);
            for (bi = 0; bi <= BOARD_MAX_PS/BOARD_STEP_PS; bi = bi + 1) begin
                bd = bi * BOARD_STEP_PS;
                t_board = bd;
                pass_lo = -1; pass_hi = -1; npass = 0; zero_ok = 0;
                for (pi = 0; pi <= PHASE_STEPS; pi = pi + 1) begin
                    ph = (pi * t_ck) / PHASE_STEPS;
                    if (ph >= t_ck - 50) ph = t_ck - 50;
                    phase = ph;
                    run_one();
                    if (one_pass) begin
                        if (pass_lo < 0) pass_lo = ph;
                        pass_hi = ph;
                        npass = npass + 1;
                        if (ph == 0) zero_ok = 1;
                    end
                end
                if (npass > 0)
                    $display("  B=%5d ps  safe_phase=[%5d .. %5d] ps  width=%5d ps  fixed(delta=0)=%s",
                             bd, pass_lo, pass_hi, pass_hi - pass_lo,
                             zero_ok ? "PASS" : "FAIL");
                else
                    $display("  B=%5d ps  safe_phase=NONE  fixed(delta=0)=FAIL", bd);
            end
        end

        // Uncertainty (jitter/DCD/OCV placeholder) sensitivity at corner A,
        // B = 0. U is added to data arrival and subtracted from the hold
        // guarantee, so the safe window should shrink by 2U about its center.
        t_ck=10000; t_ac=6000; t_oh=3000; t_hz=6000; t_lz=1000;
        t_ds=1500; t_dh=800; t_skew=0; t_board=0;
        #(t_ck * 5);
        $display("--- uncertainty sensitivity (corner A, B=0) ---");
        for (bi = 0; bi <= 6; bi = bi + 1) begin
            t_unc = bi * 250;
            pass_lo = -1; pass_hi = -1; npass = 0;
            for (pi = 0; pi <= PHASE_STEPS; pi = pi + 1) begin
                ph = (pi * t_ck) / PHASE_STEPS;
                if (ph >= t_ck - 50) ph = t_ck - 50;
                phase = ph;
                run_one();
                if (one_pass) begin
                    if (pass_lo < 0) pass_lo = ph;
                    pass_hi = ph;
                    npass = npass + 1;
                end
            end
            if (npass > 0)
                $display("  U=%4d ps  safe_phase=[%5d .. %5d] ps  width=%5d ps",
                         t_unc, pass_lo, pass_hi, pass_hi - pass_lo);
            else
                $display("  U=%4d ps  safe_phase=NONE", t_unc);
        end

        $display("SWEEP_DONE");
        $finish;
    end
endmodule
`default_nettype wire
