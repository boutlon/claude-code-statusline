#!/bin/sh
# Render README screenshots of statusline.sh in the style of Claude Code
# running inside Cursor's terminal (Cursor Dark theme, Menlo 13px).
#
# Each case feeds a hand-built JSON payload to statusline.sh, converts the
# ANSI output to HTML, and screenshots it at 2x with headless Chrome.
#
# Usage: screenshots/generate.sh [case ...]     (all cases when none given)
# Env:   CHROME=/path/to/chrome to override browser detection

set -eu

here=$(cd "$(dirname "$0")" && pwd)
script="$here/../statusline.sh"
out_dir="$here"

# ─── Browser ───

chrome=${CHROME:-}
if [ -z "$chrome" ]; then
  for c in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
           "/Applications/Chromium.app/Contents/MacOS/Chromium" \
           google-chrome chromium chromium-browser; do
    if [ -x "$c" ] || command -v "$c" >/dev/null 2>&1; then chrome=$c; break; fi
  done
fi
[ -n "$chrome" ] || { echo "no Chrome or Chromium found; set CHROME=/path/to/chrome" >&2; exit 1; }

# ─── Fixtures ───

tmp=$(mktemp -d "${TMPDIR:-/tmp}/statusline-screenshots-XXXXXX")
trap 'rm -rf "$tmp"; rm -f /tmp/claude-code-statusline-*-screenshot-*' EXIT

git_q() { git -c user.name=screenshot -c user.email=screenshot@example.com -c commit.gpgsign=false "$@"; }

# Main checkout on `main` with +121 -8 uncommitted (21 tracked lines added,
# 8 removed, plus a 100-line untracked file).
repo="$tmp/repo"
git_q init -q -b main "$repo"
seq 1 40 | sed 's/^/line /' > "$repo/app.js"
git_q -C "$repo" add -A
git_q -C "$repo" commit -q -m init
{ seq 9 40 | sed 's/^/line /'; seq 1 21 | sed 's/^/new /'; } > "$repo/app.js"
seq 1 100 | sed 's/^/util /' > "$repo/util.js"

# Linked worktree on a feature branch with +48 -12.
wt="$tmp/worktree"
git_q -C "$repo" worktree add -q -b 32-cache-countdown "$wt"
{ seq 13 40 | sed 's/^/line /'; seq 1 48 | sed 's/^/new /'; } > "$wt/app.js"

# ─── ANSI → HTML ───

# Cursor Dark terminal palette (theme-cursor/themes/cursor-dark-color-theme.json)
palette="#242424 #fc6b83 #3fa266 #d2943e #81a1c1 #b48ead #88c0d0 #f0f0f0 \
#f0f0f099 #fc6b83 #70b489 #f1b467 #87a6c4 #b48ead #88c0d0 #ffffff"

ansi_to_html() {
  awk -v palette="$palette" '
    BEGIN {
      split(palette, PAL, " ")
      re = "\033\\[[0-9;]*m"
      fg = ""; dim = 0
    }
    function esc(s) { gsub(/&/, "\\&amp;", s); gsub(/</, "\\&lt;", s); gsub(/>/, "\\&gt;", s); return s }
    function xterm(n,  r, g, b, c) {
      if (n < 16) return PAL[n + 1]
      if (n >= 232) { c = 8 + (n - 232) * 10; return sprintf("#%02x%02x%02x", c, c, c) }
      n -= 16; r = int(n / 36); g = int((n % 36) / 6); b = n % 6
      return sprintf("#%02x%02x%02x", r ? r * 40 + 55 : 0, g ? g * 40 + 55 : 0, b ? b * 40 + 55 : 0)
    }
    # Shade blocks become CSS-drawn cells (class b1..b4) so they match the
    # dot lattices xterm.js draws for them instead of a fallback font glyph.
    # The UTF-8 bytes are written as octal escapes, which every POSIX awk
    # accepts (mawk does not understand \x hex escapes).
    function span(text,  t) {
      if (text == "") return ""
      t = esc(text)
      gsub("\342\226\221", "<i class=\"b1\"></i>", t)
      gsub("\342\226\222", "<i class=\"b2\"></i>", t)
      gsub("\342\226\223", "<i class=\"b3\"></i>", t)
      gsub("\342\226\210", "<i class=\"b4\"></i>", t)
      return "<span style=\"color:" (fg == "" ? "#f0f0f0" : fg) (dim ? ";opacity:.5" : "") "\">" t "</span>"
    }
    {
      line = $0; out = ""
      while (match(line, re)) {
        out = out span(substr(line, 1, RSTART - 1))
        seq = substr(line, RSTART + 2, RLENGTH - 3)
        line = substr(line, RSTART + RLENGTH)
        n = split(seq, p, ";")
        if (n == 0) { fg = ""; dim = 0 }
        for (i = 1; i <= n; i++) {
          c = p[i] + 0
          if (c == 0) { fg = ""; dim = 0 }
          else if (c == 2) dim = 1
          else if (c >= 30 && c <= 37) fg = PAL[c - 30 + 1]
          else if (c >= 90 && c <= 97) fg = PAL[c - 90 + 9]
          else if (c == 38 && p[i + 1] == 5) { fg = xterm(p[i + 2] + 0); i += 2 }
        }
      }
      print out span(line)
    }'
}

