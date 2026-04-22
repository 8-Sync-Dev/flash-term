# =============================================================================
# 8sync gsd global -- promote local runtime to global, rollback, status
#
# Source resolution order:
#   1. --from <path>            explicit path (can be current/ dir or project root)
#   2. --version <name>         named source from project-local test/ sandboxes
#                               or cwd project (latest | baseline | X.Y.Z)
#   3. auto-detect              uses current project's active current/ if cwd is
#                               inside a project, else scans wezterm/test/latest
#                               then wezterm/test/baseline
#
# Safety:
#   - always backs up ~/.gsd/agent/node_modules/gsd-pi to .bak-<ver>-<ts>
#   - never deletes ~/.gsd/agent/{auth.json, settings.json, sessions, gsd.db}
#   - rollback restores the backup
# =============================================================================

# Primary: npm-global location — this is where the `gsd` shim actually resolves
# (via the bin field of gsd-pi's package.json). Updating this changes what
# `gsd --version` reports.
function Resolve-GsdGlobalRuntimeRoot {
    $npmGlobal = Resolve-GsdNpmGlobalRoot
    if ($npmGlobal) {
        return Join-Path $npmGlobal 'gsd-pi'
    }
    # Fallback: agent runtime cache (used when gsd is already running)
    return Join-Path $HOME '.gsd\agent\node_modules\gsd-pi'
}

function Resolve-GsdNpmGlobalRoot {
    # `npm root -g` returns the global node_modules dir. Cache result to avoid
    # repeated shell-outs.
    if ($script:GsdNpmGlobalRootCache) { return $script:GsdNpmGlobalRootCache }
    try {
        $out = & npm root -g 2>$null
        if ($out) {
            $p = "$out".Trim()
            if (Test-Path $p) {
                $script:GsdNpmGlobalRootCache = $p
                return $p
            }
        }
    } catch {}
    return $null
}

# Agent runtime cache — secondary target. Keep in sync with npm-global so gsd
# running inside gsd (agent mode) also sees the new version.
function Resolve-GsdAgentRuntimeRoot {
    return Join-Path $HOME '.gsd\agent\node_modules\gsd-pi'
}

function Get-GsdRuntimeVersion {
    param([Parameter(Mandatory)] [string]$Path)
    $pkgJson = Join-Path $Path 'package.json'
    if (-not (Test-Path $pkgJson)) { return '' }
    try {
        $pkg = Get-Content $pkgJson -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        return [string]$pkg.version
    } catch { return '' }
}

function Get-GsdWezTermRoot {
    if (-not [string]::IsNullOrWhiteSpace($script:ModulesDir)) {
        return [System.IO.Path]::GetFullPath((Join-Path $script:ModulesDir '..'))
    }
    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
}

function Resolve-GsdNamedSource {
    param([Parameter(Mandatory)] [string]$Name)

    $candidates = [System.Collections.Generic.List[object]]::new()

    # If version looks like X.Y.Z, look for baseline-X.Y.Z in cwd project
    $projectRoot = Resolve-GsdProjectRoot
    if ($Name -match '^\d+\.\d+\.\d+') {
        if ($projectRoot) {
            $p = Join-Path $projectRoot (".gsd\vendor\gsd-pi\baseline-{0}" -f $Name)
            if (Test-Path (Join-Path $p 'dist\loader.js')) {
                return [pscustomobject]@{ Path = (Resolve-Path $p).Path; Origin = "cwd-project-baseline-$Name" }
            }
        }
        # search test/ sandboxes
        $wez = Get-GsdWezTermRoot
        foreach ($s in @('latest','baseline')) {
            $p = Join-Path $wez ("test\{0}\.gsd\vendor\gsd-pi\baseline-{1}" -f $s, $Name)
            if (Test-Path (Join-Path $p 'dist\loader.js')) {
                return [pscustomobject]@{ Path = (Resolve-Path $p).Path; Origin = "test-$s-baseline-$Name" }
            }
        }
        return $null
    }

    # Named: latest or baseline
    $named = $Name.ToLowerInvariant()
    if ($named -notin @('latest','baseline','current')) { return $null }

    # Priority 1: cwd project, if sandbox name matches or current/ points to named source
    if ($projectRoot) {
        # If cwd project IS test/<named>, use its current/
        $leaf = Split-Path $projectRoot -Leaf
        if ($leaf -eq $named) {
            $p = Join-Path $projectRoot '.gsd\vendor\gsd-pi\current'
            if (Test-Path (Join-Path $p 'dist\loader.js')) {
                return [pscustomobject]@{ Path = (Resolve-Path $p).Path; Origin = "cwd-project-current-$named" }
            }
        }
        # Otherwise, try current/ regardless (user says "I want this project's active")
        if ($named -eq 'current') {
            $p = Join-Path $projectRoot '.gsd\vendor\gsd-pi\current'
            if (Test-Path (Join-Path $p 'dist\loader.js')) {
                return [pscustomobject]@{ Path = (Resolve-Path $p).Path; Origin = "cwd-project-current" }
            }
        }
    }

    # Priority 2: wezterm/test/<named>
    $wez = Get-GsdWezTermRoot
    $p = Join-Path $wez ("test\{0}\.gsd\vendor\gsd-pi\current" -f $named)
    if (Test-Path (Join-Path $p 'dist\loader.js')) {
        return [pscustomobject]@{ Path = (Resolve-Path $p).Path; Origin = "wezterm-test-$named" }
    }

    return $null
}

