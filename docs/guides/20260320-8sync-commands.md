# 8sync Command Reference

> Legacy snapshot (2026-03-20). For current behavior, use `20260322-8sync-commands.md`.

## General

```
8sync help              Show all commands and aliases
8sync status            Show installed tools and last sync time
8sync sync              Install missing tools + update all via scoop
```

Auto-sync runs in a hidden background process when tools are missing or stale (every 72 hours).

## Background Wallpaper

Search and apply wallpapers from [Wallhaven](https://wallhaven.cc) directly from the terminal.

```
8sync bg search <keywords>    Search Wallhaven for 4K wallpapers
8sync bg pick                 Pick from cached results with fzf
8sync bg set <id|path|url>    Set wallpaper by cache id, local path, or URL
8sync bg open <id>            Open wallpaper page in browser
```

**Flow**: search → pick (or set by id) → wallpaper downloads to `bg/` → `current-bg.lua` updates → WezTerm reloads.

## Helix Editor

```
8sync hx lang [name]          Install language toolchain via scoop (fzf picker)
8sync hx wrap                 Toggle soft word-wrap on/off
8sync hx opacity <+|-|val>    Adjust background transparency (0.0-1.0)
8sync hx theme [name]         Pick Helix color theme (fzf picker)
```

### Supported Languages (`8sync hx lang`)

| Language | Scoop Packages |
|---|---|
| python | python, pyright |
| typescript | nodejs |
| rust | rust, rust-analyzer |
| go | go, gopls |
| lua | lua-language-server |
| c-cpp | llvm |
| zig | zig, zls |
| toml | taplo |
| markdown | marksman |
| java | openjdk |
| csharp | dotnet-sdk |

### Opacity Examples

```
8sync hx opacity          # Show current value
8sync hx opacity +        # Increase by 0.05 (darker)
8sync hx opacity -        # Decrease by 0.05 (more transparent)
8sync hx opacity 0.5      # Set to exact value
```

## Shell Aliases

These aliases are created by the bootstrap and available in every WezTerm tab:

| Alias | Requires | Expands to |
|---|---|---|
| `ll` | eza | `eza --icons=always --group-directories-first -lah` |
| `lt` | eza | `eza --icons=always --group-directories-first -lah --tree --level=2` |
| `y` | yazi | File manager with cd-on-exit |
| `catn` | bat | `bat --paging=never --style=plain` |
| `ff` | rg | `rg --files` |
| `cdi` | zoxide | `z` (zoxide jump) |
| `e` | helix | `hx` |
| `lg` | lazygit | `lazygit` |
| `pss` | procs | `procs` |
| `top` | bottom | `btm` |
| `du` | dust | `dust` |
| `mkcd` | — | Create directory and cd into it |
