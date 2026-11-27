#!/usr/bin/env bash
# Validation pipeline: build → speech tests → UI snapshots → HTML report.
# Usage: scripts/validate.sh   (report: build/validate/report.html; exits 1 if a test fails)
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="build/validate"
BIN=".build/arm64-apple-macosx/release/Vocality"

if ! xcodebuild -version >/dev/null 2>&1; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

rm -rf "$OUT" && mkdir -p "$OUT/audio"

echo "1/3 Build"
START=$(date +%s)
swift build -c release --arch arm64 2>&1 | tail -1
BUILD_SECONDS=$(( $(date +%s) - START ))
BINARY_BYTES=$(stat -f%z "$BIN")

echo "2/3 Speech tests"
# Each case: id | sentence spoken by `say` | text Vocality should produce.
CASES=(
    "agent|Open cloud code and add a dark mode toggle to the settings page.|Open Claude Code and add a dark mode toggle to the settings page."
    "github|Then run the tests and push the branch to get hub.|Then run the tests and push the branch to GitHub."
    "plain|The meeting moved to Thursday at three in the afternoon.|The meeting moved to Thursday at three in the afternoon."
)
RESULTS="$OUT/results.tsv"
: > "$RESULTS"
for c in "${CASES[@]}"; do
    IFS='|' read -r id spoken expected <<< "$c"
    wav="$OUT/audio/$id.wav"
    say -o "$wav" --data-format=LEI16@16000 "$spoken"
    t0=$(python3 -c 'import time; print(time.time())')
    actual=$("$BIN" --transcribe "$wav" 2>/dev/null | tail -1)
    t1=$(python3 -c 'import time; print(time.time())')
    printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$spoken" "$expected" "$actual" "$(python3 -c "print(round($t1-$t0,2))")" >> "$RESULTS"
done

echo "3/3 Snapshots"
"$BIN" --snapshot "$OUT" 2>/dev/null

python3 - "$OUT" "$BUILD_SECONDS" "$BINARY_BYTES" <<'PY'
import html, re, sys, pathlib, datetime
out, build_s, binary = pathlib.Path(sys.argv[1]), sys.argv[2], int(sys.argv[3])

def words(s): return re.findall(r"[a-z0-9.]+", s.lower().replace(".", " ").replace(",", " "))
def wer(ref, hyp):
    r, h = words(ref), words(hyp)
    d = [[i + j if i * j == 0 else 0 for j in range(len(h) + 1)] for i in range(len(r) + 1)]
    for i in range(1, len(r) + 1):
        for j in range(1, len(h) + 1):
            d[i][j] = min(d[i-1][j] + 1, d[i][j-1] + 1, d[i-1][j-1] + (r[i-1] != h[j-1]))
    return d[len(r)][len(h)] / max(1, len(r))

rows, failed = [], 0
for line in (out / "results.tsv").read_text().splitlines():
    cid, spoken, expected, actual, secs = line.split("\t")
    exact = actual.strip() == expected.strip()
    err = wer(expected, actual)
    ok = exact or err <= 0.1
    failed += not ok
    rows.append((cid, spoken, expected, actual, secs, err, ok))

e = html.escape
def img(name, alt): return f'<figure><img src="{name}" alt="{e(alt)}"><figcaption>{e(alt)}</figcaption></figure>'
states = [("resting", "Resting capsule (opening)"), ("recording", "Recording, send armed"), ("recording-noautosend", "Recording, no auto-send"),
          ("transcribing", "Transcribing"), ("sent", "Sent"), ("pasted", "Pasted"), ("error", "Error")]
test_rows = "".join(
    f'<tr><td><span class="badge {"pass" if ok else "fail"}">{"Pass" if ok else "Fail"}</span></td>'
    f'<td>{e(cid)}</td><td>{e(spoken)}<br><audio controls src="audio/{e(cid)}.wav"></audio></td>'
    f'<td>{e(expected)}</td><td>{e(actual)}</td><td class="num">{err:.0%}</td><td class="num">{secs}s</td></tr>'
    for cid, spoken, expected, actual, secs, err, ok in rows)
summary = "All checks passed" if not failed else f"{failed} check{'s' if failed > 1 else ''} failed"

