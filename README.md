# flash-term

A **WezTerm** terminal configuration + the **`ft`** command for **Windows 11** (PowerShell).
Beautiful out of the box — Catppuccin Mocha, glass presets, Mica backdrop, **purple neon border**,
GPU-aware rendering, a default wallpaper — and a strong command toolkit for tooling bootstrap
and daily terminal helpers.

> **Not an AI harness.** The AI coding harness is a separate project,
> [`su-code`](https://github.com/8-Sync-Dev/su-code), which provides the **`8sync`** command
> (sessions `8sync .`, `8sync ai`, `8sync harness`, `8sync skill`, …). flash-term installs it for
> you via `ft setup` — see [AI coding (su-code)](#ai-coding-su-code) below.

## Features
- **Look** — dark gentle glass (Catppuccin Mocha + Mica), **purple neon border**, **default wallpaper** (`assets/default-bg.jpg`, shipped — set yours with `ft bg set <url>`), git branch in the status bar.
- **WezTerm** — many keybindings (leader `Ctrl+a`, pane splits, tabs, copy mode, command palette).
- **Tool sync** — managed CLI tools (fzf, zoxide, ripgrep, eza, helix, lazygit, …) via Scoop (`ft sync`).
- **Dev runtimes** — `ft dev` bootstraps Node, Python, Go, Rust, Chromium, Docker, Encore with **no Visual Studio** build tools.
- **update-all** — `ft up` updates the config, Scoop tools, and checks WezTerm.
- **Helpers** — backgrounds (Wallhaven/safebooru/yandere), glass themes, GPU policy, deep clean, profiles, GGUF local models, background update notifier.

## Install

**One-liner** (PowerShell `irm`):
```powershell
irm https://8-sync-dev.github.io/flash-term/install.ps1 | iex
```
…or with `curl`:
```sh
curl -fsSL https://raw.githubusercontent.com/8-Sync-Dev/flash-term/main/install.ps1 | pwsh -
```
Re-run either command anytime to **update** flash-term (it pulls `origin/main`).

> The public one-liners need the repo **public** (or reachable). For a **private** checkout use
> `gh repo clone 8-Sync-Dev/flash-term "$env:USERPROFILE\.config\wezterm"` or `git clone`.

**From source:**
```powershell
git clone https://github.com/8-Sync-Dev/flash-term.git "$env:USERPROFILE\.config\wezterm"
```

The one-liner does **full auto-setup**: clones flash-term to `%USERPROFILE%\.config\wezterm`, then
runs `ft setup` — which installs Scoop + WezTerm (if missing), the managed CLI tools, the dev
runtimes, and **su-code** (so the `8sync` AI command is available). Flags: `-ConfigDir <path>`,
`-Update` (pull only, skip setup), `-NoSetup` (config only), `-NoDev` (skip dev runtimes).

## After install

Launch WezTerm (Start Menu → WezTerm). The bootstrap (`wezterm-bootstrap.ps1`) sources on every tab:
PATH, aliases, PSReadLine, and a background update check. Then:
```powershell
ft status          # installed tools + last sync time
ft help            # full command menu
ft autoupdate on   # banner when a new release is available
```

Type `ft help` for the full menu.

## Daily flow

```powershell
ft sync            # install missing + update managed CLI tools
ft up              # update self + scoop tools + wezterm
ft bg pick         # pick a wallpaper (fzf + image preview)
ft theme           # set the glass style/scene
ft dev all         # bootstrap every dev runtime
```

## AI coding (su-code)

flash-term itself has no AI features. For AI coding sessions, install the separate
**su-code** project (run by `ft setup`, or directly):

```powershell
irm https://8-sync-dev.github.io/su-code/install.ps1 | iex
```

Then use the **`8sync`** command it provides:
```powershell
8sync .            # start/resume an AI coding session in this repo
8sync ai "refactor this"   # one-shot prompt
8sync skill list   # manage the skill library
```

See <https://github.com/8-Sync-Dev/su-code> for the full `8sync` surface.

## Keybindings (excerpt)

| Action | Binding |
|---|---|
| Leader | `Ctrl+a` |
| Split right / down | `Ctrl+Shift+\|` / `Ctrl+Shift+_` |
| Navigate panes | `Ctrl+Shift+Arrow` |
| Tabs | `Ctrl+Tab` / `Alt+1..9` |
| Command palette | `Ctrl+Shift+p` or `Leader → x` |
| Copy mode | `Leader → c` |
| Reload config | `Leader → r` |

Full list: `docs/KEYBINDINGS.md`.

## Repository layout

```
wezterm.lua · keys.lua          WezTerm config
wezterm-bootstrap.ps1           shell bootstrap + module loader
install.ps1                     one-liner auto-installer / updater
modules/                        the ft command toolkit (one module per concern)
  core · shell · startup        hint, completer, dispatcher, shell startup
  sync · up                     tool sync + update-all
  setup · dev                   bootstrap + dev runtimes (installs su-code for AI)
  bg · theme · gpu · helix      WezTerm UX commands
  clean · profile · gguf        cleanup, profiles, local models
  autoupdate                    background update + release notifier
gguf-config/                    llama.cpp presets/profiles
assets/                         default wallpaper
```

## License

MIT.