# ─── Rendering ───

# Geometry matches a Claude Code prompt box in Cursor at 1x: 685px wide,
# 100px tall for a one-line statusline, plus 18px per extra line.
render() {
  name=$1; cwd=$2; sid="screenshot-$name"
  rm -f /tmp/claude-code-statusline-*-"$sid" /tmp/claude-code-statusline-*-"$sid".restart

  now=$(date +%s)
  json=$(jq -n \
    --arg cwd "$cwd" --arg sid "$sid" --arg model "$MODEL" \
    --argjson used "$USED" --argjson ctx "$CTX" --argjson tpm "$TPM" --argjson now "$now" \
    --arg rl5 "$RL5" --arg rl5_in "$RL5_IN" --arg rl7 "$RL7" --arg rl7_in "$RL7_IN" \
    --arg cache "$CACHE" --arg cache_in "$CACHE_IN" '
    { cwd: $cwd, session_id: $sid, model: { display_name: $model },
      context_window: { used_percentage: $used, context_window_size: $ctx,
                        total_input_tokens: $tpm, total_output_tokens: 0 },
      cost: { total_duration_ms: 60000 } }
    | if $rl5 != "" then .rate_limits.five_hour = { used_percentage: ($rl5 | tonumber), resets_at: ($now + ($rl5_in | tonumber)) } else . end
    | if $rl7 != "" then .rate_limits.seven_day = { used_percentage: ($rl7 | tonumber), resets_at: ($now + ($rl7_in | tonumber)) } else . end
    | if $cache != "" then .prompt_cache = { warm: ($cache == "warm"), expires_at: ($now + ($cache_in | tonumber)) } else . end')

  # Override forces the context percentage to display as given (no rescale).
  # Run from $cwd like Claude Code does, so untracked paths resolve.
  ansi=$(cd "$cwd" && printf '%s' "$json" | CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=100 sh "$script")
  lines=$(printf '%s\n' "$ansi" | wc -l | tr -d ' ')
  height=$((100 + (lines - 1) * 18))
  html="$tmp/$name.html"

  {
    cat <<'EOF'
<!doctype html>
<meta charset="utf-8">
<style>
  html, body { margin: 0; background: transparent; }
  .card { box-sizing: border-box; width: 685px; padding: 22px 22px 19px; background: #141414;
          border-radius: 8px; font: 13px/18px Menlo, Monaco, monospace; color: #f0f0f0; }
  .rule { border-top: 1px solid #808080; }
  .prompt { padding: 8px 0 8px 1px; line-height: 17px; color: #999; }
  .cursor { display: inline-block; width: 8px; height: 17px; vertical-align: -4px; background: #e4e4e4; }
  .status { margin: 0; padding: 6px 0 0 20px; white-space: pre; font: inherit; }
  /* Context bar cells, masked with the xterm.js shade patterns at device pixels (2x). */
  .b1, .b2, .b3, .b4 { display: inline-block; width: 8px; height: 17px; vertical-align: -4px; background: currentColor; }
  .b1 { -webkit-mask: url("data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' width='4' height='4' shape-rendering='crispEdges'><rect width='1' height='1'/><rect x='2' y='2' width='1' height='1'/></svg>") 0 0/2px 2px;
        mask: url("data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' width='4' height='4' shape-rendering='crispEdges'><rect width='1' height='1'/><rect x='2' y='2' width='1' height='1'/></svg>") 0 0/2px 2px; }
  .b2 { -webkit-mask: url("data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' width='2' height='4' shape-rendering='crispEdges'><rect width='1' height='1'/><rect x='1' y='2' width='1' height='1'/></svg>") 0 0/1px 2px;
        mask: url("data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' width='2' height='4' shape-rendering='crispEdges'><rect width='1' height='1'/><rect x='1' y='2' width='1' height='1'/></svg>") 0 0/1px 2px; }
  .b3 { -webkit-mask: url("data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' width='2' height='4' shape-rendering='crispEdges'><rect x='1' width='1' height='1'/><rect y='1' width='2' height='1'/><rect y='2' width='1' height='1'/><rect y='3' width='2' height='1'/></svg>") 0 0/1px 2px;
        mask: url("data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' width='2' height='4' shape-rendering='crispEdges'><rect x='1' width='1' height='1'/><rect y='1' width='2' height='1'/><rect y='2' width='1' height='1'/><rect y='3' width='2' height='1'/></svg>") 0 0/1px 2px; }
</style>
<div class="card">
  <div class="rule"></div>
  <div class="prompt">&#10095; <span class="cursor"></span></div>
  <div class="rule"></div>
  <pre class="status">
EOF
    printf '%s\n' "$ansi" | ansi_to_html
    printf '</pre>\n</div>\n'
  } > "$html"

  screenshot "$html" "$out_dir/$name.png" "$height"
  echo "$name.png"
}

# Headless Chrome reports the write on stderr but does not always exit
# afterwards on macOS, so wait for the report and then stop it ourselves.
screenshot() {
  html=$1; png=$2; height=$3; log="$tmp/chrome.log"
  rm -f "$png"
  "$chrome" --headless=new --disable-gpu --no-first-run --no-default-browser-check \
    --user-data-dir="$tmp/chrome" --hide-scrollbars --default-background-color=00000000 \
    --force-device-scale-factor=2 --window-size=685,"$height" \
    --screenshot="$png" "file://$html" >"$log" 2>&1 &
  pid=$!
  i=0
  while ! grep -q 'written to file' "$log" 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -gt 150 ] || ! kill -0 "$pid" 2>/dev/null; then break; fi
    sleep 0.2
  done
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  [ -s "$png" ] || { echo "screenshot failed for $png; see $log" >&2; cat "$log" >&2; exit 1; }
}

# ─── Cases ───

# Reset offsets sit mid-minute so the script's own clock read cannot round
# a countdown down across a boundary.
reset_case() {
  MODEL="Fable 5.1"; USED=8; CTX=200000; TPM=503
  RL5=""; RL5_IN=0; RL7=""; RL7_IN=0; CACHE=""; CACHE_IN=0
}

run_case() {
  case $1 in
    default)      # calm session: branch, small diff, low context
      reset_case
      render default "$repo" ;;
    context)      # context climbing and high throughput
      reset_case; USED=78; TPM=12300
      render context "$repo" ;;
    rate-limits)  # second line: 5h and 7d windows with countdowns
      reset_case; USED=34; TPM=4800
      RL5=62; RL5_IN=8070; RL7=81; RL7_IN=277230
      render rate-limits "$repo" ;;
    cache)        # prompt cache about to go cold
      reset_case; USED=41; TPM=2100; CACHE=warm; CACHE_IN=270
      render cache "$repo" ;;
    cache-cold)   # prompt cache expired
      reset_case; USED=41; CACHE=cold; CACHE_IN=-30
      render cache-cold "$repo" ;;
    worktree)     # linked worktree on a feature branch
      reset_case; USED=52; TPM=6700
      render worktree "$wt" ;;
    context-1m)   # 1M context variant
      reset_case; CTX=1000000; USED=23; TPM=3400
      render context-1m "$repo" ;;
    everything)   # every segment at once
      reset_case; USED=91; TPM=24000; CTX=1000000
      RL5=88; RL5_IN=3330; RL7=54; RL7_IN=190830; CACHE=warm; CACHE_IN=90
      render everything "$wt" ;;
    *) echo "unknown case: $1" >&2; exit 1 ;;
  esac
}

if [ $# -eq 0 ]; then
  set -- default context rate-limits cache cache-cold worktree context-1m everything
fi
for c in "$@"; do run_case "$c"; done
