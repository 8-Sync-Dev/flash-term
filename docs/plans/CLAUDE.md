# plans/ — Implementation Plans

## Purpose
Detailed, trackable implementation plans for each development sprint.
Each file = one version/sprint. Claude agents read this to understand
what to implement and how to verify it.

## File naming
```
{YYYYMMDD}-{vMAJOR.MINOR.PATCH}-{kebab-slug}.md
```

Examples:
- `20260322-v0.3.0-stability-perf-ux.md`
- `20260401-v0.4.0-integrations.md`

## Structure per plan file
```
# Plan: {version} — {title}
## Goals          what this sprint achieves
## Tasks          ordered checklist with file+function targets
## Verification   how to confirm each task is done
## Commits        filled in as work completes (hash + message)
```

## Rules
- One plan file per sprint / version bump
- Tasks marked `[x]` when commit exists
- Never delete or rewrite history — append only
- English only, max 300 lines

## Index
| File | Version | Status | Summary |
|------|---------|--------|---------|
| `20260322-v0.3.0-stability-perf-ux.md` | v0.3.0 | done | P0-6 PS warn, P1-2 lazy init, P2-4 remote col, P3-1 dispatch refactor, P3-4 keys split |
| `20260322-v0.4.0-gpu-bg-status-docs.md` | v0.4.0 | done | WebGpu, bg rotate, disk in status, troubleshooting doc |
| `20260322-v0.5.0-gpu-clean-security.md` | v0.5.0 | pending | GPU smart adapter, animation_fps=1, deep clean cargo/go/docker, --audit ecosystem, G7 hx health |
