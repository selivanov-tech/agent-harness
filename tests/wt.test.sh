#!/usr/bin/env bash
# Tests for bin/wt on throwaway repositories. gh and docker are replaced by stubs
# that print canned answers; nothing here talks to the network or a real daemon.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

# --- fixtures -------------------------------------------------------------------

# repo_with_conf <conf lines...>: make_repo plus a committed .wt.conf.
repo_with_conf() {
  make_repo
  printf '%s\n' "$@" >"$MAIN/.wt.conf"
  git -C "$MAIN" add .wt.conf
  git -C "$MAIN" commit -q -m "add .wt.conf"
  git -C "$MAIN" push -q origin main
}

# heavy_main: ignored vendor/ and .env in the main checkout, as a real project has.
heavy_main() {
  printf 'vendor/\n.env\nhook.out\n' >"$MAIN/.gitignore"
  git -C "$MAIN" add .gitignore
  git -C "$MAIN" commit -q -m "ignore local files"
  mkdir -p "$MAIN/vendor/lib"
  printf 'original\n' >"$MAIN/vendor/lib/a.txt"
  printf 'SECRET=1\n' >"$MAIN/.env"
  chmod 600 "$MAIN/.env"
}

gh_prs() { # lines "<branch> <number> <STATE> <head sha>"
  printf '%s\n' "$@" >"$T_DIR/gh-prs"
  stub gh "if [ \"\$1 \$2\" = 'pr list' ]; then cat '$T_DIR/gh-prs'; exit 0; fi
echo \"unexpected gh call: \$*\" >&2
exit 1"
  unset WT_NO_GH
}

docker_state() { # running, all, volumes (newline-separated, may be empty)
  printf '%s' "$1" >"$T_DIR/docker-running"
  printf '%s' "$2" >"$T_DIR/docker-all"
  printf '%s' "$3" >"$T_DIR/docker-volumes"
  stub docker "case \"\$*\" in
  'compose ls -q') cat '$T_DIR/docker-running' ;;
  'compose ls -a -q') cat '$T_DIR/docker-all' ;;
  'volume ls -q') cat '$T_DIR/docker-volumes' ;;
  *) echo \"unexpected docker call: \$*\" >&2; exit 1 ;;
esac"
  unset WT_NO_DOCKER
}

wt_dir() {
  printf '%s/.wt-repo-%s' "$T_DIR" "$1"
}

tip() {
  git -C "$MAIN" rev-parse "refs/heads/$1"
}

push_from_other_clone() {
  git clone -q "$ORIGIN" "$T_DIR/other"
  commit_file "$T_DIR/other" upstream.txt "from upstream"
  git -C "$T_DIR/other" push -q origin main
}

json_ok() {
  command -v python3 >/dev/null 2>&1 || fail "python3 is needed to validate JSON output"
  printf '%s' "$1" | python3 -c 'import json, sys; json.load(sys.stdin)' || fail "invalid JSON: $1"
}

# --- core --------------------------------------------------------------------------

test_help_lists_every_command() {
  run wt help
  assert_code 0
  for cmd in new ls path adopt rm doctor help version; do
    assert_contains "$OUT" "  wt $cmd"
  done
}

test_version() {
  run wt version
  assert_code 0
  assert_contains "$OUT" "wt 0."
}

test_outside_a_repository_exits_2() {
  run wt ls
  assert_code 2
  assert_contains "$ERR" "not inside a git working tree"
}

test_unknown_command_exits_2() {
  make_repo
  cd "$MAIN"
  run wt frobnicate
  assert_code 2
}

test_repository_without_remote() {
  git init -q "$T_DIR/repo"
  commit_file "$T_DIR/repo" a.txt a
  cd "$T_DIR/repo"
  run wt new demo
  assert_code 0
  assert_eq "$(wt_dir demo)" "$OUT"
  run wt doctor
  assert_code 0
  run wt rm demo
  assert_code 0
  assert_eq 1 "$(git worktree list | wc -l | tr -d ' ')"
}

test_master_default_branch() {
  git init -q -b master "$T_DIR/repo"
  commit_file "$T_DIR/repo" a.txt a
  cd "$T_DIR/repo"
  run wt new master
  assert_code 2
  run wt new demo
  assert_code 0
  assert_eq "$(git rev-parse refs/heads/master)" "$(git rev-parse refs/heads/demo)"
}

test_ls_without_linked_worktrees() {
  make_repo
  cd "$MAIN"
  run wt ls
  assert_code 0
  assert_contains "$ERR" "no linked worktrees"
  run wt ls --json
  assert_code 0
  assert_eq "[]" "$OUT"
}

# --- new ---------------------------------------------------------------------------

test_new_creates_sibling_worktree() {
  make_repo
  cd "$MAIN"
  run wt new demo
  assert_code 0
  assert_eq "$(wt_dir demo)" "$OUT"
  assert_eq demo "$(git -C "$OUT" symbolic-ref --short HEAD)"
  assert_eq "$(tip main)" "$(tip demo)"
  assert_eq true "$(git -C "$MAIN" config --bool extensions.worktreeConfig)"
  assert_eq demo "$(git -C "$OUT" config --worktree --get wt.slug)"
  assert_eq "" "$(git -C "$MAIN" config --get branch.demo.merge || true)" "no upstream tracking"
}

test_new_twice_reuses() {
  make_repo
  cd "$MAIN"
  wt new demo >/dev/null 2>&1
  run wt new demo
  assert_code 0
  assert_eq "$(wt_dir demo)" "$OUT"
  assert_contains "$ERR" "reusing"
  assert_eq 2 "$(git worktree list | wc -l | tr -d ' ')"
}

