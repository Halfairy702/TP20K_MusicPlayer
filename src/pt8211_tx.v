//=============================================================================
// pt8211_tx.v
//   PT8211 (16-bit LSB-justified / "Japanese format") transmitter.
//
//   Tang Primer 20K Dock has an on-board PT8211 -> LPA4809 amp -> 3.5mm jack.
//   Pins: HP_BCK=N15  HP_WS=P16  HP_DIN=P15  PA_EN=R16
//
//   Everything runs in ONE clock domain (27 MHz). The serial bit clock is
//   built with a phase counter, so there are no gated clocks and no CDC.
//
//   Timing with CLK_DIV = 18 (27 MHz input):
//       BCK  = 27 MHz / 18      = 1.5 MHz
//       WS   = BCK / 32         -> frame rate 46.875 kHz
//
//   Frame layout (32 BCK per frame, 16 bits per channel):
//       din changes on the BCK rising edge
//       left  word : MSB on the wire at bit_cnt 3, LSB at 18
//       right word : MSB on the wire at bit_cnt 19, LSB at 2 of the next frame
//       WS is low while the left word is on the wire, high for the right one
//       (matches the vendor demo that is proven on this board).
//=============================================================================
`default_nettype none

module pt8211_tx #(
    parameter integer CLK_DIV = 18          // BCK = clk / CLK_DIV  (must be even)
)(
    input  wire        clk,                 // 27 MHz
    input  wire        rst_n,               // active low

    input  wire [15:0] sample_l,            // two's complement
    input  wire [15:0] sample_r,

    output reg         bck,                 // HP_BCK
    output reg         ws,                  // HP_WS
    output reg         din,                 // HP_DIN

    output reg         sample_tick          // 1-clk pulse once per frame
);

    localparam integer HALF = CLK_DIV / 2;

    reg [4:0]   ph;                         // 0 .. CLK_DIV-1
    reg [4:0]   bit_cnt;                    // 0 .. 31  (5 bits: wraps at 32)
    reg [15:0]  shreg;

    //-------------------------------------------------------------------------
    // Phase counter: wraps every BCK period.
    //-------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)             ph <= 5'd0;
        else if (ph == CLK_DIV - 1) ph <= 5'd0;
        else                    ph <= ph + 5'd1;
    end

    // BCK: high for the first half of the phase, low for the second half.
    // BCK rises at the clock edge where ph == 0, falls where ph == HALF.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) bck <= 1'b0;
        else        bck <= (ph < HALF);
    end

    // Serial data changes on the BCK rising edge, exactly like the vendor
    // demo that is proven on this board with this DAC.
    wire bit_edge = (ph == 5'd0);           // true on the BCK rising edge

    //-------------------------------------------------------------------------
    // Serialiser + WS generator
    //-------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt     <= 5'd0;
            shreg       <= 16'd0;
            din         <= 1'b0;
            ws          <= 1'b0;
            sample_tick <= 1'b0;
        end
        else begin
            sample_tick <= 1'b0;

            if (bit_edge) begin
                bit_cnt <= bit_cnt + 5'd1;

                // Load a channel word so that its MSB lands on the wire at the
                // same BCK edge where WS changes (PT8211 latches from there).
                if (bit_cnt == 5'd3) begin
                    din   <= sample_l[15];
                    shreg <= {sample_l[14:0], 1'b0};
                end
                else if (bit_cnt == 5'd19) begin
                    din   <= sample_r[15];
                    shreg <= {sample_r[14:0], 1'b0};
                end
                else begin
                    din   <= shreg[15];
                    shreg <= {shreg[14:0], 1'b0};
                end

                // Word-select edges (vendor-demo offset).
                if (bit_cnt == 5'd3)  ws <= 1'b0;   // left
                if (bit_cnt == 5'd19) ws <= 1'b1;   // right

                // One tick per frame, one bit period before the left word
                // is loaded, so the synthesiser has time to settle.
                if (bit_cnt == 5'd31) sample_tick <= 1'b1;
            end
        end
    end

endmodule

`default_nettype wire
