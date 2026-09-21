#!/usr/bin/env bats

load 'helpers'

# add_message args: age_seconds input cache_creation cache_read output [id] [file]
# A message's work is its context growth over the previous message in the
# same file (context = input + cache_creation + cache_read) plus its output.
# The first message in a file has nothing to diff against, so only its output
# counts. With a 60s session the window equals the session, so tpm == tokens.

# ─── TPM calculation ───

@test "tpm: not shown when duration is zero" {
  add_message 10 0 0 0 500
  run run_tpm 0
  [[ "$(plain)" != *"tpm"* ]]
}

@test "tpm: not shown without a transcript" {
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000
  [[ "$(plain)" != *"tpm"* ]]
}

@test "tpm: not shown when the transcript has no messages in the window" {
  add_message 400 5000 0 0 3000
  run run_tpm 600000
  [[ "$(plain)" != *"tpm"* ]]
}

@test "tpm: shows raw number below 1k" {
  add_message 10 0 0 0 500
  run run_tpm
  [[ "$(plain)" == *"ϟ 500 tpm"* ]]
}

@test "tpm: shows N.Nk for 1000-9999" {
  add_message 10 0 0 0 3000
  run run_tpm
  [[ "$(plain)" == *"3.0k tpm"* ]]
}

@test "tpm: shows N.Nk for 10k-99.9k and integer for 100k+" {
  add_message 10 0 0 0 20000
  run run_tpm
  [[ "$(plain)" == *"20.0k tpm"* ]]
  add_message 5 0 0 0 80000
  run run_tpm
  [[ "$(plain)" == *"100k tpm"* ]]
}

@test "tpm: shows N.NM for 1M-99.9M" {
  add_message 10 0 0 0 1500000
  run run_tpm
  [[ "$(plain)" == *"1.5M tpm"* ]]
}

@test "tpm: shows integer M for 100M+" {
  add_message 10 0 0 0 100000000
  run run_tpm
  [[ "$(plain)" == *"100M tpm"* ]]
}

# ─── What counts as work ───

@test "tpm: counts context growth plus output, not context size" {
  # First message: 50k context, only its 100 output counts
  add_message 20 2 50000 0 100
  # Second: context 53034 (+3034 over the first) plus 200 output
  add_message 10 32 3000 50002 200
  run run_tpm
  [[ "$(plain)" == *"3.3k tpm"* ]]
}

@test "tpm: rewriting a cold cache is not new work" {
  # Warm call: 100k read. Then the cache expires and the whole context is
  # rewritten as cache creation; only the 500 new tokens and output count.
  add_message 20 2 0 100000 100
  add_message 10 2 100500 0 100
  run run_tpm
  [[ "$(plain)" == *"ϟ 700 tpm"* ]]
}

@test "tpm: a shrinking context (compaction) counts as zero growth" {
  add_message 20 0 0 200000 100
  add_message 10 0 50000 0 100
  run run_tpm
  [[ "$(plain)" == *"ϟ 200 tpm"* ]]
}

@test "tpm: growth is measured against the last message even outside the window" {
  # The old message's own tokens don't count, but it is the baseline
  add_message 400 0 0 10000 999999
  add_message 10 0 500 10000 100
  run run_tpm 600000
  # 600 tokens over a full 5-minute window = 120 tpm
  [[ "$(plain)" == *"ϟ 120 tpm"* ]]
}

@test "tpm: streamed blocks with the same message id count once, at their final output" {
  add_message 20 0 0 1000 0
  # Streaming repeats the id per content block with a growing output count
  add_message 10 0 500 1000 2 msg_stream
  add_message 10 0 500 1000 204 msg_stream
  run run_tpm
  [[ "$(plain)" == *"ϟ 704 tpm"* ]]
}

@test "tpm: sums every message inside the window" {
  add_message 50 0 0 1000 100
  add_message 30 0 100 1000 100
  add_message 10 0 100 1100 100
  run run_tpm
  [[ "$(plain)" == *"ϟ 500 tpm"* ]]
}

@test "tpm: skips lines that are not assistant messages or not valid JSON" {
  printf '{"type":"user","timestamp":"2099-01-01T00:00:00Z","message":{"id":"u1","usage":{"output_tokens":9999}}}\n' >> "$(transcript_path)"
  printf 'not json at all\n' >> "$(transcript_path)"
  printf '{"type":"assistant","message":{"id":"no_ts","usage":{"output_tokens":9999}}}\n' >> "$(transcript_path)"
  add_message 10 0 0 0 500
  run run_tpm
  [[ "$(plain)" == *"ϟ 500 tpm"* ]]
}

