# CLAUDE.md

Guidance for AI agents (Claude Code, omp, Cursor, OpenCode, …) working in this repository.

## What This Is

**flash-term** — a WezTerm terminal configuration + omp AI coding harness for **Windows 11**.
Two layers:

- **Lua layer** (`wezterm.lua`, `keys.lua`) — appearance, fonts, keybindings, glass presets, background, shell launch.
- **PowerShell layer** (`wezterm-bootstrap.ps1` + `modules/*.ps1`) — the `8sync` toolkit: tool sync (Scoop), aliases, the omp AI harness, skill registry, update-all, backgrounds, themes, GPU policy, cleanup, GGUF local models.

The AI engine is **omp** (oh-my-pi). `8sync .` resumes an omp session; `8sync harness` deploys skills + project memory; `8sync skill` manages the skill registry; `8sync up` updates everything.

## Architecture

```
WezTerm start
  └─ wezterm.lua                 reads current-{bg,opacity,style,gpu}.lua, sets config
       └─ launches PowerShell:   ". wezterm-bootstrap.ps1"
            └─ wezterm-bootstrap.ps1   dot-sources modules/, runs Task switch
                 ├─ core.ps1      hint, status, state, paths
                 ├─ agents/00-shared.ps1   skill clone helpers
                 ├─ sync.ps1 / up.ps1     tool sync + update-all
                 ├─ shell.ps1     PSReadLine, fzf, Register-8SyncCompleter
                 ├─ startup.ps1   Invoke-8Sync dispatcher, Start-WezTermShell
                 ├─ bg / helix / clean / theme / gpu / profile   WezTerm UX commands
                 ├─ gguf.ps1      local llama.cpp model management
                 ├─ skill.ps1     8sync skill add/list/update/remove/deploy
                 └─ harness.ps1   8sync harness + 8sync . + 8sync ai (omp)
```

State is shared between Lua and PowerShell via small generated `.lua` files
(`current-bg.lua`, `current-opacity.lua`, `current-style.lua`, `current-gpu.lua`);
PowerShell writes them, Lua reads them on reload. `wezterm cli reload` is called after each write.

## Command Surface (`8sync`)

- **AI harness (omp):** `8sync .` (resume latest) · `8sync . <name>` (create/resume named) · `8sync . new <name> [--worktree]` (fresh session) · `8sync . ls` · `8sync . rm <name> [--force]` · `8sync . mv <old> <new>` · `8sync . merge <a> [b...]` · `8sync ai "<prompt>"` · `8sync harness [init|up|global|status]` · `8sync skill [list|add|update|remove|deploy]`
- **Update:** `8sync up [self|scoop|omp|skills|wezterm] [--check]`
- **Tools/UX:** `8sync sync` · `8sync status` · `8sync reload` · `8sync clean` · `8sync gpu` · `8sync theme` · `8sync bg` · `8sync hx` · `8sync profile`
- **Local models:** `8sync gguf`
- `8sync help` shows the full menu.

## Conventions

- Color scheme **Catppuccin Mocha**; font JetBrainsMono Nerd Font; Mica backdrop + glass presets.
- **Graceful degradation:** every tool integration is guarded by `Test-CommandExists`; missing tools are skipped, never fatal.
- PowerShell style: `Verb-Noun`, `$ErrorActionPreference = 'Continue'`, `try/catch` around external calls, `Write-Host -ForegroundColor` for all user output (never `Write-Output` for messages).
- Lua style: 2-space indent, `require` at top, wrap `dofile` in `pcall`, trailing commas in tables.
- Adding a command: implement in a module, add a case to `Invoke-8Sync` (startup.ps1), add to `$modes`/`$subMap` (shell.ps1), add a `Write-HintRow` (core.ps1).
- Do NOT commit generated state: `current-*.lua`, `.state/`, `bg/`, `fonts/`, `agents/skills/`.

## Validate

```powershell
# PowerShell syntax
$null = [System.Management.Automation.Language.Parser]::ParseFile("$PWD\wezterm-bootstrap.ps1",[ref]$null,[ref]$e); $e

# Source bootstrap non-interactively
pwsh -NoProfile -ExecutionPolicy Bypass -File .\wezterm-bootstrap.ps1 -Task Hint

# WezTerm config
wezterm --config-file .\wezterm.lua --version
wezterm cli reload
```
