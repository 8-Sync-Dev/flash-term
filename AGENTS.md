# AGENTS.md

Agent guidance for the flash-term WezTerm + omp harness repository.

## Repository Overview

A WezTerm terminal configuration + **omp AI coding harness** for Windows 11.

- `wezterm.lua` / `keys.lua` â€” Lua config (appearance, fonts, keybindings, glass presets, background).
- `wezterm-bootstrap.ps1` â€” PowerShell bootstrap sourced on every new shell tab.
- `modules/*.ps1` â€” the `8sync` command toolkit (AI harness, skills, update-all, sync, themes, GPU, clean, GGUF).
- `agents/registry.json` â€” the omp skill registry.
- `gguf-config/` â€” llama.cpp server presets/profiles.

Generated at runtime (gitignored, never commit): `current-{bg,opacity,style,gpu}.lua`, `.state/`, `bg/`, `fonts/`, `agents/skills/`.

## Build / Lint / Test

No build system. Validation only:

```powershell
# Syntax-check every PowerShell module
Get-ChildItem -Recurse -Include *.ps1 modules | ForEach-Object {
  $null = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$null,[ref]$e)
  if ($e.Count) { $_.Name; $e }
}

# Dry-run: source the bootstrap and show the help (non-destructive)
pwsh -NoProfile -ExecutionPolicy Bypass -File .\wezterm-bootstrap.ps1 -Task Hint

# Dry-run: tool status
pwsh -NoProfile -ExecutionPolicy Bypass -File .\wezterm-bootstrap.ps1 -Task Status

# Lua config sanity
wezterm --config-file .\wezterm.lua --version
```

No unit tests. Validate a change by sourcing the bootstrap in a fresh `pwsh` session and exercising the affected `8sync` verb.

## Architecture

```
WezTerm start
  â””â”€ wezterm.lua: reads current-{bg,opacity,style,gpu}.lua, sets config
       â””â”€ launches PowerShell: ". wezterm-bootstrap.ps1"
            â”œâ”€ Ensure-PreferredPaths   (prepend scoop/shims to PATH)
            â”œâ”€ Set-HistoryExperience   (PSReadLine + fzf Ctrl+r)
            â”œâ”€ Set-ToolAliases         (ll, e, lg, y, cdi, 8sync â€¦)
            â”‚    â””â”€ Register-8SyncCompleter  (Tab/inline completion for 8sync)
            â””â”€ Start-AutoSync          (hidden background process if stale)
```

State is shared between the Lua layer and the PowerShell layer via small generated `.lua` files;
PowerShell writes them, Lua reads them on reload. `wezterm cli reload` is called after each write.

## Code Style â€” Lua (`wezterm.lua`, `keys.lua`)

- 2-space indentation. No tabs. Trailing commas in multi-line tables.
- `require` at the top before any logic. Only `wezterm` is required.
- Wrap `dofile` / `pcall`-able calls in `pcall`; check `ok` before use. Never raise on missing optional files.
- `snake_case` locals; PascalCase WezTerm API objects. Hex colors match the Catppuccin Mocha palette.
- All keybindings live in `keys.lua` (returned as a table). Leader is `Ctrl+a` (900ms).

## Code Style â€” PowerShell (`wezterm-bootstrap.ps1`, `modules/`)

- 4-space indentation. `Verb-Noun` PascalCase for public functions; `$script:CamelCase` for script scope; `$camelCase` for locals.
- `$ErrorActionPreference = 'Continue'` at script scope â€” never change it. `try/catch` around all external calls.
- Guard every tool integration: `if (Test-CommandExists 'eza') { â€¦ }`. Never assume a tool is present.
- `$null = â€¦` to suppress output (not `| Out-Null` for assignments). `Write-Host -ForegroundColor` for all user output; never `Write-Output` for messages.
- State files in `.state/`; `ConvertTo-Json`/`ConvertFrom-Json` with `-Encoding UTF8`; wrap reads in `try/catch`.
- Generated Lua files: always call `Try-ReloadWezTerm` after writing.
- Help rendered by `Show-8SyncHint` via `Write-HintRow`/`Write-HintSection`. New commands must be added to `Show-8SyncHint` AND `Register-8SyncCompleter`.

## Adding an `8sync` command

1. Implement `Invoke-<Name>Command` in `modules/<name>.ps1`.
2. Dot-source it in `wezterm-bootstrap.ps1`.
3. Add a case to the `Invoke-8Sync` switch in `modules/startup.ps1` (and to its reload module list).
4. Add the mode + subcommands to `$modes`/`$subMap` in `Register-8SyncCompleter` (`modules/shell.ps1`).
5. Add `Write-HintRow` entries to `Show-8SyncHint` (`modules/core.ps1`).

## What NOT to Do

- Do not add `Set-StrictMode` (breaks dynamic alias creation).
- Do not use `exit` in the bootstrap (closes the terminal tab).
- Do not commit generated state or `agents/skills/`.
- Do not add a hard dependency on a tool that may be missing â€” always guard with `Test-CommandExists`.
- Treat visual appearance (Catppuccin/glass/Mica) as stable unless explicitly asked to redesign.

<!-- agents:max-skill:start -- managed by 8sync skill deploy -->

## Agent Skill Library (8sync)

**Rule:** Before any non-trivial task, read the mandatory skill first, then select by task type.
Skills are deployed to `~/.omp/skills/`; omp auto-discovers them.

| Skill | When |
|---|---|
| ~/.omp/skills/karpathy-guidelines/$mark | ALL coding tasks -- mandatory baseline read first. Software engineering best practices by Andrej Karpathy: avoid over-engineering, test before refactor, keep it simple. |

### Project memory (auto-managed)

Read the relevant file BEFORE making decisions that depend on project context:

| File | When to read |
|---|---|
| `8sync/PROJECT.md` | Start of any session |
| `8sync/STATE.md` | Before resuming work |
| `8sync/KNOWLEDGE.md` | Before writing new code |

Never dump huge tool output into context. Summarize first, then read narrow slices.

<!-- agents:max-skill:end -->

