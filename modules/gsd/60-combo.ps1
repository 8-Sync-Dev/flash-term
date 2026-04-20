# =============================================================================
# 8sync gsd combo -- curated combos for large-project GSD workflows
#
# A combo is a named recipe that either:
#   (a) applies a model/plan preset (wraps setup --plan / --model), or
#   (b) writes/updates .gsd/PREFERENCES.md with a workflow pattern, or
#   (c) prints a runnable playbook with copy-paste commands.
#
# Usage:
#   8sync gsd combo                     # list all combos
#   8sync gsd combo <name>              # apply
#   8sync gsd combo <name> --help       # detail + example
#   8sync gsd combo <name> --dry-run    # preview without writing
# =============================================================================

$script:GsdComboRegistry = [ordered]@{

    # ── MODEL STACKS ────────────────────────────────────────────────────────
    'claude-max' = @{
        category = 'model'
        summary  = '100% Claude: Opus plan + Sonnet exec + Haiku workers'
        details  = @(
            'Strongest planning + review profile. Uses Anthropic OAuth if available.',
            'Pair with --use-model=opus+sonnet (no Haiku) or sonnet+haiku (budget).'
        )
        example  = '8sync gsd combo claude-max --use-model opus+sonnet'
        handler  = { param($Rest) Invoke-GsdCommand -Rest (@('setup', '--plan', 'claude-max') + $Rest) }
    }
    'codex-max' = @{
        category = 'model'
        summary  = '100% OpenAI: gpt-5.4 plan + gpt-5.3-codex heavy'
        details  = @('Single-ecosystem billing for OpenAI subscribers.')
        example  = '8sync gsd combo codex-max'
        handler  = { param($Rest) Invoke-GsdCommand -Rest (@('setup', '--plan', 'codex-max') + $Rest) }
    }
    'gemini-max' = @{
        category = 'model'
        summary  = '100% Google: gemini-3.1-pro (2M context, free tier)'
        details  = @('Best free option for massive codebases.')
        example  = '8sync gsd combo gemini-max'
        handler  = { param($Rest) Invoke-GsdCommand -Rest (@('setup', '--plan', 'gemini-max') + $Rest) }
    }
    'glm-max' = @{
        category = 'model'
        summary  = '100% ZAI GLM-5.1 -- no OAuth, API key only'
        details  = @('Cheapest quality tier; great for cost-sensitive production.')
        example  = '8sync gsd combo glm-max'
        handler  = { param($Rest) Invoke-GsdCommand -Rest (@('setup', '--plan', 'glm-max') + $Rest) }
    }
    'big-three' = @{
        category = 'model'
        summary  = 'Claude plan + Codex review + Gemini research (best-of-three)'
        details  = @('Top quality, higher cost. Each brand plays to strengths.')
        example  = '8sync gsd combo big-three --dry-run'
        handler  = { param($Rest) Invoke-GsdCommand -Rest (@('setup', '--plan', 'claude-codex-gemini') + $Rest) }
    }
    'cost-saver' = @{
        category = 'model'
        summary  = 'Cost-optimized: Codex plan + GLM exec (-60% vs claude-max)'
        details  = @('Codex handles planning, GLM does bulk exec cheaply.')
        example  = '8sync gsd combo cost-saver'
        handler  = { param($Rest) Invoke-GsdCommand -Rest (@('setup', '--model', 'codex+glm') + $Rest) }
    }
    'no-claude' = @{
        category = 'model'
        summary  = 'Skip Anthropic: Gemini plan + GLM exec + Groq free workers'
        details  = @('For when you cannot or do not want to use Claude.')
        example  = '8sync gsd combo no-claude'
        handler  = { param($Rest) Invoke-GsdCommand -Rest (@('setup', '--plan', 'normal') + $Rest) }
    }
    'review-stack' = @{
        category = 'model'
        summary  = 'Claude codes + Codex reviews (two-LLM quality gate)'
        details  = @(
            'Opus plans, Sonnet executes, Codex validates + writes completion summaries.',
            'Great for high-stakes refactors.'
        )
        example  = '8sync gsd combo review-stack'
        handler  = { param($Rest) Invoke-GsdCommand -Rest (@('setup', '--plan', 'claude-codex-review') + $Rest) }
    }

    # ── WORKFLOW PATTERNS ───────────────────────────────────────────────────
    'upgrade' = @{
        category = 'workflow'
        summary  = 'Migrate an old-GSD project to v2.76 -- ordered steps'
        details  = @(
            'Prints a step-by-step playbook for upgrading:',
            '  - Backup -> install latest gsd-pi -> fix runtime',
            '  - Detect legacy .planning/ -> /gsd migrate to .gsd/',
            '  - Apply PREFERENCES.md 2.76 schema -> re-scan codebase',
            '  - Heal memory/DB with /gsd doctor -> verify with /gsd query',
            'Safe to run on live projects: read-only by default; actions are printed.'
        )
        example  = '8sync gsd combo upgrade'
        handler  = { param($Rest) Invoke-GsdComboUpgrade -Rest $Rest }
    }
    'day-zero' = @{
        category = 'workflow'
        summary  = 'New project: onboarding + scan + PREFERENCES + agent-instructions.md'
        details  = @(
            'Writes .gsd/PREFERENCES.md with worktree + verification + budget.',
            'Creates agent-instructions.md stub at repo root.',
            'Idempotent; use --force to overwrite.'
        )
        example  = '8sync gsd combo day-zero --dry-run'
        handler  = { param($Rest) Invoke-GsdComboDayZero -Rest $Rest }
    }
    'two-terminal' = @{
        category = 'workflow'
        summary  = '2-terminal power workflow: auto in T1, steer from T2'
        details  = @('Prints cheat-sheet; both terminals share .gsd/ on disk.')
        example  = '8sync gsd combo two-terminal'
        handler  = { param($Rest) Invoke-GsdComboPlaybook -Name 'two-terminal' }
    }
    'remote-control' = @{
        category = 'workflow'
        summary  = 'Telegram/Slack/Discord remote control for headless auto-mode'
        details  = @('Setup guide + PREFERENCES snippet + phone commands.')
        example  = '8sync gsd combo remote-control'
        handler  = { param($Rest) Invoke-GsdComboPlaybook -Name 'remote-control' }
    }
    'cost-cap' = @{
        category = 'workflow'
        summary  = 'Budget-locked: cost-saver stack + $ ceiling + graduated downgrade'
        details  = @('Applies codex+glm stack, adds PREFERENCES snippet with ceiling.')
        example  = '8sync gsd combo cost-cap --ceiling 25'
        handler  = { param($Rest) Invoke-GsdComboCostCap -Rest $Rest }
    }
    'team-mode' = @{
        category = 'workflow'
        summary  = 'Team preset: mode=team + unique_milestone_ids + worktree'
        details  = @('Configures for multi-dev collab; shared .gsd/gsd.db memory.')
        example  = '8sync gsd combo team-mode'
        handler  = { param($Rest) Invoke-GsdComboPlaybook -Name 'team-mode' }
    }
    'crash-proof' = @{
        category = 'workflow'
        summary  = 'Long-running safety: worktree + timeouts + crash recovery'
        details  = @('For 2+ day milestones; prints recovery playbook.')
        example  = '8sync gsd combo crash-proof'
        handler  = { param($Rest) Invoke-GsdComboPlaybook -Name 'crash-proof' }
    }
    'parallel' = @{
        category = 'workflow'
        summary  = 'Parallel milestones: multi-worker + per-worker budget'
        details  = @('Adds parallel block; prints spawn commands.')
        example  = '8sync gsd combo parallel --workers 3'
        handler  = { param($Rest) Invoke-GsdComboParallel -Rest $Rest }
    }
    'ci-nightly' = @{
        category = 'workflow'
        summary  = 'GitHub Actions nightly milestone pipeline'
        details  = @('Writes .github/workflows/gsd-nightly.yml; uploads report artifact.')
        example  = '8sync gsd combo ci-nightly --dry-run'
        handler  = { param($Rest) Invoke-GsdComboCiNightly -Rest $Rest }
    }
    'quick-promote' = @{
        category = 'workflow'
        summary  = 'Rapid prototyping: /gsd-quick -> /gsd-spike -> /gsd-sketch -> promote'
        details  = @('Full quick->full promotion recipe.')
        example  = '8sync gsd combo quick-promote'
        handler  = { param($Rest) Invoke-GsdComboPlaybook -Name 'quick-promote' }
    }
    'memory-sync' = @{
        category = 'workflow'
        summary  = 'Cross-project memory: export/import with scope+tag'
        details  = @('Consolidate memories, commit, seed another project.')
        example  = '8sync gsd combo memory-sync'
        handler  = { param($Rest) Invoke-GsdComboPlaybook -Name 'memory-sync' }
    }
    'karpathy' = @{
        category = 'workflow'
        summary  = "Inject Andrej Karpathy's Claude Code guidelines into project"
        details  = @(
            'Downloads CLAUDE.md from forrestchang/andrej-karpathy-skills (raw GitHub).',
            'Writes marker-delimited sections into:',
            '  - agent-instructions.md    (GSD loads into every agent session)',
            '  - .gsd/KNOWLEDGE.md        (long-term memory, survives context reset)',
            '  - .claude/CLAUDE.md        (Claude Code runtime, if using claude-code)',
            'Markers: <!-- KARPATHY:BEGIN --> ... <!-- KARPATHY:END -->',
            'Re-run replaces section in-place (no duplication).',
            'Cached at ~/.gsd/cache/karpathy-CLAUDE.md for offline use.',
            '',
            'Four principles injected:',
            '  1. Goal-Driven Execution (success criteria + verification loops)',
            '  2. Stay on task (no unrelated changes)',
            '  3. Manage uncertainty (ask, surface tradeoffs, push back)',
            '  4. Keep code simple (no bloat, clean up dead code)'
        )
        example  = '8sync gsd combo karpathy'
        handler  = { param($Rest) Invoke-GsdComboKarpathy -Rest $Rest }
    }

    # ── META ────────────────────────────────────────────────────────────────
    'list' = @{
        category = 'meta'
        summary  = 'List all combos grouped by category'
        details  = @()
        example  = '8sync gsd combo list'
        handler  = { param($Rest) Show-GsdComboList }
    }
    'help' = @{
        category = 'meta'
        summary  = 'Show combo help (pass name for detail)'
        details  = @()
        example  = '8sync gsd combo help upgrade'
        handler  = { param($Rest) Show-GsdComboHelp -Rest $Rest }
    }
}