function Resolve-GsdPromoteSource {
    param(
        [string]$Explicit = '',
        [string]$Version = ''
    )

    # 1. --from <path>
    if (-not [string]::IsNullOrWhiteSpace($Explicit)) {
        if (Test-Path (Join-Path $Explicit 'dist\loader.js')) {
            return [pscustomobject]@{ Path = (Resolve-Path $Explicit).Path; Origin = 'explicit' }
        }
        $asProject = Join-Path $Explicit '.gsd\vendor\gsd-pi\current'
        if (Test-Path (Join-Path $asProject 'dist\loader.js')) {
            return [pscustomobject]@{ Path = (Resolve-Path $asProject).Path; Origin = 'explicit-project' }
        }
        return $null
    }

    # 2. --version <name>
    if (-not [string]::IsNullOrWhiteSpace($Version)) {
        return Resolve-GsdNamedSource -Name $Version
    }

    # 3. Auto-detect: active current/ of cwd project
    $projectRoot = Resolve-GsdProjectRoot
    if ($projectRoot) {
        $candidate = Join-Path $projectRoot '.gsd\vendor\gsd-pi\current'
        if (Test-Path (Join-Path $candidate 'dist\loader.js')) {
            return [pscustomobject]@{ Path = (Resolve-Path $candidate).Path; Origin = 'auto-cwd-project' }
        }
    }

    # 4. Auto-fallback: wezterm/test/latest then wezterm/test/baseline
    $wez = Get-GsdWezTermRoot
    foreach ($testName in @('latest','baseline')) {
        $candidate = Join-Path $wez ("test\{0}\.gsd\vendor\gsd-pi\current" -f $testName)
        if (Test-Path (Join-Path $candidate 'dist\loader.js')) {
            return [pscustomobject]@{ Path = (Resolve-Path $candidate).Path; Origin = "auto-wezterm-test-$testName" }
        }
    }

    return $null
}

function Get-GsdAvailableSources {
    $list = [System.Collections.Generic.List[object]]::new()

    $projectRoot = Resolve-GsdProjectRoot
    if ($projectRoot) {
        $curr = Join-Path $projectRoot '.gsd\vendor\gsd-pi\current'
        if (Test-Path (Join-Path $curr 'dist\loader.js')) {
            $v = Get-GsdRuntimeVersion -Path $curr
            $list.Add([pscustomobject]@{ Label = 'current (cwd)';       Path = $curr; Version = $v; Tag = 'auto' }) | Out-Null
        }
    }

    $wez = Get-GsdWezTermRoot
    foreach ($testName in @('latest','baseline')) {
        $curr = Join-Path $wez ("test\{0}\.gsd\vendor\gsd-pi\current" -f $testName)
        if (Test-Path (Join-Path $curr 'dist\loader.js')) {
            $v = Get-GsdRuntimeVersion -Path $curr
            $list.Add([pscustomobject]@{ Label = ("test/{0}" -f $testName); Path = $curr; Version = $v; Tag = $testName }) | Out-Null
        }
        # also list explicit baselines in test sandboxes
        $baseDir = Join-Path $wez ("test\{0}\.gsd\vendor\gsd-pi" -f $testName)
        if (Test-Path $baseDir) {
            foreach ($bl in (Get-ChildItem $baseDir -Directory -Filter 'baseline-*' -ErrorAction SilentlyContinue)) {
                $blLoader = Join-Path $bl.FullName 'dist\loader.js'
                if (Test-Path $blLoader) {
                    $v = Get-GsdRuntimeVersion -Path $bl.FullName
                    $tag = $bl.Name.Substring('baseline-'.Length)
                    $label = "test/{0}/{1}" -f $testName, $bl.Name
                    $null = $list.Add([pscustomobject]@{ Label = $label; Path = $bl.FullName; Version = $v; Tag = $tag })
                }
            }
        }
    }

    return $list
}

