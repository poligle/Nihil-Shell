#!/usr/bin/env python3
# sounds.py by poligle

import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

RATE = 44100


def tone(freq, length, decay, attack=0.003, third=0.12, glide=0.0):
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
    out = np.zeros(int(RATE * length))
    for offset, sig, gain in parts:
        i = int(RATE * offset)
        n = min(len(sig), len(out) - i)
        out[i:i + n] += gain * sig[:n]
    return out


A5, B5, C6, E6, G6, A6, E5 = 880.0, 987.77, 1046.5, 1318.51, 1567.98, 1760.0, 659.25

POWER = (E6, C6, A5, E5)


def power_notes(order, start=0.0):
    return [(start + 0.09 * k, tone(n, 0.25, 0.08), 0.65) for k, n in enumerate(order)]


SOUNDS = {
    "switch": place([(0, click(), 0.5), (0, tone(1600, 0.03, 0.006), 0.6)], 0.04),
    "open": place([(0, tone(A5, 0.07, 0.025), 0.7), (0.045, tone(E6, 0.11, 0.035), 0.7)], 0.16),
    "close": place([(0, tone(E6, 0.07, 0.025), 0.7), (0.045, tone(A5, 0.11, 0.035), 0.7)], 0.16),
    "special": place([(0.05 * k, tone(1200 + 400 * k, 0.04, 0.01), 0.6) for k in range(3)], 0.16),
    "fullscreen": place([(0, tone(600, 0.12, 0.05, glide=1.4), 0.7)], 0.14),
    "lock": place([(0, tone(220, 0.16, 0.05, attack=0.002, third=0.25, glide=-0.3), 0.9),
                   (0.005, click(0.002, 3000), 0.5)], 0.18),
    "power": place(power_notes(POWER), 0.55),
    "menu": place([(0, tone(C6, 0.06, 0.02, attack=0.004, glide=0.02), 0.7)], 0.07),
    "notify": place([(0, tone(B5, 0.35, 0.16, third=0.05), 0.5), (0, tone(E6, 0.35, 0.13, third=0.05), 0.4),
                     (0, tone(E6 * 3, 0.2, 0.05, third=0), 0.06)], 0.36),
    "critical": place([(0.12 * k, tone(A6, 0.07, 0.03, third=0.3), 0.6) for k in range(3)], 0.34),
    "volume": place([(0, tone(1200, 0.03, 0.008), 0.6)], 0.035),
    "charge": place([(0, tone(E5, 0.09, 0.03), 0.6), (0.06, tone(B5, 0.09, 0.03), 0.6),
                     (0.12, tone(E6, 0.22, 0.09, glide=0.03), 0.65)], 0.34),
}


LAST_LED = 27 * 0.04

WAVS = {
    "boot": place(power_notes(POWER[::-1], LAST_LED - 0.27), LAST_LED + 0.29),
}
MADE_FROM = {"boot": "power"}


def pcm16(signal, dbfs):
    peak = np.max(np.abs(signal))
    signal = signal / peak * 10 ** (dbfs / 20)
    fade = int(RATE * 0.004)
    signal[-fade:] *= np.linspace(1, 0, fade)
    return (signal * 32767).astype("<i2")


def write_wav(path, pcm):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())


def write_ogg(name, signal, outdir):
    with tempfile.NamedTemporaryFile(suffix=".wav") as tmp:
        write_wav(tmp.name, pcm16(signal, -9))
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", tmp.name, "-c:a", "libvorbis", "-q:a", "5",
                        "-map_metadata", "-1", "-fflags", "+bitexact", os.path.join(outdir, f"{name}.ogg")], check=True)


def main():
    args = sys.argv[1:]
    only = args[args.index("--only") + 1:] if "--only" in args else None
    places = args[:args.index("--only")] if "--only" in args else args
    outdir = places[0] if places else os.path.join(os.path.dirname(__file__), "..", "sounds", "nihil")
    os.makedirs(outdir, exist_ok=True)
    for name, signal in SOUNDS.items():
        if only is None or name in only:
            write_ogg(name, signal.copy(), outdir)
            print(f"{name:11s} {len(signal) / RATE * 1000:5.0f} ms")
    for name, signal in WAVS.items():
        if only is None or name in only or MADE_FROM.get(name) in only:
            write_wav(os.path.join(outdir, f"{name}.wav"), pcm16(signal.copy(), -12))
            print(f"{name:11s} {len(signal) / RATE * 1000:5.0f} ms (wav)")


if __name__ == "__main__":
    main()
