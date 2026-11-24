"""Trial-and-error loop metrics from Claude Code transcripts, before/after the costly-loop gate.

Run: python ~/.claude/scripts/loop-metrics.py --since 2026-10-25 --until 2026-11-24 [--out f.json]
Counts only, never message text. Patterns and segments() come from hooks/costly_loop.py (the gate).
"""
import argparse, collections, glob, json, os, re, subprocess, sys

HOME = os.path.expanduser("~/.claude")
SLOW_MS = 60_000


# the hooks next to this script, so a checkout measures with its own gate code
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "hooks"))
import costly_loop  # noqa: E402
from costly_loop import EXPECT_RE, IMAGE_RE, POLL_RE, kind, segments, unquoted  # noqa: E402  (shared with the gate)

FG_CAP_S = 90  # the native timeout since 2026-11-24, applied to both windows so the cap alone shows no gain
GATE_MSG = (("full video render", "render"), ("`# final` render", "render"), ("device install", "install"),
            ("slow step", "slow"), ("Bounced by costly-loop", "bounce"))


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
        main_session = "subagents" not in f
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
                tur = d.get("toolUseResult")
                if main_session and isinstance(tur, dict) and tur.get("backgroundedByUser"):
                    S["ctrl_b"] += 1
                for c in content:
                    if c.get("type") == "tool_result":
                        txt = c.get("content")
                        txt = json.dumps(txt) if not isinstance(txt, str) else txt
                        gate = next((r for m, r in GATE_MSG if "costly-loop gate" in txt and m in txt), None)
                        results[c.get("tool_use_id")] = (ts, "hook error" in txt or "Blocked by" in txt, gate)
        last_diag, last_install, slow_last = "", None, {}
        for j, (tid, name, inp, ts) in enumerate(calls):
            res = results.get(tid, ("", False, None))
            blocked = res[1]
            if res[2]:  # M4: what followed a gate block or bounce, within the next 3 relevant calls
                nxt = [c for c in calls[j + 1:] if c[1] in ("Read", "Grep", "Glob", "Bash")][:3]
                S["gate_%s_blocks" % res[2]] += 1
                if any(c[1] in ("Grep", "Glob") or (c[1] == "Read" and not IMAGE_RE.search(c[2].get("file_path", "")))
                       for c in nxt):
                    S["gate_%s_diag_next3" % res[2]] += 1
                if any(results.get(c[0], ("", False, None))[2] for c in nxt):
                    S["gate_%s_reblocked_next3" % res[2]] += 1
            if (main_session and name == "Bash" and not inp.get("run_in_background") and res[0]
                    and not POLL_RE.search(unquoted(inp.get("command", "")))):
                secs = _ms(ts, res[0]) / 1000
                if secs >= 30:
                    S["fg_slow_calls"] += 1
                    S["fg_wait_capped_s"] += min(secs, FG_CAP_S)
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
                end = res[0]
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
        out["v%s:%s:%s" % (d.get("v", 1), d.get("rule"), d.get("decision"))] += 1  # v1 and v2 rule sets apart
        if d.get("expect"):
            expects[d.get("session")].add(d["expect"])
    out["distinct_expects_per_session_max"] = max((len(v) for v in expects.values()), default=0)
    fg, bounced = out.get("v2:bounce:pass:fg", 0), out.get("v2:bounce:bounce", 0)
    # A6 decision rule: drop the bounce if more than half of bounce-eligible calls carry `# fg`
    out["fg_share_of_bounce_eligible"] = round(fg / (fg + bounced), 2) if fg + bounced else None
    return dict(out)


def gate_errors(since, until):
    """Exceptions the gate swallowed (it fails open), from loop-gate-errors.jsonl."""
    path = os.path.join(HOME, "metrics", "loop-gate-errors.jsonl")
    if not os.path.exists(path):
        return 0
    n = 0
    for line in open(path, encoding="utf-8"):
        try:
            n += since <= json.loads(line).get("ts", "")[:10] <= until
        except ValueError:
            continue
    return n


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
        "ctrl_b_per_session": kind(every, "ctrl_b"),  # the auto-background goal: the user stops pressing Ctrl+B
        "fg_wait_capped_s_per_session": kind(every, "fg_wait_capped_s"),
        "gate_outcomes": outcomes(sessions),
    }


def outcomes(sessions):
    """M4/M5: per rule, the share of blocks followed by a diagnosis, or by another block, within 3 calls.
    A rule with 5+ v2 blocks where under half end the streak gets loosened or dropped; fewer: extend."""
    out = {}
    for rule in ("render", "install", "slow", "bounce"):
        n = sum(s.get("gate_%s_blocks" % rule, 0) for s in sessions.values())
        if n:
            dg = sum(s.get("gate_%s_diag_next3" % rule, 0) for s in sessions.values())
            rb = sum(s.get("gate_%s_reblocked_next3" % rule, 0) for s in sessions.values())
            out[rule] = {"blocks": n, "diag_next3": round(dg / n, 2), "reblocked_next3": round(rb / n, 2),
                         "judge": "ok" if n >= 5 else "extend to 2026-12-22"}
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", required=True)
    ap.add_argument("--until", required=True)
    ap.add_argument("--out")
    a = ap.parse_args()
    sessions = scan(a.since, a.until)
    try:
        head = subprocess.run(["git", "-C", os.path.dirname(os.path.abspath(__file__)), "rev-parse", "HEAD"],
                              capture_output=True, text=True).stdout.strip()
    except OSError:
        head = ""
    report = {"script": {"head": head, "gate_version": costly_loop.VERSION, "argv": sys.argv[1:]},
              "window": [a.since, a.until], "summary": summarize(sessions), "gate_log": gate_log(a.since, a.until),
              "gate_errors": gate_errors(a.since, a.until), "sessions": sessions}
    for k, v in report["summary"].items():
        print(k, v)
    print("gate_log", report["gate_log"])
    print("gate_errors", report["gate_errors"])
    if a.out:
        os.makedirs(os.path.dirname(a.out), exist_ok=True)
        json.dump(report, open(a.out, "w", encoding="utf-8"), indent=1)
        print("wrote", a.out)
    return 0 if sessions else 1


if __name__ == "__main__":
    sys.exit(main())
