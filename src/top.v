//=============================================================================
// top.v  -  Tang Primer 20K polyphonic synthesizer (stage 1)
//
//   Board : Sipeed Tang Primer 20K  (GW2A-LV18PG256C8/I7) + Dock
//   Clock : 27 MHz  (pin H11)
//
//   Engine : synth8 - eight parallel wavetable voices, per-voice ADSR,
//            four-chord progression, one wavetable bank per chord.
//
//   Controls
//     S1 (T10) : reset          (active low)
//     S2 (T3)  : next chord     (active low, 1.5 V bank)
//     S3 (T2)  : play / pause   (active low, 1.5 V bank)
//     LED4 (L14): blinks while playing, steady on when paused
//
//   Audio path
//     27 MHz -> pt8211_tx  BCK 1.5 MHz, frame rate 46.875 kHz
//     synth8 -> PT8211 DAC -> LPA4809 -> 3.5 mm jack J10
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

    // PA_EN is driven from `playing` further down, once the engine exists.

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

            // ---- S2 : next chord ----
            if (key_next != key_n_s) begin
                if (deb_cnt_n == DEB_MAX) begin
                    key_n_s    <= key_next;
                    deb_cnt_n  <= 20'd0;
                    if (key_next == 1'b0) press_next <= 1'b1;
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
    // Synthesiser
    //-------------------------------------------------------------------------
    wire playing;

    synth8 u_synth (
        .clk          (clk),
        .rst_n        (rst_n),
        .sample_tick  (sample_tick),
        .next_chord   (press_next),
        .pause_toggle (press_play),
        .sample_l     (sample_l),
        .sample_r     (sample_r),
        .playing      (playing),
        .chord_idx    ()
    );

    // The amp is the dominant noise source on this board, so mute it while the
    // engine is paused instead of leaving it amplifying its own noise floor.
    assign pa_en = playing;

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