function Invoke-GsdGlobalStatus {
    $globalRoot = Resolve-GsdGlobalRuntimeRoot
    $source = Resolve-GsdPromoteSource

    Write-Host ''
    Write-HintSection 'GSD GLOBAL STATUS'
    Write-Host ''

    if (Test-Path (Join-Path $globalRoot 'package.json')) {
        $ver = Get-GsdRuntimeVersion -Path $globalRoot
        Write-Host ("  global runtime : {0}  v{1}" -f $globalRoot, $ver) -ForegroundColor White
    } else {
        Write-Host ("  global runtime : {0}  [MISSING]" -f $globalRoot) -ForegroundColor DarkYellow
    }

    $parent = Split-Path $globalRoot -Parent
    $backups = @()
    if (Test-Path $parent) {
        $backups = Get-ChildItem $parent -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'gsd-pi.bak-*' } |
            Sort-Object Name -Descending
    }
    if ($backups.Count -gt 0) {
        Write-Host ''
        Write-Host '  backups (newest first)' -ForegroundColor Cyan
        foreach ($b in $backups) {
            $ver = Get-GsdRuntimeVersion -Path $b.FullName
            Write-Host ("    {0,-48} v{1}" -f $b.Name, $ver) -ForegroundColor DarkGray
        }
    }

    $avail = Get-GsdAvailableSources
    Write-Host ''
    Write-Host '  available promote sources' -ForegroundColor Cyan
    if ($avail.Count -eq 0) {
        Write-Host '    (none found)' -ForegroundColor DarkYellow
    } else {
        foreach ($s in $avail) {
            $marker = if ($source -and $source.Path -eq $s.Path) { '*' } else { ' ' }
            Write-Host ("    {0} {1,-22} v{2,-10} {3}" -f $marker, $s.Label, $s.Version, $s.Path) -ForegroundColor DarkGray
        }
        Write-Host ''
        Write-Host '    * = would be used by `8sync gsd global promote` (no args)' -ForegroundColor DarkGray
    }

    Write-Host ''
    if ($source) {
        $srcVer = Get-GsdRuntimeVersion -Path $source.Path
        Write-Host '  auto-selected source for promote' -ForegroundColor Cyan
        Write-Host ("    version : v{0}" -f $srcVer) -ForegroundColor White
        Write-Host ("    path    : {0}" -f $source.Path) -ForegroundColor DarkGray
        Write-Host ("    origin  : {0}" -f $source.Origin) -ForegroundColor DarkGray
    } else {
        Write-Host '  auto-selected source : none' -ForegroundColor DarkYellow
        Write-Host '  [hint] `8sync gsd local setup --version latest` first, or pass --version / --from' -ForegroundColor DarkGray
    }
    Write-Host ''
}