# ---------------------------------------------------------------------------
# Dispatcher
# ---------------------------------------------------------------------------

function Invoke-GsdCombo {
    param([string[]]$Rest = @())

    if ($Rest.Count -eq 0) { Show-GsdComboList; return }

    $name = $Rest[0].ToLowerInvariant()
    $tail = if ($Rest.Count -gt 1) { $Rest | Select-Object -Skip 1 } else { @() }

    if ($name -in @('-h', '--help') -and $tail.Count -eq 0) { Show-GsdComboHelp; return }
    if ($tail -contains '--help' -or $tail -contains '-h') {
        Show-GsdComboDetail -Name $name
        return
    }

    if ($script:GsdComboRegistry.Contains($name)) {
        $combo = $script:GsdComboRegistry[$name]
        & $combo.handler $tail
    } else {
        Write-Host ''
        Write-Host "  [combo] Unknown: '$name'. Run '8sync gsd combo list'." -ForegroundColor Red
        Write-Host ''
    }
}

function Show-GsdComboList {
    Write-Host ''
    Write-HintSection 'GSD Combos -- curated recipes for large projects'
    Write-Host ''

    $groups = [ordered]@{
        'workflow' = 'Workflow patterns (playbooks + config writers)'
        'model'    = 'Model stacks (wrap setup --plan / --model)'
        'meta'     = 'Meta'
    }

    foreach ($cat in $groups.Keys) {
        Write-Host ("  " + $groups[$cat]) -ForegroundColor Cyan
        foreach ($key in $script:GsdComboRegistry.Keys) {
            $c = $script:GsdComboRegistry[$key]
            if ($c.category -ne $cat) { continue }
            Write-Host ("    {0,-16} {1}" -f $key, $c.summary) -ForegroundColor White
        }
        Write-Host ''
    }

    Write-Host '  Usage:' -ForegroundColor DarkGray
    Write-Host '    8sync gsd combo <name>              Apply' -ForegroundColor DarkGray
    Write-Host '    8sync gsd combo <name> --help       Detail + example' -ForegroundColor DarkGray
    Write-Host '    8sync gsd combo <name> --dry-run    Preview' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  First time on an old project? Run: 8sync gsd combo upgrade' -ForegroundColor Yellow
    Write-Host ''
}