test_new_rejects_bad_slugs() {
  make_repo
  cd "$MAIN"
  for slug in main master Demo demo- a_b "a b" 123456789012345678901234567890123456789012345; do
    run wt new "$slug"
    assert_code 2 "slug [$slug]"
  done
  run wt new -x
  assert_code 2
  assert_eq 1 "$(git worktree list | wc -l | tr -d ' ')"
}

test_new_refuses_remote_branch_name() {
  make_repo
  cd "$MAIN"
  run wt new demo --branch origin/main
  assert_code 2
  assert_contains "$ERR" "shadows the remote-tracking branch"
  assert_contains "$ERR" "--sync"
  run wt new demo --branch refs/heads/x
  assert_code 2
  run wt new demo --branch origin
  assert_code 2
  run wt new demo --branch Origin/main
  assert_code 2 "case-insensitive filesystems make Origin/main shadow origin/main"
  run wt new demo --branch Refs/heads/x
  assert_code 2
  assert_eq "" "$(git for-each-ref refs/heads/origin refs/heads/Origin refs/heads/refs refs/heads/Refs)"
}

test_new_refuses_remote_start_point() {
  make_repo
  cd "$MAIN"
  run wt new demo --from origin/main
  assert_code 2
  assert_contains "$ERR" "remote-tracking ref"
  assert_contains "$ERR" "--sync"
  for ref in refs/remotes/origin/main remotes/origin/main origin Origin/main 'main@{u}' 'main@{upstream}'; do
    run wt new demo --from "$ref"
    assert_code 2 "--from $ref"
  done
  run wt new demo --from no-such-ref
  assert_code 2
  assert_missing "$(wt_dir demo)"
}

test_new_refuses_unregistered_directory() {
  make_repo
  cd "$MAIN"
  mkdir "$(wt_dir demo)"
  run wt new demo
  assert_code 2
  assert_contains "$ERR" "already exists"
}

test_new_sync_fast_forwards_default_branch() {
  make_repo
  push_from_other_clone
  cd "$MAIN"
  local before
  before=$(tip main)
  run wt new feat --sync
  assert_code 0
  assert_eq "$(git -C "$MAIN" rev-parse refs/remotes/origin/main)" "$(tip main)"
  [ "$(tip main)" != "$before" ] || fail "main did not move"
  assert_eq "$(tip main)" "$(tip feat)"
  assert_exists "$MAIN/upstream.txt"
}

test_new_sync_refuses_diverged_default_branch() {
  make_repo
  push_from_other_clone
  commit_file "$MAIN" local.txt "local only"
  cd "$MAIN"
  local before
  before=$(tip main)
  run wt new feat --sync
  assert_code 1
  assert_contains "$ERR" "cannot fast-forward"
  assert_eq "$before" "$(tip main)"
  assert_missing "$(wt_dir feat)"
}

test_new_sync_refuses_when_main_checkout_is_elsewhere() {
  make_repo
  git -C "$MAIN" switch -q -c side
  cd "$MAIN"
  run wt new feat --sync
  assert_code 3
}

test_new_from_tag_and_custom_branch() {
  make_repo
  git -C "$MAIN" tag v1
  commit_file "$MAIN" later.txt later
  cd "$MAIN"
  run wt new old --from v1
  assert_code 0
  assert_eq "$(git rev-parse v1)" "$(tip old)"
  run wt new x --branch feat/x
  assert_code 0
  assert_eq "$(wt_dir x)" "$OUT"
  assert_eq feat/x "$(git -C "$OUT" symbolic-ref --short HEAD)"
  run wt path x
  assert_eq "$(wt_dir x)" "$OUT"
}

test_new_existing_branch() {
  make_repo
  git -C "$MAIN" branch existing
  cd "$MAIN"
  run wt new existing --from main
  assert_code 2
  run wt new existing
  assert_code 0
  assert_contains "$ERR" "existing branch"
}

test_new_refuses_branch_checked_out_elsewhere() {
  make_repo
  git -C "$MAIN" worktree add -q "$T_DIR/elsewhere" -b taken
  cd "$MAIN"
  run wt new taken
  assert_code 2
  assert_contains "$ERR" "already checked out"
}

test_new_parent_overrides() {
  make_repo
  cd "$MAIN"
  WT_HOME="$T_DIR/wts" run wt new a
  assert_code 0
  assert_eq "$T_DIR/wts/.wt-repo-a" "$OUT"
  printf 'worktree_dir=../trees\n' >"$MAIN/.wt.conf"
  run wt new b
  assert_code 0
  assert_eq "$T_DIR/trees/.wt-repo-b" "$OUT"
}

test_new_from_inside_a_linked_worktree() {
  make_repo
  cd "$MAIN"
  wt new a >/dev/null 2>&1
  cd "$(wt_dir a)"
  run wt new b
  assert_code 0
  assert_eq "$(wt_dir b)" "$OUT"
}

# --- materialization -----------------------------------------------------------------

test_clone_and_copy() {
  repo_with_conf "clone=vendor node_modules" "copy=.env missing.txt"
  heavy_main
  cd "$MAIN"
  run wt new m
  assert_code 0
  local dir
  dir=$(wt_dir m)
  assert_eq original "$(cat "$dir/vendor/lib/a.txt")"
  printf 'changed\n' >"$dir/vendor/lib/a.txt"
  assert_eq original "$(cat "$MAIN/vendor/lib/a.txt")" "clone must be independent"
  assert_eq "SECRET=1" "$(cat "$dir/.env")"
  assert_eq "$dir/.env" "$(find "$dir/.env" -perm 600)" ".env keeps mode 600"
  assert_missing "$dir/node_modules"
  assert_contains "$ERR" "clone node_modules: not in the main checkout"
  assert_contains "$ERR" "copy missing.txt: not in the main checkout"
}

