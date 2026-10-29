# Session prompt template

The prompt every implementer session starts from. Fill the project placeholders once from the profile, embed the result in the spec («Промпт для параллельных сессий»), then instantiate it per session and pass the final text as the `spawn_task` chip prompt, with the chip titled by the session's zone.

| Placeholder | Where it comes from | Example |
|---|---|---|
| `{SPEC_PATH}` | absolute path of the spec | `/…/Notes/myapp/Parallel sessions (spec 2026-09-11).md` |
| `{SESSION_NAME}` | the session's name in «Параллелизация» | `K2 «deps-ci»` |
| `{SLUG}` | the session's slug | `deps-ci` |
| `{MAIN_CHECKOUT}` | absolute path of the main checkout | `~/src/myapp` |
| `{PROFILE_PATH}` | the profile, relative to the main checkout | `.claude/multi-session.md` |
| `{WT_CMD}` | profile → Worktrees | `wt new deps-ci` |
| `{GATE_CMD}` | profile → Quality gate | `make ready` |
| `{STACK_POLICY}` | profile → Stacks and data | `стек только на время гейта или проверки в браузере, после — make stop; одновременно не больше 4 стеков myapp-wt-*` |
| `{DECISIONS_DATE}` | spec → Решения | `2026-09-11` |

```text
Прочитай спеку "{SPEC_PATH}" целиком и профиль проекта "{MAIN_CHECKOUT}/{PROFILE_PATH}". Твой объём — {SESSION_NAME}. Разделы «Порядок выката», «Решения» и «Параллелизация» обязательны к учёту: решения, закрытые владельцем {DECISIONS_DATE}, не пересматривай, скоуп не расширяй; по решениям, делегированным твоей зоне, предложи вариант с рекомендацией и альтернативой.

Используя скилл /agent-skills:planning-and-task-breakdown, напиши план реализации своей зоны: маленькие проверяемые задачи с критериями приёмки и порядком; какие файлы трогаешь (в спеке есть пути — опирайся на них и перепроверь по коду); какие маршруты, команды и миграции появятся; риски; «Decisions I made»; что явно НЕ входит; нужен ли тебе локальный стек или хватит тестов.

Перед планированием собери контекст: прочитай упомянутые в блоке файлы кода в главном чекауте {MAIN_CHECKOUT} (только чтение) и правила агентов проекта (CLAUDE.md или AGENTS.md).

Жёсткие правила workspace (скилл worktree-sessions):
- Главный чекаут {MAIN_CHECKOUT} и его стек не редактировать, не останавливать, не пересоздавать. Кодим только в своём worktree: `{WT_CMD}` (слаг = {SLUG}).
- Гейт перед PR — `{GATE_CMD}` из своего worktree. Стеки: {STACK_POLICY}. Первый заход в общие ресурсы (стек, база, миграции) — только в свой слот из GO.
- Не выходи за файлы своей зоны — карта пересечений в «Параллелизации»; общие файлы меняй только добавлением. Новые зависимости — только с решения координатора.
- Конвенции и запреты — из профиля: стиль коммитов и автор, язык пользовательских строк, комментарии, тесты, что сессиям запрещено. Метки блоков и сессий из спеки не попадают в код, коммиты, ветки и PR.
- PR открываешь сам, не самомержишь; в описании PR — что решил сам и что нужно координатору после мержа (команды, переменные окружения, миграции).

Выведи план и остановись. Реализацию не начинай до явного подтверждения плана владельцем.
```

## Per-session extras

Append a line only where one session genuinely needs something the others must not spend budget on:

- a design-facing zone gets its design source (file, page, frames) and the verdicts the owner delegated to it, with the fallback rule;
- a zone driven by an external report (QA run, audit) gets the report's location and the instruction to re-verify every finding against the fresh default branch before planning it;
- a zone that depends on another session's merge gets that dependency spelled out, so the plan orders its tasks around it;
- a project rule that lives nowhere else yet (a factory-only rule for test users, a branch with a parked scaffold to read via `git show <branch>:<path>`) — and then move it into the profile.

## Follow-up message protocol

Messages sent later with `mcp__ccd_session_mgmt__send_message` arrive as **user turns** in a session that was told to wait for the owner. Every message states its own authority:

- Plan review: «Ревью плана от координирующей сессии (это НЕ go — старт реализации по-прежнему только после явного подтверждения владельца).»
- Scope change or question: the same label, then the change («это НЕ go; изменение объёма: …»).
- The approval is **sent by the owner, not the coordinator**. The coordinator drafts it; the owner pastes it into that session's own window. It starts with «GO — владелец подтвердил план, начинай реализацию.» and restates the merge-order position, the endorsed judgment calls, the PR-description handoffs, the stack decision («стек не нужен — хватит тестов» or «нужен браузер — стек только на время проверки»), the first-touch slot («первый заход: N-й, после сессии X») and «не самомержить».
- The owner pastes the GOs one at a time, in slot order, a few minutes apart.

> Illustration (a past project): the default there was no local stack at all — a worktree checkout plus a remote gate per worktree — and a browser check earned a lighter stack without consumers. A profile can set such a default the same way.
