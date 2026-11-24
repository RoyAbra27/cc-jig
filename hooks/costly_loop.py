"""Costly-loop gate (added 2026-11-24): block blind reruns of expensive steps, and bounce known-slow
steps to the background.

Hook events: PreToolUse(Bash|Read|Grep|Glob) decides; PostToolUse(Bash) and PostToolUseFailure(Bash)
record runs and durations (duration_ms). Exit 2 blocks (stderr is shown to Claude). Rules:
- full video render (hyperframes render without --start) needs a `# final` line, once per 20 min
- install / slow step: a rerun with no diagnosis since the last run is "blind". The first blind rerun
  is free; the second in a row blocks, unless an `# expect:` line comes with it (one per streak)
- bounce (main session, interactive only): a foreground step whose last 2 runs in this repo both
  took 30s+ is sent back with "run it in the background", unless a `# fg` line is present
Diagnosis = Read of a non-image file, Grep, Glob, or a screenshot-test command. Markers count only on
their own line; an expect must be 20+ chars and differ from the session's previous one.
Durations and the bounce match steps by step_key() (program, subcommands, script, flag names; values
dropped), so variants that differ by one argument count as one step; the gate keeps exact segments
(see GATE_KEYS). Durations persist per repo in
state/durations/; the session-start hook lists slow steps via `--slow-list <cwd>`.
scripts/loop-metrics.py imports from here. Fails open on any error. Never rewrites a call: in auto
mode a changed input is blocked by the classifier, and "allow" would skip its review.
ponytail: PowerShell-tool commands bypass this (Bash only). Cases live in costly_loop.test.sh.
"""
import hashlib, json, os, re, sys, time

RENDER_RE = re.compile(r"hyperframes(@[0-9][0-9.]*)?\s+render(\s|$)")
INSTALL_RE = re.compile(r"gradlew[^|;&]*[ :]install[A-Za-z]*|adb[^|;&]*\sinstall(\s|$)")
SHOT_RE = re.compile(r"(record|verify|compare)(Roborazzi|Paparazzi)")
SKIP_FIRST_RE = re.compile(r"^\s*(git|grep|rg|echo)(\s|$)")
IMAGE_RE = re.compile(r"\.(png|jpe?g|webp|gif)$", re.I)
EXPECT_RE = re.compile(r"^# expect: (.{20,})$", re.M)
FINAL_RE = re.compile(r"^# final$", re.M)
FG_RE = re.compile(r"^# fg$", re.M)
POLL_RE = re.compile(r"(^|[;&|\n]\s*)(until|while)\s")
HEREDOC_RE = re.compile(r"<<-?\s*['\"]?(\w+)['\"]?[^\n]*\n.*?\n\s*\1\s*(\n|$)", re.S)
QUOTED_RE = re.compile(r"'[^']*'|\"(?:\\.|[^\"\\])*\"", re.S)
TRIVIAL_SEG_RE = re.compile(
    r"^(cd|rm|mkdir|ls|echo|printf|export|sed|awk|head|tail|cat|grep|rg|wc|sort|uniq|cut|tr|find|mv|cp|"
    r"git|until|while|do|done|sleep|for|if|then|else|fi|case|esac|break|time|true|test|\[|[A-Za-z_]\w*=\S*$)(\s|$)"
)
WRAPPERS = {"rtk", "time", "exec", "nohup"}
SCRIPT_RE = re.compile(r"\.(py|sh|js|ts|mjs|ps1)$")
SUBCMD_RE = re.compile(r":?[a-z][\w:-]*")
FINAL_WINDOW = 1200
# A3 replay 2026-11-24 (30 days, main sessions, first blind rerun free): exact 19 blocks, keys 25, and all 6
# extra blocked reruns took under 30s. So the gate matches exact segments; keys drive durations and the bounce.
GATE_KEYS = False
VERSION = 2  # gate rule set in loop-gate.jsonl; v2 = streaks (first blind rerun free) + step keys + bounce


def code_lines(cmd):
    return "\n".join(l for l in cmd.splitlines() if not l.lstrip().startswith("#"))


def unquoted(cmd):
    return QUOTED_RE.sub(" ", HEREDOC_RE.sub("\n", code_lines(cmd)))