test_copy_never_overwrites() {
  repo_with_conf "copy=.env"
  heavy_main
  cd "$MAIN"
  wt new m >/dev/null 2>&1
  printf 'MINE=1\n' >"$(wt_dir m)/.env"
  run wt new m
  assert_code 0
  assert_eq "MINE=1" "$(cat "$(wt_dir m)/.env")"
}

test_materialize_hook_gets_variables() {
  # shellcheck disable=SC2016
  repo_with_conf 'materialize=printf "%s|%s|%s|%s|%s\n" "$PWD" "$WT_SLUG" "$WT_DIR" "$WT_ROOT" "$WT_BRANCH" > hook.out; echo noise'
  heavy_main
  cd "$MAIN"
  run wt new h
  assert_code 0
  local dir
  dir=$(wt_dir h)
  assert_eq "$dir" "$OUT" "hook output must not reach stdout"
  assert_eq "$dir|h|$dir|$MAIN|h" "$(cat "$dir/hook.out")"
  assert_contains "$ERR" "running materialize hook in $dir: printf"
  assert_contains "$ERR" "> hook.out; echo noise"
}

test_failing_hook_exits_5_and_rerun_is_safe() {
  repo_with_conf "materialize=exit 7"
  cd "$MAIN"
  run wt new h
  assert_code 5
  assert_contains "$ERR" "exit code 7"
  assert_exists "$(wt_dir h)/README.md"
  printf 'materialize=true\n' >"$(wt_dir h)/.wt.conf"
  run wt new h
  assert_code 0
  assert_contains "$ERR" "reusing"
}

test_no_hooks_skips_materialize_hook() {
  repo_with_conf "clone=vendor" "materialize=touch hook-ran"
  heavy_main
  cd "$MAIN"
  run wt new h --no-hooks
  assert_code 0
  assert_missing "$(wt_dir h)/hook-ran"
  assert_exists "$(wt_dir h)/vendor/lib/a.txt"
}

test_clone_falls_back_to_plain_copy() {
  repo_with_conf "clone=vendor"
  heavy_main
  # shellcheck disable=SC2016
  stub cp 'cow=0
last=""
for arg in "$@"; do
  case $arg in -c|--reflink=auto) cow=1 ;; esac
  last=$arg
done
if [ "$cow" = 1 ]; then
  mkdir -p "$last"
  : >"$last/partial"
  exit 1
fi
exec /bin/cp "$@"'
  cd "$MAIN"
  run wt new c
  assert_code 0
  assert_contains "$ERR" "cloned vendor (plain copy)"
  assert_eq original "$(cat "$(wt_dir c)/vendor/lib/a.txt")"
  assert_missing "$(wt_dir c)/vendor/partial"
}

test_conf_tolerates_crlf_spaces_and_unknown_keys() {
  make_repo
  heavy_main
  printf 'clone = vendor \r\n# a comment\r\n  bogus=1\r\n' >"$MAIN/.wt.conf"
  cd "$MAIN"
  run wt new c
  assert_code 0
  assert_eq original "$(cat "$(wt_dir c)/vendor/lib/a.txt")"
  assert_contains "$ERR" "unknown key 'bogus' ignored"
}

test_conf_rejects_paths_outside_the_repository() {
  make_repo
  printf 'clone=../outside\n' >"$MAIN/.wt.conf"
  cd "$MAIN"
  run wt new c
  assert_code 2
  assert_contains "$ERR" "relative path inside the repository"
  printf 'stack_budget=four\n' >"$MAIN/.wt.conf"
  run wt ls
  assert_code 2
  printf 'no equals sign\n' >"$MAIN/.wt.conf"
  run wt ls
  assert_code 2
}

# --- ls, path, adopt -------------------------------------------------------------------

test_ls_table() {
  make_repo
  cd "$MAIN"
  wt new clean >/dev/null 2>&1
  wt new dirty >/dev/null 2>&1
  printf 'x\n' >"$(wt_dir dirty)/new-file"
  commit_file "$(wt_dir clean)" c.txt c
  run wt ls
  assert_code 0
  assert_contains "$OUT" "SLUG"
  assert_contains "$OUT" "clean"
  assert_contains "$OUT" "+1/-0"
  assert_contains "$(printf '%s\n' "$OUT" | grep '^dirty')" "yes"
}

test_ls_json_shape() {
  make_repo
  cd "$MAIN"
  wt new a >/dev/null 2>&1
  run wt ls --json
  assert_code 0
  json_ok "$OUT"
  for key in '"slug": "a"' '"branch": "a"' '"path": ' '"ahead": 0' '"behind": 0' '"dirty": false' '"missing": false' '"pr": null' '"stack": null'; do
    assert_contains "$OUT" "$key"
  done
}

test_ls_shows_unadopted_worktree() {
  make_repo
  git -C "$MAIN" worktree add -q "$T_DIR/manual" -b manual
  cd "$MAIN"
  run wt ls
  assert_code 0
  assert_contains "$OUT" "-     manual"
  run wt ls --json
  json_ok "$OUT"
  assert_contains "$OUT" '"slug": null'
}

