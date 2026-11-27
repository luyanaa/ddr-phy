// SPDX-License-Identifier: Apache-2.0
// DDR1 single rank x8, BL4, CL2. sys_clk is CK/2, with edges aligned
// to CK rising edges; ck90 lags CK by T/4. DFI phase 0 is the low slice.
// CK/CK# below are logic signals, not SSTL-2 output drivers. The backend
// supplies the clocks and a received DQS delayed into the DQ eye.
`default_nettype none
module ddr1_phy #(
    parameter integer DQ_WIDTH = 8,
    parameter integer LANES = DQ_WIDTH / 8,
    parameter integer CAPTURE_SLOTS = 4,
    parameter integer CAPTURE_SLOT_BITS =
        (CAPTURE_SLOTS <= 1) ? 1 : $clog2(CAPTURE_SLOTS)
) (
    input  wire                        sys_clk, ck, ck90, rst,
    input  wire [25:0]                 dfi_address,
    input  wire [3:0]                  dfi_bank,
    input  wire [1:0]                  dfi_ras_n, dfi_cas_n, dfi_we_n,
    input  wire [1:0]                  dfi_cs_n, dfi_cke,
    input  wire [4*DQ_WIDTH-1:0]       dfi_wrdata,
    input  wire [4*LANES-1:0]          dfi_wrdata_mask,
    input  wire [1:0]                  dfi_wrdata_en, dfi_rddata_en,
    output reg  [4*DQ_WIDTH-1:0]       dfi_rddata,
    output reg  [1:0]                  dfi_rddata_valid,

    output wire                        pad_ck, pad_ck_n,
    output reg  [12:0]                 a,
    output reg  [1:0]                  ba,
    output reg                         ras_n, cas_n, we_n, cs_n, cke,
    output wire [DQ_WIDTH-1:0]         dq_o,
    input  wire [DQ_WIDTH-1:0]         dq_i,
    output wire [LANES-1:0]            dq_oe, dm, dqs_o, dqs_oe,
    input  wire [LANES-1:0]            dqs_capture,
    input  wire                        probe_mode,
    output reg                         read_frame_done,
    output reg  [LANES-1:0]            read_frame_good,
    output reg  [4*DQ_WIDTH-1:0]       read_frame_data,
    output reg                         read_error, dfi_error
);
    assign pad_ck   = ck;
    assign pad_ck_n = ~ck;

    // Supported CAS phase is 1. Non-data commands can use either phase.
    // An inconsistent DFI command must not reach the part without its beat.
    wire [1:0] cas_access = ~dfi_cs_n & dfi_ras_n & ~dfi_cas_n;
    wire [1:0] reads = cas_access & dfi_we_n;
    wire [1:0] writes = cas_access & ~dfi_we_n;
    wire do_read = reads[1] && dfi_rddata_en[1];
    wire do_write = writes[1] && dfi_wrdata_en[1];
    wire cs1 = dfi_cs_n[1] || (cas_access[1] && !(do_read || do_write));
    localparam [19:0] DESELECT = {13'd0, 2'd0, 4'b1111, 1'b0};
    reg [19:0] ca0, ca1;
    always @(posedge sys_clk or posedge rst) begin
        if (rst) begin
            ca0 <= DESELECT;
            ca1 <= DESELECT;
            dfi_error <= 1'b0;
        end else begin
            ca0 <= {dfi_address[12:0], dfi_bank[1:0], dfi_ras_n[0], dfi_cas_n[0],
                    dfi_we_n[0], dfi_cs_n[0] || cas_access[0], dfi_cke[0]};
            ca1 <= {dfi_address[25:13], dfi_bank[3:2], dfi_ras_n[1], dfi_cas_n[1],
                    dfi_we_n[1], cs1, dfi_cke[1]};
            if (cas_access[0] || reads != dfi_rddata_en || writes != dfi_wrdata_en)
                dfi_error <= 1'b1;
        end
    end

    // Phase 0 reaches rising CK one CK after sampling DFI, phase 1 two.
    always @(posedge pad_ck_n or posedge rst) begin
        if (rst)          {a, ba, ras_n, cas_n, we_n, cs_n, cke} <= DESELECT;
        else if (sys_clk) {a, ba, ras_n, cas_n, we_n, cs_n, cke} <= ca0;
        else              {a, ba, ras_n, cas_n, we_n, cs_n, cke} <= ca1;
    end

    // LiteDRAM presents the complete BL4 data word one sys cycle after
    // wrdata_en. Keep each physical byte lane independent at the pad edge.
    reg tx_pending, tx_valid;
    reg [4*DQ_WIDTH-1:0] tx_word;
    reg [4*LANES-1:0] tx_mask;
    always @(posedge sys_clk or posedge rst) begin
        if (rst) begin
            tx_pending <= 1'b0;
            tx_valid <= 1'b0;
        end else begin
            tx_pending <= do_write;
            tx_valid <= tx_pending;
        end
    end
    always @(posedge sys_clk) begin
        if (tx_pending) begin
            tx_word <= dfi_wrdata;
            tx_mask <= dfi_wrdata_mask;
        end
    end

    genvar lane;
    generate
        for (lane = 0; lane < LANES; lane = lane + 1) begin : g_tx_lane
            wire [7:0] fall_byte = sys_clk ? tx_word[8*lane +: 8] :
                                                tx_word[2*DQ_WIDTH + 8*lane +: 8];
            wire [7:0] rise_byte = sys_clk ? tx_word[DQ_WIDTH + 8*lane +: 8] :
                                                tx_word[3*DQ_WIDTH + 8*lane +: 8];
            wire fall_mask = sys_clk ? tx_mask[lane] :
                                         tx_mask[2*LANES + lane];
            wire rise_mask = sys_clk ? tx_mask[LANES + lane] :
                                         tx_mask[3*LANES + lane];
            wire [9:0] fall_payload = {tx_valid, tx_valid && fall_mask, fall_byte};
            wire [9:0] rise_payload = {tx_valid, tx_valid && rise_mask, rise_byte};
            wire [9:0] edge_payload;

            ddr_edge_out #(.WIDTH(10)) tx_edge (
                .clk(ck90), .rst(rst), .fall_d(fall_payload),
                .rise_d(rise_payload), .q(edge_payload)
            );
            assign dq_o[8*lane +: 8] = edge_payload[7:0];
            assign dm[lane] = edge_payload[8] && edge_payload[9];
            assign dq_oe[lane] = edge_payload[9];
        end
    endgenerate

    // One output-strobe domain per byte lane. Adjacent bursts merge.
    reg [LANES-1:0] strobe_next, strobe_prev;
    generate
        for (lane = 0; lane < LANES; lane = lane + 1) begin : g_tx_dqs
            always @(posedge pad_ck_n or posedge rst) begin
                if (rst)          strobe_next[lane] <= 1'b0;
                else if (sys_clk) strobe_next[lane] <= tx_valid;
            end
            always @(posedge ck or posedge rst) begin
                if (rst) strobe_prev[lane] <= 1'b0;
                else     strobe_prev[lane] <= strobe_next[lane];
            end
            assign dqs_o[lane]  = ck && strobe_next[lane];
            assign dqs_oe[lane] = strobe_next[lane] || (!ck && strobe_prev[lane]);
        end
    endgenerate

    // A four-slot, timed source-synchronous crossing. A frame slot is cleared
    // whenever spare, including windows with no DQS edges, so wrap can never
    // alias stale good/count state into a later read.
    reg [1:0] read_pipe, probe_pipe;
    reg capture_frame, capture_probe, return_due, return_probe;
    reg [CAPTURE_SLOT_BITS-1:0] next_slot, capture_slot, return_slot;
    reg [CAPTURE_SLOTS-1:0] slot_busy;
    localparam [CAPTURE_SLOTS-1:0] SLOT_ONE =
        {{(CAPTURE_SLOTS-1){1'b0}}, 1'b1};
    wire [CAPTURE_SLOTS-1:0] capture_slots =
        capture_frame ? (SLOT_ONE << capture_slot) : {CAPTURE_SLOTS{1'b0}};
    wire [CAPTURE_SLOTS-1:0] clear_slots = ~slot_busy;
    wire [CAPTURE_SLOTS-1:0] allocate_slots =
        read_pipe[1] ? (SLOT_ONE << next_slot) : {CAPTURE_SLOTS{1'b0}};
    wire [CAPTURE_SLOTS-1:0] release_slots =
        return_due ? (SLOT_ONE << return_slot) : {CAPTURE_SLOTS{1'b0}};
    wire [4*DQ_WIDTH-1:0] rx_words;
    wire [LANES-1:0] rx_good;

    ddr_read_capture #(
        .LANES(LANES), .SLOTS(CAPTURE_SLOTS)
    ) rx_capture (
        .rst(rst), .dqs_capture(dqs_capture), .dq_i(dq_i),
        .capture(capture_slots), .clear_slot(clear_slots),
        .return_slot(return_slot), .word(rx_words), .good(rx_good)
    );

    always @(posedge sys_clk or posedge rst) begin
        if (rst) begin
            read_pipe <= '0;
            probe_pipe <= '0;
            capture_frame <= 1'b0;
            capture_probe <= 1'b0;
            return_due <= 1'b0;
            return_probe <= 1'b0;
            next_slot <= '0;
            capture_slot <= '0;
            return_slot <= '0;
            slot_busy <= '0;
            dfi_rddata <= '0;
            dfi_rddata_valid <= '0;
            read_frame_done <= 1'b0;
            read_frame_good <= '0;
            read_frame_data <= '0;
            read_error <= 1'b0;
        end else begin
            read_pipe <= {read_pipe[0], do_read};
            probe_pipe <= {probe_pipe[0], do_read && probe_mode};
            capture_frame <= read_pipe[1];
            if (read_pipe[1]) begin
                capture_slot <= next_slot;
                capture_probe <= probe_pipe[1];
                next_slot <= next_slot + 1'b1;
            end
            return_due <= capture_frame;
            if (capture_frame) begin
                return_slot <= capture_slot;
                return_probe <= capture_probe;
            end
            slot_busy <= (slot_busy & ~release_slots) | allocate_slots;

            dfi_rddata_valid <= '0;
            read_frame_done <= 1'b0;
            if (return_due) begin
                read_frame_done <= 1'b1;
                read_frame_good <= rx_good;
                read_frame_data <= rx_words;
                if ((&rx_good) && !read_error) begin
                    dfi_rddata <= rx_words;
                    dfi_rddata_valid <= 2'b11;
                end else if (!return_probe) begin
                    read_error <= 1'b1;
                end
            end
        end
    end
endmodule
`default_nettype wire
