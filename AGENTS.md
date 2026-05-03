# AGENTS.md

Agent guidance for the WezTerm configuration repository.

## Repository Overview

A WezTerm terminal configuration for Windows 11. Two primary source files:

- **`wezterm.lua`** — Lua config loaded directly by WezTerm (appearance, fonts, keybindings, shell launch)
- **`wezterm-bootstrap.ps1`** — PowerShell script sourced on every new shell tab (8sync toolkit, aliases, auto-sync)

Four files are **generated at runtime** and must never be committed (they are in `.gitignore`):
- `current-bg.lua` — written by `8sync bg set`, read by `wezterm.lua`
- `current-opacity.lua` — written by `8sync hx opacity`, read by `wezterm.lua`
- `current-style.lua` — written by `8sync theme` / `8sync bg set`, read by `wezterm.lua`
- `current-gpu.lua` — written by `8sync gpu`, read by `wezterm.lua`

## Build / Lint / Test Commands

There is no build system, test suite, or package manager. This is a config-only repository.

### Validate the Lua config

```powershell
# Check wezterm.lua for syntax errors (requires WezTerm CLI in PATH)
wezterm --config-file .\wezterm.lua list-clients

# Reload live config (running WezTerm instance required)
wezterm cli reload
```

### Validate the PowerShell bootstrap

```powershell
# Syntax-check only (no execution)
$null = [System.Management.Automation.Language.Parser]::ParseFile(
    "$PWD\wezterm-bootstrap.ps1", [ref]$null, [ref]$null
)

# Dry-run: source with -Task Status (non-destructive, shows tool state)
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ". .\wezterm-bootstrap.ps1; Show-8SyncStatus"

# Dry-run: source with -Task Hint (non-destructive, prints help text)
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\wezterm-bootstrap.ps1 -Task Hint
```

### Manual end-to-end test

```powershell
# Source bootstrap in an isolated shell; confirm no errors, aliases present
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ". .\wezterm-bootstrap.ps1; ll; e --version"
```

There are no unit tests. When making changes, validate by sourcing the bootstrap in a fresh
`pwsh` session and exercising the affected `8sync` subcommand or alias manually.

## Architecture Summary

```
WezTerm start
  └─ wezterm.lua: reads current-bg.lua + current-opacity.lua, sets config
       └─ launches PowerShell: ". wezterm-bootstrap.ps1"
            ├─ Ensure-PreferredPaths   (prepend scoop/shims to PATH)
            ├─ Set-HistoryExperience   (PSReadLine + fzf Ctrl+r)
            ├─ Set-ToolAliases         (ll, e, lg, y, cdi, 8sync …)
            │    └─ Register-8SyncCompleter  (Tab/inline completion for 8sync)
            └─ Start-AutoSync          (hidden background process if stale)
```

State is shared between the Lua layer and the PowerShell layer via small generated `.lua` files;
PowerShell writes them, Lua reads them on reload. `wezterm cli reload` is called after each write.

## Code Style — Lua (`wezterm.lua`)

### Formatting
- 2-space indentation. No tabs.
- One blank line between top-level function definitions.
- Opening brace on the same line as the construct (`function foo()`, `config.keys = {`).
- Trailing commas on the last element of multi-line tables — consistent with existing style.

### Naming
- Local variables and functions: `snake_case` (e.g., `load_background_path`, `pane_cwd`).
- WezTerm API objects follow the library's convention (PascalCase for actions/events).

### Imports / Requires
- `require` calls at the top of the file, before any logic.
- Only `wezterm` is required; do not add other dependencies unless unavoidable.

### Error handling
- Wrap `dofile` / `pcall`-able calls in `pcall`; check `ok` before using the result.
- Never raise errors for missing optional files — fall back to a default and continue.
- Use `os.rename` to test file existence (the `file_exists` pattern already in use).

### Types / values
- Lua is dynamically typed; validate types explicitly when reading external data:
  ```lua
  if ok and type(value) == "string" and value ~= "" then …
  ```
- Color values must be hex strings matching the Catppuccin Mocha palette.

