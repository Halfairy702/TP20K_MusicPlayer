//=============================================================================
// top.v  -  Tang Primer 20K "Music Player"  (v1)
//
//   Plays two melodies through the on-board PT8211 DAC / 3.5mm jack.
//
//   Board : Sipeed Tang Primer 20K  (GW2A-LV18PG256C8/I7) + Dock
//   Clock : 27 MHz  (pin H11)
//
//   Controls
//     S1 (T10) : reset          (active low, shared with FPGA_RST)
//     S2 (T3)  : next song      (active low, 1.5 V bank)
//     S3 (T2)  : play / pause   (active low, 1.5 V bank)
//     LED4 (L14) : blinks while playing, steady on when paused
//
//   Audio path
//     27 MHz -> pt8211_tx  BCK 1.5 MHz, frame rate 46.875 kHz
//     song ROM -> 24-bit phase increment -> DDS -> 256x16 sine LUT -> PT8211
//=============================================================================
`default_nettype none

module top (
    input  wire       clk,          // 27 MHz  (H11)
    input  wire       rst_n,        // S1      (T10, active low)
    input  wire       key_next,     // S2      (T3,  active low)
    input  wire       key_play,     // S3      (T2,  active low)

    output wire       hp_bck,       // N15
    output wire       hp_ws,        // P16
    output wire       hp_din,       // P15
    output wire       pa_en,        // R16  amplifier enable (active high)
    output wire       led           // L14  (active low on this board)
);

    //-------------------------------------------------------------------------
    // PT8211 transmitter: generates BCK/WS/DIN and one tick per audio frame.
    //-------------------------------------------------------------------------
    wire        sample_tick;
    wire [15:0] sample_l;
    wire [15:0] sample_r;

    pt8211_tx #(
        .CLK_DIV(18)                    // BCK = 27 MHz / 18 = 1.5 MHz
    ) u_pt8211 (
        .clk         (clk),
        .rst_n       (rst_n),
        .sample_l    (sample_l),
        .sample_r    (sample_r),
        .bck         (hp_bck),
        .ws          (hp_ws),
        .din         (hp_din),
        .sample_tick (sample_tick)
    );

    assign pa_en = 1'b1;                // speaker amp always on

    //-------------------------------------------------------------------------
    // Button debounce (10 ms) + single-cycle press pulses
    //-------------------------------------------------------------------------
    localparam integer DEB_MAX = 270_000;       // 27 MHz * 10 ms

    reg [19:0] deb_cnt_n, deb_cnt_p;
    reg        key_n_s, key_p_s;
    reg        press_next, press_play;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            deb_cnt_n <= 20'd0;
            deb_cnt_p <= 20'd0;
            key_n_s   <= 1'b1;      // idle high
            key_p_s   <= 1'b1;
            press_next <= 1'b0;
            press_play <= 1'b0;
        end
        else begin
            press_next <= 1'b0;
            press_play <= 1'b0;

            // ---- S2 : next song ----
            if (key_next != key_n_s) begin
                if (deb_cnt_n == DEB_MAX) begin
                    key_n_s    <= key_next;
                    deb_cnt_n  <= 20'd0;
                    if (key_next == 1'b0) press_next <= 1'b1;   // falling edge
                end
                else deb_cnt_n <= deb_cnt_n + 20'd1;
            end
            else deb_cnt_n <= 20'd0;

            // ---- S3 : play / pause ----
            if (key_play != key_p_s) begin
                if (deb_cnt_p == DEB_MAX) begin
                    key_p_s    <= key_play;
                    deb_cnt_p  <= 20'd0;
                    if (key_play == 1'b0) press_play <= 1'b1;
                end
                else deb_cnt_p <= deb_cnt_p + 20'd1;
            end
            else deb_cnt_p <= 20'd0;
        end
    end

    //-------------------------------------------------------------------------
    // Song sequencer
    //   Each ROM entry is {note[3:0], length_in_quarters[3:0]}
    //   note: 0=C4 1=D4 2=E4 3=F4 4=G4 5=A4 6=B4 7=C5 8=rest
    //-------------------------------------------------------------------------
    localparam [15:0] QUARTER = 16'd18_750;

    localparam [6:0] SONG1_START = 7'd0;
    localparam [6:0] SONG1_END   = 7'd42;
    localparam [6:0] SONG2_START = 7'd42;
    localparam [6:0] SONG2_END   = 7'd70;

    reg        song_sel;            // 0 = Twinkle, 1 = Ode to Joy
    reg [6:0]  ptr;
    reg [15:0] dur_cnt;
    reg [3:0]  cur_note;
    reg        playing;

    wire [6:0] song_start = song_sel ? SONG2_START : SONG1_START;
    wire [6:0] song_end   = song_sel ? SONG2_END   : SONG1_END;

    // ---- song ROM (combinational, 70 entries) ----
    reg [7:0] rom_q;
    always @(*) begin
        case (ptr)
            // ---- Twinkle Twinkle Little Star (42 notes) ----
            7'd0 : rom_q = 8'h01;  7'd1 : rom_q = 8'h01;
            7'd2 : rom_q = 8'h41;  7'd3 : rom_q = 8'h41;
            7'd4 : rom_q = 8'h51;  7'd5 : rom_q = 8'h51;
            7'd6 : rom_q = 8'h42;
            7'd7 : rom_q = 8'h31;  7'd8 : rom_q = 8'h31;
            7'd9 : rom_q = 8'h21;  7'd10: rom_q = 8'h21;
            7'd11: rom_q = 8'h11;  7'd12: rom_q = 8'h11;
            7'd13: rom_q = 8'h02;
            7'd14: rom_q = 8'h41;  7'd15: rom_q = 8'h41;
            7'd16: rom_q = 8'h31;  7'd17: rom_q = 8'h31;
            7'd18: rom_q = 8'h21;  7'd19: rom_q = 8'h21;
            7'd20: rom_q = 8'h12;
            7'd21: rom_q = 8'h41;  7'd22: rom_q = 8'h41;
            7'd23: rom_q = 8'h31;  7'd24: rom_q = 8'h31;
            7'd25: rom_q = 8'h21;  7'd26: rom_q = 8'h21;
            7'd27: rom_q = 8'h12;
            7'd28: rom_q = 8'h01;  7'd29: rom_q = 8'h01;
            7'd30: rom_q = 8'h41;  7'd31: rom_q = 8'h41;
            7'd32: rom_q = 8'h51;  7'd33: rom_q = 8'h51;
            7'd34: rom_q = 8'h42;
            7'd35: rom_q = 8'h31;  7'd36: rom_q = 8'h31;
            7'd37: rom_q = 8'h21;  7'd38: rom_q = 8'h21;
            7'd39: rom_q = 8'h11;  7'd40: rom_q = 8'h11;
            7'd41: rom_q = 8'h02;
            // ---- Ode to Joy (28 notes) ----
            7'd42: rom_q = 8'h21;  7'd43: rom_q = 8'h21;
            7'd44: rom_q = 8'h31;  7'd45: rom_q = 8'h41;
            7'd46: rom_q = 8'h41;  7'd47: rom_q = 8'h31;
            7'd48: rom_q = 8'h21;  7'd49: rom_q = 8'h11;
            7'd50: rom_q = 8'h01;  7'd51: rom_q = 8'h01;
            7'd52: rom_q = 8'h11;  7'd53: rom_q = 8'h21;
            7'd54: rom_q = 8'h21;  7'd55: rom_q = 8'h12;
            7'd56: rom_q = 8'h21;  7'd57: rom_q = 8'h21;
            7'd58: rom_q = 8'h31;  7'd59: rom_q = 8'h41;
            7'd60: rom_q = 8'h41;  7'd61: rom_q = 8'h31;
            7'd62: rom_q = 8'h21;  7'd63: rom_q = 8'h11;
            7'd64: rom_q = 8'h01;  7'd65: rom_q = 8'h01;
            7'd66: rom_q = 8'h11;  7'd67: rom_q = 8'h21;
            7'd68: rom_q = 8'h12;  7'd69: rom_q = 8'h02;
            default: rom_q = 8'h81;     // rest
        endcase
    end

    wire [3:0] rom_note = rom_q[7:4];
    wire [3:0] rom_len  = rom_q[3:0];

    // quarter-count -> frame-count, no multiplier
    wire [15:0] dur_frames =
        (rom_len == 4'd2) ? (16'd37_500 - 16'd1) :
        (rom_len == 4'd3) ? (16'd56_250 - 16'd1) :
                            (QUARTER - 16'd1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            song_sel <= 1'b0;
            ptr      <= SONG1_START;
            dur_cnt  <= 16'd0;
            cur_note <= 4'd8;           // rest
            playing  <= 1'b1;
        end
        else if (press_next) begin
            song_sel <= ~song_sel;
            ptr      <= song_sel ? SONG1_START : SONG2_START;
            dur_cnt  <= 16'd0;
            cur_note <= 4'd8;
        end
        else if (press_play) begin
            playing  <= ~playing;
        end
        else if (sample_tick && playing) begin
            if (dur_cnt == 16'd0) begin
                cur_note <= rom_note;
                dur_cnt  <= dur_frames;
                if (ptr == song_end - 7'd1) ptr <= song_start;
                else                        ptr <= ptr + 7'd1;
            end
            else begin
                dur_cnt <= dur_cnt - 16'd1;
            end
        end
    end

    //-------------------------------------------------------------------------
    // Note -> DDS phase increment
    //   inc = f_note * 2^24 / 46875
    //-------------------------------------------------------------------------
    function [23:0] note_inc;
        input [3:0] n;
        begin
            case (n)
                4'd0: note_inc = 24'd93_648;    // C4  261.63 Hz
                4'd1: note_inc = 24'd105_113;   // D4  293.66 Hz
                4'd2: note_inc = 24'd117_987;   // E4  329.63 Hz
                4'd3: note_inc = 24'd125_002;   // F4  349.23 Hz
                4'd4: note_inc = 24'd140_313;   // G4  392.00 Hz
                4'd5: note_inc = 24'd157_482;   // A4  440.00 Hz
                4'd6: note_inc = 24'd176_780;   // B4  493.88 Hz
                4'd7: note_inc = 24'd187_292;   // C5  523.25 Hz
                default: note_inc = 24'd0;      // rest
            endcase
        end
    endfunction

    reg [23:0] phase;
    wire [23:0] inc = note_inc(cur_note);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)       phase <= 24'd0;
        else if (sample_tick) phase <= phase + inc;
    end

    //-------------------------------------------------------------------------
    // Sine lookup
    //-------------------------------------------------------------------------
    wire signed [15:0] sine_q;

    sine_rom u_sine (
        .clk  (clk),
        .idx  (phase[23:16]),
        .data (sine_q)
    );

    wire [15:0] audio = playing ? sine_q : 16'sd0;

    assign sample_l = audio;
    assign sample_r = audio;

    //-------------------------------------------------------------------------
    // Status LED: slow blink while playing, steady ON (low) when paused
    //-------------------------------------------------------------------------
    reg [23:0] blink_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) blink_cnt <= 24'd0;
        else        blink_cnt <= blink_cnt + 24'd1;
    end

    assign led = playing ? blink_cnt[23] : 1'b0;

endmodule

`default_nettype wire
