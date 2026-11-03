//=============================================================================
// top.v  -  Tang Primer 20K polyphonic synthesizer
//
//   Board : Sipeed Tang Primer 20K  (GW2A-LV18PG256C8/I7) + Dock
//   Clock : 27 MHz  (pin H11)
//
//   Engine : synth8 - eight parallel wavetable voices, per-voice ADSR.
//
//   Controls
//     S0 (T10) : reset                  (active low)
//     S1..S4   : play notes             (C4 / E4 / G4 / C5, active low)
//     LED4 (L14): slow blink while playing
//
//   This Dock revision has no DIP switch bank, so the timbre is fixed to the
//   sine table and the eight-voice chord sequencer is disabled.
//
//   Audio path
//     27 MHz -> pt8211_tx  BCK 1.5 MHz, frame rate 46.875 kHz
//     synth8 -> PT8211 DAC -> LPA4809 -> 3.5 mm jack J10
//=============================================================================
`default_nettype none

module top (
    input  wire       clk,          // 27 MHz  (H11)
    input  wire       rst_n,        // S1      (T10, active low)

    input  wire [3:0] key_in,       // S2..S5  (active low, 1.5 V bank)

    output wire       hp_bck,       // N15
    output wire       hp_ws,        // P16
    output wire       hp_din,       // P15
    output wire       pa_en,        // R16  amplifier enable (active high)
    output wire       led           // L14  (active low on this board)
);

    // This Dock has no DIP switch bank: the pins that would read it float, so
    // the timbre was being picked at random and often landed on a harsh table.
    // Fixed to the sine bank, the cleanest of the four.
    wire       demo_en   = 1'b0;
    wire [1:0] timbre    = 2'b00;
    wire       octave_up = 1'b0;

    //-------------------------------------------------------------------------
    // PT8211 transmitter
    //-------------------------------------------------------------------------
    wire        sample_tick;
    wire [15:0] sample_l;
    wire [15:0] sample_r;

    pt8211_tx #(
        .CLK_DIV(18)
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

    //-------------------------------------------------------------------------
    // Key debounce (10 ms) -> press / release pulses
    //-------------------------------------------------------------------------
    localparam integer DEB_MAX = 270_000;       // 27 MHz * 10 ms

    // One key input on this board idles low, which would otherwise look like a
    // permanently held key. Sample the pins shortly after configuration and
    // treat anything already low as released.
    reg [3:0]  stuck;
    reg [21:0] boot_cnt;
    localparam [21:0] BOOT_MAX = 22'd800_000;   // ~30 ms after configuration

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            boot_cnt <= 22'd0;
            stuck    <= 4'd0;
        end
        else if (boot_cnt != BOOT_MAX) begin
            boot_cnt <= boot_cnt + 22'd1;
            if (boot_cnt == BOOT_MAX - 22'd1) stuck <= ~key_in;
        end
    end

    wire [3:0] key_eff = key_in | stuck;
    wire       boot_done = (boot_cnt == BOOT_MAX);

    reg [19:0] deb_cnt [0:3];
    reg        key_s   [0:3];
    reg [3:0]  press, rel;
    reg [3:0]  held;

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 4; i = i + 1) begin
                deb_cnt[i] <= 20'd0;
                key_s[i]   <= 1'b1;         // idle high
            end
            press <= 4'd0;
            rel   <= 4'd0;
            held  <= 4'd0;
        end
        else begin
            press <= 4'd0;
            rel   <= 4'd0;

            if (!boot_done) begin
                for (i = 0; i < 4; i = i + 1) begin
                    key_s[i]   <= key_eff[i];
                    deb_cnt[i] <= 20'd0;
                end
            end
            else begin
                for (i = 0; i < 4; i = i + 1) begin
                    if (key_eff[i] != key_s[i]) begin
                        if (deb_cnt[i] == DEB_MAX) begin
                            key_s[i]   <= key_eff[i];
                            deb_cnt[i] <= 20'd0;
                            if (key_eff[i] == 1'b0) press[i] <= 1'b1;
                            else                    rel[i]   <= 1'b1;
                        end
                        else deb_cnt[i] <= deb_cnt[i] + 20'd1;
                    end
                    else deb_cnt[i] <= 20'd0;
                end
            end

            held <= {~key_s[3], ~key_s[2], ~key_s[1], ~key_s[0]};
        end
    end

    //-------------------------------------------------------------------------
    // Synthesiser
    //-------------------------------------------------------------------------
    wire playing;
    wire any_active;

    synth8 u_synth (
        .clk          (clk),
        .rst_n        (rst_n),
        .sample_tick  (sample_tick),
        .next_chord   (demo_en ? press[0] : 1'b0),
        .pause_toggle (demo_en ? press[1] : 1'b0),
        .key_press    (press),
        .key_release  (rel),
        .timbre       (timbre),
        .octave_up    (octave_up),
        .demo_en      (demo_en),
        .sample_l     (sample_l),
        .sample_r     (sample_r),
        .playing      (playing),
        .any_active   (any_active),
        .chord_idx    ()
    );

    // The amp is the dominant noise source on this board: keep it enabled only
    // while an envelope is running, plus a ~40 ms hold-off so note gaps and the
    // amp's own enable delay cannot chop the attack.
    reg [19:0] pa_hold;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)                pa_hold <= 20'd0;
        else if (any_active)       pa_hold <= 20'hFFFFF;
        else if (pa_hold != 20'd0) pa_hold <= pa_hold - 20'd1;
    end

    assign pa_en = any_active | (pa_hold != 20'd0);

    //-------------------------------------------------------------------------
    // Status LED: slow blink while playing, steady on when paused
    //-------------------------------------------------------------------------
    reg [23:0] blink_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) blink_cnt <= 24'd0;
        else        blink_cnt <= blink_cnt + 24'd1;
    end

    // LED4 is active low: lit steady while a key is held, slow blink while the
    // demo plays, steady on when paused.
    assign led = (|held) ? 1'b0 : (playing ? blink_cnt[23] : 1'b0);

endmodule

`default_nettype wire
