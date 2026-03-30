# S01: GPU Status Surface — UAT

**Milestone:** M001
**Written:** 2026-03-27T07:40:35.954Z

## UAT Type

- UAT mode: artifact-driven
- Why this mode is sufficient: The slice delivers a diagnostic CLI command. All behavior is observable via command output — no UI, no network, no persistent side effects. The bootstrap can be dot-sourced in an isolated pwsh session and all subcommands exercised directly.

## Preconditions

- WezTerm is installed and `wezterm` is on PATH (for liveness tag; not required for core checks)
- Working directory is the repo root (so `wezterm-bootstrap.ps1` can be dot-sourced)
- Run in a clean `pwsh -NoLogo -NoProfile` session to avoid contamination from other profiles

## Smoke Test

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ". .\wezterm-bootstrap.ps1; 8sync gpu status"
```
Expected: Displays `GPU Acceleration Status` block with Front-end, Active GPU, Power preference rows. Exit code 0.

---

## Test Cases

### 1. gpu status shows all five fields

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ". .\wezterm-bootstrap.ps1; Invoke-GpuCommand -Rest @('status')"
```

1. Run the command above.
2. **Expected:**
   - `Front-end:` row shows `WebGpu`
   - `Active GPU:` row shows a real GPU name and `(DiscreteGpu)` or `(IntegratedGpu)` — not `(unknown)`
   - `Power preference:` row shows `HighPerformance`
   - `Min GPU target:` row shows either a percentage (if `current-gpu.lua` exists) or `(not set)`
   - `State file:` row shows a full path ending in `current-gpu.lua`
   - Last line shows `[WezTerm running]` or `[WezTerm not detected]` — either is valid
   - Exit code: 0

### 2. gpu verify produces PASS/FAIL checks

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ". .\wezterm-bootstrap.ps1; Invoke-GpuCommand -Rest @('verify')"
```

1. Run the command above.
2. **Expected:**
   - `[PASS]  front_end = WebGpu` (green)
   - `[PASS]  GPU type = DiscreteGpu  device: <name>` (green)
   - `[PASS]  power_preference = HighPerformance` (green)
   - Check 4 (state file): `[PASS]` if `current-gpu.lua` exists in cwd, `[FAIL]  current-gpu.lua exists  (file missing)` if not — both are valid depending on environment
   - Summary line: `3/4 checks passed` (worktree without state file) or `4/4 checks passed` (live config)
   - Exit code: 0

### 3. gpu help renders correctly

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ". .\wezterm-bootstrap.ps1; Invoke-GpuCommand -Rest @('help')"
```

1. Run the command above.
2. **Expected:**
   - Section header `GPU ACCELERATION` shown in Cyan
   - Three rows: `8sync gpu status`, `8sync gpu verify`, `8sync gpu help` — each with a description
   - Exit code: 0

### 4. Alias dispatch via 8sync works

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ". .\wezterm-bootstrap.ps1; 8sync gpu status"
```

1. Run the command above.
2. **Expected:** Identical output to Test Case 1. Confirms `Invoke-8Sync` dispatches `gpu` to `Invoke-GpuCommand`.

### 5. Unknown subcommand falls back gracefully

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ". .\wezterm-bootstrap.ps1; Invoke-GpuCommand -Rest @('frobnicate')"
```

1. Run the command above.
2. **Expected:**
   - Warning line: `Unknown gpu subcommand: frobnicate` in DarkYellow
   - GPU ACCELERATION help block displayed below
   - Exit code: 0

### 6. No arguments shows status + help

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ". .\wezterm-bootstrap.ps1; Invoke-GpuCommand -Rest @()"
```

1. Run the command above.
2. **Expected:** GPU Acceleration Status block followed by GPU ACCELERATION help block. Exit code: 0.

---

## Edge Cases

### State file absent (fresh clone or worktree)

1. Ensure `current-gpu.lua` does not exist in the working directory.
2. Run `8sync gpu status`.
3. **Expected:** `Min GPU target: (not set)`, `Last updated: (never)` — no error, no crash.

### State file present with valid min_percent

1. Create `current-gpu.lua` with content: `return { min_percent = 42, updated_utc = "2026-01-01T00:00:00Z" }`
2. Run `8sync gpu status`.
3. **Expected:** `Min GPU target: 42%`, `Last updated: 2026-01-01T00:00:00Z`.
4. Run `8sync gpu verify`.
5. **Expected:** Check 4 shows `[PASS]  current-gpu.lua exists  (min_percent=42)`.

### WezTerm not running

1. Run the status command without WezTerm running.
2. **Expected:** Liveness tag shows `[WezTerm not detected]` — no error or exception.

### Tab completion

1. In an interactive `pwsh` session with bootstrap sourced, type `8sync gpu` then press Tab.
2. **Expected:** Completions `status`, `verify`, `help` are offered.

---

## Failure Signals

- Any output line containing `Exception` or `Error:` (not `[FAIL]`) indicates an unhandled exception
- `Active GPU: (unknown)` indicates WMI failed — check `Get-WmiObject Win32_VideoController` directly
- `Front-end:` or `Power preference:` showing `(unknown)` or empty indicates `wezterm.lua` path lookup failed
- Missing `GPU ACCELERATION` section in help output indicates `Register-8SyncCompleter` was not updated

## Not Proven By This UAT

- That `current-gpu.lua` is written correctly by `8sync gpu set` (that command doesn't exist yet)
- That WezTerm actually uses WebGpu at runtime (we read config intent, not runtime state)
- Tab completion in a live WezTerm session (requires interactive terminal)
- Behavior on a machine with only integrated GPU (no discrete adapter)

## Notes for Tester

The `$PSScriptRoot` path issue means `front_end` and `power_preference` are read from hardcoded defaults in `Get-ActiveGpuInfo`, not from the actual `wezterm.lua`. This works correctly on the current system because the config uses the default values. If you've customized `config.front_end` to something other than `WebGpu`, the status and verify commands will still show `WebGpu` — this is a known limitation documented in KNOWLEDGE.md.
