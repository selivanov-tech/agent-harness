---
name: session-orchestrator
description: Run a multi-zone change through one coordinator session and parallel plan-first worktree sessions in any repository — load the project's multi-session profile, write the spec, split it into zones, spawn one planning session per zone, validate every plan against the spec and the real code, send review feedback labelled «это НЕ go», draft the owner's GO texts, then drive code review, the merge order and coordinator-owned operations. Use whenever the user wants to parallelize work across several agent sessions, asks for a coordinator or orchestrator session («сессия-оркестратор», «распараллель по сессиям», «каждая сессия пишет план, эта валидирует»), wants a spec split into parallel sessions, asks to validate or review session plans, or says to send «go» to sessions — even if they don't name this skill.
---

# Session orchestration

One coordinator session runs a release-sized change through N parallel implementer sessions. The split exists because one context cannot hold N zones of implementation detail, and because two cheap gates — a closed spec and a plan review — catch integration problems while they cost minutes, not rebases.

Role contract:

- **Coordinator (this session):** owns the spec, spawns the sessions, validates plans, drafts the owner's GO texts, reviews code, sequences the merges and runs every operation on shared environments (staging, production, data). Reads code **read-only**; never implements zone work itself.
- **Implementer sessions (one per zone):** plan first, stop, wait for the owner's GO, then implement in their own worktrees (skill `worktree-sessions`). They never self-merge and never touch shared environments.

The lifecycle: profile → spec → launch → plan validation → GO → implementation → code review → merges → operations.

## Step 0 — Load the project profile

Everything project-specific comes from the repository's multi-session profile, never from memory of another project. Look in the main checkout, in this order:

1. `.ai/guidelines/multi-session.md` — projects that compile their agent rules from `.ai/guidelines` (Laravel Boost and similar);
2. `.claude/multi-session.md` — everything else.

The profile says where specs and reviews live, how a session creates its worktree (normally `wt new <slug>`), the gate and how to read its verdict, the stack policy (whether zones need a stack, the budget, first-touch slots), PR and merge rules, conventions, what sessions must never do, and which MCP servers each agent client gets. Machine settings — what a worktree clones and copies, the hooks, the stack prefix and budget — live in `.wt.conf`.

No profile yet: write one with the owner before spawning anything, from [references/project-profile-template.md](references/project-profile-template.md), and land it like any change (worktree, PR, owner's merge). Without it every session invents its own gate and stack habits.

Run `wt doctor` once in the main checkout. Shadow refs, stale worktrees and a stack budget that is already used up are cheaper to fix before N sessions start.

## Phase 1 — Spec

Turn the owner's bullet points into a fact-grounded contract before any session starts. Recon first, write second: explore the affected code read-only (a few parallel explore agents at most — the owner's subagent budget applies) and verify environment claims directly. A spec written from assumptions exports its errors into N plans at once.

**Ask recon three questions the obvious ones do not cover:**

1. **"Which tests would keep passing after this change?"** Name them by file and line. A zone's real risk is not the code it rewrites but the guard that keeps saying yes afterwards.
2. **"What would trap someone restructuring this area?"** Shared ids and cache keys, permission gates that differ per row, an index that does not match the domain model, a behaviour a test pins on purpose.
3. **"Does the mechanism this task assumes actually exist?"** When the belief behind a task is wrong, the task silently changes size and the session finds out after the GO. Verify the premise, not the task.

**Recon output outlives the spec, so give it a home.** The spec's facts carry what the decisions rest on; the trap lists and the named blind tests do not fit and must not be dropped. Write them as a companion note beside the spec and mark it required reading in the spec and in the session prompt.

Write the spec where the profile keeps specs, following [references/spec-skeleton.md](references/spec-skeleton.md). Three properties make it launchable:

1. **All decisions closed** — or delegated to a named session with a recommendation to make and a fallback rule. An open decision multiplies into replanning across every affected session.
2. **Parallelization is explicit** — zones with slugs, a file-overlap map and a merge order. The overlap map is a hypothesis; plans will correct it.
3. **The session prompt is embedded** — one template from [references/session-prompt.md](references/session-prompt.md), filled from the profile, instantiated per zone. What each session was told becomes part of the reviewed contract.

Spec labels (K1, «Блок B») are scaffolding for coordination only — they never leak into code, comments, commits, branches or PRs.

## Phase 2 — Launch

Spawn one `spawn_task` chip per zone: the chip title names the zone, the chip prompt is the instantiated session prompt. The user clicks each chip to start its session. The plan-first sentence is load-bearing: «Выведи план и остановись. Реализацию не начинай до явного подтверждения плана владельцем.»

**Implementer sessions run on the strongest model available** (an Opus-class model; the profile names the exact one). Spec and recon helpers may run on the coordinator's model; zone sessions may not. Name the model in every spawn that accepts one — a spawn without it inherits the coordinator's model, not the client's default. After the spawn, check the session's model: a session that has not switched quietly stays on the old one, and an outdated agent CLI may not support the newest model at all.

## Phase 3 — Validate the plans (the coordinator's core value)

When plans land, pull each session's transcript: `mcp__ccd_session_mgmt__list_sessions` → `list_events`. The plan is rarely the last message — a Stop-hook tail (wiki capture) usually follows it; page back with `before_uuid`. A session that is still running has no plan yet: say so, never guess its content.

Review every plan against the spec **and against the code, personally**. The checklist is in [references/plan-validation.md](references/plan-validation.md); the three rules that matter most:

