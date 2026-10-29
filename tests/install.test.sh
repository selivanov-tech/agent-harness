#!/usr/bin/env bash
# Tests for bin/install against a throwaway repository layout and HOME.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

# fake_repo: a repo copy with two skills and a dummy wt; sets FAKE and a fresh HOME.
fake_repo() {
  FAKE="$T_DIR/repo"
  mkdir -p "$FAKE/bin" "$FAKE/skills/alpha" "$FAKE/skills/beta" "$FAKE/skills/not-a-skill"
  cp "$REPO_ROOT/bin/install" "$FAKE/bin/install"
  printf '#!/bin/sh\necho wt-dummy\n' >"$FAKE/bin/wt"
  chmod +x "$FAKE/bin/wt"
  printf -- '---\nname: alpha\n---\n' >"$FAKE/skills/alpha/SKILL.md"
  printf -- '---\nname: beta\n---\n' >"$FAKE/skills/beta/SKILL.md"
  export HOME="$T_DIR/home"
  mkdir -p "$HOME/.codex"
}

install_cmd() {
  "$TEST_BASH" "$FAKE/bin/install" "$@"
}

test_fresh_install_links_everything() {
  fake_repo
  run install_cmd
  assert_code 0
  assert_eq "$FAKE/skills/alpha" "$(readlink "$HOME/.agents/skills/alpha")"
  assert_eq "../../.agents/skills/alpha" "$(readlink "$HOME/.claude/skills/alpha")"
  assert_eq "../../.agents/skills/beta" "$(readlink "$HOME/.codex/skills/beta")"
  assert_eq "$FAKE/bin/wt" "$(readlink "$HOME/.local/bin/wt")"
  assert_exists "$HOME/.claude/skills/alpha/SKILL.md"
  assert_missing "$HOME/.agents/skills/not-a-skill"
  assert_contains "$OUT" "7 change(s), 0 conflict(s)"
}

test_second_run_changes_nothing() {
  fake_repo
  install_cmd >/dev/null
  run install_cmd
  assert_code 0
  assert_contains "$OUT" "0 change(s), 0 conflict(s)"
  assert_not_contains "$OUT" "link "
}

test_wt_is_on_path_after_install() {
  fake_repo
  install_cmd >/dev/null
  unset -f wt
  PATH="$HOME/.local/bin:$PATH"
  assert_eq "$HOME/.local/bin/wt" "$(command -v wt)"
  assert_eq "wt-dummy" "$(wt)"
}

test_codex_is_skipped_when_missing() {
  fake_repo
  rm -rf "$HOME/.codex"
  run install_cmd
  assert_code 0
  assert_missing "$HOME/.codex"
  assert_contains "$OUT" "Codex not installed"
  assert_exists "$HOME/.claude/skills/beta/SKILL.md"
}

test_existing_directory_is_left_alone() {
  fake_repo
  mkdir -p "$HOME/.agents/skills/alpha"
  printf 'mine\n' >"$HOME/.agents/skills/alpha/SKILL.md"
  run install_cmd
  assert_code 1
  assert_contains "$OUT" "not a symlink; left untouched"
  assert_eq "mine" "$(cat "$HOME/.agents/skills/alpha/SKILL.md")"
  assert_eq "$FAKE/skills/beta" "$(readlink "$HOME/.agents/skills/beta")"
}

test_foreign_symlink_is_left_alone() {
  fake_repo
  mkdir -p "$HOME/.claude/skills"
  ln -s /somewhere/else "$HOME/.claude/skills/beta"
  run install_cmd
  assert_code 1
  assert_contains "$OUT" "conflict"
  assert_eq "/somewhere/else" "$(readlink "$HOME/.claude/skills/beta")"
}

test_dry_run_changes_nothing() {
  fake_repo
  run install_cmd --dry-run
  assert_code 0
  assert_contains "$OUT" "dry run: 7 change(s) would be made"
  assert_missing "$HOME/.agents"
  assert_missing "$HOME/.local/bin/wt"
}

test_uninstall_removes_only_own_links() {
  fake_repo
  install_cmd >/dev/null
  ln -s /somewhere/else "$HOME/.claude/skills/other"
  run install_cmd --uninstall
  assert_code 0
  assert_missing "$HOME/.agents/skills/alpha"
  assert_missing "$HOME/.claude/skills/alpha"
  assert_missing "$HOME/.codex/skills/beta"
  assert_missing "$HOME/.local/bin/wt"
  assert_eq "/somewhere/else" "$(readlink "$HOME/.claude/skills/other")"
}

test_rejects_unknown_option() {
  fake_repo
  run install_cmd --bogus
  assert_code 2
}

test_real_repository_on_a_clean_home() {
  export HOME="$T_DIR/home"
  mkdir -p "$HOME/.codex"
  run "$TEST_BASH" "$REPO_ROOT/bin/install"
  assert_code 0
  assert_exists "$HOME/.claude/skills/session-orchestrator/SKILL.md"
  assert_exists "$HOME/.claude/skills/worktree-sessions/SKILL.md"
  assert_exists "$HOME/.codex/skills/session-orchestrator/agents/openai.yaml"
  assert_eq "$REPO_ROOT/skills/worktree-sessions" "$(readlink "$HOME/.agents/skills/worktree-sessions")"
  unset -f wt
  PATH="$HOME/.local/bin:$PATH"
  assert_contains "$(wt version)" "wt 0."
  run "$TEST_BASH" "$REPO_ROOT/bin/install"
  assert_contains "$OUT" "0 change(s), 0 conflict(s)"
}

t "fresh install links skills and wt" test_fresh_install_links_everything
t "second run changes nothing" test_second_run_changes_nothing
t "wt resolves from ~/.local/bin" test_wt_is_on_path_after_install
t "codex links are skipped without ~/.codex" test_codex_is_skipped_when_missing
t "an existing directory is left alone" test_existing_directory_is_left_alone
t "a foreign symlink is left alone" test_foreign_symlink_is_left_alone
t "dry run changes nothing" test_dry_run_changes_nothing
t "uninstall removes only own links" test_uninstall_removes_only_own_links
t "unknown option is rejected" test_rejects_unknown_option
t "the real repository installs on a clean HOME" test_real_repository_on_a_clean_home
t_done
