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

    if (Test-Path (Join-Path $target '.git')) {
        # Already cloned -- pull latest (non-interactive, 30s timeout)
        try {
            Write-Host ('  [info]   Pulling latest: {0}' -f $Dir) -ForegroundColor DarkGray
            $env:GIT_TERMINAL_PROMPT = '0'
            $proc = Start-Process -FilePath 'git' -ArgumentList 'pull','--ff-only' -WorkingDirectory $target -NoNewWindow -Wait -PassThru -RedirectStandardOutput ([System.IO.Path]::GetTempFileName()) -RedirectStandardError ([System.IO.Path]::GetTempFileName())
            if ($proc.ExitCode -eq 0) {
                Write-Host ('  [ok]     {0}: up to date' -f $Dir) -ForegroundColor Green
            }
        } catch {}
        $env:GIT_TERMINAL_PROMPT = $null
        return $target
    }

    # Ensure URL ends with .git for reliable clone
    $cloneUrl = $Url
    if ($cloneUrl -notmatch '\.git$' -and $cloneUrl -match 'github\.com') {
        $cloneUrl = $cloneUrl.TrimEnd('/') + '.git'
    }

    # Fresh clone -- non-interactive (GIT_TERMINAL_PROMPT=0), 60s timeout
    try {
        Write-Host ('  [info]   Cloning {0}...' -f $cloneUrl) -ForegroundColor DarkGray
        $env:GIT_TERMINAL_PROMPT = '0'
        $stdoutTmp = [System.IO.Path]::GetTempFileName()
        $stderrTmp = [System.IO.Path]::GetTempFileName()
        $proc = Start-Process -FilePath 'git' -ArgumentList 'clone','--depth=1',$cloneUrl,$target -NoNewWindow -Wait -PassThru -RedirectStandardOutput $stdoutTmp -RedirectStandardError $stderrTmp
        $env:GIT_TERMINAL_PROMPT = $null
        Remove-Item $stdoutTmp -Force -ErrorAction SilentlyContinue
        Remove-Item $stderrTmp -Force -ErrorAction SilentlyContinue
        if ($proc.ExitCode -eq 0) {
            Write-Host ('  [ok]     Cloned -> {0}' -f $target) -ForegroundColor Green
            return $target
        }
        Write-Host ('  [error]  git clone failed (exit {0})' -f $proc.ExitCode) -ForegroundColor Red
        return $null
    } catch {
        $env:GIT_TERMINAL_PROMPT = $null
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
