# Changelog

All notable changes to flash-term are tracked here.


## [v2026.08.13] - 2026-08-13 -- flash-term = WezTerm config; AI delegated to su-code

### Changed
- **Renamed the flash-term command `8sync` -> `ft`.** The `8sync` name now belongs to the
  [su-code](https://github.com/8-Sync-Dev/su-code) AI harness binary, which `ft setup` installs
  (`irm https://8-sync-dev.github.io/su-code/install.ps1 | iex`). flash-term no longer aliases or
  shadows `8sync`. All terminal/theme/bg/dev/gguf commands are now `ft <verb>` (`ft bg set`,
  `ft dev all`, `ft setup`); AI work is `8sync .` / `8sync ai` (su-code).
- **Removed the omp AI harness from flash-term** -- sessions (`8sync .`), `ai`, `harness`, `skill`,
  `find`/`note`/`run`/`ship`, `doctor`, the skill registry, `.omp/commands/`, and `agents/`. Deleted
  `modules/harness.ps1`, `modules/skill.ps1`, `modules/agents/00-shared.ps1`, `agents/`, `.omp/`.
  flash-term is now purely a WezTerm config + terminal toolkit. `ft up` dropped the `omp`/`skills` targets.
- **`ft setup` step [5/5] now installs su-code** (instead of deploying the omp harness).
- **`ft setup [5/5]` now prints the full AI onboarding sequence** after installing su-code:
  `8sync setup` (once: omp + gh + MCP servers + models) -> `8sync harness` (per-project: 50 skills +
  `/sx-*` commands) -> `8sync .`. Previously it only hinted `8sync .`, leaving the global + per-project
  skill layers unconfigured -- a fresh `ft setup` then `8sync .` started a skill-poor session.
- **`ft bg set <id|path|url>` persists the image into the repo** as `assets/default-bg.<ext>` (the
  committed default wallpaper) and points `current-bg.lua` at it; `wezterm.lua` falls back to
  `assets/default-bg.jpg` then `.png`. The old shipped `default-bg.png` was replaced by the
  user-chosen `default-bg.jpg`.

### Internal
- Dispatcher remains the `Invoke-8Sync` function (internal name unchanged), now aliased as `ft`;
  completer registered for `ft`; user-facing text rewritten `8sync` -> `ft` across all terminal modules.

## [v2026.08.12] - 2026-08-12 -- dev runtimes bootstrap (no Visual Studio)

### Added
- **`ft dev` -- install development runtimes with NO Visual Studio C++ Build Tools.**
  A single command (and the `ft setup` one-liner bootstrap) now provisions the full
  local dev stack via Scoop:
  - `ft dev node` -- Node.js + npm + pnpm (corepack, with `npm i -g pnpm` fallback).
  - `ft dev python` -- `uv` + a managed standalone CPython (`uv python install`);
    prebuilt, so no VS build tools.
  - `ft dev go` -- Go (self-contained toolchain).
  - `ft dev rust` -- Rust on the **GNU/MinGW host triple** (`gcc` + `rustup … windows-gnu`),
    sidestepping MSVC / `link.exe` entirely.
  - `ft dev chromium` -- Chromium (extras bucket) for browser automation / debugging.
  - `ft dev docker` -- Docker Desktop via `winget` (needs admin + WSL2 + first GUI launch;
    not a Scoop package).
  - `ft dev encore` -- Encore.dev CLI via `iwr https://encore.dev/install.ps1 | iex` into
    `~/.encore/bin` (non-Scoop installer).
  - `ft dev all` installs every runtime/app; `ft dev` shows status; `ft dev --check`
    is a dry run. Non-Scoop installs (encore, docker) use a new `Custom` scriptblock path.
  - `ft setup` runs `Invoke-DevInstall` as step `[4/5]`, so the `irm | iex` one-liner pulls
    the whole stack down in one pass (`--no-dev` skips it). `~/.cargo/bin` + `~/.encore/bin`
    are on the preferred PATH so `cargo`/`rustc`/`encore` resolve in every tab.
  - Added `jq`, `yq`, `make` to the managed CLI tool set (`ft sync` / `ft setup`).

## [v2026.08.11] - 2026-08-11 -- omp slash commands (/sx-*)

### Added
- **omp native slash commands** now ship with the config and auto-deploy, so a one-liner
  `irm | iex` install (or `8sync setup` / `8sync harness`) makes them appear in every
  omp session -- closing the gap where the omp app showed no custom commands:
  - `/sx-init` -- onboard to a project (stack, layout, commands, conventions).
  - `/sx-plan` -- plan a task before coding (investigate + propose, no implementation).
  - `/sx-review` -- review code/diff for correctness, bugs, edge cases.
  - `/sx-commit` -- stage + write a Conventional Commit from the current diff.
  - `/sx-fix` -- reproduce -> root-cause -> fix at source -> verify.
  - Source: `.omp/commands/*.md` (committed). Deployed to `~/.omp/agent/commands` by
    `Deploy-OmpCommands` (harness.ps1), wired into `8sync harness init|up|global` and
    `8sync setup` (so `install.ps1` provisions them). Readiness counts them
    (`8sync harness status`, `8sync doctor`).

## [v2026.08.11] - 2026-08-11 — full omp session management

### Added
- **Full per-project omp session management under `8sync .`** — port of the `su-code`
  `here.rs` / `session.rs` model, closing the gap vs. the su-code harness:
  - `8sync . new <name> [--worktree]` — create a FRESH named session (`--worktree` =
    isolated git worktree + branch `8sync/<name>`). Previously `8sync . new` wrongly
    treated `new` as a session *name*.
  - `8sync . <name>` — create-or-resume a named, isolated omp session.
  - `8sync .` — resume the latest session (registry-tracked `last_used`, else omp default).
  - `8sync . ls` (aliases: `--list`, `--ls`, `list`, `--json`) — list this repo's sessions
    (★ latest, branch, dirty, omp auto-title).
  - `8sync . ls --all` (or `8sync . --all`) — list EVERY session across all repos.
  - `8sync . rm <name> [--force]` — remove a session (`--force` also deletes the transcript).
  - `8sync . mv <old> <new>` — rename a session (registry + dir + worktree/branch).
  - `8sync . merge <a> [b...]` — land session branches into the current branch
    (`git merge-tree` preflight → rebase-to-unblock → merge → cleanup).
  - Registry at `~/.8sync/sessions/<repo-slug>/index.json`; omp pinned via `--cwd`;
    model flags (`--model`/`--smol`/`--slow`/`--plan`/`--thinking`) pass through.

### Fixed
- `8sync . new <name>` no longer creates a session literally named "new" —
  `new`/`ls`/`rm`/`mv`/`merge` are now reserved verbs.
- `8sync . --ls` and `8sync . --all` no longer fall through to `omp --continue`
  (which errored `unknown flag: --list`/`--ls`/`--all`).
- Empty-repo `ls` now reports sessions that exist in other repos and points to `--all`.
- Session-name path-traversal guard: reject `.`/`..`.

### Changed
- `Invoke-OmpSession` (harness.ps1) rewritten as a verb dispatcher; full session layer
  ported from `su-code` `session.rs`.
- `Show-8SyncHint` (core.ps1) + `Register-8SyncCompleter` (shell.ps1): `.` mode added to
  `$modes`; `new`/`ls`/`rm`/`mv`/`merge`/`--worktree`/`--force`/`--list`/`--ls`/`--all`/`--json`
  tab-completions.
- Docs (`CLAUDE.md`, `docs/ARCHITECTURE.md`) updated for the session surface.

## [v2026.08.10] - 2026-08-10 — omp harness release

### Added
- **omp AI harness** (port of the `su-code` model to Windows/PowerShell):
  - `8sync .` / `8sync . <name>` — resume or create an isolated omp session in the current repo.
  - `8sync ai "<prompt>"` — omp one-shot or interactive (`-p` for stdout).
  - `8sync harness [init|up|global|status]` — deploy skills to `~/.omp/skills`, seed project memory
    (`8sync/PROJECT.md`, `STATE.md`, `KNOWLEDGE.md`), manage `.gitignore`, and report readiness
    (omp / skills / codegraph / MCP / gitleaks).
- **`8sync skill [list|add|update|remove|deploy]`** — manage the omp skill registry (`agents/registry.json`);
  skills are cloned and deployed to `~/.omp/skills` where omp auto-discovers them.
- **`8sync up` (update-all)** — update the config repo (git ff-only), Scoop tools, omp, installed skills,
  and report the WezTerm version. Supports `--check` (dry-run) and selective targets
  (`self|scoop|omp|skills|wezterm`).
- WezTerm keybindings: AI leader shortcuts (`Leader .`/`o`/`h`/`k`/`u`/`b`), `Alt+1..9` tab jumps,
  `Ctrl+Tab` / `Ctrl+Shift+Tab` tab cycling, `Leader r` reload.

### Removed (lean pivot — single omp engine)
- `8sync forge` (ForgeCode), `8sync jcode`, `8sync opencode`, `8sync gsd`, `8sync gsd-1`,
  `8sync remove`, and `8sync agents` (folded into `8sync skill` + `8sync harness`).
- Modules: `modules/forge.ps1`, `modules/jcode.ps1`, `modules/opencode.ps1`, `modules/gsd.ps1`,
  `modules/gsd/`, `modules/gsd1.ps1`, `modules/agents/50-command.ps1`, `modules/agents/55-max-skill.ps1`.
- Repo cruft: `.gsd/`, `.planning/`, `.claude/`, `.mcp.json`, `gsd-config/`, `oc-bundle/`,
  `stable-patches/`, `remove-gsd2-deep.ps1`, dated plan/issue/guide docs.
- `.gitignore`: dropped obsolete GSD/Forge entries.

### Changed
- `wezterm-bootstrap.ps1` dot-sources the lean module set + `agents/00-shared.ps1` (skill clone backend).
- `agents/00-shared.ps1` rewired to deploy skills to `~/.omp/skills` (was `.forge`/`.gsd`/`.claude`).
- `Show-8SyncHint`, `Invoke-8Sync` dispatcher, and `Register-8SyncCompleter` reflect the new command surface.
- Docs (`CLAUDE.md`, `AGENTS.md`, `README.md`) rewritten to match the real structure.

## [v2026.04.20-anthropic-restore] - 2026-04-20
### Added
- `8sync gsd local` command suite: project-scoped gsd-pi runtime vendoring
  (init, baseline, add-submodule, use, install, build, apply-anthropic-patch, fix, enter/leave, status, setup).
- Anthropic OAuth restoration patches under `modules/gsd/patches/`.

### Fixed
- Anthropic OAuth login restored for gsd-pi >= 2.70.0 (upstream removed the OAuth module).
- OAuth `#145` system prompt fix applied at source level (`.ts`).
- Provider label `anthropic-api` -> `anthropic` normalized.

### Notes
- Verified on Windows 10 with Node 22.14.0.

## [v2026.04.10-stable-1] - 2026-04-10
### Added
- `stable-patches/` stable recovery profiles (OpenCode, GSD Anthropic OAuth).
- `8sync gsd fix` to force-apply the runtime patch; `--stable` support.

### Fixed
- OpenCode Claude OAuth recovery path (issue `#145`).
- GSD Anthropic OAuth runtime system-prompt normalization.
