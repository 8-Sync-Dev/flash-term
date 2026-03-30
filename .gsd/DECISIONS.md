# Decisions

## D001 — GPU data source: Win32_VideoController WMI instead of wezterm CLI
**Scope:** architecture
**Made by:** agent
**Context:** M001 / S01 / T01

`wezterm cli list-clients` returns mux client metadata only (pane IDs, tab titles) — it has no GPU enumeration capability. `Get-WmiObject Win32_VideoController` is always available on Windows without a running WezTerm instance and reliably returns all GPU adapters.

**Choice:** Use `Win32_VideoController` WMI for GPU name/type detection.

---

## D002 — front_end / power_preference sourced from wezterm.lua config, not runtime CLI
**Scope:** architecture
**Made by:** agent
**Context:** M001 / S01 / T01

WezTerm has no CLI command to introspect the active renderer at runtime. `wezterm.lua` is always present and is the authoritative source for `config.front_end` and `config.webgpu_power_preference`. Regex parsing is fast and reliable.

**Choice:** Parse `wezterm.lua` with regex for `front_end` and `power_preference`.

---

## D003 — WezTerm liveness tag is informational only, not a hard requirement
**Scope:** architecture
**Made by:** agent
**Context:** M001 / S01 / T01

`8sync gpu status` should work whether or not WezTerm is currently running. The liveness probe (`wezterm cli list-clients --format json`) adds a `[WezTerm running]` / `[WezTerm not detected]` tag for user awareness, but a failed probe is not an error condition.

**Choice:** WezTerm liveness is displayed as an informational tag only.

---

## Decisions Table

| # | When | Scope | Decision | Choice | Rationale | Revisable? | Made By |
|---|------|-------|----------|--------|-----------|------------|---------|
| D001 | M001 / S03 / T01 | architecture | WezTerm reload mechanism for bg set | Use wezterm cli list-clients as liveness probe only; rely on WezTerm file-watcher for actual config reload | wezterm CLI has no reload/reload-configuration subcommand. WezTerm automatically reloads config via file-watcher when Lua state files are written. list-clients confirms WezTerm is running so we can print "Config reloaded." confidently; if it fails, print the manual Ctrl+Shift+R hint instead. | Yes | agent |
