function Ensure-ScoopBuckets {
    param(
        [Parameter(Mandatory)] [object]$Scoop,
        [string[]]$Buckets = @('extras')
    )

    try {
        $existing = & $Scoop.Source bucket list 2>$null | ForEach-Object { "$_".Trim() }
    } catch {
        $existing = @()
    }

    foreach ($bucket in $Buckets) {
        if ($existing -notcontains $bucket) {
            Write-Host ("Adding Scoop bucket: {0}" -f $bucket) -ForegroundColor Yellow
            try {
                & $Scoop.Source bucket add $bucket 2>&1 | Out-Host
            } catch {
                Write-Warning ("Failed to add bucket '{0}': {1}" -f $bucket, $_.Exception.Message)
            }
        }
    }
}

function Invoke-ToolSync {
    param(
        [switch]$Quiet,
        [switch]$Check
    )

    $scoop = Get-ScoopCommand
    if (-not $scoop) {
        if (-not $Quiet) {
            Write-Warning 'Scoop was not found. Install Scoop first, then run /8sync sync.'
        }
        return
    }

    # --check: dry-run report of missing + outdated, no install/update
    if ($Check) {
        Write-Host ''
        Write-Host '  8sync sync --check  (dry-run — no changes made)' -ForegroundColor Cyan
        Write-Host ''

        # Missing tools
        $missingPackages = Get-MissingPackages
        if ($missingPackages.Count -gt 0) {
            Write-Host '  MISSING' -ForegroundColor Yellow
            foreach ($pkg in $missingPackages) {
                $cmd = ($script:ToolPackages.GetEnumerator() | Where-Object { $_.Value -eq $pkg } | Select-Object -First 1).Key
                Write-Host ('    {0,-20} scoop install {1}' -f $pkg, $pkg) -ForegroundColor DarkGray
            }
            Write-Host ''
        } else {
            Write-Host '  All managed tools are installed.' -ForegroundColor DarkGray
            Write-Host ''
        }

        # Outdated tools via scoop status
        Write-Host '  Checking for updates via scoop status...' -ForegroundColor Yellow
        try {
            $statusOut = & $scoop.Source status 2>&1 | Out-String
            # Parse scoop status output: lines with "Name  Installed  Latest"
            $lines = $statusOut -split "`n" | Where-Object { $_ -match '\S' }
            # Find data lines (skip header, separator lines)
            $dataLines = $lines | Where-Object {
                $_ -notmatch '^[-\s]+$' -and
                $_ -notmatch '^Name\s' -and
                $_ -notmatch '^Scoop is up to date' -and
                $_ -notmatch '^Updates are available' -and
                $_ -notmatch '^\s*$'
            }
            # Filter to only managed packages
            $managedNames = @($script:ToolPackages.Values | Select-Object -Unique)
            $outdated = $dataLines | Where-Object {
                $name = ($_ -split '\s+')[0].Trim()
                $managedNames -contains $name
            }
            if ($outdated.Count -gt 0) {
                Write-Host '  UPDATES AVAILABLE' -ForegroundColor Yellow
                Write-Host ('    {0,-20} {1,-12} {2}' -f 'Package', 'Installed', 'Latest') -ForegroundColor DarkGray
                Write-Host ('    {0,-20} {1,-12} {2}' -f ('-' * 18), ('-' * 10), ('-' * 10)) -ForegroundColor DarkGray
                foreach ($line in $outdated) {
                    $parts = $line -split '\s+' | Where-Object { $_ -ne '' }
                    if ($parts.Count -ge 3) {
                        Write-Host ('    {0,-20} {1,-12} {2}' -f $parts[0], $parts[1], $parts[2]) -ForegroundColor White
                    }
                }
                Write-Host ''
                Write-Host '  Run: 8sync sync  to apply updates.' -ForegroundColor DarkGray
            } else {
                Write-Host '  All installed tools are up to date.' -ForegroundColor Green
            }
        } catch {
            Write-Host '  Could not retrieve scoop status.' -ForegroundColor DarkYellow
        }

        Write-Host ''
        return
    }

    Ensure-StateDir
    if (Test-Path $script:SyncLockPath) {
        if (-not $Quiet) {
            Write-Host 'A background sync is already running.' -ForegroundColor DarkYellow
        }
        return
    }

    Set-Content -Path $script:SyncLockPath -Value ([datetime]::UtcNow.ToString('o')) -Encoding ASCII
    try {
        # Ensure required buckets exist before install (lazygit lives in extras)
        Ensure-ScoopBuckets -Scoop $scoop -Buckets @('extras')

        $missingPackages = Get-MissingPackages
        if ($missingPackages.Count -gt 0) {
            if (-not $Quiet) {
                Write-Host ('Installing missing packages: {0}' -f ($missingPackages -join ', ')) -ForegroundColor Yellow
            }
            & $scoop.Source install @missingPackages | Out-Host

            # Refresh PATH so newly installed shims are visible to scoop update
            Ensure-PreferredPaths
        }

        # Only update packages that are now actually installed
        $installedPackages = $script:ToolPackages.GetEnumerator() |
            Where-Object { Test-CommandExists $_.Key } |
            ForEach-Object { $_.Value } |
            Select-Object -Unique

        if ($installedPackages.Count -gt 0) {
            if (-not $Quiet) {
                Write-Host ('Updating managed packages: {0}' -f ($installedPackages -join ', ')) -ForegroundColor Yellow
            }
            & $scoop.Source update @installedPackages | Out-Host
        } elseif (-not $Quiet) {
            Write-Host 'No installed packages to update.' -ForegroundColor DarkGray
        }

        Write-State -LastSyncUtc ([datetime]::UtcNow)
        Clear-MissingCache   # force re-scan on next tab open
        if (-not $Quiet) {
            Write-Host 'Tool sync completed.' -ForegroundColor Green
        }
    } finally {
        Remove-Item $script:SyncLockPath -Force -ErrorAction SilentlyContinue
    }
}

function Start-AutoSync {
    $scoop = Get-ScoopCommand
    if (-not $scoop) {
        return
    }

    if (Test-Path $script:SyncLockPath) {
        try {
            $lockAge = ([datetime]::UtcNow - (Get-Item $script:SyncLockPath).LastWriteTimeUtc).TotalMinutes
            if ($lockAge -gt 30) {
                Remove-Item $script:SyncLockPath -Force -ErrorAction SilentlyContinue
            } else {
                return
            }
        } catch {
            return
        }
    }

    $state = Read-State
    $lastSyncUtc = if ($state.lastSyncUtc) { [datetime]$state.lastSyncUtc } else { $null }
    $missingPackages = Get-MissingPackages
    $shouldSync = $missingPackages.Count -gt 0

    if (-not $shouldSync -and $lastSyncUtc) {
        $hours = ([datetime]::UtcNow - $lastSyncUtc).TotalHours
        $shouldSync = $hours -ge $script:SyncIntervalHours
    } elseif (-not $lastSyncUtc) {
        $shouldSync = $true
    }

    if (-not $shouldSync) {
        return
    }

    $engine = Get-ShellEngine
    if (-not (Test-Path $engine)) {
        return
    }

    $arguments = @(
        '-NoLogo',
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $PSCommandPath,
        '-Task', 'SyncQuiet'
    )

    try {
        Start-Process -FilePath $engine -ArgumentList $arguments -WindowStyle Hidden -ErrorAction Stop | Out-Null
    } catch {
        # Silently ignore auto-sync failures
    }
}
