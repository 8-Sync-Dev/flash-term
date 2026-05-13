# =============================================================================
# 8sync agents max-skill -- deploy skill suite to Forge, GSD, Claude Code
# =============================================================================
# Usage:
#   8sync agents max-skill [--dry-run] [--skip-token-save] [--only <name>]
#   8sync agents list
#   8sync agents check
# =============================================================================

function Get-ForceLoadSkillContent {
    # Returns the content of the master force-load skill written to
    # ~/.forge/skills/00-force-load.md (prefix 00 = loaded first alphabetically).
    param([object[]]$Registry)

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('# 00 -- Force Load Skills  (managed by 8sync agents max-skill)')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('## MANDATORY RULE')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('**Before starting ANY non-trivial task you MUST:**')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('1. Read `.forge/skills/karpathy-guidelines/SKILL.md` -- no exceptions')
    [void]$sb.AppendLine('2. Identify the task type from the table below')
    [void]$sb.AppendLine('3. Read all skills listed for that type before writing code')
    [void]$sb.AppendLine('4. For GSD work, use memory/token tools before broad reads: `memory_query`, `gsd_resume`, `gsd_exec`, `gsd_exec_search`, `capture_thought`')
    [void]$sb.AppendLine('5. Never dump huge tool output into context; summarize first, then read narrow slices')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('## Skill Selection Guide')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('| Task type | Skills to read (in order) |')
    [void]$sb.AppendLine('|---|---|')
    [void]$sb.AppendLine('| Any coding task | **karpathy-guidelines** (always first, always mandatory) |')
    $hasGsd = [bool]($Registry | Where-Object { $_.name -eq 'gsd-pi-guide' })
    if ($hasGsd) {
        [void]$sb.AppendLine('| GSD workflow / auto mode | karpathy + **gsd-pi-guide** + GSD memory/token discipline below |')
        [void]$sb.AppendLine('| Large repo / broad analysis | Use `gsd_exec` to summarize, then read only narrow file slices |')
    }
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('## Installed Skills')
    [void]$sb.AppendLine()

    foreach ($skill in $Registry | Sort-Object { [int]($_.priority) }) {
        $mandatory = if ($skill.mandatory) { ' **(MANDATORY)**' } else { '' }
        [void]$sb.AppendLine(('- `{0}`{1} -- {2}' -f $skill.dir, $mandatory, $skill.use_when))
    }

    if ($hasGsd) {
        [void]$sb.AppendLine()
        [void]$sb.AppendLine('## GSD memory/token discipline')
        [void]$sb.AppendLine()
        [void]$sb.AppendLine('Use these tools before broad reads or repeated rediscovery:')
        [void]$sb.AppendLine()
        [void]$sb.AppendLine('- `gsd_resume` after compaction/session resume')
        [void]$sb.AppendLine('- `memory_query` before re-reading history')
        [void]$sb.AppendLine('- `gsd_exec` for multi-file analysis or large command output')
        [void]$sb.AppendLine('- `gsd_exec_search` before rerunning expensive analysis')
        [void]$sb.AppendLine('- `capture_thought` for reusable conventions, gotchas, and architecture lessons')
        [void]$sb.AppendLine('- `gsd_graph` when memory relationships matter')
        [void]$sb.AppendLine('- GSD status/summary tools instead of raw DB or huge artifact reads')
        [void]$sb.AppendLine()
        [void]$sb.AppendLine('Never dump large tool output into context. Summarize first, then read narrow slices.')
    }
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('## Never skip karpathy-guidelines')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('If unsure which skills apply, at minimum read karpathy-guidelines.')
    [void]$sb.AppendLine('Karpathy overrides any habit of jumping straight to implementation.')

    return $sb.ToString()
}

