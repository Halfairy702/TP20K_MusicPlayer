// adsr.v - exponential ADSR envelope, one instance per voice.
//
// Every stage is an exponential approach to its target, which is close to how
// a real string loses energy. Time constants are set by the SHIFT parameters
// (tau = 2^SHIFT samples at 46875 Hz).
`default_nettype none

module adsr #(
    parameter integer ATT_SHIFT = 9,        // tau ~ 11 ms
    parameter integer DEC_SHIFT = 12,       // tau ~ 87 ms
    parameter integer REL_SHIFT = 13,       // tau ~ 175 ms
    parameter [15:0]  SUSTAIN   = 16'd12000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sample_tick,
    input  wire        trigger,             // 1-clk pulse
    input  wire        note_off,            // 1-clk pulse
    output reg  [15:0] env,
    output wire        active
);

    localparam [2:0] S_IDLE = 3'd0, S_ATK = 3'd1, S_DEC = 3'd2,
                     S_SUS  = 3'd3, S_REL = 3'd4;

    reg [2:0] state;

    assign active = (state != S_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            env   <= 16'd0;
        end
        else if (trigger) begin
            state <= S_ATK;
        end
        else if (note_off) begin
            state <= (state == S_IDLE) ? S_IDLE : S_REL;
        end
        else if (sample_tick) begin
            case (state)
                S_IDLE: env <= 16'd0;

                S_ATK: begin
                    env <= env + ((16'd32767 - env) >> ATT_SHIFT) + 16'd1;
                    if (env >= 16'd32000) state <= S_DEC;
                end

                S_DEC: begin
                    if (env > SUSTAIN) begin
                        env <= env - ((env - SUSTAIN) >> DEC_SHIFT) - 16'd1;
                    end
                    else begin
                        env   <= SUSTAIN;
                        state <= S_SUS;
                    end
                end

                S_SUS: env <= SUSTAIN;

                S_REL: begin
                    if (env > 16'd8)
                        env <= env - (env >> REL_SHIFT) - 16'd1;
                    else begin
                        env   <= 16'd0;
                        state <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
