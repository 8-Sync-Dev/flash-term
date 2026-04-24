# =============================================================================
# 8sync gsd nuke -- deep, complete removal of ALL gsd-pi artifacts
# =============================================================================
# Covers every known install vector on Windows:
#   - npm -g, bun -g
#   - %APPDATA%/npm/node_modules and shims
#   - ~/scoop/shims and persist/nodejs-lts bins
#   - %LOCALAPPDATA%/npm-cache/_npx entries
#   - ~/.gsd/  (agent, auth, db, resource-loader shim, prefs)
#   - ~/.gsd-cache/
#   - project-local .gsd/vendor/gsd-pi/ (if cwd is inside a project)
#
# Usage:
#   8sync gsd nuke [--dry-run] [--yes] [--keep-home] [--project-only]
# =============================================================================

function Invoke-GsdNuke {
    param(
        [switch]$DryRun,
        [switch]$Yes,
        [switch]$KeepHome,
        [switch]$ProjectOnly
    )

    # ---- helpers --------------------------------------------------------

    function Write-NukeStep  { param([string]$m) Write-Host ("`n  [nuke] {0}" -f $m) -ForegroundColor Cyan }
    function Write-NukeOk    { param([string]$m) Write-Host ("    [ok]      {0}" -f $m) -ForegroundColor Green }
    function Write-NukeWarn  { param([string]$m) Write-Host ("    [warn]    {0}" -f $m) -ForegroundColor DarkYellow }
    function Write-NukeDry   { param([string]$m) Write-Host ("    [dry-run] {0}" -f $m) -ForegroundColor Yellow }
    function Write-NukeSkip  { param([string]$m) Write-Host ("    [skip]    {0}" -f $m) -ForegroundColor DarkGray }

    function Remove-DeepPath {
        param(
            [Parameter(Mandatory)][string]$Path,
            [string]$Label,
            [switch]$Wildcard
        )

        $displayLabel = if ($Label) { $Label } else { $Path }

        $items = @()
        try {
            if ($Wildcard) {
                $items = @(Get-ChildItem -Path $Path -Force -ErrorAction SilentlyContinue)
            } elseif (Test-Path -LiteralPath $Path) {
                $items = @(Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue)
            }
        } catch { $items = @() }

        if (-not $items -or $items.Count -eq 0) {
            Write-NukeSkip ("not found: {0}" -f $displayLabel)
            return
        }

        foreach ($item in $items) {
            if ($DryRun) {
                Write-NukeDry ("would remove: {0}" -f $item.FullName)
                continue
            }
            try {
                if ($item.PSIsContainer) {
                    Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
                } else {
                    Remove-Item -LiteralPath $item.FullName -Force -ErrorAction Stop
                }
                Write-NukeOk ("removed: {0}" -f $item.FullName)
            } catch {
                Write-NukeWarn ("could not remove {0}: {1}" -f $item.FullName, $_.Exception.Message)
            }
        }
    }

    function Invoke-GlobalUninstall {
        param([string]$Bin, [string[]]$Args, [string]$Label)
        if (-not (Get-Command $Bin -ErrorAction SilentlyContinue)) {
            Write-NukeSkip ("{0} not found" -f $Bin)
            return
        }
        if ($DryRun) {
            Write-NukeDry ("would run: {0} {1}" -f $Bin, ($Args -join ' '))
            return
        }
        try {
            & $Bin @Args 2>&1 | Out-Null
            Write-NukeOk $Label
        } catch {
            Write-NukeWarn ("{0}: {1}" -f $Label, $_.Exception.Message)
        }
    }

    # ---- banner ---------------------------------------------------------

    Write-Host ''
    Write-Host '  GSD-PI DEEP NUKE' -ForegroundColor Red
    Write-Host '  Removes ALL gsd-pi artifacts: packages, shims, cache, home dir, project vendor.' -ForegroundColor DarkGray
    if ($DryRun) {
        Write-Host '  MODE: DRY RUN -- no files will be deleted.' -ForegroundColor Yellow
    }
    Write-Host ''

    # ---- confirmation ---------------------------------------------------

    if (-not $DryRun -and -not $Yes) {
        Write-Host '  This will permanently delete:' -ForegroundColor DarkYellow
        if (-not $ProjectOnly) {
            Write-Host '    * npm/bun global gsd-pi package' -ForegroundColor DarkGray
            Write-Host '    * All gsd-pi shims (scoop, npm)' -ForegroundColor DarkGray
            Write-Host '    * npm _npx cache entries for gsd*' -ForegroundColor DarkGray
            if (-not $KeepHome) {
                Write-Host '    * ~/.gsd/  (auth, db, prefs, agent, everything)' -ForegroundColor DarkGray
                Write-Host '    * ~/.gsd-cache/' -ForegroundColor DarkGray
            }
        }
        Write-Host '    * <project>/.gsd/vendor/gsd-pi/ (if inside a project)' -ForegroundColor DarkGray
        Write-Host ''
        Write-Host '  Add --yes to skip this prompt, or --dry-run to preview.' -ForegroundColor DarkGray
        Write-Host ''
        $answer = Read-Host '  Type YES to continue'
        if ($answer -ne 'YES') {
            Write-Host '  Aborted.' -ForegroundColor DarkYellow
            Write-Host ''
            return
        }
    }

    $homePath     = [Environment]::GetFolderPath('UserProfile')
    $appData      = [Environment]::GetFolderPath('ApplicationData')
    $localAppData = [Environment]::GetFolderPath('LocalApplicationData')

    # ---- 1. project-local vendor ----------------------------------------

    Write-NukeStep 'Project-local .gsd/vendor/gsd-pi/'
    $projectRoot = Resolve-GsdProjectRoot
    if ($projectRoot) {
        $vendorGsdPi = Join-Path $projectRoot '.gsd\vendor\gsd-pi'
        Remove-DeepPath -Path $vendorGsdPi -Label ('.gsd/vendor/gsd-pi/ under ' + $projectRoot)
    } else {
        Write-NukeSkip 'Not inside a GSD project (no .gsd/ found in parent chain)'
    }

    if ($ProjectOnly) {
        Write-Host ''
        Write-Host '  --project-only: stopped after project-local cleanup.' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    # ---- 2. global package managers ------------------------------------

    Write-NukeStep 'Uninstall global npm package'
    Invoke-GlobalUninstall -Bin 'npm' -Args @('uninstall', '-g', 'gsd-pi') -Label 'npm uninstall -g gsd-pi'

    Write-NukeStep 'Uninstall global bun package'
    Invoke-GlobalUninstall -Bin 'bun' -Args @('pm', 'rm', '-g', 'gsd-pi') -Label 'bun pm rm -g gsd-pi'

    # ---- 3. %APPDATA%/npm node_modules ---------------------------------

    Write-NukeStep '%APPDATA%/npm/node_modules -- gsd-pi and @gsd scope'
    Remove-DeepPath -Path (Join-Path $appData 'npm\node_modules\gsd-pi') -Label '%APPDATA%/npm/node_modules/gsd-pi'
    Remove-DeepPath -Path (Join-Path $appData 'npm\node_modules\@gsd')   -Label '%APPDATA%/npm/node_modules/@gsd'

    Write-NukeStep '%APPDATA%/npm/ -- gsd* shims'
    Remove-DeepPath -Path (Join-Path $appData 'npm\gsd*') -Label '%APPDATA%/npm/gsd* shims' -Wildcard

    # ---- 4. scoop shims + persist node_modules -------------------------

    Write-NukeStep 'scoop/shims -- gsd* shims'
    Remove-DeepPath -Path (Join-Path $homePath 'scoop\shims\gsd*') -Label 'scoop/shims/gsd*' -Wildcard

    Write-NukeStep 'scoop persist nodejs-lts -- gsd-pi node_modules'
    $scoopBin = Join-Path $homePath 'scoop\persist\nodejs-lts\bin'
    Remove-DeepPath -Path (Join-Path $scoopBin 'node_modules\gsd-pi')       -Label 'scoop nodejs-lts/node_modules/gsd-pi'
    Remove-DeepPath -Path (Join-Path $scoopBin 'node_modules\@gsd')         -Label 'scoop nodejs-lts/node_modules/@gsd'
    Remove-DeepPath -Path (Join-Path $scoopBin 'node_modules\.bin\gsd*')    -Label 'scoop nodejs-lts/.bin/gsd*' -Wildcard

    # scoop apps/nodejs-lts/current/bin mirror
    $scoopAppBin = Join-Path $homePath 'scoop\apps\nodejs-lts\current\bin'
    Remove-DeepPath -Path (Join-Path $scoopAppBin 'node_modules\gsd-pi')    -Label 'scoop apps/nodejs-lts/current/node_modules/gsd-pi'
    Remove-DeepPath -Path (Join-Path $scoopAppBin 'node_modules\@gsd')      -Label 'scoop apps/nodejs-lts/current/node_modules/@gsd'
    Remove-DeepPath -Path (Join-Path $scoopAppBin 'node_modules\.bin\gsd*') -Label 'scoop apps/nodejs-lts/current/.bin/gsd*' -Wildcard

    # ---- 5. npm _npx cache ---------------------------------------------

    Write-NukeStep '%LOCALAPPDATA%/npm-cache/_npx -- gsd* entries'
    Remove-DeepPath -Path (Join-Path $localAppData 'npm-cache\_npx\*gsd*') -Label 'npm-cache/_npx/*gsd*' -Wildcard

    # ---- 6. ~/.gsd and ~/.gsd-cache ------------------------------------

    if (-not $KeepHome) {
        Write-NukeStep '~/.gsd (agent, auth, db, resource-loader shim, prefs, everything)'
        Remove-DeepPath -Path (Join-Path $homePath '.gsd')       -Label '~/.gsd'

        Write-NukeStep '~/.gsd-cache'
        Remove-DeepPath -Path (Join-Path $homePath '.gsd-cache') -Label '~/.gsd-cache'
    } else {
        Write-NukeStep '~/.gsd -- skipped (--keep-home)'
        Write-NukeSkip '~/.gsd and ~/.gsd-cache preserved (--keep-home)'
    }

    # ---- done ----------------------------------------------------------

    Write-Host ''
    Write-Host '  Nuke complete.' -ForegroundColor Green
    if (-not $DryRun) {
        Write-Host ''
        Write-Host '  To reinstall from scratch:' -ForegroundColor DarkGray
        Write-Host '    8sync gsd setup   or   8sync gsd local init' -ForegroundColor White
    }
    Write-Host ''
}
