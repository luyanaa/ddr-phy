// SPDX-License-Identifier: Apache-2.0
// Clean-room, pin-level DDR1 x8 BL4/CL2 behavioral device.
// This is a functional protocol/data model, not a datasheet timing checker.
`timescale 1ps/1ps
`include "ddr1_timing.vh"
`default_nettype none

module ddr1_device_model #(
    parameter integer READ_DQS_JITTER_PS = 0,
    parameter integer READ_DQ_SKEW_PS = 0,
    parameter integer READ_SSO_PS = 0
) (
    input  wire        ck,
    input  wire        cke,
    input  wire        cs_n,
    input  wire        ras_n,
    input  wire        cas_n,
    input  wire        we_n,
    input  wire [1:0]  ba,
    input  wire [12:0] a,
    input  wire        dm,
    inout  wire [7:0]  dq,
    inout  wire        dqs,
    input  wire signed [31:0] read_offset_ps,

    output reg         fault,
    output reg  [7:0]  fault_code,
    output reg         initialized,
    output wire        read_dq_oe,
    output wire        read_dqs_oe
);

    localparam integer CK_PS          = `DDR1_TCK_PS;
    localparam integer HALF_CK_PS     = CK_PS / 2;
    localparam integer BANKS          = 4;
    localparam integer MEM_BYTES      = 33554432; // 4 banks x 8192 rows x 1024 cols x 8 bit = 32 MiB
    localparam integer WRITE_QUEUE    = 16;
    localparam [7:0]   BAD_COMMAND    = 8'd1;
    localparam [7:0]   BAD_MODE       = 8'd2;
    localparam [7:0]   ACT_OPEN       = 8'd3;
    localparam [7:0]   RW_CLOSED      = 8'd4;
    localparam [7:0]   REF_OPEN       = 8'd5;
    localparam [7:0]   BAD_DQS        = 8'd6;
    localparam [7:0]   BAD_DQ         = 8'd7;
    localparam [7:0]   BAD_POWERUP    = 8'd9;

    reg                  bank_open [0:BANKS-1];
    reg [12:0]           bank_row  [0:BANKS-1];
    // Full 32 MiB x8 array, addressed by {bank, row, column}. This replaces
    // the old 1024-entry sparse slot list; unwritten bytes read as x, which
    // is the correct "no data" state for this functional model.
    reg [7:0]            mem [0:MEM_BYTES-1];

    reg [1:0]            wq_bank [0:WRITE_QUEUE-1];
    reg [12:0]           wq_row  [0:WRITE_QUEUE-1];
    reg [12:0]           wq_col  [0:WRITE_QUEUE-1];
    integer              wq_beat [0:WRITE_QUEUE-1];
    time                 wq_due  [0:WRITE_QUEUE-1];
    integer              wq_head;
    integer              wq_tail;

    reg                  read_dqs;
    reg [7:0]            read_dq;
    reg                  dll_reset_seen;
    reg                  emrs_seen;
    reg                  precharge_all_seen;
    integer              refreshes_after_dll_reset;
    integer              read_tag, dqs_started, dq_started, read_stopped;
    integer              pending_write_count;
    reg                  previous_dqs;
    reg                  previous_cke;
    reg                  first_cke_rise_seen;
    time                 cke_low_since;
    integer              i;

    assign read_dqs_oe = dqs_started != read_stopped;
    assign read_dq_oe  = dq_started  != read_stopped;
    assign dq  = read_dq_oe  ? read_dq  : 8'hzz;
    assign dqs = read_dqs_oe ? read_dqs : 1'bz;

    function automatic [12:0] burst_column;
        input [12:0] base;
        input integer beat;
        begin
            // Sequential BL4 wraps only within the starting four-column group.
            burst_column = (base & 13'h1ffc) | ((base + beat) & 13'h0003);
        end
    endfunction

    task automatic raise_fault;
        input [7:0] code;
        input [8*96-1:0] message;
        begin
            if (fault !== 1'b1) begin
                fault      = 1'b1;
                fault_code = code;
                $display("DDR1_DEVICE_FAULT code=%0d time=%0t: %0s", code, $time, message);
            end
        end
    endtask

    function automatic integer mem_index;
        input [1:0] bank;
        input [12:0] row;
        input [9:0] column;
        begin
            mem_index = {bank, row, column};
        end
    endfunction

    task automatic load_byte;
        input [1:0] bank;
        input [12:0] row;
        input [12:0] column;
        output reg [7:0] value;
        begin
            value = mem[mem_index(bank, row, column[9:0])];
        end
    endtask

    task automatic store_byte;
        input [1:0] bank;
        input [12:0] row;
        input [12:0] column;
        input [7:0] value;
        begin
            mem[mem_index(bank, row, column[9:0])] = value;
        end
    endtask

    task automatic enqueue_write;
        input [1:0] bank;
        input [12:0] row;
        input [12:0] column;
        input time first_edge;
        begin
            if (pending_write_count >= WRITE_QUEUE) begin
                raise_fault(BAD_COMMAND, "write burst queue overflow");
            end else begin
                wq_bank[wq_tail] = bank;
                wq_row[wq_tail]  = row;
                wq_col[wq_tail]  = column;
                wq_beat[wq_tail] = 0;
                wq_due[wq_tail]   = first_edge;
                wq_tail = (wq_tail + 1) % WRITE_QUEUE;
                pending_write_count = pending_write_count + 1;
            end
        end
    endtask

    function automatic integer popcount8;
        input [7:0] value;
        integer idx;
        begin
            popcount8 = 0;
            for (idx = 0; idx < 8; idx = idx + 1)
                popcount8 = popcount8 + value[idx];
        end
    endfunction

    task automatic schedule_read;
        input integer tag;
        input [7:0] beat0, beat1, beat2, beat3;
        integer first_ps;
        integer idx;
        integer sso0, sso1, sso2, sso3;
        begin
            first_ps = `DDR1_CL * CK_PS + read_offset_ps;
            // CL2, 1 CK low preamble, 4 data edges, 0.5 CK postamble.
            // Separate start/end tags merge adjacent bursts without
            // releasing OE or resetting DQS in an older burst.
            // READ_DQS_JITTER_PS models per-burst tDQSCK excursion; the DQ
            // beats stay on the nominal grid, so positive jitter eats the
            // read setup window. READ_DQ_SKEW_PS models per-bit flight skew.
            sso0 = READ_SSO_PS * popcount8(beat0 ^ read_dq);
            sso1 = READ_SSO_PS * popcount8(beat1 ^ read_dq);
            sso2 = READ_SSO_PS * popcount8(beat2 ^ read_dq);
            sso3 = READ_SSO_PS * popcount8(beat3 ^ read_dq);
            dqs_started <= #(first_ps - CK_PS + READ_DQS_JITTER_PS) tag;
            dq_started  <= #(first_ps + sso0) tag;
            read_stopped <= #(first_ps + 2*CK_PS + READ_DQS_JITTER_PS) tag;
            read_dqs <= #(first_ps + READ_DQS_JITTER_PS) 1'b1;
            read_dqs <= #(first_ps + HALF_CK_PS + READ_DQS_JITTER_PS) 1'b0;
            read_dqs <= #(first_ps + CK_PS + READ_DQS_JITTER_PS) 1'b1;
            read_dqs <= #(first_ps + 3*HALF_CK_PS + READ_DQS_JITTER_PS) 1'b0;
            // Worst late DQ relative to DQS in the device profile.
            for (idx = 0; idx < 8; idx = idx + 1) begin
                read_dq[idx] <= #(first_ps + `DDR1_T_DQSQ_PS + idx*READ_DQ_SKEW_PS + sso0) beat0[idx];
                read_dq[idx] <= #(first_ps + HALF_CK_PS + `DDR1_T_DQSQ_PS + idx*READ_DQ_SKEW_PS + sso1) beat1[idx];
                read_dq[idx] <= #(first_ps + CK_PS + `DDR1_T_DQSQ_PS + idx*READ_DQ_SKEW_PS + sso2) beat2[idx];
                read_dq[idx] <= #(first_ps + 3*HALF_CK_PS + `DDR1_T_DQSQ_PS + idx*READ_DQ_SKEW_PS + sso3) beat3[idx];
            end
        end
    endtask

    initial begin
        fault                  = 1'b0;
        fault_code             = 8'd0;
        initialized            = 1'b0;
        pending_write_count    = 0;
        dqs_started            = 0;
        dq_started             = 0;
        read_stopped           = 0;
        read_dqs               = 1'b0;
        read_dq                = 8'h00;
        dll_reset_seen         = 1'b0;
        emrs_seen              = 1'b0;
        precharge_all_seen     = 1'b0;
        refreshes_after_dll_reset = 0;
        wq_head                = 0;
        wq_tail                = 0;
        read_tag               = 0;
        previous_dqs           = 1'bz;
        previous_cke           = 1'bx;
        first_cke_rise_seen    = 1'b0;
        cke_low_since          = 0;
        for (i = 0; i < BANKS; i = i + 1) begin
            bank_open[i] = 1'b0;
            bank_row[i]  = 13'd0;
        end
    end

    // Require stable, low CKE for the DDR1 power-up interval before its
    // first rising edge. CK is driven continuously by the fixture throughout.
    always @(cke) begin
        if (cke === 1'b0) begin
            cke_low_since = $time;
            previous_cke = 1'b0;
        end else if (cke === 1'b1) begin
            if (previous_cke === 1'b0 && !first_cke_rise_seen) begin
                if ($time - cke_low_since < 200_000_000)
                    raise_fault(BAD_POWERUP, "CKE rose before 200 us of stable low power-up");
                first_cke_rise_seen = 1'b1;
            end
            previous_cke = 1'b1;
        end else begin
            previous_cke = 1'bx;
        end
    end

    // Commands are sampled on the actual forwarded CK pin. The sparse key
    // includes every bank, row, and column bit used by the device model.
    always @(posedge ck) begin : sample_pin_command
        integer bank_index;
        reg any_open;
        reg [12:0] base_column;
        reg [7:0] b0, b1, b2, b3;

        if ((cke === 1'b1) && (cs_n === 1'b0)) begin
            any_open = 1'b0;
            for (bank_index = 0; bank_index < BANKS; bank_index = bank_index + 1)
                any_open = any_open | bank_open[bank_index];

            // MRS / EMRS.
            if ((ras_n === 1'b0) && (cas_n === 1'b0) && (we_n === 1'b0)) begin
                if (any_open || !precharge_all_seen) begin
                    raise_fault(BAD_MODE, "MRS/EMRS with an open bank or before PRECHARGE ALL");
                end else if (ba == 2'd1) begin
                    // DDR1 extended mode register: DLL enabled (A0=0).
                    if (a[0] !== 1'b0)
                        raise_fault(BAD_MODE, "unsupported EMRS: DLL disable requested");
                    else begin
                        emrs_seen = 1'b1;
                    end
                end else if (ba == 2'd0) begin
                    if (a[2:0] !== 3'b010 || a[6:4] !== 3'b010 ||
                        a[3] !== 1'b0 || a[9] !== 1'b0) begin
                        raise_fault(BAD_MODE, "only sequential BL4, CL2 programmed-write mode is supported");
                    end else if (a[8] === 1'b1) begin
                        dll_reset_seen = 1'b1;
                        initialized = 1'b0;
                        refreshes_after_dll_reset = 0;
                    end else if (!emrs_seen || !dll_reset_seen || refreshes_after_dll_reset < 2) begin
                        raise_fault(BAD_MODE, "final CL2 MRS missing EMRS, DLL reset, or two refreshes");
                    end else begin
                        initialized = 1'b1;
                    end
                end else begin
                    raise_fault(BAD_MODE, "unsupported DDR1 mode-register bank");
                end
            // ACTIVATE.
            end else if ((ras_n === 1'b0) && (cas_n === 1'b1) && (we_n === 1'b1)) begin
                if (!initialized) begin
                    raise_fault(BAD_MODE, "ACTIVATE before completed CL2/DLL initialization");
                end else if (bank_open[ba]) begin
                    raise_fault(ACT_OPEN, "ACTIVATE to an already-open bank");
                end else begin
                    bank_open[ba] = 1'b1;
                    bank_row[ba]  = a;
                end
            // READ or WRITE.
            end else if ((ras_n === 1'b1) && (cas_n === 1'b0)) begin
                if (!initialized) begin
                    raise_fault(BAD_MODE, "READ/WRITE before completed CL2/DLL initialization");
                end else if (!bank_open[ba]) begin
                    raise_fault(RW_CLOSED, "READ/WRITE to a closed bank");
                end else if (a[10] !== 1'b0) begin
                    raise_fault(BAD_COMMAND, "this profile requires explicit PRECHARGE");
                end else begin
                    base_column = {3'b0, a[9:0]};
                    if (we_n === 1'b0) begin
                        enqueue_write(ba, bank_row[ba], base_column, $time + `DDR1_CWL * CK_PS);
                    end else begin
                        load_byte(ba, bank_row[ba], burst_column(base_column, 0), b0);
                        load_byte(ba, bank_row[ba], burst_column(base_column, 1), b1);
                        load_byte(ba, bank_row[ba], burst_column(base_column, 2), b2);
                        load_byte(ba, bank_row[ba], burst_column(base_column, 3), b3);
                        read_tag = read_tag + 1;
                        schedule_read(read_tag, b0, b1, b2, b3);
                    end
                end
            // PRECHARGE.
            end else if ((ras_n === 1'b0) && (cas_n === 1'b1) && (we_n === 1'b0)) begin
                if (a[10] === 1'b1) begin
                    for (bank_index = 0; bank_index < BANKS; bank_index = bank_index + 1)
                        bank_open[bank_index] = 1'b0;
                    precharge_all_seen = 1'b1;
                end else begin
                    bank_open[ba] = 1'b0;
                end
            // AUTO REFRESH.
            end else if ((ras_n === 1'b0) && (cas_n === 1'b0) && (we_n === 1'b1)) begin
                if (any_open) begin
                    raise_fault(REF_OPEN, "AUTO REFRESH with an open bank");
                end else begin
                    if (dll_reset_seen)
                        refreshes_after_dll_reset = refreshes_after_dll_reset + 1;
                end
            end else if ((ras_n !== 1'b1) || (cas_n !== 1'b1) || (we_n !== 1'b1)) begin
                raise_fault(BAD_COMMAND, "unknown or unsupported command pin encoding");
            end
        end
    end

    // Consume only resolved, real DQS transitions. Z-to-preamble and
    // postamble-to-Z are not data edges. Write bytes and DM are sampled from
    // the shared pins at each of the four expected DQS edges.
    always @(dqs) begin : sample_write_strobe
        time expected_edge;
        reg stable_edge;

        stable_edge = ((previous_dqs === 1'b0) || (previous_dqs === 1'b1)) &&
                      ((dqs === 1'b0) || (dqs === 1'b1)) &&
                      (dqs !== previous_dqs);
        if (stable_edge && (read_dqs_oe !== 1'b1)) begin
            if (pending_write_count == 0) begin
                raise_fault(BAD_DQS, "unexpected DQS data edge without a queued WRITE");
            end else begin
                expected_edge = wq_due[wq_head] + HALF_CK_PS * wq_beat[wq_head];
                if ($time + 1 < expected_edge || $time > expected_edge + 1) begin
                    raise_fault(BAD_DQS, "write DQS edge is not at the nominal BL4 phase");
                end else if (((wq_beat[wq_head] & 1) == 0 && dqs !== 1'b1) ||
                             ((wq_beat[wq_head] & 1) != 0 && dqs !== 1'b0)) begin
                    raise_fault(BAD_DQS, "write BL4 DQS polarity/order is incorrect");
                end else if ((^dq) === 1'bx || (dm !== 1'b0 && dm !== 1'b1)) begin
                    raise_fault(BAD_DQ, "unknown DQ/DM sampled on a write DQS edge");
                end else begin
                    if (dm === 1'b0) begin
                        store_byte(wq_bank[wq_head], wq_row[wq_head],
                                   burst_column(wq_col[wq_head], wq_beat[wq_head]), dq);
                    end
                    if (wq_beat[wq_head] == 3) begin
                        wq_head = (wq_head + 1) % WRITE_QUEUE;
                        pending_write_count = pending_write_count - 1;
                    end else begin
                        wq_beat[wq_head] = wq_beat[wq_head] + 1;
                    end
                end
            end
        end
        previous_dqs = dqs;
    end

endmodule

`default_nettype wire
