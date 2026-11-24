"""Check a voiceover built by joining takes: gaps inside the line and level jumps at each join.
Usage: python -I vo_join_check.py <line.wav> <join_s> [<join_s> ...]
Needs numpy and scipy. Reports every pause over 0.25 s (a pause mid-sentence reads as a cut), and the loudness of
1.5 s of speech either side of each join (flagged when 1.5 dB beyond the line's own natural steps; coarse, it catches a take at the wrong level, not a subtle mismatch). Word boundaries still need a transcript:
check that no word near a join is missing or clipped.
"""
import sys

import numpy as np
from scipy.io import wavfile

sr, x = wavfile.read(sys.argv[1])
x = x.astype(np.float64)
if x.ndim > 1:
    x = x.mean(1)
x /= np.abs(x).max() or 1
joins = [float(a) for a in sys.argv[2:]]
hop = int(0.01 * sr)
rms = np.sqrt(np.array([np.mean(x[i:i + hop] ** 2) for i in range(0, len(x) - hop, hop)]))
db = 20 * np.log10(rms + 1e-9)
voiced = db > db.max() - 35
idx = np.flatnonzero(voiced)
first, last = idx[0], idx[-1]
problems = 0
k = first
while k <= last:
    if not voiced[k]:
        j = k
        while j <= last and not voiced[j]:
            j += 1
        dur = (j - k) * 0.01
        if dur > 0.25:
            print(f"PAUSE {k * 0.01:.2f}-{j * 0.01:.2f}s ({dur:.2f} s): fine at a full stop, a cut if mid-sentence")
        k = j
    k += 1


def level(t, side):
    # the nearest 1.5 s of speech on that side (a join usually sits in a pause; a sentence end falls in level, so a
    # shorter window misreads it)
    v = idx[idx < t * 100][-150:] if side < 0 else idx[idx >= t * 100][:150]
    return float(np.mean(db[v])) if len(v) >= 30 else None


def step(t):
    a, b = level(t, -1), level(t, 1)
    return None if a is None or b is None else abs(a - b)


# speech moves by a few dB on its own, so a join is judged against the same line's natural steps away from any join
natural = [s for t in np.arange(first * 0.01 + 1.5, last * 0.01 - 1.5, 0.25)
           if all(abs(t - j) > 1.6 for j in joins) and (s := step(t)) is not None]
base = float(np.percentile(natural, 90)) if natural else 1.5
print(f"natural step in this line: 90th percentile {base:.1f} dB over {len(natural)} points")
for t in joins:
    gap = step(t)
    if gap is None:
        print(f"JOIN {t:.2f}s: too little speech on one side, level not comparable"); continue
    lb, la = level(t, -1), level(t, 1)
    flag = "JUMP" if gap > base + 1.5 else "ok"
    problems += flag == "JUMP"
    print(f"JOIN {t:.2f}s: before {lb:.1f} dB, after {la:.1f} dB, difference {gap:.1f} dB {flag}")
print(f"RESULT speech {first * 0.01:.2f}-{last * 0.01:.2f}s, {len(joins)} join(s): "
      f"{'PASS' if problems == 0 else f'{problems} level jump(s)'} (pauses listed above need a human read)")
