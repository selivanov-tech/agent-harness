# Plan validation checklist

How the coordinator reviews implementer plans. The review catches two failure classes before code is written: plans built on wrong facts, and plans that are correct one by one but collide in integration. Both cost minutes at plan time and rebases afterwards.

## 1. Pull the plans

- `mcp__ccd_session_mgmt__list_sessions` → find the zone sessions by title.
- `list_events` per session. The tail is usually a wiki-capture Stop-hook exchange; the plan is the long assistant message before it. Page back with `before_uuid`; the plan can sit hundreds of events back, so use a large page size.
- A session that is still running has not finished its plan — skip it and say so; never guess its content.

## 2. Verify load-bearing claims yourself (read-only)

A claim is load-bearing when the plan's shape depends on it: "X already works", "Y is dead code", "the spec is wrong about Z", "this test forbids that change". For each one:

- Read the main checkout. When the plan says the local default branch lags, check `git rev-list --count <default>..origin/<default>` and read files with `git show origin/<default>:<path>`.
- Prove the ref before trusting it: `git rev-parse origin/<default>` must equal `git ls-remote origin refs/heads/<default>`. A remote-tracking ref is only as fresh as the last fetch, and a local branch literally named `origin/<default>` shadows it (`wt doctor` finds those). `ls-remote` changes no state; when the two differ, fetch first.
- Confirm routes by the code that serves them, not by a response's shape; "dead code" by searching for callers; validation claims by reading the actual rule.
- Cross-check against the coordinator's memory and the project notes. Independent recon that agrees is strong confirmation; disagreement means someone's fact is stale — find out whose.

Plans that **correct the spec** are the system working: the session read the code more closely than the spec's recon. Confirm the correction, credit it in the review, and treat the spec as amended.

## 3. Per-plan checks

- **Coverage:** every «Сделать» and «Приёмка» line of the zone maps to a task, and everything else is explicitly out of scope. Silence about a spec line is the bug.
- **Judgment calls:** plans list their own decisions («Decisions I made», formats, error codes, defaults). Endorse or override each one explicitly.
- **Scope discipline:** flag additions beyond the spec, even good ones, and either endorse them or move them to the backlog. Watch for silent scope shrink too: spot-check every "already fixed on the default branch".
- **Worktree and gate hygiene (against the profile):** own worktree with the agreed slug, the profile's gate before the PR, no self-merge, no shared-environment actions. A plan that starts a stack immediately should say why the zone needs one.
- **Ordered artifacts:** migrations, schema versions, generated clients — whoever adds one to a shared sequence must wait for the earlier session's merge; check the plan scheduled it.
- **Label leaks:** spec labels in proposed branch, commit or PR names.

## 4. Cross-plan checks (where parallel work actually breaks)

- **Shared files:** build the real overlap map from the plans; the spec's map was a hypothesis. Same file and different regions is fine with a fixed merge order; the same region needs an owner.
- **Crossing contracts:** when session A ships something session B consumes or widens (an endpoint, a type, a flag, a compose service), the merge order must land the widener second, and B's plan must name A's file.
- **Shared infrastructure files:** compose files, Makefiles, CI workflows and agent-rule sources are touched by many zones; give each such file one owner per round, or an append-only rule.
- **Fix the merge order** as an explicit chain in the review; every GO repeats the session's own position.

## 5. Record and respond

- Write the review note where the profile keeps reviews: per-session verdict (approved / rework), what was re-verified in code, endorsed and overridden calls, the fixed merge order, open questions to the owner.
- Send feedback with `send_message`, labelled «это НЕ go» (protocol in `session-prompt.md`). Only sessions with remarks need a message before the GO; the rest get everything in their GO.
- Report the verdicts to the user with owner-facing questions separated out: the user relays decisions, the owner sends the GO.

## 6. After the GO

- Track completion notifications; review code the same way: verify, don't trust, and look at the cross-plan seams first (shared files, widened contracts, rebase results).
- Keep the review note and the coordinator's memory current per state change (approved → GO → implemented → merged), so a future coordinator can resume from the notes alone.
- **Before handing the coordinator role over, name what does not travel.** The notes do; the coordinator's context does not. Typical misses: unpublished work on a notes branch that the next coordinator must continue rather than restart; a main checkout parked on another branch, so files must be read from `origin/<default>`; prompts and plans kept only in a session scratchpad. Say plainly what must not be done by the successor on its own: merge, publish, send a GO.
