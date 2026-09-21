#!/usr/bin/env bats

load 'helpers'

# ─── Subagent tokens ───

subagent_file() {
  printf '%s/%s/subagents/agent-%s.jsonl' "$BATS_TEST_TMPDIR" "$TEST_SID" "$1"
}

@test "subagent: work is added to the main transcript's" {
  add_message 10 0 0 0 500
  add_message 10 0 0 0 100 msg_a1 "$(subagent_file 1)"
  add_message 10 0 0 0 100 msg_b1 "$(subagent_file 2)"
  run run_tpm
  [[ "$(plain)" == *"ϟ 700 tpm"* ]]
}

@test "subagent: context growth is measured within each file, not across files" {
  # Main: 1000 -> 1500 context (+500) plus 100 output
  add_message 20 0 0 1000 0
  add_message 10 0 500 1000 100
  # Agent: 100k context (first in file, output only) then +200 plus 50
  add_message 15 0 0 100000 50 msg_a1 "$(subagent_file 1)"
  add_message 10 0 200 100000 50 msg_a2 "$(subagent_file 1)"
  run run_tpm
  [[ "$(plain)" == *"ϟ 900 tpm"* ]]
}

@test "subagent: messages outside the window are ignored" {
  add_message 10 0 0 0 500
  add_message 400 0 0 100000 50000 msg_old "$(subagent_file 1)"
  run run_tpm 600000
  [[ "$(plain)" == *"ϟ 100 tpm"* ]]
}

@test "subagent: transcripts count even when the main transcript is quiet" {
  add_message 400 0 0 0 500
  add_message 10 0 0 0 150 msg_a1 "$(subagent_file 1)"
  run run_tpm 600000
  [[ "$(plain)" == *"ϟ 30 tpm"* ]]
}
