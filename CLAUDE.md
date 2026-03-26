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