function Get-AgentsMdSection {
    # Returns the agents max-skill section to inject into AGENTS.md (GSD/Claude Code).
    # Deep-references .gsd/* project state files so agents understand the project structure.
    param([object[]]$Registry)

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('<!-- agents:max-skill:start -- managed by 8sync agents max-skill -->')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('## Agent Skill Library (8sync max-skill)')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('**Rule:** Before any non-trivial task, read karpathy-guidelines first.')
    [void]$sb.AppendLine('Then select additional skills by task type. These rules apply to GSD, Claude Code, Forge, and all project agents that read this file.')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('| Task type | Skills |')
    [void]$sb.AppendLine('|---|---|')
    [void]$sb.AppendLine('| Any coding | `agents/skills/karpathy-guidelines/` (mandatory, always first) |')
    $hasGsd = [bool]($Registry | Where-Object { $_.name -eq 'gsd-pi-guide' })
    if ($hasGsd) {
        [void]$sb.AppendLine('| GSD workflow | + `agents/skills/gsd-pi-guide/` and the GSD memory/token rules below |')
        [void]$sb.AppendLine('| Large repo analysis | Use `gsd_exec`/`gsd_exec_search` before reading many files |')
    }
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('### Skill Registry')
    [void]$sb.AppendLine()

    foreach ($skill in $Registry | Sort-Object { [int]($_.priority) }) {
        $mandatory = if ($skill.mandatory) { ' **(mandatory)**' } else { '' }
        $urlLabel  = if ($skill.url -eq 'built-in' -or $skill.url -eq 'local') { $skill.url } else { $skill.url }
        [void]$sb.AppendLine(('- **{0}**{1}: {2}  ' -f $skill.display, $mandatory, $skill.use_when))
        [void]$sb.AppendLine(('  Ref: {0}' -f $urlLabel))
    }

    # ---- Deep .gsd/* project context injection (only when gsd-pi-guide is registered) ----
    if ($hasGsd) {
        [void]$sb.AppendLine()
        [void]$sb.AppendLine('### GSD Project Context (auto-injected)')
        [void]$sb.AppendLine()
        [void]$sb.AppendLine('When working in a GSD-enabled project, these files contain critical project state.')
        [void]$sb.AppendLine('**Read the relevant file BEFORE making decisions** that depend on project context.')
        [void]$sb.AppendLine()
        [void]$sb.AppendLine('| File | What it contains | When to read |')
        [void]$sb.AppendLine('|---|---|---|')
        [void]$sb.AppendLine('| `.gsd/PROJECT.md` | Project name, tech stack, goals, constraints | Start of any session |')
        [void]$sb.AppendLine('| `.gsd/CONTEXT.md` | Current milestone, active slice, recent decisions | Before planning or coding |')
        [void]$sb.AppendLine('| `.gsd/STATE.md` | Workflow state machine position, phase, blockers | Before any `/gsd` command |')
        [void]$sb.AppendLine('| `.gsd/CODEBASE.md` | Auto-generated codebase map (modules, entry points) | When navigating unfamiliar code |')
        [void]$sb.AppendLine('| `.gsd/DECISIONS.md` | Architecture decisions log (ADRs) | Before proposing arch changes |')
        [void]$sb.AppendLine('| `.gsd/KNOWLEDGE.md` | Learned patterns, gotchas, team conventions | Before writing new code |')
        [void]$sb.AppendLine('| `.gsd/PREFERENCES.md` | User coding style, tool preferences, review standards | Always (style compliance) |')
        [void]$sb.AppendLine('| `.gsd/milestones/M*/` | Milestone roadmaps, slice breakdowns, validation criteria | When planning or reviewing scope |')
        [void]$sb.AppendLine()
        [void]$sb.AppendLine('**Priority order:** PROJECT.md > CONTEXT.md > STATE.md > others as needed.')
        [void]$sb.AppendLine()
        [void]$sb.AppendLine('### GSD Memory and Token Optimization Rules')
        [void]$sb.AppendLine()
        [void]$sb.AppendLine('These rules are mandatory on large projects or long sessions:')
        [void]$sb.AppendLine()
        [void]$sb.AppendLine('1. Use `gsd_resume` immediately after compaction/session resume when context may be stale.')
        [void]$sb.AppendLine('2. Use `memory_query` before re-reading broad project history or prior decisions.')
        [void]$sb.AppendLine('3. Use `gsd_exec` for analysis that would read more than 3 files or produce large output; log summaries, not raw dumps.')
        [void]$sb.AppendLine('4. Use `gsd_exec_search` before rerunning expensive analysis.')
        [void]$sb.AppendLine('5. Use `capture_thought` only for reusable project knowledge, conventions, gotchas, and architectural lessons.')
        [void]$sb.AppendLine('6. Use `gsd_graph` when a memory relationship matters instead of rediscovering context manually.')
        [void]$sb.AppendLine('7. Prefer GSD summaries and status tools over raw DB/file spelunking: `gsd_milestone_status`, `gsd_journal_query`, `gsd_summary_save`.')
        [void]$sb.AppendLine('8. Prefer `rtk read`, `rtk grep`, and `rtk git` for shell/file output when available.')
        [void]$sb.AppendLine('9. Never dump huge tool output into the model context. Summarize first, then read narrow slices with offsets/limits.')
        [void]$sb.AppendLine()
        [void]$sb.AppendLine('### GSD Workflow Reference')
        [void]$sb.AppendLine()
        [void]$sb.AppendLine('Read `agents/skills/gsd-pi-guide/SKILL.md` for the full GSD 2 CLI reference.')
        [void]$sb.AppendLine('Key commands: `/gsd start`, `/gsd plan`, `/gsd auto`, `/gsd status`, `/gsd cost`.')
        [void]$sb.AppendLine('GSD uses a state machine: discuss > plan > execute > verify > complete.')
        [void]$sb.AppendLine('Never skip phases. Always verify before marking complete.')
    }
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('<!-- agents:max-skill:end -->')

    return $sb.ToString()
}

