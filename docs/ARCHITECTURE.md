# Architecture

## Config loading flow

```
WezTerm start
  └─ wezterm.lua                 reads current-{bg,opacity,style,gpu}.lua, builds config
       └─ default_prog = pwsh -Command ". wezterm-bootstrap.ps1"
            └─ wezterm-bootstrap.ps1
                 ├─ dot-source modules/*.ps1   (defines all 8sync functions)
                 └─ switch ($Task)             Shell | Hint | Status | Sync | BgRotate | CleanLoop
                      └─ Start-WezTermShell (default)
                           ├─ Ensure-PreferredPaths    prepend scoop/shims to PATH
                           ├─ Set-HistoryExperience    PSReadLine + fzf Ctrl+r
                           ├─ Set-ToolAliases          ll, e, lg, y, cdi, 8sync …
                           │    └─ Register-8SyncCompleter
                           └─ Start-AutoSync           hidden bg process if tools stale (72h)
```

## State sharing (Lua ↔ PowerShell)

PowerShell writes small `.lua` files; Lua reads them on reload. After every write, `wezterm cli reload` reapplies the change live.

| File | Writer | Shape |
|---|---|---|
| `current-bg.lua` | `8sync bg set` | `return [[C:\path\to\image.jpg]]` |
| `current-opacity.lua` | `8sync hx opacity` | `return 0.72` |
| `current-style.lua` | `8sync theme` / `8sync bg set` | `return { style=…, scene=…, bg_hint=… }` |
| `current-gpu.lua` | `8sync gpu` | `return { min_percent=…, updated_utc=… }` |

All are gitignored.

## omp AI harness

The harness is omp-centric (single engine), mirroring `su-code`:

- **Skills** live in `~/.omp/skills/<name>/SKILL.md`. omp auto-discovers them; the registry is `agents/registry.json`.
  `8sync skill deploy` clones each registry skill and copies it into `~/.omp/skills`.
- **Sessions** — `8sync .` runs `omp --continue` (resume latest). `8sync . <name>` runs omp with
  `--session-dir=~/.8sync/sessions/<repo>/<name>` for isolated per-feature sessions.
- **Project memory** — `8sync harness` seeds `8sync/{PROJECT,STATE,KNOWLEDGE}.md` and a managed
  `.gitignore` block (ignores `.codegraph/`, `.cache/`, `.env*`, `8sync/skills/`; keeps `8sync/`).
- **AGENTS.md** — `8sync skill deploy` injects an omp-tuned skill-library + memory section into the
  project `AGENTS.md` so omp reads the skill table and project-context rules.

## Readiness check

`8sync harness status` reports: omp version, skill count, codegraph presence, omp config presence,
gitleaks availability, and whether project memory is seeded.

## Tool management

`$script:ToolPackages` lists the managed CLI tools (fzf, zoxide, ripgrep, fd, bat, eza, starship,
helix, yazi, lazygit, delta, tokei, hyperfine, dust, procs, bottom, less). All installed/updated via
Scoop. State persists to `.state/tool-state.json`; `.state/sync.lock` prevents concurrent syncs.
A missing-tools cache (`.state/missing-cache.json`, 5-min TTL) avoids re-scanning on every tab.
