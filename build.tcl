set_device -name GW2A-18C GW2A-LV18PG256C8/I7

add_file src/top.v
add_file src/pt8211_tx.v
add_file src/synth8.v
add_file src/voice.v
add_file src/adsr.v
add_file src/wavetable_rom.v
add_file src/note_inc.v
add_file src/top.cst
add_file src/top.sdc

set_option -top_module top
set_option -output_base_name top

# T10 (S1 / reset) is an SSPI configuration pin on this board.
set_option -use_sspi_as_gpio 1

run all