### Key bindings
- All bindings go in the `config.keys` table; do not scatter them.
- Leader key is `Ctrl+a` (900 ms timeout). New leader-chained bindings use `mods = "LEADER"`.

## Code Style — PowerShell (`wezterm-bootstrap.ps1`)

### Formatting
- 4-space indentation. No tabs.
- Opening brace on the same line (`function Foo {`).
- Closing brace on its own line.
- Use `$null = …` to suppress unwanted output instead of `| Out-Null` for assignment contexts.

### Naming
- Public/exported functions: `Verb-Noun` PascalCase following PowerShell conventions
  (e.g., `Invoke-ToolSync`, `Set-HelixThemeValue`).
- Script-scoped variables: `$script:CamelCase` (e.g., `$script:StateDir`).
- Local variables inside functions: `$camelCase`.
- Boolean flags: prefix with verb (`$shouldSync`, `$found`, `$inSection`).

### Function design
- Each function has one responsibility. Decompose large operations.
- Use `[Parameter(Mandatory)]` for required parameters.
- Return early on precondition failures (`if (-not $scoop) { return }`).
- Prefer `[pscustomobject]@{ … }` for structured return values.

### Error handling
- `$ErrorActionPreference = 'Continue'` at script scope — never change this.
- Use `try/catch` around all external calls (network, file I/O, process launch).
- Silently suppress errors in background/auto-sync code paths with empty `catch {}` blocks and a comment explaining why.
- Use `-ErrorAction SilentlyContinue` on `Get-Command` checks; never let a missing command crash the shell.
- Warnings to the user: `Write-Warning` for actionable problems, `Write-Host … -ForegroundColor DarkYellow` for soft informational notices.

### Graceful degradation pattern
Every alias or integration must be guarded:
```powershell
if (Test-CommandExists 'eza') {
    function global:ll { eza --icons=always --group-directories-first -lah @args }
} else {
    function global:ll { Get-ChildItem -Force @args }
}
```
Never assume a managed tool is present. Use `Test-CommandExists` before setting any alias.

### Output / UX
- Use `Write-Host` with `-ForegroundColor` for all user-visible output; do not rely on default stream output.
- Color palette: Cyan = section headers, Yellow = action/progress, Green = success, DarkYellow = warning/missing, DarkGray = hints.
- No `Write-Output` for user messages (it pollutes the pipeline).

### Imports
- No `Import-Module` at script scope except inside a `try/catch` (e.g., PSReadLine).
- Check `Get-Module -ListAvailable` before importing optional modules.

### State files
- `.state/` directory holds all mutable runtime state. Ensure the directory with `Ensure-StateDir` before any read/write.
- Serialize with `ConvertTo-Json` / `ConvertFrom-Json`; always `-Encoding UTF8`.
- Wrap JSON reads in `try/catch` and return a safe default on parse failure.

### Generated Lua files
- `current-bg.lua` format: `return [[C:\path\to\image.jpg]]`
- `current-opacity.lua` format: `return 0.72`
- `current-gpu.lua` format: `return { min_percent = 10, updated_utc = "2026-03-27T02:00:00.0000000Z" }`
- Always call `Try-ReloadWezTerm` after writing any generated Lua state file.

### UI / help output
- Help is rendered by `Show-8SyncHint` using `Write-HintRow` / `Write-HintSection` helpers.
- `Write-HintRow` reads `$Host.UI.RawUI.WindowSize.Width` and word-wraps the description column;
  command column is 32 chars wide. Do not revert to the old manual padding pattern.
- Add new commands to `Show-8SyncHint` AND to the `Register-8SyncCompleter` subMap.

### Tab completion
- `Register-8SyncCompleter` registers `Register-ArgumentCompleter` for both `8sync` and `/8sync`.
- Top-level modes list and per-mode subcommand lists live in `$modes` / `$subMap` inside that function.
- Call `Register-8SyncCompleter` at the end of `Set-ToolAliases` (already done).

### 8sync clean
- Entry point: `Invoke-CleanCommand` → `Invoke-SystemClean`.
- Flags: `--days N` (default 7), `--dry-run`, `--help`.
- Safe-delete rules: uses `LastWriteTime` age filter; never deletes files without a path guard;
  skips non-existent paths silently; PSIsContainer items are not deleted directly (only empties removed).
