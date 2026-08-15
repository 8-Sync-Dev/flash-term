# ---------------------------------------------------------------------------
#  ft skills -- mirror the omp/su-code skill library (~/.omp/skills) into the
#  ZCode workspace layout: <project>/.zcode/skills/<name>/SKILL.md
#  `8sync harness init` only vendors su-code/skills/; ZCode reads .zcode/skills/,
#  so this fills that gap for one project or every project on the machine.
# ---------------------------------------------------------------------------

function Get-OmpSkillsDir {
    return (Join-Path $HOME '.omp\skills')
}

function Get-OmpSkillDirs {
    # Every skill directory that actually carries a SKILL.md (the Agent Skills
    # contract). Loose files like 00-force-load.md are not skills.
    $root = Get-OmpSkillsDir
    if (-not (Test-Path $root)) { return @() }
    try {
        return @(Get-ChildItem -Path $root -Directory -ErrorAction Stop |
            Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') })
    } catch {
        return @()
    }
}

function Test-SuCodeMemoryDir {
    # A directory named su-code only marks a project when it holds real memory.
    # Without this, a checkout literally named `su-code` makes its PARENT look
    # like a project (same guard su-code's own discover.rs applies).
    param([Parameter(Mandatory)] [string]$Path)

    if (Test-Path (Join-Path $Path 'skills')) { return $true }
    foreach ($f in @('STATE.md', 'KNOWLEDGE.md', 'PROJECT.md', 'PLAYBOOKS.md', 'skills.toml')) {
        if (Test-Path (Join-Path $Path $f)) { return $true }
    }
    return $false
}

function Find-SuCodeProjects {
    param([string]$Root, [int]$Depth = 4)

    if (-not $Root) { $Root = $script:SkillsScanRoot }
    if (-not (Test-Path $Root)) {
        Write-Warning ('[ft] Scan root not found: {0}' -f $Root)
        return @()
    }

    $skip = @('node_modules', '.git', 'target', 'dist', 'build', '.venv', 'venv', '.zcode', '.omp')
    $found = @()
    try {
        $candidates = Get-ChildItem -Path $Root -Directory -Recurse -Depth $Depth -Filter 'su-code' -ErrorAction SilentlyContinue
    } catch {
        return @()
    }

    foreach ($dir in $candidates) {
        $parts = $dir.FullName -split '[\\/]'
        if ($parts | Where-Object { $skip -contains $_ }) { continue }
        if (-not (Test-SuCodeMemoryDir -Path $dir.FullName)) { continue }
        $projectRoot = Split-Path $dir.FullName -Parent
        if ($projectRoot -and ($found -notcontains $projectRoot)) { $found += $projectRoot }
    }

    return @($found | Sort-Object)
}

function Sync-ZcodeSkills {
    # Copy every omp skill tree into <Project>/.zcode/skills/. Additive by
    # default so a locally edited skill is never clobbered; -Force re-copies.
    param(
        [Parameter(Mandatory)] [string]$Project,
        [switch]$Force,
        [switch]$Quiet
    )

    $skills = Get-OmpSkillDirs
    if ($skills.Count -eq 0) {
        Write-Warning '[ft] No skills found in ~/.omp/skills -- run: 8sync harness init'
        return [pscustomobject]@{ Project = $Project; Copied = 0; Skipped = 0; Total = 0 }
    }

    $target = Join-Path $Project '.zcode\skills'
    try {
        if (-not (Test-Path $target)) { $null = New-Item -ItemType Directory -Path $target -Force -ErrorAction Stop }
    } catch {
        Write-Warning ('[ft] Cannot create {0}: {1}' -f $target, $_)
        return [pscustomobject]@{ Project = $Project; Copied = 0; Skipped = 0; Total = $skills.Count }
    }

    $copied = 0
    $skipped = 0
    foreach ($skill in $skills) {
        $dest = Join-Path $target $skill.Name
        if ((Test-Path (Join-Path $dest 'SKILL.md')) -and -not $Force) {
            $skipped++
            continue
        }
        try {
            if (Test-Path $dest) { Remove-Item -Path $dest -Recurse -Force -ErrorAction Stop }
            Copy-Item -Path $skill.FullName -Destination $dest -Recurse -Force -ErrorAction Stop
            $copied++
        } catch {
            Write-Warning ('[ft] Failed to copy {0}: {1}' -f $skill.Name, $_)
        }
    }

    if (-not $Quiet) {
        $verb = if ($Force) { 'refreshed' } else { 'copied' }
        Write-Host ('  {0}' -f $Project) -ForegroundColor Cyan
        Write-Host ('    {0} {1}, {2} already present -> {3}' -f $copied, $verb, $skipped, $target) -ForegroundColor DarkGray
    }

    return [pscustomobject]@{ Project = $Project; Copied = $copied; Skipped = $skipped; Total = $skills.Count }
}

function Show-SkillsStatus {
    param([string]$Project)

    if (-not $Project) { $Project = (Get-Location).Path }
    $omp = Get-OmpSkillDirs
    $local = Join-Path $Project '.zcode\skills'
    $localCount = 0
    if (Test-Path $local) {
        $localCount = @(Get-ChildItem -Path $local -Directory -ErrorAction SilentlyContinue |
            Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') }).Count
    }

    Write-Host ''
    Write-HintSection 'SKILLS STATUS'
    Write-HintRow 'omp library'    ('{0} skill(s) in {1}' -f $omp.Count, (Get-OmpSkillsDir))
    Write-HintRow 'This project'   $Project
    Write-HintRow '.zcode/skills'  $(if ($localCount -gt 0) { '{0} skill(s)' -f $localCount } else { 'missing -- run: ft skills sync' })
    Write-HintRow 'su-code memory' $(if (Test-Path (Join-Path $Project 'su-code')) { 'present' } else { 'absent (8sync harness init)' })
    Write-Host ''
}

function Invoke-SkillsSyncAll {
    param([string]$Root, [switch]$Force)

    if (-not $Root) { $Root = $script:SkillsScanRoot }
    Write-Host ('[ft] Scanning for su-code projects under {0} ...' -f $Root) -ForegroundColor DarkGray
    $projects = Find-SuCodeProjects -Root $Root
    if ($projects.Count -eq 0) {
        Write-Warning '[ft] No project with a su-code/ memory dir found.'
        return
    }

    Write-Host ''
    Write-HintSection ('SKILLS SYNC -- {0} project(s)' -f $projects.Count)
    $totalCopied = 0
    foreach ($p in $projects) {
        $r = Sync-ZcodeSkills -Project $p -Force:$Force
        $totalCopied += $r.Copied
    }
    Write-Host ''
    Write-Host ('[ft] Done: {0} skill copy operation(s) across {1} project(s).' -f $totalCopied, $projects.Count) -ForegroundColor Green
    Write-Host ''
}

function Show-SkillsHelp {
    Write-Host ''
    Write-HintSection 'SKILLS -- mirror omp skills into .zcode/skills for ZCode'
    Write-HintRow 'ft skills'                'Status: omp library vs this project .zcode/skills'
    Write-HintRow 'ft skills sync'           'Copy all omp skills into ./.zcode/skills (this project)'
    Write-HintRow 'ft skills sync --force'   'Re-copy, overwriting existing skills'
    Write-HintRow 'ft skills all'            'Sync every project with a su-code/ dir under the scan root'
    Write-HintRow 'ft skills all --force'    'Same, overwriting existing skills'
    Write-HintRow 'ft skills all <path>'     'Scan a custom root instead of the default'
    Write-HintRow 'ft skills list'           'List projects that would be synced by: ft skills all'
    Write-HintRow 'Default scan root'        $script:SkillsScanRoot
    Write-Host ''
}

function Invoke-SkillsCommand {
    param([string[]]$Rest)

    if (-not $Rest -or $Rest.Count -eq 0) {
        Show-SkillsStatus
        return
    }

    if ($Rest -contains '--help' -or $Rest -contains '-h' -or $Rest -contains 'help') {
        Show-SkillsHelp
        return
    }

    $force = ($Rest -contains '--force')
    $positional = @($Rest | Where-Object { $_ -notlike '--*' })
    $sub = if ($positional.Count -gt 0) { $positional[0].ToLowerInvariant() } else { 'status' }
    $arg = if ($positional.Count -gt 1) { $positional[1] } else { $null }

    switch ($sub) {
        'status' { Show-SkillsStatus }
        'sync' {
            $project = if ($arg) { $arg } else { (Get-Location).Path }
            Write-Host ''
            Write-HintSection 'SKILLS SYNC'
            $null = Sync-ZcodeSkills -Project $project -Force:$force
            Write-Host ''
        }
        'all' { Invoke-SkillsSyncAll -Root $arg -Force:$force }
        'list' {
            $root = if ($arg) { $arg } else { $script:SkillsScanRoot }
            $projects = Find-SuCodeProjects -Root $root
            Write-Host ''
            Write-HintSection ('SU-CODE PROJECTS ({0}) under {1}' -f $projects.Count, $root)
            foreach ($p in $projects) {
                $has = Test-Path (Join-Path $p '.zcode\skills')
                Write-HintRow $p $(if ($has) { '.zcode/skills present' } else { 'missing -- ft skills all' })
            }
            Write-Host ''
        }
        default { Write-Warning '[ft] Unknown skills option. Use: ft skills help' }
    }
}
