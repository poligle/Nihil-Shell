#!/usr/bin/env python3
# sounds.py by poligle
#
# Synthesises the NIHIL interface sounds into sounds/nihil/*.ogg:
# short digital blips (sine with a touch of third harmonic), fast attack,
# exponential decay, nothing louder than -9 dBFS.
#
#   python3 tools/sounds.py [OUTDIR]     needs numpy and ffmpeg (libvorbis)

import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

RATE = 44100


def tone(freq, length, decay, attack=0.003, third=0.12, glide=0.0):
    """One blip. `glide` bends the pitch by that fraction over the note."""
    t = np.arange(int(RATE * length)) / RATE
    f = freq * (1 + glide * t / length)
    phase = 2 * np.pi * np.cumsum(f) / RATE
    wave_ = np.sin(phase) + third * np.sin(3 * phase)
    env = np.minimum(1, t / attack) * np.exp(-t / decay)
    return wave_ * env


def click(length=0.0015, freq=3200):
    t = np.arange(int(RATE * length)) / RATE
    return np.sin(2 * np.pi * freq * t) * np.hanning(len(t))


def place(parts, length):
    """Mix (offset_seconds, signal, gain) parts into one buffer."""
    out = np.zeros(int(RATE * length))
    for offset, sig, gain in parts:
        i = int(RATE * offset)
        n = min(len(sig), len(out) - i)
        out[i:i + n] += gain * sig[:n]
    return out


A5, B5, C6, E6, G6, A6, E5 = 880.0, 987.77, 1046.5, 1318.51, 1567.98, 1760.0, 659.25

SOUNDS = {
    # workspace change: the quietest tick
    "switch": place([(0, click(), 0.5), (0, tone(1600, 0.03, 0.006), 0.6)], 0.04),
    # window opens / closes: two notes up or down
    "open": place([(0, tone(A5, 0.07, 0.025), 0.7), (0.045, tone(E6, 0.11, 0.035), 0.7)], 0.16),
    "close": place([(0, tone(E6, 0.07, 0.025), 0.7), (0.045, tone(A5, 0.11, 0.035), 0.7)], 0.16),
    # scratchpad: three rising ticks
    "special": place([(0.05 * k, tone(1200 + 400 * k, 0.04, 0.01), 0.6) for k in range(3)], 0.16),
    # fullscreen: an upward glide
    "fullscreen": place([(0, tone(600, 0.12, 0.05, glide=1.4), 0.7)], 0.14),
    # lock: a low thump and a click, like a switch
    "lock": place([(0, tone(220, 0.16, 0.05, attack=0.002, third=0.25, glide=-0.3), 0.9),
                   (0.005, click(0.002, 3000), 0.5)], 0.18),
    # power off: four notes going down
    "power": place([(0.09 * k, tone(n, 0.25, 0.08), 0.65) for k, n in enumerate((E6, C6, A5, E5))], 0.55),
    # launcher: one soft blip
    "menu": place([(0, tone(C6, 0.06, 0.02, attack=0.004, glide=0.02), 0.7)], 0.07),
    # notification: a glassy two-note ping
    "notify": place([(0, tone(B5, 0.35, 0.16, third=0.05), 0.5), (0, tone(E6, 0.35, 0.13, third=0.05), 0.4),
                     (0, tone(E6 * 3, 0.2, 0.05, third=0), 0.06)], 0.36),
    # critical: three pulses, the sound of the red dot
    "critical": place([(0.12 * k, tone(A6, 0.07, 0.03, third=0.3), 0.6) for k in range(3)], 0.34),
    # volume step
    "volume": place([(0, tone(1200, 0.03, 0.008), 0.6)], 0.035),
}


def write_ogg(name, signal, outdir):
    peak = np.max(np.abs(signal))
    signal = signal / peak * 10 ** (-9 / 20)  # normalise to -9 dBFS
    fade = int(RATE * 0.004)
    signal[-fade:] *= np.linspace(1, 0, fade)
    pcm = (signal * 32767).astype("<i2")
    with tempfile.NamedTemporaryFile(suffix=".wav") as tmp:
        with wave.open(tmp.name, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(pcm.tobytes())
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", tmp.name, "-c:a", "libvorbis", "-q:a", "5",
                        "-map_metadata", "-1", "-fflags", "+bitexact", os.path.join(outdir, f"{name}.ogg")], check=True)


def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "sounds", "nihil")
    os.makedirs(outdir, exist_ok=True)
    for name, signal in SOUNDS.items():
        write_ogg(name, signal.copy(), outdir)
        print(f"{name:11s} {len(signal) / RATE * 1000:5.0f} ms")


if __name__ == "__main__":
    main()
