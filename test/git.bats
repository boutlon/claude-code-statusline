#!/usr/bin/env bats

load 'helpers'

# ─── Git integration ───

@test "git: shows branch name" {
  make_git_repo test-branch
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_GIT_REPO"
  [[ "$(plain)" == *"⌥ test-branch"* ]]
}

@test "git: shows diff stats for tracked changes" {
  make_git_repo
  printf 'line1\nline2\nline3\n' > "$TEST_GIT_REPO/file.txt"
  git -C "$TEST_GIT_REPO" add file.txt
  git -C "$TEST_GIT_REPO" -c user.name=test -c user.email=test@test commit -m "add file" >/dev/null 2>&1
  printf 'changed\nline2\nline3\nnew\n' > "$TEST_GIT_REPO/file.txt"
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_GIT_REPO"
  # 1 insertion (+new line, +changed), 1 deletion (-line1)
  [[ "$(plain)" == *"+2"* ]]
  [[ "$(plain)" == *"-1"* ]]
}

@test "git: counts untracked file lines" {
  make_git_repo
  printf 'a\nb\nc\n' > "$TEST_GIT_REPO/untracked.txt"
  # Must run from repo dir: git ls-files outputs relative paths that grep reads from cwd
  cd "$TEST_GIT_REPO"
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_GIT_REPO"
  [[ "$(plain)" == *"+3"* ]]
}

@test "git: detached HEAD shows short SHA" {
  make_git_repo
  local sha
  sha=$(git -C "$TEST_GIT_REPO" rev-parse --short HEAD)
  git -C "$TEST_GIT_REPO" checkout --detach HEAD >/dev/null 2>&1
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_GIT_REPO"
  [[ "$(plain)" == *"⌥ ${sha}"* ]]
}

@test "git: empty repo shows branch name" {
  TEST_GIT_REPO=$(mktemp -d)
  git -C "$TEST_GIT_REPO" init -b main >/dev/null 2>&1
  # No commits -- empty repo
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_GIT_REPO"
  [[ "$(plain)" == *"⌥ main"* ]]
}

@test "git: no branch indicator outside git repo" {
  TEST_GIT_REPO=$(mktemp -d)
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_GIT_REPO"
  [[ "$(plain)" != *"⌥"* ]]
  [[ "$(plain)" == *"✦ Opus 4.6"* ]]
}

@test "git: main checkout uses the main-checkout glyph" {
  make_git_repo
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_GIT_REPO"
  [[ "$(plain)" == *"⌥ main"* ]]
  [[ "$(plain)" != *"⧉"* ]]
}

@test "git: linked worktree uses the worktree glyph" {
  make_git_repo
  make_worktree feature -b feature
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_WORKTREE"
  [[ "$(plain)" == *"⧉ feature"* ]]
  [[ "$(plain)" != *"⌥"* ]]
  # Worktree folder matches the branch, so the name is not shown twice
  [[ "$(plain)" != *"feature feature"* ]]
}

@test "git: shows the worktree name alongside the branch when they differ" {
  make_git_repo
  make_worktree wt-alpha -b feature
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_WORKTREE"
  [[ "$(plain)" == *"⧉ wt-alpha feature"* ]]
}

@test "git: shows the worktree name from a subdir of the worktree" {
  make_git_repo
  make_worktree wt-alpha -b feature
  mkdir -p "$TEST_WORKTREE/src"
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_WORKTREE/src"
  [[ "$(plain)" == *"⧉ wt-alpha feature"* ]]
}

@test "git: detached HEAD in a worktree still shows the worktree name" {
  make_git_repo
  make_worktree wt-alpha --detach
  local sha
  sha=$(git -C "$TEST_WORKTREE" rev-parse --short HEAD)
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_WORKTREE"
  [[ "$(plain)" == *"⧉ wt-alpha ${sha}"* ]]
}

@test "git: slashed branch is shown alongside the worktree name, not suppressed" {
  make_git_repo
  make_worktree foo -b feature/foo
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_WORKTREE"
  # Folder "foo" != branch "feature/foo": full branch string is compared, so both render
  [[ "$(plain)" == *"⧉ foo feature/foo"* ]]
}

@test "git: worktree name reflects the folder after git worktree move" {
  make_git_repo
  make_worktree wt-alpha -b feature
  # Internal git dir stays .git/worktrees/wt-alpha after the move; only
  # --show-toplevel tracks the new folder, which is why the script uses it
  git -C "$TEST_GIT_REPO" worktree move "$TEST_WORKTREE" "$TEST_GIT_REPO/.worktrees/wt-beta" >/dev/null 2>&1
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_GIT_REPO/.worktrees/wt-beta"
  [[ "$(plain)" == *"⧉ wt-beta feature"* ]]
  [[ "$(plain)" != *"wt-alpha"* ]]
}

@test "git: shows diff stats alongside the worktree name" {
  make_git_repo
  make_worktree wt-alpha -b feature
  printf 'a\nb\n' > "$TEST_WORKTREE/untracked.txt"
  # Must run from repo dir: git ls-files outputs relative paths that grep reads from cwd
  cd "$TEST_WORKTREE"
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_WORKTREE"
  [[ "$(plain)" == *"⧉ wt-alpha feature  +2"* ]]
}

@test "git: subdir of main checkout is not mistaken for a worktree" {
  make_git_repo
  mkdir -p "$TEST_GIT_REPO/subdir"
  run run_sl "Opus 4.6" 25 "$TEST_SID" 60000 5000 3000 "$TEST_GIT_REPO/subdir"
  [[ "$(plain)" == *"⌥ main"* ]]
  [[ "$(plain)" != *"⧉"* ]]
}
