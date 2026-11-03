// synth8.v - 8-voice polyphonic wavetable engine with a chord sequencer.
//
// Stage 1 of the competition instrument: proves polyphony, per-voice ADSR and
// multi-timbral output before the real touch/pressure front end exists.
// The sequencer plays a four-chord progression, each chord on a different
// wavetable bank, so the polyphony and the timbre switch are both audible.
`default_nettype none

module synth8 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sample_tick,
    input  wire        next_chord,      // 1-clk pulse, jump to next chord
    input  wire        pause_toggle,    // 1-clk pulse
    output wire [15:0] sample_l,
    output wire [15:0] sample_r,
    output wire        playing,
    output reg  [1:0]  chord_idx
);

    localparam [15:0] CHORD_PERIOD = 16'd46_875;    // 1 s at 46875 Hz
    localparam [5:0]  REST         = 6'd63;

    //-------------------------------------------------------------------------
    // Chord table
    //-------------------------------------------------------------------------
    function [5:0] note_of;
        input [1:0] c;
        input [3:0] v;
        begin
            case (c)
                // C major
                2'd0: case (v)
                    4'd0: note_of = 6'd12;   // C4
                    4'd1: note_of = 6'd16;   // E4
                    4'd2: note_of = 6'd19;   // G4
                    4'd3: note_of = 6'd24;   // C5
                    4'd4: note_of = 6'd28;   // E5
                    4'd5: note_of = 6'd31;   // G5
                    default: note_of = REST;
                endcase
                // A minor
                2'd1: case (v)
                    4'd0: note_of = 6'd9;    // A3
                    4'd1: note_of = 6'd12;   // C4
                    4'd2: note_of = 6'd16;   // E4
                    4'd3: note_of = 6'd21;   // A4
                    4'd4: note_of = 6'd24;   // C5
                    4'd5: note_of = 6'd28;   // E5
                    default: note_of = REST;
                endcase
                // F major
                2'd2: case (v)
                    4'd0: note_of = 6'd5;    // F3
                    4'd1: note_of = 6'd9;    // A3
                    4'd2: note_of = 6'd12;   // C4
                    4'd3: note_of = 6'd17;   // F4
                    4'd4: note_of = 6'd21;   // A4
                    4'd5: note_of = 6'd24;   // C5
                    default: note_of = REST;
                endcase
                // G major
                default: case (v)
                    4'd0: note_of = 6'd7;    // G3
                    4'd1: note_of = 6'd11;   // B3
                    4'd2: note_of = 6'd14;   // D4
                    4'd3: note_of = 6'd19;   // G4
                    4'd4: note_of = 6'd23;   // B4
                    4'd5: note_of = 6'd26;   // D5
                    default: note_of = REST;
                endcase
            endcase
        end
    endfunction

    function [1:0] bank_of;
        input [1:0] c;
        begin
            case (c)
                2'd0:    bank_of = 2'd1;        // guzheng
                2'd1:    bank_of = 2'd2;        // pipa
                2'd2:    bank_of = 2'd3;        // organ
                default: bank_of = 2'd1;
            endcase
        end
    endfunction

    //-------------------------------------------------------------------------
    // Sequencer: one chord change per CHORD_PERIOD samples
    //-------------------------------------------------------------------------
    reg [15:0] period_cnt;
    reg        go;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            period_cnt <= 16'd0;
            go         <= 1'b0;
        end
        else begin
            go <= 1'b0;
            if (sample_tick) begin
                if (period_cnt >= CHORD_PERIOD - 16'd1) begin
                    period_cnt <= 16'd0;
                    go         <= 1'b1;
                end
                else begin
                    period_cnt <= period_cnt + 16'd1;
                end
            end
            if (next_chord) begin
                period_cnt <= 16'd0;
                go         <= 1'b1;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) chord_idx <= 2'd3;
        else if (go) chord_idx <= chord_idx + 2'd1;
    end

    //-------------------------------------------------------------------------
    // Increment mailbox: eight lookups spread over eight clocks, so the
    // note-to-increment ROM only needs one instance.
    //-------------------------------------------------------------------------
    reg [23:0] inc_q [0:7];
    reg [7:0]  mask_q;
    reg        ld_busy;
    reg [3:0]  ld_cnt;
    reg        fire;

    wire [5:0]  ld_note = note_of(chord_idx, ld_cnt);
    wire [23:0] ld_inc;

    note_inc u_ld_inc (
        .note (ld_note),
        .inc  (ld_inc)
    );

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ld_busy <= 1'b0;
            ld_cnt  <= 4'd0;
            fire    <= 1'b0;
            mask_q  <= 8'd0;
            for (i = 0; i < 8; i = i + 1) inc_q[i] <= 24'd0;
        end
        else begin
            fire <= 1'b0;

            if (go) begin
                ld_busy <= 1'b1;
                ld_cnt  <= 4'd0;
            end
            else if (ld_busy) begin
                inc_q[ld_cnt]  <= ld_inc;
                mask_q[ld_cnt] <= (ld_note != REST);
                if (ld_cnt == 4'd7) begin
                    ld_busy <= 1'b0;
                    fire    <= 1'b1;
                end
                else begin
                    ld_cnt <= ld_cnt + 4'd1;
                end
            end
        end
    end

    //-------------------------------------------------------------------------
    // Eight voices
    //-------------------------------------------------------------------------
    wire signed [15:0] vout [0:7];
    wire [1:0] bank = bank_of(chord_idx);

    genvar g;
    generate
        for (g = 0; g < 8; g = g + 1) begin : VOICES
            voice u_voice (
                .clk         (clk),
                .rst_n       (rst_n),
                .sample_tick (sample_tick),
                .inc         (inc_q[g]),
                .bank        (bank),
                .trigger     (fire & mask_q[g]),
                .note_off    (fire & ~mask_q[g]),
                .out         (vout[g])
            );
        end
    endgenerate

    //-------------------------------------------------------------------------
    // Mixer with saturation
    //-------------------------------------------------------------------------
    reg        playing_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)         playing_r <= 1'b1;
        else if (pause_toggle) playing_r <= ~playing_r;
    end

    assign playing = playing_r;

    reg signed [20:0] mix;
    integer k;

    // Headroom check: 8 voices x 16384 peak >> 2 = 32768, so the sum can just
    // reach full scale and the saturator below covers the overshoot.
    always @(*) begin
        mix = 21'sd0;
        for (k = 0; k < 8; k = k + 1)
            mix = mix + (vout[k] >>> 2);
    end

    wire signed [20:0] mix_m = playing_r ? mix : 21'sd0;

    assign sample_l = (mix_m > 21'sd32767)  ? 16'sh7FFF :
                      (mix_m < -21'sd32768) ? 16'sh8000 :
                                              mix_m[15:0];
    assign sample_r = sample_l;

endmodule

`default_nettype wire
