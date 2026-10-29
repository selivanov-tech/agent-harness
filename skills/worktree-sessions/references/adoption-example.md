# Adopting `wt` in a repository

`wt` needs no setup: in any git repository `wt new <slug>` creates `<parent>/.wt-<repo>-<slug>` from the local default branch and `wt rm <slug>` removes it. This page covers the optional parts — `.wt.conf`, hooks, a Docker stack per worktree and the project profile — in the order a new project needs them. Budget: under 30 minutes.

## 1. List what a fresh worktree lacks

`git worktree add` brings only tracked files. Whatever a session needs on day one that git does not carry has to come from `.wt.conf`:

| What is missing | Typical items | Where it goes |
|---|---|---|
| Dependency directories installed from a lock file | `vendor`, host-built `node_modules` | `clone=` (copy-on-write) |
| Local config and secrets | `.env`, `.env.local`, `config/jwt` | `copy=` (never overwritten) |
| Generated agent rules that git ignores | `CLAUDE.md`, `AGENTS.md` compiled by a generator such as Laravel Boost | `copy=` |
| Anything computed per worktree | reinstall when the lock file differs, code generation | `materialize=` hook |
| Per-worktree runtime | a compose stack with its database and volumes | `stack_prefix=`, `teardown=` hook |

Traps that cost real time:

- **Generated rule files.** When `CLAUDE.md` and `AGENTS.md` are compiled from sources and git-ignored, a new worktree has no project rules at all, and regenerating them may need a running stack. List them in `copy=`; regenerate inside the worktree later if the branch changes their sources.
- **Stale clones.** A cloned `vendor` matches the main checkout's lock file, not the branch's. The materialize hook should compare the lock file with the installed state and reinstall when they differ.
- **Host versus container binaries.** Clone `node_modules` only when the host runs it. A container needs linux binaries: install them inside the container, into a named volume of the worktree's stack.
- **Files your hooks create.** They must be git-ignored, otherwise `wt rm` sees untracked changes and refuses.

## 2. Write `.wt.conf`

Commit it at the repository root. One `KEY=VALUE` per line, `#` comments, no shell expansion; paths are relative to the repository.

```text
clone=vendor
copy=.env CLAUDE.md AGENTS.md
materialize=make wt-materialize
teardown=make wt-teardown
stack_prefix=myapp-wt-
stack_budget=4
idle_days=7
# worktree_dir=../.worktrees   (default: next to the main checkout)
```

- Hooks run through `bash -c` with `WT_SLUG`, `WT_DIR`, `WT_ROOT` (the main checkout), `WT_BRANCH` and `WT_DROP_DATA` (`1` with `wt rm --drop-data`). `wt` prints each hook command before running it.
- `materialize` runs in the new worktree after clone and copy. A failure exits 5 and keeps the worktree; running the same `wt new <slug>` again retries.
- `teardown` runs in the worktree before it is removed, so it uses the compose file and Makefile of the branch that started the stack. When the directory is already gone, `wt rm` refuses: `--force` runs the hook from the main checkout, `--no-hooks` only unregisters the worktree. Either way the hook must take the slug from `WT_SLUG`, never from the directory it runs in — in the main checkout that would name the main stack.
- `clone`, `copy`, `materialize` and `teardown` come from the worktree's own `.wt.conf` when it has one, so a branch that introduces or changes them works before it is merged. The same rule means a branch decides which commands `wt new` and `wt rm` run with your rights; `wt` prints a note when the branch's file differs from the main checkout's. `stack_prefix`, `stack_budget`, `idle_days` and `worktree_dir` always come from the main checkout.
- `stack_budget` counts only `<stack_prefix>*` projects; the main checkout's stack must use another name. Lower the number when the Docker VM shrinks.

## 3. A Docker stack per worktree

Skip this section when sessions need no local services. The pattern was verified with Docker Compose v5.1.4 on 2026-09-11. It keeps the main checkout's stack exactly as it was, because every value falls back to today's default when there is no slug.

The compose file takes names, ports and the app URL from the environment:

```yaml
services:
  app:
    image: ${APP_IMAGE:-myapp-dev}
    container_name: ${STACK:-myapp}-app
    ports: ["${HTTP_BIND:-80}:80"]
    environment: [APP_URL]   # passed only when set: the main checkout keeps its .env value
  postgres:
    image: postgres:17
    container_name: ${STACK:-myapp}-postgres
    ports: ["${PG_BIND:-5432}:5432"]
    volumes: [pg-data:/var/lib/postgresql/data]
volumes:
  pg-data:
```

In the Makefile one variable decides which stack every target talks to:

```make
WT_SLUG ?= $(shell git config --worktree --get wt.slug 2>/dev/null)
LINKED  := $(shell [ "$$(git rev-parse --git-dir)" = "$$(git rev-parse --git-common-dir)" ] || echo 1)
ifeq ($(WT_SLUG),)
  ifneq ($(LINKED),)
    $(error linked worktree has no wt.slug: run wt adopt "$(CURDIR)" <slug>)
  endif
  PROJECT := myapp-dev
else
  PROJECT   := myapp-wt-$(WT_SLUG)
  HTTP_PORT := $(shell echo $$((8100 + $$(printf '%s' '$(WT_SLUG)' | cksum | cut -d' ' -f1) % 400)))
  export STACK := $(PROJECT)
  export HTTP_BIND := 127.0.0.1:$(HTTP_PORT)
  export PG_BIND := 127.0.0.1:
  export APP_URL := http://127.0.0.1:$(HTTP_PORT)
endif
DOCKER_COMPOSE := docker compose -p $(PROJECT) -f docker-compose.yml

wt-teardown:
	@test -n "$(WT_SLUG)" || { echo "wt-teardown: no slug, refusing to touch $(PROJECT)"; exit 1; }
	$(DOCKER_COMPOSE) down -v --remove-orphans
```

