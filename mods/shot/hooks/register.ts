import type { Register } from 'claude-code'

export type Args = { url: string; label: string } | { error: string }

// Only http(s) and file URLs: a leading "-" would be read as an agent-browser flag.
export const parseArgs = (raw: string): Args => {
  const [url, ...rest] = raw.trim().split(/\s+/)
  if (!url || !/^(https?|file):\/\/\S+$/i.test(url)) return { error: 'Usage: /shot <http(s)://url> [label]' }
  const name = rest.join('-') || new URL(url).host || 'page'
  return { url, label: name.replace(/[^\w.-]+/g, '_').slice(0, 60) || 'page' }
}

// One script, two modes: `dir <label>` prints the scratch folder; `compare <dir>` diffs before/after
// and writes diff.png + compare.html next to them. Pillow comes from `uv run --with pillow`.
export const PY = `
import sys, os, tempfile, html
mode = sys.argv[1]
if mode == "dir":
    d = os.path.join(tempfile.gettempdir(), "claude-shot", sys.argv[2])
    os.makedirs(d, exist_ok=True)
    print(d)
elif mode == "reset":
    for n in ("after.png", "diff.png"):
        p = os.path.join(sys.argv[2], n)
        if os.path.exists(p):
            os.remove(p)
else:
    from PIL import Image, ImageChops
    d = sys.argv[2]
    a = Image.open(os.path.join(d, "before.png")).convert("RGB")
    b = Image.open(os.path.join(d, "after.png")).convert("RGB")
    w, h = max(a.width, b.width), max(a.height, b.height)
    pad = lambda im: im if im.size == (w, h) else (lambda c: (c.paste(im, (0, 0)), c)[1])(Image.new("RGB", (w, h), (255, 255, 255)))
    a, b = pad(a), pad(b)
    diff = ImageChops.difference(a, b)
    changed = diff.convert("L").point(lambda v: 255 if v > 8 else 0).histogram()[255]
    pct = 100.0 * changed / (w * h)
    Image.eval(diff, lambda v: 255 if v > 8 else 0).save(os.path.join(d, "diff.png"))
    cell = lambda t, f: "<figure><figcaption>%s</figcaption><img src='%s'></figure>" % (t, f)
    page = "<!doctype html><meta charset=utf-8><title>shot compare</title><style>body{font:14px system-ui;margin:16px;background:#fff;color:#111}.row{display:flex;gap:12px;align-items:flex-start}figure{margin:0;flex:1;min-width:0}img{width:100%%;border:1px solid #ccc}figcaption{font-weight:600;margin-bottom:4px}</style><h1>%s</h1><p>%.2f%% of pixels changed (%d of %d)</p><div class=row>%s%s%s</div>" % (html.escape(os.path.basename(d)), pct, changed, w * h, cell("before", "before.png"), cell("after", "after.png"), cell("diff", "diff.png"))
    open(os.path.join(d, "compare.html"), "w", encoding="utf-8").write(page)
    print("%.2f" % pct)
`

type Run = (argv: readonly string[], init?: { timeoutMs?: number }) => Promise<{ exitCode: number; stdout: string; stderr: string }>

const py = (run: Run, ...args: string[]) => run(['uv', 'run', '--with', 'pillow', 'python', '-I', '-c', PY, ...args], { timeoutMs: 120000 })

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({ name: 'shot', description: 'Before/after screenshot diff of a URL', argumentHint: '<url> [label]' })
    return next(e)
  })

  on('command.run', { command: 'shot' }, async ($, e) => {
    const a = parseArgs(e.args)
    if ('error' in a) return { text: a.error }
    const run: Run = (argv, init) => $.process.run(argv, init)
    try {
      const d = await py(run, 'dir', a.label)
      if (d.exitCode !== 0) return { text: `/shot: python/pillow step failed: ${d.stderr.trim().slice(-300)}` }
      const dir = d.stdout.trim()
      // before without after = waiting for the second shot; both present = a finished pair, so start a new one
      const hasBefore = (await $.fs.exists(`${dir}/before.png`)) && !(await $.fs.exists(`${dir}/after.png`))
      const name = hasBefore ? 'after' : 'before'
      if (!hasBefore) await py(run, 'reset', dir)
      try {
        const o = await run(['agent-browser', 'open', a.url], { timeoutMs: 60000 })
        if (o.exitCode !== 0) return { text: `/shot: agent-browser open failed: ${(o.stderr || o.stdout).trim().slice(-300)}` }
        await run(['agent-browser', 'wait', '--load', 'load'], { timeoutMs: 30000 })
        const s = await run(['agent-browser', 'screenshot', '--full', `${dir}/${name}.png`], { timeoutMs: 60000 })
        if (s.exitCode !== 0) return { text: `/shot: screenshot failed: ${(s.stderr || s.stdout).trim().slice(-300)}` }
      } finally {
        await run(['agent-browser', 'close']).catch(() => undefined)
      }
      if (!hasBefore) return { text: `/shot: stored "before" for ${a.label}. Change the page, then run /shot ${a.url} ${a.label} again.` }
      const c = await py(run, 'compare', dir)
      if (c.exitCode !== 0) return { text: `/shot: compare failed: ${c.stderr.trim().slice(-300)}` }
      return { text: `/shot: ${c.stdout.trim()}% of pixels changed.\nCompare page: ${dir}/compare.html` }
    } catch (err) {
      return { text: `/shot failed: ${String(err).slice(0, 300)}` }
    }
  })
}
