# claude-code-statusline

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![POSIX shell](https://img.shields.io/badge/Shell-POSIX-green.svg)](statusline.sh)
[![macOS / Linux](https://img.shields.io/badge/macOS_|_Linux-compatible-lightgrey.svg)]()

A minimal Claude Code statusline showing branch, diff, model, context, throughput, rate limit usage, and prompt cache state.

<img width="685" height="100" alt="Screenshot" src="https://github.com/user-attachments/assets/5ce0a134-6b07-4754-8b9c-dca3e8fc6574" />


## Design principles

- **Essential** – relevant indicators shown without extra labels, dividers, or empty states
- **Quiet** – supporting the main action, not competing with it
- **Terminal-first** – plain text symbols, no emojis


## What it shows

|   |   |   |
|---|---|---|
| **Branch** | Current git branch |  |
| **Diff** | Uncommitted additions and deletions |  |
| **Model** | Active Claude model |  |
| **Context** | Usage bar and percentage, scaled so 100% matches the actual autocompact point | Grey <35%, yellow-green 35%, yellow 50%, orange 75%, red 90% |
| **Throughput** | Tokens per minute | Grey <1k, yellow 1k, orange 5k, red 10k, violet 20k |
| **Rate limits** | 5-hour and 7-day usage with countdown. Shown on first use, when on pace to hit the limit, and at or above 75%. Hidden means comfortable pace | Grey <50%, yellow 50%, orange 75%, red 90% |
| **Prompt cache** | Countdown to the cached prefix going cold, then `cache cold` until the next response warms it. Shown only in the last 10 minutes or once cold. Hidden means warm with time to spare | Yellow 10m, orange 5m, red 2m, blue when cold |

Indicators without data are hidden rather than shown empty.


## Install

1. Download the script:

```bash
curl -o ~/.claude/statusline.sh https://raw.githubusercontent.com/levibe/claude-code-statusline/main/statusline.sh && chmod +x ~/.claude/statusline.sh
```

Or clone and symlink: `git clone https://github.com/levibe/claude-code-statusline && ln -s claude-code-statusline/statusline.sh ~/.claude/statusline.sh`

2. Add to your `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh",
    "refreshInterval": 30
  }
}
```

`refreshInterval` re-runs the script every 30 seconds while the session is idle so the prompt cache countdown keeps ticking. Without it the segment still updates on every event and still flips to cold at the right moment, it just stays fixed between events.

3. Restart Claude Code.


## Configuration

Hide indicators you don't want by setting `CLAUDE_STATUSLINE_HIDE` to a comma-separated list of names. Prefix the command in `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "CLAUDE_STATUSLINE_HIDE=tpm ~/.claude/statusline.sh"
  }
}
```

Or add it to the `env` block in the same file, which the statusline inherits.

| Name | Hides |
|---|---|
| `branch` | Branch name and worktree marker |
| `diff` | Uncommitted additions and deletions |
| `model` | Model name and 1M marker |
| `context` | Context usage bar and percentage |
| `tpm` | Throughput (tokens per minute) |
| `limits` | 5-hour and 7-day rate limits |

Unknown names are ignored. A hidden indicator also skips the work behind it, so hiding `diff` avoids the git diff scan and hiding `tpm` avoids the sliding-window bookkeeping.


## Requirements

- [`jq`](https://jqlang.github.io/jq/) – JSON parsing
- `git` – branch and diff information

`brew install jq git` or `apt install jq git`


## Notes

- Tracks text diffs, untracked files, and binary file changes (binary files count as +1 added or -1 removed)
- Caps line counting at 10k to avoid slowdowns on large diffs
- TPM uses a 5-minute sliding window and includes subagent token usage
- Shows short SHA on detached HEAD; falls back to symbolic ref in empty repos
- Marks a linked git worktree with a distinct icon and color, separating it from the main checkout
- Computes prompt cache warmth from `expires_at` against the clock rather than trusting the `warm` flag, which can lag when Claude Code re-runs the script at the moment of expiry (requires Claude Code 2.1.251 or later for `prompt_cache`)
- Uses `--no-optional-locks` on all git calls to prevent lock contention
- Fixes model name bleeding across sessions ([CC bug](https://github.com/anthropics/claude-code/issues/19570))
- Validates model names to filter garbled input from Claude Code


## Changelog

[CHANGELOG.md](CHANGELOG.md)


## Development

Run the test suite:

```bash
brew install bats-core  # https://bats-core.readthedocs.io/en/stable/installation.html
bats test/
```


## Contributing

[Issues and feature requests](https://github.com/levibe/claude-code-statusline/issues)


## License

[MIT](LICENSE)
