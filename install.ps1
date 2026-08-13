#Requires -Version 5.1
<#
.SYNOPSIS
    flash-term auto-installer / updater (Windows).
.DESCRIPTION
    Installs or updates the flash-term WezTerm config to
    %USERPROFILE%\.config\wezterm (or -ConfigDir). Idempotent:
    re-running pulls the latest. Prefers git; falls back to a tarball.
.EXAMPLE
    # One-liner (public repo / hosted):
    irm https://8-sync-dev.github.io/flash-term/install.ps1 | iex

    # Authenticated one-liner (private repo, gh installed):
    gh api repos/8-Sync-Dev/flash-term/contents/install.ps1 --jq .content | ForEach-Object { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_)) } | iex

    # Local / from source:
    pwsh -File install.ps1
    pwsh -File install.ps1 -Update
#>
[CmdletBinding()]
param(
    [string]$ConfigDir,
    [switch]$Update,
    [switch]$NoSetup,
    [string]$Repo = 'https://github.com/8-Sync-Dev/flash-term',
    [string]$Branch = 'main'
)

$ErrorActionPreference = 'Continue'
$VerbosePreference = 'SilentlyContinue'

function Write-Step($m) { Write-Host "  [info]  $m" -ForegroundColor Cyan }
function Write-Ok($m)   { Write-Host "  [ok]    $m" -ForegroundColor Green }
function Write-Warn2($m){ Write-Host "  [warn]  $m" -ForegroundColor DarkYellow }
function Write-Err($m)  { Write-Host "  [error] $m" -ForegroundColor Red }

# ── resolve target ──────────────────────────────────────────────────────────
$target = if ($ConfigDir) { $ConfigDir } else { Join-Path $env:USERPROFILE '.config\wezterm' }
$parent = Split-Path $target -Parent

Write-Host ''
Write-Host '  flash-term installer' -ForegroundColor Magenta
Write-Host "  target: $target" -ForegroundColor DarkGray
Write-Host ''

# ── 1. git path? ─────────────────────────────────────────────────────────────
$git = (Get-Command git -ErrorAction SilentlyContinue).Source
if (-not $git) {
    foreach ($p in @(
        (Join-Path $env:LOCALAPPDATA 'bin\git\cmd\git.exe'),
        'C:\Program Files\Git\cmd\git.exe',
        (Join-Path $env:USERPROFILE 'scoop\shims\git.exe')
    )) { if (Test-Path $p) { $git = $p; break } }
}

# ── 2. install / update ─────────────────────────────────────────────────────
$cloned = $false
if ($git) {
    if (Test-Path (Join-Path $target '.git')) {
        Write-Step "existing git checkout -> pulling $Branch"
        & $git -C $target fetch -q origin $Branch 2>&1 | Out-Null
        & $git -C $target reset --hard -q "origin/$Branch" 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Ok "updated to origin/$Branch" }
        else { Write-Err 'git pull failed'; exit 1 }
    } elseif ((Test-Path $target) -and (Get-ChildItem $target -Force -ErrorAction SilentlyContinue)) {
        Write-Warn2 "$target exists and is not empty (and not a git clone)."
        Write-Warn2 'Pass -ConfigDir to choose another location, or empty it first.'
        exit 1
    } else {
        $null = New-Item -ItemType Directory -Force -Path $parent
        Write-Step "git clone -> $target"
        & $git clone -q -b $Branch $Repo $target 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Ok 'cloned'; $cloned = $true }
        else {
            Write-Warn2 'git clone failed (private repo without auth?); trying tarball...'
            $git = $null   # fall through to tarball path
        }
    }
}

if (-not $git) {
    # Tarball fallback (works for public repos; private needs $env:GH_TOKEN / GH_PAT)
    Write-Step 'downloading tarball'
    $tmpZip = [System.IO.Path]::GetTempFileName() + '.zip'
    $url = "https://api.github.com/repos/8-Sync-Dev/flash-term/zipball/$Branch"
    $headers = @{ 'User-Agent' = 'flash-term-installer' }
    if ($env:GH_TOKEN) { $headers['Authorization'] = "Bearer $env:GH_TOKEN" }
    elseif ($env:GH_PAT) { $headers['Authorization'] = "Bearer $env:GH_PAT" }
    try {
        Invoke-WebRequest -Uri $url -OutFile $tmpZip -Headers $headers -UseBasicParsing -ErrorAction Stop
    } catch {
        Write-Err "download failed: $($_.Exception.Message)"
        Write-Warn2 'For a private repo, set $env:GH_TOKEN (gh auth token) first.'
        exit 1
    }
    $extract = Join-Path ([System.IO.Path]::GetTempPath()) "flashterm-$(Get-Random)"
    $null = New-Item -ItemType Directory -Force -Path $extract
    Expand-Archive -Path $tmpZip -DestinationPath $extract -Force
    $inner = Get-ChildItem $extract -Directory | Select-Object -First 1
    if (Test-Path $target) { Remove-Item $target -Recurse -Force -ErrorAction SilentlyContinue }
    $null = New-Item -ItemType Directory -Force -Path $target
    # Copy each child of the inner extracted dir (reliable on PS 5.1, unlike wildcard Move-Item)
    Get-ChildItem -Path $inner.FullName -Force | Copy-Item -Destination $target -Recurse -Force
    if (-not (Test-Path (Join-Path $target 'wezterm.lua'))) {
        Write-Err 'extraction produced no wezterm.lua'
        exit 1
    }
    Remove-Item $extract -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue
    Write-Ok 'installed from tarball'
}

# ── 3. sanity: config present? ──────────────────────────────────────────────
if (-not (Test-Path (Join-Path $target 'wezterm.lua'))) {
    Write-Err 'wezterm.lua missing after install -- aborting'
    exit 1
}

# ── 4. full bootstrap (ft setup) unless skipped/update-only ─────────────
if (-not $NoSetup -and -not $Update) {
    Write-Host ''
    Write-Host '  == Full bootstrap: ft setup ==' -ForegroundColor Magenta
    Write-Host '  (PATH + Scoop + WezTerm + tools + dev runtimes + su-code AI)' -ForegroundColor DarkGray
    $env:PATH = "$env:windir\System32;$env:windir;$target;$env:PATH"
    & powershell -NoProfile -ExecutionPolicy Bypass -Command ". (Join-Path '$target' 'wezterm-bootstrap.ps1') -Task Status 2>`$null; Invoke-SetupCommand"
} else {
    $wt = Get-Command wezterm -ErrorAction SilentlyContinue
    if ($wt) { Write-Ok "WezTerm found: $($wt.Source)" }
    else { Write-Warn2 'WezTerm not found -- run: scoop install wezterm' }
}

# ── 5. done ────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '  Done.' -ForegroundColor Green
if ($Update) {
    Write-Host '  flash-term updated. Reload in WezTerm: ft reload' -ForegroundColor DarkGray
} else {
    Write-Host '  Launch WezTerm -> ft (looks/tools) + 8sync . (AI session, su-code).' -ForegroundColor DarkGray
    Write-Host '  Update anytime: re-run this installer (or ft up self / ft autoupdate on).' -ForegroundColor DarkGray
}
Write-Host ''