@test "tpm: tolerates the partial line left by reading only the file tail" {
  # A first line larger than the tail read; the cut lands mid-line
  head -c 17000000 /dev/zero | tr '\0' 'x' > "$(transcript_path)"
  printf '\n' >> "$(transcript_path)"
  add_message 10 0 0 0 500
  run run_tpm
  [[ "$(plain)" == *"ϟ 500 tpm"* ]]
}

@test "tpm: counts messages behind several MB of tool output inside the window" {
  add_message 20 0 0 0 500
  # 6MB of user-side tool results after it, as a busy five minutes can write
  printf '{"type":"user","message":{"content":"%s"}}\n' "$(head -c 6000000 /dev/zero | tr '\0' 'x')" >> "$(transcript_path)"
  add_message 10 0 0 0 500
  run run_tpm
  [[ "$(plain)" == *"ϟ 1.0k tpm"* ]]
}

# ─── Session lifetime ───

@test "tpm: window is capped at the session lifetime" {
  # 3000 tokens in a 2-minute-old session = 1500 tpm, not 3000/5min
  add_message 10 0 0 0 3000
  run run_tpm 120000
  [[ "$(plain)" == *"1.5k tpm"* ]]
}

@test "tpm: window never shrinks below one minute" {
  # A first response 10s into a session is spread over a minute, not 10s
  add_message 5 0 0 0 3000
  run run_tpm 10000
  [[ "$(plain)" == *"3.0k tpm"* ]]
}

@test "tpm: resumed session ignores messages from before the process started" {
  # 60k tokens two minutes ago belong to the previous process (session is 90s old)
  add_message 120 0 0 60000 20000
  run run_tpm 90000
  [[ "$(plain)" != *"tpm"* ]]
  # First post-resume response: growth over the pre-resume message plus output
  add_message 10 0 3000 60000 500
  run run_tpm 90000
  # 3500 tokens over 90s = 2333 tpm
  [[ "$(plain)" == *"2.3k tpm"* ]]
}

@test "tpm: floor widens the divisor but not the lookback after a resume" {
  # Session is 20s old; a message from 40s ago belongs to the previous process
  add_message 40 0 0 0 60000
  run run_tpm 20000
  [[ "$(plain)" != *"tpm"* ]]
  # A message from 10s ago counts, spread over the one-minute floor
  add_message 10 0 0 0 3000
  run run_tpm 20000
  [[ "$(plain)" == *"3.0k tpm"* ]]
}

@test "tpm: idle session shows nothing rather than a session average" {
  add_message 400 0 0 200000 5000
  run run_tpm 499000000
  [[ "$(plain)" != *"tpm"* ]]
}

# ─── TPM bolt colors ───

@test "bolt: no color below 1000 tpm" {
  add_message 10 0 0 0 500
  run run_tpm
  # Should NOT have any color code immediately before the bolt
  [[ "$output" != *$'\033[93m'"ϟ"* ]]
  [[ "$output" != *$'\033[38;5;209m'"ϟ"* ]]
  [[ "$output" != *$'\033[91m'"ϟ"* ]]
  [[ "$output" != *$'\033[38;5;57m'"ϟ"* ]]
}

@test "bolt: yellow at 1000 tpm" {
  add_message 10 0 0 0 1000
  run run_tpm
  [[ "$output" == *$'\033[93m'"ϟ"* ]]
}

@test "bolt: orange at 5000 tpm" {
  add_message 10 0 0 0 5000
  run run_tpm
  [[ "$output" == *$'\033[38;5;209m'"ϟ"* ]]
}

@test "bolt: red at 10000 tpm" {
  add_message 10 0 0 0 10000
  run run_tpm
  [[ "$output" == *$'\033[91m'"ϟ"* ]]
}

@test "bolt: violet at 20000 tpm" {
  add_message 10 0 0 0 20000
  run run_tpm
  [[ "$output" == *$'\033[38;5;57m'"ϟ"* ]]
}

@test "bolt: hot pink at 1M tpm" {
  add_message 10 0 0 0 1500000
  run run_tpm
  [[ "$output" == *$'\033[38;5;198m'"ϟ"* ]]
}
