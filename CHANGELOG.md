# Changelog

All notable stability-oriented changes for this repo are tracked here.

## [v2026.04.20-anthropic-restore] - 2026-04-20

### Added
- `8sync gsd local` command suite: project-scoped gsd-pi runtime vendoring
  - `init` scaffold `.gsd/vendor/` layout with README, PATCHES, UPGRADE docs
  - `baseline` seed immutable 2.69.0 snapshot from global or clone upstream tag
  - `add-submodule` add `gsd-build/gsd-2` as submodule at `latest/` for upstream tracking
  - `use <baseline|latest>` seed `current/` from chosen source + auto install + fix
  - `install` run `npm install` inside `current/` (never `-g`)
  - `build` run `npm run build:core` inside `current/`
  - `apply-anthropic-patch` restore Anthropic OAuth removed upstream
  - `fix [--stable]` apply known-good patches to `current/`
  - `enter` / `leave` activate or revert local runtime scope
  - `status` show layout and preferred runtime
  - `setup [--version latest|baseline|X.Y.Z]` one-shot full setup
- `modules/gsd/patches/anthropic-oauth.ts` saved OAuth module source extracted from upstream parent of `c2acb1fb4`
- `modules/gsd/patches/oauth-index-with-anthropic.ts` saved OAuth registry with `anthropicOAuthProvider` re-registered
- `modules/gsd/patches/README.md` documenting the restore procedure

### Fixed
- Anthropic OAuth login restored for gsd-pi >= 2.70.0 where upstream removed the OAuth module for TOS compliance (commit `c2acb1fb4`)
- Local runtime builds correctly from upstream `main` source tree with full workspace package compilation
- OAuth `#145` system prompt fix now applied at source level (`.ts`) so it survives `npm run build:core`
- Provider label `anthropic-api` -> `anthropic` normalized in both baseline and latest runtimes

### Changed
- Global `gsd-pi` install is no longer refreshed by default — requires `--allow-global` on `8sync gsd fix --refresh`
- `Resolve-GsdResourceLoaderTarget` and `Resolve-GsdNodeModulesTarget` now prefer project-local `.gsd/vendor/gsd-pi/current/` before falling back to global
- `.gitignore` excludes `test/` directory so sandbox environments never pollute the config repo

### Safety contract
- No `npm install -g`, no `bun add -g`, no scoop changes from any `local` command
- Global `~/.gsd/agent/` is never touched by local operations
- Sandbox environments under `test/baseline/` and `test/latest/` are fully isolated (own auth.json, DB, sessions, runtime)
- API keys set via `8sync gsd key` remain in Windows User env vars and are intentionally shared across global and local scopes

### Notes
- Verified on Windows 10 with Node 22.14.0
  - `test/baseline/` runs gsd-pi `2.69.0` with OAuth `#145` fix
  - `test/latest/` runs gsd-pi `2.76.0` (upstream `main` at `4c866b677`) with Anthropic OAuth restored + OAuth `#145` fix
  - Global `gsd --version` still returns original pinned install, untouched

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
