"""Costly-loop gate (added 2026-11-24): block expensive reruns that follow no diagnosis.

Hook events: PreToolUse(Bash|Read|Grep|Glob) decides; PostToolUse(Bash) and PostToolUseFailure(Bash)
record slow steps from duration_ms. Exit 2 blocks (stderr is shown to Claude). Rules:
- full video render (hyperframes render without --start) needs a `# final` line, once per 20 min
- a device install after the first needs a diagnosis since the last install, or a `# expect:` line
- a rerun of any segment of a slow (>60s) command needs a diagnosis since its last run, or `# expect:`
Diagnosis = Read of a non-image file, Grep, Glob, or a screenshot-test command. Markers count only on
their own line; an expect must be 20+ chars and differ from the session's previous one.
scripts/loop-metrics.py imports the patterns and segments() from here. Fails open on any error.
ponytail: PowerShell-tool commands bypass this (Bash only); background calls have no duration, so a
slow step launched only in the background is never recorded. Cases live in costly_loop.test.sh.
"""
import json, os, re, sys, time

RENDER_RE = re.compile(r"hyperframes(@[0-9][0-9.]*)?\s+render(\s|$)")
INSTALL_RE = re.compile(r"gradlew[^|;&]*[ :]install[A-Za-z]*|adb[^|;&]*\sinstall(\s|$)")
SHOT_RE = re.compile(r"(record|verify|compare)(Roborazzi|Paparazzi)")
SKIP_FIRST_RE = re.compile(r"^\s*(git|grep|rg|echo)(\s|$)")
IMAGE_RE = re.compile(r"\.(png|jpe?g|webp|gif)$", re.I)
EXPECT_RE = re.compile(r"^# expect: (.{20,})$", re.M)
FINAL_RE = re.compile(r"^# final$", re.M)
HEREDOC_RE = re.compile(r"<<-?\s*['\"]?(\w+)['\"]?[^\n]*\n.*?\n\s*\1\s*(\n|$)", re.S)
QUOTED_RE = re.compile(r"'[^']*'|\"(?:\\.|[^\"\\])*\"", re.S)
TRIVIAL_SEG_RE = re.compile(
    r"^(cd|rm|mkdir|ls|echo|printf|export|sed|awk|head|tail|cat|grep|rg|wc|sort|uniq|cut|tr|find|mv|cp|"
    r"git|until|while|do|done|sleep|for|if|then|else|fi|case|esac|break|time|true|test|\[|[A-Za-z_]\w*=\S*$)(\s|$)"
)
FINAL_WINDOW = 1200


def code_lines(cmd):
    return "\n".join(l for l in cmd.splitlines() if not l.lstrip().startswith("#"))


def segments(cmd):
    """Non-trivial segments, quotes and heredoc bodies removed: `python patch7.py && <pipeline>` repeats on <pipeline>."""
    body = unquoted(cmd)
    out = set()
    for s in re.split(r"&&|\|\||;|\||\n", body):
        s = " ".join(s.split())
        if len(s.split()) >= 2 and not TRIVIAL_SEG_RE.search(s) and not re.search(r"\s-[ce]?$|<<|\)$|^\S+\)", s):
            out.add(s[:200])
    return out


def unquoted(cmd):
    return QUOTED_RE.sub(" ", HEREDOC_RE.sub("\n", code_lines(cmd)))


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