test_ls_reads_pr_and_stack_state() {
  repo_with_conf "stack_prefix=p-"
  cd "$MAIN"
  wt new demo >/dev/null 2>&1
  gh_prs "demo 12 OPEN $(tip demo)"
  docker_state "p-demo" "p-demo" ""
  run wt ls
  assert_code 0
  assert_contains "$OUT" "#12 open"
  assert_contains "$OUT" "running"
  run wt ls --json
  json_ok "$OUT"
  assert_contains "$OUT" '"pr": {"number": 12, "state": "open"}'
  assert_contains "$OUT" '"stack": "running"'
}

test_path() {
  make_repo
  cd "$MAIN"
  wt new demo >/dev/null 2>&1
  run wt path demo
  assert_code 0
  assert_eq "$(wt_dir demo)" "$OUT"
  run wt path nope
  assert_code 2
}

test_adopt() {
  make_repo
  git -C "$MAIN" worktree add -q "$T_DIR/manual" -b manual
  cd "$MAIN"
  run wt adopt ../manual man
  assert_code 0
  assert_eq "$T_DIR/manual" "$OUT"
  assert_eq man "$(git -C "$T_DIR/manual" config --worktree --get wt.slug)"
  run wt path man
  assert_eq "$T_DIR/manual" "$OUT"
}

test_adopt_refusals() {
  make_repo
  mkdir "$T_DIR/plain"
  git -C "$MAIN" worktree add -q "$T_DIR/manual" -b manual
  cd "$MAIN"
  wt new taken >/dev/null 2>&1
  run wt adopt ../plain p
  assert_code 2
  assert_contains "$ERR" "not a registered worktree"
  run wt adopt . p
  assert_code 2
  assert_contains "$ERR" "main checkout"
  run wt adopt ../manual taken
  assert_code 2
  assert_contains "$ERR" "already used"
  run wt adopt ../manual Bad
  assert_code 2
}

# --- rm -----------------------------------------------------------------------------------

test_rm_refuses_dirty_worktree() {
  make_repo
  cd "$MAIN"
  wt new demo >/dev/null 2>&1
  printf 'changed\n' >"$(wt_dir demo)/README.md"
  run wt rm demo
  assert_code 3
  assert_contains "$ERR" "uncommitted"
  git -C "$(wt_dir demo)" checkout -q -- README.md
  printf 'new\n' >"$(wt_dir demo)/untracked.txt"
  run wt rm demo
  assert_code 3
  assert_exists "$(wt_dir demo)"
}

test_rm_refuses_unmerged_commits_without_gh() {
  make_repo
  cd "$MAIN"
  wt new demo >/dev/null 2>&1
  commit_file "$(wt_dir demo)" feature.txt work
  run wt rm demo
  assert_code 3
  assert_contains "$ERR" "1 commit(s) not in main"
  assert_contains "$ERR" "no PR data from gh"
  assert_exists "$(wt_dir demo)"
}

test_rm_removes_merged_worktree_and_branch() {
  make_repo
  cd "$MAIN"
  wt new demo >/dev/null 2>&1
  commit_file "$(wt_dir demo)" feature.txt work
  git -C "$MAIN" merge -q --ff-only demo
  run wt rm demo
  assert_code 0
  assert_missing "$(wt_dir demo)"
  assert_eq "" "$(git branch --list demo)"
  assert_contains "$ERR" "restore with: git branch demo"
  assert_eq 1 "$(git worktree list | wc -l | tr -d ' ')"
}

test_rm_keep_branch() {
  make_repo
  cd "$MAIN"
  wt new demo >/dev/null 2>&1
  run wt rm demo --keep-branch
  assert_code 0
  assert_contains "$(git branch --list demo)" demo
}

test_rm_force_removes_dirty_worktree() {
  make_repo
  cd "$MAIN"
  wt new demo >/dev/null 2>&1
  commit_file "$(wt_dir demo)" feature.txt work
  printf 'dirty\n' >"$(wt_dir demo)/untracked.txt"
  run wt rm demo --force
  assert_code 0
  assert_missing "$(wt_dir demo)"
  assert_eq "" "$(git branch --list demo)"
}

test_rm_accepts_squash_merged_pr() {
  make_repo
  cd "$MAIN"
  wt new demo >/dev/null 2>&1
  commit_file "$(wt_dir demo)" feature.txt work
  gh_prs "demo 5 MERGED $(tip demo)"
  run wt rm demo
  assert_code 0
  assert_missing "$(wt_dir demo)"
}

test_rm_refuses_commits_after_merged_pr() {
  make_repo
  cd "$MAIN"
  wt new demo >/dev/null 2>&1
  commit_file "$(wt_dir demo)" feature.txt work
  gh_prs "demo 5 MERGED $(tip demo)"
  commit_file "$(wt_dir demo)" more.txt "after merge"
  run wt rm demo
  assert_code 3
  assert_contains "$ERR" "commits after merged PR #5"
}

test_rm_refuses_open_pr() {
  make_repo
  cd "$MAIN"
  wt new demo >/dev/null 2>&1
  gh_prs "demo 7 OPEN $(tip demo)" "demo 3 MERGED 0000000000000000000000000000000000000000"
  run wt rm demo
  assert_code 3
  assert_contains "$ERR" "PR #7 is open"
}

teardown_conf() {
  # shellcheck disable=SC2016
  printf '%s\n' 'teardown=printf "%s %s %s\n" "$PWD" "$WT_DROP_DATA" "$(test -d "$WT_DIR" && echo present || echo gone)" >> "$WT_ROOT/../teardown.log"'
}

test_rm_teardown_runs_in_worktree_first() {
  repo_with_conf "$(teardown_conf)"
  cd "$MAIN"
  wt new demo >/dev/null 2>&1
  run wt rm demo --drop-data
  assert_code 0
  assert_eq "$(wt_dir demo) 1 present" "$(cat "$T_DIR/teardown.log")"
  assert_contains "$ERR" "running teardown hook in $(wt_dir demo)"
}