function Show-GsdComboHelp {
    param([string[]]$Rest = @())
    if ($Rest.Count -ge 1) { Show-GsdComboDetail -Name $Rest[0]; return }
    Show-GsdComboList
}

function Show-GsdComboDetail {
    param([string]$Name)
    $key = $Name.ToLowerInvariant()
    if (-not $script:GsdComboRegistry.Contains($key)) {
        Write-Host ''
        Write-Host "  [combo] Unknown: '$Name'" -ForegroundColor Red
        Write-Host ''
        return
    }
    $c = $script:GsdComboRegistry[$key]
    Write-Host ''
    Write-Host "  === combo: $key  [$($c.category)] ===" -ForegroundColor Magenta
    Write-Host ''
    Write-Host "  $($c.summary)" -ForegroundColor White
    Write-Host ''
    if ($c.details.Count -gt 0) {
        Write-Host '  Details:' -ForegroundColor Cyan
        foreach ($line in $c.details) { Write-Host "    $line" -ForegroundColor DarkGray }
        Write-Host ''
    }
    Write-Host '  Example:' -ForegroundColor Cyan
    Write-Host "    $($c.example)" -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  Common flags:    --dry-run    --force    --help' -ForegroundColor DarkGray
    Write-Host ''
}

# ---------------------------------------------------------------------------
# Combo: upgrade (migrate old GSD project -> 2.76)
# ---------------------------------------------------------------------------

