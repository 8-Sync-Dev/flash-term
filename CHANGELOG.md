# Changelog

All notable stability-oriented changes for this repo are tracked here.

## [v2026.04.10-stable-1] - 2026-04-10

### Added
- `stable-patches/README.md` to describe the stable patch profile strategy
- `stable-patches/opencode/STABLE.md` documenting the known-good OpenCode recovery flow
- `stable-patches/gsd/STABLE.md` documenting the known-good GSD Anthropic OAuth runtime fix
- `8sync gsd fix` to force-apply the GSD runtime patch without re-running setup
- `--stable` support for the documented stable recovery flows
- runtime patch status to `8sync gsd status`

### Changed
- `8sync opencode reinstall` now purges auth/plugin cache before force re-apply
- `8sync opencode fresh-install` now goes through the reinstall flow so it inherits the same plugin/auth fix path
- `8sync gsd setup` now auto-applies the Anthropic OAuth runtime fix after writing routing
- help text and completion entries now surface the stable repair commands

### Fixed
- OpenCode Claude OAuth recovery path using the plugin-file workaround derived from issue `#145`
- OpenCode bundle/config generation now preserves the working Anthropic auth plugin behavior
- GSD Anthropic OAuth runtime now strips the extra appended system prompt and keeps only the Claude Code identity prefix
- GSD provider label normalization from `anthropic-api` to `anthropic`

### Notes
- Stable recovery commands:
  - `8sync opencode reinstall --stable`
  - `8sync opencode fresh-install --stable --claude=yes --openai=yes`
  - `8sync gsd fix --stable`
  - `8sync gsd setup --model claude+codex --stable`