test_rm_teardown_from_branch_conf_before_merge() {
  make_repo
  cd "$MAIN"
  wt new demo >/dev/null 2>&1
  teardown_conf >"$(wt_dir demo)/.wt.conf"
  git -C "$(wt_dir demo)" add .wt.conf
  git -C "$(wt_dir demo)" commit -q -m "add .wt.conf"
  assert_missing "$MAIN/.wt.conf"
  run wt rm demo --force
  assert_code 0
  assert_eq "$(wt_dir demo) 0 present" "$(cat "$T_DIR/teardown.log")"
  assert_contains "$ERR" "note: the main checkout has no .wt.conf"
}

test_rm_refuses_teardown_from_main_checkout_by_default() {
  repo_with_conf "$(teardown_conf)" "stack_prefix=p-"
  cd "$MAIN"
  wt new demo >/dev/null 2>&1
  rm -rf "$(wt_dir demo)"
  run wt rm demo
  assert_code 3
  assert_contains "$ERR" "its directory is gone"
  assert_contains "$ERR" "WT_SLUG"
  assert_contains "$ERR" "--no-hooks"
  assert_contains "$ERR" "p-demo"
  assert_missing "$T_DIR/teardown.log"
  assert_eq 2 "$(git worktree list | wc -l | tr -d ' ')"
}

test_rm_force_runs_teardown_in_main_checkout_and_keeps_other_registrations() {
  # shellcheck disable=SC2016
  repo_with_conf 'teardown=printf "%s %s\n" "$PWD" "$WT_SLUG" >> "$WT_ROOT/../teardown.log"'
  cd "$MAIN"
  wt new demo >/dev/null 2>&1
  wt new other >/dev/null 2>&1
  rm -rf "$(wt_dir demo)" "$(wt_dir other)"
  run wt rm demo --force
  assert_code 0
  assert_eq "$MAIN demo" "$(cat "$T_DIR/teardown.log")"
  assert_eq "" "$(git branch --list demo)"
  assert_contains "$(git worktree list --porcelain)" "$(wt_dir other)" "wt rm must not prune other registrations"
  assert_not_contains "$(git worktree list --porcelain)" "$(wt_dir demo)"
}

test_rm_no_hooks_unregisters_a_missing_directory() {
  repo_with_conf "$(teardown_conf)"
  cd "$MAIN"
  wt new demo >/dev/null 2>&1
  rm -rf "$(wt_dir demo)"
  run wt rm demo --no-hooks
  assert_code 0
  assert_missing "$T_DIR/teardown.log"
  assert_eq 1 "$(git worktree list | wc -l | tr -d ' ')"
}

test_rm_no_hooks_skips_teardown() {
  repo_with_conf "$(teardown_conf)"
  cd "$MAIN"
  wt new demo >/dev/null 2>&1
  run wt rm demo --no-hooks
  assert_code 0
  assert_missing "$T_DIR/teardown.log"
  assert_missing "$(wt_dir demo)"
}

test_rm_failing_teardown_keeps_worktree() {
  repo_with_conf "teardown=exit 9"
  cd "$MAIN"
  wt new demo >/dev/null 2>&1
  run wt rm demo
  assert_code 5
  assert_exists "$(wt_dir demo)"
  assert_contains "$(git branch --list demo)" demo
}

test_rm_refuses_from_inside_the_worktree() {
  make_repo
  cd "$MAIN"
  wt new demo >/dev/null 2>&1
  cd "$(wt_dir demo)"
  run wt rm demo --force
  assert_code 3
  assert_contains "$ERR" "you are inside"
  assert_exists "$(wt_dir demo)"
}

test_rm_leaves_remote_branch_alone() {
  make_repo
  cd "$MAIN"
  wt new demo >/dev/null 2>&1
  commit_file "$(wt_dir demo)" feature.txt work
  git -C "$(wt_dir demo)" push -q origin demo
  git -C "$MAIN" merge -q --ff-only demo
  run wt rm demo
  assert_code 0
  assert_contains "$(git ls-remote "$ORIGIN" refs/heads/demo)" "refs/heads/demo"
}

test_rm_unknown_slug() {
  make_repo
  cd "$MAIN"
  run wt rm nope
  assert_code 2
}

# --- doctor -----------------------------------------------------------------------------

test_doctor_clean_repository() {
  make_repo
  cd "$MAIN"
  wt new demo >/dev/null 2>&1
  run wt doctor
  assert_code 0
  assert_contains "$OUT" "nothing to act on"
}

test_doctor_shadow_ref() {
  make_repo
  git -C "$MAIN" branch origin/main main
  cd "$MAIN"
  run wt doctor
  assert_code 4
  assert_contains "$OUT" "shadow-ref"
  assert_contains "$OUT" "refs/heads/origin/main"
}

test_doctor_stale_registration() {
  make_repo
  cd "$MAIN"
  wt new demo >/dev/null 2>&1
  rm -rf "$(wt_dir demo)"
  run wt doctor
  assert_code 4
  assert_contains "$OUT" "stale-registration"
}

test_doctor_unadopted() {
  make_repo
  git -C "$MAIN" worktree add -q "$T_DIR/manual" -b manual
  cd "$MAIN"
  run wt doctor
  assert_code 4
  assert_contains "$OUT" "unadopted"
  assert_contains "$OUT" "wt adopt '$T_DIR/manual' <slug>"
}

