#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$KeepHome,
    [switch]$KeepNpmCache
)

$ErrorActionPreference = 'Continue'

function Write-Step {
    param([string]$Message)
    Write-Host ("[gsd-remove] {0}" -f $Message) -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host ("  [ok]      {0}" -f $Message) -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host ("  [warn]    {0}" -f $Message) -ForegroundColor DarkYellow
}

function Write-DryRun {
    param([string]$Message)
    Write-Host ("  [dry-run] {0}" -f $Message) -ForegroundColor Yellow
}

function Test-CommandExists {
    param([Parameter(Mandatory)] [string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Invoke-External {
    param(
        [Parameter(Mandatory)] [string]$FilePath,
        [string[]]$Arguments,
        [string]$Label
    )

    $argsText = if ($Arguments -and $Arguments.Count -gt 0) { $Arguments -join ' ' } else { '' }
    $display = if ($argsText) { "$FilePath $argsText" } else { $FilePath }

    if ($DryRun) {
        Write-DryRun ("run {0}" -f $display)
        return
    }

    try {
        & $FilePath @Arguments | Out-Null
        if ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) {
            Write-Ok $Label
        } else {
            Write-Warn ("{0} exited with code {1}" -f $display, $LASTEXITCODE)
        }
    } catch {
        Write-Warn ("Failed to run {0}: {1}" -f $display, $_.Exception.Message)
    }
}

function Remove-PathDeep {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Label,
        [switch]$Wildcard
    )

    $items = @()
    try {
        if ($Wildcard) {
            $items = @(Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue)
            if (-not $items -or $items.Count -eq 0) {
                $items = @(Get-ChildItem -Path $Path -Force -ErrorAction SilentlyContinue)
            }
        } else {
            if (Test-Path -LiteralPath $Path) {
                $items = @(Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue)
            }
        }
    } catch {
        $items = @()
    }

    if (-not $items -or $items.Count -eq 0) {
        Write-Warn ("{0}: not found" -f $Label)
        return
    }

    foreach ($item in $items) {
        if ($DryRun) {
            Write-DryRun ("remove {0}" -f $item.FullName)
            continue
        }

        try {
            if ($item.PSIsContainer) {
                Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
            } else {
                Remove-Item -LiteralPath $item.FullName -Force -ErrorAction Stop
            }
            Write-Ok ("Removed {0}" -f $item.FullName)
        } catch {
            Write-Warn ("Failed to remove {0}: {1}" -f $item.FullName, $_.Exception.Message)
        }
    }
}

Write-Host ''
Write-Step 'Deep remove gsd-2 (gsd-pi@latest)'
if ($DryRun) {
    Write-Host '  Preview mode only. No changes will be made.' -ForegroundColor DarkYellow
}
Write-Host ''

# 1) Remove global package registrations
Write-Step 'Uninstall global packages'
if (Test-CommandExists 'npm') {
    Invoke-External -FilePath 'npm' -Arguments @('uninstall', '-g', 'gsd-pi') -Label 'npm uninstall -g gsd-pi'
} else {
    Write-Warn 'npm not found; skipped npm uninstall'
}

if (Test-CommandExists 'bun') {
    Invoke-External -FilePath 'bun' -Arguments @('pm', 'rm', '-g', 'gsd-pi') -Label 'bun pm rm -g gsd-pi'
} else {
    Write-Warn 'bun not found; skipped bun global uninstall'
}

Write-Host ''

# 2) Remove local runtime + data
Write-Step 'Remove runtime/data directories'
$homePath = [Environment]::GetFolderPath('UserProfile')
$appData = [Environment]::GetFolderPath('ApplicationData')
$localAppData = [Environment]::GetFolderPath('LocalApplicationData')

if (-not $KeepHome) {
    Remove-PathDeep -Path (Join-Path $homePath '.gsd') -Label '~/.gsd'
    Remove-PathDeep -Path (Join-Path $homePath '.gsd-cache') -Label '~/.gsd-cache'
} else {
    Write-Warn 'KeepHome enabled: skipped ~/.gsd and ~/.gsd-cache'
}

Remove-PathDeep -Path (Join-Path $appData 'npm\node_modules\gsd-pi') -Label '%APPDATA%/npm/node_modules/gsd-pi'
Remove-PathDeep -Path (Join-Path $appData 'npm\node_modules\@gsd') -Label '%APPDATA%/npm/node_modules/@gsd'

Remove-PathDeep -Path (Join-Path $appData 'npm\gsd*') -Label '%APPDATA%/npm/gsd* shims' -Wildcard
Remove-PathDeep -Path (Join-Path $homePath 'scoop\shims\gsd*') -Label '%USERPROFILE%/scoop/shims/gsd*' -Wildcard

Remove-PathDeep -Path (Join-Path $homePath 'scoop\persist\nodejs-lts\bin\node_modules\gsd-pi') -Label 'scoop node_modules/gsd-pi'
Remove-PathDeep -Path (Join-Path $homePath 'scoop\persist\nodejs-lts\bin\node_modules\@gsd') -Label 'scoop node_modules/@gsd'
Remove-PathDeep -Path (Join-Path $homePath 'scoop\persist\nodejs-lts\bin\node_modules\.bin\gsd*') -Label 'scoop .bin/gsd*' -Wildcard

if (-not $KeepNpmCache) {
    Remove-PathDeep -Path (Join-Path $localAppData 'npm-cache\_npx\*gsd*') -Label '%LOCALAPPDATA%/npm-cache/_npx/*gsd*' -Wildcard
} else {
    Write-Warn 'KeepNpmCache enabled: skipped npm _npx gsd cache cleanup'
}

Write-Host ''
Write-Host 'Done. If you also want to remove 8sync gsd commands from this repo shell, edit modules/startup.ps1 + modules/shell.ps1 + modules/core.ps1 and remove gsd entries.' -ForegroundColor DarkGray
Write-Host ''