Why each piece is there:

- `WT_SLUG ?=` lets the value that `wt` exports to hooks win over the directory's own config. A teardown hook that runs in the main checkout (the worktree directory is gone) still targets `myapp-wt-<slug>`, and the guard in `wt-teardown` refuses to run without a slug instead of stopping the main stack.

- `-p <project>` (or `COMPOSE_PROJECT_NAME`) wins over a top-level `name:` in the compose file. Without it every worktree resolves to the main project, and `down` from a worktree stops the main stack.
- Volumes get the project prefix automatically (`myapp-wt-<slug>_pg-data`), so each worktree has its own database, and `docker compose -p <project> down -v` in the teardown hook deletes exactly those volumes.
- `PG_BIND=127.0.0.1:` expands to `127.0.0.1::5432`, an ephemeral loopback port; `docker compose port postgres 5432` prints it. Worktree ports never bind to all interfaces.
- The HTTP port comes from the slug, so the URL is known before the stack starts. A collision fails loudly on `up`; an override variable fixes it.
- Before `up`, count the `docker compose ls -q` names with the prefix and refuse above the budget.
- When the image is built locally, tag worktree images with a hash of the Dockerfile and the files it copies: parallel worktrees share one build and never retag the main checkout's image.
- Later, one shared Traefik on `127.0.0.1:80` can route `http://<slug>.<project>.localhost` by labels instead of ports. Browsers resolve `*.localhost` without `/etc/hosts`. Inside containers use compose service names: there `localhost` is the container itself.

## 4. Write the profile

Machine settings live in `.wt.conf`; everything a session has to know in words lives in the profile: `.ai/guidelines/multi-session.md` when the project compiles its agent rules from `.ai/guidelines` (Laravel Boost), otherwise `.claude/multi-session.md`, committed. Start from `references/project-profile-template.md` in the `session-orchestrator` skill. Say explicitly which agent clients get which MCP servers: `.mcp.json` reaches Claude Code only, Codex reads `~/.codex/config.toml`.

## 5. Try it on a scratch repository

```bash
cd "$(mktemp -d)" && git init -q -b main demo && cd demo
printf 'vendor/\n.env\n.materialized\n.teardown.log\n' > .gitignore
mkdir -p vendor/lib && echo dep > vendor/lib/dep.txt && echo 'APP_KEY=local' > .env
cat > .wt.conf <<'EOF'
clone=vendor
copy=.env
materialize=echo "materialized $WT_SLUG" > .materialized
teardown=echo "teardown $WT_SLUG drop=$WT_DROP_DATA" >> "$WT_ROOT/.teardown.log"
EOF
git add .gitignore .wt.conf && git commit -qm "chore: add .wt.conf"
wt new try-it
wt ls
wt rm try-it --drop-data
cat .teardown.log
```

Expected output, paths shortened:

```text
wt: created worktree 'try-it' at …/.wt-demo-try-it on the new branch 'try-it' from main (5faaa9dfae93)
wt: cloned vendor (copy-on-write)
wt: copied .env
wt: running materialize hook in …/.wt-demo-try-it: echo "materialized $WT_SLUG" > .materialized
…/.wt-demo-try-it
SLUG    BRANCH  AHEAD/BEHIND  DIRTY    PR  STACK    PATH
try-it  try-it  +0/-0         no       ?   -        …/.wt-demo-try-it
wt: running teardown hook in …/.wt-demo-try-it: echo "teardown $WT_SLUG drop=$WT_DROP_DATA" >> "$WT_ROOT/.teardown.log"
wt: deleted local branch 'try-it' (was 5faaa9dfae93; restore with: git branch try-it 5faaa9dfae93)
wt: removed worktree 'try-it' (…/.wt-demo-try-it)
teardown try-it drop=1
```

`PR ?` means `gh` could not tell (there is no GitHub remote here). `plain copy` instead of `copy-on-write` means the filesystem, or a worktree on another volume, cannot clone: the result is the same, only slower.

## 6. Checklist

- [ ] `wt new try-it && wt rm try-it` leaves `git worktree list` and `git branch` unchanged.
- [ ] `.wt.conf` clones and copies everything a session needs on day one, including git-ignored agent rules.
- [ ] Hooks are safe to run twice, and the files they create are git-ignored.
- [ ] From a worktree, the gate and `make start` / `make stop` reach the worktree's own stack; from the main checkout nothing changed.
- [ ] `wt rm <slug>` leaves no containers or volumes of the slug (`docker ps -a`, `docker volume ls`).
- [ ] The profile names the gate, the stack budget, the PR rules, the prohibitions and which MCP servers each agent client gets.
- [ ] `wt doctor` is clean.
