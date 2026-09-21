#!/usr/bin/env bats

load 'helpers'

# A repo on branch test-branch with one uncommitted insertion (+1)
make_repo() {
  TEST_GIT_REPO=$(mktemp -d)
  git -C "$TEST_GIT_REPO" init -b test-branch >/dev/null 2>&1
  git -C "$TEST_GIT_REPO" -c user.name=test -c user.email=test@test commit --allow-empty -m "init" >/dev/null 2>&1
  printf 'a\nb\n' > "$TEST_GIT_REPO/file.txt"
  git -C "$TEST_GIT_REPO" add file.txt
  git -C "$TEST_GIT_REPO" -c user.name=test -c user.email=test@test commit -m "add file" >/dev/null 2>&1
  printf 'a\nb\nc\n' > "$TEST_GIT_REPO/file.txt"
}

# ─── CLAUDE_STATUSLINE_HIDE parsing ───

@test "hide: names are matched inside a comma-separated list with spaces" {
  add_message 10 0 0 0 3000
  CLAUDE_STATUSLINE_HIDE="diff, tpm" run run_tpm
  [[ "$(plain)" != *"tpm"* ]]
}

@test "hide: unrecognized or partial names change nothing" {
  add_message 10 0 0 0 3000
  CLAUDE_STATUSLINE_HIDE=nope run run_tpm
  [[ "$(plain)" == *"3.0k tpm"* ]]
  CLAUDE_STATUSLINE_HIDE=tpmx run run_tpm
  [[ "$(plain)" == *"3.0k tpm"* ]]
}

@test "hide: empty value changes nothing" {
  add_message 10 0 0 0 3000
  CLAUDE_STATUSLINE_HIDE= run run_tpm
  [ "$(plain)" = "✦ Opus 4.6  █░░░░ 25%  ϟ 3.0k tpm" ]
}

# ─── branch / diff ───

@test "hide: branch hides the branch but keeps the diff" {
  make_repo
  CLAUDE_STATUSLINE_HIDE=branch run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_GIT_REPO"
  [[ "$(plain)" != *"test-branch"* ]]
  [[ "$(plain)" != *"⌥"* ]]
  [[ "$(plain)" == "+1  ✦ Opus 4.6"* ]]
}

@test "hide: diff hides the diff but keeps the branch" {
  make_repo
  CLAUDE_STATUSLINE_HIDE=diff run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_GIT_REPO"
  [[ "$(plain)" != *"+1"* ]]
  [[ "$(plain)" == "⌥ test-branch  ✦ Opus 4.6"* ]]
}

@test "hide: branch and diff together leave no git segment" {
  make_repo
  CLAUDE_STATUSLINE_HIDE=branch,diff run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_GIT_REPO"
  [[ "$(plain)" == "✦ Opus 4.6"* ]]
}

# ─── model / context ───

@test "hide: model hides the model name and 1M marker" {
  add_message 10 0 0 0 3000
  CLAUDE_STATUSLINE_HIDE=model run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 0 0 "" "$(transcript_path)" "" "" "" "" 1000000
  [[ "$(plain)" != *"✦"* ]]
  [[ "$(plain)" != *"1M"* ]]
  [ "$(plain)" = "█░░░░ 25%  ϟ 3.0k tpm" ]
}

@test "hide: context hides the bar and percentage" {
  add_message 10 0 0 0 3000
  CLAUDE_STATUSLINE_HIDE=context run run_tpm
  [[ "$(plain)" != *"25%"* ]]
  [ "$(plain)" = "✦ Opus 4.6  ϟ 3.0k tpm" ]
}

# ─── tpm ───

@test "hide: tpm hides the tpm indicator" {
  add_message 10 0 0 0 3000
  CLAUDE_STATUSLINE_HIDE=tpm run run_tpm
  [ "$(plain)" = "✦ Opus 4.6  █░░░░ 25%" ]
}

# ─── limits ───

@test "hide: limits hides rate limits and writes no usage state" {
  now=$(date +%s)
  CLAUDE_STATUSLINE_HIDE=limits run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "" "" 90 "$((now + 9000))" 90 "$((now + 300000))"
  [[ "$(plain)" != *"5h"* ]]
  [[ "$(plain)" != *"7d"* ]]
  [[ "$output" != *$'\n'* ]]
  [ ! -f "/tmp/claude-code-statusline-usage-${TEST_SID}" ]
}

# ─── cache ───

@test "hide: cache hides the prompt cache segment" {
  now=$(date +%s)
  # Cold cache would otherwise always render on line 2
  make_json "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 \
    | jq --argjson exp "$((now - 60))" '.prompt_cache = { warm: false, ttl: "1h", expires_at: $exp }' \
    > "$BATS_TEST_TMPDIR/payload.json"
  run env CLAUDE_STATUSLINE_HIDE=cache CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=100 sh "$SCRIPT" < "$BATS_TEST_TMPDIR/payload.json"
  [ "$status" -eq 0 ]
  [[ "$(plain)" != *"cache"* ]]
  [[ "$output" != *$'\n'* ]]
}

# ─── combinations ───

@test "hide: all of line 1 leaves line 2 without a leading blank line" {
  now=$(date +%s)
  CLAUDE_STATUSLINE_HIDE=branch,diff,model,context,tpm run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "" "" 90 "$((now + 9000))" "" ""
  [[ "$(plain)" == "5h 90%"* ]]
}

@test "hide: everything produces empty output" {
  now=$(date +%s)
  make_json "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "" "" 90 "$((now + 9000))" "" "" \
    | jq --argjson exp "$((now - 60))" '.prompt_cache = { warm: false, ttl: "1h", expires_at: $exp }' \
    > "$BATS_TEST_TMPDIR/payload.json"
  run env CLAUDE_STATUSLINE_HIDE=branch,diff,model,context,tpm,limits,cache CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=100 sh "$SCRIPT" < "$BATS_TEST_TMPDIR/payload.json"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
