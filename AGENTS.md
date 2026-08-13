# AGENTS.md



Agent guidance for the flash-term WezTerm configuration + `ft` command repository.

## Repository Overview

A **WezTerm terminal configuration** + the **`ft` command** for **Windows 11** (PowerShell).
flash-term handles terminal *appearance*, *tooling bootstrap*, and *convenience helpers* — it is
**not** an AI harness. (The AI coding harness is the separate
[`su-code`](https://github.com/8-Sync-Dev/su-code) project, which provides the `8sync` command;
`ft setup` installs it.)

- `wezterm.lua` / `keys.lua` — Lua config (appearance, fonts, keybindings, glass presets, background).
- `wezterm-bootstrap.ps1` — PowerShell bootstrap sourced on every new shell tab.
- `modules/*.ps1` — the **`ft`** command toolkit (one module per concern):
  `core` · `sync` · `shell` · `bg` · `helix` · `clean` · `theme` · `gpu` · `gguf` · `up` ·
  `autoupdate` · `setup` · `dev` · `startup` · `profile`.
- `gguf-config/` — llama.cpp server presets/profiles.
- `assets/` — shipped default wallpaper.

Generated at runtime (gitignored, never commit): `current-{bg,opacity,style,gpu}.lua`, `.state/`, `bg/`, `fonts/`.

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

No unit tests. Validate a change by sourcing the bootstrap in a fresh `pwsh` session and exercising the affected `ft` verb.

## Architecture

```
WezTerm start
  └─ wezterm.lua: reads current-{bg,opacity,style,gpu}.lua, sets config
       └─ launches PowerShell: ". wezterm-bootstrap.ps1"
            ├─ Ensure-PreferredPaths   (prepend scoop/shims to PATH)
            ├─ Set-HistoryExperience   (PSReadLine + fzf Ctrl+r)
            ├─ Set-ToolAliases         (ll, e, lg, y, cdi, …)
            │    └─ Register-8SyncCompleter  (Tab/inline completion for `ft`)
            └─ Start-AutoSync          (hidden background process if stale)
```

State is shared between the Lua layer and the PowerShell layer via small generated `.lua` files;
PowerShell writes them, Lua reads them on reload. `wezterm cli reload` is called after each write.

## Code Style — Lua (`wezterm.lua`, `keys.lua`)

- 2-space indentation. No tabs. Trailing commas in multi-line tables.
- `require` at the top before any logic. Only `wezterm` is required.
- Wrap `dofile` / `pcall`-able calls in `pcall`; check `ok` before use. Never raise on missing optional files.
- `snake_case` locals; PascalCase WezTerm API objects. Hex colors match the Catppuccin Mocha palette.
- All keybindings live in `keys.lua` (returned as a table). Leader is `Ctrl+a` (900ms).

## Code Style — PowerShell (`wezterm-bootstrap.ps1`, `modules/`)

- 4-space indentation. `Verb-Noun` PascalCase for public functions; `$script:CamelCase` for script scope; `$camelCase` for locals.
- `$ErrorActionPreference = 'Continue'` at script scope — never change it. `try/catch` around all external calls.
- Guard every tool integration: `if (Test-CommandExists 'eza') { … }`. Never assume a tool is present.
- `$null = …` to suppress output (not `| Out-Null` for assignments). `Write-Host -ForegroundColor` for all user output; never `Write-Output` for messages.
- State files in `.state/`; `ConvertTo-Json`/`ConvertFrom-Json` with `-Encoding UTF8`; wrap reads in `try/catch`.
- Generated Lua files: always call `Try-ReloadWezTerm` after writing.
- Help rendered by `Show-8SyncHint` via `Write-HintRow`/`Write-HintSection`. New commands must be added to `Show-8SyncHint` AND `Register-8SyncCompleter`.

## Adding an `ft` command

1. Implement `Invoke-<Name>Command` in `modules/<name>.ps1`.
2. Dot-source it in `wezterm-bootstrap.ps1`.
3. Add a case to the `Invoke-8Sync` switch in `modules/startup.ps1` (the dispatcher is the function `Invoke-8Sync`, aliased globally as **`ft`**; also add the file to the reload module list in the `reload` case).
4. Add the mode + subcommands to `$modes`/`$subMap` in `Register-8SyncCompleter` (`modules/shell.ps1`) — note it registers the completer against the command name **`ft`**.
5. Add `Write-HintRow` entries to `Show-8SyncHint` (`modules/core.ps1`).

> Do **not** alias or implement anything under the name `8sync` here — that command belongs to the
> su-code AI binary. flash-term's user-facing command is always `ft`.

## What NOT to Do

- Do not add `Set-StrictMode` (breaks dynamic alias creation).
- Do not use `exit` in the bootstrap (closes the terminal tab).
- Do not commit generated state (`current-*.lua`, `.state/`, `bg/`, `fonts/`).
- Do not add a hard dependency on a tool that may be missing — always guard with `Test-CommandExists`.
- Do not shadow the `8sync` command (su-code) with a flash-term alias — the flash-term command is `ft`.
- Treat visual appearance (Catppuccin/glass/Mica) as stable unless explicitly asked to redesign.
