# =============================================================================
# 8sync agents -- shared functions, skill registry helpers
# =============================================================================

function Get-AgentRegistryPath {
    # Canonical registry JSON shipped with the config repo.
    Join-Path $PSScriptRoot '..\..\agents\registry.json'
}

function Get-AgentSkillRegistry {
    # Returns the skill registry as an array of PSCustomObjects.
    # Falls back to built-in minimal registry if file is missing.
    $path = Get-AgentRegistryPath
    if (Test-Path $path) {
        try {
            $raw = [System.IO.File]::ReadAllText($path)
            $list = $raw | ConvertFrom-Json -ErrorAction Stop
            return @($list | Sort-Object { [int]($_.priority) })
        } catch {
            Write-Host ('  [warn]   Could not parse agents/registry.json: {0}' -f $_.Exception.Message) -ForegroundColor DarkYellow
        }
    }
    # Minimal fallback
    return @(
        [pscustomobject]@{
            name = 'karpathy'; display = 'Karpathy Guidelines'
            url = 'https://github.com/forrestchang/andrej-karpathy-skills'
            dir = 'karpathy-guidelines'; priority = 1; mandatory = $true; builtin = $true
            use_when = 'ALL coding tasks — mandatory baseline.'
            tags = @('baseline','engineering','mandatory')
        }
    )
}

function Get-AgentInstallRoot {
    # Where installed skill content lives (gitignored).
    Join-Path $PSScriptRoot '..\..\agents\skills'
}

function Get-ForgeGlobalSkillsDir {
    Join-Path $HOME '.forge\skills'
}

function Get-GsdSkillsDir {
    # GSD project skills directory (current working directory).
    Join-Path (Get-Location) '.gsd\skills'
}

function Get-ClaudeContextDir {
    Join-Path $HOME '.claude'
}

function Get-RealGitExe {
    # Resolve the REAL git.exe path, bypassing any .bat shims in PATH
    # (rtk-forge-shims/git.bat would redirect to `rtk git` which can't clone).
    $shimDir = Join-Path $HOME '.local\bin\rtk-forge-shims'
    $candidates = $env:PATH -split ';' | Where-Object { $_ -ine $shimDir -and $_ -ne '' }
    foreach ($d in $candidates) {
        $p = Join-Path $d 'git.exe'
        if (Test-Path $p) { return $p }
    }
    # Fallback common locations
    foreach ($p in @(
        'C:\Program Files\Git\cmd\git.exe',
        'C:\Program Files\Git\bin\git.exe',
        (Join-Path $HOME 'scoop\shims\git.exe')
    )) {
        if (Test-Path $p) { return $p }
    }
    return 'git'  # hope for the best
}

function Suspend-Defender {
    # Temporarily add exclusion paths for git clone dirs to stop Antimalware
    # from scanning every git object (1.7GB+ RAM). Requires elevation.
    # Returns $true if exclusions were added, $false if not (non-admin).
    param([string[]]$Paths)
    $added = @()
    try {
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdmin) {
            # Try via powershell -Verb RunAs silently -- skip if UAC blocked
            return @()
        }
        foreach ($p in $Paths) {
            try {
                Add-MpPreference -ExclusionPath $p -ErrorAction Stop
                $added += $p
            } catch {}
        }
        # Also exclude git.exe process from real-time scan during clone
        try { Add-MpPreference -ExclusionProcess 'git.exe' -ErrorAction Stop } catch {}
        return $added
    } catch {
        return @()
    }
}

function Resume-Defender {
    # Remove exclusions added by Suspend-Defender.
    param([string[]]$Paths)
    foreach ($p in $Paths) {
        try { Remove-MpPreference -ExclusionPath $p -ErrorAction SilentlyContinue } catch {}
    }
    try { Remove-MpPreference -ExclusionProcess 'git.exe' -ErrorAction SilentlyContinue } catch {}
}

function Invoke-EmptyWorkingSet {
    # Flush current process working set to free physical RAM pages back to OS.
    # Safe -- OS will page back in on demand. Gives headroom for git clones.
    try {
        $sig = @'
using System; using System.Runtime.InteropServices;
public class WS { [DllImport("psapi.dll")] public static extern bool EmptyWorkingSet(IntPtr h); }
'@
        if (-not ([System.Management.Automation.PSTypeName]'WS').Type) {
            Add-Type -TypeDefinition $sig -Language CSharp -ErrorAction Stop
        }
        [WS]::EmptyWorkingSet([System.Diagnostics.Process]::GetCurrentProcess().Handle) | Out-Null
    } catch {}
}

