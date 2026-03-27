# ---------------------------------------------------------------------------
#  8sync clean -- deep system / RAM / venv cleaner
# ---------------------------------------------------------------------------

function Format-Bytes {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:F2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:F1} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:F0} KB' -f ($Bytes / 1KB)) }
    return ('{0} B' -f $Bytes)
}

# Spinner state -- shared across the clean session
$script:CleanSpinnerFrames = @('-','\\','|','/')
$script:CleanSpinnerIdx    = 0
$script:CleanTotalFreed    = [long]0
$script:CleanTotalFiles    = 0

# Spinner guard: only use \r-overwrite trick on a real interactive console.
# Extra checks beyond ConsoleHost:
#   - Width must be readable and sane (20..300) -- rules out SSH/tmux/redir
#   - Not output-redirected (pipe, file, capture)
#   - WindowSize must not throw (non-interactive hosts do)
$script:CleanIsConsole = $false
if ($Host.Name -eq 'ConsoleHost' -and
    -not [System.Console]::IsOutputRedirected -and
    -not [System.Console]::IsInputRedirected) {
    try {
        $w = $Host.UI.RawUI.WindowSize.Width
        if ($w -ge 20 -and $w -le 300) {
            $script:CleanIsConsole = $true
        }
    } catch {}
}

function Get-SafeTermWidth {
    $w = 80
    try { $w = $Host.UI.RawUI.WindowSize.Width } catch {}
    if ($w -lt 20 -or $w -gt 300) { $w = 80 }
    return $w
}

function Write-CleanSpinner {
    param([string]$Msg, [string]$Counter = '')
    if (-not $script:CleanIsConsole) { return }
    $frame = $script:CleanSpinnerFrames[$script:CleanSpinnerIdx % $script:CleanSpinnerFrames.Count]
    $script:CleanSpinnerIdx++
    $termWidth = Get-SafeTermWidth
    # Truncate long paths so line never wraps
    $maxMsg = $termWidth - 32
    if ($Msg.Length -gt $maxMsg -and $maxMsg -gt 8) { $Msg = '...' + $Msg.Substring($Msg.Length - ($maxMsg - 3)) }
    $line = ('  {0} {1}  {2}' -f $frame, $Msg, $Counter).PadRight($termWidth - 1)
    # Overwrite same line via \r -- stays on one line, no scroll
    [System.Console]::Write("`r" + $line)
}

function Clear-SpinnerLine {
    if (-not $script:CleanIsConsole) { return }
    $termWidth = Get-SafeTermWidth
    [System.Console]::Write("`r" + (' ' * ($termWidth - 1)) + "`r")
}

function Write-CleanResult {
    param([string]$Label, [int]$FileCount, [long]$Freed, [switch]$DryRun, [switch]$Skipped)
    Clear-SpinnerLine
    if ($Skipped) { return }   # path didn't exist -- print nothing
    $tag   = if ($DryRun) { ' ~' } else { '' }
    $fStr  = if ($Freed -gt 0) { Format-Bytes $Freed } else { '--' }
    $nStr  = if ($FileCount -gt 0) { ('{0} files' -f $FileCount) } else { '0 files' }
    # colour: green when freed something, dry-run yellow, zero gray
    $color = if ($Freed -gt 0 -and -not $DryRun) { 'Green' } elseif ($DryRun -and $Freed -gt 0) { 'DarkYellow' } else { 'DarkGray' }
    Write-Host ('  {0}{1}  {2}  {3}' -f $Label, $tag, $nStr, $fStr) -ForegroundColor $color
}

# Fast recursive file scan using .NET EnumerateFiles (5-10x faster than Get-ChildItem -Recurse)
function Invoke-CleanPath {
    param(
        [string]$Path,
        [string]$Label,
        [int]$StaleDays = 0,
        [switch]$DryRun,
        [switch]$Recursive
    )

    if (-not (Test-Path $Path)) {
        Write-CleanResult -Label $Label -FileCount 0 -Freed 0 -DryRun:$DryRun -Skipped
        return [long]0
    }

    $cutoff   = if ($StaleDays -gt 0) { (Get-Date).AddDays(-$StaleDays) } else { $null }
    $freed    = [long]0
    $count    = 0
    $spinFreq = 0   # throttle spinner updates

    # Show initial spinner immediately so user knows we started
    Write-CleanSpinner -Msg $Label -Counter 'scanning...'

    try {
        $searchOpt = if ($Recursive) {
            [System.IO.SearchOption]::AllDirectories
        } else {
            [System.IO.SearchOption]::TopDirectoryOnly
        }

        $files = [System.IO.Directory]::EnumerateFiles($Path, '*', $searchOpt)

        foreach ($filePath in $files) {
            # Throttle spinner: update every 500 files -- 1 Console.Write per 500 iterations
            $spinFreq++
            if ($spinFreq -ge 500) {
                $spinFreq = 0
                Write-CleanSpinner -Msg $Label -Counter ('{0} files  {1}' -f $count, (Format-Bytes $freed))
            }

            try {
                $info = [System.IO.FileInfo]::new($filePath)
                if ($cutoff -and $info.LastWriteTime -ge $cutoff) { continue }
                $sz = $info.Length
                if (-not $DryRun) {
                    [System.IO.File]::Delete($filePath)
                }
                $freed += $sz
                $count++
            } catch {}
        }
    } catch {}

    # Remove empty leftover dirs (bottom-up, non-blocking)
    if (-not $DryRun -and $Recursive) {
        try {
            [System.IO.Directory]::EnumerateDirectories($Path, '*', [System.IO.SearchOption]::AllDirectories) |
                Sort-Object { $_.Length } -Descending |
                ForEach-Object {
                    try {
                        if ([System.IO.Directory]::GetFileSystemEntries($_).Count -eq 0) {
                            [System.IO.Directory]::Delete($_)
                        }
                    } catch {}
                }
        } catch {}
    }

    $script:CleanTotalFreed += $freed
    $script:CleanTotalFiles += $count
    Write-CleanResult -Label $Label -FileCount $count -Freed $freed -DryRun:$DryRun
    return $freed
}

function Invoke-RamFlush {
    param([switch]$DryRun)
    Write-CleanSpinner -Msg 'flushing memory + network...'

    # -- GC: flush PowerShell/.NET managed heap ---------------------------
    if (-not $DryRun) {
        try {
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            [System.GC]::Collect()
        } catch {}
    }

    # -- EmptyWorkingSet: trim current process working set ----------------
    try {
        if (-not ([System.Management.Automation.PSTypeName]'MemUtil').Type) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class MemUtil {
    [DllImport("psapi.dll")]    public static extern bool EmptyWorkingSet(IntPtr hProcess);
    [DllImport("kernel32.dll")] public static extern IntPtr GetCurrentProcess();
}
'@ -ErrorAction SilentlyContinue
        }
        if (-not $DryRun) {
            [MemUtil]::EmptyWorkingSet([MemUtil]::GetCurrentProcess()) | Out-Null
        }
    } catch {}

    # -- Network flush (all no-admin) -------------------------------------
    if (-not $DryRun) {
        try { & ipconfig /flushdns   2>$null | Out-Null } catch {}  # DNS resolver cache
        try { & nbtstat  /R          2>$null | Out-Null } catch {}  # NetBIOS name cache
        try { & arp      -d *        2>$null | Out-Null } catch {}  # ARP table (fails silently without admin)
    }

    # -- Report: RAM stats + top 5 memory hogs ----------------------------
    Clear-SpinnerLine
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os) {
            $freeMB  = [math]::Round($os.FreePhysicalMemory / 1024)
            $totalMB = [math]::Round($os.TotalVisibleMemorySize / 1024)
            $usedMB  = $totalMB - $freeMB
            $pct     = [math]::Round($usedMB * 100 / $totalMB)
            $tag     = if ($DryRun) { ' ~' } else { '' }
            $color   = if ($pct -gt 85) { 'Yellow' } elseif ($pct -gt 65) { 'DarkYellow' } else { 'Green' }
            $flushNote = if ($DryRun) { '' } else { '  flushed: DNS ARP NetBIOS clipboard GC' }
            Write-Host ('  RAM{0}  {1} MB / {2} MB  ({3}% used){4}' -f $tag, $usedMB, $totalMB, $pct, $flushNote) -ForegroundColor $color
        }
    } catch {}

    # Top 5 RAM hogs -- informational only (never killed)
    try {
        $top = Get-Process -ErrorAction SilentlyContinue |
            Sort-Object WorkingSet64 -Descending |
            Select-Object -First 5 |
            ForEach-Object {
                $mb = [math]::Round($_.WorkingSet64 / 1MB)
                '{0} ({1} MB)' -f $_.ProcessName, $mb
            }
        if ($top) {
            Write-Host ('  top: ' + ($top -join '  ')) -ForegroundColor DarkGray
        }
    } catch {}
}

# ---------------------------------------------------------------------------
#  Disk optimization -- SSD TRIM / HDD defrag (requires admin for Optimize-Volume)
# ---------------------------------------------------------------------------

function Invoke-DiskOptimize {
    param([switch]$DryRun)
    Write-CleanSpinner -Msg 'checking disks...'

    # Detect disk types via Get-PhysicalDisk -- requires Storage module
    $disks = @()
    try {
        $disks = Get-PhysicalDisk -ErrorAction SilentlyContinue |
            Where-Object { $_.BusType -ne 'USB' } |    # skip USB drives
            ForEach-Object {
                [pscustomobject]@{
                    Name      = $_.FriendlyName
                    MediaType = $_.MediaType             # SSD, HDD, Unspecified
                    BusType   = $_.BusType               # NVMe, SATA, SAS
                    SizeGB    = [math]::Round($_.Size / 1GB)
                    Health    = $_.HealthStatus
                }
            }
    } catch {
        # Storage module not available -- skip disk optimization
        Clear-SpinnerLine
        Write-Host '  disk info unavailable' -ForegroundColor DarkGray
        return
    }

    if ($disks.Count -eq 0) {
        Clear-SpinnerLine
        Write-Host '  no disks found' -ForegroundColor DarkGray
        return
    }

    Clear-SpinnerLine
    foreach ($disk in $disks) {
        $type  = if ($disk.MediaType -eq 'SSD') { 'SSD' } elseif ($disk.MediaType -eq 'HDD') { 'HDD' } else { '???' }
        $bus   = if ($disk.BusType) { $disk.BusType } else { '' }
        $health = if ($disk.Health -ne 'Healthy') { "  $($disk.Health)" } else { '' }
        $color  = if ($disk.Health -ne 'Healthy') { 'Yellow' } else { 'DarkGray' }

        # Attempt Optimize-Volume (requires admin -- will fail gracefully without)
        $action = ''
        if (-not $DryRun) {
            try {
                # Get volumes on this physical disk
                $volumes = Get-Volume -ErrorAction SilentlyContinue |
                    Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' }
                foreach ($vol in $volumes) {
                    Write-CleanSpinner -Msg ('optimizing ' + $vol.DriveLetter + ':')
                    try {
                        if ($disk.MediaType -eq 'SSD') {
                            Optimize-Volume -DriveLetter $vol.DriveLetter -ReTrim -ErrorAction Stop
                            $action = 'TRIM'
                        } elseif ($disk.MediaType -eq 'HDD') {
                            Optimize-Volume -DriveLetter $vol.DriveLetter -Defrag -ErrorAction Stop
                            $action = 'defrag'
                        }
                    } catch {
                        # Access denied without admin -- that's expected
                        $action = 'skipped (needs admin)'
                    }
                }
            } catch {
                $action = 'skipped (needs admin)'
            }
        } else {
            $action = if ($disk.MediaType -eq 'SSD') { 'would TRIM' } elseif ($disk.MediaType -eq 'HDD') { 'would defrag' } else { 'skip' }
        }

        Clear-SpinnerLine
        Write-Host ('  {0}  {1} {2} {3}GB  {4}{5}' -f $disk.Name, $type, $bus, $disk.SizeGB, $action, $health) -ForegroundColor $color
    }
}

