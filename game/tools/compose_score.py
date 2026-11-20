#!/usr/bin/env python3
"""Original ZONE TRADER score draft. Deterministic, no downloaded audio or dependencies.
Generate synchronized stereo PCM stems. The four-bar intro plays once; the
32-bar core loops at exactly the same sample offsets in all three stems.
"""
from array import array
from functools import lru_cache
from pathlib import Path
import math
import sys
import wave

RATE = 24000
BEAT = 20000  # 72 BPM
BAR = 4 * BEAT
INTRO = 4 * BAR
FRAMES = 36 * BAR
NAMES = ("theme", "low", "texture")
DEST = Path(__file__).resolve().parents[1] / "assets/audio/generated"
# Dm(add9), Bbmaj7, F(add9), C(sus2), Gm, Bb, Dm, Asus4.
CHORDS = [(50,57,64,65), (46,53,57,62), (41,48,55,57), (48,55,62,67),
          (43,50,58,62), (46,53,60,62), (50,57,64,65), (45,52,57,62)]
# Original sparse melodic phrases, with small variations across 32 bars.
PHRASES = [[(0,69,1.3),(2.5,65,1.2)], [(1,64,1.4)], [(0,62,2.1)],
           [(2,67,1.3)], [(0,65,1.2),(2,62,1.3)], [(1,69,1.4)],
           [(0,64,1.4),(2,65,1.3)], [(1,62,2.3)]]

@lru_cache(maxsize=128)
def note(midi, beats, timbre):
    n = int(beats * BEAT)
    f = 440 * 2 ** ((midi - 69) / 12)
    omega = 2 * math.pi * f / RATE
    result = array("f")
    for i in range(n):
        t = i / RATE
        x = omega * i
        if timbre == 0:
            attack = min(1.0, i / 240)
            env = attack * math.exp(-2.1*t) * min(1.0, (n-1-i)/1200)
            value = (math.sin(x) + .28*math.sin(2*x) + .11*math.sin(3.002*x))*env
        else:
            env = min(1.0, i/9600, (n-1-i)/9600)
            value = (math.sin(x)+.14*math.sin(2*x+.1)) * env
            if timbre == 2:
                value = (math.sin(x)+.35*math.sin(1.004*x)+.10*math.sin(2*x))*env
        result.append(value)
    return result

def render(stem):
    left = array("f", [0.0])*FRAMES
    right = array("f", [0.0])*FRAMES
    def add(bar, beat, midi, duration, gain, pan=0.0):
        start = bar*BAR + round(beat*BEAT)
        sound = note(midi, duration, stem)
        gl, gr = gain*(1-pan*.35), gain*(1+pan*.35)
        for i in range(min(len(sound), FRAMES-start)):
            left[start+i] += gl*sound[i]
            right[start+i] += gr*sound[i]
    for bar in range(36):
        core = bar-4
        phrase = core % 8 if core >= 0 else bar
        section = max(0, core)//8
        chord = CHORDS[phrase]
        if stem == 0:
            add(bar, 0, chord[0]+12, 1.8, .10, -.3)
            if bar % 2 == 0:
                add(bar, 2, chord[1]+12, 1.6, .07, .2)
            if core >= 0:
                for beat, midi, dur in PHRASES[phrase]:
                    if section == 1 and phrase % 2: continue
                    if section == 2 and phrase in (1,5): midi += 2
                    add(bar, beat, midi, dur, .14, .18)
        elif stem == 1:
            if bar >= 4:
                add(bar, 0, chord[0]-12, 3.95, .09 if section else .055, -.14)
                add(bar, 0, chord[1]-12, 3.95, .035, .18)
        else:
            if bar >= 4:
                gain = .035 if section == 2 else .018
                add(bar, 0, chord[2], 3.95, gain, -.42)
                add(bar, 0, chord[3], 3.95, gain, .42)
    pcm = array("h")
    peak = 0
    # Both sides of the loop boundary are quiet. Preserve the exact frame length.
    for i in range(FRAMES):
        edge = min(1.0,i/480,(FRAMES-1-i)/480)
        if abs(i-INTRO) < 480:
            edge = min(edge,abs(i-INTRO)/480)
        for buf in (left,right):
            sample = round(buf[i]*edge*32767)
            if abs(sample) > 30000:
                raise ValueError("score clipping/headroom")
            peak = max(peak,abs(sample))
            pcm.append(sample)
    if sys.byteorder != "little":
        pcm.byteswap()
    path = DEST / (NAMES[stem]+".wav")
    temp = path.with_suffix(".tmp")
    with wave.open(str(temp),"wb") as out:
        out.setnchannels(2); out.setsampwidth(2); out.setframerate(RATE)
        out.writeframes(pcm.tobytes())
    temp.replace(path)
    print("ZT_OST_STEM", NAMES[stem], FRAMES, "loop", INTRO, FRAMES, "peak", peak)

def prepare():
    DEST.mkdir(parents=True, exist_ok=True)
    for i in range(3):
        # Rebuild from the editable score on every preparation, avoiding stale media.
        render(i)
    note.cache_clear()

if __name__ == "__main__":
    prepare()