def segments(cmd):
    """Non-trivial segments, quotes and heredoc bodies removed: `python patch7.py && <pipeline>` repeats on <pipeline>."""
    out = set()
    for s in re.split(r"&&|\|\||;|\||\n", unquoted(cmd)):
        s = " ".join(s.split())
        if len(s.split()) >= 2 and not TRIVIAL_SEG_RE.search(s) and not re.search(r"\s-[ce]?$|<<|\)$|^\S+\)", s):
            out.add(s[:200])
    return out


def strip_prefix(seg):
    """Drop leading VAR=value assignments and wrapper words."""
    toks = seg.split()
    while toks and (re.match(r"^[A-Za-z_]\w*=", toks[0]) or toks[0] in WRAPPERS):
        toks.pop(0)
    return toks


def step_key(seg):
    """`npx -y hyperframes@0.9.86 render -o renders/v2.mp4` -> `npx -y hyperframes render -o`."""
    toks = strip_prefix(seg)
    # `F=$(ls -t x` leaves `-t x`: no program to key on
    if not toks or toks[0].startswith("-") or re.search(r"[$*?(){}<>]", toks[0]):
        return None
    prog = re.split(r"[/\\]", toks[0])[-1]
    out, subs = [re.sub(r"@[\d.]+$", "", re.sub(r"\.exe$", "", prog, flags=re.I))], 0
    for t in toks[1:]:
        t = re.sub(r"@[\d.]+$", "", t)
        if t.startswith("-"):
            out.append(t.split("=")[0])
        elif SCRIPT_RE.search(t):
            out.append(re.split(r"[/\\]", t)[-1])
        elif subs < 2 and SUBCMD_RE.fullmatch(t) and not re.search(r"[\d.]", t):
            out.append(t)
            subs += 1
        if len(out) >= 6:
            break
    return " ".join(out)


def keys(cmd):
    return {k for k in (step_key(s) for s in segments(cmd)) if k}


def gate_keys(cmd):
    return keys(cmd) if GATE_KEYS else segments(cmd)


def kind(cmd):
    # ponytail: unquoted only, so `bash -c "npx hyperframes render"` passes (same trade as guard.sh)
    body = unquoted(cmd)
    if SKIP_FIRST_RE.search(body):
        return None
    if RENDER_RE.search(body) and "--help" not in body:
        return "span_render" if "--start" in body else "full_render"
    if INSTALL_RE.search(body):
        return "install"
    if SHOT_RE.search(body):
        return "shot_test"
    return "other"


def repo_root(cwd):
    """Walk up for .git (dir, or file in a worktree); no subprocess. Falls back to cwd."""
    d = os.path.normcase(os.path.abspath(cwd or "."))
    while True:
        if os.path.exists(os.path.join(d, ".git")):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            return os.path.normcase(os.path.abspath(cwd or "."))
        d = parent


def durations_path(cwd):
    base = os.environ.get("CL_DURATIONS") or os.path.join(os.path.expanduser("~/.claude"), "state", "durations")
    return base, os.path.join(base, hashlib.sha1(repo_root(cwd).encode("utf-8")).hexdigest() + ".json")


def load_json(p, default):
    try:
        return json.load(open(p, encoding="utf-8"))
    except (OSError, ValueError):
        return default


def slow_steps(mem, bg_ms):
    """Keys whose last 2 runs both took bg_ms or more, slowest first."""
    rows = [(sum(v["last"]) / len(v["last"]), k, v) for k, v in mem.items()
            if len(v.get("last", [])) == 2 and min(v["last"]) >= bg_ms]
    return sorted(rows, reverse=True)


def slow_list(cwd, now, bg_ms):
    base, path = durations_path(cwd)
    # Prune: stale entries here, and whole files elsewhere whose newest entry is 30+ days old.
    if os.path.isdir(base):
        for name in os.listdir(base):
            p = os.path.join(base, name)
            m = load_json(p, {})
            if not m or max(v.get("seen", 0) for v in m.values()) < now - 30 * 86400:
                os.remove(p)
    mem = load_json(path, {})
    rows = slow_steps(mem, bg_ms)[:8]
    if not rows:
        return ""
    items = "; ".join("`%s` (~%ds, e.g. `%s`)" % (k, avg / 1000, v.get("example", "")[:80]) for avg, k, v in rows)
    return ("In this repo these steps usually take %ds or more; start them with run_in_background: true and keep "
            "working: %s. After a call moves to the background, wait for its notification before git or install "
            "steps on the same tree." % (bg_ms / 1000, items))