function Test-IsPythonVenv {
    # Quick check: dir has Scripts\python.exe (Windows) or bin/python (Unix-style)
    # OR contains pyvenv.cfg -- any of these = it's a Python env
    param([string]$Dir)
    return (
        [System.IO.File]::Exists([System.IO.Path]::Combine($Dir, 'pyvenv.cfg')) -or
        [System.IO.File]::Exists([System.IO.Path]::Combine($Dir, 'Scripts', 'python.exe')) -or
        [System.IO.File]::Exists([System.IO.Path]::Combine($Dir, 'Scripts', 'python3.exe')) -or
        [System.IO.File]::Exists([System.IO.Path]::Combine($Dir, 'bin', 'python')) -or
        [System.IO.File]::Exists([System.IO.Path]::Combine($Dir, 'bin', 'python3'))
    )
}

function Test-IsInsideGitRepo {
    # Returns $true if $Path itself, or any ancestor up to $HOME, contains a .git directory.
    # This prevents accidental deletion of build artifacts inside active git repos.
    param([Parameter(Mandatory)][string]$Path)
    $current = $Path
    $home    = $HOME.TrimEnd('\','/')
    while ($current -and $current.Length -ge $home.Length) {
        if ([System.IO.Directory]::Exists((Join-Path $current '.git'))) { return $true }
        $parent = [System.IO.Path]::GetDirectoryName($current)
        if (-not $parent -or $parent -eq $current) { break }
        $current = $parent
    }
    return $false
}

function Test-IsProjectPath {
    # Returns $true if $Path appears to be inside a software project/workspace.
    # This guard is intentionally conservative to avoid deleting user projects.
    param([Parameter(Mandatory)][string]$Path)

    $markerFiles = @(
        'package.json',
        'pnpm-workspace.yaml',
        'pyproject.toml',
        'requirements.txt',
        'Pipfile',
        'Cargo.toml',
        'go.mod',
        '*.sln',
        '*.csproj'
    )

    $current = $Path
    $home    = $HOME.TrimEnd('\','/')
    while ($current -and $current.Length -ge $home.Length) {
        if ([System.IO.Directory]::Exists((Join-Path $current '.git'))) { return $true }

        foreach ($marker in $markerFiles) {
            try {
                if ($marker.Contains('*')) {
                    $hit = Get-ChildItem -Path $current -Filter $marker -File -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($hit) { return $true }
                } elseif ([System.IO.File]::Exists((Join-Path $current $marker))) {
                    return $true
                }
            } catch {}
        }

        $parent = [System.IO.Path]::GetDirectoryName($current)
        if (-not $parent -or $parent -eq $current) { break }
        $current = $parent
    }

    return $false
}

function Find-VenvDirs {
    param([string[]]$SearchRoots, [int]$StaleDays)
    $cutoff = (Get-Date).AddDays(-$StaleDays)
    $found  = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    # Helper: add dir to found if it exists, is stale, and is safe to delete.
    # Safety rule (hard): never target anything that appears to be inside a project.
    $tryAdd = {
        param([string]$dir)
        if ([System.IO.Directory]::Exists($dir)) {
            $lw = [System.IO.Directory]::GetLastWriteTime($dir)
            if ($lw -ge $cutoff) { return }

            if (Test-IsProjectPath -Path $dir) { return }

            $null = $found.Add($dir)
        }
    }

    $recurseOpt = [System.IO.SearchOption]::AllDirectories

    # -- Track 1: pyvenv.cfg -- standard venv / uv / virtualenv (modern) --------
    # pyvenv.cfg lives INSIDE the env dir, so its parent IS the env.
    # Catches: python -m venv .venv, uv venv, virtualenv, hatch, pdm, pyenv-virtualenv
    # --------------------------------------------------------------------------
    foreach ($root in $SearchRoots) {
        if (-not (Test-Path $root)) { continue }
        Write-CleanSpinner -Msg ('scanning ' + $root)
        try {
            foreach ($f in [System.IO.Directory]::EnumerateFiles($root, 'pyvenv.cfg', $recurseOpt)) {
                try {
                    $dir = [System.IO.Path]::GetDirectoryName($f)
                    Write-CleanSpinner -Msg $dir
                    & $tryAdd $dir
                } catch {}
            }
        } catch {}
    }

    # -- Track 2: directory-name patterns -- conda, old virtualenv, custom names -
    # .venv / venv / .env / env / virtualenv / .virtualenv -- verify it's Python
    # by checking for Scripts\python.exe (no pyvenv.cfg in old virtualenv / conda)
    # --------------------------------------------------------------------------
    $pyDirPatterns = @('.venv', 'venv', '.env', 'env', 'virtualenv', '.virtualenv')
    foreach ($root in $SearchRoots) {
        if (-not (Test-Path $root)) { continue }
        foreach ($pattern in $pyDirPatterns) {
            try {
                foreach ($d in [System.IO.Directory]::EnumerateDirectories($root, $pattern, $recurseOpt)) {
                    try {
                        Write-CleanSpinner -Msg $d
                        if (Test-IsPythonVenv -Dir $d) {
                            & $tryAdd $d
                        }
                    } catch {}
                }
            } catch {}
        }
    }

    # -- Track 3: conda / mamba named envs --------------------------------------
    # Conda stores named envs in fixed locations, not inside project dirs.
    # Each env subdir contains Scripts\python.exe (Windows).
    # --------------------------------------------------------------------------
    $condaRoots = @(
        (Join-Path $HOME '.conda\envs'),
        (Join-Path $HOME 'miniconda3\envs'),
        (Join-Path $HOME 'miniforge3\envs'),
        (Join-Path $HOME 'mambaforge\envs'),
        (Join-Path $HOME 'anaconda3\envs'),
        (Join-Path $HOME 'anaconda\envs'),
        (Join-Path $env:LOCALAPPDATA 'conda\conda\envs'),
        (Join-Path $env:USERPROFILE 'AppData\Local\miniconda3\envs')
    ) | Select-Object -Unique
    foreach ($condaRoot in $condaRoots) {
        if (-not [System.IO.Directory]::Exists($condaRoot)) { continue }
        Write-CleanSpinner -Msg ('conda envs: ' + $condaRoot)
        try {
            foreach ($envDir in [System.IO.Directory]::EnumerateDirectories($condaRoot)) {
                if (Test-IsPythonVenv -Dir $envDir) {
                    & $tryAdd $envDir
                }
            }
        } catch {}
    }

    # -- Track 4: uv tool installs ---------------------------------------------
    # `uv tool install` creates isolated envs in %APPDATA%\uv\tools\<package>
    # These are not project venvs but are safe to remove if stale (reinstallable)
    # --------------------------------------------------------------------------
    $uvToolsRoot = Join-Path $env:APPDATA 'uv\tools'
    if ([System.IO.Directory]::Exists($uvToolsRoot)) {
        Write-CleanSpinner -Msg ('uv tools: ' + $uvToolsRoot)
        try {
            foreach ($toolDir in [System.IO.Directory]::EnumerateDirectories($uvToolsRoot)) {
                if (Test-IsPythonVenv -Dir $toolDir) {
                    & $tryAdd $toolDir
                }
            }
        } catch {}
    }

    # Project build/output directories (target/, vendor/, node_modules/) are intentionally
    # excluded from automatic deletion to avoid data loss in source repositories.

    return @($found)
}

function Remove-VenvDir {
    param([string]$Path, [switch]$DryRun)
    Write-CleanSpinner -Msg ('sizing ' + [System.IO.Path]::GetFileName($Path) + '...')
    try {
        $size = [long]0
        foreach ($f in [System.IO.Directory]::EnumerateFiles($Path, '*', [System.IO.SearchOption]::AllDirectories)) {
            try { $size += [System.IO.FileInfo]::new($f).Length } catch {}
        }
        Clear-SpinnerLine
        $tag   = if ($DryRun) { ' ~' } else { '' }
        $color = if ($size -gt 0 -and -not $DryRun) { 'Green' } elseif ($DryRun -and $size -gt 0) { 'DarkYellow' } else { 'DarkGray' }
        $name  = [System.IO.Path]::GetFileName($Path)
        $parent= [System.IO.Path]::GetFileName([System.IO.Path]::GetDirectoryName($Path))
        Write-Host ('  {0}/{1}{2}  {3}' -f $parent, $name, $tag, (Format-Bytes $size)) -ForegroundColor $color
        if (-not $DryRun) {
            # Final safety: never remove if the path appears to belong to a project/workspace
            if (Test-IsProjectPath -Path $Path) {
                Write-Host ('  skipped (project path): {0}' -f $Path) -ForegroundColor DarkGray
                return 0
            }
            Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
        }
        $script:CleanTotalFreed += $size
        return $size
    } catch {
        Clear-SpinnerLine
        return [long]0
    }
}

# ---------------------------------------------------------------------------
#  Stale project scanner
# ---------------------------------------------------------------------------

function Get-DirSizeBytes {
    param([string]$Path)
    $size = [long]0
    try {
        foreach ($f in [System.IO.Directory]::EnumerateFiles($Path, '*', [System.IO.SearchOption]::AllDirectories)) {
            try { $size += [System.IO.FileInfo]::new($f).Length } catch {}
        }
    } catch {}
    return $size
}

function Find-StaleProjects {
    param([int]$StaleDays = 90)

    $cutoff = (Get-Date).AddDays(-$StaleDays)
    $found  = [System.Collections.Generic.List[object]]::new()

    $searchRoots = @(
        $HOME,
        (Join-Path $HOME 'projects'),
        (Join-Path $HOME 'dev'),
        (Join-Path $HOME 'code'),
        (Join-Path $HOME 'repos'),
        (Join-Path $HOME 'workspace'),
        (Join-Path $HOME 'Documents'),
        (Join-Path $HOME 'Desktop'),
        (Join-Path $HOME 'Downloads'),
        (Join-Path $HOME 'src'),
        (Join-Path $HOME 'work'),
        (Join-Path $HOME 'github'),
        (Join-Path $HOME 'lab')
    ) | Where-Object { [System.IO.Directory]::Exists($_) } | Select-Object -Unique

    $topOnlyOpt = [System.IO.SearchOption]::TopDirectoryOnly

    foreach ($root in $searchRoots) {
        Write-CleanSpinner -Msg ('scanning ' + $root)
        try {
            foreach ($dir in [System.IO.Directory]::EnumerateDirectories($root, '*', $topOnlyOpt)) {
                $gitDir = Join-Path $dir '.git'
                if (-not [System.IO.Directory]::Exists($gitDir)) { continue }

                # Get last commit date via git log (fast  reads packfile header only)
                $lastCommit = $null
                try {
                    $ts = & git -C $dir log -1 --format='%ct' 2>$null
                    if ($ts -and $ts -match '^\d+$') {
                        $lastCommit = [System.DateTimeOffset]::FromUnixTimeSeconds([long]$ts).LocalDateTime
                    }
                } catch {}

                # Fall back to filesystem mtime of .git/COMMIT_EDITMSG
                if (-not $lastCommit) {
                    $editmsg = Join-Path $gitDir 'COMMIT_EDITMSG'
                    if ([System.IO.File]::Exists($editmsg)) {
                        $lastCommit = [System.IO.File]::GetLastWriteTime($editmsg)
                    } else {
                        $lastCommit = [System.IO.Directory]::GetLastWriteTime($gitDir)
                    }
                }

                if ($lastCommit -ge $cutoff) { continue }   # active  skip

                Write-CleanSpinner -Msg ('sizing ' + [System.IO.Path]::GetFileName($dir) + '...')
                $sizeBytes = Get-DirSizeBytes -Path $dir

                $remote = ''
                try {
                    $r = & git -C $dir remote get-url origin 2>$null
                    if ($r) { $remote = $r.Trim() }
                } catch {}

                $null = $found.Add([pscustomobject]@{
                    Path        = $dir
                    Name        = [System.IO.Path]::GetFileName($dir)
                    LastCommit  = $lastCommit
                    SizeBytes   = $sizeBytes
                    SizeDisplay = Format-Bytes $sizeBytes
                    DaysOld     = [int]([datetime]::Now - $lastCommit).TotalDays
                    Remote      = $remote
                })
            }
        } catch {}
    }

    Clear-SpinnerLine
    return @($found | Sort-Object SizeBytes -Descending)
}

# ---------------------------------------------------------------------------
#  Interactive project picker (fzf multi-select)
# ---------------------------------------------------------------------------

function Invoke-ProjectPicker {
    param(
        [int]$StaleDays = 90,
        [switch]$All,
        [switch]$DryRun
    )

    Write-Host ''
    Write-Host ('  8sync clean --projects  stale > {0}d (report-only)' -f $StaleDays) -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  Project deletion has been disabled for safety. This mode now only reports.' -ForegroundColor DarkYellow
    Write-Host ''
    Write-Host '  Scanning for stale git repos...' -ForegroundColor Yellow

    $projects = Find-StaleProjects -StaleDays $StaleDays
    Clear-SpinnerLine

    if ($projects.Count -eq 0) {
        Write-Host ('  No stale projects found (threshold: {0} days).' -f $StaleDays) -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    Write-Host ('  Found {0} stale project(s):' -f $projects.Count) -ForegroundColor Yellow
    Write-Host ''

    $totalSize = [long]0
    foreach ($p in $projects) {
        $totalSize += $p.SizeBytes
        Write-Host ('  {0,-42} {1,8}  {2,4}d  {3}' -f $p.Name, $p.SizeDisplay, $p.DaysOld, $p.Path) -ForegroundColor White
    }

    Write-Host ''
    Write-Host ('  Report only: {0} stale project(s), total size {1}.' -f $projects.Count, (Format-Bytes $totalSize)) -ForegroundColor DarkGray
    if ($All) {
        Write-Host '  Note: --all is ignored because project deletion is disabled.' -ForegroundColor DarkGray
    }
    if ($DryRun) {
        Write-Host '  Note: --dry-run is redundant in report-only mode.' -ForegroundColor DarkGray
    }
    Write-Host ''
}

# ---------------------------------------------------------------------------
#  Deep dev artifact scanner (MCP, npm globals, pip globals, cargo, go)
# ---------------------------------------------------------------------------

function Find-OrphanedDevArtifacts {
    param([int]$StaleDays = 30)

    $cutoff  = (Get-Date).AddDays(-$StaleDays)
    $results = [System.Collections.Generic.List[object]]::new()

    $addEntry = {
        param([string]$Type, [string]$Name, [string]$Path, [datetime]$LastWrite, [long]$Size)
        $null = $results.Add([pscustomobject]@{
            Type        = $Type
            Name        = $Name
            Path        = $Path
            LastWrite   = $LastWrite
            DaysOld     = [int]([datetime]::Now - $LastWrite).TotalDays
            SizeBytes   = $Size
            SizeDisplay = Format-Bytes $Size
        })
    }

    # -- MCP server caches & data ----------------------------------------
    $mcpRoots = @(
        (Join-Path $env:APPDATA 'Claude\claude_desktop_config.json'),   # Claude Desktop
        (Join-Path $HOME '.config\claude'),
        (Join-Path $env:APPDATA 'Code\User\globalStorage\saoudrizwan.claude-dev'),  # Cline/Claude VSCode ext
        (Join-Path $env:LOCALAPPDATA 'npm-cache\_npx')                  # npx-cached MCP servers
    )
    foreach ($p in $mcpRoots) {
        if (-not (Test-Path $p)) { continue }
        Write-CleanSpinner -Msg ('MCP: ' + $p)
        try {
            # npx cache entries older than threshold
            if ($p -like '*_npx*') {
                foreach ($d in [System.IO.Directory]::EnumerateDirectories($p)) {
                    $lw = [System.IO.Directory]::GetLastWriteTime($d)
                    if ($lw -lt $cutoff) {
                        $sz = Get-DirSizeBytes $d
                        & $addEntry 'npx-cache' ([System.IO.Path]::GetFileName($d)) $d $lw $sz
                    }
                }
            }
        } catch {}
    }

    # -- npm global packages ---------------------------------------------
    $npmGlobalDirs = @(
        (Join-Path $env:APPDATA 'npm\node_modules'),
        (Join-Path $HOME 'scoop\apps\nodejs\current\node_modules'),
        (Join-Path $env:PROGRAMFILES 'nodejs\node_modules')
    )
    foreach ($ngDir in $npmGlobalDirs) {
        if (-not [System.IO.Directory]::Exists($ngDir)) { continue }
        Write-CleanSpinner -Msg ('npm globals: ' + $ngDir)
        try {
            foreach ($pkg in [System.IO.Directory]::EnumerateDirectories($ngDir)) {
                $lw = [System.IO.Directory]::GetLastWriteTime($pkg)
                if ($lw -lt $cutoff) {
                    $name = [System.IO.Path]::GetFileName($pkg)
                    if ($name -eq 'npm') { continue }   # never remove npm itself
                    $sz = Get-DirSizeBytes $pkg
                    & $addEntry 'npm-global' $name $pkg $lw $sz
                }
            }
        } catch {}
        break   # only scan the first found npm global dir
    }

    # -- pip / uv global site-packages -----------------------------------
    $pipGlobalDirs = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python*\Lib\site-packages'),
        (Join-Path $HOME 'scoop\apps\python\current\Lib\site-packages'),
        (Join-Path $env:APPDATA 'Python\Python*\site-packages')
    )
    foreach ($pattern in $pipGlobalDirs) {
        $resolved = try { (Resolve-Path $pattern -ErrorAction SilentlyContinue) } catch { $null }
        if (-not $resolved) { continue }
        foreach ($dir in @($resolved)) {
            if (-not [System.IO.Directory]::Exists($dir.Path)) { continue }
            Write-CleanSpinner -Msg ('pip site-packages: ' + $dir.Path)
            try {
                foreach ($pkg in [System.IO.Directory]::EnumerateDirectories($dir.Path)) {
                    $lw = [System.IO.Directory]::GetLastWriteTime($pkg)
                    if ($lw -lt $cutoff) {
                        $name = [System.IO.Path]::GetFileName($pkg)
                        if ($name -match '(pip|setuptools|wheel|distutils)') { continue }
                        $sz = Get-DirSizeBytes $pkg
                        & $addEntry 'pip-global' $name $pkg $lw $sz
                    }
                }
            } catch {}
            break
        }
    }

    # -- cargo installed bins --------------------------------------------
    $cargoBin = Join-Path $HOME '.cargo\bin'
    if ([System.IO.Directory]::Exists($cargoBin)) {
        Write-CleanSpinner -Msg 'cargo bin...'
        try {
            foreach ($bin in [System.IO.Directory]::EnumerateFiles($cargoBin, '*.exe')) {
                $info = [System.IO.FileInfo]::new($bin)
                if ($info.LastWriteTime -lt $cutoff) {
                    & $addEntry 'cargo-bin' $info.Name $bin $info.LastWriteTime $info.Length
                }
            }
        } catch {}
    }

    # -- go installed bins -----------------------------------------------
    $goBin = Join-Path $HOME 'go\bin'
    if ([System.IO.Directory]::Exists($goBin)) {
        Write-CleanSpinner -Msg 'go bin...'
        try {
            foreach ($bin in [System.IO.Directory]::EnumerateFiles($goBin, '*.exe')) {
                $info = [System.IO.FileInfo]::new($bin)
                if ($info.LastWriteTime -lt $cutoff) {
                    & $addEntry 'go-bin' $info.Name $bin $info.LastWriteTime $info.Length
                }
            }
        } catch {}
    }

    Clear-SpinnerLine
    return @($results | Sort-Object SizeBytes -Descending)
}

function Show-DevArtifactReport {
    param([int]$StaleDays = 30)

    Write-Host ''
    Write-Host ('  8sync clean --deep  dev artifacts > {0}d old' -f $StaleDays) -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  Scanning dev artifacts (MCP, npm, pip, cargo, go)...' -ForegroundColor Yellow

    $artifacts = Find-OrphanedDevArtifacts -StaleDays $StaleDays
    Clear-SpinnerLine

    if ($artifacts.Count -eq 0) {
        Write-Host ('  No stale dev artifacts found (threshold: {0} days).' -f $StaleDays) -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    # Group by type
    $grouped = $artifacts | Group-Object Type
    foreach ($group in $grouped) {
        $totalSz = ($group.Group | Measure-Object SizeBytes -Sum).Sum
        Write-Host ('  {0}  ({1} items  {2})' -f $group.Name.ToUpper(), $group.Count, (Format-Bytes $totalSz)) -ForegroundColor Yellow
        foreach ($item in $group.Group | Select-Object -First 10) {
            Write-Host ('    {0,-45} {1,8}  {2}d ago' -f $item.Name, $item.SizeDisplay, $item.DaysOld) -ForegroundColor DarkGray
        }
        if ($group.Group.Count -gt 10) {
            Write-Host ('    ... and {0} more' -f ($group.Group.Count - 10)) -ForegroundColor DarkGray
        }
        Write-Host ''
    }

    $totalAll = ($artifacts | Measure-Object SizeBytes -Sum).Sum
    Write-Host ('  Total stale dev artifacts: {0} items  {1}' -f $artifacts.Count, (Format-Bytes $totalAll)) -ForegroundColor DarkYellow
    Write-Host '  These are reported only  remove manually or with your package manager.' -ForegroundColor DarkGray
    Write-Host ''

    return $artifacts
}

function Invoke-DeleteDevArtifacts {
    param(
        [object[]]$Artifacts,
        [switch]$All,
        [switch]$DryRun
    )

    if (-not $Artifacts -or $Artifacts.Count -eq 0) { return }

    $grouped    = $Artifacts | Group-Object Type
    $totalFreed = [long]0
    $totalFiles = 0

    foreach ($group in $grouped) {
        $typeName = $group.Name
        $items    = @($group.Group)
        $typeSz   = ($items | Measure-Object SizeBytes -Sum).Sum

        if (-not $All) {
            Write-Host ''
            $prompt = ('  Delete {0} {1} package(s) ({2})? [y/N] ' -f $items.Count, $typeName, (Format-Bytes $typeSz))
            $answer = Read-Host $prompt
            if ($answer -notmatch '^[Yy]$') {
                Write-Host ('  Skipped {0}.' -f $typeName) -ForegroundColor DarkGray
                continue
            }
        }

        foreach ($item in $items) {
            # Safety: never touch anything inside a git repo
            if (Test-IsInsideGitRepo -Path $item.Path) {
                Write-Host ('  skipped (git repo): {0}' -f $item.Path) -ForegroundColor DarkGray
                continue
            }

            if ($DryRun) {
                Write-Host ('  [dry-run] would remove: {0}' -f $item.Path) -ForegroundColor DarkYellow
                $totalFreed += $item.SizeBytes
                $totalFiles++
            } else {
                try {
                    if (Test-Path $item.Path -PathType Container) {
                        Remove-Item $item.Path -Recurse -Force -ErrorAction Stop
                    } elseif (Test-Path $item.Path -PathType Leaf) {
                        Remove-Item $item.Path -Force -ErrorAction Stop
                    }
                    Write-Host ('  removed: {0}  ({1})' -f $item.Name, $item.SizeDisplay) -ForegroundColor Green
                    $totalFreed += $item.SizeBytes
                    $totalFiles++
                } catch {
                    Write-Host ('  failed:  {0} — {1}' -f $item.Name, $_.Exception.Message) -ForegroundColor DarkYellow
                }
            }
        }
    }

    Write-Host ''
    $verb = if ($DryRun) { 'would free' } else { 'freed' }
    Write-Host ('  >> {0} {1}  {2} items removed' -f $verb, (Format-Bytes $totalFreed), $totalFiles) -ForegroundColor $(if ($DryRun) { 'DarkYellow' } else { 'Green' })
    Write-Host ''
}

# ---------------------------------------------------------------------------
#  Ecosystem security audit (npm, cargo, pip + postinstall scanner)
# ---------------------------------------------------------------------------

function Invoke-EcosystemAudit {
    Write-Host ''
    Write-Host '  8sync clean --audit  ecosystem vulnerability scan' -ForegroundColor Cyan
    Write-Host ''

    $anyFound = $false

    # -- npm audit -----------------------------------------------------------
    if (Test-CommandExists 'npm') {
        Write-Host '  NPM AUDIT' -ForegroundColor Yellow

        # Find package.json roots up to depth 3 under HOME
        $pkgRoots = [System.Collections.Generic.List[string]]::new()
        $searchRoots = @($HOME, (Join-Path $HOME 'projects'), (Join-Path $HOME 'dev'),
                         (Join-Path $HOME 'code'), (Join-Path $HOME 'repos'),
                         (Join-Path $HOME 'workspace'), (Join-Path $HOME 'Documents')) |
            Where-Object { Test-Path $_ }

        foreach ($root in $searchRoots) {
            try {
                Get-ChildItem $root -Filter 'package.json' -Recurse -Depth 3 -ErrorAction SilentlyContinue |
                    Where-Object { $_.FullName -notmatch '\\node_modules\\' } |
                    ForEach-Object { $null = $pkgRoots.Add($_.DirectoryName) }
            } catch {}
        }
        $pkgRoots = @($pkgRoots | Select-Object -Unique)

        if ($pkgRoots.Count -gt 0) {
            foreach ($dir in $pkgRoots) {
                $nmDir = Join-Path $dir 'node_modules'
                if (-not (Test-Path $nmDir)) { continue }   # skip if not installed
                try {
                    $auditOut = & npm audit --json --prefix $dir 2>$null | Out-String
                    $auditData = $auditOut | ConvertFrom-Json -ErrorAction SilentlyContinue
                    if ($auditData -and $auditData.metadata) {
                        $vulns = $auditData.metadata.vulnerabilities
                        $critical = if ($vulns.critical) { [int]$vulns.critical } else { 0 }
                        $high     = if ($vulns.high)     { [int]$vulns.high }     else { 0 }
                        if ($critical -gt 0 -or $high -gt 0) {
                            $anyFound = $true
                            $shortDir = if ($dir -like "$HOME*") { '~' + $dir.Substring($HOME.Length) } else { $dir }
                            Write-Host ('    [!] {0,-50} critical:{1}  high:{2}' -f $shortDir, $critical, $high) -ForegroundColor Red
                        } else {
                            $shortDir = if ($dir -like "$HOME*") { '~' + $dir.Substring($HOME.Length) } else { $dir }
                            Write-Host ('    [OK] {0}' -f $shortDir) -ForegroundColor DarkGray
                        }
                    }
                } catch {}
            }
        } else {
            Write-Host '    no package.json with node_modules found' -ForegroundColor DarkGray
        }
        Write-Host ''

        # -- postinstall script scanner (red flag: network calls in postinstall) --
        Write-Host '  POSTINSTALL SCRIPT SCAN (malicious pattern check)' -ForegroundColor Yellow
        $nmDirs = @($pkgRoots | ForEach-Object { Join-Path $_ 'node_modules' } | Where-Object { Test-Path $_ })
        if ($nmDirs.Count -eq 0) {
            # Also scan global npm
            $globalNm = Join-Path $env:APPDATA 'npm\node_modules'
            if (Test-Path $globalNm) { $nmDirs = @($globalNm) }
        }

        $suspiciousPatterns = @('curl','wget','http\.get','https\.get','fetch\(','axios','request\(','child_process','exec\(','spawn\(','eval\(','atob\(','fromCharCode')
        $flaggedPkgs = [System.Collections.Generic.List[string]]::new()

        foreach ($nmDir in $nmDirs) {
            try {
                foreach ($pkgDir in [System.IO.Directory]::EnumerateDirectories($nmDir)) {
                    $pkgJson = Join-Path $pkgDir 'package.json'
                    if (-not (Test-Path $pkgJson)) { continue }
                    try {
                        $pkgData = Get-Content $pkgJson -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue
                        if (-not $pkgData -or -not $pkgData.scripts) { continue }
                        $postInstall = $pkgData.scripts.postinstall
                        if (-not $postInstall) { continue }
                        foreach ($pat in $suspiciousPatterns) {
                            if ($postInstall -match $pat) {
                                $pkgName = [System.IO.Path]::GetFileName($pkgDir)
                                $null = $flaggedPkgs.Add($pkgName)
                                break
                            }
                        }
                    } catch {}
                }
            } catch {}
        }

        if ($flaggedPkgs.Count -gt 0) {
            $anyFound = $true
            Write-Host ('    [!] {0} package(s) with suspicious postinstall scripts:' -f $flaggedPkgs.Count) -ForegroundColor Red
            foreach ($pkg in $flaggedPkgs | Select-Object -First 20) {
                Write-Host ('        {0}' -f $pkg) -ForegroundColor DarkYellow
            }
            Write-Host '    Review manually: npm show <pkg> scripts' -ForegroundColor DarkGray
        } else {
            Write-Host '    No suspicious postinstall scripts found.' -ForegroundColor DarkGray
        }
        Write-Host ''
    }

    # -- cargo audit ---------------------------------------------------------
    if (Test-CommandExists 'cargo-audit' -or (Test-CommandExists 'cargo' -and (Test-Path (Join-Path $HOME '.cargo\bin\cargo-audit.exe')))) {
        Write-Host '  CARGO AUDIT (RustSec)' -ForegroundColor Yellow
        try {
            $cargoAuditCmd = if (Test-CommandExists 'cargo-audit') { 'cargo-audit' } else { 'cargo' }
            $auditArgs = if ($cargoAuditCmd -eq 'cargo') { @('audit', '--json') } else { @('--json') }
            $auditOut  = & $cargoAuditCmd @auditArgs 2>$null | Out-String
            $auditData = $auditOut | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($auditData -and $auditData.vulnerabilities) {
                $count = if ($auditData.vulnerabilities.count) { [int]$auditData.vulnerabilities.count } else { 0 }
                if ($count -gt 0) {
                    $anyFound = $true
                    Write-Host ('    [!] {0} vulnerabilities found (RustSec advisory)' -f $count) -ForegroundColor Red
                    foreach ($vuln in @($auditData.vulnerabilities.list | Select-Object -First 5)) {
                        $id   = if ($vuln.advisory.id)    { $vuln.advisory.id }    else { '?' }
                        $pkg  = if ($vuln.package.name)   { $vuln.package.name }   else { '?' }
                        $titl = if ($vuln.advisory.title) { $vuln.advisory.title } else { '' }
                        Write-Host ('      {0}  {1}  {2}' -f $id, $pkg, $titl) -ForegroundColor DarkYellow
                    }
                } else {
                    Write-Host '    [OK] No known vulnerabilities.' -ForegroundColor DarkGray
                }
            } else {
                Write-Host '    Could not parse cargo audit output.' -ForegroundColor DarkGray
            }
        } catch {
            Write-Host '    cargo audit failed or not installed. Install: cargo install cargo-audit' -ForegroundColor DarkGray
        }
        Write-Host ''
    } elseif (Test-CommandExists 'cargo') {
        Write-Host '  CARGO AUDIT' -ForegroundColor Yellow
        Write-Host '    cargo-audit not installed. Run: cargo install cargo-audit' -ForegroundColor DarkGray
        Write-Host ''
    }

    # -- pip-audit -----------------------------------------------------------
    if (Test-CommandExists 'pip-audit') {
        Write-Host '  PIP AUDIT (OSV/PyPI)' -ForegroundColor Yellow
        try {
            $auditOut  = & pip-audit --format=json 2>$null | Out-String
            $auditData = $auditOut | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($auditData) {
                # pip-audit JSON: array of {name, version, vulns:[{id,fix_versions,aliases}]}
                $vulnPkgs = @($auditData | Where-Object { $_.vulns -and $_.vulns.Count -gt 0 })
                if ($vulnPkgs.Count -gt 0) {
                    $anyFound = $true
                    Write-Host ('    [!] {0} package(s) with vulnerabilities:' -f $vulnPkgs.Count) -ForegroundColor Red
                    foreach ($pkg in $vulnPkgs | Select-Object -First 10) {
                        foreach ($v in $pkg.vulns | Select-Object -First 2) {
                            $fix = if ($v.fix_versions) { 'fix: ' + ($v.fix_versions -join ', ') } else { 'no fix' }
                            Write-Host ('      {0} {1}  {2}  {3}' -f $pkg.name, $pkg.version, $v.id, $fix) -ForegroundColor DarkYellow
                        }
                    }
                } else {
                    Write-Host '    [OK] No known vulnerabilities.' -ForegroundColor DarkGray
                }
            } else {
                Write-Host '    Could not parse pip-audit output.' -ForegroundColor DarkGray
            }
        } catch {
            Write-Host '    pip-audit failed.' -ForegroundColor DarkGray
        }
        Write-Host ''
    } else {
        Write-Host '  PIP AUDIT' -ForegroundColor Yellow
        Write-Host '    pip-audit not installed. Run: pip install pip-audit' -ForegroundColor DarkGray
        Write-Host ''
    }

    if (-not $anyFound) {
        Write-Host '  All clear — no high/critical vulnerabilities detected.' -ForegroundColor Green
        Write-Host ''
    }
}

# ---------------------------------------------------------------------------
#  Windows Defender quick scan
# ---------------------------------------------------------------------------

function Invoke-DefenderScan {
    param([string[]]$TargetPaths)

    Write-Host ''
    Write-Host '  8sync clean --scan  Windows Defender scan' -ForegroundColor Cyan
    Write-Host ''

    # Locate MpCmdRun.exe
    $mpCmd = $null
    $candidates = @(
        (Join-Path $env:ProgramFiles 'Windows Defender\MpCmdRun.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Windows Defender\MpCmdRun.exe'),
        (Join-Path $env:ProgramData 'Microsoft\Windows Defender\Platform\*\MpCmdRun.exe')
    )
    foreach ($c in $candidates) {
        $resolved = try { (Resolve-Path $c -ErrorAction SilentlyContinue) } catch { $null }
        if ($resolved) {
            $mpCmd = @($resolved)[0].Path
            break
        }
    }

    if (-not $mpCmd -or -not (Test-Path $mpCmd)) {
        Write-Host '  Windows Defender MpCmdRun.exe not found. Skipping scan.' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    Write-Host ('  Defender: {0}' -f $mpCmd) -ForegroundColor DarkGray

    if ($TargetPaths -and $TargetPaths.Count -gt 0) {
        # Custom path scan
        foreach ($path in $TargetPaths | Where-Object { Test-Path $_ }) {
            Write-Host ('  Scanning: {0}' -f $path) -ForegroundColor Yellow
            try {
                $result = & $mpCmd -Scan -ScanType 3 -File $path 2>&1
                $threat = $result | Select-String -Pattern 'threat|found|infected' -CaseSensitive:$false
                if ($threat) {
                    Write-Host ('  [!] THREATS DETECTED in {0}' -f $path) -ForegroundColor Red
                    $threat | ForEach-Object { Write-Host ('      ' + $_) -ForegroundColor Red }
                } else {
                    Write-Host ('  [OK] Clean: {0}' -f $path) -ForegroundColor Green
                }
            } catch {
                Write-Host ('  Scan failed for {0}: {1}' -f $path, $_.Exception.Message) -ForegroundColor DarkYellow
            }
        }
    } else {
        # Quick scan (ScanType 1)  non-blocking, Defender runs in background
        Write-Host '  Running quick scan (ScanType 1)...' -ForegroundColor Yellow
        Write-Host '  Note: scan runs in background. Check Windows Security for results.' -ForegroundColor DarkGray
        try {
            Start-Process -FilePath $mpCmd -ArgumentList @('-Scan', '-ScanType', '1') -WindowStyle Hidden -ErrorAction Stop
            Write-Host '  [OK] Quick scan started.' -ForegroundColor Green
        } catch {
            Write-Host ('  Failed to start scan: {0}' -f $_.Exception.Message) -ForegroundColor DarkYellow
        }

        # Also scan common dev artifact roots (targeted, foreground)
        $devRoots = @(
            (Join-Path $env:LOCALAPPDATA 'npm-cache\_npx'),
            (Join-Path $HOME 'scoop\apps'),
            (Join-Path $HOME '.cargo\bin')
        ) | Where-Object { Test-Path $_ }

        if ($devRoots.Count -gt 0) {
            Write-Host '  Targeted scan on dev tool directories...' -ForegroundColor Yellow
            foreach ($root in $devRoots) {
                Write-Host ('  Scanning: {0}' -f $root) -ForegroundColor DarkGray
                try {
                    & $mpCmd -Scan -ScanType 3 -File $root 2>&1 | Out-Null
                    Write-Host ('  [OK] {0}' -f $root) -ForegroundColor Green
                } catch {}
            }
        }
    }

    Write-Host ''
}

function Read-CleanLoopState {
    Ensure-StateDir
    if (-not (Test-Path $script:CleanLoopPath)) {
        return [pscustomobject]@{
            enabled         = $false
            intervalMinutes = $script:CleanLoopDefaultMinutes
            profile         = $script:CleanLoopDefaultProfile
            cooldownMinutes = 240
            lastRunUtc      = $null
            lastDeepRunUtc  = $null
        }
    }

    try {
        $raw = Get-Content -Raw $script:CleanLoopPath | ConvertFrom-Json
        $profile = if ($raw.profile -and ($script:CleanLoopKnownProfiles -contains $raw.profile)) {
            $raw.profile
        } else {
            $script:CleanLoopDefaultProfile
        }
        $cooldown = if ($raw.cooldownMinutes -and [int]$raw.cooldownMinutes -gt 0) {
            [int]$raw.cooldownMinutes
        } else {
            240
        }

        return [pscustomobject]@{
            enabled         = [bool]$raw.enabled
            intervalMinutes = if ($raw.intervalMinutes -and [int]$raw.intervalMinutes -gt 0) { [int]$raw.intervalMinutes } else { $script:CleanLoopDefaultMinutes }
            profile         = $profile
            cooldownMinutes = $cooldown
            lastRunUtc      = $raw.lastRunUtc
            lastDeepRunUtc  = $raw.lastDeepRunUtc
        }
    } catch {
        return [pscustomobject]@{
            enabled         = $false
            intervalMinutes = $script:CleanLoopDefaultMinutes
            profile         = $script:CleanLoopDefaultProfile
            cooldownMinutes = 240
            lastRunUtc      = $null
            lastDeepRunUtc  = $null
        }
    }
}

function Write-CleanLoopState {
    param(
        [bool]$Enabled,
        [int]$IntervalMinutes,
        [string]$Profile,
        [int]$CooldownMinutes,
        [datetime]$LastRunUtc,
        [datetime]$LastDeepRunUtc
    )

    Ensure-StateDir

    $current = Read-CleanLoopState
    $resolvedProfile = if ($Profile) { $Profile } else { $current.profile }
    if (-not ($script:CleanLoopKnownProfiles -contains $resolvedProfile)) {
        $resolvedProfile = $script:CleanLoopDefaultProfile
    }

    $resolvedInterval = if ($IntervalMinutes -gt 0) { $IntervalMinutes } else { $current.intervalMinutes }
    $resolvedCooldown = if ($CooldownMinutes -gt 0) { $CooldownMinutes } else { $current.cooldownMinutes }
    $resolvedLastRun = if ($PSBoundParameters.ContainsKey('LastRunUtc')) { $LastRunUtc } elseif ($current.lastRunUtc) { [datetime]$current.lastRunUtc } else { [datetime]::UtcNow }
    $resolvedLastDeepRun = if ($PSBoundParameters.ContainsKey('LastDeepRunUtc')) { $LastDeepRunUtc } elseif ($current.lastDeepRunUtc) { [datetime]$current.lastDeepRunUtc } else { $null }

    [pscustomobject]@{
        enabled         = $Enabled
        intervalMinutes = $resolvedInterval
        profile         = $resolvedProfile
        cooldownMinutes = $resolvedCooldown
        lastRunUtc      = if ($resolvedLastRun) { $resolvedLastRun.ToString('o') } else { $null }
        lastDeepRunUtc  = if ($resolvedLastDeepRun) { $resolvedLastDeepRun.ToString('o') } else { $null }
    } | ConvertTo-Json | Set-Content -Path $script:CleanLoopPath -Encoding UTF8
}

function Get-CleanLoopProfileSettings {
    param([string]$Profile)

    $resolved = if ($script:CleanLoopKnownProfiles -contains $Profile) { $Profile } else { $script:CleanLoopDefaultProfile }
    switch ($resolved) {
        'deep' {
            return [pscustomobject]@{
                profile                  = 'deep'
                defaultIntervalMinutes   = 45
                defaultCooldownMinutes   = 180
                runDryCleanPreview       = $true
                dryCleanStaleDays        = 7
                runDefenderQuickScan     = $true
            }
        }
        'balanced' {
            return [pscustomobject]@{
                profile                  = 'balanced'
                defaultIntervalMinutes   = 15
                defaultCooldownMinutes   = 360
                runDryCleanPreview       = $true
                dryCleanStaleDays        = 14
                runDefenderQuickScan     = $false
            }
        }
        default {
            return [pscustomobject]@{
                profile                  = 'light'
                defaultIntervalMinutes   = 5
                defaultCooldownMinutes   = 720
                runDryCleanPreview       = $false
                dryCleanStaleDays        = 21
                runDefenderQuickScan     = $false
            }
        }
    }
}

function Acquire-CleanLoopLock {
    if (Test-Path $script:CleanLoopLockPath) {
        try {
            $raw = Get-Content -Raw $script:CleanLoopLockPath | ConvertFrom-Json
            if ($raw -and $raw.startedUtc) {
                $started = [datetime]$raw.startedUtc
                $ageMinutes = ([datetime]::UtcNow - $started).TotalMinutes
                if ($ageMinutes -lt $script:CleanLoopLockMaxAgeMinutes) {
                    return $false
                }
            }
        } catch {
        }
        Remove-Item $script:CleanLoopLockPath -Force -ErrorAction SilentlyContinue
    }

    try {
        [pscustomobject]@{
            pid        = $PID
            startedUtc = [datetime]::UtcNow.ToString('o')
        } | ConvertTo-Json | Set-Content -Path $script:CleanLoopLockPath -Encoding UTF8
        return $true
    } catch {
        return $false
    }
}

function Release-CleanLoopLock {
    Remove-Item $script:CleanLoopLockPath -Force -ErrorAction SilentlyContinue
}

function Invoke-CleanLoopTick {
    param([switch]$Manual)

    if (-not (Acquire-CleanLoopLock)) {
        if ($Manual) {
            Write-Host '  clean loop skipped: another loop task is active.' -ForegroundColor DarkYellow
        }
        return
    }

    try {
        $state = Read-CleanLoopState
        $profileSettings = Get-CleanLoopProfileSettings -Profile $state.profile
        $didDryClean = $false
        $didDefender = $false
        $lastDeepRunUtc = if ($state.lastDeepRunUtc) { [datetime]$state.lastDeepRunUtc } else { $null }

        # Safe-only operations always: RAM GC + working set trim + DNS/ARP flush.
        try { [System.GC]::Collect(); [System.GC]::WaitForPendingFinalizers(); [System.GC]::Collect() } catch {}
        try {
            if (-not ([System.Management.Automation.PSTypeName]'MemUtil').Type) {
                Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public class MemUtil {
    [DllImport("psapi.dll")]    public static extern bool EmptyWorkingSet(IntPtr hProcess);
    [DllImport("kernel32.dll")] public static extern IntPtr GetCurrentProcess();
}
'@ -ErrorAction SilentlyContinue
            }
            [MemUtil]::EmptyWorkingSet([MemUtil]::GetCurrentProcess()) | Out-Null
        } catch {}
        try { & ipconfig /flushdns 2>$null | Out-Null } catch {}
        try { & arp -d * 2>$null | Out-Null } catch {}

        # Profile-specific preview mode: run safe clean as dry-run only.
        if ($profileSettings.runDryCleanPreview) {
            if ($Manual) {
                Write-Host ('  profile {0}: running clean preview (dry-run, {1}d stale)...' -f $profileSettings.profile, $profileSettings.dryCleanStaleDays) -ForegroundColor Yellow
            }
            Invoke-SystemClean -StaleDays $profileSettings.dryCleanStaleDays -DryRun
            $didDryClean = $true
        }

        # Deep profile can trigger Defender quick scan on cooldown.
        if ($profileSettings.runDefenderQuickScan) {
            $cooldown = if ($state.cooldownMinutes -gt 0) { $state.cooldownMinutes } else { $profileSettings.defaultCooldownMinutes }
            $canRunDefender = $true
            if ($lastDeepRunUtc) {
                $minutesSinceDeep = ([datetime]::UtcNow - $lastDeepRunUtc).TotalMinutes
                if ($minutesSinceDeep -lt $cooldown) {
                    $canRunDefender = $false
                }
            }

            if ($canRunDefender) {
                if ($Manual) {
                    Write-Host ('  profile {0}: starting Defender quick scan...' -f $profileSettings.profile) -ForegroundColor Yellow
                }
                Invoke-DefenderScan -TargetPaths @()
                $didDefender = $true
                $lastDeepRunUtc = [datetime]::UtcNow
            } elseif ($Manual) {
                Write-Host ('  Defender cooldown active ({0} min).' -f $cooldown) -ForegroundColor DarkGray
            }
        }

        Write-CleanLoopState -Enabled $state.enabled -IntervalMinutes $state.intervalMinutes -Profile $state.profile -CooldownMinutes $state.cooldownMinutes -LastRunUtc ([datetime]::UtcNow) -LastDeepRunUtc $lastDeepRunUtc

        if ($Manual) {
            $dryMsg = if ($didDryClean) { 'yes' } else { 'no' }
            $defMsg = if ($didDefender) { 'yes' } else { 'no' }
            Write-Host ('  loop tick done (profile={0}, dry-clean-preview={1}, defender={2}).' -f $state.profile, $dryMsg, $defMsg) -ForegroundColor Green
        }
    } finally {
        Release-CleanLoopLock
    }
}

function Start-CleanLoopCheck {
    $state = Read-CleanLoopState
    if (-not $state.enabled) { return }

    $profileSettings = Get-CleanLoopProfileSettings -Profile $state.profile
    $interval = if ($state.intervalMinutes -gt 0) { $state.intervalMinutes } else { $profileSettings.defaultIntervalMinutes }

    $lastUtc      = if ($state.lastRunUtc) { [datetime]$state.lastRunUtc } else { [datetime]::MinValue }
    $minutesSince = ([datetime]::UtcNow - $lastUtc).TotalMinutes
    if ($minutesSince -lt $interval) { return }

    $engine = Get-ShellEngine
    if (-not (Test-Path $engine)) { return }

    $arguments = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                   '-File', $PSCommandPath, '-Task', 'CleanLoop')
    try {
        Start-Process -FilePath $engine -ArgumentList $arguments -WindowStyle Hidden -ErrorAction Stop | Out-Null
    } catch {}
}

function Invoke-CleanLoopCommand {
    param([string[]]$Rest)

    $sub = if ($Rest -and $Rest.Count -gt 0) { $Rest[0].ToLowerInvariant() } else { 'status' }

    switch ($sub) {
        'on' {
            $state = Read-CleanLoopState
            $profile = $state.profile
            $mins = $state.intervalMinutes

            if ($Rest.Count -ge 2) {
                foreach ($token in ($Rest | Select-Object -Skip 1)) {
                    $arg = $token.ToLowerInvariant()
                    $parsed = 0
                    if ($script:CleanLoopKnownProfiles -contains $arg) {
                        $profile = $arg
                        continue
                    }
                    if ($arg -match '^\d+$' -and [int]::TryParse($arg, [ref]$parsed) -and $parsed -ge 1) {
                        $mins = $parsed
                    }
                }
            }

            $profileSettings = Get-CleanLoopProfileSettings -Profile $profile
            if (-not $mins -or $mins -lt 1) {
                $mins = $profileSettings.defaultIntervalMinutes
            }

            Write-CleanLoopState -Enabled $true -IntervalMinutes $mins -Profile $profile -CooldownMinutes $profileSettings.defaultCooldownMinutes
            Write-Host ('  clean loop: ON  every {0} min  profile={1}' -f $mins, $profile) -ForegroundColor Green
            Write-Host '  safety: lock + cooldown + dry-run-first deep preview (no auto file deletion).' -ForegroundColor DarkGray
        }
        'off' {
            $state = Read-CleanLoopState
            Write-CleanLoopState -Enabled $false -IntervalMinutes $state.intervalMinutes -Profile $state.profile -CooldownMinutes $state.cooldownMinutes
            Write-Host '  clean loop: OFF' -ForegroundColor DarkGray
        }
        'profile' {
            $state = Read-CleanLoopState
            if ($Rest.Count -lt 2) {
                Write-Host ('  current profile: {0}' -f $state.profile) -ForegroundColor Cyan
                Write-Host ('  available: {0}' -f ($script:CleanLoopKnownProfiles -join ', ')) -ForegroundColor DarkGray
                return
            }

            $requested = $Rest[1].ToLowerInvariant()
            if (-not ($script:CleanLoopKnownProfiles -contains $requested)) {
                Write-Host ('  invalid profile: {0}' -f $requested) -ForegroundColor DarkYellow
                Write-Host ('  available: {0}' -f ($script:CleanLoopKnownProfiles -join ', ')) -ForegroundColor DarkGray
                return
            }

            $settings = Get-CleanLoopProfileSettings -Profile $requested
            Write-CleanLoopState -Enabled $state.enabled -IntervalMinutes $state.intervalMinutes -Profile $requested -CooldownMinutes $settings.defaultCooldownMinutes
            Write-Host ('  clean loop profile set: {0}' -f $requested) -ForegroundColor Green
        }
        'now' {
            Write-Host '  Running clean loop tick...' -ForegroundColor Yellow
            Invoke-CleanLoopTick -Manual
        }
        'status' {
            $state = Read-CleanLoopState
            $settings = Get-CleanLoopProfileSettings -Profile $state.profile
            $lastStr = if ($state.lastRunUtc) {
                $last = [datetime]$state.lastRunUtc
                $ago  = [math]::Round(([datetime]::UtcNow - $last).TotalMinutes, 1)
                ('{0:u}  ({1} min ago)' -f $last, $ago)
            } else { 'never' }
            $deepStr = if ($state.lastDeepRunUtc) {
                $last = [datetime]$state.lastDeepRunUtc
                $ago  = [math]::Round(([datetime]::UtcNow - $last).TotalMinutes, 1)
                ('{0:u}  ({1} min ago)' -f $last, $ago)
            } else { 'never' }
            $stateColor = if ($state.enabled) { 'Green' } else { 'DarkGray' }
            Write-Host ''
            Write-Host ('  clean loop: {0}  every {1} min' -f $(if ($state.enabled) { 'ON' } else { 'OFF' }), $state.intervalMinutes) -ForegroundColor $stateColor
            Write-Host ('  profile:    {0}' -f $state.profile) -ForegroundColor Cyan
            Write-Host ('  last run:   {0}' -f $lastStr) -ForegroundColor DarkGray
            Write-Host ('  last deep:  {0}' -f $deepStr) -ForegroundColor DarkGray
            Write-Host ('  cooldown:   {0} min' -f $state.cooldownMinutes) -ForegroundColor DarkGray
            Write-Host '  safe ops:   RAM GC + working set trim + DNS flush + ARP flush (always)' -ForegroundColor DarkGray
            if ($settings.runDryCleanPreview) {
                Write-Host ('  deep ops:   dry-run clean preview every tick (stale>{0}d)' -f $settings.dryCleanStaleDays) -ForegroundColor DarkGray
            }
            if ($settings.runDefenderQuickScan) {
                Write-Host '  deep ops:   Defender quick scan on cooldown' -ForegroundColor DarkGray
            }
            Write-Host ''
        }
        { $_ -in 'help', '-h', '--help' } {
            Write-Host ''
            Write-HintSection 'CLEAN LOOP -- background auto-optimization (safe-by-default)'
            Write-HintRow '8sync clean --loop on'       'Start loop with current/default interval and profile'
            Write-HintRow '8sync clean --loop on N'     'Start loop every N minutes'
            Write-HintRow '8sync clean --loop on deep'  'Enable deep profile (dry-run clean + Defender cooldown)'
            Write-HintRow '8sync clean --loop on 15 balanced' 'Set interval + profile together'
            Write-HintRow '8sync clean --loop profile <name>' 'Set profile only: light|balanced|deep'
            Write-HintRow '8sync clean --loop off'      'Stop the background clean loop'
            Write-HintRow '8sync clean --loop now'      'Run one tick immediately'
            Write-HintRow '8sync clean --loop status'   'Show loop state and last run time'
            Write-Host ''
        }
        default {
            $parsed = 0
            if ([int]::TryParse($sub, [ref]$parsed) -and $parsed -ge 1) {
                $state = Read-CleanLoopState
                Write-CleanLoopState -Enabled $true -IntervalMinutes $parsed -Profile $state.profile -CooldownMinutes $state.cooldownMinutes
                Write-Host ('  clean loop: ON  every {0} min' -f $parsed) -ForegroundColor Green
            } elseif ($script:CleanLoopKnownProfiles -contains $sub) {
                $state = Read-CleanLoopState
                $settings = Get-CleanLoopProfileSettings -Profile $sub
                Write-CleanLoopState -Enabled $true -IntervalMinutes $state.intervalMinutes -Profile $sub -CooldownMinutes $settings.defaultCooldownMinutes
                Write-Host ('  clean loop: ON  profile={0}' -f $sub) -ForegroundColor Green
            } else {
                Write-Host ('  Unknown loop subcommand: {0}. Try: on, off, profile, now, status' -f $sub) -ForegroundColor DarkYellow
            }
        }
    }
}

function Invoke-SystemClean {
    param(
        [int]$StaleDays = 7,
        [switch]$DryRun
    )

    # Reset session counters
    $script:CleanTotalFreed  = [long]0
    $script:CleanTotalFiles  = 0
    $script:CleanSpinnerIdx  = 0

    $sw    = [System.Diagnostics.Stopwatch]::StartNew()
    $dTag  = if ($DryRun) { '  dry-run' } else { '' }

    Write-Host ''
    Write-Host ('  8sync clean  >{0}d stale{1}' -f $StaleDays, $dTag) -ForegroundColor Cyan
    Write-Host '  SAFE: OS/browser/tool caches + global env/tool caches only. Project folders are never deleted.' -ForegroundColor DarkGray
    Write-Host ''

    # -- Temp --------------------------------------------------------------
    Write-Host '  TEMP' -ForegroundColor Yellow
    $tempPaths = @($env:TEMP, $env:TMP, (Join-Path $env:SystemRoot 'Temp'), (Join-Path $env:LOCALAPPDATA 'Temp')) |
        Select-Object -Unique
    foreach ($p in $tempPaths) {
        $shortLabel = if ($p -like "$HOME*") { '~' + $p.Substring($HOME.Length) } else { $p }
        Invoke-CleanPath -Path $p -Label $shortLabel -StaleDays $StaleDays -DryRun:$DryRun -Recursive | Out-Null
    }

    # -- App caches ------------------------------------------------------
    Write-Host ''
    Write-Host '  APP CACHES' -ForegroundColor Yellow
    $cachePaths = @(
        # -- Browsers --
        @{ Path = (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data\Default\Cache');       Label = 'Chrome' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data\Default\Code Cache');  Label = 'Chrome/code' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data\Default\Cache');      Label = 'Edge' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data\Default\Code Cache'); Label = 'Edge/code' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'Mozilla\Firefox\Profiles');                    Label = 'Firefox' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data\Default\Cache'); Label = 'Brave' }
        # -- Dev tools --
        @{ Path = (Join-Path $env:APPDATA 'Code\User\workspaceStorage');                       Label = 'VSCode/workspace' }
        @{ Path = (Join-Path $env:APPDATA 'Code\logs');                                        Label = 'VSCode/logs' }
        @{ Path = (Join-Path $env:APPDATA 'Code\CachedExtensionVSIXs');                        Label = 'VSCode/vsix' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'npm-cache');                                   Label = 'npm' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'pip\cache');                                   Label = 'pip' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'uv\cache');                                    Label = 'uv' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'go\pkg\mod\cache');                            Label = 'go/mod' }
        @{ Path = (Join-Path $HOME '.cargo\registry\cache');                                   Label = 'cargo/cache' }
        @{ Path = (Join-Path $HOME '.cargo\registry\src');                                     Label = 'cargo/src' }
        @{ Path = (Join-Path $HOME '.cargo\git\checkouts');                                    Label = 'cargo/git' }
        @{ Path = (Join-Path $HOME '.gradle\caches');                                          Label = 'gradle' }
        @{ Path = (Join-Path $HOME '.m2\repository');                                          Label = 'maven' }
        @{ Path = (Join-Path $HOME '.nuget\packages');                                         Label = 'nuget' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'Yarn\Cache');                                  Label = 'yarn' }
        @{ Path = (Join-Path $HOME 'scoop\cache');                                             Label = 'scoop' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'pnpm\store');                                  Label = 'pnpm' }
        @{ Path = (Join-Path $env:APPDATA 'Bun\install\cache');                                Label = 'bun' }
        # -- Communication apps --
        @{ Path = (Join-Path $env:APPDATA 'Microsoft\Teams\Cache');                            Label = 'Teams' }
        @{ Path = (Join-Path $env:APPDATA 'Microsoft\Teams\blob_storage');                     Label = 'Teams/blob' }
        @{ Path = (Join-Path $env:APPDATA 'Microsoft\Teams\databases');                        Label = 'Teams/db' }
        @{ Path = (Join-Path $env:APPDATA 'discord\Cache');                                    Label = 'Discord' }
        @{ Path = (Join-Path $env:APPDATA 'discord\Code Cache');                               Label = 'Discord/code' }
        @{ Path = (Join-Path $env:APPDATA 'Slack\Cache');                                      Label = 'Slack' }
        @{ Path = (Join-Path $env:APPDATA 'Slack\Code Cache');                                 Label = 'Slack/code' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'Spotify\Storage');                             Label = 'Spotify' }
    )
    foreach ($entry in $cachePaths) {
        Invoke-CleanPath -Path $entry.Path -Label $entry.Label -StaleDays $StaleDays -DryRun:$DryRun -Recursive | Out-Null
    }

    # -- Toolchain command-based caches ----------------------------------
    Write-Host ''
    Write-Host '  TOOLCHAIN CACHES' -ForegroundColor Yellow

    # go build cache: go clean -cache (100% safe, regenerates)
    if (Test-CommandExists 'go') {
        Write-CleanSpinner -Msg 'go build cache...'
        try {
            $goCache = & go env GOCACHE 2>$null
            if ($goCache -and [System.IO.Directory]::Exists($goCache)) {
                $goCacheSize = (Get-ChildItem $goCache -Recurse -Force -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum).Sum
                Clear-SpinnerLine
                if (-not $DryRun) {
                    & go clean -cache 2>$null
                    Write-Host ('  [go/build]    {0,-48} freed ~{1}' -f $goCache, (Format-Bytes ([long]$goCacheSize))) -ForegroundColor Green
                    $script:CleanTotalFreed += [long]$goCacheSize
                } else {
                    Write-Host ('  [go/build]    {0,-48} would free ~{1}' -f $goCache, (Format-Bytes ([long]$goCacheSize))) -ForegroundColor DarkYellow
                }
            } else {
                Clear-SpinnerLine
                Write-Host '  [go/build]    cache empty or not found' -ForegroundColor DarkGray
            }
        } catch {
            Clear-SpinnerLine
            Write-Host '  [go/build]    skipped (error)' -ForegroundColor DarkGray
        }
    }

    # go module cache: go clean -modcache (safe, but slow rebuilds)
    if (Test-CommandExists 'go') {
        Write-CleanSpinner -Msg 'go module cache...'
        try {
            $goModCache = & go env GOMODCACHE 2>$null
            if ($goModCache -and [System.IO.Directory]::Exists($goModCache)) {
                $goModSize = (Get-ChildItem $goModCache -Recurse -Force -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum).Sum
                Clear-SpinnerLine
                if (-not $DryRun) {
                    & go clean -modcache 2>$null
                    Write-Host ('  [go/mod]      {0,-48} freed ~{1}' -f $goModCache, (Format-Bytes ([long]$goModSize))) -ForegroundColor Green
                    $script:CleanTotalFreed += [long]$goModSize
                } else {
                    Write-Host ('  [go/mod]      {0,-48} would free ~{1}' -f $goModCache, (Format-Bytes ([long]$goModSize))) -ForegroundColor DarkYellow
                }
            } else {
                Clear-SpinnerLine
                Write-Host '  [go/mod]      cache empty or not found' -ForegroundColor DarkGray
            }
        } catch {
            Clear-SpinnerLine
            Write-Host '  [go/mod]      skipped (error)' -ForegroundColor DarkGray
        }
    }

    # docker system prune: safe to remove stopped containers, dangling images, build cache
    if (Test-CommandExists 'docker') {
        Write-CleanSpinner -Msg 'docker prune...'
        try {
            # Check if docker daemon is running
            $null = & docker info 2>$null
            if ($LASTEXITCODE -eq 0) {
                Clear-SpinnerLine
                if (-not $DryRun) {
                    $pruneOut = & docker system prune -f 2>&1 | Out-String
                    # Parse "Total reclaimed space: X.XXX MB" from output
                    $reclaimedMatch = [regex]::Match($pruneOut, 'Total reclaimed space:\s+([\d.]+)\s*(B|kB|MB|GB)')
                    $reclaimedLabel = if ($reclaimedMatch.Success) { $reclaimedMatch.Value.Trim() } else { 'done' }
                    Write-Host ('  [docker]      prune complete — {0}' -f $reclaimedLabel) -ForegroundColor Green
                } else {
                    $dfOut = & docker system df 2>&1 | Out-String
                    Write-Host '  [docker]      would run: docker system prune -f' -ForegroundColor DarkYellow
                    Write-Host ($dfOut.Trim() -replace '^', '              ') -ForegroundColor DarkGray
                }
            } else {
                Clear-SpinnerLine
                Write-Host '  [docker]      daemon not running, skipped' -ForegroundColor DarkGray
            }
        } catch {
            Clear-SpinnerLine
            Write-Host '  [docker]      skipped (not available)' -ForegroundColor DarkGray
        }
    }

    # -- Windows caches --------------------------------------------------
    Write-Host ''
    Write-Host '  WINDOWS' -ForegroundColor Yellow
    $winCaches = @(
        # -- System caches (some need admin -- fail silently) --
        @{ Path = (Join-Path $env:SystemRoot 'SoftwareDistribution\Download'); Label = 'WU/download' }
        @{ Path = (Join-Path $env:SystemRoot 'Prefetch');                       Label = 'Prefetch' }
        # -- User-space caches (no admin) --
        @{ Path = (Join-Path $env:LOCALAPPDATA 'CrashDumps');                   Label = 'CrashDumps' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\INetCache');  Label = 'INetCache' }
        @{ Path = (Join-Path $env:APPDATA 'Microsoft\Windows\Recent');          Label = 'Recent' }
        @{ Path = (Join-Path $env:APPDATA 'Microsoft\Windows\Recent\AutomaticDestinations');   Label = 'JumpLists' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\WER');        Label = 'ErrorReports' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer');   Label = 'Thumbnails' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'D3DSCache');                    Label = 'D3DShader' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'NVIDIA\DXCache');               Label = 'NVIDIA/DXCache' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'NVIDIA\GLCache');               Label = 'NVIDIA/GLCache' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'AMD\DxCache');                  Label = 'AMD/DxCache' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'AMD\GLCache');                  Label = 'AMD/GLCache' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'Intel\ShaderCache');            Label = 'Intel/Shader' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\ActionCenterCache'); Label = 'ActionCenter' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Caches');     Label = 'WinCaches' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\WebCache');   Label = 'WebCache' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'IconCache.db');                 Label = 'IconCache' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.Windows.Search_cw5n1h2txyewy\LocalState\ConstraintIndex'); Label = 'SearchIdx' }
    )
    foreach ($entry in $winCaches) {
        Invoke-CleanPath -Path $entry.Path -Label $entry.Label -StaleDays $StaleDays -DryRun:$DryRun -Recursive | Out-Null
    }

    # -- Stale envs ------------------------------------------------------
    Write-Host ''
    Write-Host ('  STALE ENVS  (>{0}d)' -f $StaleDays) -ForegroundColor Yellow
    $searchRoots = @(
        (Join-Path $HOME '.conda\envs'),
        (Join-Path $HOME 'miniconda3\envs'),
        (Join-Path $HOME 'miniforge3\envs'),
        (Join-Path $HOME 'mambaforge\envs'),
        (Join-Path $HOME 'anaconda3\envs'),
        (Join-Path $HOME 'anaconda\envs'),
        (Join-Path $env:LOCALAPPDATA 'conda\conda\envs'),
        (Join-Path $env:USERPROFILE 'AppData\Local\miniconda3\envs'),
        (Join-Path $env:APPDATA 'uv\tools')
    ) | Where-Object { Test-Path $_ } | Select-Object -Unique

    if ($searchRoots.Count -gt 0) {
        $venvDirs = Find-VenvDirs -SearchRoots $searchRoots -StaleDays $StaleDays
        Clear-SpinnerLine
        if ($venvDirs.Count -gt 0) {
            foreach ($venv in $venvDirs) {
                Remove-VenvDir -Path $venv -DryRun:$DryRun | Out-Null
            }
        } else {
            Write-Host '  no stale envs' -ForegroundColor DarkGray
        }
    }

    # -- RAM + network flush --------------------------------------------
    Write-Host ''
    Write-Host '  MEMORY & NETWORK' -ForegroundColor Yellow
    Invoke-RamFlush -DryRun:$DryRun

    # -- Disk optimization -----------------------------------------------
    Write-Host ''
    Write-Host '  DISK' -ForegroundColor Yellow
    Invoke-DiskOptimize -DryRun:$DryRun

    # -- Summary ----------------------------------------------------------
    $sw.Stop()
    $elapsed = if ($sw.Elapsed.TotalSeconds -ge 60) {
        ('{0}m {1}s' -f [int]$sw.Elapsed.TotalMinutes, $sw.Elapsed.Seconds)
    } else {
        ('{0:F1}s' -f $sw.Elapsed.TotalSeconds)
    }
    Write-Host ''
    $summaryColor = if ($DryRun) { 'DarkYellow' } else { 'Green' }
    $verb         = if ($DryRun) { 'would free' } else { 'freed' }
    Write-Host ('  >> {0} {1}  {2} files  {3}' -f $verb, (Format-Bytes $script:CleanTotalFreed), $script:CleanTotalFiles, $elapsed) -ForegroundColor $summaryColor
    if ($DryRun) { Write-Host '  run without --dry-run to apply' -ForegroundColor DarkGray }
    Write-Host ''
}

