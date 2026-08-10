# =============================================================================
# 8sync up -- update everything flash-term manages (update-all)
# =============================================================================
# Usage:
#   8sync up                  Update all (self -> scoop tools -> omp -> skills -> wezterm)
#   8sync up --check          Dry-run: report what would update, change nothing
#   8sync up self|scoop|omp|skills|wezterm   Update only one target
#   8sync update-all          Alias of `8sync up`
# =============================================================================

$script:UpTargets = @('self', 'scoop', 'omp', 'skills', 'wezterm')

function Get-UpRootDir {
    # flash-term config root = parent of modules/
    Split-Path $PSScriptRoot -Parent
}

function Get-RealGitForUp {
    # Prefer the agents resolver, but only if it returns a real, resolvable git.
    $candidates = @()
    if (Get-Command Get-RealGitExe -ErrorAction SilentlyContinue) {
        $candidates += (Get-RealGitExe)
    }
    $candidates += @(
        'git',
        (Join-Path $env:LOCALAPPDATA 'bin\git\cmd\git.exe'),
        (Join-Path $HOME 'scoop\shims\git.exe'),
        'C:\Program Files\Git\cmd\git.exe'
    )
    foreach ($c in $candidates) {
        if (-not $c) { continue }
        $cmd = Get-Command $c -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
        if (Test-Path $c) { return $c }
    }
    return $null
}

function Update-FlashTermSelf {
    # Pull the latest config repo (ff-only). Generated lua/.state/ are gitignored.
    param([switch]$DryRun)

    $root = Get-UpRootDir
    $git  = Get-RealGitForUp
    if (-not $git) {
        Write-Host '  [skip]   self: git not found' -ForegroundColor DarkYellow
        return
    }
    if (-not (Test-Path (Join-Path $root '.git'))) {
        Write-Host '  [skip]   self: not a git repo (no .git)' -ForegroundColor DarkYellow
        return
    }

    $behind = & $git -C $root rev-list --count 'HEAD..@{u}' 2>$null
    if ($LASTEXITCODE -ne 0) {
        $defaultBranch = (& $git -C $root symbolic-ref refs/remotes/origin/HEAD 2>$null) -replace 'refs/remotes/origin/', ''
        if (-not $defaultBranch) { $defaultBranch = 'main' }
        Write-Host ("  [info]   self: setting upstream to origin/$defaultBranch") -ForegroundColor DarkGray
        if ($DryRun) { return }
        & $git -C $root branch --set-upstream-to="origin/$defaultBranch" 2>$null
        $behind = & $git -C $root rev-list --count 'HEAD..@{u}' 2>$null
    }

    if (-not $behind -or [int]$behind -le 0) {
        Write-Host '  [ok]     self: up to date' -ForegroundColor Green
        return
    }
    Write-Host ("  [info]   self: $behind commit(s) behind") -ForegroundColor DarkGray
    if ($DryRun) { return }

    $dirty = -not (Test-WorkingTreeClean -Root $root)
    if ($dirty) {
        Write-Host '  [info]   self: stashing local changes before pull' -ForegroundColor DarkGray
        & $git -C $root stash push -u -m "8sync up auto-stash" 2>$null
    }
    try {
        & $git -C $root pull --ff-only --quiet 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host '  [ok]     self: pulled latest (apply: 8sync reload)' -ForegroundColor Green
        } else {
            Write-Host '  [warn]   self: ff-only failed (diverged). Resolve manually.' -ForegroundColor DarkYellow
        }
    } finally {
        if ($dirty) { & $git -C $root stash pop 2>$null }
    }
}

function Find-OmpExe {
    foreach ($name in @('omp', 'omp.exe')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    foreach ($p in @(
        (Join-Path $HOME '.bun\bin\omp.cmd'),
        (Join-Path $HOME '.bun\bin\omp.exe'),
        (Join-Path $HOME 'scoop\shims\omp.exe')
    )) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Update-Omp {
    param([switch]$DryRun)
    $omp = Find-OmpExe
    if (-not $omp) {
        Write-Host '  [skip]   omp: not installed (harness engine absent)' -ForegroundColor DarkYellow
        Write-Host '           install omp first, then 8sync harness' -ForegroundColor DarkGray
        return
    }
    Write-Host ("  [info]   omp: $omp") -ForegroundColor DarkGray
    if ($DryRun) { return }

    # omp ships a self-upgrade; try common verbs, then fall back to the bun/npm installer.
    foreach ($verb in @('upgrade', 'update', 'self-update')) {
        $null = & $omp $verb --help 2>&1
        if ($LASTEXITCODE -eq 0) {
            & $omp $verb
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  [ok]     omp: upgraded (via omp $verb)" -ForegroundColor Green
                return
            }
        }
    }
    foreach ($pair in @(@('bun','pm','update','-g','omp'), @('npm','update','-g','omp'))) {
        $bin = Get-Command $pair[0] -ErrorAction SilentlyContinue
        if ($bin) {
            & $pair[0] @($pair[1..($pair.Length - 1)])
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  [ok]     omp: upgraded (via $($pair[0]))" -ForegroundColor Green
                return
            }
        }
    }
    Write-Host '  [warn]   omp: no self-upgrade verb found; update manually' -ForegroundColor DarkYellow
}