test_doctor_cleanup_candidate() {
  make_repo
  cd "$MAIN"
  wt new demo >/dev/null 2>&1
  local dir admin
  dir=$(wt_dir demo)
  printf 'old\n' >"$dir/old.txt"
  git -C "$dir" add old.txt
  GIT_AUTHOR_DATE=2026-01-01T00:00:00 GIT_COMMITTER_DATE=2026-01-01T00:00:00 git -C "$dir" commit -q -m old
  admin=$(git -C "$dir" rev-parse --absolute-git-dir)
  touch -t 202601010000 "$admin/HEAD" "$admin/index" "$admin/logs/HEAD"
  gh_prs "demo 4 MERGED $(tip demo)"
  run wt doctor
  assert_code 4
  assert_contains "$OUT" "cleanup-candidate"
  assert_contains "$OUT" "wt rm demo"
  run wt doctor --idle-days 100000
  assert_code 0
}

test_doctor_stacks() {
  repo_with_conf "stack_prefix=p-" "stack_budget=1"
  cd "$MAIN"
  wt new demo >/dev/null 2>&1
  docker_state "p-demo
p-ghost" "p-demo
p-ghost" "p-demo_data
p-ghost_data
other_data"
  run wt doctor
  assert_code 4
  assert_contains "$OUT" "stack-budget"
  assert_contains "$OUT" "2 stacks running, budget 1"
  assert_contains "$OUT" "orphan-stack"
  assert_contains "$OUT" "p-ghost"
  assert_contains "$OUT" "docker volume rm p-ghost_data"
  assert_not_contains "$OUT" "docker volume rm p-demo_data"
  assert_not_contains "$OUT" "other_data"
}

test_doctor_json() {
  repo_with_conf "stack_prefix=p-" "stack_budget=4"
  git -C "$MAIN" branch origin/main main
  cd "$MAIN"
  docker_state "" "" ""
  run wt doctor --json
  assert_code 4
  json_ok "$OUT"
  assert_contains "$OUT" '"kind": "shadow-ref"'
  assert_contains "$OUT" '"stacks_running": 0'
  assert_contains "$OUT" '"stack_budget": 4'
}

test_doctor_reports_moved_origin() {
  make_repo
  push_from_other_clone
  cd "$MAIN"
  run wt doctor
  assert_code 0
  assert_contains "$OUT" "origin-stale"
}

# --- review regressions -------------------------------------------------------------------

test_copied_slug_does_not_hijack_rm() {
  make_repo
  cd "$MAIN"
  wt new a >/dev/null 2>&1
  (cd "$(wt_dir a)" && git worktree add -q "$MAIN/.claude/worktrees/x" -b harness-x)
  assert_eq a "$(git -C "$MAIN/.claude/worktrees/x" config --worktree --get wt.slug)" "git copies config.worktree"
  run wt path a
  assert_code 0
  assert_eq "$(wt_dir a)" "$OUT"
  run wt doctor
  assert_contains "$OUT" "copied from $(wt_dir a)"
  run wt rm a
  assert_code 0
  assert_missing "$(wt_dir a)"
  assert_exists "$MAIN/.claude/worktrees/x"
  assert_contains "$(git branch --list harness-x)" harness-x
}

test_shared_slug_is_refused() {
  make_repo
  cd "$MAIN"
  wt new dup >/dev/null 2>&1
  mkdir -p "$T_DIR/elsewhere"
  git worktree add -q "$T_DIR/elsewhere/.wt-repo-dup" -b dup2
  run wt path dup
  assert_code 3
  assert_contains "$ERR" "matches 2 worktrees"
  run wt rm dup --force
  assert_code 3
  assert_exists "$(wt_dir dup)"
  assert_exists "$T_DIR/elsewhere/.wt-repo-dup"
  run wt doctor
  assert_code 4
  assert_contains "$OUT" "duplicate-slug"
}

test_rm_refuses_locked_worktree_before_hooks() {
  repo_with_conf "$(teardown_conf)"
  cd "$MAIN"
  wt new demo >/dev/null 2>&1
  git worktree lock "$(wt_dir demo)"
  run wt rm demo --force --drop-data
  assert_code 3
  assert_contains "$ERR" "locked"
  assert_missing "$T_DIR/teardown.log"
  assert_exists "$(wt_dir demo)"
}

test_rm_refuses_checked_out_submodules() {
  make_repo
  git init -q "$T_DIR/sub"
  commit_file "$T_DIR/sub" s.txt s
  cd "$MAIN"
  wt new demo >/dev/null 2>&1
  git -C "$(wt_dir demo)" -c protocol.file.allow=always submodule --quiet add "$T_DIR/sub" sub
  git -C "$(wt_dir demo)" commit -q -m "add submodule"
  git -C "$MAIN" merge -q --ff-only demo
  run wt rm demo
  assert_code 3
  assert_contains "$ERR" "submodules"
  run wt rm demo --force
  assert_code 0
  assert_missing "$(wt_dir demo)"
}

test_hook_never_runs_in_the_wrong_directory() {
  if [ "$(id -u)" = 0 ]; then
    return 0
  fi
  # shellcheck disable=SC2016
  repo_with_conf 'teardown=touch "$PWD/teardown-ran-here"'
  cd "$MAIN"
  wt new demo >/dev/null 2>&1
  chmod 000 "$(wt_dir demo)"
  run wt rm demo --force
  chmod 755 "$(wt_dir demo)"
  assert_code 5
  assert_missing "$MAIN/teardown-ran-here"
  assert_exists "$(wt_dir demo)"
}