function Write-ForceLoadSkill {
    param([object[]]$Registry, [switch]$DryRun)

    $forgeSkills = Get-ForgeGlobalSkillsDir
    $target      = Join-Path $forgeSkills '00-force-load.md'
    $content     = Get-ForceLoadSkillContent -Registry $Registry

    if ($DryRun) {
        Write-Host ('  [dry-run] Would write {0}' -f $target) -ForegroundColor Yellow
        return
    }

    if (-not (Test-Path $forgeSkills)) {
        $null = New-Item -Path $forgeSkills -ItemType Directory -Force
    }

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($target, $content, $utf8NoBom)
    Write-Host ('  [ok]     Wrote ~/.forge/skills/00-force-load.md') -ForegroundColor Green
}

function Write-AgentsMdSection {
    # Inject/update the max-skill section in project AGENTS.md + ~/.claude/AGENTS.md
    param([object[]]$Registry, [switch]$DryRun, [string]$TargetPath)

    if (-not $TargetPath) { $TargetPath = Join-Path (Get-Location) 'AGENTS.md' }

    $section  = Get-AgentsMdSection -Registry $Registry
    $startTag = '<!-- agents:max-skill:start'
    $endTag   = '<!-- agents:max-skill:end -->'

    if ($DryRun) {
        Write-Host ('  [dry-run] Would update {0}' -f $TargetPath) -ForegroundColor Yellow
        return
    }

    $existing = ''
    if (Test-Path $TargetPath) {
        try { $existing = [System.IO.File]::ReadAllText($TargetPath) } catch {}
    }

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)

    if ($existing -match [regex]::Escape($startTag)) {
        # Replace existing section
        $pattern = [regex]::Escape($startTag) + '[\s\S]*?' + [regex]::Escape($endTag) + '(\r?\n)?'
        $updated = [regex]::Replace($existing, $pattern, $section)
        [System.IO.File]::WriteAllText($TargetPath, $updated, $utf8NoBom)
        Write-Host ('  [ok]     Updated max-skill section in {0}' -f (Split-Path $TargetPath -Leaf)) -ForegroundColor Green
    } else {
        # Append
        $newContent = $existing.TrimEnd() + "`n`n" + $section
        [System.IO.File]::WriteAllText($TargetPath, $newContent, $utf8NoBom)
        Write-Host ('  [ok]     Appended max-skill section to {0}' -f (Split-Path $TargetPath -Leaf)) -ForegroundColor Green
    }
}

