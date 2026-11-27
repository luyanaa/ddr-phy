// SPDX-License-Identifier: Apache-2.0
`timescale 1ns/1ps
module tb_ddr_dqs_train;
    localparam integer LANES = 2;
    localparam integer TAP_BITS = 4;
    localparam integer TAP_COUNT = (1 << TAP_BITS);
    localparam integer SAMPLES_PER_TAP = 2;
    localparam integer SCAN_READS = TAP_COUNT * SAMPLES_PER_TAP;
    localparam integer MAX_WAIT_CYCLES = 2000;

    reg sys_clk = 1'b0;
    always #5 sys_clk = !sys_clk;

    reg rst = 1'b1;
    reg start = 1'b0;
    wire [LANES-1:0] tap_valid;
    reg [LANES-1:0] tap_ready = {LANES{1'b0}};
    wire [LANES*TAP_BITS-1:0] tap_value;
    wire probe_valid;
    reg probe_ready = 1'b0;
    reg probe_done = 1'b0;
    reg [LANES-1:0] probe_pass = {LANES{1'b0}};
    wire busy;
    wire trained;
    wire failed;

    ddr_dqs_train #(
        .LANES(LANES),
        .TAP_BITS(TAP_BITS),
        .SAMPLES_PER_TAP(SAMPLES_PER_TAP),
        .MIN_WINDOW(2),
        .TIMEOUT_CYCLES(16)
    ) dut (
        .sys_clk(sys_clk),
        .rst(rst),
        .start(start),
        .tap_valid(tap_valid),
        .tap_ready(tap_ready),
        .tap_value(tap_value),
        .probe_valid(probe_valid),
        .probe_ready(probe_ready),
        .probe_done(probe_done),
        .probe_pass(probe_pass),
        .busy(busy),
        .trained(trained),
        .failed(failed)
    );

    integer profile = 0;
    integer ack_delay [0:LANES-1];
    integer read_count [0:LANES-1][0:TAP_COUNT-1];
    integer probe_count = 0;
    integer cycle_count = 0;
    integer lane;
    integer tap;
    reg freeze_taps = 1'b0;
    reg hold_probe_ready = 1'b0;
    reg hold_probe_done = 1'b0;

    reg pending_tap [0:LANES-1];
    reg [TAP_BITS-1:0] pending_value [0:LANES-1];
    integer ack_wait [0:LANES-1];
    reg [TAP_BITS-1:0] applied_tap [0:LANES-1];
    reg applied_valid [0:LANES-1];
    reg epoch_active = 1'b0;
    reg [LANES-1:0] epoch_ack_mask = {LANES{1'b0}};
    reg [LANES-1:0] expect_tap_drop = {LANES{1'b0}};

    reg probe_pending = 1'b0;
    integer probe_wait = 0;
    integer last_probe_accept_cycle = -1;
    reg [LANES-1:0] queued_probe_pass = {LANES{1'b0}};
    integer expected_tap;

    function automatic pass_for;
        input integer selected_profile;
        input integer selected_lane;
        input integer selected_tap;
        input integer sample_number;
        begin
            pass_for = 1'b0;
            case (selected_profile)
                // Lane 0's wider candidate is broken by one bad repeated READ.
                // Lane 1 has two equal, disjoint windows and must choose the
                // earlier one. Together these exercise aggregation and ties.
                0: begin
                    if (selected_lane == 0) begin
                        pass_for = (selected_tap >= 1 && selected_tap <= 2) ||
                                   (selected_tap >= 8 && selected_tap <= 11);
                        if (selected_tap == 9 && sample_number == 1)
                            pass_for = 1'b0;
                    end else begin
                        pass_for = (selected_tap >= 4 && selected_tap <= 6) ||
                                   (selected_tap >= 11 && selected_tap <= 13);
                    end
                end
                // Windows reach the last legal tap; the rightmost run wins.
                1: begin
                    if (selected_lane == 0)
                        pass_for = (selected_tap >= 13 && selected_tap <= 15);
                    else
                        pass_for = (selected_tap >= 14 && selected_tap <= 15);
                end
                // No lane has a qualifying window.
                2: pass_for = 1'b0;
                // A valid scan window whose selected center fails final verify.
                3: begin
                    if (sample_number < SAMPLES_PER_TAP) begin
                        if (selected_lane == 0)
                            pass_for = (selected_tap >= 2 && selected_tap <= 4);
                        else
                            pass_for = (selected_tap >= 6 && selected_tap <= 8);
                    end
                end
                default: pass_for = 1'b0;
            endcase
        end
    endfunction

    // This model changes the applied tap only when it raises tap_ready, and
    // computes each READ from that applied value and lane-specific windows.
    // Requests are captured, checked stable until acknowledgement, and lanes
    // acknowledge at different times. Probe completion is deliberately delayed.
    always @(posedge sys_clk or posedge rst) begin
        if (rst) begin
            tap_ready <= {LANES{1'b0}};
            probe_ready <= 1'b0;
            probe_done <= 1'b0;
            probe_pass <= {LANES{1'b0}};
            epoch_active = 1'b0;
            epoch_ack_mask = {LANES{1'b0}};
            expect_tap_drop = {LANES{1'b0}};
            probe_pending = 1'b0;
            probe_wait = 0;
            probe_count = 0;
            last_probe_accept_cycle = -1;
            for (lane = 0; lane < LANES; lane = lane + 1) begin
                pending_tap[lane] = 1'b0;
                pending_value[lane] = {TAP_BITS{1'b0}};
                ack_wait[lane] = 0;
                applied_tap[lane] = {TAP_BITS{1'b0}};
                applied_valid[lane] = 1'b0;
                for (tap = 0; tap < TAP_COUNT; tap = tap + 1)
                    read_count[lane][tap] = 0;
            end
        end else begin
            cycle_count = cycle_count + 1;
            if (cycle_count > 10000)
                $fatal(1, "testbench global watchdog expired");

            tap_ready <= {LANES{1'b0}};
            probe_ready <= !hold_probe_ready;
            probe_done <= 1'b0;

            if ((|tap_valid) && !epoch_active) begin
                epoch_active = 1'b1;
                epoch_ack_mask = {LANES{1'b0}};
            end

            for (lane = 0; lane < LANES; lane = lane + 1) begin
                if (expect_tap_drop[lane]) begin
                    if (tap_valid[lane])
                        $fatal(1, "lane %0d kept tap_valid high after its acknowledgement", lane);
                    expect_tap_drop[lane] = 1'b0;
                end

                if (tap_valid[lane]) begin
                    if (freeze_taps) begin
                        // Deliberately leave this real request unacknowledged.
                    end else if (tap_ready[lane]) begin
                        if (!pending_tap[lane])
                            $fatal(1, "lane %0d acknowledged without a pending request", lane);
                        if (tap_value[lane*TAP_BITS +: TAP_BITS] !== pending_value[lane])
                            $fatal(1, "lane %0d changed its tap before acknowledgement", lane);
                        pending_tap[lane] = 1'b0;
                        epoch_ack_mask[lane] = 1'b1;
                        expect_tap_drop[lane] = 1'b1;
                    end else if (!pending_tap[lane]) begin
                        pending_tap[lane] = 1'b1;
                        pending_value[lane] = tap_value[lane*TAP_BITS +: TAP_BITS];
                        ack_wait[lane] = ack_delay[lane];
                        if (ack_delay[lane] == 0) begin
                            applied_tap[lane] = pending_value[lane];
                            applied_valid[lane] = 1'b1;
                            tap_ready[lane] <= 1'b1;
                        end
                    end else begin
                        if (tap_value[lane*TAP_BITS +: TAP_BITS] !== pending_value[lane])
                            $fatal(1, "lane %0d tap request was not stable", lane);
                        if (ack_wait[lane] == 0) begin
                            applied_tap[lane] = pending_value[lane];
                            applied_valid[lane] = 1'b1;
                            tap_ready[lane] <= 1'b1;
                        end else begin
                            ack_wait[lane] = ack_wait[lane] - 1;
                        end
                    end
                end else if (pending_tap[lane] && !freeze_taps) begin
                    $fatal(1, "lane %0d tap request withdrew before acknowledgement", lane);
                end
            end

            if (!(|tap_valid))
                epoch_active = 1'b0;

            if (probe_pending && !hold_probe_done) begin
                if (probe_wait == 0) begin
                    if (cycle_count - last_probe_accept_cycle < 2)
                        $fatal(1, "probe_done was not delayed after request acceptance");
                    probe_done <= 1'b1;
                    probe_pass <= queued_probe_pass;
                    probe_pending = 1'b0;
                end else begin
                    probe_wait = probe_wait - 1;
                end
            end

            if (probe_valid && probe_ready) begin
                if (|tap_valid)
                    $fatal(1, "probe started while a tap request was still outstanding");
                if (epoch_ack_mask != {LANES{1'b1}})
                    $fatal(1, "probe started before every lane acknowledged its tap");
                if (probe_pending)
                    $fatal(1, "probe accepted while the previous READ was incomplete");
                for (lane = 0; lane < LANES; lane = lane + 1) begin
                    if (!applied_valid[lane])
                        $fatal(1, "probe used lane %0d before any tap was applied", lane);
                end

                if (probe_count < SCAN_READS) begin
                    expected_tap = probe_count / SAMPLES_PER_TAP;
                    for (lane = 0; lane < LANES; lane = lane + 1)
                        if (applied_tap[lane] != expected_tap)
                            $fatal(1, "scan READ %0d used lane %0d tap %0d, expected %0d",
                                   probe_count, lane, applied_tap[lane], expected_tap);
                end else if (probe_count == SCAN_READS) begin
                    case (profile)
                        0: begin
                            if (applied_tap[0] != 1 || applied_tap[1] != 5)
                                $fatal(1, "wrong tie/instability centers: %0d, %0d",
                                       applied_tap[0], applied_tap[1]);
                        end
                        1: begin
                            if (applied_tap[0] != 14 || applied_tap[1] != 14)
                                $fatal(1, "rightmost window center was not selected");
                        end
                        3: begin
                            if (applied_tap[0] != 3 || applied_tap[1] != 7)
                                $fatal(1, "unexpected final-verify test centers");
                        end
                        default: $fatal(1, "unexpected final READ for profile %0d", profile);
                    endcase
                end else begin
                    $fatal(1, "unexpected extra READ after final verification");
                end

                for (lane = 0; lane < LANES; lane = lane + 1) begin
                    queued_probe_pass[lane] = pass_for(
                        profile, lane, applied_tap[lane], read_count[lane][applied_tap[lane]]);
                    read_count[lane][applied_tap[lane]] = read_count[lane][applied_tap[lane]] + 1;
                end
                probe_count = probe_count + 1;
                last_probe_accept_cycle = cycle_count;
                probe_wait = 2;
                probe_pending = 1'b1;
            end
        end
    end

    task set_profile;
        input integer selected_profile;
        input integer lane0_delay;
        input integer lane1_delay;
        integer l;
        integer t;
        begin
            @(negedge sys_clk);
            profile = selected_profile;
            ack_delay[0] = lane0_delay;
            ack_delay[1] = lane1_delay;
            hold_probe_ready = 1'b0;
            hold_probe_done = 1'b0;
            freeze_taps = 1'b0;
            probe_count = 0;
            probe_pending = 1'b0;
            probe_wait = 0;
            epoch_active = 1'b0;
            epoch_ack_mask = {LANES{1'b0}};
            expect_tap_drop = {LANES{1'b0}};
            for (l = 0; l < LANES; l = l + 1)
                for (t = 0; t < TAP_COUNT; t = t + 1)
                    read_count[l][t] = 0;
        end
    endtask

    task pulse_start;
        begin
            @(negedge sys_clk);
            start = 1'b1;
            @(negedge sys_clk);
            start = 1'b0;
        end
    endtask

    task wait_result;
        input integer expect_success;
        integer waited;
        begin
            waited = 0;
            while (!trained && !failed && waited < MAX_WAIT_CYCLES) begin
                @(negedge sys_clk);
                waited = waited + 1;
            end
            if (waited == MAX_WAIT_CYCLES)
                $fatal(1, "training did not finish within %0d cycles", MAX_WAIT_CYCLES);
            if (expect_success && (!trained || failed))
                $fatal(1, "expected trained success, got trained=%b failed=%b", trained, failed);
            if (!expect_success && (!failed || trained))
                $fatal(1, "expected failure, got trained=%b failed=%b", trained, failed);
            if (busy || tap_valid != {LANES{1'b0}} || probe_valid)
                $fatal(1, "terminal state continued issuing traffic");
        end
    endtask

    task check_stays_quiet;
        input integer expected_probe_count;
        begin
            repeat (3) @(negedge sys_clk);
            if (busy || tap_valid != {LANES{1'b0}} || probe_valid)
                $fatal(1, "terminal state emitted traffic after completion");
            if (probe_count != expected_probe_count)
                $fatal(1, "probe count changed after terminal state: %0d", probe_count);
        end
    endtask

    integer waited;
    initial begin
        ack_delay[0] = 0;
        ack_delay[1] = 4;
        repeat (3) @(negedge sys_clk);
        rst = 1'b0;

        // Cancel a live request with reset, then recover into a complete run.
        set_profile(0, 0, 4);
        freeze_taps = 1'b1;
        pulse_start();
        waited = 0;
        while (!(busy && (|tap_valid)) && waited < 20) begin
            @(negedge sys_clk);
            waited = waited + 1;
        end
        if (waited == 20)
            $fatal(1, "training did not present its initial tap request");
        @(negedge sys_clk);
        rst = 1'b1;
        repeat (2) @(negedge sys_clk);
        if (busy || trained || failed || tap_valid != {LANES{1'b0}} || probe_valid)
            $fatal(1, "reset did not cancel training and clear status");
        rst = 1'b0;

        set_profile(0, 0, 4);
        pulse_start();
        wait_result(1);
        if (probe_count != SCAN_READS + 1)
            $fatal(1, "tie/unstable-window run used %0d READs", probe_count);
        check_stays_quiet(SCAN_READS + 1);

        // A separate lane-specific scan checks a winning run at the right edge.
        set_profile(1, 1, 3);
        pulse_start();
        wait_result(1);
        if (probe_count != SCAN_READS + 1)
            $fatal(1, "rightmost-window run used %0d READs", probe_count);
        check_stays_quiet(SCAN_READS + 1);

        // Retesting after TRAINED is supported; a no-window profile must fail.
        set_profile(2, 0, 2);
        pulse_start();
        wait_result(0);
        if (probe_count != SCAN_READS)
            $fatal(1, "no-window scan issued an unexpected final READ");
        check_stays_quiet(SCAN_READS);

        // A valid scan followed by a bad final READ fails without fallback.
        set_profile(3, 0, 1);
        pulse_start();
        wait_result(0);
        if (probe_count != SCAN_READS + 1)
            $fatal(1, "final verification did not use exactly one READ");
        check_stays_quiet(SCAN_READS + 1);

        // A missing probe acceptance and a missing completion each time out.
        set_profile(0, 0, 1);
        hold_probe_ready = 1'b1;
        pulse_start();
        wait_result(0);
        if (probe_count != 0)
            $fatal(1, "probe-ready timeout unexpectedly accepted a READ");
        check_stays_quiet(0);

        set_profile(0, 0, 1);
        hold_probe_done = 1'b1;
        pulse_start();
        wait_result(0);
        if (probe_count != 1)
            $fatal(1, "probe-done timeout accepted %0d READs", probe_count);
        check_stays_quiet(1);

        $display("DDR_DQS_TRAIN_PASS");
        $finish;
    end
endmodule