def main():
    if os.environ.get("CL_DISABLE"):  # escape hatch, and the control arm of the gate eval
        return 0
    d = json.load(sys.stdin)
    now = float(os.environ.get("CL_NOW") or time.time())
    slow_ms = float(os.environ.get("CL_SLOW_MS") or 60000)
    home = os.path.expanduser("~/.claude")
    state_dir = os.environ.get("CL_STATE") or os.path.join(home, "state", "costly-loop")
    log_path = os.environ.get("CL_LOG") or os.path.join(home, "metrics", "loop-gate.jsonl")
    sid = re.sub(r"[^\w-]", "_", d.get("session_id") or "nosession")
    path = os.path.join(state_dir, sid + ".json")
    try:
        st = json.load(open(path, encoding="utf-8"))
    except (OSError, ValueError):
        st = {"diag": 0, "last_install": None, "last_expect": "", "last_final": None, "slow": {}}
    event, tool, inp = d.get("hook_event_name"), d.get("tool_name"), d.get("tool_input") or {}

    def save():
        os.makedirs(state_dir, exist_ok=True)
        json.dump(st, open(path, "w", encoding="utf-8"))

    def log(rule, decision, expect=""):
        os.makedirs(os.path.dirname(log_path), exist_ok=True)
        rec = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(now)), "session": sid, "rule": rule,
               "decision": decision, "agent": d.get("agent_id") or ""}
        if expect:
            rec["expect"] = expect
        open(log_path, "a", encoding="utf-8").write(json.dumps(rec) + "\n")

    if event != "PreToolUse":
        if tool == "Bash" and not inp.get("run_in_background") and kind(inp.get("command", "")) == "other":
            # A fast run clears its segments, so a cheap step chained once onto a slow pipeline stops counting.
            slow = (d.get("duration_ms") or 0) >= slow_ms
            for s in segments(inp.get("command", "")):
                if slow:
                    st["slow"][s] = now
                else:
                    st["slow"].pop(s, None)
            save()
        return 0

    if tool in ("Grep", "Glob") or (tool == "Read" and not IMAGE_RE.search(inp.get("file_path", ""))):
        st["diag"] = now
        save()
        return 0
    if tool != "Bash":
        return 0

    cmd = inp.get("command", "")
    k = kind(cmd)
    if k is None:
        return 0
    m = EXPECT_RE.search(cmd)
    expect = m.group(1).strip() if m and m.group(1).strip() != st["last_expect"] else ""

    def block(rule, msg):
        log(rule, "block")
        print("Blocked by costly-loop gate: " + msg, file=sys.stderr)
        return 2

    def allow(rule, why):
        if expect and why == "expect":
            st["last_expect"] = expect
        log(rule, "pass:" + why, expect if why == "expect" else "")

    if SHOT_RE.search(code_lines(cmd)):  # also when chained before an install
        st["diag"] = now
    if k == "full_render":
        if not FINAL_RE.search(cmd):
            return block("render", "full video render. Render only the changed span (`render --start A --end B`) "
                         "and check snapshots and frame-diff at the cuts. A full render is only for a version going "
                         "to the user: put `# final` on its own line in the command.")
        if st["last_final"] is not None and now - st["last_final"] < FINAL_WINDOW:
            return block("render", "a second `# final` render within 20 minutes is a loop. Send the user the last "
                         "one, or render only the changed span.")
        st["last_final"] = now
        allow("render", "final")
    elif k == "install":
        if st["last_install"] is None:
            allow("install", "first")
        elif st["diag"] > st["last_install"]:
            allow("install", "diagnosed")
        elif expect:
            allow("install", "expect")
        else:
            return block("install", "another device install with no diagnosis since the last one. Read the code or "
                         "theme that decides what you are changing, or run a screenshot test, first. Or add a line "
                         "`# expect: <what the screen will show and why>` (20+ chars, new text).")
        st["last_install"] = now
    elif k == "other" and not inp.get("run_in_background"):
        hit = sorted(s for s in segments(cmd) if s in st["slow"])
        if hit:
            if any(st["diag"] > st["slow"][s] for s in hit):
                allow("slow", "diagnosed")
            elif expect:
                allow("slow", "expect")
            else:
                return block("slow", "this reruns a slow step (`%s`) with no diagnosis since its last run. Read or "
                             "grep what caused the last result first, run only the affected unit (one slide, page, "
                             "span, test), or add a line `# expect: <what this run will show and why>` (20+ chars, "
                             "new text)." % hit[0][:80])
    save()
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        sys.exit(0)
