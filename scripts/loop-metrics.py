"""Trial-and-error loop metrics from Claude Code transcripts, before/after the costly-loop gate.

Run: python ~/.claude/scripts/loop-metrics.py --since 2026-10-25 --until 2026-11-24 [--out f.json]
Counts only, never message text. Patterns and segments() come from hooks/costly_loop.py (the gate).
"""
import argparse, collections, glob, json, os, re, sys

HOME = os.path.expanduser("~/.claude")
SLOW_MS = 60_000


sys.path.insert(0, os.path.join(HOME, "hooks"))
from costly_loop import EXPECT_RE, IMAGE_RE, kind, segments  # noqa: E402  (shared with the gate)


def classify(cmd, background):
    k = kind(cmd)
    return None if k is None or (background and k == "other") else k


def is_review(name, inp):
    if name == "Skill":
        return bool(re.search(r"review", inp.get("skill", ""), re.I))
    if name == "Agent":
        return bool(re.search(r"review", (inp.get("description", "") + " " + str(inp.get("subagent_type", ""))), re.I))
    return False


def session_of(path):
    parts = os.path.normpath(path).split(os.sep)
    if "subagents" in parts:
        return parts[parts.index("subagents") - 1]
    return os.path.splitext(parts[-1])[0]


def scan(since, until):
    sessions = collections.defaultdict(lambda: collections.Counter())
    for f in glob.glob(os.path.join(HOME, "projects", "**", "*.jsonl"), recursive=True):
        proj = os.path.relpath(f, os.path.join(HOME, "projects")).split(os.sep)[0]
        if "scratchpad" in proj or "-eval-" in proj:
            continue
        sid = session_of(f)
        S = sessions[sid]
        calls, results = [], {}
        for line in open(f, encoding="utf-8", errors="ignore"):
            try:
                d = json.loads(line)
            except ValueError:
                continue
            ts = d.get("timestamp") or ""
            if not (since <= ts[:10] <= until):
                continue
            msg = d.get("message") or {}
            content = msg.get("content")
            if d.get("type") == "assistant":
                u = msg.get("usage") or {}
                S["output_tokens"] += u.get("output_tokens", 0)
                S["cache_create_tokens"] += u.get("cache_creation_input_tokens", 0)
                for c in content if isinstance(content, list) else []:
                    if c.get("type") == "tool_use":
                        calls.append((c.get("id"), c.get("name"), c.get("input") or {}, ts))
            elif d.get("type") == "user" and isinstance(content, list):
                for c in content:
                    if c.get("type") == "tool_result":
                        txt = c.get("content")
                        txt = json.dumps(txt) if not isinstance(txt, str) else txt
                        results[c.get("tool_use_id")] = (ts, "hook error" in txt or "Blocked by" in txt)
        last_diag, last_install, slow_last = "", None, {}
        for tid, name, inp, ts in calls:
            blocked = results.get(tid, ("", False))[1]
            if is_review(name, inp):
                S["review_dispatches"] += 1
            if name in ("Grep", "Glob") or (name == "Read" and not IMAGE_RE.search(inp.get("file_path", ""))):
                last_diag = ts
                continue
            if name != "Bash":
                continue
            cmd = inp.get("command", "")
            kind = classify(cmd, inp.get("run_in_background"))
            if kind is None:
                continue
            if blocked:
                S["blocked_" + kind] += 1
                continue
            if kind == "shot_test":
                S["shot_tests"] += 1
                last_diag = ts
            elif kind in ("full_render", "span_render"):
                S[kind + "s"] += 1
            elif kind == "install":
                S["installs"] += 1
                if last_install is not None and last_diag < last_install and not EXPECT_RE.search(cmd):
                    S["blind_installs"] += 1
                last_install = ts
            else:
                end = results.get(tid, ("", False))[0]
                segs = segments(cmd)
                hit = [s for s in segs if s in slow_last]
                if hit and not EXPECT_RE.search(cmd) and all(last_diag < slow_last[s] for s in hit):
                    S["blind_slow_repeats"] += 1
                slow = bool(end) and _ms(ts, end) > SLOW_MS  # same rule as the gate's PostToolUse
                for s in segs:
                    if slow:
                        slow_last[s] = ts
                    else:
                        slow_last.pop(s, None)
    return {k: dict(v) for k, v in sessions.items() if v}


def _ms(a, b):
    from datetime import datetime
    f = lambda s: datetime.fromisoformat(s.replace("Z", "+00:00"))
    try:
        return (f(b) - f(a)).total_seconds() * 1000
    except ValueError:
        return 0


def gate_log(since, until):
    path = os.path.join(HOME, "metrics", "loop-gate.jsonl")
    out = collections.Counter()
    expects = collections.defaultdict(set)
    if not os.path.exists(path):
        return {}
    for line in open(path, encoding="utf-8"):
        try:
            d = json.loads(line)
        except ValueError:
            continue
        if not (since <= d.get("ts", "")[:10] <= until):
            continue
        out["%s:%s" % (d.get("rule"), d.get("decision"))] += 1
        if d.get("expect"):
            expects[d.get("session")].add(d["expect"])
    out["distinct_expects_per_session_max"] = max((len(v) for v in expects.values()), default=0)
    return dict(out)


def summarize(sessions):
    def kind(pred, metric):
        rows = [s for s in sessions.values() if pred(s)]
        n = len(rows)
        total = sum(s.get(metric, 0) for s in rows)
        return {"sessions": n, metric: total, "per_session": round(total / n, 2) if n else None,
                "verdict_ok": n >= 3}
    video = lambda s: s.get("full_renders", 0) + s.get("span_renders", 0) + s.get("blocked_full_render", 0) > 0
    android = lambda s: s.get("installs", 0) + s.get("blocked_install", 0) > 0
    every = lambda s: s.get("output_tokens", 0) > 0
    return {
        "full_renders_per_video_session": kind(video, "full_renders"),
        "span_renders_per_video_session": kind(video, "span_renders"),
        "installs_per_android_session": kind(android, "installs"),
        "blind_installs_per_android_session": kind(android, "blind_installs"),
        "blind_slow_repeats_per_session": kind(every, "blind_slow_repeats"),
        "review_dispatches_per_session": kind(every, "review_dispatches"),
        "output_tokens_per_session": kind(every, "output_tokens"),
        "blocked_total": sum(v for s in sessions.values() for k, v in s.items() if k.startswith("blocked_")),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", required=True)
    ap.add_argument("--until", required=True)
    ap.add_argument("--out")
    a = ap.parse_args()
    sessions = scan(a.since, a.until)
    report = {"window": [a.since, a.until], "summary": summarize(sessions), "gate_log": gate_log(a.since, a.until),
              "sessions": sessions}
    for k, v in report["summary"].items():
        print(k, v)
    print("gate_log", report["gate_log"])
    if a.out:
        os.makedirs(os.path.dirname(a.out), exist_ok=True)
        json.dump(report, open(a.out, "w", encoding="utf-8"), indent=1)
        print("wrote", a.out)
    return 0 if sessions else 1


if __name__ == "__main__":
    sys.exit(main())