- RAM flush: `EmptyWorkingSet` P/Invoke on current process + `ipconfig /flushdns` (no admin required).
- Venv scan: `Find-VenvDirs` walks `$HOME` and common project roots up to depth 4;
  detects Python (`pyvenv.cfg`), Node (`node_modules`), Rust (`target/`), Go (`vendor/`).

## File & Directory Conventions

| Path | Purpose | Committed? |
|---|---|---|
| `wezterm.lua` | WezTerm Lua config | Yes |
| `wezterm-bootstrap.ps1` | Shell bootstrap + 8sync | Yes |
| `current-bg.lua` | Generated: active wallpaper path | **No** |
| `current-opacity.lua` | Generated: overlay opacity | **No** |
| `current-style.lua` | Generated: active glass style/scene + bg hint | **No** |
| `current-gpu.lua` | Generated: GPU policy threshold + timestamp | **No** |
| `bg/` | Downloaded wallpaper images | **No** |
| `fonts/` | Bundled Nerd Font | **No** |
| `.state/` | Runtime state (JSON) | **No** |
| `docs/` | Reference documentation | Yes |

## What NOT to Do

- Do not add `Set-StrictMode` — it breaks dynamic alias creation patterns.
- Do not use `exit` in the bootstrap — it would close the terminal tab.
- Do not commit `current-bg.lua`, `current-opacity.lua`, `current-style.lua`, `current-gpu.lua`, `.state/`, `bg/`, or `fonts/`.
- Do not add Lua `require` calls for modules outside the WezTerm standard library.
- Do not add hard dependencies on tools that might not be installed; always guard with `Test-CommandExists`.
- Do not raise unhandled errors from background sync paths — they run in hidden processes with no user-visible output.

<!-- OMA:START — managed by oh-my-agent. Do not edit this block manually. -->

# oh-my-agent

## Architecture

- **SSOT**: `.agents/` directory (do not modify directly)
- **Response language**: Follows `language` in `.agents/oma-config.yaml`
- **Skills**: `.agents/skills/` (domain specialists)
- **Workflows**: `.agents/workflows/` (multi-step orchestration)
- **Subagents**: `oma agent:spawn {agent} {prompt} {sessionId}`

## Workflows

Execute by naming the workflow in your prompt. Keywords are auto-detected via hooks.

| Workflow | File | Description |
|----------|------|-------------|
| orchestrate | `orchestrate.md` | Parallel subagents + Review Loop |
| work | `work.md` | Step-by-step with remediation loop |
| ultrawork | `ultrawork.md` | 5-Phase Gate Loop (11 reviews) |
| plan | `plan.md` | PM task breakdown |
| brainstorm | `brainstorm.md` | Design-first ideation |
| review | `review.md` | QA audit |
| debug | `debug.md` | Root cause + minimal fix |
| commit | `commit.md` | Conventional Commits |

To execute: read and follow `.agents/workflows/{name}.md` step by step.

## Auto-Detection

Hooks: `UserPromptSubmit` (keyword detection), `PreToolUse`, `Stop` (persistent mode)
Keywords defined in `.agents/hooks/core/triggers.json` (multi-language).
Persistent workflows (orchestrate, ultrawork, work) block termination until complete.
Deactivate: say "workflow done".

## Rules

1. **Do not modify `.agents/` files** — SSOT protection
2. Workflows execute via keyword detection or explicit naming — never self-initiated
3. Response language follows `.agents/oma-config.yaml`

## Project Rules

Read the relevant file from `.agents/rules/` when working on matching code.

| Rule | File | Scope |
|------|------|-------|
| backend | `.agents/rules/backend.md` | on request |
| commit | `.agents/rules/commit.md` | on request |
| database | `.agents/rules/database.md` | **/*.{sql,prisma} |
| debug | `.agents/rules/debug.md` | on request |
| design | `.agents/rules/design.md` | on request |
| dev-workflow | `.agents/rules/dev-workflow.md` | on request |
| frontend | `.agents/rules/frontend.md` | **/*.{tsx,jsx,css,scss} |
| i18n-guide | `.agents/rules/i18n-guide.md` | always |
| infrastructure | `.agents/rules/infrastructure.md` | **/*.{tf,tfvars,hcl} |
| mobile | `.agents/rules/mobile.md` | **/*.{dart,swift,kt} |
| quality | `.agents/rules/quality.md` | on request |