function Invoke-CleanCommand {
    param([string[]]$Rest)

    $dryRun      = $false
    $staleDays   = 7
    $doProjects  = $false
    $projectsAll = $false
    $doDeep      = $false
    $doDelete    = $false
    $doScan      = $false
    $doAudit     = $false
    $doLoop      = $false
    $loopArgs    = @()
    $scanPaths   = @()

    foreach ($arg in $Rest) {
        switch ($arg.ToLowerInvariant()) {
            '--dry-run'  { $dryRun = $true }
            '--projects' { $doProjects = $true }
            '--all'      { $projectsAll = $true }
            '--deep'     { $doDeep = $true }
            '--delete'   { $doDelete = $true }
            '--scan'     { $doScan = $true }
            '--audit'    { $doAudit = $true }
            '--loop'     { $doLoop = $true }
            { $_ -in '--help', 'help', '-h' } {
                Write-Host ''
                Write-HintSection 'CLEAN -- deep system / cache / global env / RAM / disk'
                Write-HintRow '8sync clean'                          'Full clean: temp/cache/global env/RAM/disk (stale > 7d)'
                Write-HintRow '8sync clean --days N'                 'Custom stale threshold  e.g. --days 14'
                Write-HintRow '8sync clean --dry-run'                'Preview only -- nothing deleted'
                Write-HintRow '8sync clean --projects'               'Report stale git repos only (deletion disabled for safety)'
                Write-HintRow '8sync clean --projects --all'         'Alias accepted but ignored (deletion disabled)'
                Write-HintRow '8sync clean --projects --days N'      'Stale threshold for projects (default: 90d)'
                Write-HintRow '8sync clean --projects --dry-run'     'Report stale projects (same as without --dry-run)'
                Write-HintRow '8sync clean --deep'                   'Report stale MCP/npm/pip/cargo/go artifacts'
                Write-HintRow '8sync clean --deep --delete'          'Delete stale artifacts with per-type confirmation'
                Write-HintRow '8sync clean --deep --delete --all'    'Delete ALL stale artifacts, skip per-type prompt'
                Write-HintRow '8sync clean --deep --delete --dry-run' 'Preview what --delete would remove'
                Write-HintRow '8sync clean --deep --days N'          'Custom threshold for artifact scan'
                Write-HintRow '8sync clean --scan'                   'Windows Defender quick + dev-folder scan'
                Write-HintRow '8sync clean --scan <path>'            'Targeted Defender scan on specific path'
                Write-HintRow '8sync clean --audit'                  'npm/cargo/pip vulnerability scan + postinstall check'
                Write-HintRow '8sync clean --loop on [N] [profile]'  'Auto loop: light|balanced|deep with safety lock/cooldown'
                Write-HintRow '8sync clean --loop off'               'Stop background clean loop'
                Write-HintRow '8sync clean --loop status'            'Show loop state and last run time'
                Write-HintRow '8sync clean --loop profile <name>'    'Change loop profile: light|balanced|deep'
                Write-Host ''
                return
            }
        }
    }

    for ($i = 0; $i -lt $Rest.Count; $i++) {
        if ($Rest[$i] -in '--days', '-d') {
            $parsed = 0
            if ($i + 1 -lt $Rest.Count -and [int]::TryParse($Rest[$i + 1], [ref]$parsed) -and $parsed -gt 0) {
                $staleDays = $parsed
            }
        }
        if ($Rest[$i].ToLowerInvariant() -eq '--scan') {
            for ($j = $i + 1; $j -lt $Rest.Count; $j++) {
                if ($Rest[$j] -like '--*') { break }
                $scanPaths += $Rest[$j]
            }
        }
        if ($Rest[$i].ToLowerInvariant() -eq '--loop') {
            for ($j = $i + 1; $j -lt $Rest.Count; $j++) {
                if ($Rest[$j] -like '--*') { break }
                $loopArgs += $Rest[$j]
            }
        }
    }

    if ($doProjects) {
        # Use explicit --days N if provided, otherwise default 90d for projects
        $projectDays = if ($Rest -contains '--days' -or $Rest -contains '-d') { $staleDays } else { 90 }
        Invoke-ProjectPicker -StaleDays $projectDays -All:$projectsAll -DryRun:$dryRun
        return
    }

    if ($doDeep) {
        $artifacts = Show-DevArtifactReport -StaleDays $staleDays
        if ($doDelete -and $artifacts -and $artifacts.Count -gt 0) {
            Invoke-DeleteDevArtifacts -Artifacts $artifacts -All:$projectsAll -DryRun:$dryRun
        }
        return
    }

    if ($doScan) {
        Invoke-DefenderScan -TargetPaths $scanPaths
        return
    }

    if ($doAudit) {
        Invoke-EcosystemAudit
        return
    }

    if ($doLoop) {
        Invoke-CleanLoopCommand -Rest $loopArgs
        return
    }

    Invoke-SystemClean -StaleDays $staleDays -DryRun:$dryRun
}
