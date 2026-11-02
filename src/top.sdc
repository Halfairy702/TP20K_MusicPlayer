// 27 MHz system clock, 37.037 ns period
create_clock -name clk -period 37.037 -waveform {0 18.518} [get_ports {clk}]

// Audio pins are static-rate outputs; no special timing constraints required.