page = f"""<title>Vocality Validation</title>
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="claude:viewport-fit-sides" content="cover">
<style>
:root {{ --bg:#F5F9FF; --card:#FFFFFF; --line:#D8E6FA; --ink:#0E1A2B; --muted:#4A5B73; --accent:#1A63C7; --pass:#0F7B4F; --fail:#B42318; --chip:#E3F0FF; }}
@media (prefers-color-scheme: dark) {{ :root:not([data-theme="light"]) {{ --bg:#10151C; --card:#18202A; --line:#2A3646; --ink:#E8EEF6; --muted:#9AA8BB; --accent:#7CC0FF; --pass:#4ADE80; --fail:#F87171; --chip:#1D2C40; color-scheme: dark; }} }}
:root[data-theme="dark"] {{ --bg:#10151C; --card:#18202A; --line:#2A3646; --ink:#E8EEF6; --muted:#9AA8BB; --accent:#7CC0FF; --pass:#4ADE80; --fail:#F87171; --chip:#1D2C40; color-scheme: dark; }}
* {{ box-sizing: border-box; }}
body {{ margin:0; background:var(--bg); color:var(--ink); font:15px/1.5 -apple-system, BlinkMacSystemFont, "Inter", sans-serif; }}
main {{ max-width:1100px; margin:0 auto; padding-block:32px 64px; padding-left:max(16px, env(safe-area-inset-left, 0px)); padding-right:max(16px, env(safe-area-inset-right, 0px)); }}
h1, h2 {{ text-wrap: balance; }}
.stat b, .num {{ font-variant-numeric: tabular-nums; }}
h1 {{ font-size:28px; margin:0 0 4px; }} h2 {{ font-size:18px; margin:40px 0 12px; }}
.muted {{ color:var(--muted); }}
.stats {{ display:grid; grid-template-columns:repeat(auto-fit,minmax(160px,1fr)); gap:12px; margin-top:20px; }}
.stat {{ background:var(--card); border:1px solid var(--line); border-radius:12px; padding:14px 16px; }}
.stat b {{ display:block; font-size:22px; }}
.table-wrap {{ overflow-x:auto; background:var(--card); border:1px solid var(--line); border-radius:12px; }}
table {{ border-collapse:collapse; width:100%; min-width:760px; }}
th, td {{ text-align:left; padding:10px 12px; border-bottom:1px solid var(--line); vertical-align:top; font-size:14px; }}
th {{ color:var(--muted); font-weight:600; font-size:12px; }}
tr:last-child td {{ border-bottom:0; }} .num {{ text-align:right; white-space:nowrap; }}
audio {{ height:28px; margin-top:6px; max-width:220px; }}
.badge {{ display:inline-block; padding:2px 8px; border-radius:999px; font-size:12px; font-weight:600; }}
.pass {{ color:var(--pass); border:1px solid currentColor; }} .fail {{ color:var(--fail); border:1px solid currentColor; }}
.grid {{ display:grid; grid-template-columns:repeat(auto-fit,minmax(300px,1fr)); gap:16px; }}
figure {{ margin:0; background:var(--card); border:1px solid var(--line); border-radius:12px; padding:12px; }}
figure img {{ width:100%; height:auto; display:block; border-radius:8px; }}
figcaption {{ font-size:13px; color:var(--muted); margin-top:8px; }}
.sounds {{ display:flex; flex-wrap:wrap; gap:16px; }}
.sounds div {{ background:var(--card); border:1px solid var(--line); border-radius:12px; padding:12px 16px; }}
</style><main>
<h1>Vocality validation</h1>
<p class="muted">{datetime.datetime.now().strftime("%Y-%m-%d %H:%M")} · <strong style="color:var({'--pass' if not failed else '--fail'})">{summary}</strong></p>
<div class="stats">
<div class="stat"><span class="muted">Speech tests</span><b>{len(rows) - failed}/{len(rows)} pass</b></div>
<div class="stat"><span class="muted">Binary size</span><b>{binary/1e6:.1f} MB</b></div>
<div class="stat"><span class="muted">Build time</span><b>{build_s}s</b></div>
<div class="stat"><span class="muted">Model</span><b>Parakeet V3</b></div>
</div>
<h2>Speech tests</h2>
<p class="muted">Audio is generated with macOS <code>say</code> and transcribed by Vocality on device. A case passes on an exact match or a word error rate of 10% or less. Times include model load.</p>
<div class="table-wrap"><table><thead><tr><th>Result</th><th>Case</th><th>Spoken</th><th>Expected</th><th>Got</th><th class="num">WER</th><th class="num">Time</th></tr></thead><tbody>{test_rows}</tbody></table></div>
<h2>Sounds</h2>
<div class="sounds"><div>Start<br><audio controls src="sound-start.wav"></audio></div><div>Stop<br><audio controls src="sound-stop.wav"></audio></div></div>
<h2>Recorder, light</h2>
<div class="grid">{"".join(img(f"overlay-{k}-light.png", v) for k, v in states)}</div>
<h2>Recorder, dark</h2>
<div class="grid">{"".join(img(f"overlay-{k}-dark.png", v) for k, v in states)}</div>
<h2>Settings window</h2>
<p class="muted">System switches and pickers can't be drawn offscreen and appear as placeholders. Liquid Glass and the window blur need the live desktop behind them, so these renders show the frosted fallback.</p>
<div class="grid">{img("window-light.png", "Light")}{img("window-dark.png", "Dark")}</div>
</main>"""
(out / "report.html").write_text(page)
print(summary)
sys.exit(1 if failed else 0)
PY
echo "Report: $OUT/report.html"
