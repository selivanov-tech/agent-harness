#!/usr/bin/env bash
# Skills may mention only the wt commands and flags that `wt help` documents, and
# every skill is packaged for both Claude Code (SKILL.md) and Codex (agents/openai.yaml).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

# wt_mentions: one line per "wt <command> ..." mention in the skill documents.
wt_mentions() {
  local doc
  while IFS= read -r doc; do
    # shellcheck disable=SC2016
    grep -oE '(^|[^A-Za-z0-9_./-])wt [a-z]+( +(--[a-z-]+|<[^>]*>|[A-Za-z0-9_./:$(){}-]+))*' "$doc" |
      sed -E 's/^[^w]*//' || true
  done < <(find "$REPO_ROOT/skills" -name '*.md' -type f | sort)
}

test_skill_commands_exist_in_wt_help() {
  local help commands mention cmd usage flag mentions
  help=$(wt help)
  commands=" $(printf '%s\n' "$help" | sed -nE 's/^  wt ([a-z]+).*/\1/p' | tr '\n' ' ')"
  mentions=$(wt_mentions)
  [ -n "$mentions" ] || fail "no wt mentions found: the extractor is broken"
  while IFS= read -r mention; do
    cmd=$(printf '%s' "$mention" | awk '{print $2}')
    case "$commands" in
      *" $cmd "*) ;;
      *) fail "a skill mentions '$mention', but wt help has no command '$cmd'" ;;
    esac
    usage=$(printf '%s\n' "$help" | grep -E "^  wt $cmd( |$)")
    for flag in $(printf '%s' "$mention" | grep -oE -- '--[a-z-]+' || true); do
      assert_contains "$usage" "$flag" "flag of wt $cmd in '$mention'"
    done
  done <<<"$mentions"
}

test_both_skills_exist() {
  assert_exists "$REPO_ROOT/skills/worktree-sessions/SKILL.md"
  assert_exists "$REPO_ROOT/skills/session-orchestrator/SKILL.md"
}

test_skills_are_packaged() {
  local dir name yaml
  for dir in "$REPO_ROOT"/skills/*/; do
    dir=${dir%/}
    name=$(basename "$dir")
    assert_eq "---" "$(sed -n '1p' "$dir/SKILL.md")" "frontmatter start of $name"
    assert_eq "name: $name" "$(sed -n '2p' "$dir/SKILL.md")" "frontmatter name of $name"
    assert_contains "$(sed -n '3p' "$dir/SKILL.md")" "description: " "frontmatter description of $name"
    assert_exists "$dir/agents/openai.yaml"
    yaml=$(cat "$dir/agents/openai.yaml")
    for key in "interface:" "display_name:" "short_description:" "default_prompt:" "\$$name"; do
      assert_contains "$yaml" "$key" "agents/openai.yaml of $name"
    done
  done
}

test_skill_links_resolve() {
  local dir link
  for dir in "$REPO_ROOT"/skills/*/; do
    dir=${dir%/}
    while IFS= read -r link; do
      assert_exists "$dir/$link"
    done < <(grep -oE '\]\(references/[^)]+\)' "$dir/SKILL.md" | sed -E 's/^\]\(//; s/\)$//' || true)
  done
}

t "every wt command and flag in the skills exists" test_skill_commands_exist_in_wt_help
t "both skills exist" test_both_skills_exist
t "skills are packaged for Claude Code and Codex" test_skills_are_packaged
t "reference links in SKILL.md resolve" test_skill_links_resolve
t_done
