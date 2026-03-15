# WezTerm Config + 8sync Shell Toolkit

A batteries-included WezTerm configuration for Windows 11 with an integrated shell toolkit for tool management, wallpaper switching, and Helix editor configuration.

## Features

- **Catppuccin Mocha** color scheme with acrylic backdrop and background image overlay
- **8sync** — shell toolkit that auto-manages CLI tools via [Scoop](https://scoop.sh)
- **Wallpaper system** — search [Wallhaven](https://wallhaven.cc), pick with fzf, apply live
- **Helix editor management** — theme picker, word-wrap toggle, transparency control, language server install
- **JetBrainsMono Nerd Font** with fallback chain
- **Starship prompt** + zoxide + fzf history search
- **tmux-style leader key** (`Ctrl+a`) for workspace and pane management

## Prerequisites

- [WezTerm](https://wezfurlong.org/wezterm/) (Windows build)
- [Scoop](https://scoop.sh) package manager

## Installation

```powershell
# Clone to WezTerm config directory
git clone https://github.com/8-Sync-Dev/wezterm-config.git "$HOME\.config\wezterm"

# Open WezTerm — 8sync will auto-detect missing tools on first launch
# Then install everything with:
8sync sync
```

## Quick Start

```
8sync help          # Show all commands and aliases
8sync status        # Show installed tools and sync state
8sync sync          # Install/update all managed tools via scoop
```

## Documentation

| Guide | Description |
|---|---|
| [docs/keybindings.md](docs/keybindings.md) | All WezTerm key bindings |
| [docs/8sync-commands.md](docs/8sync-commands.md) | 8sync CLI reference |
| [docs/architecture.md](docs/architecture.md) | How the config files work together |

## Managed Tools

All tools are installed and updated via Scoop with `8sync sync`:

| Tool | Alias | Purpose |
|---|---|---|
| [fzf](https://github.com/junegunn/fzf) | `Ctrl+r` | Fuzzy finder, history search |
| [zoxide](https://github.com/ajeetdsouza/zoxide) | `cdi` | Smart directory jumper |
| [ripgrep](https://github.com/BurntSushi/ripgrep) | `ff` | Fast file search |
| [fd](https://github.com/sharkdp/fd) | — | Fast find alternative |
| [bat](https://github.com/sharkdp/bat) | `catn` | Syntax-highlighted cat |
| [eza](https://github.com/eza-community/eza) | `ll`, `lt` | Modern ls with icons |
| [starship](https://starship.rs) | — | Cross-shell prompt |
| [helix](https://helix-editor.com) | `e` | Terminal editor with LSP |
| [yazi](https://github.com/sxyazi/yazi) | `y` | Terminal file manager |
| [lazygit](https://github.com/jesseduffield/lazygit) | `lg` | Git TUI |
| [delta](https://github.com/dandavison/delta) | `git diff` | Syntax-highlighted diffs |
| [tokei](https://github.com/XAMPPRocky/tokei) | `tokei` | Code line counter |
| [hyperfine](https://github.com/sharkdp/hyperfine) | `hyperfine` | Command benchmarker |
| [dust](https://github.com/bootandy/dust) | `du` | Disk usage visualizer |
| [procs](https://github.com/dalance/procs) | `pss` | Modern process viewer |
| [bottom](https://github.com/ClementTsang/bottom) | `top` | System monitor TUI |

## License

MIT
