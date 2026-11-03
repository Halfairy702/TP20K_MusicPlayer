// voice.v - one polyphonic voice: phase accumulator + wavetable + ADSR.
//
// The wavetable ROM has one clock of latency, so the envelope multiply runs one
// stage behind; at 46875 Hz the resulting sub-sample skew is inaudible.
`default_nettype none

module voice (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sample_tick,
    input  wire [23:0] inc,             // phase increment for the current note
    input  wire [1:0]  bank,            // wavetable bank
    input  wire        trigger,         // 1-clk pulse
    input  wire        note_off,        // 1-clk pulse
    output reg  signed [15:0] out
);

    reg [23:0] phase;
    reg [1:0]  bank_r;
    wire [15:0] env;
    wire signed [15:0] wave;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase  <= 24'd0;
            bank_r <= 2'd0;
        end
        else if (sample_tick) begin
            phase  <= phase + inc;
            bank_r <= bank;
        end
    end

    adsr u_adsr (
        .clk         (clk),
        .rst_n       (rst_n),
        .sample_tick (sample_tick),
        .trigger     (trigger),
        .note_off    (note_off),
        .env         (env),
        .active      ()
    );

    wavetable_rom u_rom (
        .clk  (clk),
        .bank (bank_r),
        .idx  (phase[23:16]),
        .data (wave)
    );

    reg signed [31:0] prod;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) prod <= 32'sd0;
        else        prod <= wave * $signed(env);
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) out <= 16'sd0;
        else        out <= prod[30:15];
    end

endmodule

`default_nettype wire
