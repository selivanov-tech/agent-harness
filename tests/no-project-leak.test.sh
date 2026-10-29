#!/usr/bin/env bash
# The skills are project-agnostic. Names, paths and commands of a concrete
# project may appear only inside marked illustrations: blockquotes whose first
# line starts with "> Illustration (".
#
# The terms that must never appear outside an illustration are private to the
# maintainer: one regex per line in tests/leak-terms.local (git-ignored), or a
# single pattern in $LEAK_TERMS. Without either, the scan is skipped.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

leak_re() {
  if [ -n "${LEAK_TERMS:-}" ]; then
    printf '%s' "$LEAK_TERMS"
  elif [ -f "$(dirname "$0")/leak-terms.local" ]; then
    grep -v '^$' "$(dirname "$0")/leak-terms.local" | paste -sd'|' -
  fi
}

outside_illustrations() {
  awk '
    /^> Illustration \(/ { skip = 1; next }
    skip && /^>/ { next }
    { skip = 0; print }
  ' "$1"
}

test_no_project_leaks_outside_illustrations() {
  local re file hits
  re=$(leak_re)
  if [ -z "$re" ]; then
    echo "  (skipped: no leak terms configured)"
    return 0
  fi
  while IFS= read -r file; do
    hits=$(outside_illustrations "$file" | grep -inE "$re" || true)
    if [ -n "$hits" ]; then
      fail "project-specific text outside an illustration in ${file#"$REPO_ROOT"/}: $hits"
    fi
  done < <(find "$REPO_ROOT/skills" -type f | sort)
}

test_filter_drops_only_illustrations() {
  local out
  printf 'keep\n> Illustration (acme): drop acme\n> still dropped\nkept acme\n> plain quote acme\n' >"$T_DIR/sample.md"
  out=$(outside_illustrations "$T_DIR/sample.md")
  assert_not_contains "$out" "drop acme"
  assert_not_contains "$out" "still dropped"
  assert_contains "$out" "kept acme"
  assert_contains "$out" "plain quote acme"
}

test_illustrations_exist() {
  local count
  count=$(grep -rh '^> Illustration (' "$REPO_ROOT/skills" | wc -l | tr -d ' ')
  [ "$count" -gt 0 ] || fail "no illustrations found: the marker convention changed"
}

t "no project-specific text outside illustrations" test_no_project_leaks_outside_illustrations
t "the filter drops only illustration blockquotes" test_filter_drops_only_illustrations
t "illustrations use the marker" test_illustrations_exist
t_done
