---
name: video-iteration
description: The edit-check-send loop for a rendered video (HyperFrames or any HTML/ffmpeg pipeline) once a first cut exists - render and measure only the seconds that changed, prove cuts are smooth with frame-diff numbers, check voiceover joins and loudness, and do one full render + master only for a version that goes to the person. Use whenever a video, promo, launch film, explainer or reel is being revised from feedback ("the transition is chopped", "the logo is stuck", "she pauses before X", "make it smoother", "fix the end card", "send me the new version"), when splicing TTS takes, and before sending any render. Not for the first build of a new video (use hyperframes:hyperframes) or for getting media (hyperframes:media-use).
---

# Video iteration

A revision round has three costs: render time, the person's attention, and trust. A full 60 fps render of a 60 s film takes minutes; a 5 s span takes seconds. Every version the person watches should already have passed the checks below, because they are checking by eye and ear what numbers could have caught. You can't watch or listen to the result yourself, so the scripts are your eyes and ears; say what they measured, never "it looks smooth".

Scripts (in this skill's `scripts/`; run Python with `uv run --no-project --with numpy[ --with scipy] python -I`):
- `frame_diff.py <video> <t0> <t1> [--all]` - per-frame change over a span; prints POP (one-frame spike = something appeared or jumped) and STALL (motion stopped while the film is moving) lines and a RESULT line.
- `vo_join_check.py <line.wav> <join_s>...` - pauses over 0.25 s in the line and the level step at each join, judged against that line's own natural variation.
- `loudness.sh <file> [target=-14] [max_tp=-1.5]` - integrated LUFS, true peak, short-term per second, PASS/FAIL.

## 1. Before editing: read, then plan the check

Read the scene source and the frames around the complaint before changing anything, and name the cause ("the strip stops at 8.8 s and the ring fades in on the cut", not "transition is off"). Decide which span the change touches and what number will prove it fixed, e.g. "frame_diff 24.0-24.9 shows no POP and no STALL". One render should confirm the plan, not discover the problem. Feedback about a feeling ("unprofessional", "stuck", "chopped") usually maps to a measurable cause: a one-frame appearance (pop), a hold where motion stops (stall), a speed jump at a cut, an element that draws all at once.

## 2. Iterate on the span only

Render only the changed seconds, with half a second of margin each side of any cut:

```bash
npx -y hyperframes@<pinned> render --start 23.9 --end 25.0 -o renders/span-<name>.mp4
npx -y hyperframes@<pinned> snapshot --at 24.2,24.4,24.6     # look at the frames too
```

Then measure (`frame_diff.py renders/span-<name>.mp4 0 1.1`). Fix and re-run the span until it passes. Batch several fixes before the next full render. A full render to check a 5 s change is the thing this skill exists to stop.

## 3. Cuts and motion

Every scene cut gets frame-diff over 0.5 s each side before a send. What has worked for invisible cuts:
- The incoming scene redraws the outgoing scene's exact last frame (same elements, same phase: time = previous duration + t) and continues its motion with the same speed; don't start from rest on a cut.
- Fade or reveal what is new; nothing appears in one frame.
- Drive canvas drawing from the timeline's own update callback so it reads this frame's tween values, not last frame's (one-frame lag shows as jitter at cuts).
- SVG draw-on: set dashes from `getTotalLength()`; some renderers ignore `pathLength`, and the stroke then pops in complete.

## 4. Voiceover joins

Join TTS takes only at a sentence boundary (acrossfade ~0.12 s, level matched). A word inside a sentence can't be replaced by cutting: regenerate the whole sentence. After every join run `vo_join_check.py` and a transcript (word timings) and check: no word near the join missing or clipped, no pause over ~0.25 s except at a full stop, no JUMP. Then say plainly that the reading itself (intonation, a pause that sounds odd) still needs the person's ear.

## 5. A version to send

Only now render the whole video, master it, and run every check on the master:

```bash
ffmpeg -i full.mp4 -af loudnorm=I=-14:TP=-2.2:LRA=11 -c:v copy -c:a aac -b:a 192k full-m.mp4
bash scripts/loudness.sh full-m.mp4 -14 -1.5
```

Plus frame_diff at every cut, and the project's own lint/check. Send it with a short note: what changed, by the person's own words for each complaint, what was measured (numbers), and what you could not check (sound and feel). Keep version numbers in file names (`wip-v19-m.mp4`) so the person can compare.

## Notes

- Keep a live checklist in the project (`TASKS.md`): each round's complaints, causes, fixes, and the version that shipped them, so a compaction or new session doesn't redo a round.
- An independent look is worth more than your own: for a pass over a whole cut, dispatch the `video-critic` agent with frames only.
