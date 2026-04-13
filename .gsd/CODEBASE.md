# Codebase Map

Generated: 2026-04-13T23:48:35Z | Files: 283 | Described: 0/283
<!-- gsd:codebase-meta {"generatedAt":"2026-04-13T23:48:35Z","fingerprint":"12f7f2ece7737494f672b2be7efb616dac9bad16","fileCount":283,"truncated":false} -->

### (root)/
- `_check.ps1`
- `.gitignore`
- `AGENTS.md`
- `CHANGELOG.md`
- `CLAUDE.md`
- `keys.lua`
- `LICENSE`
- `README.md`
- `remove-gsd2-deep.ps1`
- `wezterm-bootstrap.ps1`
- `wezterm.lua`

### docs/
- `docs/CLAUDE.md`
- `docs/gguf-local-gpu-provider.md`

### docs/architecture/
- `docs/architecture/20260320-architecture.md`
- `docs/architecture/20260322-roadmap.md`
- `docs/architecture/CLAUDE.md`

### docs/guides/
- `docs/guides/20260320-8sync-commands.md`
- `docs/guides/20260320-keybindings.md`
- `docs/guides/20260322-8sync-commands.md`
- `docs/guides/20260322-troubleshooting.md`
- `docs/guides/CLAUDE.md`

### docs/plans/
- `docs/plans/20260322-v0.3.0-stability-perf-ux.md`
- `docs/plans/20260322-v0.4.0-gpu-bg-status-docs.md`
- `docs/plans/20260322-v0.5.0-gpu-clean-security.md`
- `docs/plans/CLAUDE.md`

### gguf-config/
- `gguf-config/presets.json`
- `gguf-config/profiles.json`

### gsd-config/
- `gsd-config/PREFERENCES-claude-codex-gemini.md`
- `gsd-config/PREFERENCES-claude-codex-review.md`
- `gsd-config/PREFERENCES-claude-max.md`
- `gsd-config/PREFERENCES-codex-max.md`
- `gsd-config/PREFERENCES-gemini-max.md`
- `gsd-config/PREFERENCES-glm-max.md`
- `gsd-config/PREFERENCES-max.md`
- `gsd-config/PREFERENCES-normal.md`
- `gsd-config/PREFERENCES-pro.md`
- `gsd-config/PREFERENCES.md`

### modules/
- `modules/bg.ps1`
- `modules/clean.ps1`
- `modules/core.ps1`
- `modules/gguf.ps1`
- `modules/gpu.ps1`
- `modules/gsd.ps1`
- `modules/gsd1.ps1`
- `modules/helix.ps1`
- `modules/opencode.ps1`
- `modules/shell.ps1`
- `modules/startup.ps1`
- `modules/sync.ps1`
- `modules/theme.ps1`

### modules/gsd/
- `modules/gsd/00-shared.ps1`
- `modules/gsd/05-plans.ps1`
- `modules/gsd/10-setup.ps1`
- `modules/gsd/20-interactive.ps1`
- `modules/gsd/30-status.ps1`
- `modules/gsd/40-gguf.ps1`
- `modules/gsd/50-command.ps1`

### oc-bundle/
- `oc-bundle/.gitignore`
- `oc-bundle/AGENTS.md`
- `oc-bundle/cache-package.json`
- `oc-bundle/dcp.jsonc`
- `oc-bundle/gsd-file-manifest.json`
- `oc-bundle/opencode.json`
- `oc-bundle/opencode.json.tmp`
- `oc-bundle/package-lock.json`
- `oc-bundle/package.json`
- `oc-bundle/settings.json`
- `oc-bundle/SETUP_GUIDE.md`

### oc-bundle/agents/
- *(25 files: 25 .md)*

### oc-bundle/command/
- *(57 files: 57 .md)*

### oc-bundle/get-shit-done/
- `oc-bundle/get-shit-done/VERSION`

### oc-bundle/get-shit-done/bin/
- `oc-bundle/get-shit-done/bin/gsd-tools.cjs`

### oc-bundle/get-shit-done/commands/gsd/
- `oc-bundle/get-shit-done/commands/gsd/workstreams.md`

### oc-bundle/get-shit-done/references/
- `oc-bundle/get-shit-done/references/checkpoints.md`
- `oc-bundle/get-shit-done/references/continuation-format.md`
- `oc-bundle/get-shit-done/references/decimal-phase-calculation.md`
- `oc-bundle/get-shit-done/references/git-integration.md`
- `oc-bundle/get-shit-done/references/git-planning-commit.md`
- `oc-bundle/get-shit-done/references/model-profile-resolution.md`
- `oc-bundle/get-shit-done/references/model-profiles.md`
- `oc-bundle/get-shit-done/references/phase-argument-parsing.md`
- `oc-bundle/get-shit-done/references/planning-config.md`
- `oc-bundle/get-shit-done/references/questioning.md`
- `oc-bundle/get-shit-done/references/tdd.md`
- `oc-bundle/get-shit-done/references/ui-brand.md`
- `oc-bundle/get-shit-done/references/user-profiling.md`
- `oc-bundle/get-shit-done/references/verification-patterns.md`
- `oc-bundle/get-shit-done/references/workstream-flag.md`

### oc-bundle/get-shit-done/templates/
- *(30 files: 29 .md, 1 .json)*

### oc-bundle/get-shit-done/templates/codebase/
- `oc-bundle/get-shit-done/templates/codebase/architecture.md`
- `oc-bundle/get-shit-done/templates/codebase/concerns.md`
- `oc-bundle/get-shit-done/templates/codebase/conventions.md`
- `oc-bundle/get-shit-done/templates/codebase/integrations.md`
- `oc-bundle/get-shit-done/templates/codebase/stack.md`
- `oc-bundle/get-shit-done/templates/codebase/structure.md`
- `oc-bundle/get-shit-done/templates/codebase/testing.md`

### oc-bundle/get-shit-done/templates/research-project/
- `oc-bundle/get-shit-done/templates/research-project/ARCHITECTURE.md`
- `oc-bundle/get-shit-done/templates/research-project/FEATURES.md`
- `oc-bundle/get-shit-done/templates/research-project/PITFALLS.md`
- `oc-bundle/get-shit-done/templates/research-project/STACK.md`
- `oc-bundle/get-shit-done/templates/research-project/SUMMARY.md`

### oc-bundle/get-shit-done/workflows/
- *(56 files: 56 .md)*

### oc-bundle/hooks/
- `oc-bundle/hooks/gsd-check-update.js`
- `oc-bundle/hooks/gsd-context-monitor.js`
- `oc-bundle/hooks/gsd-prompt-guard.js`
- `oc-bundle/hooks/gsd-statusline.js`
- `oc-bundle/hooks/gsd-workflow-guard.js`

### oc-bundle/instructions/
- `oc-bundle/instructions/context-compaction.md`
- `oc-bundle/instructions/mcp-awareness.md`
- `oc-bundle/instructions/search-maximization.md`

### oc-bundle/plugins/
- `oc-bundle/plugins/anthropic-auth.mjs`
- `oc-bundle/plugins/anthropic-user-agent.mjs`
- `oc-bundle/plugins/login.bat`
- `oc-bundle/plugins/smart-compact.mjs`

### oc-bundle/plugins/plugins/
- `oc-bundle/plugins/plugins/anthropic-auth.mjs`
- `oc-bundle/plugins/plugins/anthropic-user-agent.mjs`

### stable-patches/
- `stable-patches/README.md`

### stable-patches/gsd/
- `stable-patches/gsd/STABLE.md`

### stable-patches/opencode/
- `stable-patches/opencode/STABLE.md`
