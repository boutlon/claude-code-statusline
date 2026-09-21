#!/usr/bin/env bats

load 'helpers'

# Run the script with a prompt_cache object added to the standard payload.
# Args: warm expires_at [rl_5h_pct rl_5h_reset]
run_cache() {
  local warm="$1" expires="$2" rl_pct="${3:-}" rl_reset="${4:-}"
  make_json "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "" "" "$rl_pct" "$rl_reset" "" "" \
    | jq --argjson warm "$warm" --argjson exp "$expires" \
        '.prompt_cache = { warm: $warm, ttl: "1h", expires_at: $exp }' \
    | env CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=100 sh "$SCRIPT"
}

# ─── Visibility ───

@test "cache: hidden when prompt_cache absent" {
  run run_sl "Opus 4.6" 25
  [ "$status" -eq 0 ]
  [[ "$(plain)" != *"cache"* ]]
}

@test "cache: hidden when expires_at is null" {
  run run_cache true null
  [ "$status" -eq 0 ]
  [[ "$(plain)" != *"cache"* ]]
}

@test "cache: hidden when expires_at is non-numeric, other fields unaffected" {
  run run_cache true '"soon"'
  [ "$status" -eq 0 ]
  [[ "$(plain)" != *"cache"* ]]
  [[ "$(plain)" == *"Opus 4.6"* ]]
}

@test "cache: hidden while warm with more than 10m left" {
  now=$(date +%s)
  run run_cache true $((now + 660))
  [ "$status" -eq 0 ]
  [[ "$(plain)" != *"cache"* ]]
  [[ "$(plain)" != *$'\n'* ]]
}

@test "cache: line 2 holds only the cache segment when rate limits are hidden" {
  now=$(date +%s)
  run run_cache true $((now + 480))
  [ "$status" -eq 0 ]
  [ "$(plain | sed -n '2p')" = "cache 8m" ]
}

@test "cache: rendered after rate limits with the standard separator" {
  now=$(date +%s)
  run run_cache true $((now + 480)) 80 $((now + 3600))
  [ "$status" -eq 0 ]
  [[ "$(plain | sed -n '2p')" == "5h 80% "*"  cache 8m" ]]
}

# ─── Countdown tiers ───

@test "cache: yellow from 10m down" {
  now=$(date +%s)
  run run_cache true $((now + 600))
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033[93m'"cache 10m"* ]]
}

@test "cache: orange under 5m" {
  now=$(date +%s)
  run run_cache true $((now + 299))
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033[38;5;208m'"cache 4m"* ]]
}

@test "cache: red under 2m" {
  now=$(date +%s)
  run run_cache true $((now + 119))
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033[91m'"cache 1m"* ]]
}

@test "cache: under a minute floors to <1m instead of seconds" {
  now=$(date +%s)
  run run_cache true $((now + 30))
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033[91m'"cache <1m"* ]]
  [[ "$(plain)" != *"30s"* ]]
}

# ─── Cold ───

@test "cache: cold in blue once expires_at has passed" {
  now=$(date +%s)
  run run_cache true $((now - 5))
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033[38;5;63m'"cache cold"* ]]
}

@test "cache: cold at the exact expiry second" {
  now=$(date +%s)
  run run_cache true "$now"
  [ "$status" -eq 0 ]
  [[ "$(plain)" == *"cache cold"* ]]
}

@test "cache: cold when warm is false even with a future expires_at" {
  now=$(date +%s)
  run run_cache false $((now + 3000))
  [ "$status" -eq 0 ]
  [[ "$(plain)" == *"cache cold"* ]]
}
