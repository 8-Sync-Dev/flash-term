# =============================================================================
# 8sync agents max-skill -- deploy full skill suite to Forge, GSD, Claude Code
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
    [void]$sb.AppendLine('# 00 — Force Load Skills  (managed by 8sync agents max-skill)')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('## MANDATORY RULE')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('**Before starting ANY non-trivial task you MUST:**')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('1. Read `.forge/skills/karpathy-guidelines/SKILL.md` — no exceptions')
    [void]$sb.AppendLine('2. Identify the task type from the table below')
    [void]$sb.AppendLine('3. Read all skills listed for that type before writing code')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('## Skill Selection Guide')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('| Task type | Skills to read (in order) |')
    [void]$sb.AppendLine('|---|---|')
    [void]$sb.AppendLine('| Any coding task | **karpathy-guidelines** (always first) |')
    [void]$sb.AppendLine('| Frontend / UI / CSS / React | karpathy + **ui-ux-pro-max** |')
    [void]$sb.AppendLine('| Design systems / tokens / brand | karpathy + ui-ux-pro-max + **getdesign** + **dembrandt** |')
    [void]$sb.AppendLine('| Git workflow / PR / CI | karpathy + **gitnexus** |')
    [void]$sb.AppendLine('| Code review / refactor | karpathy + **code-review-graph** |')
    [void]$sb.AppendLine('| Ruby / Rails / backend | karpathy + **ba-skills** |')
    [void]$sb.AppendLine('| All shell / CLI commands | **rtk-token-save** (always — use rtk variants) |')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('## Installed Skills')
    [void]$sb.AppendLine()

    foreach ($skill in $Registry | Sort-Object { [int]($_.priority) }) {
        $mandatory = if ($skill.mandatory) { ' **(MANDATORY)**' } else { '' }
        [void]$sb.AppendLine(('- `{0}`{1} — {2}' -f $skill.dir, $mandatory, $skill.use_when))
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
    param([object[]]$Registry)

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('<!-- agents:max-skill:start — managed by 8sync agents max-skill -->')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('## Agent Skill Library (8sync max-skill)')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('**Rule:** Before any non-trivial task, read karpathy-guidelines first.')
    [void]$sb.AppendLine('Then select additional skills by task type:')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('| Task type | Skills |')
    [void]$sb.AppendLine('|---|---|')
    [void]$sb.AppendLine('| Any coding | `agents/skills/karpathy-guidelines/` (mandatory) |')
    [void]$sb.AppendLine('| Frontend/UI | + `agents/skills/ui-ux-pro-max/` |')
    [void]$sb.AppendLine('| Design system | + `agents/skills/getdesign/` + `agents/skills/dembrandt/` |')
    [void]$sb.AppendLine('| Git/PR/CI | + `agents/skills/gitnexus/` |')
    [void]$sb.AppendLine('| Code review | + `agents/skills/code-review-graph/` |')
    [void]$sb.AppendLine('| Ruby/Rails | + `agents/skills/ba-skills/` |')
    [void]$sb.AppendLine('| Shell cmds | Use rtk variants: `rtk git`, `rtk read`, `rtk grep` |')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('### Skill Registry')
    [void]$sb.AppendLine()

    foreach ($skill in $Registry | Sort-Object { [int]($_.priority) }) {
        $mandatory = if ($skill.mandatory) { ' **(mandatory)**' } else { '' }
        $urlLabel  = if ($skill.url -eq 'built-in') { 'built-in' } else { $skill.url }
        [void]$sb.AppendLine(('- **{0}**{1}: {2}  ' -f $skill.display, $mandatory, $skill.use_when))
        [void]$sb.AppendLine(('  Ref: {0}' -f $urlLabel))
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
    Write-Host ('  [ok]     Wrote ~/.forge/skills/00-force-load.md (loads first, enforces skill order)') -ForegroundColor Green
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

    # Built-in rtk skill is already handled by token-save; just deploy if already written
    if ($skill.builtin -and $name -eq 'rtk-token-save') {
        $rtkSkill = Join-Path (Get-ForgeGlobalSkillsDir) 'rtk-token-save'
        if (Test-Path $rtkSkill) {
            Write-Host '       Already present (written by token-save).' -ForegroundColor DarkGray
        } else {
            Write-Host '       Run 8sync gsd token-save --forge-full to install.' -ForegroundColor DarkGray
        }
        return $true
    }

    # Karpathy built-in: use existing forge add-skill mechanism if available
    if ($skill.builtin -and $name -eq 'karpathy') {
        $target = Join-Path (Get-AgentInstallRoot) $dir
        $forgeTarget = Join-Path (Get-ForgeGlobalSkillsDir) $dir
        if (Test-Path $forgeTarget) {
            Write-Host '       karpathy-guidelines already deployed to ~/.forge/skills/.' -ForegroundColor Green
            # Still ensure it's in agents/skills/
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

    # Fetch type: URL or git
    $fetchType = if ($skill.PSObject.Properties['fetch_type']) { $skill.fetch_type } else { 'git' }
    $localDir  = $null

    if ($fetchType -eq 'url') {
        $localDir = Fetch-SkillFromUrl -Url $url -Dir $dir -DryRun:$DryRun
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

function Invoke-AgentMaxSkill {
    param(
        [switch]$DryRun,
        [switch]$SkipTokenSave,
        [string]$Only   # install only this skill name
    )

    Write-Host ''
    Write-Host '  8SYNC AGENTS -- MAX-SKILL' -ForegroundColor Cyan
    Write-Host '  Deploys full skill suite to Forge, GSD project, and Claude Code.' -ForegroundColor DarkGray
    Write-Host ''

    $registry = Get-AgentSkillRegistry

    # ---- Step 1: Token save (RTK for Claude Code + Forge) ---------------
    Write-Host '  [1/5] Token optimizer (RTK + Forge full)...' -ForegroundColor Cyan
    if ($SkipTokenSave) {
        Write-Host '  [skip]   --skip-token-save passed.' -ForegroundColor DarkGray
    } else {
        Invoke-GsdTokenSave -DryRun:$DryRun -SkipAuthFix -SkipEnv -ForgeFull
    }
    Write-Host ''

    # ---- Step 2: Install skills into agents/skills/ + deploy to Forge ---
    Write-Host '  [2/5] Installing skills...' -ForegroundColor Cyan

    $gitOk = [bool](Get-Command git -ErrorAction SilentlyContinue)
    if (-not $gitOk) {
        Write-Host '  [warn]   git not found in PATH. Git-based skills will be skipped.' -ForegroundColor DarkYellow
        Write-Host '           Install git: scoop install git' -ForegroundColor DarkGray
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
    foreach ($skill in $toInstall | Sort-Object { [int]($_.priority) }) {
        $result = Install-AgentSkillEntry -Skill $skill -DryRun:$DryRun
        if ($result) { $ok++ } else { $fail++ }
    }

    # Restore Defender exclusions
    if ($defenderExcluded.Count -gt 0) {
        Resume-Defender -Paths $defenderExcluded
        Write-Host '  [ok]     Defender exclusions removed (real-time scan restored)' -ForegroundColor Green
    }

    Write-Host ("`n  Installed: {0} skills{1}" -f $ok, $(if ($fail) { ", $fail failed" } else { '' })) -ForegroundColor $(if ($fail) { 'DarkYellow' } else { 'Green' })
    Write-Host ''

    # ---- Step 3: Write force-load master skill to Forge -----------------
    Write-Host '  [3/5] Writing Forge force-load skill (00-force-load.md)...' -ForegroundColor Cyan
    Write-ForceLoadSkill -Registry $registry -DryRun:$DryRun
    Write-Host ''

    # ---- Step 4: Inject into project AGENTS.md --------------------------
    Write-Host '  [4/5] Updating project AGENTS.md...' -ForegroundColor Cyan
    $agentsMd = Join-Path (Get-Location) 'AGENTS.md'
    Write-AgentsMdSection -Registry $registry -DryRun:$DryRun -TargetPath $agentsMd
    Write-Host ''

    # ---- Step 5: Inject into ~/.claude/AGENTS.md (global Claude Code) ---
    Write-Host '  [5/5] Updating global ~/.claude/AGENTS.md...' -ForegroundColor Cyan
    $claudeAgentsMd = Join-Path (Get-ClaudeContextDir) 'AGENTS.md'
    Write-AgentsMdSection -Registry $registry -DryRun:$DryRun -TargetPath $claudeAgentsMd
    Write-Host ''

    # ---- Done -----------------------------------------------------------
    Write-Host '  Done. Restart Forge and GSD for skills to take effect.' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  Forge:      skills in ~/.forge/skills/ auto-load each session.' -ForegroundColor DarkGray
    Write-Host '  GSD:        AGENTS.md skill section visible to all agents.' -ForegroundColor DarkGray
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

        $instColor  = if ($installed -eq 'yes') { 'Green' } else { 'DarkYellow' }
        $forgeColor = if ($forgeDepl -eq 'yes') { 'Green' } else { 'DarkYellow' }

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
        foreach ($skill in $registry | Where-Object { $_.url -ne 'built-in' }) {
            $url = $skill.url
            # For .git URLs, check the base repo URL
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
    Write-Host '    8sync agents max-skill              # install all skills' -ForegroundColor DarkGray
    Write-Host '    8sync agents max-skill --only <n>   # install one skill' -ForegroundColor DarkGray
    Write-Host '    8sync agents check                  # check all URLs' -ForegroundColor DarkGray
    Write-Host '    8sync agents list                   # this listing' -ForegroundColor DarkGray
    Write-Host ''
}

function Invoke-AgentCheckLinks {
    Invoke-AgentListSkills -CheckLinks
}
