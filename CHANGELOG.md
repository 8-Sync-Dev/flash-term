# Changelog

All notable changes to flash-term are tracked here.


## [v2026.08.16] - 2026-08-16 -- omp OAuth gateway + ZCode skill mirror

### Added
- **`ft gateway` command** (`modules/gateway.ps1`): reuse the Claude / Gemini / GLM accounts
  already OAuth'd in omp from any OpenAI-compatible client (ZCode, etc.) without issuing a new
  API key. Starts `omp auth-broker serve` (credential vault, port 9377) plus
  `omp auth-gateway serve` (proxy that injects the live token, port 9378) as hidden background
  processes, then prints the exact provider values to paste into a client form:
  base URL `http://127.0.0.1:9378/v1`, the gateway bearer key, OpenAI-compatible format.
  Subcommands: `start` · `stop` · `restart` · `status` · `key` · `models` · `help`.
  OAuth refresh stays with omp, so the key never has to be rotated by hand.
  - Verified end to end: live completions through `anthropic/claude-haiku-4-5`,
    `google-antigravity/gemini-2.5-flash` and `zai/glm-5.3` (60 models across 3 providers),
    idempotent `start`, `restart` + a post-restart request, and `stop` clearing both ports.
  - Note: reasoning models (`zai/*`) need a larger `max_tokens` — a small budget is consumed by
    `reasoning_content` and returns empty `content`.
- **`ft skills` command** (`modules/skills.ps1`): mirror the omp skill library
  (`~/.omp/skills`, 54 skills) into the ZCode workspace layout
  `<project>/.zcode/skills/<name>/SKILL.md`. `8sync harness init` only vendors
  `su-code/skills/`, which ZCode does not read, so this closes that gap.
  Subcommands: `sync [--force]` (current project) · `all [path] [--force]` (every project that
  has a real `su-code/` memory dir under the scan root) · `list` · `status` · `help`.
  Copies are additive by default so a locally edited skill is never clobbered; `--force`
  re-copies. The scanner requires `su-code/` to hold actual memory
  (`STATE.md`/`KNOWLEDGE.md`/`skills/`…), so a checkout merely *named* `su-code` cannot make its
  parent look like a project.
  - Applied across the machine: 16 projects synced, 54 `SKILL.md` each (verified on disk).


## [v2026.08.15] - 2026-08-15 -- session restore across reboots (resurrect.wezterm)

