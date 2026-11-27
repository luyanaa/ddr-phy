// SPDX-License-Identifier: Apache-2.0
// Passive pin-level minimum-command-timing checker for the DDR1 x8/BL4 profile.
// Functional geometry, initialization, and retention checks belong to the device model.
`timescale 1ps/1ps
`include "ddr1_timing.vh"
`default_nettype none

module ddr1_timing_checker #(
    parameter integer TCK_PS    = `DDR1_TCK_PS,
    parameter integer T_RCD_PS  = `DDR1_T_RCD_PS,
    parameter integer T_RP_PS   = `DDR1_T_RP_PS,
    parameter integer T_RAS_PS  = `DDR1_T_RAS_PS,
    parameter integer T_RFC_PS  = `DDR1_T_RFC_PS,
    parameter integer T_RRD_PS  = `DDR1_T_RRD_PS,
    parameter integer T_RC_PS   = `DDR1_T_RC_PS,
    parameter integer T_WR_PS   = `DDR1_T_WR_PS,
    parameter integer T_RTP_CK  = `DDR1_T_RTP_CK,
    parameter integer T_MRD_CK  = `DDR1_T_MRD_CK,
    parameter integer T_WTR_CK  = `DDR1_T_WTR_CK,
    parameter integer T_CCD_CK  = `DDR1_T_CCD_CK,
    parameter integer BL        = `DDR1_BL,
    parameter integer CWL       = `DDR1_CWL
)(
    input  wire       ck,
    input  wire       cke,
    input  wire       cs_n,
    input  wire       ras_n,
    input  wire       cas_n,
    input  wire       we_n,
    input  wire [1:0] ba,
    input  wire       a10,
    output reg        fault,
    output reg  [3:0] fault_code
);

    localparam [3:0] F_T_RCD = 4'd1;
    localparam [3:0] F_T_RAS = 4'd2;
    localparam [3:0] F_T_RP  = 4'd3;
    localparam [3:0] F_T_RFC = 4'd4;
    localparam [3:0] F_T_MRD = 4'd5;
    localparam [3:0] F_T_RRD = 4'd6;
    localparam [3:0] F_T_RC  = 4'd7;
    localparam [3:0] F_T_CCD = 4'd8;
    localparam [3:0] F_T_WR  = 4'd9;
    localparam [3:0] F_T_WTR = 4'd10;
    localparam [3:0] F_T_RTP = 4'd11;

    reg       bank_open [0:3];
    reg       act_valid [0:3];
    reg       pre_valid [0:3];
    reg       wr_valid  [0:3];
    reg       rd_valid  [0:3];
    time  act_at    [0:3];
    time  pre_at    [0:3];
    time  wr_anchor_at [0:3];
    time  rd_at     [0:3];

    reg       refresh_valid;
    reg       mrs_valid;
    reg       cas_valid;
    reg       last_wr_anchor_valid;
    time  refresh_at;
    time  mrs_at;
    time  cas_at;
    time  last_wr_anchor_at;

    task automatic raise_fault;
        input [3:0] code;
        input [8*80-1:0] message;
        begin
            if (fault !== 1'b1) begin
                fault      = 1'b1;
                fault_code = code;
                $display("DDR1_TIMING_FAULT code=%0d time=%0t: %0s",
                         code, $time, message);
            end
        end
    endtask

    integer init_bank;
    initial begin
        fault                 = 1'b0;
        fault_code            = 4'd0;
        refresh_valid         = 1'b0;
        mrs_valid             = 1'b0;
        cas_valid             = 1'b0;
        last_wr_anchor_valid  = 1'b0;
        refresh_at            = 0;
        mrs_at                = 0;
        cas_at                = 0;
        last_wr_anchor_at     = 0;
        for (init_bank = 0; init_bank < 4; init_bank = init_bank + 1) begin
            bank_open[init_bank]    = 1'b0;
            act_valid[init_bank]    = 1'b0;
            pre_valid[init_bank]    = 1'b0;
            wr_valid[init_bank]     = 1'b0;
            rd_valid[init_bank]     = 1'b0;
            act_at[init_bank]       = 0;
            pre_at[init_bank]       = 0;
            wr_anchor_at[init_bank] = 0;
            rd_at[init_bank]        = 0;
        end
    end

    // Commands are decoded only on the forwarded CK edge. Timestamps are
    // absolute pin times in ps; cycle-valued limits are converted using TCK_PS.
    always @(posedge ck) begin : check_pin_command
        integer bank_index;
        reg [2:0] command;
        time now_ps;

        if ((cke === 1'b1) && (cs_n === 1'b0)) begin
            command = {ras_n, cas_n, we_n};
            now_ps = $time;

            // tRFC and tMRD block every defined non-NOP command, including
            // PRECHARGE and another REF/MRS, not just row/column commands.
            if (((^command) !== 1'bx) && (command !== 3'b111)) begin
                if (refresh_valid && ((now_ps - refresh_at) < T_RFC_PS))
                    raise_fault(F_T_RFC, "command issued before tRFC elapsed");
                if (mrs_valid && ((now_ps - mrs_at) < (T_MRD_CK * TCK_PS)))
                    raise_fault(F_T_MRD, "command issued before tMRD elapsed");
            end

            case (command)
                // ACTIVATE.
                3'b011: begin
                    if ((^ba) !== 1'bx) begin
                        if (!bank_open[ba]) begin
                            if (pre_valid[ba] &&
                                ((now_ps - pre_at[ba]) < T_RP_PS))
                                raise_fault(F_T_RP, "ACTIVATE issued before tRP elapsed");
                            for (bank_index = 0; bank_index < 4; bank_index = bank_index + 1) begin
                                if ((bank_index != ba) && act_valid[bank_index] &&
                                    ((now_ps - act_at[bank_index]) < T_RRD_PS))
                                    raise_fault(F_T_RRD, "different-bank ACTIVATEs violate tRRD");
                            end
                            if (act_valid[ba] &&
                                ((now_ps - act_at[ba]) < T_RC_PS))
                                raise_fault(F_T_RC, "same-bank ACTIVATEs violate tRC");
                            bank_open[ba] = 1'b1;
                            act_valid[ba] = 1'b1;
                            act_at[ba] = now_ps;
                            pre_valid[ba] = 1'b0;
                        end
                    end
                end

                // READ or WRITE. A10 does not change the CAS command timing;
                // auto-precharge geometry remains the functional model's scope.
                3'b101, 3'b100: begin
                    if ((^ba) !== 1'bx) begin
                        if (bank_open[ba] && act_valid[ba] &&
                            ((now_ps - act_at[ba]) < T_RCD_PS))
                            raise_fault(F_T_RCD, "READ/WRITE issued before tRCD elapsed");
                    end
                    if ((command === 3'b101) && last_wr_anchor_valid &&
                        ((now_ps - last_wr_anchor_at) < (T_WTR_CK * TCK_PS)))
                        raise_fault(F_T_WTR, "READ issued before DDR1 tWTR elapsed");
                    if (cas_valid && ((now_ps - cas_at) < (T_CCD_CK * TCK_PS)))
                        raise_fault(F_T_CCD, "column commands violate tCCD");
                    cas_valid = 1'b1;
                    cas_at = now_ps;

                    if ((command === 3'b101) && ((^ba) !== 1'bx) &&
                        bank_open[ba] && (a10 === 1'b0)) begin
                        rd_valid[ba] = 1'b1;
                        rd_at[ba] = now_ps;
                    end
                    if ((command === 3'b100) && ((^ba) !== 1'bx) && bank_open[ba]) begin
                        // The DDR1 figures reference write recovery/turnaround
                        // from the first CK after the final data-in pair.
                        wr_valid[ba] = 1'b1;
                        wr_anchor_at[ba] = now_ps + ((CWL + (BL / 2)) * TCK_PS);
                        last_wr_anchor_valid = 1'b1;
                        last_wr_anchor_at = wr_anchor_at[ba];
                    end
                end

                // PRECHARGE. A10=1 targets all banks. Auto-precharge is not
                // inferred from READ/WRITE in this explicit-PRE profile.
                3'b010: begin
                    if (a10 === 1'b1) begin
                        for (bank_index = 0; bank_index < 4; bank_index = bank_index + 1) begin
                            if (bank_open[bank_index] && act_valid[bank_index] &&
                                ((now_ps - act_at[bank_index]) < T_RAS_PS))
                                raise_fault(F_T_RAS, "PRECHARGE ALL issued before tRAS elapsed");
                            if ((BL == 4) && (CWL == 1) && wr_valid[bank_index] &&
                                ((now_ps - wr_anchor_at[bank_index]) < T_WR_PS))
                                raise_fault(F_T_WR, "PRECHARGE ALL issued before guarded tWR elapsed");
                            if (rd_valid[bank_index] &&
                                ((now_ps - rd_at[bank_index]) < (T_RTP_CK * TCK_PS)))
                                raise_fault(F_T_RTP, "PRECHARGE ALL issued before tRTP elapsed");
                        end
                        for (bank_index = 0; bank_index < 4; bank_index = bank_index + 1) begin
                            bank_open[bank_index] = 1'b0;
                            pre_valid[bank_index] = 1'b1;
                            pre_at[bank_index] = now_ps;
                            wr_valid[bank_index] = 1'b0;
                            rd_valid[bank_index] = 1'b0;
                        end
                    end else if ((a10 === 1'b0) && ((^ba) !== 1'bx)) begin
                        if (bank_open[ba] && act_valid[ba] &&
                            ((now_ps - act_at[ba]) < T_RAS_PS))
                            raise_fault(F_T_RAS, "PRECHARGE issued before tRAS elapsed");
                        if ((BL == 4) && (CWL == 1) && wr_valid[ba] &&
                            ((now_ps - wr_anchor_at[ba]) < T_WR_PS))
                            raise_fault(F_T_WR, "PRECHARGE issued before guarded tWR elapsed");
                        if (rd_valid[ba] &&
                            ((now_ps - rd_at[ba]) < (T_RTP_CK * TCK_PS)))
                            raise_fault(F_T_RTP, "PRECHARGE issued before tRTP elapsed");
                        bank_open[ba] = 1'b0;
                        pre_valid[ba] = 1'b1;
                        pre_at[ba] = now_ps;
                        wr_valid[ba] = 1'b0;
                        rd_valid[ba] = 1'b0;
                    end
                end

                // AUTO REFRESH and MRS/EMRS both require tRP after each
                // observed bank precharge. Initial power-up state is outside
                // this checker; the functional device model owns that sequence.
                3'b001, 3'b000: begin
                    for (bank_index = 0; bank_index < 4; bank_index = bank_index + 1) begin
                        if (pre_valid[bank_index] &&
                            ((now_ps - pre_at[bank_index]) < T_RP_PS))
                            raise_fault(F_T_RP, "REFRESH/MRS issued before tRP elapsed");
                    end
                    if (command === 3'b001) begin
                        refresh_valid = 1'b1;
                        refresh_at = now_ps;
                    end else begin
                        mrs_valid = 1'b1;
                        mrs_at = now_ps;
                    end
                end

                default: ;
            endcase
        end
    end

endmodule

`default_nettype wire