function Install-AgentSkillEntry {
    # Install a single skill from the registry into agents/skills/ and deploy to Forge.
    param([object]$Skill, [switch]$DryRun)

    $name    = $skill.name
    $url     = $skill.url
    $dir     = $skill.dir
    $display = $skill.display

    Write-Host ("  [{0,-2}] {1}" -f $skill.priority, $display) -ForegroundColor Cyan

    # Built-in rtk skill -- handled by token-save command
    if ($skill.builtin -and $name -eq 'rtk-token-save') {
        $rtkSkill = Join-Path (Get-ForgeGlobalSkillsDir) 'rtk-token-save'
        if (Test-Path $rtkSkill) {
            Write-Host '       Already present (written by token-save).' -ForegroundColor DarkGray
        } else {
            Write-Host '       Run 8sync gsd token-save --forge-full to install.' -ForegroundColor DarkGray
        }
        return $true
    }

    # Karpathy built-in: check if already deployed
    if ($skill.builtin -and $name -eq 'karpathy') {
        $target = Join-Path (Get-AgentInstallRoot) $dir
        $forgeTarget = Join-Path (Get-ForgeGlobalSkillsDir) $dir
        if (Test-Path $forgeTarget) {
            Write-Host '       Already deployed to ~/.forge/skills/.' -ForegroundColor Green
            if (-not (Test-Path $target) -and (Test-Path $forgeTarget)) {
                if (-not $DryRun) {
                    $parentDir = Split-Path $target -Parent
                    if (-not (Test-Path $parentDir)) { $null = New-Item -Path $parentDir -ItemType Directory -Force }
                    Copy-Item $forgeTarget $target -Recurse -Force
                }
            }
            return $true
        }
        # Fall through to clone path
    }

    if ($url -eq 'built-in') {
        Write-Host '       built-in, skipping.' -ForegroundColor DarkGray
        return $true
    }

    # Fetch type: local or git
    $fetchType = if ($skill.PSObject.Properties['fetch_type']) { $skill.fetch_type } else { 'git' }
    $localDir  = $null

    if ($fetchType -eq 'local') {
        # Copy a local file (e.g. gsd-pi README.md) into agents/skills/<dir>/
        $localSource = $skill.local_source
        $configRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
        $sourcePath = Join-Path $configRoot $localSource
        # Fallback: try baseline path if current symlink missing
        if (-not (Test-Path $sourcePath)) {
            $sourcePath = Join-Path $configRoot ($localSource -replace '/current/', '/baseline-*/') | Resolve-Path -ErrorAction SilentlyContinue | Select-Object -Last 1
        }
        if ($sourcePath -and (Test-Path $sourcePath)) {
            $installDir = Join-Path (Get-AgentInstallRoot) $dir
            if (-not $DryRun) {
                if (-not (Test-Path $installDir)) {
                    $null = New-Item -Path $installDir -ItemType Directory -Force
                }
                $destFile = Join-Path $installDir 'SKILL.md'
                Copy-Item $sourcePath $destFile -Force
                Write-Host ('  [ok]     Copied {0} -> SKILL.md' -f (Split-Path $sourcePath -Leaf)) -ForegroundColor Green
            }
            $localDir = $installDir
        } else {
            Write-Host ('  [warn]   Local source not found: {0}' -f $localSource) -ForegroundColor DarkYellow
        }
    } else {
        $localDir = Clone-SkillRepo -Url $url -Dir $dir -DryRun:$DryRun
    }

    if ($localDir -or $DryRun) {
        $deploySource = if ($localDir) { $localDir } else { Join-Path (Get-AgentInstallRoot) $dir }
        Deploy-SkillToForge -SourceDir $deploySource -SkillDir $dir -DryRun:$DryRun
        return $true
    }
    return $false
}

