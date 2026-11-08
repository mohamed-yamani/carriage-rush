"""Synthesises every sound effect for the game into assets/sfx/*.wav (22.05 kHz, mono, 16-bit).

Nothing is sampled, so there are no licensing questions. Run from the project root:
    python3 tool/make_sounds.py        (needs numpy)
"""
import os
import wave

import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sfx")
rng = np.random.default_rng(7)


def t(sec):
    return np.arange(int(SR * sec)) / SR


def env(n, attack=0.005, decay=0.2):
    x = np.arange(n) / SR
    a = np.clip(x / max(attack, 1e-4), 0, 1)
    return a * np.exp(-x / max(decay, 1e-4))


def lowpass(x, cutoff):
    # one-pole low-pass, good enough for rumbles and wind
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1 - a) * v + a * acc
        y[i] = acc
    return y


def bandpass(x, lo, hi):
    return lowpass(x, hi) - lowpass(x, lo)


def noise(sec):
    return rng.uniform(-1, 1, int(SR * sec))


def write(name, x, peak=0.9):
    x = np.asarray(x, dtype=np.float64)
    m = np.max(np.abs(x)) or 1
    x = x / m * peak
    data = (x * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print(f"{name:12s} {len(x) / SR:5.2f}s")


def make_loop(x, fade=0.05):
    """Cross-fade the tail into the head so the loop has no click."""
    n = int(SR * fade)
    head, tail = x[:n].copy(), x[-n:]
    ramp = np.linspace(0, 1, n)
    x = x[:-n].copy()
    x[:n] = head * ramp + tail * (1 - ramp)
    return x


# ---------- hooves ----------
def hoof(strength=1.0, pitch=1.0):
    n = int(SR * 0.16)
    x = np.arange(n) / SR
    thump = np.sin(2 * np.pi * 95 * pitch * x) * np.exp(-x / 0.035)
    knock = np.sin(2 * np.pi * 420 * pitch * x) * np.exp(-x / 0.012)
    click = bandpass(rng.uniform(-1, 1, n), 1500, 5000) * np.exp(-x / 0.006)
    dirt = lowpass(rng.uniform(-1, 1, n), 900) * np.exp(-x / 0.05)
    return strength * (thump * 0.9 + knock * 0.35 + click * 0.6 + dirt * 0.5)


def place(buf, sound, at):
    i = int(at * SR)
    j = min(len(buf), i + len(sound))
    buf[i:j] += sound[: j - i]


def gallop_cycle(cycle=0.5, jitter=0.0, pitch=1.0):
    """One stride of a gallop: four footfalls, the classic ba-da-da-dum, at 2 strides/s."""
    buf = np.zeros(int(SR * cycle))
    for off, s in [(0.0, 0.8), (0.075, 0.65), (0.15, 0.75), (0.2, 1.0)]:
        o = off * cycle / 0.5 + rng.uniform(-jitter, jitter)
        place(buf, hoof(s * rng.uniform(0.85, 1.05), pitch * rng.uniform(0.95, 1.05)), max(0.0, o))
    return buf


def gallop_loop():
    # 4 strides, slightly varied, played back faster/slower to match the horse's cadence
    x = np.concatenate([gallop_cycle() for _ in range(4)])
    jingle = np.zeros_like(x)  # a little harness jingle on every stride
    for k in range(4):
        n = int(SR * 0.12)
        tt = np.arange(n) / SR
        ring = (np.sin(2 * np.pi * 3100 * tt) + 0.6 * np.sin(2 * np.pi * 4700 * tt)) * np.exp(-tt / 0.03)
        place(jingle, ring * 0.12, k * 0.5 + 0.21)
    return x + jingle


def pack_loop():
    # many horses at once: overlapping out-of-phase strides, softer and wider
    total = np.zeros(int(SR * 2.0))
    for h in range(6):
        start = rng.uniform(0, 0.5)
        pitch = rng.uniform(0.85, 1.15)
        k = start
        while k < 2.0:
            place(total, gallop_cycle(0.5 * rng.uniform(0.92, 1.08), 0.01, pitch) * 0.55, k)
            k += 0.5 * rng.uniform(0.95, 1.05)
    return make_loop(lowpass(total, 2500) * 0.8 + total * 0.2)


# ---------- impacts ----------
def wood_crash():
    d = 1.1
    x = t(d)
    crack = bandpass(noise(d), 300, 4000) * env(len(x), 0.001, 0.12)
    thump = np.sin(2 * np.pi * 70 * x) * np.exp(-x / 0.15)
    splinters = np.zeros(len(x))
    for _ in range(40):
        at = rng.uniform(0.02, 0.7)
        n = int(SR * 0.02)
        tt = np.arange(n) / SR
        s = np.sin(2 * np.pi * rng.uniform(600, 2400) * tt) * np.exp(-tt / 0.004)
        place(splinters, s * rng.uniform(0.2, 0.6) * np.exp(-at / 0.3), at)
    rattle = bandpass(noise(d), 200, 1200) * env(len(x), 0.05, 0.35) * 0.4
    return crack * 1.6 + thump * 0.45 + splinters * 1.4 + rattle


def wood_bump():
    x = t(0.35)
    knock = np.sin(2 * np.pi * 210 * x) * np.exp(-x / 0.05) + 0.5 * np.sin(2 * np.pi * 530 * x) * np.exp(-x / 0.025)
    click = bandpass(noise(0.35), 800, 4000) * np.exp(-x / 0.01)
    return knock + click * 0.6


def rock_hit():
    x = t(0.9)
    clack = bandpass(noise(0.9), 1200, 6000) * np.exp(-x / 0.02)
    ring = (np.sin(2 * np.pi * 1650 * x) + 0.7 * np.sin(2 * np.pi * 2730 * x)) * np.exp(-x / 0.06) * 0.4
    thud = np.sin(2 * np.pi * 85 * x) * np.exp(-x / 0.12)
    gravel = np.zeros(len(x))
    for _ in range(30):
        at = rng.uniform(0.05, 0.6)
        n = int(SR * 0.015)
        tt = np.arange(n) / SR
        g = bandpass(rng.uniform(-1, 1, n), 2000, 7000) * np.exp(-tt / 0.004)
        place(gravel, g * rng.uniform(0.1, 0.4), at)
    return clack + ring + thud + gravel


def whinny():
    """A neigh: a bright, buzzy voice that jumps up, wobbles and slides down."""
    d = 1.3
    x = t(d)
    f0 = np.interp(x, [0, 0.12, 0.5, 1.0, 1.3], [520, 980, 820, 560, 380])
    vib = 1 + 0.06 * np.sin(2 * np.pi * 22 * x) * np.clip((x - 0.1) * 4, 0, 1)
    phase = 2 * np.pi * np.cumsum(f0 * vib) / SR
    voice = sum(np.sin(phase * h) / h ** 0.9 for h in range(1, 9))
    breath = bandpass(noise(d), 1500, 6000) * 0.25
    amp = np.interp(x, [0, 0.05, 0.9, 1.3], [0, 1, 0.7, 0])
    snort_x = t(0.18)
    snort = bandpass(noise(0.18), 200, 2000) * env(len(snort_x), 0.01, 0.06)
    out = (voice * 0.6 + breath) * amp
    out[: len(snort)] += snort * 0.6
    return lowpass(out, 5000)


# ---------- surfaces + ambience ----------
def gravel_loop():
    d = 1.5
    base = bandpass(noise(d), 400, 5000) * 0.35
    crunch = np.zeros(int(SR * d))
    for _ in range(220):
        n = int(SR * 0.01)
        tt = np.arange(n) / SR
        c = bandpass(rng.uniform(-1, 1, n), 1500, 8000) * np.exp(-tt / 0.003)
        place(crunch, c * rng.uniform(0.2, 1.0), rng.uniform(0, d - 0.02))
    return make_loop(base + crunch)


def wind_loop(gusty=1.0):
    d = 6.0
    x = t(d)
    w = lowpass(noise(d), 500) * (0.6 + 0.4 * np.sin(2 * np.pi * x / d * 2 * gusty) ** 2)
    whistle = lowpass(noise(d), 1500) - lowpass(noise(d), 1200)
    return make_loop(w + whistle * 0.3, 0.3)


def waves_loop():
    d = 8.0
    x = t(d)
    surf = lowpass(noise(d), 1200)
    swell = np.clip(np.sin(2 * np.pi * x / 4.0), 0, 1) ** 2 + 0.15
    return make_loop(surf * swell + lowpass(noise(d), 300) * 0.4, 0.5)


def crickets_loop():
    d = 4.0
    x = t(d)
    out = lowpass(noise(d), 200) * 0.25  # distant city hum
    for k in range(3):
        f = 4300 + k * 350
        rate = 14 + k * 3
        chirp = np.sin(2 * np.pi * f * x) * (np.sin(2 * np.pi * rate * x) > 0.3)
        gate = (np.sin(2 * np.pi * x / (0.9 + k * 0.4) + k) > 0.2).astype(float)
        out += chirp * gate * 0.12
    return make_loop(out, 0.3)


# ---------- UI / race ----------
def beep(freq, dur):
    x = t(dur)
    tone = np.sign(np.sin(2 * np.pi * freq * x)) * 0.3 + np.sin(2 * np.pi * freq * x)
    return lowpass(tone * env(len(x), 0.005, dur / 2.5), 6000)


def fanfare():
    notes = [(523, 0.14), (659, 0.14), (784, 0.14), (1047, 0.55)]
    out = []
    for f, d in notes:
        x = t(d)
        saw = sum(np.sin(2 * np.pi * f * h * x) / h for h in range(1, 7))
        out.append(lowpass(saw * env(len(x), 0.01, d * 0.8), 5000))
    return np.concatenate(out)


def click():
    x = t(0.05)
    return np.sin(2 * np.pi * 1800 * x) * np.exp(-x / 0.008)


def whip():
    x = t(0.4)
    crack = bandpass(noise(0.4), 2000, 9000) * np.exp(-np.abs(x - 0.03) / 0.006)
    swish = bandpass(noise(0.4), 800, 3000) * np.exp(-((x - 0.0) / 0.04) ** 2)
    return crack * 1.2 + swish * 0.4


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    write("gallop", make_loop(gallop_loop(), 0.01))
    write("pack", pack_loop(), 0.7)
    write("crash", wood_crash())
    write("bump", wood_bump(), 0.7)
    write("rock", rock_hit())
    write("neigh", whinny(), 0.8)
    write("gravel", gravel_loop(), 0.6)
    write("wind", wind_loop(), 0.5)
    write("mountain", wind_loop(2.5), 0.55)
    write("waves", waves_loop(), 0.55)
    write("crickets", crickets_loop(), 0.4)
    write("beep", beep(880, 0.18), 0.6)
    write("go", beep(1320, 0.5), 0.7)
    write("fanfare", fanfare(), 0.7)
    write("click", click(), 0.5)
    write("whip", whip(), 0.8)
