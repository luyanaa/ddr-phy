// SPDX-License-Identifier: Apache-2.0
// Layer-2 timing/boundary model for one SDR SDRAM DQ beat.
//
// It does NOT model banks, rows, bursts or commands. Layer-1
// sim/sdram_model.sv does that. This model produces a *timed* read data
// eye at the ASIC pins so a capture phase can be swept against real
// datasheet AC limits. Per checklist section 3 the layers are independent
// and combinable; this is the timing/boundary layer.
//
// A posedge on launch (issued at a CK edge, time T0) schedules one beat:
//
//   T0 + B + T_LZ              DQ leaves Hi-Z
//   T0 + B + T_AC + U          DQ = launch_data; data_valid rises
//   T0 + B + T_CK + T_OH - U   data_valid falls (tOH,min guarantee ends)
//   T0 + B + T_CK + T_HZ       DQ returns to Hi-Z
//
// B = T_BOARD: a single-number placeholder for the TBD round trip
// (tCLK,fwd + tDQ,return) in specs/timing_contract.yaml. It is NOT a
// characterized value. U = T_UNC: placeholder for jitter/DCD/OCV.
// DQ bit [DATA_BITS-1] is delayed by T_SKEW to model bit-to-bit skew.
// T_DS / T_DH are checked against write data while phy_oe is high.
//
// Delays are integer ps (timescale 1ps/1ps) so Icarus applies them
// exactly. Runtime knobs are input ports, so one elaboration sweeps many
// corners. Launches must be spaced far enough apart that the fork branches
// do not overlap (the sweep uses BL=1 with idle cycles).
//
// Verification model only: not synthesizable, not STA, not SI/PI, not
// sign-off. No package RLC, no PVT corners, no min/max path pairing.

`timescale 1ps/1ps
`default_nettype none

module sdram_timing_model #(
    parameter integer DATA_BITS = 8
)(
    input  wire                    ck,
    input  wire                    launch,
    input  wire [DATA_BITS-1:0]    launch_data,
    input  wire                    phy_oe,
    input  wire [DATA_BITS-1:0]    phy_dq,
    input  wire                    clear_errors,

    input  wire [31:0]             t_ck,
    input  wire [31:0]             t_ac,
    input  wire [31:0]             t_oh,
    input  wire [31:0]             t_hz,
    input  wire [31:0]             t_lz,
    input  wire [31:0]             t_ds,
    input  wire [31:0]             t_dh,
    input  wire [31:0]             t_board,
    input  wire [31:0]             t_skew,
    input  wire [31:0]             t_unc,

    inout  wire [DATA_BITS-1:0]    dq,
    output wire                    model_oe,
    output wire                    data_valid,
    output wire                    contention,
    output wire                    in_setup_violation,
    output wire                    in_hold_violation
);

    reg                    oe_r  = 1'b0;
    reg                    dv_r  = 1'b0;
    reg [DATA_BITS-1:0]    data_r = {DATA_BITS{1'b0}};
    reg                    setup_v = 1'b0;
    reg                    hold_v  = 1'b0;
    reg [63:0]             last_ck_time = 64'd0;
    reg [63:0]             dt;

    assign dq                 = oe_r ? data_r : {DATA_BITS{1'bz}};
    assign model_oe           = oe_r;
    assign data_valid         = dv_r;
    assign contention         = oe_r && phy_oe;
    assign in_setup_violation = setup_v;
    assign in_hold_violation  = hold_v;

    always @(posedge ck)       last_ck_time = $time;
    always @(posedge clear_errors) begin
        setup_v = 1'b0;
        hold_v  = 1'b0;
    end

    // Write-path input setup/hold check. A DQ change too soon after the
    // sampling edge violates tDH; one too close to the next edge violates
    // tDS. This is a clock-counting check on an absolute time axis, not a
    // transistor-level window check.
    always @(phy_dq) begin
        if (phy_oe) begin
            dt = $time - last_ck_time;
            if (dt < {32'd0, t_dh})            hold_v  = 1'b1;
            if (dt > {32'd0, t_ck} - {32'd0, t_ds}) setup_v = 1'b1;
        end
    end

    // Scheduled read eye. Separate branches so T_BOARD, T_UNC and T_SKEW
    // can be swept at runtime without re-elaboration.
    always @(posedge launch) begin
        // Each beat starts with unknown data, so a bit that has not arrived
        // yet (skew) cannot silently reuse the previous beat's value.
        data_r = {DATA_BITS{1'bx}};
        dv_r   = 1'b0;
        fork
            begin
                #(t_board + t_lz) oe_r = 1'b1;
            end
            begin
                #(t_board + t_ac + t_unc);
                data_r[DATA_BITS-2:0] = launch_data[DATA_BITS-2:0];
                if ((t_oh > t_unc) &&
                    (t_board + t_ck + t_oh - t_unc > t_board + t_ac + t_unc))
                    dv_r = 1'b1;
            end
            begin
                #(t_board + t_ac + t_unc + t_skew);
                data_r[DATA_BITS-1] = launch_data[DATA_BITS-1];
            end
            begin
                if (t_oh > t_unc)
                    #(t_board + t_ck + t_oh - t_unc) dv_r = 1'b0;
                else
                    #(t_board + t_ck)                dv_r = 1'b0;
            end
            begin
                #(t_board + t_ck + t_hz) oe_r = 1'b0;
            end
        join_none
    end

endmodule
`default_nettype wire
