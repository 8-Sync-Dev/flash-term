# flash-term

A **WezTerm** terminal configuration + **omp AI coding harness** for Windows 11.
Beautiful out of the box (Catppuccin Mocha, glass presets, Mica backdrop, GPU-aware rendering) and a
strong agent harness on top of [omp](https://github.com/) — the same engine model as
[`su-code`](https://github.com/8-Sync-Dev/su-code), ported to Windows + PowerShell.

## Features

- **WezTerm** — many keybindings (leader `Ctrl+a`, pane splits, tabs, copy mode, command palette).
- **omp harness** — `8sync .` resumes an AI coding session; skills auto-discovered from `~/.omp/skills`.
- **Skill registry** — `8sync skill add/list/update/deploy` manages a portable skill library.
- **update-all** — `8sync up` updates the config, Scoop tools, omp, skills, and checks WezTerm.
- **Project memory** — `8sync harness` seeds `8sync/PROJECT.md`, `STATE.md`, `KNOWLEDGE.md` + a managed `.gitignore`.
- **Tool sync** — managed CLI tools (fzf, zoxide, ripgrep, eza, helix, lazygit, …) via Scoop.
- **Local models** — `8sync gguf` runs llama.cpp presets on your GPU.
- **UX toolkit** — backgrounds (Wallhaven), glass themes, GPU policy, deep clean, profiles.

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

The installer (`install.ps1`) drops flash-term at `%USERPROFILE%\.config\wezterm` (WezTerm's config
dir), detects WezTerm, and is idempotent. Optional flags: `-ConfigDir <path>`, `-Update`.

## After install

Install [WezTerm](https://wezfurlong.org/wezterm/installation) and [Scoop](https://scoop.sh) if missing,
then launch WezTerm. The bootstrap (`wezterm-bootstrap.ps1`) sources on every tab: PATH, aliases,
PSReadLine, and a one-time tool sync (Scoop) in the background. Then deploy the AI harness:
```powershell
8sync up        # update-all: tools + omp + skills + self + wezterm
8sync harness   # deploy skills + seed project memory + readiness check
```

Type `8sync help` for the full menu.

## Daily flow

```powershell
8sync .              # resume the latest omp session in this repo
8sync . feat-login   # a NAMED, isolated session for a feature
8sync ai "refactor this"      # omp one-shot (add -p for stdout)
8sync skill add https://github.com/<owner>/<skill-repo>   # add a skill
8sync up             # update everything (config, tools, omp, skills)
```

## Keybindings (excerpt)

| Action | Binding |
|---|---|
| Leader | `Ctrl+a` |
| Resume omp session | `Leader → .` |
| omp one-shot prompt | `Leader → o` |
| Harness readiness | `Leader → h` |
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
modules/                        the 8sync command toolkit (one module per concern)
  core · shell · startup        hint, completer, dispatcher, shell startup
  sync · up                     tool sync + update-all
  harness · skill · agents/     omp AI harness + skill registry
  bg · theme · gpu · helix      WezTerm UX commands
  clean · profile · gguf        cleanup, profiles, local models
agents/registry.json            skill registry
gguf-config/                    llama.cpp presets/profiles
```

## License

MIT.
