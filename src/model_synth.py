"""Bit-accurate model of synth8.v, rendered to WAV for offline listening.

Run from the project root:  python src/model_synth.py
Output: sim/synth8.wav  (46875 Hz, 16-bit, mono)

Mirrors the RTL arithmetic exactly, including the prod[30:15] truncation and
the 8-voice mixer saturation, so anything heard here is in the FPGA design.
"""

import math
import os
import struct

FS = 46875
N_TABLE = 256
SCALE = 16384
ATT_SHIFT, DEC_SHIFT, REL_SHIFT, SUSTAIN = 9, 12, 13, 12000
CHORD_PERIOD = 46875

TIMBRES = {
    "sine":    [1.0],
    "guzheng": [1.0, 0.55, 0.34, 0.24, 0.17, 0.11, 0.07, 0.04],
    "pipa":    [1.0, 0.80, 0.62, 0.47, 0.34, 0.24, 0.16, 0.11, 0.07, 0.05, 0.03],
    "organ":   [1.0, 0.00, 0.36, 0.00, 0.22, 0.00, 0.15, 0.00, 0.11, 0.00, 0.07],
}
ORDER = ["sine", "guzheng", "pipa", "organ"]

CHORDS = [
    ([12, 16, 19, 24, 28, 31], 1),
    ([9, 12, 16, 21, 24, 28], 2),
    ([5, 9, 12, 17, 21, 24], 3),
    ([7, 11, 14, 19, 23, 26], 1),
]
REST = 63


def build_table(amps):
    raw = []
    for i in range(N_TABLE):
        ph = 2.0 * math.pi * i / N_TABLE
        raw.append(sum(a * math.sin(k * ph) for k, a in enumerate(amps, start=1)))
    peak = max(abs(x) for x in raw)
    return [int(round(x / peak * SCALE)) for x in raw]


TABLES = [build_table(TIMBRES[n]) for n in ORDER]
NOTE_INC = [int(round(440.0 * 2 ** ((48 + n - 69) / 12.0) * (1 << 24) / FS)) for n in range(36)]


def trunc15(v):
    """Replicate prod[30:15]: arithmetic shift right by 15, truncated."""
    return v >> 15


class Voice:
    def __init__(self):
        self.phase = 0
        self.inc = 0
        self.env = 0
        self.state = 0      # 0 idle, 1 atk, 2 dec, 3 sus, 4 rel

    def tick(self, table):
        self.phase = (self.phase + self.inc) & 0xFFFFFF
        e = self.env
        if self.state == 1:
            e = e + ((32767 - e) >> ATT_SHIFT) + 1
            if e > 0xFFFF:
                e = 0xFFFF
            if e >= 32000:
                self.state = 2
        elif self.state == 2:
            if e > SUSTAIN:
                e = e - ((e - SUSTAIN) >> DEC_SHIFT) - 1
            else:
                e = SUSTAIN
                self.state = 3
        elif self.state == 3:
            e = SUSTAIN
        elif self.state == 4:
            if e > 8:
                e = e - (e >> REL_SHIFT) - 1
            else:
                e = 0
                self.state = 0
        self.env = e & 0xFFFF
        wave = table[(self.phase >> 16) & 0xFF]
        return trunc15(wave * self.env)


def render(seconds=4.0):
    voices = [Voice() for _ in range(8)]
    out = []
    n_samples = int(FS * seconds)
    chord_i = 3
    period = 0

    for _ in range(n_samples):
        if period >= CHORD_PERIOD - 1:
            period = 0
            chord_i = (chord_i + 1) % 4
            notes, bank = CHORDS[chord_i]
            for v in range(8):
                if v < len(notes):
                    voices[v].inc = NOTE_INC[notes[v]]
                    voices[v].state = 1          # trigger
                else:
                    if voices[v].state != 0:
                        voices[v].state = 4      # note_off
        else:
            period += 1

        _, bank = CHORDS[chord_i]
        table = TABLES[bank]

        mix = 0
        for v in voices:
            mix += v.tick(table) >> 2
        if mix > 32767:
            mix = 32767
        elif mix < -32768:
            mix = -32768
        out.append(mix)
    return out


def main():
    data = render(4.0)
    peak = max(abs(x) for x in data)
    clipped = sum(1 for x in data if abs(x) >= 32767)
    rms = math.sqrt(sum(x * x for x in data) / len(data))
    jumps = [abs(data[i] - data[i - 1]) for i in range(1, len(data))]
    print(f"samples      : {len(data)}")
    print(f"peak         : {peak}  ({peak/32768*100:.1f}% full scale)")
    print(f"rms          : {rms:.0f}")
    print(f"clipped      : {clipped} samples")
    print(f"max step     : {max(jumps)}   (full-scale step = 65535)")

    here = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(here, "..", "sim", "synth8.wav")
    with open(path, "wb") as f:
        f.write(b"RIFF")
        f.write(struct.pack("<I", 36 + len(data) * 2))
        f.write(b"WAVEfmt ")
        f.write(struct.pack("<IHHIIHH", 16, 1, 1, FS, FS * 2, 2, 16))
        f.write(b"data")
        f.write(struct.pack("<I", len(data) * 2))
        f.write(struct.pack(f"<{len(data)}h", *data))
    print(f"written      : {os.path.normpath(path)}")


if __name__ == "__main__":
    main()