function Update-ManagedSkills {
    # Re-pull every installed skill repo via the agents clone helper.
    param([switch]$DryRun)
    if (-not (Get-Command Get-AgentInstallRoot -ErrorAction SilentlyContinue)) {
        Write-Host '  [skip]   skills: agents module not loaded' -ForegroundColor DarkYellow
        return
    }
    $root = Get-AgentInstallRoot
    if (-not (Test-Path $root)) {
        Write-Host '  [ok]     skills: none installed (run: 8sync harness)' -ForegroundColor Green
        return
    }
    $count = 0
    foreach ($skill in (Get-AgentSkillRegistry)) {
        $target = Join-Path $root $skill.dir
        if (-not (Test-Path (Join-Path $target '.git'))) { continue }
        $count++
        if ($DryRun) { continue }
        Clone-SkillRepo -Url $skill.url -Dir $skill.dir | Out-Null
    }
    if ($count -eq 0) {
        Write-Host '  [ok]     skills: none installed (run: 8sync harness)' -ForegroundColor Green
    } else {
        Write-Host ("  [ok]     skills: refreshed $count skill repo(s)") -ForegroundColor Green
    }
}

function Update-WezTermApp {
    # WezTerm ships its own auto-updater; we only report the installed version.
    param([switch]$DryRun)
    $wt = Get-Command wezterm -ErrorAction SilentlyContinue
    if (-not $wt) {
        $found = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'bin\wezterm\WezTerm-windows-*\wezterm.exe') -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $wt = @{ Source = $found.FullName } }
    }
    if (-not $wt) {
        Write-Host '  [skip]   wezterm: not found' -ForegroundColor DarkYellow
        return
    }
    $ver = (& $wt.Source --version 2>$null | Select-Object -First 1)
    Write-Host ("  [ok]     wezterm: $ver (auto-updates in-app)") -ForegroundColor Green
}

function Show-UpHelp {
    Write-Host ''
    Write-Host '  8SYNC UP -- update everything flash-term manages' -ForegroundColor Cyan
    Write-Host ''
    Write-HintRow '8sync up'          'Update all: self, scoop tools, omp, skills, wezterm'
    Write-HintRow '8sync up --check'  'Dry-run: report what would update, change nothing'
    Write-HintRow '8sync up self'     'git pull the flash-term config repo (ff-only)'
    Write-HintRow '8sync up scoop'    'scoop update buckets + all managed tools'
    Write-HintRow '8sync up omp'      'Update the omp AI engine'
    Write-HintRow '8sync up skills'   'Re-pull every installed skill repo'
    Write-HintRow '8sync up wezterm'  'Report WezTerm version (auto-updates in-app)'
    Write-Host ''
}

function Invoke-UpCommand {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Rest
    )

    if ($Rest -contains '--help' -or $Rest -contains 'help' -or $Rest -contains '-h') {
        Show-UpHelp
        return
    }

    $dryRun = $Rest -contains '--check' -or $Rest -contains '--dry-run'
    $targets = @($Rest | Where-Object { $_ -in $script:UpTargets } | Select-Object -Unique)
    if ($targets.Count -eq 0) { $targets = $script:UpTargets }

    if ($dryRun) {
        Write-Host '  Update preview (dry-run) -- no changes will be made' -ForegroundColor Yellow
    } else {
        Write-Host '  Updating flash-term managed stack...' -ForegroundColor Cyan
    }
    Write-Host ''

    foreach ($t in $targets) {
        switch ($t) {
            'self'    { Update-FlashTermSelf -DryRun:$dryRun }
            'scoop'   {
                if ($dryRun) {
                    Write-Host '  [dry-run] scoop: would update buckets + managed tools' -ForegroundColor Yellow
                } else {
                    Invoke-ToolSync
                }
            }
            'omp'     { Update-Omp -DryRun:$dryRun }
            'skills'  { Update-ManagedSkills -DryRun:$dryRun }
            'wezterm' { Update-WezTermApp -DryRun:$dryRun }
        }
    }

    Write-Host ''
    Write-Host '  Done.' -ForegroundColor Green
}