function Invoke-GsdComboUpgrade {
    param([string[]]$Rest = @())

    $repoRoot = (Get-Location).Path
    $hasLegacy = Test-Path (Join-Path $repoRoot '.planning')
    $hasGsd = Test-Path (Join-Path $repoRoot '.gsd')

    Write-Host ''
    Write-HintSection 'Combo upgrade -- migrate old GSD project to v2.76'
    Write-Host ''
    Write-Host "  Repo: $repoRoot" -ForegroundColor DarkGray
    $legacyMark = if ($hasLegacy) { 'YES' } else { 'no' }
    $gsdMark = if ($hasGsd) { 'YES' } else { 'no' }
    Write-Host ("  .planning/ (v1): {0}" -f $legacyMark) -ForegroundColor DarkGray
    Write-Host ("  .gsd/      (v2): {0}" -f $gsdMark) -ForegroundColor DarkGray
    Write-Host ''

    Write-Host '  === RECOMMENDED ORDER ===' -ForegroundColor Magenta
    Write-Host ''

    Write-Host '  1. BACKUP (always first)' -ForegroundColor Cyan
    Write-Host '     git add -A && git commit -m "chore: snapshot before GSD upgrade"' -ForegroundColor DarkGray
    Write-Host '     git tag pre-gsd-upgrade' -ForegroundColor DarkGray
    Write-Host '     # If .gsd/ exists, also backup the DB:' -ForegroundColor DarkGray
    Write-Host '     cp .gsd/gsd.db .gsd/gsd.db.bak 2>/dev/null' -ForegroundColor DarkGray
    Write-Host ''

    Write-Host '  2. UPGRADE RUNTIME' -ForegroundColor Cyan
    Write-Host '     npm install -g gsd-pi@latest       # now 2.76.x' -ForegroundColor DarkGray
    Write-Host '     gsd --version                       # verify >= 2.76' -ForegroundColor DarkGray
    Write-Host '     8sync gsd fix                       # repair ~/.gsd/agent' -ForegroundColor DarkGray
    Write-Host '     8sync gsd fix --refresh             # refresh local runtime' -ForegroundColor DarkGray
    Write-Host ''

    Write-Host '  3. REAUTH PROVIDERS' -ForegroundColor Cyan
    Write-Host '     gsd                                  # open TUI' -ForegroundColor DarkGray
    Write-Host '     /login                               # re-OAuth Anthropic if needed' -ForegroundColor DarkGray
    Write-Host '     /gsd onboarding                      # re-check provider + keys' -ForegroundColor DarkGray
    Write-Host '     8sync gsd status                     # outside TUI: verify routing' -ForegroundColor DarkGray
    Write-Host ''

    if ($hasLegacy -and -not $hasGsd) {
        Write-Host '  4. MIGRATE .planning/ -> .gsd/ (YOU HAVE LEGACY V1 DATA)' -ForegroundColor Cyan
        Write-Host '     # In GSD TUI:' -ForegroundColor DarkGray
        Write-Host '     /gsd migrate                         # parse .planning/ -> .gsd/' -ForegroundColor DarkGray
        Write-Host '     #   Maps: phases -> slices, plans -> tasks, milestones -> milestones' -ForegroundColor DarkGray
        Write-Host '     #   Preserves completion state and summaries.' -ForegroundColor DarkGray
        Write-Host ''
    } elseif ($hasGsd) {
        Write-Host '  4. (SKIP -- .gsd/ already present; no v1 migration needed)' -ForegroundColor DarkGray
        Write-Host ''
    } else {
        Write-Host '  4. (SKIP -- no .planning/ legacy data)' -ForegroundColor DarkGray
        Write-Host ''
    }

    Write-Host '  5. APPLY 2.76 PREFERENCES SCHEMA' -ForegroundColor Cyan
    Write-Host '     8sync gsd combo day-zero --force     # writes .gsd/PREFERENCES.md' -ForegroundColor DarkGray
    Write-Host '     # Then edit to taste -- new 2.76 fields:' -ForegroundColor DarkGray
    Write-Host '     #   planning.sketch_first, planning.escalation_rollback' -ForegroundColor DarkGray
    Write-Host '     #   unique_milestone_ids, crash_recovery, auto_report' -ForegroundColor DarkGray
    Write-Host ''

    Write-Host '  6. PICK A MODEL STACK (or keep current)' -ForegroundColor Cyan
    Write-Host '     8sync gsd combo claude-max           # or codex-max / gemini-max / cost-saver' -ForegroundColor DarkGray
    Write-Host '     8sync gsd combo list                 # see all options' -ForegroundColor DarkGray
    Write-Host ''

    Write-Host '  7. REBUILD CODEBASE INTEL' -ForegroundColor Cyan
    Write-Host '     # In GSD TUI:' -ForegroundColor DarkGray
    Write-Host '     /gsd language vi                     # persistent language pref (2.76)' -ForegroundColor DarkGray
    Write-Host '     /gsd scan                            # writes .gsd/codebase/SCAN-*.md' -ForegroundColor DarkGray
    Write-Host '     /gsd doctor                          # heal legacy task arrays + STATE.md' -ForegroundColor DarkGray
    Write-Host '     /gsd changelog                       # browse LLM-summarized release notes' -ForegroundColor DarkGray
    Write-Host ''

    Write-Host '  8. VERIFY HEALTH' -ForegroundColor Cyan
    Write-Host '     /gsd query                           # JSON snapshot; must show valid phase' -ForegroundColor DarkGray
    Write-Host '     /gsd status                          # progress + provider + cost' -ForegroundColor DarkGray
    Write-Host '     /gsd viz                             # visualizer: progress/DAG/metrics' -ForegroundColor DarkGray
    Write-Host ''

    Write-Host '  9. RESUME WORK (option A -- existing milestone)' -ForegroundColor Cyan
    Write-Host '     /gsd auto                            # picks up from STATE.md, fresh context' -ForegroundColor DarkGray
    Write-Host ''

    Write-Host '  9. START FRESH (option B -- new milestone on upgraded repo)' -ForegroundColor Cyan
    Write-Host '     /gsd new-milestone                   # sketch-then-refine (2.76 ADR-011)' -ForegroundColor DarkGray
    Write-Host '     /gsd auto' -ForegroundColor DarkGray
    Write-Host ''

    Write-Host '  10. (OPTIONAL) LAYER ADVANCED COMBOS' -ForegroundColor Cyan
    Write-Host '     8sync gsd combo crash-proof          # for multi-day milestones' -ForegroundColor DarkGray
    Write-Host '     8sync gsd combo team-mode            # if 3+ devs on repo' -ForegroundColor DarkGray
    Write-Host '     8sync gsd combo cost-cap --ceiling 25' -ForegroundColor DarkGray
    Write-Host '     8sync gsd combo remote-control       # Telegram for off-hours runs' -ForegroundColor DarkGray
    Write-Host '     8sync gsd combo ci-nightly           # GitHub Actions integration' -ForegroundColor DarkGray
    Write-Host ''

    Write-Host '  === ROLLBACK (if something breaks) ===' -ForegroundColor Magenta
    Write-Host '    git reset --hard pre-gsd-upgrade' -ForegroundColor DarkGray
    Write-Host '    cp .gsd/gsd.db.bak .gsd/gsd.db' -ForegroundColor DarkGray
    Write-Host '    npm install -g gsd-pi@<previous-version>' -ForegroundColor DarkGray
    Write-Host ''
}

# ---------------------------------------------------------------------------
# Combo: day-zero (new project)
# ---------------------------------------------------------------------------

