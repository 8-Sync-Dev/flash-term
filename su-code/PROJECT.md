# PROJECT

**One-liner:** A WezTerm terminal configuration + the `ft` command toolkit for Windows 11 — appearance,
tooling bootstrap, and daily terminal helpers. **Not** an AI harness.

## Tech stack
- **Lua** — `wezterm.lua`, `keys.lua` (appearance, fonts, keybindings, glass/scene presets, background).
- **PowerShell 7** — `wezterm-bootstrap.ps1` (sourced on every new tab) + `modules/*.ps1`, one module per
  concern: `core` `sync` `shell` `bg` `helix` `clean` `theme` `gpu` `gguf` `up` `autoupdate` `setup`
  `dev` `startup` `profile`.
- **Scoop** as the package manager for the 21 managed CLI tools and most dev runtimes.
- No build system, no unit tests. Validation = `[Parser]::ParseFile` over every `.ps1`,
  `wezterm --config-file ./wezterm.lua --version|show-keys`, and running the affected `ft` verb in a
  fresh `pwsh`.

## Goals
- Beautiful out of the box: Catppuccin Mocha, glass/Mica, purple neon border, shipped wallpaper.
- One command (`ft setup`) provisions PATH, Scoop, 21 CLI tools, 7 dev runtimes **without Visual Studio
  C++ build tools**, and installs the separate su-code (`8sync`) AI harness.
- Every documented verb must actually run — docs are audited against `file:line`, screenshots are
  rendered from real command output.

## Constraints
- **Windows 11 + PowerShell only.** No `Set-StrictMode` (breaks dynamic alias creation); never `exit` in
  the bootstrap (closes the tab); `$ErrorActionPreference = 'Continue'` at script scope stays.
- Guard every tool integration with `Test-CommandExists` — nothing may hard-depend on a missing binary.
- The name `8sync` belongs to su-code; flash-term's user-facing command is always `ft`.
- Never commit generated state: `current-{bg,opacity,style,gpu}.lua`, `.state/`, `bg/`, `fonts/`.
- Visual appearance is stable unless a redesign is explicitly requested.
