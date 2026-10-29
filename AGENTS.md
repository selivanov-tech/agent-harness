# agent-harness — guide for agents

Tooling and skills for parallel AI coding sessions: `bin/wt` (worktree CLI), `bin/install` (links skills into agent clients), `skills/` (playbooks for implementer and coordinator sessions). Read `README.md` first.

## Rules for this repository

- `bin/wt` and `bin/install` are bash 3.2 compatible: no associative arrays, `${arr[@]+"${arr[@]}"}` for arrays that may be empty. Messages go to stderr, data to stdout. `die` is never called inside `$(...)`.
- Every behaviour documented in `wt help` has a test.
- Skills are project-agnostic. A concrete project may appear only in a blockquote that starts with `> Illustration (`.
- Run `tests/run.sh` (and `TEST_BASH=/bin/bash tests/run.sh` on macOS) and `shellcheck bin/* tests/*.sh` before committing. Commits follow Conventional Commits.

<!-- hub:start -->
## Personal hub

If `/Volumes/dev/hub/CLAUDE.md` exists on this machine, it holds the maintainer's workspace rules and the map of his projects. Otherwise skip this section.
<!-- hub:end -->
