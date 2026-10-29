# agent-harness

Tooling and skills for parallel AI coding sessions. Every session works in its own git worktree next to the main checkout, the main checkout stays read-only, and one coordinator session runs the spec → plan → GO → review → merge cycle. The repository holds tools as well as skills, and is meant to stay project-agnostic: concrete project names live only in marked illustrations.

| Path | What it is |
|---|---|
| `bin/wt` | Worktree CLI: `new`, `ls`, `path`, `adopt`, `rm`, `doctor`. One bash script, bash 3.2 compatible, no dependencies beyond git; `gh` and `docker` are used when present. |
| `bin/install` | Links the skills for Claude Code and Codex and puts `wt` on `PATH`. |
| `skills/worktree-sessions` | Playbook for an implementer session: own worktree, gate, stack budget, PR, cleanup. |
| `skills/session-orchestrator` | Coordinator skill: profile, spec, launch, plan validation, GO drafts, merges. References: spec skeleton, session prompt, plan-validation checklist, project profile template. |
| `tests/` | Shell tests for `wt`, the installer and the skills. |

## Install

```bash
git clone https://github.com/selivanov-tech/agent-harness.git ~/src/agent-harness
~/src/agent-harness/bin/install
```

`bin/install` creates symlinks only:

- `~/.agents/skills/<skill>` → `<repo>/skills/<skill>`
- `~/.claude/skills/<skill>` and `~/.codex/skills/<skill>` → `../../.agents/skills/<skill>` (Codex only when `~/.codex` exists)
- `~/.local/bin/wt` → `<repo>/bin/wt`

It is idempotent, never replaces a file, a directory or a symlink it did not create (it reports a conflict and exits 1), and supports `--dry-run` and `--uninstall`. Updating is `git pull`: the links point into the checkout. If `~/.local/bin` is not on `PATH`, the installer says so.

## `wt` in one screen

```text
wt new <slug>                   create or reuse <parent>/.wt-<repo>-<slug> on branch <slug>, print its path
wt new <slug> --sync            fetch origin and fast-forward the default branch in the main checkout first
wt new <slug> --from v1.2       start from a local branch, tag or commit (never origin/…)
wt new <slug> --branch feat/x   branch name when it should differ from the slug
wt ls [--json]                  slug, branch, ahead/behind, dirty, PR (gh), stack (docker), path
wt path <slug>                  path for cd or Claude Code's EnterWorktree
wt adopt <dir> <slug>           give a slug to a worktree made by hand or by an agent harness
wt rm <slug>                    teardown hook, then remove the worktree and its local branch
wt doctor [--json]              read-only: shadow refs, stale or unadopted worktrees, cleanup candidates, stacks
```

`wt help` is the full reference: every option, the `.wt.conf` keys, hook variables, environment variables and exit codes (0 success, 1 internal, 2 usage, 3 safety refusal, 4 doctor findings, 5 hook failure).

A repository without `.wt.conf` works in basic mode: a plain worktree and branch, nothing cloned, copied or run. A `.wt.conf` at the repository root adds heavy directories to clone (copy-on-write on APFS and reflink filesystems), files to copy, `materialize` and `teardown` hooks, and the stack prefix, budget and idle threshold that `wt ls` and `wt doctor` check.

## Safety

- `wt` acts only on worktrees registered in the current repository. It never deletes remote branches, never runs `docker volume prune` or any other docker write, and `wt doctor` changes nothing.
- `wt rm` refuses uncommitted or untracked changes, commits that are neither in the default branch nor in a merged PR, an open PR, checked-out submodules and a missing worktree directory (the teardown hook would then run in the main checkout); `--force` lifts these. It always refuses a locked worktree, a slug shared by several worktrees, and being run from inside the worktree. It deletes a local branch only when it is the branch `wt` created or adopted for that worktree.
- New branches start from local refs only. `--branch origin/…` and `--from origin/…` are refused: git would create a local branch that shadows the remote-tracking one. `--sync` is the way to a fresh base.
- **Hooks are code.** `wt new` in a repository with a `.wt.conf` runs that file's `materialize` command, and `wt rm` its `teardown` command. `wt` prints each command before running it; use `wt` only in repositories you trust. The hooks come from the `.wt.conf` of the worktree's own branch and run with your rights — the same trust as running `make` in that worktree — so a branch can change the commands `wt` runs for you; `wt` prints a note when the branch's `.wt.conf` differs from the main checkout's. A teardown hook must take the slug from `WT_SLUG`, never from the directory it runs in.
- `wt` records `wt.slug`, `wt.path` and `wt.branch` in each worktree's own config. `git worktree add` copies that config into worktrees made from inside another one; `wt` ignores a copied slug whose `wt.path` names a different directory, and `wt doctor` reports it.
- `stack_budget` counts only `<stack_prefix>*` compose projects. Lower it when the Docker VM gets smaller (for a light app + Postgres stack: 4 fit into today's ~8 GB VM, plan 3 for 6 GB).

## Adopting a project

1. `wt new try-it && wt rm try-it` in the repository: it must leave `git worktree list` and `git branch` unchanged.
2. Write `.wt.conf`: what a fresh worktree lacks (dependency directories, `.env`, git-ignored generated agent rules such as `CLAUDE.md`/`AGENTS.md`), and hooks that are safe to run twice.
3. For Docker projects, make the compose project, container names and ports depend on the slug so each worktree gets its own stack and data, and the main stack stays untouched.
4. Write the profile (`.claude/multi-session.md`, or `.ai/guidelines/multi-session.md` for Laravel Boost projects) from the template.
5. `wt doctor` must be clean.

Details and a worked example: [skills/worktree-sessions/references/adoption-example.md](skills/worktree-sessions/references/adoption-example.md). Profile template: [skills/session-orchestrator/references/project-profile-template.md](skills/session-orchestrator/references/project-profile-template.md).

## Development

```bash
tests/run.sh                      # all tests with bash from PATH
TEST_BASH=/bin/bash tests/run.sh  # macOS: prove bash 3.2 compatibility
shellcheck bin/* tests/*.sh
```

CI runs shellcheck on Ubuntu and the tests on Ubuntu (bash 5) and macOS (`/bin/bash` 3.2). Tests build throwaway repositories under `$TMPDIR`, isolate git from the user's config, and replace `gh` and `docker` with stubs.

Rules for `bin/wt`: stay bash 3.2 compatible (no associative arrays, `${arr[@]+"${arr[@]}"}` for arrays that may be empty); messages go to stderr, data to stdout; `die` is never called inside `$(...)` so exit codes survive; every behaviour in `wt help` has a test. Commits follow Conventional Commits.

## Background

The practices come from the multi-session workflow of an earlier project (sibling worktrees with a per-worktree slug, shadow-ref protection, copy-on-write clones of dependencies, a stack budget, a coordinator that never relays the owner's GO); none of its code was copied.

## See also

[LifeOS Lite](https://github.com/selivanov-tech/lifeos-lite) — a companion project: a personal assistant profile for Hermes that keeps goals, weekly reviews, workouts and a journal in plain Markdown files (Russian, Windows installer). The same idea of keeping state in files that the agent reads on demand, applied to a personal operating system instead of a codebase.