<!-- OMA:END -->

<!-- agents:max-skill:start -- managed by 8sync agents max-skill -->

## Agent Skill Library (8sync max-skill)

**Rule:** Before any non-trivial task, read karpathy-guidelines first.
Then select additional skills by task type. These rules apply to GSD, Claude Code, Forge, and all project agents that read this file.

| Task type | Skills |
|---|---|
| Any coding | `agents/skills/karpathy-guidelines/` (mandatory, always first) |
| GSD workflow | + `agents/skills/gsd-pi-guide/` and the GSD memory/token rules below |
| Large repo analysis | Use `gsd_exec`/`gsd_exec_search` before reading many files |
| Shell cmds | Use rtk variants: `rtk git`, `rtk read`, `rtk grep` |

### Skill Registry

- **Karpathy Guidelines** **(mandatory)**: ALL coding tasks -- mandatory baseline read first. Software engineering best practices by Andrej Karpathy: avoid over-engineering, test before refactor, keep it simple.  
  Ref: https://github.com/forrestchang/andrej-karpathy-skills
- **GSD 2 Guide**: GSD 2 workflow, auto mode, slash commands, milestone planning, slice execution, verification, cost management. Read to understand how to use /gsd commands.  
  Ref: local

### GSD Project Context (auto-injected)

When working in a GSD-enabled project, these files contain critical project state.
**Read the relevant file BEFORE making decisions** that depend on project context.

| File | What it contains | When to read |
|---|---|---|
| `.gsd/PROJECT.md` | Project name, tech stack, goals, constraints | Start of any session |
| `.gsd/CONTEXT.md` | Current milestone, active slice, recent decisions | Before planning or coding |
| `.gsd/STATE.md` | Workflow state machine position, phase, blockers | Before any `/gsd` command |
| `.gsd/CODEBASE.md` | Auto-generated codebase map (modules, entry points) | When navigating unfamiliar code |
| `.gsd/DECISIONS.md` | Architecture decisions log (ADRs) | Before proposing arch changes |
| `.gsd/KNOWLEDGE.md` | Learned patterns, gotchas, team conventions | Before writing new code |
| `.gsd/PREFERENCES.md` | User coding style, tool preferences, review standards | Always (style compliance) |
| `.gsd/milestones/M*/` | Milestone roadmaps, slice breakdowns, validation criteria | When planning or reviewing scope |

**Priority order:** PROJECT.md > CONTEXT.md > STATE.md > others as needed.

### GSD Memory and Token Optimization Rules

These rules are mandatory on large projects or long sessions:

1. Use `gsd_resume` immediately after compaction/session resume when context may be stale.
2. Use `memory_query` before re-reading broad project history or prior decisions.
3. Use `gsd_exec` for analysis that would read more than 3 files or produce large output; log summaries, not raw dumps.
4. Use `gsd_exec_search` before rerunning expensive analysis.
5. Use `capture_thought` only for reusable project knowledge, conventions, gotchas, and architectural lessons.
6. Use `gsd_graph` when a memory relationship matters instead of rediscovering context manually.
7. Prefer GSD summaries and status tools over raw DB/file spelunking: `gsd_milestone_status`, `gsd_journal_query`, `gsd_summary_save`.
8. Prefer `rtk read`, `rtk grep`, and `rtk git` for shell/file output when available.
9. Never dump huge tool output into the model context. Summarize first, then read narrow slices with offsets/limits.

### GSD Workflow Reference

Read `agents/skills/gsd-pi-guide/SKILL.md` for the full GSD 2 CLI reference.
Key commands: `/gsd start`, `/gsd plan`, `/gsd auto`, `/gsd status`, `/gsd cost`.
GSD uses a state machine: discuss > plan > execute > verify > complete.
Never skip phases. Always verify before marking complete.

<!-- agents:max-skill:end -->
