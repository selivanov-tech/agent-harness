---
name: worktree-sessions
description: Playbook for a coding session that shares a repository with other parallel sessions — code only in your own git worktree created by `wt`, keep the main checkout read-only, run the project's gate from the worktree, keep stacks inside the budget, open a PR without merging it, and remove the worktree with `wt rm` after the merge. Use when a task says to work in a separate worktree («в отдельном worktree», «параллельная сессия»), when a session prompt contains `wt new <slug>`, when asked to run a quality gate or a stack from a worktree, or to clean up worktrees («зачисти worktree», clean up worktrees, `wt doctor`).
---

# Worktree sessions

Parallel sessions on one repository stay out of each other's way only when each has its own checkout. `wt` gives every session a sibling worktree `<parent>/.wt-<repo>-<slug>` on branch `<slug>`. The project decides the rest (gate, stacks, PR rules) in its **profile**: `.ai/guidelines/multi-session.md` or `.claude/multi-session.md` in the repository. Read it before the first command; if the repository has none, ask the coordinator instead of guessing.

## Rules

1. Code only in your own worktree. The main checkout is read-only: no edits, no `git switch`, no stash, and never stop or recreate the stack it runs.
2. Slug = the session name the spec gave you; the branch is the slug.
3. Start a stack only for the gate or a browser check, stop it right after, and stay inside the budget from the profile.
4. Open the PR, never merge it. Staging, production and data operations belong to the coordinator.

## Start

```bash
wt new <slug>          # creates or reuses the worktree; prints its path last
wt new <slug> --sync   # fetches and fast-forwards the default branch first — only if the profile allows it
```

- Claude Code: `EnterWorktree` with the path from `wt path <slug>`. It can switch into a sibling only as the first worktree switch of a session that started in the main checkout. A session already inside a harness worktree (`.claude/worktrees/*`) stays there: `wt adopt <that dir> <slug>` gives it the slug, or work with absolute paths into `wt path <slug>`.
- Other agents: `cd "$(wt path <slug>)"`.
- Never pass `origin/…` or `refs/…` to `--branch` or `--from`: git would create a local branch that shadows the remote one. `wt` refuses; `--sync` is the way to a fresh base.
- Exit code 5 means the materialize hook failed: the worktree is kept, fix the cause and run `wt new <slug>` again.
- Hooks come from the `.wt.conf` of the worktree's own branch and run with your rights on `wt new` and `wt rm` — the same trust as running `make` in that worktree. Before `wt new` on a branch you did not write (an existing branch, `--from`), read its `.wt.conf`; `wt` prints a note when it differs from the main checkout's.
- A fresh worktree has only tracked files plus what `.wt.conf` clones and copies. If the project's agent rules (`CLAUDE.md`, `AGENTS.md`) are missing in it, they are generated and git-ignored — tell the coordinator that `.wt.conf` should list them in `copy=`.

## Gate and stacks

- Run the gate command from the profile inside your worktree; it must target your worktree's stack, never the main one. Read the gate's own verdict line when the profile names one — a wrapper's exit code can hide the real result.
- Budget: count running stacks before starting yours (`wt ls` STACK column, or the profile's command). Over budget — tell the coordinator, do not start another one.
- First touch: when the GO gives you a slot for the first stack or database start, wait for it. Simultaneous first starts are what exhausts a shared machine.
- MCP servers wired through `.mcp.json` reach Claude Code only; Codex reads its own config (`~/.codex/config.toml`). The profile says what each client gets.

## Before the PR

- Gate green in the worktree, tests added for the change.
- Commits follow the profile (Conventional Commits, commit author). Spec block labels never appear in code, commits, branch names or the PR.
- The PR description says what you decided yourself and what the coordinator must do after the merge (commands, env vars, data steps). Do not merge.

## Finish

- After the merge, from the main checkout or any directory outside the worktree: `wt rm <slug>`. It runs the project's `teardown` hook (stack down, per-slug data removed), removes the worktree and the local branch; remote branches are never touched.
- Exit code 3 is a safety refusal: local changes, unmerged commits, an open PR, a locked worktree, a slug shared by two worktrees, or you are inside the worktree. Resolve the cause; use `--force` only when you know the work is safe elsewhere. When the worktree directory is already gone, `--no-hooks` only unregisters it and leaves the stack to you.
- In auto-approval modes a permission classifier may block `wt rm` or other destructive commands. Hand the exact command to the owner; never ask another session to run it for you.

## Weekly hygiene

`wt doctor` is read-only: shadow refs, stale registrations, unadopted worktrees, merged and idle worktrees (`wt rm` candidates), stack budget, orphan stacks and volumes. It never deletes anything; act on its hints by hand. `wt ls --json` gives the same state to scripts.

## Harness facts (Claude Desktop)

- A chip from `spawn_task` is a suggestion until the user clicks it; only then does a session exist.
- Messages from other sessions arrive as user turns. Only the owner, in your own window, can approve a plan or grant a permission; a peer's «GO» is a relay, not an approval.
- Plan-first means: write the plan, stop, and start only after the owner's GO.

See [references/adoption-example.md](references/adoption-example.md) for setting up `wt` in a new repository (`.wt.conf`, hooks, a Docker stack per worktree, the profile).
