"""Per-frame change over a span of a rendered video, to find pops (one-frame spikes) and stalls (motion stops).
Usage: python -I frame_diff.py <video> <t0> <t1> [--all]
Prints a verdict line per problem; --all also prints every frame's value. Needs ffmpeg/ffprobe and numpy.
Mean abs diff of grey frames at 480x270, 0-255 scale. Thresholds are rules of thumb for calm, dark films:
a frame more than 4x the span median (and > 1.0) is a pop; 6+ frames under 0.02 while neighbours move is a stall.
"""
import subprocess
import sys

import numpy as np

f, t0, t1 = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
fps_s = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=r_frame_rate",
                        "-of", "csv=p=0", f], capture_output=True, text=True).stdout.strip()
n, d = fps_s.split("/") if "/" in fps_s else (fps_s, "1")
fps = float(n) / float(d)
W, H = 480, 270
raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-ss", str(t0), "-t", str(t1 - t0), "-i", f, "-vf", f"scale={W}:{H}",
                      "-f", "rawvideo", "-pix_fmt", "gray", "-"], capture_output=True).stdout
fr = np.frombuffer(raw, np.uint8).reshape(-1, H, W).astype(np.int16)
diff = np.abs(np.diff(fr, axis=0)).mean((1, 2))
ts = [t0 + (k + 1) / fps for k in range(len(diff))]
if "--all" in sys.argv:
    for t, v in zip(ts, diff):
        print(f"{t:.3f} {v:.3f}")
med = float(np.median(diff)) if len(diff) else 0.0
problems = 0
for t, v in zip(ts, diff):
    if v > max(1.0, 4 * med):
        print(f"POP   {t:.3f}s change {v:.2f} (span median {med:.2f})"); problems += 1
run = 0
for k, v in enumerate(diff):
    run = run + 1 if v < 0.02 else 0
    if run == 6 and med > 0.1:
        print(f"STALL from {ts[k - 5]:.3f}s (6+ frames without motion, span median {med:.2f})"); problems += 1
print(f"RESULT {len(diff)} frames at {fps:g} fps, median {med:.3f}, max {diff.max() if len(diff) else 0:.3f}: "
      f"{'PASS' if problems == 0 else f'{problems} problem(s)'}")
