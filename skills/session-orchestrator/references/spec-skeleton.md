# Spec skeleton

The spec is the contract every implementer session plans against. Put it where the project profile keeps specs (a notes vault, `docs/specs/`, an issue). Use frontmatter if the notes system has it (`title`, `date`, `tags`, `status`). Write it in the language the sessions are prompted in; when the notes app soft-wraps, keep every paragraph, bullet and table row on one line.

## Sections, in order

1. **Вводная (context).** One paragraph: where the input came from (the owner's words, a QA report, recon) and the process sentence — «каждая сессия пишет план по своему блоку, координирующая сессия валидирует; реализация — только после GO владельца».

2. **Порядок выката (rollout order).** A numbered list from plan review to production. Name the steps the coordinator owns (deploys, imports, environment changes) and what gates each step (the owner's GO, CI, QA). This is what keeps sessions from "helpfully" running shared-environment operations.

3. **Данные (data)** — only when the change ships data. Exact paths, row counts, formats, provenance. Sessions must never re-derive data the coordinator already prepared.

4. **Блоки A…Z** — one per work area, each with three layers:
   - *Факты* — code-verified reality with `file:line` references: recon results, not beliefs.
   - *Сделать* — the change at decision level, not implementation level. Where the spec has no opinion, say so («решит план сессии»).
   - *Приёмка* — observable acceptance criteria a reviewer can check.

   Recon produces more than the facts: the trap list and, per zone, the tests that would stay green after a bad rewrite. Give them a companion note beside the spec and have the spec name it as **required** reading. "Recon also found those tests" without a pointer is a promise the sessions cannot keep.

5. **Решения (decisions).** Closed decisions with the owner's date; decisions delegated to a named session, each with the recommendation expected and a fallback rule («если ответа нет — не менять и вернуть вопрос владельцу»). Launch only at zero open decisions, and say so explicitly: «Открытых решений не осталось».

6. **Параллелизация (parallelization).**
   - One line per session: name, slug, blocks owned, scope notes (who merges first, who waits for whose merge, whether the zone needs a stack).
   - **Карта пересечений** — files shared between sessions, with regions and the resolution (merge order, append-only edits, "don't touch X").
   - **Порядок мержа** as an explicit chain.
   - The reminder that spec and session labels never leak into code, commits, branches or PRs.

7. **Промпт для параллельных сессий.** The session prompt from `session-prompt.md`, filled from the profile, in a fenced block with the per-session placeholders left in. Keeping it in the spec makes the instructions reviewable and reproducible.

8. **Связанные (related).** Links to previous specs and reviews, the companion recon note, source notes, data folders.

## Placement and numbering

- When the profile's notes folder numbers its notes, check the next free number right before writing: parallel sessions create notes too.
- The plan review is a separate note, never an edit of the spec. Corrections the review accepts are recorded in the review and referenced from the spec's decisions.

> Illustration (a past project): specs and reviews shared one number sequence in a delivery-plan folder of a git-backed notes repository, with a daily-branch rule for commits.