function Invoke-GsdComboDayZero {
    param([string[]]$Rest = @())
    $dryRun = $Rest -contains '--dry-run'
    $force  = $Rest -contains '--force'

    $repoRoot = (Get-Location).Path
    $gsdDir = Join-Path $repoRoot '.gsd'
    $prefsPath = Join-Path $gsdDir 'PREFERENCES.md'
    $instructionsPath = Join-Path $repoRoot 'agent-instructions.md'

    $prefsYaml = @'
---
version: 1
mode: team
token_profile: balanced

git:
  isolation: worktree
  main_branch: main

unique_milestone_ids: true
crash_recovery: true

auto_supervisor:
  soft_timeout_minutes: 20
  idle_timeout_minutes: 10
  hard_timeout_minutes: 30
  budget_ceiling: 50.00

verification_commands:
  - npm run lint
  - npm run typecheck
  - npm test
verification_auto_fix: true
verification_max_retries: 3

auto_report: true

planning:
  sketch_first: true
  escalation_rollback: true

skill_discovery: suggest
---
'@

    $instructionsStub = @'
# Agent Instructions

## Coding Standards
- (Fill in: language, strict mode, formatting rules)

## Architecture
- (Fill in: layers, allowed import directions, key boundaries)

## Domain Terms
- (Fill in: project-specific vocabulary)

## Workflow Preferences
- Conventional Commits, PR per slice, review before merge.
'@

    Write-Host ''
    Write-HintSection 'Combo day-zero -- prepare repo for pro GSD'
    Write-Host ''
    Write-Host ("  Will write: {0}" -f $prefsPath) -ForegroundColor DarkGray
    Write-Host ("  Will write: {0}" -f $instructionsPath) -ForegroundColor DarkGray
    Write-Host ''

    if ($dryRun) {
        Write-Host '  [dry-run] PREFERENCES.md:' -ForegroundColor Yellow
        Write-Host $prefsYaml -ForegroundColor DarkGray
        Write-Host ''
        Write-Host '  [dry-run] agent-instructions.md:' -ForegroundColor Yellow
        Write-Host $instructionsStub -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    if (-not (Test-Path $gsdDir)) { New-Item -ItemType Directory -Path $gsdDir -Force | Out-Null }

    if ((Test-Path $prefsPath) -and -not $force) {
        Write-Host "  [skip] $prefsPath exists (use --force)" -ForegroundColor DarkYellow
    } else {
        Set-Content -Path $prefsPath -Value $prefsYaml -Encoding UTF8 -Force
        Write-Host "  [ok] wrote PREFERENCES.md" -ForegroundColor Green
    }

    if ((Test-Path $instructionsPath) -and -not $force) {
        Write-Host "  [skip] $instructionsPath exists (use --force)" -ForegroundColor DarkYellow
    } else {
        Set-Content -Path $instructionsPath -Value $instructionsStub -Encoding UTF8 -Force
        Write-Host "  [ok] wrote agent-instructions.md" -ForegroundColor Green
    }

    Write-Host ''
    Write-Host '  Next: gsd ; /gsd language vi ; /gsd scan ; /gsd new-milestone' -ForegroundColor Cyan
    Write-Host ''
}

# ---------------------------------------------------------------------------
# Combo: cost-cap
# ---------------------------------------------------------------------------

function Invoke-GsdComboCostCap {
    param([string[]]$Rest = @())
    $dryRun = $Rest -contains '--dry-run'
    $ceilingIdx = [Array]::IndexOf($Rest, '--ceiling')
    $ceiling = if ($ceilingIdx -ge 0 -and $ceilingIdx + 1 -lt $Rest.Count) { $Rest[$ceilingIdx + 1] } else { '25.00' }

    Write-Host ''
    Write-HintSection "Combo cost-cap -- budget ceiling `$$ceiling + cost-saver stack"
    Write-Host ''

    if (-not $dryRun) {
        Invoke-GsdCommand -Rest @('setup', '--model', 'codex+glm')
    }

    Write-Host '  Add to PREFERENCES.md:' -ForegroundColor Cyan
    Write-Host "    token_profile: budget" -ForegroundColor DarkGray
    Write-Host "    auto_supervisor:" -ForegroundColor DarkGray
    Write-Host "      budget_ceiling: $ceiling" -ForegroundColor DarkGray
    Write-Host "      graduated_downgrade:" -ForegroundColor DarkGray
    Write-Host "        - at_percent: 50; action: warn" -ForegroundColor DarkGray
    Write-Host "        - at_percent: 75; action: downgrade_execution" -ForegroundColor DarkGray
    Write-Host "        - at_percent: 90; action: downgrade_all_except_planning" -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  Monitor: /gsd status | /gsd viz | gsd headless --json status' -ForegroundColor Cyan
    Write-Host ''
}

# ---------------------------------------------------------------------------
# Combo: parallel
# ---------------------------------------------------------------------------

function Invoke-GsdComboParallel {
    param([string[]]$Rest = @())
    $workersIdx = [Array]::IndexOf($Rest, '--workers')
    $workers = if ($workersIdx -ge 0 -and $workersIdx + 1 -lt $Rest.Count) { [int]$Rest[$workersIdx + 1] } else { 3 }

    Write-Host ''
    Write-HintSection "Combo parallel -- $workers workers for independent milestones"
    Write-Host ''
    Write-Host '  Add to PREFERENCES.md:' -ForegroundColor Cyan
    Write-Host "    parallel:" -ForegroundColor DarkGray
    Write-Host "      enabled: true" -ForegroundColor DarkGray
    Write-Host "      max_workers: $workers" -ForegroundColor DarkGray
    Write-Host "      budget_cap_per_worker: 20.00" -ForegroundColor DarkGray
    Write-Host "      ipc_dir: .gsd/parallel" -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  Spawn (independent milestones only):' -ForegroundColor Cyan
    for ($i = 1; $i -le $workers; $i++) {
        Write-Host ("    gsd headless dispatch M00{0} --worker-id w{1} &" -f ($i + 1), $i) -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Host '  Monitor: gsd headless --json status --all-workers' -ForegroundColor Cyan
    Write-Host ''
}

# ---------------------------------------------------------------------------
# Combo: ci-nightly
# ---------------------------------------------------------------------------

function Invoke-GsdComboCiNightly {
    param([string[]]$Rest = @())
    $dryRun = $Rest -contains '--dry-run'
    $force  = $Rest -contains '--force'
    $workflowDir = Join-Path (Get-Location).Path '.github/workflows'
    $workflowPath = Join-Path $workflowDir 'gsd-nightly.yml'

    $yaml = @'
name: GSD Nightly Milestone
on:
  schedule:
    - cron: '0 2 * * *'
  workflow_dispatch:

jobs:
  gsd-auto:
    runs-on: ubuntu-latest
    timeout-minutes: 180
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 22

      - name: Install GSD
        run: npm install -g gsd-pi

      - name: Run milestone headless
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
        run: |
          gsd headless --timeout 7200000 --answers answers-ci.json
        continue-on-error: true

      - name: Upload HTML report
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: gsd-report
          path: .gsd/reports/

      - name: Notify on block
        if: failure()
        run: |
          STATUS=$(gsd headless --json status | jq -r '.blocked_reason // "unknown"')
          echo "::warning::GSD blocked: $STATUS"
'@

    Write-Host ''
    Write-HintSection 'Combo ci-nightly -- GitHub Actions nightly milestone'
    Write-Host ''
    Write-Host ("  Will write: {0}" -f $workflowPath) -ForegroundColor DarkGray
    Write-Host ''

    if ($dryRun) {
        Write-Host '  [dry-run]' -ForegroundColor Yellow
        Write-Host $yaml -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    if (-not (Test-Path $workflowDir)) { New-Item -ItemType Directory -Path $workflowDir -Force | Out-Null }
    if ((Test-Path $workflowPath) -and -not $force) {
        Write-Host "  [skip] $workflowPath exists (use --force)" -ForegroundColor DarkYellow
    } else {
        Set-Content -Path $workflowPath -Value $yaml -Encoding UTF8 -Force
        Write-Host "  [ok] wrote $workflowPath" -ForegroundColor Green
    }

    Write-Host ''
    Write-Host '  Next:' -ForegroundColor Cyan
    Write-Host '    1. Add ANTHROPIC_API_KEY to repo secrets' -ForegroundColor DarkGray
    Write-Host '    2. Create answers-ci.json with pre-answered ask_user_questions' -ForegroundColor DarkGray
    Write-Host '    3. Commit + push; runs 2am UTC daily' -ForegroundColor DarkGray
    Write-Host ''
}

# ---------------------------------------------------------------------------
# Combo: generic playbook renderer
# ---------------------------------------------------------------------------

function Invoke-GsdComboPlaybook {
    param([string]$Name)

    $playbooks = @{
        'two-terminal' = @{
            title = '2-Terminal Power Workflow'
            body  = @(
                '  TERMINAL 1 -- executor:',
                '    gsd',
                '    /gsd language vi',
                '    /gsd new-milestone',
                '    /gsd auto',
                '',
                '  TERMINAL 2 -- steering (same repo):',
                '    gsd',
                '    /gsd discuss            # architecture while T1 runs',
                '    /gsd status             # text progress',
                '    /gsd query              # JSON snapshot (~50ms, no LLM)',
                '    /gsd viz                # visualizer: progress/DAG/metrics',
                '    /gsd queue M002         # queue next milestone',
                '    /gsd capture "..."      # fire-and-forget idea',
                '    /gsd steer              # hard-edit plan',
                '',
                '  Both terminals share .gsd/ on disk.',
                '  T2 changes picked up at next phase boundary -- no stop needed.'
            )
        }
        'remote-control' = @{
            title = 'Remote Control via Telegram'
            body  = @(
                '  1. Create Telegram bot via @BotFather, copy token',
                '  2. Get chat ID: https://api.telegram.org/bot<TOKEN>/getUpdates',
                '  3. TUI: /gsd prefs -> Remote -> Telegram',
                '     OR edit ~/.gsd/PREFERENCES.md:',
                '       remote:',
                '         telegram:',
                '           bot_token: "123:ABC..."',
                '           chat_id: "YOUR_ID"',
                '',
                '  4. Run on server:',
                '     gsd headless --timeout 86400000',
                '',
                '  5. From phone Telegram:',
                '     /status  /pause  /resume  /next  /query',
                '',
                '  ask_user_questions bounce to Telegram -> answer on phone.'
            )
        }
        'team-mode' = @{
            title = 'Team Collaboration Mode'
            body  = @(
                '  .gsd/PREFERENCES.md (commit to git, shared):',
                '    mode: team',
                '    unique_milestone_ids: true   # M001-abc123',
                '    git:',
                '      isolation: worktree',
                '      main_branch: main',
                '',
                '  Per-dev workflow:',
                '    git pull',
                '    gsd                          # picks free milestone',
                '    /gsd queue M00X --assignee <dev>',
                '',
                '  Sync memory (end of sprint):',
                '    (in chat) "consolidate memories tagged=sprint-14"',
                '    git add .gsd/gsd.db .gsd/KNOWLEDGE.md',
                '    git commit -m "chore(memory): sprint-14" && git push'
            )
        }
        'crash-proof' = @{
            title = 'Crash-Proof Long-Running Milestone'
            body  = @(
                '  PREFERENCES.md:',
                '    git.isolation: worktree',
                '    auto_supervisor:',
                '      hard_timeout_minutes: 60',
                '    crash_recovery: true',
                '    auto_report: true',
                '',
                '  Run inside persistent session (tmux/screen/wezterm):',
                '    wezterm start -- gsd',
                '    /gsd auto',
                '',
                '  On crash (SSH/reboot/rate-limit):',
                '    ssh server && cd project && gsd',
                '    /gsd auto       # auto-recovers from lock file',
                '    /gsd doctor     # heal dispatch warnings',
                '    /gsd forensics  # full debugger if doctor insufficient',
                '',
                '  Headless auto-restart (3x exponential backoff):',
                '    gsd headless --timeout 172800000   # 48h'
            )
        }
        'quick-promote' = @{
            title = 'Rapid Prototype -> Milestone Promotion'
            body  = @(
                '  Phase 1 (spike, < 1h):',
                '    /gsd-quick "add dark mode toggle"',
                '    /gsd-quick "rate limiter POC" --research',
                '',
                '  Phase 2 (explore options):',
                '    /gsd-spike "redis vs in-memory rate limit"',
                '    /gsd-sketch "2-3 HTML mockups for dark mode"',
                '',
                '  Phase 3 (promote):',
                '    /gsd new-milestone --from-quick 001',
                '    /gsd auto',
                '',
                '  Spike/sketch artifacts become planner context automatically.'
            )
        }
        'memory-sync' = @{
            title = 'Cross-Project Memory Sync'
            body  = @(
                '  Project A -- hint agent to capture:',
                '    (chat) "capture pattern: zod runtime validation, tag=validation,api"',
                '    (chat) "capture gotcha: Next.js 15 params must await, tag=nextjs"',
                '',
                '  Export (Phase 5):',
                '    (chat) "memory export with tag=validation" -> JSON',
                '    # or copy DB:',
                '    cp .gsd/gsd.db ../project-B/.gsd/gsd.db',
                '',
                '  Import in project B:',
                '    cd ../project-B && gsd',
                '    (chat) "import memories from /path/export.json, scope=global"',
                '',
                '  Commit for team:',
                '    git add .gsd/gsd.db .gsd/KNOWLEDGE.md && git commit -m "chore(memory): sync"'
            )
        }
    }

    if (-not $playbooks.ContainsKey($Name)) {
        Write-Host "  [combo] No playbook: $Name" -ForegroundColor Red
        return
    }
    $pb = $playbooks[$Name]
    Write-Host ''
    Write-HintSection ("Combo $Name -- " + $pb.title)
    Write-Host ''
    foreach ($line in $pb.body) { Write-Host $line -ForegroundColor DarkGray }
    Write-Host ''
}

# ---------------------------------------------------------------------------
# Combo: karpathy -- inject andrej-karpathy-skills CLAUDE.md into project
# ---------------------------------------------------------------------------

$script:GsdKarpathyUrl = 'https://raw.githubusercontent.com/forrestchang/andrej-karpathy-skills/main/CLAUDE.md'
$script:GsdKarpathyBeginMarker = '<!-- KARPATHY:BEGIN -->'
$script:GsdKarpathyEndMarker = '<!-- KARPATHY:END -->'

function Invoke-GsdComboKarpathy {
    param([string[]]$Rest = @())
    $dryRun = $Rest -contains '--dry-run'
    $update = $Rest -contains '--update' -or $Rest -contains '--refresh'
    $remove = $Rest -contains '--remove' -or $Rest -contains '--uninstall'

    $repoRoot = (Get-Location).Path
    $cacheDir = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.gsd/cache'
    $cachePath = Join-Path $cacheDir 'karpathy-CLAUDE.md'

    $targets = @(
        [pscustomobject]@{ Path = Join-Path $repoRoot 'agent-instructions.md'; Label = 'agent-instructions.md'; EnsureHeader = $true },
        [pscustomobject]@{ Path = Join-Path $repoRoot '.gsd/KNOWLEDGE.md';     Label = '.gsd/KNOWLEDGE.md';     EnsureHeader = $true },
        [pscustomobject]@{ Path = Join-Path $repoRoot '.claude/CLAUDE.md';     Label = '.claude/CLAUDE.md';     EnsureHeader = $true }
    )

    Write-Host ''
    Write-HintSection 'Combo karpathy -- inject Karpathy Claude Code guidelines'
    Write-Host ''
    Write-Host ("  Repo:     {0}" -f $repoRoot) -ForegroundColor DarkGray
    Write-Host ("  Source:   {0}" -f $script:GsdKarpathyUrl) -ForegroundColor DarkGray
    Write-Host ("  Cache:    {0}" -f $cachePath) -ForegroundColor DarkGray
    Write-Host ''

    if ($remove) {
        Write-Host '  Removing karpathy sections from all targets...' -ForegroundColor Yellow
        foreach ($t in $targets) {
            if (-not (Test-Path $t.Path)) { continue }
            $content = Get-Content $t.Path -Raw -Encoding UTF8
            $stripped = Remove-GsdKarpathySection -Content $content
            if ($content -ne $stripped) {
                if (-not $dryRun) { Set-Content -Path $t.Path -Value $stripped -Encoding UTF8 -Force }
                Write-Host ("    [{0}] removed from {1}" -f (if ($dryRun) { 'dry-run' } else { 'ok' }), $t.Label) -ForegroundColor Green
            } else {
                Write-Host ("    [skip] no karpathy section in {0}" -f $t.Label) -ForegroundColor DarkGray
            }
        }
        Write-Host ''
        return
    }

    # Get content (cache first unless --update)
    $karpathyContent = $null
    $usedCache = $false

    if (-not $update -and (Test-Path $cachePath)) {
        Write-Host '  [cache] using cached CLAUDE.md (pass --update to refresh)' -ForegroundColor DarkGray
        $karpathyContent = Get-Content $cachePath -Raw -Encoding UTF8
        $usedCache = $true
    }

    if (-not $karpathyContent) {
        Write-Host '  [fetch] downloading from GitHub...' -ForegroundColor Cyan
        try {
            $karpathyContent = (Invoke-WebRequest -Uri $script:GsdKarpathyUrl -UseBasicParsing -TimeoutSec 15).Content
            if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
            Set-Content -Path $cachePath -Value $karpathyContent -Encoding UTF8 -Force
            Write-Host '  [ok]    cached' -ForegroundColor Green
        } catch {
            Write-Host ("  [err]   download failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
            if (Test-Path $cachePath) {
                Write-Host '  [fallback] using stale cache' -ForegroundColor Yellow
                $karpathyContent = Get-Content $cachePath -Raw -Encoding UTF8
                $usedCache = $true
            } else {
                Write-Host '  [fatal] no cache available, aborting' -ForegroundColor Red
                Write-Host ''
                return
            }
        }
    }

    $section = Build-GsdKarpathySection -Content $karpathyContent -FromCache:$usedCache

    if ($dryRun) {
        Write-Host ''
        Write-Host '  [dry-run] section preview (first 30 lines):' -ForegroundColor Yellow
        ($section -split "`n" | Select-Object -First 30) | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
        Write-Host '    ...' -ForegroundColor DarkGray
        Write-Host ''
        Write-Host '  [dry-run] targets that would be updated:' -ForegroundColor Yellow
        foreach ($t in $targets) { Write-Host ("    {0}" -f $t.Path) -ForegroundColor DarkGray }
        Write-Host ''
        return
    }

    foreach ($t in $targets) {
        $dir = Split-Path $t.Path -Parent
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

        $existing = if (Test-Path $t.Path) { Get-Content $t.Path -Raw -Encoding UTF8 } else { '' }
        $newContent = Write-GsdKarpathySection -Existing $existing -Section $section -Header $t.Label
        Set-Content -Path $t.Path -Value $newContent -Encoding UTF8 -Force
        $verb = if ($existing -match [regex]::Escape($script:GsdKarpathyBeginMarker)) { 'updated' } else { 'injected' }
        Write-Host ("  [ok] {0} {1}" -f $verb, $t.Label) -ForegroundColor Green
    }

    Write-Host ''
    Write-Host '  Next steps:' -ForegroundColor Cyan
    Write-Host '    - GSD will auto-load agent-instructions.md into every session.' -ForegroundColor DarkGray
    Write-Host '    - Claude Code reads .claude/CLAUDE.md on session start.' -ForegroundColor DarkGray
    Write-Host '    - .gsd/KNOWLEDGE.md survives context reset and /new.' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  Commit the files so teammates/CI share the guidelines:' -ForegroundColor Cyan
    Write-Host '    git add agent-instructions.md .gsd/KNOWLEDGE.md .claude/CLAUDE.md' -ForegroundColor DarkGray
    Write-Host '    git commit -m "chore(agent): inject karpathy guidelines"' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  Flags: --update (re-download)  --remove (strip sections)  --dry-run (preview)' -ForegroundColor DarkGray
    Write-Host ''
}

function Build-GsdKarpathySection {
    param([string]$Content, [switch]$FromCache)
    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm')
    $src = if ($FromCache) { '(cached) ' + $script:GsdKarpathyUrl } else { $script:GsdKarpathyUrl }
    $header = @"
$script:GsdKarpathyBeginMarker
<!-- Source: $src -->
<!-- Injected: $stamp by 8sync gsd combo karpathy -->
<!-- Re-run '8sync gsd combo karpathy --update' to refresh -->
<!-- Re-run '8sync gsd combo karpathy --remove' to strip -->

## Karpathy Guidelines (auto-injected)

> These four principles improve Claude Code / any LLM agent behavior.
> Based on Andrej Karpathy's observations on LLM coding pitfalls.

"@
    return $header + $Content.TrimEnd() + "`n`n" + $script:GsdKarpathyEndMarker + "`n"
}

function Write-GsdKarpathySection {
    param([string]$Existing, [string]$Section, [string]$Header)

    $beginEsc = [regex]::Escape($script:GsdKarpathyBeginMarker)
    $endEsc = [regex]::Escape($script:GsdKarpathyEndMarker)
    $pattern = "(?ms)" + $beginEsc + ".*?" + $endEsc + "\r?\n?"

    if ($Existing -match $pattern) {
        return [regex]::Replace($Existing, $pattern, $Section)
    }

    if ([string]::IsNullOrWhiteSpace($Existing)) {
        $titleFile = Split-Path $Header -Leaf
        $preface = "# $titleFile`n`nProject-specific guidance for AI coding agents.`n`n"
        return $preface + $Section
    }

    $sep = if ($Existing.EndsWith("`n")) { "`n" } else { "`n`n" }
    return $Existing.TrimEnd() + $sep + "`n" + $Section
}

function Remove-GsdKarpathySection {
    param([string]$Content)
    $beginEsc = [regex]::Escape($script:GsdKarpathyBeginMarker)
    $endEsc = [regex]::Escape($script:GsdKarpathyEndMarker)
    $pattern = "(?ms)\r?\n?" + $beginEsc + ".*?" + $endEsc + "\r?\n?"
    return [regex]::Replace($Content, $pattern, "`n")
}