function Invoke-AgentProjectSkill {
    param(
        [switch]$DryRun,
        [string]$Only
    )

    Write-Host ''
    Write-Host '  8SYNC AGENTS -- PROJECT SKILLS' -ForegroundColor Cyan
    Write-Host '  Installs skill rules only into the current project (AGENTS.md + CLAUDE.md).' -ForegroundColor DarkGray
    Write-Host ''

    $registry = Get-AgentSkillRegistry
    $toInstall = if ($Only) { $registry | Where-Object { $_.name -eq $Only } } else { $registry }

    Write-Host '  [1/2] Installing project-local skills...' -ForegroundColor Cyan
    $ok = 0; $fail = 0
    foreach ($skill in @($toInstall | Sort-Object { [int]($_.priority) })) {
        $result = Install-AgentSkillEntry -Skill $skill -DryRun:$DryRun
        if ($result) { $ok++ } else { $fail++ }
    }
    Write-Host ("`n  Installed: {0} skills{1}" -f $ok, $(if ($fail) { ", $fail failed" } else { '' })) -ForegroundColor $(if ($fail) { 'DarkYellow' } else { 'Green' })
    Write-Host ''

    Write-Host '  [2/2] Updating project instruction files...' -ForegroundColor Cyan
    Write-AgentsMdSection -Registry $registry -DryRun:$DryRun -TargetPath (Join-Path (Get-Location) 'AGENTS.md')
    Write-AgentsMdSection -Registry $registry -DryRun:$DryRun -TargetPath (Join-Path (Get-Location) 'CLAUDE.md')
    Write-Host ''
    Write-Host '  Done. Project AGENTS.md and CLAUDE.md now force skill + memory/token discipline.' -ForegroundColor Cyan
    Write-Host ''
}