function Clone-SkillRepo {
    # Clone or pull a git skill repo into the install root.
    # Returns the local path on success, $null on failure.
    param(
        [string]$Url,
        [string]$Dir,
        [switch]$DryRun
    )

    $root    = Get-AgentInstallRoot
    $target  = Join-Path $root $Dir

    if ($DryRun) {
        Write-Host ('  [dry-run] Would clone {0} -> {1}' -f $Url, $target) -ForegroundColor Yellow
        return $target
    }

    if (-not (Test-Path $root)) {
        $null = New-Item -Path $root -ItemType Directory -Force
    }

    $gitExe = Get-RealGitExe

    if (Test-Path (Join-Path $target '.git')) {
        # Already cloned -- pull latest
        try {
            Write-Host ('  [info]   Pulling latest: {0}' -f $Dir) -ForegroundColor DarkGray
            $env:GIT_TERMINAL_PROMPT = '0'
            $null = & $gitExe -C $target pull --ff-only --no-tags --quiet 2>&1
            $env:GIT_TERMINAL_PROMPT = $null
            Write-Host ('  [ok]     {0}: up to date' -f $Dir) -ForegroundColor Green
        } catch {
            $env:GIT_TERMINAL_PROMPT = $null
        }
        return $target
    }

    # Ensure URL ends with .git for reliable clone
    $cloneUrl = $Url
    if ($cloneUrl -notmatch '\.git$' -and $cloneUrl -match 'github\.com') {
        $cloneUrl = $cloneUrl.TrimEnd('/') + '.git'
    }

    # Free RAM before clone: flush working set + GC
    Invoke-EmptyWorkingSet
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()

    # Fresh clone -- ultra-light to avoid RAM spike (0xc0000142 on low-mem machines)
    try {
        Write-Host ('  [info]   Cloning {0}...' -f $cloneUrl) -ForegroundColor DarkGray
        $env:GIT_TERMINAL_PROMPT = '0'
        $env:GIT_CONFIG_NOSYSTEM = '1'
        $null = & $gitExe clone --depth=1 --single-branch --no-tags --filter=blob:none --quiet $cloneUrl $target 2>&1
        $exitCode = $LASTEXITCODE
        $env:GIT_TERMINAL_PROMPT = $null
        $env:GIT_CONFIG_NOSYSTEM = $null
        if ($exitCode -eq 0) {
            Write-Host ('  [ok]     Cloned -> {0}' -f $target) -ForegroundColor Green
            # Free memory between clones
            [GC]::Collect()
            [GC]::WaitForPendingFinalizers()
            Invoke-EmptyWorkingSet
            Start-Sleep -Milliseconds 300
            return $target
        }
        Write-Host ('  [error]  git clone failed (exit {0})' -f $exitCode) -ForegroundColor Red
        return $null
    } catch {
        $env:GIT_TERMINAL_PROMPT = $null
        $env:GIT_CONFIG_NOSYSTEM = $null
        Write-Host ('  [error]  {0}' -f $_.Exception.Message) -ForegroundColor Red
        return $null
    }
}

function Fetch-SkillFromUrl {
    # Fetch skill content from a plain URL (not a git repo).
    # Saves to agents/skills/<dir>/SKILL.md
    param(
        [string]$Url,
        [string]$Dir,
        [switch]$DryRun
    )

    $root    = Get-AgentInstallRoot
    $target  = Join-Path $root $Dir
    $skillMd = Join-Path $target 'SKILL.md'

    if ($DryRun) {
        Write-Host ('  [dry-run] Would fetch {0} -> {1}' -f $Url, $skillMd) -ForegroundColor Yellow
        return $target
    }

    if (-not (Test-Path $target)) {
        $null = New-Item -Path $target -ItemType Directory -Force
    }

    try {
        $content = (Invoke-WebRequest -Uri $Url -UseBasicParsing -ErrorAction Stop).Content
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($skillMd, $content, $utf8NoBom)
        Write-Host ('  [ok]     Fetched {0} -> SKILL.md ({1} chars)' -f $Url, $content.Length) -ForegroundColor Green
        return $target
    } catch {
        Write-Host ('  [error]  Fetch failed: {0}' -f $_.Exception.Message) -ForegroundColor Red
        return $null
    }
}

function Deploy-SkillToForge {
    # Copy/link installed skill content into ~/.forge/skills/<dir>/.
    # Forge loads all .md files in that dir automatically.
    param(
        [string]$SourceDir,
        [string]$SkillDir,
        [switch]$DryRun
    )

    $forgeSkills = Get-ForgeGlobalSkillsDir
    $target      = Join-Path $forgeSkills $SkillDir

    if ($DryRun) {
        Write-Host ('  [dry-run] Would deploy to {0}' -f $target) -ForegroundColor Yellow
        return
    }

    if (-not (Test-Path $SourceDir)) {
        Write-Host ('  [warn]   Source not found: {0}' -f $SourceDir) -ForegroundColor DarkYellow
        return
    }

    if (-not (Test-Path $forgeSkills)) {
        $null = New-Item -Path $forgeSkills -ItemType Directory -Force
    }

    # Copy source dir -> forge skills dir (overwrite)
    try {
        if (Test-Path $target) {
            Remove-Item $target -Recurse -Force
        }
        Copy-Item $SourceDir $target -Recurse -Force
        Write-Host ('  [ok]     Deployed to ~/.forge/skills/{0}/' -f $SkillDir) -ForegroundColor Green
    } catch {
        Write-Host ('  [error]  Deploy failed: {0}' -f $_.Exception.Message) -ForegroundColor Red
    }
}

function Find-SkillMd {
    # Locate the primary SKILL.md (or README.md) inside a cloned skill dir.
    param([string]$Dir)

    foreach ($candidate in @('SKILL.md', 'skill.md', 'README.md', 'readme.md')) {
        $p = Join-Path $Dir $candidate
        if (Test-Path $p) { return $p }
    }
    # Recursive search
    $found = Get-ChildItem -Path $Dir -Filter 'SKILL.md' -Recurse -File -ErrorAction SilentlyContinue |
             Select-Object -First 1
    if ($found) { return $found.FullName }
    $found = Get-ChildItem -Path $Dir -Filter 'README.md' -Recurse -File -ErrorAction SilentlyContinue |
             Select-Object -First 1
    if ($found) { return $found.FullName }
    return $null
}
