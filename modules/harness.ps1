# =============================================================================
# 8sync harness -- omp AI coding harness for Windows (port of su-code model)
# =============================================================================
# Usage:
#   8sync .                  Resume the latest omp session in this repo
#   8sync . <name>           Create/resume a NAMED omp session (isolated)
#   8sync ai "<prompt>"      omp one-shot or interactive (add --print for stdout)
#   8sync harness            Deploy skills + project memory + AGENTS.md + readiness
#   8sync harness up         Light refresh (re-deploy skills + consolidate memory)
#   8sync harness global     Deploy skills to ~/.omp (every omp project benefits)
#   8sync harness status     Health: omp, skills, codegraph, MCP, memory
# =============================================================================

# ── omp discovery ────────────────────────────────────────────────────────────

function Find-OmpExe {
    foreach ($name in @('omp', 'omp.exe')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    $local = Join-Path $env:LOCALAPPDATA 'omp\omp.exe'
    if (Test-Path $local) { return $local }
    foreach ($p in @(
        (Join-Path $HOME '.bun\bin\omp.cmd'),
        (Join-Path $HOME 'scoop\shims\omp.exe')
    )) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Get-OmpHome { Join-Path $HOME '.omp' }
function Get-OmpSkillsDir { Join-Path (Get-OmpHome) 'skills' }
function Get-HarnessSessionsRoot { Join-Path $HOME '.8sync\sessions' }

function Get-RepoSlug {
    # Safe directory name for per-project session isolation.
    $cwd = (Get-Location).Path
    $base = Split-Path $cwd -Leaf
    if ([string]::IsNullOrWhiteSpace($base)) { $base = 'default' }
    return ($base -replace '[^A-Za-z0-9._-]', '_')
}

# ── 8sync .  /  8sync ai  -- omp session launcher ───────────────────────────

function Invoke-OmpSession {
    # `8sync .` and `8sync . <name>` -- resume/create an omp session in cwd.
    param([string]$Name)
    $omp = Find-OmpExe
    if (-not $omp) {
        Write-Host '  omp not found.' -ForegroundColor Red
        Write-Host '  Install omp first, then run: 8sync harness' -ForegroundColor DarkGray
        return
    }

    if ($Name) {
        $root = Get-HarnessSessionsRoot
        $dir = Join-Path $root (Join-Path (Get-RepoSlug) ($Name -replace '[^A-Za-z0-9._-]', '_'))
        $null = New-Item -ItemType Directory -Force -Path $dir -ErrorAction SilentlyContinue
        Write-Host ("  omp session [{0}] -> {1}" -f $Name, $dir) -ForegroundColor DarkGray
        & $omp --session-dir="$dir"
    } else {
        Write-Host '  omp: resuming latest session in this repo...' -ForegroundColor DarkGray
        & $omp --continue
    }
}

function Invoke-AiCommand {
    # `8sync ai [prompt]` -- one-shot or interactive. Pass-through model flags.
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Rest
    )
    $omp = Find-OmpExe
    if (-not $omp) {
        Write-Host '  omp not found. Install omp first, then: 8sync harness' -ForegroundColor Red
        return
    }

    $printMode = $Rest -contains '--print' -or $Rest -contains '-p'
    $args = @()
    foreach ($a in $Rest) {
        if ($a -in @('--print', '-p')) { continue }
        $args += $a
    }
    $prompt = ($args -join ' ').Trim()

    if ($printMode) {
        if (-not $prompt) { Write-Host '  --print requires a prompt.' -ForegroundColor DarkYellow; return }
        & $omp -p $prompt
    } elseif ($prompt) {
        & $omp $prompt
    } else {
        Write-Host '  omp: resuming latest session...' -ForegroundColor DarkGray
        & $omp --continue
    }
}

# ── project memory + managed .gitignore ─────────────────────────────────────

function Get-ProjectHarnessDir { Join-Path (Get-Location) '8sync' }

function Get-MemoryTemplate {
    param([string]$Kind)
    switch ($Kind) {
        'PROJECT' {
            return @"
# PROJECT

**One-liner:** _describe this project in one line_

## Tech stack
- _add: language, framework, runtime, package manager_

## Goals
- _what success looks like_

## Constraints
- _hard limits: performance, RAM, OS, deadlines_
"@
        }
        'STATE' {
            return @"
# STATE

**Goal:** _current objective_
**Phase:** _discuss | plan | execute | verify | complete_

## Checklist
- [ ] _step 1_
- [ ] _step 2_

## Current
_where you are right now_

## Next
_the single next concrete action_
"@
        }
        'KNOWLEDGE' {
            return @"
# KNOWLEDGE

Reusable conventions, gotchas, architecture lessons learned while working here.
Append `## YYYY-MM-DD` dated entries. Distill failures (`failure:`) and validated
flows (`validated:`) so future sessions don't repeat them.
"@
        }
    }
    return ''
}

function Initialize-ProjectMemory {
    param([switch]$DryRun)
    $dir = Get-ProjectHarnessDir
    if (-not (Test-Path $dir)) {
        if ($DryRun) { Write-Host "  [dry-run] would create $dir\" -ForegroundColor Yellow; return }
        $null = New-Item -ItemType Directory -Force -Path $dir
    }
    foreach ($kind in @('PROJECT', 'STATE', 'KNOWLEDGE')) {
        $f = Join-Path $dir "$kind.md"
        if (Test-Path $f) {
            Write-Host "  [ok]     8sync/$kind.md exists (kept)" -ForegroundColor DarkGray
        } else {
            if ($DryRun) { Write-Host "  [dry-run] would seed 8sync/$kind.md" -ForegroundColor Yellow; continue }
            [System.IO.File]::WriteAllText($f, (Get-MemoryTemplate -Kind $kind), [System.Text.UTF8Encoding]::new($false))
            Write-Host "  [ok]     seeded 8sync/$kind.md" -ForegroundColor Green
        }
    }
}

function Initialize-ManagedGitignore {
    # Add a managed block to the project .gitignore (idempotent).
    param([switch]$DryRun)
    $gi = Join-Path (Get-Location) '.gitignore'
    $marker = '# ── 8sync harness (managed) ──'
    $block = @"
$marker
.codegraph/
.cache/
8sync/skills/
.env
.env.*
!.env.example
# ── /8sync harness ──
"@
    $existing = if (Test-Path $gi) { Get-Content -Raw $gi } else { '' }
    if ($existing -match [regex]::Escape($marker)) {
        Write-Host '  [ok]     .gitignore: harness block present' -ForegroundColor DarkGray
        return
    }
    if ($DryRun) { Write-Host '  [dry-run] would append harness block to .gitignore' -ForegroundColor Yellow; return }
    $content = if ($existing) { $existing.TrimEnd() + "`n`n" + $block + "`n" } else { $block + "`n" }
    [System.IO.File]::WriteAllText($gi, $content, [System.Text.UTF8Encoding]::new($false))
    Write-Host '  [ok]     .gitignore: harness block added' -ForegroundColor Green
}

# ── codegraph / MCP readiness ───────────────────────────────────────────────

function Get-HarnessReadiness {
    $omp = Find-OmpExe
    $ompVer = if ($omp) { (& $omp --version 2>$null | Select-Object -First 1) } else { 'not installed' }
    $skillsDir = Get-OmpSkillsDir
    $skillCount = if (Test-Path $skillsDir) { @(Get-ChildItem $skillsDir -Directory -ErrorAction SilentlyContinue).Count } else { 0 }
    $codegraph = [bool](Get-Command codegraph -ErrorAction SilentlyContinue)
    $gitleaks  = [bool](Get-Command gitleaks -ErrorAction SilentlyContinue)

    # MCP servers: omp config lists them; detect by config presence.
    $mcpConfig = Join-Path (Get-OmpHome) 'config.yml'
    $mcp = (Test-Path $mcpConfig)

    return [pscustomobject]@{
        Omp         = if ($omp) { $ompVer } else { 'not installed' }
        OmpFound    = [bool]$omp
        SkillsDir   = $skillsDir
        SkillCount  = $skillCount
        Codegraph   = $codegraph
        McpConfig   = $mcp
        Gitleaks    = $gitleaks
    }
}

# ── harness verbs ───────────────────────────────────────────────────────────

function Invoke-HarnessInit {
    param([switch]$DryRun)
    Write-Host '  [1/3] Skills -> ~/.omp/skills ...' -ForegroundColor Cyan
    if (Get-Command Invoke-SkillDeploy -ErrorAction SilentlyContinue) {
        Invoke-SkillDeploy -DryRun:$DryRun
    } else {
        Write-Host '  [skip]   skill deployer not loaded (agents/00-shared)' -ForegroundColor DarkYellow
    }
    Write-Host ''
    Write-Host '  [2/3] Project memory (8sync/) ...' -ForegroundColor Cyan
    Initialize-ProjectMemory -DryRun:$DryRun
    Write-Host ''
    Write-Host '  [3/3] Managed .gitignore ...' -ForegroundColor Cyan
    Initialize-ManagedGitignore -DryRun:$DryRun
    Write-Host ''
    Show-HarnessStatus
}

function Invoke-HarnessUp {
    param([switch]$DryRun)
    if (Get-Command Invoke-SkillDeploy -ErrorAction SilentlyContinue) {
        Invoke-SkillDeploy -DryRun:$DryRun
    }
    # Consolidate KNOWLEDGE.md if large (light touch).
    $k = Join-Path (Get-ProjectHarnessDir) 'KNOWLEDGE.md'
    if (Test-Path $k) {
        $lines = (Get-Content $k -ErrorAction SilentlyContinue | Measure-Object).Count
        if ($lines -gt 200) {
            Write-Host "  [info]   8sync/KNOWLEDGE.md has $lines lines -- consider archiving" -ForegroundColor DarkYellow
        }
    }
    Write-Host '  harness refreshed.' -ForegroundColor Green
}

function Show-HarnessStatus {
    $r = Get-HarnessReadiness
    Write-Host ''
    Write-Host '  8SYNC HARNESS -- readiness' -ForegroundColor Cyan
    Write-Host ''
    $ompColor = if ($r.OmpFound) { 'Green' } else { 'Red' }
    Write-Host ("  omp:        {0}" -f $r.Omp) -ForegroundColor $ompColor
    Write-Host ("  skills:     {0} in {1}" -f $r.SkillCount, $r.SkillsDir) -ForegroundColor DarkGray
    $cgColor = if ($r.Codegraph) { 'Green' } else { 'DarkYellow' }
    Write-Host ("  codegraph:  {0}" -f $(if ($r.Codegraph) { 'available' } else { 'not found (optional)' })) -ForegroundColor $cgColor
    Write-Host ("  mcp config: {0}" -f $(if ($r.McpConfig) { 'present' } else { 'absent (run omp once)' })) -ForegroundColor DarkGray
    Write-Host ("  gitleaks:   {0}" -f $(if ($r.Gitleaks) { 'available' } else { 'not found (optional pre-commit)' })) -ForegroundColor DarkGray

    $mem = Get-ProjectHarnessDir
    if (Test-Path $mem) {
        Write-Host ("  memory:     {0} (PROJECT/STATE/KNOWLEDGE)" -f $mem) -ForegroundColor DarkGray
    } else {
        Write-Host '  memory:     not seeded (run: 8sync harness)' -ForegroundColor DarkYellow
    }
    Write-Host ''
    if (-not $r.OmpFound) {
        Write-Host '  Install omp, then run: 8sync harness' -ForegroundColor Yellow
    } else {
        Write-Host '  Start coding:  8sync .' -ForegroundColor Green
    }
    Write-Host ''
}

function Show-HarnessHelp {
    Write-Host ''
    Write-Host '  8SYNC HARNESS -- omp AI coding harness' -ForegroundColor Cyan
    Write-Host ''
    Write-HintRow '8sync .'               'Resume the latest omp session in this repo'
    Write-HintRow '8sync . <name>'        'Create/resume a NAMED omp session (isolated)'
    Write-HintRow '8sync ai "prompt"'     'omp interactive with a seed prompt'
    Write-HintRow '8sync ai "prompt" -p'  'omp one-shot print mode (non-interactive)'
    Write-HintRow '8sync harness'         'Deploy skills + seed project memory + AGENTS.md + readiness'
    Write-HintRow '8sync harness up'      'Light refresh (re-deploy skills + memory check)'
    Write-HintRow '8sync harness global'  'Deploy skills to ~/.omp (all omp projects benefit)'
    Write-HintRow '8sync harness status'  'Health: omp, skills, codegraph, MCP, memory'
    Write-Host ''
}

function Invoke-HarnessCommand {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Rest
    )
    $sub = if ($Rest -and $Rest.Count -gt 0) { $Rest[0].ToLowerInvariant() } else { '' }
    $dryRun = $Rest -contains '--check' -or $Rest -contains '--dry-run'

    switch ($sub) {
        'init'    { Invoke-HarnessInit -DryRun:$dryRun }
        'up'      { Invoke-HarnessUp -DryRun:$dryRun }
        'global'  {
            Write-Host '  Deploying skills globally to ~/.omp/skills ...' -ForegroundColor Cyan
            if (Get-Command Invoke-SkillDeploy -ErrorAction SilentlyContinue) {
                Invoke-SkillDeploy -DryRun:$dryRun
            }
            Write-Host '  Global deploy done. Every omp run now sees these skills.' -ForegroundColor Green
        }
        'status'  { Show-HarnessStatus }
        'help'    { Show-HarnessHelp }
        default   { Show-HarnessHelp }
    }
}