### Added
- **Session persistence via [resurrect.wezterm](https://github.com/YedPool/resurrect.wezterm)
  (YedPool fork — fixes Windows hangs and `periodic_save` never writing files)**: the window/
  tab/split layout, pane working directories and screen text are auto-saved every 2 minutes and
  the last workspace is restored automatically when WezTerm starts — so after a PC shutdown/reboot
  the terminal reopens with the session as it was left.
  - `wezterm.lua`: pcall-guarded `wezterm.plugin.require` + `periodic_save` (120 s) +
    `gui-startup` auto-restore. Failure to load the plugin (offline first start) degrades to the
    previous behaviour — the config never breaks.
  - `keys.lua`: `Ctrl+a Shift+s` saves the workspace now; `Ctrl+a Shift+r` fuzzy-restores any
    saved workspace/window/tab (`restore_text` on, safe-process allowlist honoured).
  - Caveat: processes are not literally resurrected. Panes reopen a fresh shell (with the
    bootstrap) at the saved cwd with scrollback text restored; known-safe TUIs (`vim`, `nvim`,
    `claude`, `htop`, …) are relaunched automatically, others are not.
- **`ft session` command** (`modules/session.ps1`): manage saved sessions from the shell —
  `status`/`list [--all]` (saved workspaces/windows/tabs with pane counts), `save` (instant save
  via an OSC 1337 `ft_session_save` user-var trigger wired to `event_driven_save` in
  `wezterm.lua`), `restore <name>` (stages `current_state` so the next WezTerm start restores
  that workspace), `delete <name>` (with confirm). Wired into the dispatcher, reload list,
  Tab-completer and help hints. Structure-change saves (event-driven) were also enabled, so a
  split/tab change is captured immediately instead of waiting for the 2-minute periodic save.
- **Smart image paste (`Ctrl+Alt+v`)**: WezTerm has no native clipboard-image paste
  (wezterm#7272 closed unmerged; the latest stable is still 20240203, so upgrading adds
  nothing here). When the clipboard holds an image, it is saved to
  `%TEMP%\ft-paste\img_<timestamp>.png` and the file path is typed into the pane (Claude
  Code / `8sync` image workflow); with plain text in the clipboard it falls back to a normal
  paste. Implementation: `wezterm.action_callback` + STA PowerShell child process
  (`Windows.Forms.Clipboard::GetImage`) in `keys.lua`.


## [v2026.08.14] - 2026-08-14 -- bilingual README + GitHub Pages site; `ft up` wired

### Added
- **`ft up sucode` / `ft sucode` auto-updater**: `su-code` AI binary can now be updated on-demand or as part of `ft up` directly pulling latest releases from `8-Sync-Dev/su-code` repo.
- **Real usage screenshot (`assets/preview.png`, 1568x642)**: featured real multi-pane terminal workflow (Yazi file tree, Helix editor, theme picker, starry anime wallpaper) prominently in `README.md`, `README.vi.md`, `index.html`, and `vi.html`.
- **Rewritten `README.md`** -- rendered banner + three preview images (`assets/banner.png`,
  `preview-help.png`, `preview-status.png`, `preview-themes.png`), badges, a full feature deep-dive
  (look/wallpapers/toolchain/GGUF/clean/profiles), a mermaid architecture diagram, an honest-caveats
  section, and an SEO keyword/hashtag block.
- **`README.vi.md`** -- complete Vietnamese translation, cross-linked with the English README.
- **GitHub Pages landing site**: `index.html` (EN) + `vi.html` (VI) sharing `assets/site.css`, with
  `hreflang` alternates, canonical URLs, Open Graph/Twitter cards pointing at `assets/banner.png`,
  JSON-LD `SoftwareApplication`, `sitemap.xml`, `robots.txt` and `.nojekyll`. Served from the repo root,
  so `https://8-sync-dev.github.io/flash-term/install.ps1` keeps working.
- **`chafa` is now a managed CLI tool** (21 total), so `ft bg pick`'s inline thumbnail preview works
  after `ft sync` instead of silently degrading to the text-only fallback.

### Fixed
- **`ft up` actually runs.** The dispatcher had no `up` case (it fell through to the help menu) and
  `$script:UpTargets` was never defined, so even a direct call iterated zero targets. Added the
  dispatcher arm + `$script:UpTargets = @('self','scoop','wezterm')`, and replaced the call to the
  non-existent `Test-WorkingTreeClean` with a `git status --porcelain` check. `ft up`, `ft up --check`,
  `ft up help` and single targets verified.
- **`ft clean --envs --delete` project/git guard never fired**: `Test-IsProjectPath -Path $p -or (...)`
  passed `-or` as a parameter, so the condition could not evaluate and stale envs inside project/git
  trees were not skipped. Same binding bug in the `cargo audit` branch of `ft clean --audit`.
- **`Alt+0` now jumps to the last tab** (`ActivateTab(-1)`); it was a duplicate of `Alt+9`.
- **`ft help` no longer claims `ft bg pick` uses `imgcat`** -- the preview renderer is `chafa`.
- **`docs/KEYBINDINGS.md`** documents `Ctrl+Shift+b` (wallpaper toggle), `Ctrl+Shift+o` (cursor cycle),
  `Alt+0`, the mouse bindings, all six leader-typed commands, and the PSReadLine keys.
- **`docs/gguf-local-gpu-provider.md`** no longer claims `--balance` equals a `balanced` preset (no such
  preset exists); it now describes the actual VRAM solver and its `nvidia-smi` requirement.
- **`docs/ARCHITECTURE.md`** updated: 21 tools, sync lock/TTL details, `ft dev all --check` caveat,
  plus new Profiles and Startup-cost-control sections.

### Internal
- Project memory spine moved to the committed `su-code/` directory (`STATE.md` with a cold-resume
  handoff, `KNOWLEDGE.md`, `PROJECT.md`). The root `8sync/` template folder is gitignored leftover from
  before the su-code rename and holds nothing.

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
