"""
verify.py - bit-accurate model of TP20K_MusicPlayer

1) Simulates pt8211_tx.v cycle by cycle and reconstructs the serial words
   to prove the DAC receives exactly sample_l / sample_r.
2) Simulates the song sequencer + DDS and writes out.wav for listening.
"""

import math
import struct
import wave

FS = 27_000_000 / 18 / 32          # 46875 Hz

# ----------------------------------------------------------------------------
# 1) PT8211 transmitter model
# ----------------------------------------------------------------------------
def sim_pt8211(sample_l, sample_r, frames=3, clk_div=18):
    half = clk_div // 2
    ph = bck = bit_cnt = shreg = din = ws = 0
    bits = []
    ws_trace = []
    ticks = 0

    for _ in range(clk_div * 32 * frames + 64):
        bit_edge = (ph == 0)
        n_ph = 0 if ph == clk_div - 1 else ph + 1
        n_bck = 1 if ph < half else 0
        n_bit_cnt, n_shreg, n_din, n_ws = bit_cnt, shreg, din, ws

        if bit_edge:
            n_bit_cnt = (bit_cnt + 1) & 0x1F      # 5-bit counter, wraps at 32
            if bit_cnt == 0:
                n_din = (sample_l >> 15) & 1
                n_shreg = ((sample_l & 0x7FFF) << 1) & 0xFFFF
            elif bit_cnt == 16:
                n_din = (sample_r >> 15) & 1
                n_shreg = ((sample_r & 0x7FFF) << 1) & 0xFFFF
            else:
                n_din = (shreg >> 15) & 1
                n_shreg = (shreg << 1) & 0xFFFF
            if bit_cnt == 3:
                n_ws = 0
            if bit_cnt == 19:
                n_ws = 1
            if bit_cnt == 31:
                ticks += 1
            bits.append(n_din)
            ws_trace.append(n_ws)

        ph, bck, bit_cnt, shreg, din, ws = n_ph, n_bck, n_bit_cnt, n_shreg, n_din, n_ws

    return bits, ws_trace, ticks


def check_pt8211():
    sl, sr = 0xA55A, 0x3CC3         # distinctive patterns
    bits, ws_trace, ticks = sim_pt8211(sl, sr, frames=3)

    ok = True
    # first full frame starts at bit index 0
    for f in range(2):
        wl = 0
        wr = 0
        for i in range(16):
            wl = (wl << 1) | bits[f * 32 + i]
        for i in range(16):
            wr = (wr << 1) | bits[f * 32 + 16 + i]
        if wl != sl or wr != sr:
            ok = False
            print(f"  frame {f}: got L=0x{wl:04X} R=0x{wr:04X}, "
                  f"expected L=0x{sl:04X} R=0x{sr:04X}")
        else:
            print(f"  frame {f}: L=0x{wl:04X} R=0x{wr:04X}  OK")

    print(f"  frames produced: {ticks}, BCK period = {18} clk, "
          f"frame = 32 BCK, Fs = {FS:.2f} Hz")
    ws_left = sum(1 for w in ws_trace[:32] if w == 0)
    print(f"  WS low clocks in a frame: {ws_left}")
    return ok


# ----------------------------------------------------------------------------
# 2) Song + DDS model -> WAV
# ----------------------------------------------------------------------------
QUARTER = 18_750

NOTE_INC = {
    0: 93_648, 1: 105_113, 2: 117_987, 3: 125_002,
    4: 140_313, 5: 157_482, 6: 176_780, 7: 187_292,
}

# (note, length in quarters)
TWINKLE = [
    (0, 1), (0, 1), (4, 1), (4, 1), (5, 1), (5, 1), (4, 2),
    (3, 1), (3, 1), (2, 1), (2, 1), (1, 1), (1, 1), (0, 2),
    (4, 1), (4, 1), (3, 1), (3, 1), (2, 1), (2, 1), (1, 2),
    (4, 1), (4, 1), (3, 1), (3, 1), (2, 1), (2, 1), (1, 2),
    (0, 1), (0, 1), (4, 1), (4, 1), (5, 1), (5, 1), (4, 2),
    (3, 1), (3, 1), (2, 1), (2, 1), (1, 1), (1, 1), (0, 2),
]

ODE = [
    (2, 1), (2, 1), (3, 1), (4, 1), (4, 1), (3, 1), (2, 1), (1, 1),
    (0, 1), (0, 1), (1, 1), (2, 1), (2, 1), (1, 2),
    (2, 1), (2, 1), (3, 1), (4, 1), (4, 1), (3, 1), (2, 1), (1, 1),
    (0, 1), (0, 1), (1, 1), (2, 1), (1, 2), (0, 2),
]


def sine_table(n=256, amp=8192):
    return [int(round(amp * math.sin(2 * math.pi * i / n))) for i in range(n)]


def render(song, path):
    lut = sine_table()
    samples = []
    phase = 0

    for note, length in song:
        inc = NOTE_INC.get(note, 0)
        frames = QUARTER * length
        for _ in range(frames):
            samples.append(lut[(phase >> 16) & 0xFF])
            phase = (phase + inc) & 0xFFFFFF

    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(int(round(FS)))
        w.writeframes(b"".join(struct.pack("<h", s) for s in samples))

    print(f"  {path}: {len(samples)} frames = "
          f"{len(samples)/FS:.2f} s, peak={max(abs(s) for s in samples)}")


if __name__ == "__main__":
    print("[1] PT8211 serial verification")
    ok = check_pt8211()

    print("[2] Rendering melodies")
    render(TWINKLE, "twinkle.wav")
    render(ODE, "ode.wav")

    print("RESULT:", "PASS" if ok else "FAIL")