test_rm_detached_head() {
  make_repo
  cd "$MAIN"
  wt new det >/dev/null 2>&1
  git -C "$(wt_dir det)" checkout -q --detach
  commit_file "$(wt_dir det)" loose.txt loose
  run wt rm det
  assert_code 3
  assert_contains "$ERR" "its HEAD has 1 commit(s)"
  run wt rm det --force
  assert_code 0
  assert_missing "$(wt_dir det)"
  assert_contains "$(git branch --list det)" det "a detached worktree never deletes a branch"
}

test_rm_keeps_a_branch_it_does_not_own() {
  make_repo
  cd "$MAIN"
  wt new sw >/dev/null 2>&1
  git -C "$(wt_dir sw)" switch -q -c release-1
  run wt rm sw
  assert_code 0
  assert_contains "$ERR" "kept branch 'release-1'"
  assert_contains "$(git branch --list release-1)" release-1
  assert_contains "$(git branch --list sw)" sw
}

test_rm_treats_merged_pr_without_head_as_unknown() {
  make_repo
  cd "$MAIN"
  wt new demo >/dev/null 2>&1
  commit_file "$(wt_dir demo)" feature.txt work
  gh_prs "demo 5 MERGED "
  run wt rm demo
  assert_code 3
  assert_contains "$ERR" "no PR data from gh"
}

test_sync_without_origin() {
  git init -q "$T_DIR/repo"
  commit_file "$T_DIR/repo" a.txt a
  cd "$T_DIR/repo"
  run wt new x --sync
  assert_code 2
  assert_contains "$ERR" "needs a remote named origin"
}

test_doctor_idle_days_from_conf() {
  repo_with_conf "idle_days=100000"
  cd "$MAIN"
  wt new demo >/dev/null 2>&1
  local dir admin
  dir=$(wt_dir demo)
  printf 'old\n' >"$dir/old.txt"
  git -C "$dir" add old.txt
  GIT_AUTHOR_DATE=2026-01-01T00:00:00 GIT_COMMITTER_DATE=2026-01-01T00:00:00 git -C "$dir" commit -q -m old
  admin=$(git -C "$dir" rev-parse --absolute-git-dir)
  touch -t 202601010000 "$admin/HEAD" "$admin/index" "$admin/logs/HEAD"
  gh_prs "demo 4 MERGED $(tip demo)"
  run wt doctor
  assert_code 0
  run wt doctor --idle-days 1
  assert_code 4
  assert_contains "$OUT" "cleanup-candidate"
}

test_doctor_default_behind() {
  make_repo
  push_from_other_clone
  git -C "$MAIN" fetch -q origin
  cd "$MAIN"
  run wt doctor
  assert_code 0
  assert_contains "$OUT" "default-behind"
}

test_doctor_case_insensitive_shadow_ref() {
  make_repo
  git -C "$MAIN" branch Origin/main main
  cd "$MAIN"
  run wt doctor
  assert_code 4
  assert_contains "$OUT" "refs/heads/Origin/main"
}

test_doctor_json_normalizes_numbers() {
  repo_with_conf "stack_prefix=p-" "stack_budget=04" "idle_days=07"
  cd "$MAIN"
  docker_state "" "" ""
  run wt doctor --json
  assert_code 0
  json_ok "$OUT"
  assert_contains "$OUT" '"stack_budget": 4'
}

# register_via_symlink <dir>: make git list <dir> under a path that goes through
# a symlink, as a registration made through a symlinked parent looks.
register_via_symlink() {
  local admin
  ln -s "$T_DIR" "$T_DIR/link"
  admin=$(git -C "$1" rev-parse --absolute-git-dir)
  printf '%s\n' "$T_DIR/link/${1##*/}/.git" >"$admin/gitdir"
}

test_rm_refuses_from_inside_a_symlinked_registration() {
  make_repo
  cd "$MAIN"
  wt new x >/dev/null 2>&1
  register_via_symlink "$(wt_dir x)"
  assert_contains "$(git worktree list --porcelain)" "$T_DIR/link/.wt-repo-x"
  cd "$(wt_dir x)"
  run wt rm x --force
  assert_code 3
  assert_contains "$ERR" "you are inside"
  assert_exists "$(wt_dir x)"
  cd "$MAIN"
  run wt path x
  assert_code 0 "a slug recorded under the physical path still counts"
}

test_adopt_a_symlinked_registration() {
  make_repo
  git -C "$MAIN" worktree add -q "$T_DIR/manual" -b manual
  register_via_symlink "$T_DIR/manual"
  cd "$MAIN"
  run wt adopt "$T_DIR/manual" man
  assert_code 0
  assert_eq "$T_DIR/link/manual" "$OUT"
  run wt path man
  assert_eq "$T_DIR/link/manual" "$OUT"
}

test_hook_note_when_branch_conf_differs() {
  repo_with_conf "materialize=true" "teardown=true"
  cd "$MAIN"
  run wt new a
  assert_code 0
  assert_not_contains "$ERR" "note:"
  printf 'teardown=echo branch-hook\n' >"$(wt_dir a)/.wt.conf"
  run wt rm a --force
  assert_code 0
  assert_contains "$ERR" "note: $(wt_dir a)/.wt.conf differs from the main checkout's"
}