function Invoke-AgentMaxSkill {
    param(
        [switch]$DryRun,
        [switch]$SkipTokenSave,
        [string]$Only   # install only this skill name
    )

    Write-Host ''
    Write-Host '  8SYNC AGENTS -- MAX-SKILL' -ForegroundColor Cyan
    Write-Host '  Deploys skill suite to Forge, GSD project, and Claude Code.' -ForegroundColor DarkGray
    Write-Host ''

    $registry = Get-AgentSkillRegistry

    # ---- Step 1: Token save (RTK for Claude Code + Forge) ---------------
    Write-Host '  [1/4] Token optimizer (RTK + Forge full)...' -ForegroundColor Cyan
    if ($SkipTokenSave) {
        Write-Host '  [skip]   --skip-token-save passed.' -ForegroundColor DarkGray
    } else {
        # Only install rtk + hook, skip shims (they intercept ALL processes and break npm/cargo)
        Invoke-GsdTokenSave -DryRun:$DryRun -SkipAuthFix -SkipEnv
    }
    Write-Host ''

    # ---- Step 2: Install skills into agents/skills/ + deploy to Forge ---
    Write-Host '  [2/4] Installing skills...' -ForegroundColor Cyan

    $gitOk = [bool](Get-Command git -ErrorAction SilentlyContinue)
    if (-not $gitOk) {
        Write-Host '  [warn]   git not found in PATH. Git-based skills will be skipped.' -ForegroundColor DarkYellow
    }

    $toInstall = if ($Only) { $registry | Where-Object { $_.name -eq $Only } } else { $registry }

    # Suspend Windows Defender real-time scan on clone dirs + git.exe process
    # Antimalware eats 1.7GB+ scanning every git object → causes 0xc0000142
    $cloneRoot = Get-AgentInstallRoot
    $forgeRoot = Get-ForgeGlobalSkillsDir
    $defenderPaths = @($cloneRoot, $forgeRoot)
    $defenderExcluded = @()
    if (-not $DryRun) {
        $defenderExcluded = Suspend-Defender -Paths $defenderPaths
        if ($defenderExcluded.Count -gt 0) {
            Write-Host ('  [ok]     Defender exclusions added for clone dirs ({0} paths)' -f $defenderExcluded.Count) -ForegroundColor Green
        } else {
            Write-Host '  [info]   Non-admin: Defender exclusions skipped (clone may be slower)' -ForegroundColor DarkGray
        }
        # Pre-flush RAM before clone loop
        Invoke-EmptyWorkingSet
    }

    $ok = 0; $fail = 0
    $skillList = @($toInstall | Sort-Object { [int]($_.priority) })
    foreach ($skill in $skillList) {
        $result = Install-AgentSkillEntry -Skill $skill -DryRun:$DryRun
        if ($result) { $ok++ } else { $fail++ }
    }

    # Prune stale skill dirs that are no longer in the registry (formerly deployed)
    # Hardcoded list = dirs that were previously managed by this command and must be
    # cleaned up when removed from registry.json. Safe: only known names are touched.
    $knownLegacyDirs = @('gsd-pi-guide')
    $registryDirs = @($registry | ForEach-Object { $_.dir })
    foreach ($legacy in $knownLegacyDirs) {
        if ($registryDirs -contains $legacy) { continue }
        foreach ($root in @($cloneRoot, $forgeRoot)) {
            $stale = Join-Path $root $legacy
            if (Test-Path $stale) {
                if ($DryRun) {
                    Write-Host ('  [dry-run] Would prune stale skill dir: {0}' -f $stale) -ForegroundColor Yellow
                } else {
                    try {
                        Remove-Item $stale -Recurse -Force -ErrorAction Stop
                        Write-Host ('  [ok]     Pruned stale skill dir: {0}' -f $stale) -ForegroundColor Green
                    } catch {
                        Write-Host ('  [warn]   Could not prune {0}: {1}' -f $stale, $_.Exception.Message) -ForegroundColor DarkYellow
                    }
                }
            }
        }
    }

    # Restore Defender exclusions
    if ($defenderExcluded.Count -gt 0) {
        Resume-Defender -Paths $defenderExcluded
        Write-Host '  [ok]     Defender exclusions removed (real-time scan restored)' -ForegroundColor Green
    }

    Write-Host ("`n  Installed: {0} skills{1}" -f $ok, $(if ($fail) { ", $fail failed" } else { '' })) -ForegroundColor $(if ($fail) { 'DarkYellow' } else { 'Green' })
    Write-Host ''

    # ---- Step 3: Write force-load master skill to Forge -----------------
    Write-Host '  [3/4] Writing Forge force-load skill + updating AGENTS.md...' -ForegroundColor Cyan
    Write-ForceLoadSkill -Registry $registry -DryRun:$DryRun

    # Inject into project AGENTS.md + CLAUDE.md
    $agentsMd = Join-Path (Get-Location) 'AGENTS.md'
    Write-AgentsMdSection -Registry $registry -DryRun:$DryRun -TargetPath $agentsMd

    $projectClaudeMd = Join-Path (Get-Location) 'CLAUDE.md'
    Write-AgentsMdSection -Registry $registry -DryRun:$DryRun -TargetPath $projectClaudeMd

    # Inject into ~/.claude/AGENTS.md (global Claude Code)
    $claudeAgentsMd = Join-Path (Get-ClaudeContextDir) 'AGENTS.md'
    Write-AgentsMdSection -Registry $registry -DryRun:$DryRun -TargetPath $claudeAgentsMd
    Write-Host ''

    # ---- Step 4: GC to release memory -----------------------------------
    Write-Host '  [4/4] Cleanup...' -ForegroundColor Cyan
    if (-not $DryRun) {
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
        Write-Host '  [ok]     Memory released' -ForegroundColor Green
    }
    Write-Host ''

    # ---- Done -----------------------------------------------------------
    Write-Host '  Done. Restart Forge and GSD for skills to take effect.' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  Forge:      skills in ~/.forge/skills/ auto-load each session.' -ForegroundColor DarkGray
    Write-Host '  GSD:        AGENTS.md + CLAUDE.md skill sections visible to project agents.' -ForegroundColor DarkGray
    Write-Host '  Claude Code: ~/.claude/AGENTS.md loaded globally.' -ForegroundColor DarkGray
    Write-Host '  Verify:     8sync agents list' -ForegroundColor DarkGray
    Write-Host ''
}