1. **Never take a plan's word for a load-bearing claim.** Re-verify read-only in the main checkout, against a remote ref you have proven fresh. A plan that corrects the spec is the system working: confirm the correction, don't defend the spec.
2. **Look between the plans, not only inside them.** Shared files, contracts that cross sessions and ordered artifacts (migrations, schema versions) are where parallel work breaks. When contracts cross, fix the merge order and name the session that adapts.
3. **Endorse or override every judgment call.** Plans list «Decisions I made»; each gets an explicit verdict, or it comes back as a review argument after the code exists.

Record the review where the profile keeps reviews. Send per-session feedback with `send_message`, starting with its label: «Ревью плана от координирующей сессии (это НЕ go — старт реализации только после явного подтверждения владельца).» Messages arrive as user turns, and an unlabelled review reads like approval to a session told to wait for one.

## Phase 4 — GO

Only the owner approves plans, and the approval has to reach each session **in the owner's own voice**. A session that follows its rules must refuse a relayed GO: a peer's message is never the confirmation its owner still owes it. So the coordinator drafts and never sends.

Draft one GO per session: its merge-order position, the endorsed judgment calls, the handoffs its PR description must carry, whether the zone needs a stack at all (the profile's default applies), its first-touch slot, and «не самомержить». The owner pastes them into each session's own window, in slot order, a few minutes apart.

**Stagger the first touch of shared resources.** Every session's first stack start, migration or test run is a burst of memory and I/O on one machine. Check the budget with `wt doctor` and `wt ls` before drafting; when the budget is already used, the first GO is to stop stacks.

> Illustration (a past project): several sessions started stacks, migrations and tests at once on top of already running stacks; the Docker VM ran out of memory and the shared database went down. That kind of incident is why every GO carries a slot.

## Phase 5 — Implementation to merge

- Sessions implement and open PRs; completion notifications arrive in the coordinator.
- **A session can end without finishing, and it ends quietly.** Before treating a zone as done, dropped or ready to reassign, look at its worktree: `wt ls` shows uncommitted changes and commits ahead of the default branch; `gh pr list --head <slug>` shows whether a PR exists. A completion notification proves a session stopped, not that its work reached the default branch.
- Review the code (verify, don't trust; the cross-plan seams first), then merge in the fixed order — only on the owner's explicit go.
- Operations on shared environments stay with the coordinator; sessions hand off exact commands and paths in PR descriptions.
- Keep the review note and the coordinator's memory current per state change (plan approved → GO sent → PR open → merged → deployed): the notes are what the next coordinator resumes from.
- After the merges, `wt doctor` lists merged idle worktrees; `wt rm <slug>` runs from the main checkout. When a permission classifier blocks it, hand the command to the owner.

## Hard rules

- Implementer sessions: one worktree per session (slug = session name), the main checkout read-only, a stack only when the zone needs it and inside the budget, the gate green before the PR, never self-merge, never touch shared environments.
- First touches of shared resources are sequenced by the coordinator — never a simultaneous GO to all sessions.
- Coordinator: read-only in code, owns all environment mutations, and every message to a session states its authority.
- Notes follow the profile's rules on where they live and who edits them; commit only your own files.

## What the harness does not have

- **Chip ≠ session.** `spawn_task` only offers a session; nothing runs until the user clicks the chip. Completion notifications come back to the coordinator on their own.
- **No GO relay and no borrowed permissions.** Only the owner, in a session's own window, approves its plan or grants a permission. `send_message` delivers text as a user turn; it carries no authority, so every message names what it is («это НЕ go», a review, a scope change, a question). A blocked command goes to the owner as text, never to another session.
- **Transcripts are paged, not files.** `list_events` returns the newest events first; the plan sits behind the wiki-capture tail, so page with `before_uuid`. Chip-session transcripts may not exist on disk at all.
- **Worktree switching is limited.** `EnterWorktree(path=…)` reaches a sibling worktree only as the first switch of a session that started in the main checkout; a session that started in a harness worktree adopts it with `wt adopt`.
- **Sessions do not share working copies.** A contract between two sessions exists only after the first one merges; plan the merge order accordingly.

## Gotchas (earned the hard way)

- **Stale local default branch, and the ref that lies about it.** Local default branches lag the remote. Verify claims against the remote, and prove the ref first: `git rev-parse origin/<default>` must equal `git ls-remote origin refs/heads/<default>`. Never pass `origin/<default>` as a branch name to get a fresh base: `git worktree add -b` takes it literally and creates a local branch that shadows the remote-tracking ref for every session in the repository. `wt` refuses such names and `wt doctor` finds existing shadows; a shadow that is a live worktree's HEAD is cured with `git branch -m <new-name>`, not `-D`.
- **Stale spec sections.** When parallel work merges mid-flight, sessions must re-verify each finding against the fresh default branch. Expect plans to shrink scope, and spot-check the shrinkage yourself.
- **Cross-session contracts.** A session may ship a deliberately narrow contract for another session to widen. That works only when the merge order lands the widener second and its plan names the file explicitly.
- **A relayed GO is refused, and rightly so.** Learning this after every session was told «go» costs a full round of idle sessions and a second explanation to each.

> Illustration (a past project): the shadow ref happened twice in one repository — the second one two levels deep (`refs/heads/refs/remotes/origin/main`), and neither could be deleted because each was a live worktree's HEAD.