t "help lists every command" test_help_lists_every_command
t "version" test_version
t "outside a repository exits 2" test_outside_a_repository_exits_2
t "unknown command exits 2" test_unknown_command_exits_2
t "repository without a remote" test_repository_without_remote
t "master as the default branch" test_master_default_branch
t "ls without linked worktrees" test_ls_without_linked_worktrees
t "new creates a sibling worktree" test_new_creates_sibling_worktree
t "new twice reuses the worktree" test_new_twice_reuses
t "new rejects bad and reserved slugs" test_new_rejects_bad_slugs
t "new refuses a remote branch name (shadow ref)" test_new_refuses_remote_branch_name
t "new refuses a remote start point" test_new_refuses_remote_start_point
t "new refuses an unregistered directory" test_new_refuses_unregistered_directory
t "new --sync fast-forwards the default branch" test_new_sync_fast_forwards_default_branch
t "new --sync refuses a diverged default branch" test_new_sync_refuses_diverged_default_branch
t "new --sync refuses when the main checkout is elsewhere" test_new_sync_refuses_when_main_checkout_is_elsewhere
t "new --from a tag and --branch" test_new_from_tag_and_custom_branch
t "new on an existing branch" test_new_existing_branch
t "new refuses a branch checked out elsewhere" test_new_refuses_branch_checked_out_elsewhere
t "WT_HOME and worktree_dir set the parent" test_new_parent_overrides
t "new works from inside a linked worktree" test_new_from_inside_a_linked_worktree
t "clone and copy from the main checkout" test_clone_and_copy
t "copy never overwrites" test_copy_never_overwrites
t "materialize hook gets WT_ variables" test_materialize_hook_gets_variables
t "failing hook exits 5, re-run is safe" test_failing_hook_exits_5_and_rerun_is_safe
t "--no-hooks skips the materialize hook" test_no_hooks_skips_materialize_hook
t "failed copy-on-write clone falls back to a plain copy" test_clone_falls_back_to_plain_copy
t ".wt.conf validation" test_conf_rejects_paths_outside_the_repository
t ".wt.conf tolerates CRLF, spaces and unknown keys" test_conf_tolerates_crlf_spaces_and_unknown_keys
t "ls table" test_ls_table
t "ls --json shape" test_ls_json_shape
t "ls shows unadopted worktrees" test_ls_shows_unadopted_worktree
t "ls reads PR and stack state" test_ls_reads_pr_and_stack_state
t "path" test_path
t "adopt" test_adopt
t "adopt refusals" test_adopt_refusals
t "rm refuses a dirty worktree" test_rm_refuses_dirty_worktree
t "rm refuses unmerged commits without gh" test_rm_refuses_unmerged_commits_without_gh
t "rm removes a merged worktree and its branch" test_rm_removes_merged_worktree_and_branch
t "rm --keep-branch" test_rm_keep_branch
t "rm --force removes a dirty worktree" test_rm_force_removes_dirty_worktree
t "rm accepts a squash-merged PR" test_rm_accepts_squash_merged_pr
t "rm refuses commits after the merged PR" test_rm_refuses_commits_after_merged_pr
t "rm refuses an open PR" test_rm_refuses_open_pr
t "rm teardown runs in the worktree before removal" test_rm_teardown_runs_in_worktree_first
t "rm teardown from the branch's own .wt.conf" test_rm_teardown_from_branch_conf_before_merge
t "rm refuses teardown from the main checkout by default" test_rm_refuses_teardown_from_main_checkout_by_default
t "rm --force runs teardown in the main checkout, other registrations stay" test_rm_force_runs_teardown_in_main_checkout_and_keeps_other_registrations
t "rm --no-hooks unregisters a missing directory" test_rm_no_hooks_unregisters_a_missing_directory
t "rm --no-hooks skips teardown" test_rm_no_hooks_skips_teardown
t "rm failing teardown keeps the worktree" test_rm_failing_teardown_keeps_worktree
t "rm refuses from inside the worktree" test_rm_refuses_from_inside_the_worktree
t "rm leaves the remote branch alone" test_rm_leaves_remote_branch_alone
t "rm unknown slug" test_rm_unknown_slug
t "doctor on a clean repository" test_doctor_clean_repository
t "doctor finds shadow refs" test_doctor_shadow_ref
t "doctor finds stale registrations" test_doctor_stale_registration
t "doctor finds unadopted worktrees" test_doctor_unadopted
t "doctor finds cleanup candidates" test_doctor_cleanup_candidate
t "doctor checks stacks and volumes" test_doctor_stacks
t "doctor --json" test_doctor_json
t "doctor reports a moved origin" test_doctor_reports_moved_origin
t "a copied wt.slug does not hijack rm" test_copied_slug_does_not_hijack_rm
t "a slug shared by two worktrees is refused" test_shared_slug_is_refused
t "rm refuses a locked worktree before hooks" test_rm_refuses_locked_worktree_before_hooks
t "rm refuses checked-out submodules" test_rm_refuses_checked_out_submodules
t "a hook never runs in the wrong directory" test_hook_never_runs_in_the_wrong_directory
t "rm of a detached HEAD" test_rm_detached_head
t "rm keeps a branch it does not own" test_rm_keeps_a_branch_it_does_not_own
t "rm treats a merged PR without head as unknown" test_rm_treats_merged_pr_without_head_as_unknown
t "--sync without origin" test_sync_without_origin
t "doctor takes idle_days from .wt.conf" test_doctor_idle_days_from_conf
t "doctor reports a default branch behind origin" test_doctor_default_behind
t "doctor finds case-insensitive shadow refs" test_doctor_case_insensitive_shadow_ref
t "doctor --json normalizes numbers" test_doctor_json_normalizes_numbers
t "rm refuses from inside a symlinked registration" test_rm_refuses_from_inside_a_symlinked_registration
t "adopt a symlinked registration" test_adopt_a_symlinked_registration
t "a note when the branch's .wt.conf differs" test_hook_note_when_branch_conf_differs
t_done
