# Project profile template

The profile tells the coordinator and every session how parallel work runs in one repository. Copy the template to `.claude/multi-session.md` — or to `.ai/guidelines/multi-session.md` when the project compiles its agent rules from `.ai/guidelines` (Laravel Boost), so the profile also lands in the generated `CLAUDE.md` and `AGENTS.md`. Fill every section, delete the hints, keep the headings: the orchestrator and the session prompt refer to them by name. Machine settings stay in `.wt.conf`, not here.

## Template

```markdown
# Multi-session profile — <project>

## Specs and reviews
- Specs live in: <folder or path>. Plan reviews: <same folder, one note per review round>.
- Who edits these notes: <the coordinator only>.

## Worktrees
- Create: `wt new <slug>` (slug = session name). The main checkout <path> stays on <default branch> and is read-only for sessions.
- `wt new --sync` (fast-forwards the main checkout's default branch): <allowed / coordinator and owner only, because <reason>>.
- Agent rule files in a fresh worktree: <tracked in git / generated and git-ignored, so `.wt.conf` copies them: `copy=… CLAUDE.md AGENTS.md`>.

## Quality gate
- Command: `<gate>` from the worktree. It runs: <formatter, static analysis, tests>.
- Verdict: <exit code / the line to read>. CI is the final judge.

## Stacks and data
- Default: <no stack — tests only / the gate starts and stops one / a browser check only>.
- Budget: <N> running `<stack_prefix>*` stacks at once; the main stack does not count. <When to lower it.>
- First touch of shared resources: <one session at a time, slot given in the GO>.
- A worktree's data: <own database in its own stack>; `wt rm` removes it through the teardown hook.

## PR and merge
- Branch = slug → PR → <squash-merge on green CI>. Sessions never merge; the owner merges in the spec's order.
- The PR description lists the session's own decisions and the coordinator's post-merge steps.

## Conventions
- Commits: <Conventional Commits>; author <Name <email>>.
- Language of user-facing strings and code comments: <…>.
- Tests: <every change covered; how to run one test from the worktree>.

## Prohibited for sessions
- <editing the main checkout; stopping or recreating its stack>
- <deploys, staging and production data — coordinator only>
- <editing planning notes — coordinator only>
- <new dependencies without the coordinator's decision>

## Agent clients and MCP
- Claude Code: <MCP servers from `.mcp.json`, and how they reach the worktree's own stack>.
- Codex: <servers configured in `~/.codex/config.toml`; `.mcp.json` does not reach Codex — list the gap as a follow-up>.
```

## Filled example — a Docker project with one compose file

```markdown
# Multi-session profile — myapp

## Specs and reviews
- Specs and plan reviews: a notes vault or `docs/specs/`, one note per spec and one per review round. Only the coordinator edits them.

## Worktrees
- Create: `wt new <slug>`. The main checkout `~/src/myapp` stays on `main`, runs the main stack `myapp-dev`, and is read-only for sessions.
- `wt new --sync`: coordinator and owner only — the main stack mounts the main checkout, so moving its branch changes the running app.
- `CLAUDE.md` and `AGENTS.md` are generated from `.ai/guidelines/` and git-ignored; `.wt.conf` copies them (`copy=.env CLAUDE.md AGENTS.md`), so a new worktree has the rules from its first minute. After `make start` in the worktree, `make guidelines` regenerates them from the branch.

## Quality gate
- `make ready` from the worktree: formatter check, static analysis, tests — inside the worktree's own stack, which the gate starts when needed and stops again if it started it.
- Read each step's output, not only make's exit code. CI decides.

## Stacks and data
- Default: no running stack beyond the gate. For a browser check `make start`, and `make stop` as soon as it is done.
- Budget: 4 running `myapp-wt-*` stacks; `myapp-dev` does not count. Lower it to 3 when the Docker VM goes down to 6 GB.
- First stack start: in the slot from the GO, a few minutes after the previous session.
- Each worktree has its own Postgres (volume `myapp-wt-<slug>_pg-data`); `wt rm` deletes it through `make wt-teardown`.

## PR and merge
- Branch = slug → PR → squash-merge on green CI. Sessions never merge; the owner merges in the spec's order.
- The PR description lists the session's decisions, the coordinator's post-merge steps, and screenshots for UI changes.

## Conventions
- Conventional Commits; author `Jane Doe <jane@example.com>`.
- User-facing strings in Russian, matching the existing wording; code comments only for genuinely hard logic.
- Every change has a test; one test from the worktree: `make test FILTER=<name>`.

## Prohibited for sessions
- Editing the main checkout; stopping or recreating `myapp-dev`.
- Deploys, production data, `docker volume prune`.
- Editing the planning notes.
- New dependencies without the coordinator's decision.

## Agent clients and MCP
- Claude Code: the project MCP server starts through `bin/app-mcp` from `.mcp.json`, inside the container of the checkout it runs from (main or worktree). With that stack stopped it exits 1 with a message; reconnect MCP after `make start`.
- Codex: `.mcp.json` does not reach Codex, and `~/.codex/config.toml` has no project server yet — a known follow-up, not a bug to chase in a session.
```
