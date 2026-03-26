# Reporting Standards

## Status Reporting

All implementation reports should include:

1. **What changed** (files + behavior)
2. **Why it changed** (problem/risk addressed)
3. **How it was verified** (exact command/evidence)

## Verification Expectations

For this repository, use these checks when relevant:

```powershell
# Lua config sanity
wezterm --config-file .\wezterm.lua list-clients

# PowerShell parse check
$null = [System.Management.Automation.Language.Parser]::ParseFile(
  "$PWD\wezterm-bootstrap.ps1", [ref]$null, [ref]$null
)

# Bootstrap dry-runs
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\wezterm-bootstrap.ps1 -Task Hint
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ". .\wezterm-bootstrap.ps1; Show-8SyncStatus"
```

## Documentation Updates

When updating command behavior:

- Update canonical docs first (`docs/guides/20260322-8sync-commands.md`)
- Update indexes (`docs/CLAUDE.md`, subfolder `CLAUDE.md`)
- Mark older docs as legacy if retained for history

## Anti-Patterns

- Do not report “done” without command output evidence.
- Do not keep conflicting docs for the same command behavior.
- Do not add unrelated architecture patterns from other projects.
