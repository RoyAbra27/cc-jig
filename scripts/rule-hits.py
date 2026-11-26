"""Count how often each skill-router row fired in main-session transcripts, plus ratchet corrections.

Usage: python scripts/rule-hits.py [days=30]. Read-only; prints Markdown, quotes no transcript text.
A row fires when a name in its "Reach for" cell is a Skill or Agent call, or is announced
("Using <name> to ..."). Rows at 0 are candidates for the /reflect counts mode to cut or merge.
ponytail: announcement match is a loose regex; a skipped announcement still counts via the tool call.
"""
import glob, json, os, re, sys, time

CFG = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
days = int(sys.argv[1]) if len(sys.argv) > 1 else 30
cut = time.time() - days * 86400

rows = []
for line in open(os.path.join(CFG, "hooks", "skill-router.md"), encoding="utf-8"):
    cells = [c.strip() for c in line.strip().strip("|").split("|")]
    if len(cells) < 2 or cells[0] in ("Situation", "") or set(cells[0]) <= set("-"):
        continue
    names = set(re.findall(r"`/?([\w:.-]+)`", cells[1])) | set(re.findall(r"\bsuperpowers:[\w-]+", cells[1]))
    names = {n.split(":")[-1] for n in names if not n.startswith("-")}
    rows.append((cells[0], sorted(names)))

hits = {n: 0 for _, ns in rows for n in ns}
cmd_rx = re.compile(r"<command-name>/?([\w:.-]+)</command-name>")
announce = {n: re.compile(r"\bUsing\b[^\n.]{0,40}\b" + re.escape(n) + r"\b") for n in hits}
sessions = 0
for f in glob.glob(os.path.join(CFG, "projects", "**", "*.jsonl"), recursive=True):
    if "subagents" in f or "ab-fixture-" in f or os.path.getmtime(f) < cut:
        continue
    sessions += 1
    for line in open(f, encoding="utf-8", errors="replace"):
        # commands the user typed (/goal, /advisor) appear as <command-name> in user lines
        for n in cmd_rx.findall(line):
            if n in hits:
                hits[n] += 1
        if '"assistant"' not in line:
            continue
        try:
            content = json.loads(line).get("message", {}).get("content", [])
        except ValueError:
            continue
        for c in content if isinstance(content, list) else []:
            if not isinstance(c, dict):
                continue
            if c.get("type") == "tool_use":
                inp = c.get("input") or {}
                called = str(inp.get("skill") or inp.get("subagent_type") or "").split(":")[-1]
                if called in hits:
                    hits[called] += 1
                else:
                    # MCP tools (mcp__claude-in-chrome__*) and CLIs run through Bash (agent-browser ...)
                    first = str(inp.get("command") or "").split(" ", 1)[0]
                    for n in hits:
                        if n == first or ("__" + n + "__") in c.get("name", ""):
                            hits[n] += 1
            elif c.get("type") == "text":
                for n, rx in announce.items():
                    hits[n] += len(rx.findall(c.get("text", "")))

print(f"## Router rows fired, last {days} days ({sessions} main sessions)\n")
print("| row | names | hits |\n|---|---|---|")
for situation, ns in sorted(rows, key=lambda r: sum(hits[n] for n in r[1])):
    count = sum(hits[n] for n in ns) if ns else "n/a (names no skill)"
    print(f"| {situation[:60]} | {', '.join(ns)} | {count} |")

rp = os.path.expanduser("~/.claude-mods-data/ratchet.json")
if os.path.exists(rp):
    counts = json.load(open(rp, encoding="utf-8")).get("counts", {})
    print("\n## Ratchet corrections per CLAUDE.md heading\n")
    for k, v in sorted(counts.items(), key=lambda kv: -kv[1]):
        print(f"- {k}: {v}")
