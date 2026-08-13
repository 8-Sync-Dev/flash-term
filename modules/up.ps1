# =============================================================================
# ft up -- update everything flash-term manages (update-all)
# =============================================================================
# Usage:
#   ft up                  Update all (self -> scoop tools -> wezterm)
#   ft up --check          Dry-run: report what would update, change nothing
#   ft up self|scoop|wezterm   Update only one target
# =============================================================================


function Get-UpRootDir {
    # flash-term config root = parent of modules/
    Split-Path $PSScriptRoot -Parent
}

function Get-RealGitForUp {
    # Prefer the agents resolver, but only if it returns a real, resolvable git.
    $candidates = @()
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
        & $git -C $root stash push -u -m "ft up auto-stash" 2>$null
    }
    try {
        & $git -C $root pull --ff-only --quiet 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host '  [ok]     self: pulled latest (apply: ft reload)' -ForegroundColor Green
        } else {
            Write-Host '  [warn]   self: ff-only failed (diverged). Resolve manually.' -ForegroundColor DarkYellow
        }
    } finally {
        if ($dirty) { & $git -C $root stash pop 2>$null }
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
    Write-Host '  FT UP -- update everything flash-term manages' -ForegroundColor Cyan
    Write-Host ''
    Write-HintRow 'ft up'          'Update all: self, scoop tools, wezterm'
    Write-HintRow 'ft up --check'  'Dry-run: report what would update, change nothing'
    Write-HintRow 'ft up self'     'git pull the flash-term config repo (ff-only)'
    Write-HintRow 'ft up scoop'    'scoop update buckets + all managed tools'
    Write-HintRow 'ft up wezterm'  'Report WezTerm version (auto-updates in-app)'
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
            'wezterm' { Update-WezTermApp -DryRun:$dryRun }
        }
    }

    Write-Host ''
    Write-Host '  Done.' -ForegroundColor Green
}