def main():
    if os.environ.get("CL_DISABLE"):  # escape hatch, and the control arm of the gate eval
        return 0
    now = float(os.environ.get("CL_NOW") or time.time())
    bg_ms = float(os.environ.get("CL_BG_MS") or 30000)
    if len(sys.argv) == 3 and sys.argv[1] == "--slow-list":
        line = slow_list(sys.argv[2], now, bg_ms)
        if line:
            print(line)
        return 0
    d = json.load(sys.stdin)
    slow_ms = float(os.environ.get("CL_SLOW_MS") or 60000)
    home = os.path.expanduser("~/.claude")
    state_dir = os.environ.get("CL_STATE") or os.path.join(home, "state", "costly-loop")
    log_path = os.environ.get("CL_LOG") or os.path.join(home, "metrics", "loop-gate.jsonl")
    sid = re.sub(r"[^\w-]", "_", d.get("session_id") or "nosession")
    path = os.path.join(state_dir, sid + ".json")
    st = load_json(path, {})
    for k, v in {"diag": 0, "last_install": None, "last_expect": "", "last_final": None, "slow": {},
                 "blind": {}, "expect_used": {}}.items():
        st.setdefault(k, v)
    event, tool, inp = d.get("hook_event_name"), d.get("tool_name"), d.get("tool_input") or {}
    cmd = inp.get("command", "") if tool == "Bash" else ""
    bg = bool(inp.get("run_in_background"))

    def save():
        os.makedirs(state_dir, exist_ok=True)
        json.dump(st, open(path, "w", encoding="utf-8"))

    def log(rule, decision, expect="", key=""):
        os.makedirs(os.path.dirname(log_path), exist_ok=True)
        rec = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(now)), "v": VERSION, "session": sid,
               "rule": rule, "decision": decision, "agent": d.get("agent_id") or ""}
        if expect:
            rec["expect"] = expect
        if key:
            rec["key"] = key
        open(log_path, "a", encoding="utf-8").write(json.dumps(rec) + "\n")

    def blind_run(name, last):
        """Post: count a run as blind when no diagnosis came after the previous one."""
        if last is not None and st["diag"] <= last:
            st["blind"][name] = st["blind"].get(name, 0) + 1
        else:
            st["blind"][name] = 0

    if event != "PreToolUse":
        # Runs are recorded here, not in Pre: another PreToolUse hook (guard.sh) may still block the call.
        if tool != "Bash":
            return 0
        k = kind(cmd)
        if k == "install":
            blind_run("install", st["last_install"])
            st["last_install"] = now
        elif k == "full_render" and FINAL_RE.search(cmd):
            st["last_final"] = now
        elif k == "other":
            slow = (d.get("duration_ms") or 0) >= slow_ms
            for g in gate_keys(cmd):
                if g in st["slow"] and (bg or slow):  # a background launch is a rerun with no duration
                    blind_run(g, st["slow"][g])
                    st["slow"][g] = now
                elif slow:
                    st["slow"][g] = now
                    st["blind"][g] = 0
                elif not bg:  # a fast foreground run clears it
                    st["slow"].pop(g, None)
                    st["blind"].pop(g, None)
        if k is not None and not POLL_RE.search(unquoted(cmd)):
            base, dpath = durations_path(d.get("cwd"))
            mem = load_json(dpath, {})
            ks = keys(cmd)
            if bg:
                for x in ks & set(mem):
                    mem[x]["seen"] = now
            elif len(ks) == 1 and d.get("duration_ms") is not None:  # one step, so the time is its own
                x = ks.pop()
                seg = next(s for s in segments(cmd) if step_key(s) == x)
                e = mem.setdefault(x, {"last": []})
                e["last"] = (e["last"] + [d["duration_ms"]])[-2:]
                e["seen"] = now
                e["example"] = " ".join(strip_prefix(seg))[:120]
            os.makedirs(base, exist_ok=True)
            json.dump(mem, open(dpath, "w", encoding="utf-8"))
        save()
        return 0

    if tool in ("Grep", "Glob") or (tool == "Read" and not IMAGE_RE.search(inp.get("file_path", ""))):
        st["diag"] = now
        st["blind"], st["expect_used"] = {}, {}
        save()
        return 0
    if tool != "Bash":
        return 0

    k = kind(cmd)
    if k is None:
        return 0
    m = EXPECT_RE.search(cmd)
    expect = m.group(1).strip() if m and m.group(1).strip() != st["last_expect"] else ""

    def block(rule, msg, key=""):
        log(rule, "block", key=key)
        print("Blocked by costly-loop gate: " + msg, file=sys.stderr)
        return 2

    def allow(rule, why, key=""):
        if why == "expect":
            st["last_expect"] = expect
            st["expect_used"][key or rule] = True
        log(rule, "pass:" + why, expect if why == "expect" else "", key)

    def streak_msg(name, label, mem_key):
        n = st["blind"].get(name, 0) + 2  # blind reruns so far + this one, counting the first run
        e = load_json(durations_path(d.get("cwd"))[1], {}).get(mem_key or "")
        secs = " (~%ds each)" % (sum(e["last"]) / len(e["last"]) / 1000) if e and e.get("last") else ""
        return "run %d of %s%s with no diagnosis since the first." % (n, label, secs)

    if SHOT_RE.search(code_lines(cmd)):  # also when chained before an install
        st["diag"] = now
        st["blind"], st["expect_used"] = {}, {}
    if k == "full_render":
        if not FINAL_RE.search(cmd):
            return block("render", "full video render. Render only the changed span (`render --start A --end B`) "
                         "and check snapshots and frame-diff at the cuts. A full render is only for a version going "
                         "to the user: put `# final` on its own line in the command.")
        if st["last_final"] is not None and now - st["last_final"] < FINAL_WINDOW:
            return block("render", "a second `# final` render within 20 minutes is a loop. Send the user the last "
                         "one, or render only the changed span.")
        allow("render", "final")
    elif k == "install":
        if st["last_install"] is None or st["diag"] > st["last_install"]:
            allow("install", "first" if st["last_install"] is None else "diagnosed")
        elif st["blind"].get("install", 0) < 1:
            allow("install", "free")
        elif expect and not st["expect_used"].get("install"):
            allow("install", "expect")
        else:
            ik = next(iter(keys(cmd)), "")
            return block("install", streak_msg("install", "a device install", ik) + " Read the code or theme that "
                         "decides what you are changing, or run a screenshot test, first. Or add a line "
                         "`# expect: <what the screen will show and why>` (20+ chars, new text, one per streak).")
    elif k == "other":
        hit = sorted(g for g in gate_keys(cmd) if g in st["slow"])
        if hit:
            g = hit[0]
            if any(st["diag"] > st["slow"][h] for h in hit):
                allow("slow", "diagnosed", g)
            elif all(st["blind"].get(h, 0) < 1 for h in hit):
                allow("slow", "free", g)
            elif expect and not st["expect_used"].get(g):
                allow("slow", "expect", g)
            else:
                return block("slow", streak_msg(g, "the slow step `%s`" % g[:80], g if GATE_KEYS else None) +
                             " Read or grep what caused the last result first, run only the affected unit (one "
                             "slide, page, span, test), or add a line `# expect: <what this run will show and why>` "
                             "(20+ chars, new text, one per streak).", g)

    # Bounce: interactive main session only; a subagent or a -p run has no conversation to unblock.
    if (not bg and not d.get("agent_id") and os.environ.get("CLAUDE_CODE_ENTRYPOINT") != "sdk-cli"
            and not POLL_RE.search(unquoted(cmd))):
        mem = load_json(durations_path(d.get("cwd"))[1], {})
        slow = [(avg, x) for avg, x, _ in slow_steps({x: mem[x] for x in keys(cmd) if x in mem}, bg_ms)]
        if slow:
            avg, x = slow[0]
            if FG_RE.search(cmd):
                log("bounce", "pass:fg", key=x)
            else:
                save()
                log("bounce", "bounce", key=x)
                print("Bounced by costly-loop gate: `%s` usually takes ~%ds here. Rerun with run_in_background: "
                      "true and keep working (wait for its notification before git or install steps on the same "
                      "tree), or add a line `# fg` if you need the output now and have nothing else to do."
                      % (x, avg / 1000), file=sys.stderr)
                return 2
    save()
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        sys.exit(0)