function Invoke-AgentListSkills {
    param([switch]$CheckLinks)

    $registry = Get-AgentSkillRegistry

    Write-Host ''
    Write-Host '  8SYNC AGENTS -- SKILL REGISTRY' -ForegroundColor Cyan
    Write-Host ("  {0} skills registered  |  registry: agents/registry.json" -f $registry.Count) -ForegroundColor DarkGray
    Write-Host ''

    $installRoot  = Get-AgentInstallRoot
    $forgeSkills  = Get-ForgeGlobalSkillsDir

    Write-Host ("  {0,-4} {1,-22} {2,-12} {3,-8} {4}" -f 'Pri', 'Name', 'Installed', 'Forge', 'URL') -ForegroundColor DarkGray
    Write-Host ("  {0}" -f ('-' * 90)) -ForegroundColor DarkGray

    foreach ($skill in $registry | Sort-Object { [int]($_.priority) }) {
        $localPath  = Join-Path $installRoot $skill.dir
        $forgePath  = Join-Path $forgeSkills $skill.dir
        $installed  = if (Test-Path $localPath) { 'yes' } else { 'no' }
        $forgeDepl  = if (Test-Path $forgePath) { 'yes' } else { 'no' }
        $url        = $skill.url
        $mandatory  = if ($skill.mandatory) { '*' } else { ' ' }

        Write-Host ("  [{0}]{1,-3} {2,-22} " -f $skill.priority, $mandatory, $skill.name) -NoNewline -ForegroundColor White
        Write-Host ("{0,-12} {1,-8} " -f $installed, $forgeDepl) -NoNewline -ForegroundColor $(if ($installed -eq 'yes' -and $forgeDepl -eq 'yes') { 'Green' } else { 'DarkYellow' })
        Write-Host $url -ForegroundColor DarkGray
    }

    Write-Host ''
    Write-Host '  * = mandatory (read first)' -ForegroundColor DarkGray
    Write-Host '  Installed = agents/skills/<dir>/ exists' -ForegroundColor DarkGray
    Write-Host '  Forge = ~/.forge/skills/<dir>/ deployed' -ForegroundColor DarkGray
    Write-Host ''

    if ($CheckLinks) {
        Write-Host '  Checking URLs...' -ForegroundColor Cyan
        foreach ($skill in $registry | Where-Object { $_.url -ne 'built-in' -and $_.url -ne 'local' }) {
            $url = $skill.url
            $checkUrl = $url -replace '\.git$', ''
            try {
                $resp = Invoke-WebRequest -Uri $checkUrl -Method Head -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
                $code = $resp.StatusCode
                $color = if ($code -lt 400) { 'Green' } else { 'Red' }
                Write-Host ("    [{0}] {1}" -f $code, $skill.name) -ForegroundColor $color
            } catch {
                $msg = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 'ERR' }
                Write-Host ("    [{0}] {1} -- {2}" -f $msg, $skill.name, $checkUrl) -ForegroundColor Red
            }
        }
        Write-Host ''
    }

    Write-Host '  Commands:' -ForegroundColor DarkGray
    Write-Host '    8sync agents max-skill              # install all skills globally + project' -ForegroundColor DarkGray
    Write-Host '    8sync agents project                # install only into current project' -ForegroundColor DarkGray
    Write-Host '    8sync agents max-skill --only <n>   # install one skill' -ForegroundColor DarkGray
    Write-Host '    8sync agents check                  # check all URLs' -ForegroundColor DarkGray
    Write-Host '    8sync agents list                   # this listing' -ForegroundColor DarkGray
    Write-Host ''
}

function Invoke-AgentCheckLinks {
    Invoke-AgentListSkills -CheckLinks
}
