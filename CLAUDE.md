# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Companion Claude Config

Project-specific Claude policy is organized under `.claude/`:

- `.claude/CLAUDE.md` — Claude workspace index for this repo
- `.claude/rules/core/docs-standards.md` — markdown standards and naming
- `.claude/rules/core/project-structure.md` — canonical repository map
- `.claude/rules/core/reporting-standards.md` — reporting quality rules

When updating docs, keep these files aligned with `docs/CLAUDE.md`.

## What This Is

A WezTerm terminal configuration for Windows 11, consisting of two main files:

- **`wezterm.lua`** — WezTerm's Lua config: appearance, keybindings, font, background, shell launch command
- **`wezterm-bootstrap.ps1`** — PowerShell bootstrap script sourced on every new shell tab. Provides the "8sync" tool management system, shell aliases, wallpaper management, and PSReadLine setup

## Architecture

### Config Loading Flow
1. WezTerm loads `wezterm.lua` on start/reload
2. `wezterm.lua` launches PowerShell with `-Command ". 'wezterm-bootstrap.ps1'"` (see `config.default_prog`)
3. The bootstrap runs `Start-WezTermShell` which sets up PATH, aliases, PSReadLine, and triggers auto-sync

### Background Wallpaper System
- `wezterm.lua` calls `load_background_path()` which reads `current-bg.lua`
- `current-bg.lua` is a one-line Lua file returning an image path (e.g., `return [[C:\path\to\image.jpg]]`)
- The bootstrap's `8sync bg` commands search Wallhaven, download images to `bg/`, and write `current-bg.lua`
- After writing, `wezterm cli reload` is called to apply the change live

### 8sync Tool Management
- `$script:ToolPackages` defines the managed tool set (fzf, zoxide, ripgrep, fd, bat, eza, starship, helix, yazi, lazygit, delta, tokei, hyperfine, dust, procs, bottom, less)
- All tools are installed/updated via Scoop
- Auto-sync runs in a hidden background process when tools are missing or stale (72h interval)
- State persisted to `.state/tool-state.json`; `.state/sync.lock` prevents concurrent syncs
- `8sync opencode` exports a portable bundle to `./oc-bundle` from `~/.config/opencode`, excluding `lib/`, `node_modules/`, `*.ps1`, and `*.py` for cross-machine setup

### Key Design Patterns
- **Graceful degradation**: every tool check uses `Test-CommandExists` before setting aliases; if a tool is missing, the alias is simply skipped
- **Leader key**: `Ctrl+a` is the leader key (tmux-style), with `Leader → s` for workspace switcher, `Leader → c` for copy mode
- **Shell preference**: prefers `pwsh.exe` (via Scoop) over `powershell.exe`; auto-detected at both Lua and PowerShell layers

## Key Bindings Summary (wezterm.lua)

| Action | Binding |
|---|---|
| Split right / down | `Ctrl+Shift+\|` / `Ctrl+Shift+_` |
| Navigate panes | `Ctrl+Shift+Arrow` |
| Resize panes | `Alt+Shift+Arrow` |
| Close pane | `Ctrl+Shift+w` |
| Zoom pane | `Ctrl+Shift+z` |
| Command palette | `Ctrl+Shift+p` or `Leader → x` |
| Workspace switcher | `Leader → s` |

## Conventions

- Color scheme: **Catppuccin Mocha** throughout (status bar colors reference Catppuccin palette tokens like `#89b4fa`, `#a6adc8`)
- Font: JetBrainsMono Nerd Font with fallback chain, bundled in `fonts/`
- Window: Acrylic backdrop with background image overlay (brightness 0.32, dark overlay at 0.72 opacity)
- The bootstrap uses `$PSScriptRoot` for all paths — config is portable as long as the directory structure is preserved


<claude-mem-context>
# Recent Activity

### Mar 15, 2026

| ID | Time | T | Title | Read |
|----|------|---|-------|------|
| #126 | 6:52 PM | ✅ | CLAUDE.md documentation created for WezTerm configuration | ~497 |
</claude-mem-context>

<!-- OMA:START — managed by oh-my-agent. Do not edit this block manually. -->
# oh-my-agent — Claude Code Integration

## Reading Large Files
When reading large files, run `wc -l` first to check the line count. If the file is over 2,000 lines, use the `offset` and `limit` parameters on the Read tool to read in chunks rather than attempting to read the entire file at once.

## Architecture
- **SSOT**: `.agents/` directory (do not modify directly)
- **Response language**: Follows `language` in `.agents/oma-config.yaml`
- **Domain Skills**: `.agents/skills/` (exposed to `.claude/skills/` via symlinks)
- **Workflows**: `.agents/workflows/` (mapped to `.claude/skills/` as thin routers)
- **Subagents**: `.claude/agents/` (spawned via Task tool)

## Slash Commands

| Command | Workflow | Execution |
|:--|:--|:--|
| `/orchestrate` | `orchestrate.md` | Parallel subagents + Review Loop |
| `/work` | `work.md` | TaskCreate + Issue Remediation Loop |
| `/ultrawork` | `ultrawork.md` | 5-Phase Gate Loop |
| `/plan` | `plan.md` | Inline PM analysis |
| `/exec-plan` | `exec-plan.md` | Inline plan management |
| `/brainstorm` | `brainstorm.md` | Inline design exploration |
| `/review` | `review.md` | qa-reviewer subagent delegation |
| `/debug` | `debug.md` | Inline + subagent |
| `/commit` | `commit.md` | Inline git commit |
| `/tools` | `tools.md` | Inline MCP management |
| `/stack-set` | `stack-set.md` | Inline stack configuration |
| `/deepinit` | `deepinit.md` | Inline project initialization |

## Automatic Workflow Detection

Workflows activate via natural-language keywords — no `/command` required.
The `UserPromptSubmit` hook detects keywords and injects `[OMA WORKFLOW: ...]` into context.
Trigger keywords are defined in `.claude/hooks/triggers.json` (multi-language support).

### Hook Behavior
- `[OMA WORKFLOW: ...]` → read and execute the workflow file immediately
- `[OMA PERSISTENT MODE: ...]` → workflow still in progress, continue execution
- Informational context ("what is X?") is filtered out — no false triggers
- Explicit `/command` input skips the hook (no duplication)
- Persistent-mode workflows (`ultrawork`, `orchestrate`, `work`) block termination until complete
- Deactivate persistent mode: say "workflow done" → deletes `.agents/state/{workflow}-state-{sessionId}.json`

## Required References (before any skill execution)
1. `.agents/skills/_shared/core/skill-routing.md` — Agent routing
2. `.agents/skills/_shared/core/context-loading.md` — Selective resource loading
3. `.agents/skills/_shared/core/prompt-structure.md` — Goal, Context, Constraints, Done When

## Subagent Rules
- Definitions: `.claude/agents/*.md` → spawn via Task tool
- Parallel: multiple Task tool calls in a single message
- Results: synchronous return, written to `.agents/results/result-{agent}[-{sessionId}].md`
- Subagents require Charter Preflight (`CHARTER_CHECK`)

## Rules
1. **Do not modify `.agents/` files** — SSOT protection
2. Domain skills load only via explicit invocation or agent `skills` field
3. Workflows execute via explicit `/command` or hook auto-detection only — never self-initiated
4. Plans saved to `.agents/plan.json`
5. `stack/` is generated output — SSOT exception
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