function Invoke-GsdGlobalPromote {
    param(
        [switch]$DryRun,
        [switch]$Force,
        [string]$From = '',
        [string]$Version = '',
        [switch]$NoAutoSetup    # opt-out of auto `gsd local setup` when source missing/unbuilt
    )

    $source = Resolve-GsdPromoteSource -Explicit $From -Version $Version

    # ------------------------------------------------------------------
    # AUTO-SETUP: if source not found and caller used --version latest|baseline|X.Y.Z,
    # automatically run `8sync gsd local setup --version <ver>` to build it,
    # then re-resolve. This makes `promote --version latest` a one-shot
    # install + patches + build + promote command.
    # Disable with --no-auto-setup.
    # ------------------------------------------------------------------
    if (-not $source -and -not $NoAutoSetup -and -not [string]::IsNullOrWhiteSpace($Version)) {
        $namedTarget = $Version.ToLowerInvariant()
        $canAutoSetup = $false
        $autoVersionArg = ''

        if ($namedTarget -in @('latest','baseline')) {
            $canAutoSetup = $true
            $autoVersionArg = $namedTarget
        } elseif ($Version -match '^\d+\.\d+\.\d+') {
            $canAutoSetup = $true
            $autoVersionArg = $Version
        }

        if ($canAutoSetup) {
            Write-Host ''
            Write-Host ("  [auto]    source for '{0}' not ready." -f $autoVersionArg) -ForegroundColor Cyan
            Write-Host ("            Running: 8sync gsd local setup --version {0}" -f $autoVersionArg) -ForegroundColor Cyan
            Write-Host '            (pass --no-auto-setup to disable)' -ForegroundColor DarkGray
            Write-Host ''

            if (-not (Get-Command Invoke-GsdLocalSetup -ErrorAction SilentlyContinue)) {
                Write-Host '  [err]     Invoke-GsdLocalSetup not available.' -ForegroundColor Red
                Write-Host '            Load modules/gsd/25-local.ps1 first (8sync reload).' -ForegroundColor DarkGray
                return
            }

            if ($DryRun) {
                Write-Host ("  [dry-run] would run: Invoke-GsdLocalSetup -Version {0} -SkipEnter" -f $autoVersionArg) -ForegroundColor DarkYellow
                Write-Host '  [dry-run] then re-resolve source and promote.' -ForegroundColor DarkYellow
                Write-Host ''
                return
            }

            try {
                Invoke-GsdLocalSetup -Version $autoVersionArg -SkipEnter
            } catch {
                Write-Host ''
                Write-Host ("  [err]     auto-setup failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
                Write-Host '  [hint]    run manually to inspect:' -ForegroundColor DarkGray
                Write-Host ("            8sync gsd local setup --version {0}" -f $autoVersionArg) -ForegroundColor White
                return
            }

            Write-Host ''
            Write-Host '  [auto]    setup finished. Re-resolving promote source...' -ForegroundColor Cyan
            $source = Resolve-GsdPromoteSource -Explicit $From -Version $Version

            if (-not $source) {
                Write-Host ''
                Write-Host '  [err]     source still not resolvable after auto-setup.' -ForegroundColor Red
                Write-Host '            Check setup output above for npm/build errors.' -ForegroundColor DarkGray
                Write-Host '  [retry]   8sync gsd global promote --version ' -NoNewline -ForegroundColor DarkGray
                Write-Host $Version -ForegroundColor White
                Write-Host ''
                return
            }

            Write-Host ("  [ok]      source resolved: v{0}  ({1})" -f (Get-GsdRuntimeVersion -Path $source.Path), $source.Origin) -ForegroundColor Green
            Write-Host '            continuing with promote...' -ForegroundColor DarkGray
        }
    }

    if (-not $source) {
        Write-Host ''
        Write-Host '  [err]     no promote source found.' -ForegroundColor Red

        # Detect unbuilt source (common case): current/ exists but dist/loader.js missing
        $wez = Get-GsdWezTermRoot
        $unbuilt = @()
        foreach ($name in @('latest','baseline')) {
            $candidate = Join-Path $wez ("test\{0}\.gsd\vendor\gsd-pi\current" -f $name)
            if ((Test-Path (Join-Path $candidate 'package.json')) -and -not (Test-Path (Join-Path $candidate 'dist\loader.js'))) {
                $unbuilt += [pscustomobject]@{ Name = $name; Path = $candidate }
            }
        }

        if ($unbuilt.Count -gt 0) {
            Write-Host '  [diag]    source exists but is NOT built (no dist/loader.js):' -ForegroundColor Yellow
            foreach ($u in $unbuilt) {
                Write-Host ("            test/{0}/  -> {1}" -f $u.Name, $u.Path) -ForegroundColor DarkYellow
            }
            Write-Host ''
            Write-Host '  [fix]     auto-setup was disabled (--no-auto-setup). Run manually:' -ForegroundColor Green
            $firstName = $unbuilt[0].Name
            Write-Host ("            8sync gsd local setup --version {0}" -f $firstName) -ForegroundColor White
            Write-Host ("            8sync gsd global promote --version {0}" -f $firstName) -ForegroundColor White
            Write-Host ''
        } else {
            Write-Host '  [hint]    options:' -ForegroundColor DarkGray
            Write-Host '            1. --version latest       use wezterm/test/latest active current/' -ForegroundColor DarkGray
            Write-Host '            2. --version baseline     use wezterm/test/baseline active current/' -ForegroundColor DarkGray
            Write-Host '            3. --version 2.69.0       specific baseline directory' -ForegroundColor DarkGray
            Write-Host '            4. --from <path>          explicit path (project or current/ dir)' -ForegroundColor DarkGray
            Write-Host '            5. cd into a project with .gsd/vendor/gsd-pi/current/' -ForegroundColor DarkGray
            Write-Host ''
            Write-Host '  Run `8sync gsd global status` to list available sources.' -ForegroundColor DarkGray
            Write-Host ''
        }
        return
    }

    $globalRoot = Resolve-GsdGlobalRuntimeRoot
    $globalParent = Split-Path $globalRoot -Parent
    $sourceVer = Get-GsdRuntimeVersion -Path $source.Path
    $globalVer = Get-GsdRuntimeVersion -Path $globalRoot

    Write-Host ''
    Write-Host '  [gsd global] promote' -ForegroundColor Cyan
    Write-Host ("  source     : v{0}  ({1})" -f $sourceVer, $source.Origin) -ForegroundColor White
    Write-Host ("               {0}" -f $source.Path) -ForegroundColor DarkGray
    Write-Host ("  global     : v{0}" -f $globalVer) -ForegroundColor White
    Write-Host ("               {0}" -f $globalRoot) -ForegroundColor DarkGray
    Write-Host ''

    if ([string]::IsNullOrWhiteSpace($sourceVer)) {
        Write-Host '  [err]     cannot read source version. Is the source built?' -ForegroundColor Red
        return
    }

    if (-not (Test-Path (Join-Path $source.Path 'dist\loader.js'))) {
        Write-Host '  [err]     source has no dist/loader.js. Run `8sync gsd local build` first.' -ForegroundColor Red
        return
    }

    if ($sourceVer -eq $globalVer -and -not $Force) {
        Write-Host ("  [skip]    source and global are both v{0}. Use --force to overwrite anyway." -f $sourceVer) -ForegroundColor DarkYellow
        return
    }

    $backupName = 'gsd-pi.bak-{0}-{1}' -f $globalVer, (Get-Date -Format 'yyyyMMdd-HHmmss')
    $backupPath = Join-Path $globalParent $backupName

    if (Test-Path $globalRoot) {
        if ($DryRun) {
            Write-Host ("  [dry-run] rename {0} -> {1}" -f $globalRoot, $backupName) -ForegroundColor DarkYellow
        } else {
            try {
                Write-Host ("  [gsd]     backing up current global to {0}" -f $backupName) -ForegroundColor Cyan
                Move-Item -LiteralPath $globalRoot -Destination $backupPath -Force -ErrorAction Stop
                Write-Host '  [ok]      backup done' -ForegroundColor Green
            } catch {
                Write-Host ("  [err]     backup failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
                return
            }
        }
    }

    if ($DryRun) {
        Write-Host ("  [dry-run] robocopy {0} {1} /E /XD node_modules .git" -f $source.Path, $globalRoot) -ForegroundColor DarkYellow
        Write-Host '  [dry-run] bridge global node_modules -> source node_modules' -ForegroundColor DarkYellow
        return
    }

    Write-Host '  [gsd]     copying source to global (exclude node_modules)...' -ForegroundColor Cyan
    $null = New-Item -Path $globalRoot -ItemType Directory -Force
    try {
        & robocopy $source.Path $globalRoot /E /XD node_modules .git /NFL /NDL /NJH /NJS /NP | Out-Null
        Write-Host '  [ok]      source copied' -ForegroundColor Green
    } catch {
        Write-Host ("  [err]     copy failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
        return
    }

    $sourceNm = Join-Path $source.Path 'node_modules'
    $globalNm = Join-Path $globalRoot 'node_modules'
    if (Test-Path $sourceNm) {
        try {
            if (Test-Path $globalNm) { Remove-Item -LiteralPath $globalNm -Recurse -Force -ErrorAction Stop }
            $null = New-Item -Path $globalNm -ItemType Junction -Target $sourceNm -Force
            Write-Host ("  [ok]      bridged global node_modules -> source node_modules") -ForegroundColor Green
            Write-Host ("  [warn]    global now depends on source path. Do not delete: {0}" -f $source.Path) -ForegroundColor DarkYellow
        } catch {
            Write-Host ("  [warn]    node_modules bridge failed: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
            Write-Host '  [hint]    run `npm install` inside global gsd-pi manually' -ForegroundColor DarkGray
        }
    }

    # ------------------------------------------------------------------
    # Sync agent runtime cache (~/.gsd/agent/node_modules/gsd-pi).
    # gsd loads extensions/plugins from here when running; must match the
    # CLI-resolved version in npm-global or users see mixed behavior.
    # ------------------------------------------------------------------
    $agentRoot = Resolve-GsdAgentRuntimeRoot
    if ($agentRoot -and $agentRoot -ne $globalRoot) {
        $agentParent = Split-Path $agentRoot -Parent
        if (-not (Test-Path $agentParent)) {
            $null = New-Item -Path $agentParent -ItemType Directory -Force
        }

        # Backup existing agent runtime alongside npm-global backup
        if (Test-Path $agentRoot) {
            $agentBackupName = 'gsd-pi.bak-{0}-{1}-agent' -f (Get-GsdRuntimeVersion -Path $agentRoot), (Get-Date -Format 'yyyyMMdd-HHmmss')
            $agentBackupPath = Join-Path $agentParent $agentBackupName
            try {
                Move-Item -LiteralPath $agentRoot -Destination $agentBackupPath -Force -ErrorAction Stop
                Write-Host ("  [ok]      agent runtime backed up to {0}" -f $agentBackupName) -ForegroundColor Green
            } catch {
                Write-Host ("  [warn]    could not back up agent runtime: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
            }
        }

        # Junction from agent runtime -> npm-global (single source of truth)
        try {
            $null = New-Item -Path $agentRoot -ItemType Junction -Target $globalRoot -Force -ErrorAction Stop
            Write-Host ("  [ok]      agent runtime junctioned -> {0}" -f $globalRoot) -ForegroundColor Green
        } catch {
            # Fallback: copy if junction fails (e.g. non-NTFS)
            try {
                & robocopy $globalRoot $agentRoot /E /XJ /NFL /NDL /NJH /NJS /NP | Out-Null
                Write-Host '  [ok]      agent runtime synced via copy (junction failed)' -ForegroundColor Green
            } catch {
                Write-Host ("  [warn]    agent runtime sync failed: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
            }
        }
    }

    $claudeBundle = Invoke-GsdClaudeFix
    if ($claudeBundle.ClaudePath.Status -in @('configured','rewritten','already-correct')) {
        Write-Host ("  [claude]  native binary {0}: {1}" -f $claudeBundle.ClaudePath.Status, $claudeBundle.ClaudePath.NativePath) -ForegroundColor Green
    }
    if ($claudeBundle.Settings -and $claudeBundle.Settings.Status -eq 'rewritten') {
        Write-Host '  [claude]  rewrote settings.json default provider/model -> claude-code' -ForegroundColor Green
    }
    if ($claudeBundle.GlobalClaude -and $claudeBundle.GlobalClaude.Status -eq 'written') {
        Write-Host ("  [claude]  wrote global settings: {0}" -f $claudeBundle.GlobalClaude.Path) -ForegroundColor Green
    }
    if ($claudeBundle.Preferences -and $claudeBundle.Preferences.Status -eq 'rewritten') {
        Write-Host ("  [claude]  rewrote {0} Anthropic route(s) -> claude-code in PREFERENCES.md" -f $claudeBundle.Preferences.Replacements) -ForegroundColor Green
    }

    Write-Host ''
    Write-Host '  Verify' -ForegroundColor Yellow
    Write-Host '    gsd --version     # should show new version' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  Rollback' -ForegroundColor Yellow
    Write-Host ("    8sync gsd global rollback   # restores {0}" -f $backupName) -ForegroundColor DarkGray
    Write-Host ''
}

function Invoke-GsdGlobalRollback {
    param(
        [switch]$DryRun,
        [string]$Backup = ''
    )

    $globalRoot = Resolve-GsdGlobalRuntimeRoot
    $globalParent = Split-Path $globalRoot -Parent

    if (-not (Test-Path $globalParent)) {
        Write-Host '  [err]     global agent parent missing.' -ForegroundColor Red
        return
    }

    $backups = Get-ChildItem $globalParent -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'gsd-pi.bak-*' } |
        Sort-Object Name -Descending

    if ($backups.Count -eq 0) {
        Write-Host '  [err]     no backup found to rollback.' -ForegroundColor Red
        return
    }

    $selected = $null
    if (-not [string]::IsNullOrWhiteSpace($Backup)) {
        $selected = $backups | Where-Object { $_.Name -eq $Backup -or $_.FullName -eq $Backup } | Select-Object -First 1
        if (-not $selected) {
            Write-Host ("  [err]     backup '{0}' not found. Available:" -f $Backup) -ForegroundColor Red
            foreach ($b in $backups) { Write-Host ("    - {0}" -f $b.Name) -ForegroundColor DarkGray }
            return
        }
    } else {
        $selected = $backups | Select-Object -First 1
    }

    $selectedVer = Get-GsdRuntimeVersion -Path $selected.FullName
    Write-Host ''
    Write-Host '  [gsd global] rollback' -ForegroundColor Cyan
    Write-Host ("  from   : v{0}  {1}" -f $selectedVer, $selected.FullName) -ForegroundColor DarkGray
    Write-Host ("  to     : {0}" -f $globalRoot) -ForegroundColor DarkGray
    Write-Host ''

    if ($DryRun) {
        Write-Host ("  [dry-run] remove {0}" -f $globalRoot) -ForegroundColor DarkYellow
        Write-Host ("  [dry-run] move {0} -> {1}" -f $selected.FullName, $globalRoot) -ForegroundColor DarkYellow
        return
    }

    try {
        if (Test-Path $globalRoot) {
            $stashName = 'gsd-pi.bak-rollback-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss')
            $stashPath = Join-Path $globalParent $stashName
            Move-Item -LiteralPath $globalRoot -Destination $stashPath -Force -ErrorAction Stop
            Write-Host ("  [ok]      current global stashed as {0}" -f $stashName) -ForegroundColor Green
        }
        Move-Item -LiteralPath $selected.FullName -Destination $globalRoot -Force -ErrorAction Stop
        Write-Host ("  [ok]      restored global from {0}" -f $selected.Name) -ForegroundColor Green
    } catch {
        Write-Host ("  [err]     rollback failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
        return
    }

    Write-Host ''
    Write-Host '  Verify' -ForegroundColor Yellow
    Write-Host '    gsd --version' -ForegroundColor DarkGray
    Write-Host ''
}

function Show-GsdGlobalHelp {
    Write-Host ''
    Write-HintSection 'GSD GLOBAL -- promote local runtime, rollback, inspect'
    Write-Host ''
    Write-Host '  Commands' -ForegroundColor Cyan
    Write-Host '    8sync gsd global                     Status: current version + backups + sources' -ForegroundColor White
    Write-Host '    8sync gsd global status              Same as above' -ForegroundColor White
    Write-Host '    8sync gsd global promote             Auto-detect source, back up, promote' -ForegroundColor White
    Write-Host '    8sync gsd global promote --version latest     Use wezterm/test/latest + auto-fix Claude Code path/settings' -ForegroundColor White
    Write-Host '    8sync gsd global promote --version baseline   Use wezterm/test/baseline' -ForegroundColor White
    Write-Host '    8sync gsd global promote --version 2.69.0     Specific baseline-X.Y.Z' -ForegroundColor White
    Write-Host '    8sync gsd global promote --from <path>        Explicit source path' -ForegroundColor White
    Write-Host '    8sync gsd global promote --dry-run            Preview, no changes' -ForegroundColor White
    Write-Host '    8sync gsd global promote --force              Promote even if versions match' -ForegroundColor White
    Write-Host '    8sync gsd global rollback            Restore most recent backup' -ForegroundColor White
    Write-Host '    8sync gsd global rollback --backup <name>     Restore specific backup' -ForegroundColor White
    Write-Host '    8sync gsd global help                This help' -ForegroundColor White
    Write-Host ''
    Write-Host '  Source resolution (no args)' -ForegroundColor Cyan
    Write-Host '    1. cwd project .gsd/vendor/gsd-pi/current/  (if inside one)' -ForegroundColor DarkGray
    Write-Host '    2. wezterm/test/latest/.gsd/vendor/gsd-pi/current/' -ForegroundColor DarkGray
    Write-Host '    3. wezterm/test/baseline/.gsd/vendor/gsd-pi/current/' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  Source resolution (--version X)' -ForegroundColor Cyan
    Write-Host '    latest|baseline   -> wezterm/test/<X>/.gsd/vendor/gsd-pi/current/' -ForegroundColor DarkGray
    Write-Host '    X.Y.Z             -> <project>/.gsd/vendor/gsd-pi/baseline-X.Y.Z/' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  Safety' -ForegroundColor Yellow
    Write-Host '    - backs up global to gsd-pi.bak-<ver>-<timestamp> before promote' -ForegroundColor DarkGray
    Write-Host '    - never deletes ~/.gsd/agent/{auth.json, settings.json, sessions, gsd.db}' -ForegroundColor DarkGray
    Write-Host '    - rollback stashes current global (un-rollback possible)' -ForegroundColor DarkGray
    Write-Host '    - skips promote if source and global versions match (use --force to override)' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  Typical workflow' -ForegroundColor Yellow
    Write-Host '    cd wezterm/test/latest                    # or any project with local runtime' -ForegroundColor DarkGray
    Write-Host '    8sync gsd local fix --stable              # ensure source is patched' -ForegroundColor DarkGray
    Write-Host '    8sync gsd global status                   # check what will be used' -ForegroundColor DarkGray
    Write-Host '    8sync gsd global promote --dry-run        # preview' -ForegroundColor DarkGray
    Write-Host '    8sync gsd global promote                  # commit' -ForegroundColor DarkGray
    Write-Host '    gsd --version                             # verify' -ForegroundColor DarkGray
    Write-Host '    # if anything breaks:' -ForegroundColor DarkGray
    Write-Host '    8sync gsd global rollback                 # revert' -ForegroundColor DarkGray
    Write-Host ''
}

function Invoke-GsdGlobalCommand {
    param([string[]]$Rest)

    $dryRun = $Rest -contains '--dry-run'
    $force = $Rest -contains '--force'
    $noAutoSetup = $Rest -contains '--no-auto-setup'
    $noAutoSetup = $Rest -contains '--no-auto-setup'

    $fromArg = ''
    $fromIdx = [Array]::IndexOf($Rest, '--from')
    if ($fromIdx -ge 0 -and $fromIdx + 1 -lt $Rest.Count) { $fromArg = $Rest[$fromIdx + 1] }
    $fromEq = $Rest | Where-Object { $_ -like '--from=*' } | Select-Object -First 1
    if ($fromEq) { $fromArg = $fromEq -replace '^--from=', '' }

    $versionArg = ''
    $versionIdx = [Array]::IndexOf($Rest, '--version')
    if ($versionIdx -ge 0 -and $versionIdx + 1 -lt $Rest.Count) { $versionArg = $Rest[$versionIdx + 1] }
    $versionEq = $Rest | Where-Object { $_ -like '--version=*' } | Select-Object -First 1
    if ($versionEq) { $versionArg = $versionEq -replace '^--version=', '' }

    $backupArg = ''
    $backupIdx = [Array]::IndexOf($Rest, '--backup')
    if ($backupIdx -ge 0 -and $backupIdx + 1 -lt $Rest.Count) { $backupArg = $Rest[$backupIdx + 1] }

    $sub = if ($Rest.Count -gt 0 -and $Rest[0] -notlike '--*') { $Rest[0].ToLowerInvariant() } else { '' }

    switch ($sub) {
        ''          { Invoke-GsdGlobalStatus }
        'status'    { Invoke-GsdGlobalStatus }
        'help'      { Show-GsdGlobalHelp }
        'promote'   { Invoke-GsdGlobalPromote -DryRun:$dryRun -Force:$force -From $fromArg -Version $versionArg -NoAutoSetup:$noAutoSetup }
        'rollback'  { Invoke-GsdGlobalRollback -DryRun:$dryRun -Backup $backupArg }
        default     {
            Write-Host ("  [err]     unknown subcommand '{0}'" -f $sub) -ForegroundColor Red
            Show-GsdGlobalHelp
        }
    }
}
