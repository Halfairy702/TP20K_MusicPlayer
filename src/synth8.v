// synth8.v - 8-voice polyphonic wavetable engine, two control modes.
//
//   demo_en = 0 : four-key instrument. S2..S5 drive four voices directly, so
//                 chords are just multiple keys held down. SW3/SW4 pick the
//                 wavetable, SW5 transposes an octave.
//   demo_en = 1 : automatic four-chord progression, one wavetable per chord,
//                 used as a self-test and for the video recording.
`default_nettype none

module synth8 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sample_tick,

    input  wire        next_chord,      // 1-clk pulse
    input  wire        pause_toggle,    // 1-clk pulse

    input  wire [3:0]  key_press,       // 1-clk pulses, one per key
    input  wire [3:0]  key_release,     // 1-clk pulses
    input  wire [1:0]  timbre,          // manual mode wavetable select
    input  wire        octave_up,       // manual mode +1 octave
    input  wire        demo_en,         // 1 = chord sequencer, 0 = keys

    output wire [15:0] sample_l,
    output wire [15:0] sample_r,
    output wire        playing,
    output wire        any_active,      // at least one envelope is running
    output reg  [1:0]  chord_idx
);

    localparam [15:0] CHORD_PERIOD = 16'd46_875;    // 1 s at 46875 Hz
    localparam [5:0]  REST         = 6'd63;

    //-------------------------------------------------------------------------
    // Demo chord table
    //-------------------------------------------------------------------------
    function [5:0] note_of;
        input [1:0] c;
        input [3:0] v;
        begin
            case (c)
                2'd0: case (v)                    // C major
                    4'd0: note_of = 6'd12;   4'd1: note_of = 6'd16;
                    4'd2: note_of = 6'd19;   4'd3: note_of = 6'd24;
                    4'd4: note_of = 6'd28;   4'd5: note_of = 6'd31;
                    default: note_of = REST;
                endcase
                2'd1: case (v)                    // A minor
                    4'd0: note_of = 6'd9;    4'd1: note_of = 6'd12;
                    4'd2: note_of = 6'd16;   4'd3: note_of = 6'd21;
                    4'd4: note_of = 6'd24;   4'd5: note_of = 6'd28;
                    default: note_of = REST;
                endcase
                2'd2: case (v)                    // F major
                    4'd0: note_of = 6'd5;    4'd1: note_of = 6'd9;
                    4'd2: note_of = 6'd12;   4'd3: note_of = 6'd17;
                    4'd4: note_of = 6'd21;   4'd5: note_of = 6'd24;
                    default: note_of = REST;
                endcase
                default: case (v)                 // G major
                    4'd0: note_of = 6'd7;    4'd1: note_of = 6'd11;
                    4'd2: note_of = 6'd14;   4'd3: note_of = 6'd19;
                    4'd4: note_of = 6'd23;   4'd5: note_of = 6'd26;
                    default: note_of = REST;
                endcase
            endcase
        end
    endfunction

    function [1:0] bank_of;
        input [1:0] c;
        begin
            case (c)
                2'd0:    bank_of = 2'd1;
                2'd1:    bank_of = 2'd2;
                2'd2:    bank_of = 2'd3;
                default: bank_of = 2'd1;
            endcase
        end
    endfunction

    //-------------------------------------------------------------------------
    // Demo sequencer
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
            if (sample_tick && demo_en) begin
                if (period_cnt >= CHORD_PERIOD - 16'd1) begin
                    period_cnt <= 16'd0;
                    go         <= 1'b1;
                end
                else begin
                    period_cnt <= period_cnt + 16'd1;
                end
            end
            if (next_chord && demo_en) begin
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
    // Demo increment mailbox: eight lookups spread over eight clocks
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
    // Manual keyboard: S2..S5 -> C4 E4 G4 C5, optional +1 octave
    //-------------------------------------------------------------------------
    wire [5:0] k_note0 = octave_up ? 6'd24 : 6'd12;
    wire [5:0] k_note1 = octave_up ? 6'd28 : 6'd16;
    wire [5:0] k_note2 = octave_up ? 6'd31 : 6'd19;
    wire [5:0] k_note3 = octave_up ? 6'd36 : 6'd24;

    wire [23:0] k_inc [0:3];

    note_inc u_k0 (.note (k_note0), .inc (k_inc[0]));
    note_inc u_k1 (.note (k_note1), .inc (k_inc[1]));
    note_inc u_k2 (.note (k_note2), .inc (k_inc[2]));
    note_inc u_k3 (.note (k_note3), .inc (k_inc[3]));

    //-------------------------------------------------------------------------
    // Per-voice control mux
    //-------------------------------------------------------------------------
    reg demo_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) demo_d <= 1'b0;
        else        demo_d <= demo_en;
    end
    wire mode_chg = demo_en ^ demo_d;

    wire [23:0] vinc  [0:7];
    wire [7:0]  vtrig;
    wire [7:0]  voff;

    genvar g;
    generate
        for (g = 0; g < 8; g = g + 1) begin : CTRL
            if (g < 4) begin : KEYED
                assign vinc[g]   = demo_en ? inc_q[g] : k_inc[g];
                assign vtrig[g]  = demo_en ? (fire & mask_q[g]) : key_press[g];
                // mode_chg releases the demo voices left over from the previous
                // mode, but must not cancel the key press that caused it.
                assign voff[g]   = demo_en ? (fire & ~mask_q[g])
                                           : (key_release[g] |
                                              (mode_chg & ~key_press[g]));
            end
            else begin : SPARE
                assign vinc[g]   = demo_en ? inc_q[g] : 24'd0;
                assign vtrig[g]  = demo_en ? (fire & mask_q[g]) : 1'b0;
                assign voff[g]   = demo_en ? (fire & ~mask_q[g]) : mode_chg;
            end
        end
    endgenerate

    wire [1:0] vbank = demo_en ? bank_of(chord_idx) : timbre;

    //-------------------------------------------------------------------------
    // Eight voices
    //-------------------------------------------------------------------------
    wire signed [15:0] vout [0:7];
    wire [7:0]         vbusy;

    assign any_active = |vbusy;

    generate
        for (g = 0; g < 8; g = g + 1) begin : VOICES
            voice u_voice (
                .clk         (clk),
                .rst_n       (rst_n),
                .sample_tick (sample_tick),
                .inc         (vinc[g]),
                .bank        (vbank),
                .trigger     (vtrig[g]),
                .note_off    (voff[g]),
                .busy        (vbusy[g]),
                .out         (vout[g])
            );
        end
    endgenerate

    //-------------------------------------------------------------------------
    // Mixer with saturation
    //-------------------------------------------------------------------------
    reg        playing_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)            playing_r <= 1'b1;
        else if (pause_toggle) playing_r <= ~playing_r;
    end

    assign playing = playing_r;

    reg signed [20:0] mix;
    integer k;

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
