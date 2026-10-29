# shellcheck shell=bash
# Shared helpers for tests/*.test.sh: an isolated git environment, temporary
# repositories and a tiny assertion runner. Each test function runs in its own
# subshell and directory, so one failure does not stop the others.

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$(cd "$TESTS_DIR/.." && pwd -P)
TEST_BASH=${TEST_BASH:-$BASH}
WT_BIN=${WT_BIN:-"$REPO_ROOT/bin/wt"}
export TESTS_DIR REPO_ROOT TEST_BASH WT_BIN

T_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/agent-harness-test.XXXXXX")
T_ROOT=$(cd "$T_ROOT" && pwd -P)
trap 'rm -rf "$T_ROOT"' EXIT

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
unset WT_HOME WT_VERBOSE
export WT_NO_GH=1 WT_NO_DOCKER=1
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$T_ROOT/gitconfig"
export HOME="$T_ROOT/home"
mkdir -p "$HOME"
cat >"$GIT_CONFIG_GLOBAL" <<'EOF'
[user]
	name = Test
	email = test@example.com
[init]
	defaultBranch = main
[advice]
	detachedHead = false
[commit]
	gpgsign = false
[tag]
	gpgsign = false
EOF

T_PASS=0
T_FAIL=0

fail() {
  printf '  assertion failed: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  [ "$1" = "$2" ] || fail "${3:-values differ}: expected [$1], got [$2]"
}

assert_contains() {
  case $1 in
    *"$2"*) ;;
    *) fail "${3:-text not found}: [$2] not in [$1]" ;;
  esac
}

assert_not_contains() {
  case $1 in
    *"$2"*) fail "${3:-unexpected text}: [$2] found in [$1]" ;;
  esac
}

assert_exists() {
  [ -e "$1" ] || fail "expected $1 to exist"
}

assert_missing() {
  if [ -e "$1" ] || [ -L "$1" ]; then
    fail "expected $1 to be absent"
  fi
}

# run <cmd...>: stdout goes to OUT, stderr to ERR, the exit status to CODE.
run() {
  set +e
  "$@" >"$T_DIR/.stdout" 2>"$T_DIR/.stderr"
  CODE=$?
  set -e
  OUT=$(cat "$T_DIR/.stdout")
  ERR=$(cat "$T_DIR/.stderr")
}

assert_code() {
  [ "$CODE" = "$1" ] || fail "exit code: expected $1, got $CODE${2:+ ($2)}; stdout: [$OUT]; stderr: [$ERR]"
}

wt() {
  "$TEST_BASH" "$WT_BIN" "$@"
}

# make_repo [name]: a bare origin plus a main checkout with one commit pushed to
# origin/main and origin/HEAD set. Sets ORIGIN and MAIN.
make_repo() {
  local name=${1:-repo}
  ORIGIN="$T_DIR/$name-origin.git"
  MAIN="$T_DIR/$name"
  git init -q --bare "$ORIGIN"
  git init -q "$MAIN"
  printf 'hello\n' >"$MAIN/README.md"
  git -C "$MAIN" add README.md
  git -C "$MAIN" commit -q -m "initial"
  git -C "$MAIN" remote add origin "$ORIGIN"
  git -C "$MAIN" push -q -u origin main
  git -C "$MAIN" remote set-head origin main
}

# commit_file <dir> <file> <content> [message]
commit_file() {
  mkdir -p "$(dirname "$1/$2")"
  printf '%s\n' "$3" >"$1/$2"
  git -C "$1" add "$2"
  git -C "$1" commit -q -m "${4:-change $2}"
}

# stub <name> <body>: an executable /bin/sh stub on PATH for the current test.
stub() {
  mkdir -p "$T_DIR/bin"
  {
    printf '#!/bin/sh\n'
    printf '%s\n' "$2"
  } >"$T_DIR/bin/$1"
  chmod +x "$T_DIR/bin/$1"
  case ":$PATH:" in
    *":$T_DIR/bin:"*) ;;
    *) PATH="$T_DIR/bin:$PATH" ;;
  esac
}

# t <description> <function>
t() {
  T_DIR="$T_ROOT/$2"
  mkdir -p "$T_DIR"
  local rc
  set +e
  (
    set -e
    cd "$T_DIR"
    "$2"
  ) >"$T_DIR.log" 2>&1
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    T_PASS=$((T_PASS + 1))
    printf 'ok   %s\n' "$1"
  else
    T_FAIL=$((T_FAIL + 1))
    printf 'FAIL %s\n' "$1"
    sed 's/^/     /' "$T_DIR.log"
  fi
}

t_done() {
  # shellcheck disable=SC2016
  printf '%s: %d passed, %d failed (bash %s)\n' "$(basename "$0")" "$T_PASS" "$T_FAIL" "$("$TEST_BASH" -c 'printf %s "$BASH_VERSION"')"
  [ "$T_FAIL" -eq 0 ]
}
