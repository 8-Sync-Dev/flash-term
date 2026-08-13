# CLAUDE.md



Guidance for AI agents (Claude Code, omp via su-code, Cursor, OpenCode, …) working in this repository.

## What This Is

**flash-term** — a **WezTerm terminal configuration** + the **`ft` command** for **Windows 11**
(PowerShell). It is *not* an AI harness: it handles terminal **appearance**, **tooling bootstrap**,
and **convenience helpers**. The AI coding harness is a separate project —
[`su-code`](https://github.com/8-Sync-Dev/su-code), which provides the **`8sync`** command
(sessions `8sync .`, `8sync ai`, `8sync harness`, `8sync skill`, …). flash-term installs su-code for
you via `ft setup`.

Two layers in *this* repo:

- **Lua layer** (`wezterm.lua`, `keys.lua`) — appearance, fonts, keybindings, glass presets,
  background, shell launch.
- **PowerShell layer** (`wezterm-bootstrap.ps1` + `modules/*.ps1`) — the **`ft`** toolkit: tool sync
  (Scoop), dev runtimes, aliases, update-all, backgrounds, themes, GPU policy, cleanup, GGUF local
  models, profiles.

The `ft` dispatcher is the function `Invoke-8Sync`, aliased as **`ft`**. The name `8sync` is
deliberately **not** aliased here — it belongs to the su-code AI binary, which must not be shadowed.

## Architecture

```
WezTerm start
  └─ wezterm.lua                 reads current-{bg,opacity,style,gpu}.lua, sets config
       └─ launches PowerShell:   ". wezterm-bootstrap.ps1"
            └─ wezterm-bootstrap.ps1   dot-sources modules/, runs Task switch
                 ├─ core.ps1      hint (Show-8SyncHint), status, state, paths
                 ├─ sync.ps1 / up.ps1     tool sync + update-all
                 ├─ shell.ps1     PSReadLine, fzf, Register-8SyncCompleter (for `ft`)
                 ├─ startup.ps1   Invoke-8Sync dispatcher (aliased as `ft`), Start-WezTermShell
                 ├─ setup.ps1     full bootstrap; installs su-code (`8sync`) for AI
                 ├─ dev.ps1       dev runtimes (node/python/go/rust/chromium/docker/encore)
                 ├─ bg / helix / clean / theme / gpu / profile   WezTerm UX commands
                 ├─ gguf.ps1      local llama.cpp model management
                 └─ autoupdate.ps1   background update + release notifier
```

State is shared between Lua and PowerShell via small generated `.lua` files
(`current-bg.lua`, `current-opacity.lua`, `current-style.lua`, `current-gpu.lua`);
PowerShell writes them, Lua reads them on reload. `wezterm cli reload` is called after each write.

## Command Surface (`ft`)

- **Bootstrap:** `ft setup` (PATH + Scoop + managed CLI tools + dev runtimes + **installs su-code for AI**) · `ft dev [node|python|go|rust|chromium|docker|encore|all]` · `ft dev --check`
- **Tools/UX:** `ft sync` (install/update managed tools) · `ft sync --check` · `ft status` · `ft reload` · `ft clean [--days N|--deep|--scan|--audit|--loop on …]` · `ft gpu [N|status|auto|off]` · `ft theme [style] [scene]` · `ft bg <search|pick|set|rotate|list|…>` · `ft hx <lang|health|opacity|theme|…>` · `ft profile <list|create|clone|switch|open|delete>`
- **Update:** `ft up [self|scoop|wezterm] [--check]` (updates the config repo, Scoop tools, and checks WezTerm)
- **Background notifier:** `ft autoupdate [on|off|auto|now]`
- **Local models:** `ft gguf <serve|hint|save|status|stop|presets|profiles|…>` — runs a local llama.cpp server (OpenAI-compatible `/v1`) on your GPU.
- `ft help` shows the full menu.

> **AI coding** is the separate **su-code** project (`8sync`), not flash-term:
> `8sync .` (resume an AI session) · `8sync ai "<prompt>"` · `8sync harness` · `8sync skill` ·
> `8sync ship`. Installed by `ft setup` (`irm https://8-sync-dev.github.io/su-code/install.ps1 | iex`).
> See <https://github.com/8-Sync-Dev/su-code>.

## Conventions

- Color scheme **Catppuccin Mocha**; font JetBrainsMono Nerd Font; Mica backdrop + glass presets.
- **Graceful degradation:** every tool integration is guarded by `Test-CommandExists`; missing tools are skipped, never fatal.
- PowerShell style: `Verb-Noun`, `$ErrorActionPreference = 'Continue'`, `try/catch` around external calls, `Write-Host -ForegroundColor` for all user output (never `Write-Output` for messages).
- Lua style: 2-space indent, `require` at top, wrap `dofile` in `pcall`, trailing commas in tables.
- Adding an `ft` command: implement `Invoke-<Name>Command` in a module, dot-source it in `wezterm-bootstrap.ps1`, add a case to `Invoke-8Sync` (`startup.ps1`), add to `$modes`/`$subMap` in `Register-8SyncCompleter` (`shell.ps1`), and add `Write-HintRow` entries to `Show-8SyncHint` (`core.ps1`).
- Do NOT commit generated state: `current-*.lua`, `.state/`, `bg/`, `fonts/`.

## Validate

```powershell
# PowerShell syntax
$null = [System.Management.Automation.Language.Parser]::ParseFile("$PWD\wezterm-bootstrap.ps1",[ref]$null,[ref]$e); $e

# Source bootstrap non-interactively (shows the ft hint menu)
pwsh -NoProfile -ExecutionPolicy Bypass -File .\wezterm-bootstrap.ps1 -Task Hint

# Tool status
pwsh -NoProfile -ExecutionPolicy Bypass -File .\wezterm-bootstrap.ps1 -Task Status

# WezTerm config
wezterm --config-file .\wezterm.lua --version
wezterm cli reload
```
