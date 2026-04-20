# =============================================================================
# 8sync gsd local -- project-scoped gsd-pi vendoring
#
# Contract:
#   - Never touches global gsd-pi runtime (~/.gsd/agent, ~/scoop, npm -g, bun -g)
#   - All operations scoped to <project>/.gsd/vendor/gsd-pi/
#   - 3-layer vendoring:
#       baseline-<pinned>/   immutable snapshot, reference + rollback
#       latest/              submodule upstream, auto-pull, read-only
#       current/             working copy with patches, active runtime
#   - current/ is the runtime; baseline/latest are never run
# =============================================================================

$script:GsdUpstreamRepo = 'https://github.com/gsd-build/gsd-2.git'

function Resolve-GsdLocalAgentDir {
    $projectRoot = Resolve-GsdProjectRoot
    if (-not $projectRoot) { return $null }
    return Join-Path $projectRoot '.gsd\vendor\agent'
}

function Write-GsdVendorReadme {
    param([string]$Path)
    $content = @"
# GSD local runtime

Project-scoped gsd-pi vendoring. This directory is NOT global. Global runtime under `~/.gsd/agent/` stays untouched.

## Layout

| Folder | Role | Mutable | Runs? |
|---|---|---|---|
| `gsd-pi/baseline-$($script:GsdPinnedVersion)/` | Immutable snapshot of gsd-pi@$($script:GsdPinnedVersion) | No | No |
| `gsd-pi/latest/` | Submodule of upstream $($script:GsdUpstreamRepo) | No (auto-pull only) | No |
| `gsd-pi/current/` | Working copy. Starts from baseline, patches applied. | Yes | **Yes** |
| `agent/` | Local equivalent of `~/.gsd/agent/` -- auth, settings, extensions | Yes | **Yes** |

## Workflow

``````
8sync gsd local init                # scaffold layout
8sync gsd local baseline            # seed baseline from global or clone
8sync gsd local add-submodule       # add upstream as submodule at latest/
8sync gsd local use baseline        # point current/ to baseline copy
8sync gsd local fix --stable        # patch current/ with known stable fixes
8sync gsd local enter               # activate GSD_CODING_AGENT_DIR for this shell
gsd ...                             # now runs from current/
8sync gsd local leave               # revert to global
``````

## Notes

- `current/` is yours to commit into the project repo for reproducibility.
- `latest/` is a submodule reference; diff against baseline to decide what to merge.
- Global `gsd-pi` install is never touched by these commands.
- Global install is only refreshed when `--allow-global` is explicitly passed to `8sync gsd fix`.
"@
    $parent = Split-Path $Path -Parent
    if (-not (Test-Path $parent)) { $null = New-Item -Path $parent -ItemType Directory -Force }
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $content, $utf8NoBom)
}

function Write-GsdVendorGitignore {
    param([string]$Path)
    $content = @"
# Keep baseline + current source. Exclude build artifacts and submodule internals.

# baseline + current are committed source; do not ignore their .git or code
# but do ignore transient build outputs

# node_modules inside current/ is regenerated per-machine
gsd-pi/current/node_modules/
gsd-pi/baseline-*/node_modules/

# local agent state: auth + db, do not commit secrets
agent/auth.json
agent/.env
agent/*.db
agent/*.db-*
agent/extensions/*/node_modules/
"@
    $parent = Split-Path $Path -Parent
    if (-not (Test-Path $parent)) { $null = New-Item -Path $parent -ItemType Directory -Force }
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $content, $utf8NoBom)
}

function Write-GsdVendorPatchesLog {
    param([string]$Path)
    $content = @"
# Applied patches on current/

Each row documents a patch applied to `current/` after seeding from baseline.
Review this list when upgrading current/ to a newer baseline, or when cherry-picking from latest/.

| Date | Patch | File | Reason | Upstream? |
|---|---|---|---|---|
| -- | OAuth system prompt $([char]35)145 fix | packages/pi-ai/dist/providers/anthropic-shared.js | Remove context.systemPrompt append for OAuth tokens | not merged |
| -- | provider label normalize | packages/pi-coding-agent/dist/modes/interactive/components/model-selector.js | anthropic-api -> anthropic | not merged |
| -- | model registry opus-4-7 | packages/pi-ai/dist/models.generated.js + models.js | Add claude-opus-4-7 entry and xhigh capability | upstream in newer versions |

## Re-application procedure

1. Diff baseline vs current: `git diff --no-index baseline-<ver>/ current/`
2. Apply each patch above to the new baseline.
3. Verify via `8sync gsd local fix --dry-run`.
"@
    $parent = Split-Path $Path -Parent
    if (-not (Test-Path $parent)) { $null = New-Item -Path $parent -ItemType Directory -Force }
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $content, $utf8NoBom)
}

function Write-GsdVendorUpgradeDoc {
    param([string]$Path)
    $content = @"
# Upgrade procedure

## Pull latest upstream to inspect

``````
cd .gsd/vendor/gsd-pi/latest
git pull
cd -
8sync gsd local diff                # shows baseline vs latest summary (planned)
``````

## Decide what to merge

1. Read diff summary.
2. For each change in `latest/`:
   - If it fixes something we patched -> we can drop our patch from current/.
   - If it is new feature -> cherry-pick into current/.
   - If it breaks shape we patch -> rewrite patch against new shape.
3. Update `PATCHES.md`.

## Bump baseline

``````
8sync gsd local baseline --from current --tag <new-version>
``````

This snapshots current/ as `baseline-<new-version>/`. Old baseline stays for rollback.

## Rollback

``````
8sync gsd local use baseline --version 2.69.0
``````
"@
    $parent = Split-Path $Path -Parent
    if (-not (Test-Path $parent)) { $null = New-Item -Path $parent -ItemType Directory -Force }
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $content, $utf8NoBom)
}

function Invoke-GsdLocalInit {
    param([switch]$DryRun)

    $projectRoot = Resolve-GsdProjectRoot
    if (-not $projectRoot) {
        Write-Host ''
        Write-Host '  [err]     No .gsd/ project root found from current directory.' -ForegroundColor Red
        Write-Host '  [hint]    Run this from inside a project that already has a .gsd/ folder.' -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    $vendorDir = Join-Path $projectRoot '.gsd\vendor'
    $gsdPiDir = Join-Path $vendorDir 'gsd-pi'
    $agentDir = Join-Path $vendorDir 'agent'
    $baselineDir = Join-Path $gsdPiDir ("baseline-{0}" -f $script:GsdPinnedVersion)
    $latestDir = Join-Path $gsdPiDir 'latest'
    $currentDir = Join-Path $gsdPiDir 'current'

    Write-Host ''
    Write-Host '  [gsd local] init' -ForegroundColor Cyan
    Write-Host ("  project   : {0}" -f $projectRoot) -ForegroundColor DarkGray
    Write-Host ("  vendor    : {0}" -f $vendorDir) -ForegroundColor DarkGray
    Write-Host ''

    $dirs = @($vendorDir, $gsdPiDir, $baselineDir, $latestDir, $currentDir, $agentDir)
    foreach ($d in $dirs) {
        if ($DryRun) {
            Write-Host ("  [dry-run] mkdir {0}" -f $d) -ForegroundColor DarkYellow
        } else {
            if (-not (Test-Path $d)) {
                $null = New-Item -Path $d -ItemType Directory -Force
                Write-Host ("  [ok]      mkdir {0}" -f $d) -ForegroundColor Green
            } else {
                Write-Host ("  [skip]    {0} already exists" -f $d) -ForegroundColor DarkGray
            }
        }
    }

    $readmePath = Join-Path $vendorDir 'README.md'
    $gitignorePath = Join-Path $vendorDir '.gitignore'
    $patchesPath = Join-Path $vendorDir 'PATCHES.md'
    $upgradePath = Join-Path $vendorDir 'UPGRADE.md'

    if ($DryRun) {
        Write-Host ("  [dry-run] write {0}" -f $readmePath) -ForegroundColor DarkYellow
        Write-Host ("  [dry-run] write {0}" -f $gitignorePath) -ForegroundColor DarkYellow
        Write-Host ("  [dry-run] write {0}" -f $patchesPath) -ForegroundColor DarkYellow
        Write-Host ("  [dry-run] write {0}" -f $upgradePath) -ForegroundColor DarkYellow
    } else {
        if (-not (Test-Path $readmePath))   { Write-GsdVendorReadme     -Path $readmePath;   Write-Host ("  [ok]      wrote {0}" -f $readmePath)   -ForegroundColor Green } else { Write-Host ("  [skip]    {0} exists" -f $readmePath) -ForegroundColor DarkGray }
        if (-not (Test-Path $gitignorePath)){ Write-GsdVendorGitignore  -Path $gitignorePath; Write-Host ("  [ok]      wrote {0}" -f $gitignorePath) -ForegroundColor Green } else { Write-Host ("  [skip]    {0} exists" -f $gitignorePath) -ForegroundColor DarkGray }
        if (-not (Test-Path $patchesPath))  { Write-GsdVendorPatchesLog -Path $patchesPath;  Write-Host ("  [ok]      wrote {0}" -f $patchesPath)  -ForegroundColor Green } else { Write-Host ("  [skip]    {0} exists" -f $patchesPath) -ForegroundColor DarkGray }
        if (-not (Test-Path $upgradePath))  { Write-GsdVendorUpgradeDoc -Path $upgradePath;  Write-Host ("  [ok]      wrote {0}" -f $upgradePath)  -ForegroundColor Green } else { Write-Host ("  [skip]    {0} exists" -f $upgradePath) -ForegroundColor DarkGray }
    }

    Write-Host ''
    Write-Host '  Next steps' -ForegroundColor Yellow
    Write-Host ("    8sync gsd local baseline       # seed {0} from global or clone" -f ("baseline-{0}" -f $script:GsdPinnedVersion)) -ForegroundColor DarkGray
    Write-Host '    8sync gsd local add-submodule  # add upstream at latest/' -ForegroundColor DarkGray
    Write-Host '    8sync gsd local use baseline   # seed current/ from baseline' -ForegroundColor DarkGray
    Write-Host '    8sync gsd local fix --stable   # apply patches' -ForegroundColor DarkGray
    Write-Host '    8sync gsd local enter          # activate local runtime in this shell' -ForegroundColor DarkGray
    Write-Host ''
}

function Invoke-GsdLocalBaseline {
    param(
        [switch]$DryRun,
        [string]$Source = 'auto',    # auto | global | clone
        [string]$Version = ''
    )

    $projectRoot = Resolve-GsdProjectRoot
    if (-not $projectRoot) {
        Write-Host '  [err]     No .gsd/ project root found.' -ForegroundColor Red
        return
    }

    if ([string]::IsNullOrWhiteSpace($Version)) { $Version = $script:GsdPinnedVersion }
    $baselineDir = Join-Path $projectRoot (".gsd\vendor\gsd-pi\baseline-{0}" -f $Version)

    Write-Host ''
    Write-Host '  [gsd local] baseline' -ForegroundColor Cyan
    Write-Host ("  target    : {0}" -f $baselineDir) -ForegroundColor DarkGray
    Write-Host ("  source    : {0}" -f $Source) -ForegroundColor DarkGray

    if (Test-Path $baselineDir) {
        $hasFiles = $false
        try {
            $hasFiles = [System.IO.Directory]::EnumerateFileSystemEntries($baselineDir) | Select-Object -First 1
        } catch {}
        if ($hasFiles) {
            Write-Host '  [skip]    baseline already seeded. Remove it first to re-seed.' -ForegroundColor DarkYellow
            Write-Host ''
            return
        }
    }

    $globalSrc = Join-Path $HOME '.gsd\agent\node_modules\gsd-pi'
    $useGlobal = $false
    if ($Source -eq 'auto' -or $Source -eq 'global') {
        if (Test-Path (Join-Path $globalSrc 'package.json')) {
            try {
                $pkg = Get-Content (Join-Path $globalSrc 'package.json') -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
                if ([string]$pkg.version -eq $Version) {
                    $useGlobal = $true
                }
            } catch {}
        }
    }

    if ($useGlobal) {
        Write-Host ("  [plan]    copy from global: {0}" -f $globalSrc) -ForegroundColor DarkGray
        if ($DryRun) {
            Write-Host ("  [dry-run] robocopy {0} {1} /E /XD node_modules" -f $globalSrc, $baselineDir) -ForegroundColor DarkYellow
        } else {
            if (-not (Test-Path $baselineDir)) { $null = New-Item -Path $baselineDir -ItemType Directory -Force }
            try {
                & robocopy $globalSrc $baselineDir /E /XD node_modules /NFL /NDL /NJH /NJS /NP | Out-Null
                Write-Host ("  [ok]      baseline seeded from global ({0})" -f $Version) -ForegroundColor Green
            } catch {
                Write-Host ("  [err]     copy failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
            }
        }
        Write-Host ''
        return
    }

    # fall back to git clone
    Write-Host ("  [plan]    clone {0} --branch v{1} --depth 1 -> {2}" -f $script:GsdUpstreamRepo, $Version, $baselineDir) -ForegroundColor DarkGray
    if ($DryRun) {
        Write-Host ("  [dry-run] git clone {0} --branch v{1} --depth 1 {2}" -f $script:GsdUpstreamRepo, $Version, $baselineDir) -ForegroundColor DarkYellow
    } else {
        try {
            & git clone $script:GsdUpstreamRepo --branch ("v{0}" -f $Version) --depth 1 $baselineDir
            if ($LASTEXITCODE -eq 0) {
                Write-Host ("  [ok]      baseline cloned from upstream ({0})" -f $Version) -ForegroundColor Green
            } else {
                Write-Host ("  [warn]    git clone exited with code {0}" -f $LASTEXITCODE) -ForegroundColor DarkYellow
            }
        } catch {
            Write-Host ("  [err]     git clone failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
        }
    }
    Write-Host ''
}

function Invoke-GsdLocalAddSubmodule {
    param(
        [switch]$DryRun,
        [string]$Ref = 'main'
    )

    $projectRoot = Resolve-GsdProjectRoot
    if (-not $projectRoot) {
        Write-Host '  [err]     No .gsd/ project root found.' -ForegroundColor Red
        return
    }

    $latestPath = '.gsd/vendor/gsd-pi/latest'
    $absLatest = Join-Path $projectRoot ($latestPath -replace '/','\')

    Write-Host ''
    Write-Host '  [gsd local] add-submodule' -ForegroundColor Cyan
    Write-Host ("  project   : {0}" -f $projectRoot) -ForegroundColor DarkGray
    Write-Host ("  upstream  : {0}" -f $script:GsdUpstreamRepo) -ForegroundColor DarkGray
    Write-Host ("  target    : {0}  (ref: {1})" -f $absLatest, $Ref) -ForegroundColor DarkGray

    # Check project is a git repo
    if (-not (Test-Path (Join-Path $projectRoot '.git'))) {
        Write-Host '  [err]     project is not a git repo. Submodule requires git.' -ForegroundColor Red
        return
    }

    # If already a submodule, offer to update instead
    if (Test-Path $absLatest) {
        $hasFiles = $false
        try { $hasFiles = [System.IO.Directory]::EnumerateFileSystemEntries($absLatest) | Select-Object -First 1 } catch {}
        if ($hasFiles) {
            Write-Host '  [skip]    latest/ already populated. Use `git submodule update --remote` to pull.' -ForegroundColor DarkYellow
            Write-Host ''
            return
        }
    }

    if ($DryRun) {
        Write-Host ("  [dry-run] git -C {0} submodule add -b {1} {2} {3}" -f $projectRoot, $Ref, $script:GsdUpstreamRepo, $latestPath) -ForegroundColor DarkYellow
        Write-Host ''
        return
    }

    try {
        Push-Location $projectRoot
        & git submodule add -b $Ref $script:GsdUpstreamRepo $latestPath
        if ($LASTEXITCODE -eq 0) {
            Write-Host '  [ok]      submodule added at latest/' -ForegroundColor Green
            Write-Host '  [hint]    commit .gitmodules and latest/ pointer to lock the ref' -ForegroundColor DarkGray
        } else {
            Write-Host ("  [warn]    git submodule add exited with code {0}" -f $LASTEXITCODE) -ForegroundColor DarkYellow
        }
    } catch {
        Write-Host ("  [err]     submodule add failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
    } finally {
        try { Pop-Location } catch {}
    }
    Write-Host ''
}

function Invoke-GsdLocalUse {
    param(
        [Parameter(Mandatory)] [string]$Target,     # baseline | latest
        [string]$Version = '',
        [switch]$DryRun
    )

    $projectRoot = Resolve-GsdProjectRoot
    if (-not $projectRoot) {
        Write-Host '  [err]     No .gsd/ project root found.' -ForegroundColor Red
        return
    }

    $gsdPiDir = Join-Path $projectRoot '.gsd\vendor\gsd-pi'
    $currentDir = Join-Path $gsdPiDir 'current'

    $sourceDir = ''
    switch ($Target.ToLowerInvariant()) {
        'baseline' {
            if ([string]::IsNullOrWhiteSpace($Version)) { $Version = $script:GsdPinnedVersion }
            $sourceDir = Join-Path $gsdPiDir ("baseline-{0}" -f $Version)
        }
        'latest' {
            $sourceDir = Join-Path $gsdPiDir 'latest'
        }
        default {
            Write-Host ("  [err]     Unknown target '{0}'. Use: baseline | latest" -f $Target) -ForegroundColor Red
            return
        }
    }

    if (-not (Test-Path $sourceDir)) {
        Write-Host ("  [err]     source missing: {0}" -f $sourceDir) -ForegroundColor Red
        Write-Host '  [hint]    run `8sync gsd local baseline` or `add-submodule` first.' -ForegroundColor DarkGray
        return
    }

    Write-Host ''
    Write-Host '  [gsd local] use' -ForegroundColor Cyan
    Write-Host ("  source    : {0}" -f $sourceDir) -ForegroundColor DarkGray
    Write-Host ("  current   : {0}" -f $currentDir) -ForegroundColor DarkGray

    # Remove current/ if present
    if (Test-Path $currentDir) {
        if ($DryRun) {
            Write-Host ("  [dry-run] remove existing current/") -ForegroundColor DarkYellow
        } else {
            try {
                Remove-Item -LiteralPath $currentDir -Recurse -Force -ErrorAction Stop
            } catch {
                Write-Host ("  [err]     could not clear current/: {0}" -f $_.Exception.Message) -ForegroundColor Red
                return
            }
        }
    }

    if ($DryRun) {
        Write-Host ("  [dry-run] copy {0} -> {1} (exclude node_modules, .git)" -f $sourceDir, $currentDir) -ForegroundColor DarkYellow
        Write-Host ''
        return
    }

    if (-not (Test-Path $currentDir)) { $null = New-Item -Path $currentDir -ItemType Directory -Force }
    try {
        & robocopy $sourceDir $currentDir /E /XD node_modules .git /NFL /NDL /NJH /NJS /NP | Out-Null
        Write-Host ("  [ok]      current/ seeded from {0}" -f $Target) -ForegroundColor Green
    } catch {
        Write-Host ("  [err]     copy failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
        return
    }

    Write-Host '  [next]    8sync gsd local fix --stable' -ForegroundColor DarkGray
    Write-Host ''
}

function Invoke-GsdLocalEnter {
    param([switch]$DryRun)

    $projectRoot = Resolve-GsdProjectRoot
    if (-not $projectRoot) {
        Write-Host '  [err]     No .gsd/ project root found.' -ForegroundColor Red
        return
    }

    $localHome = Join-Path $projectRoot '.gsd\vendor'
    $localAgent = Join-Path $localHome 'agent'
    $currentLoader = Join-Path $projectRoot '.gsd\vendor\gsd-pi\current\dist\loader.js'

    if (-not (Test-Path $localAgent)) {
        Write-Host ("  [err]     local agent dir missing: {0}" -f $localAgent) -ForegroundColor Red
        Write-Host '  [hint]    run `8sync gsd local init` first.' -ForegroundColor DarkGray
        return
    }
    if (-not (Test-Path $currentLoader)) {
        Write-Host ("  [err]     current loader missing: {0}" -f $currentLoader) -ForegroundColor Red
        Write-Host '  [hint]    run `8sync gsd local use baseline` then `8sync gsd local install`.' -ForegroundColor DarkGray
        return
    }

    Write-Host ''
    Write-Host '  [gsd local] enter' -ForegroundColor Cyan
    Write-Host ("  GSD_HOME             = {0}" -f $localHome) -ForegroundColor DarkGray
    Write-Host ("  GSD_CODING_AGENT_DIR = {0}" -f $localAgent) -ForegroundColor DarkGray
    Write-Host ("  gsd loader           = {0}" -f $currentLoader) -ForegroundColor DarkGray

    if ($DryRun) {
        Write-Host '  [dry-run] would set env vars and override gsd function' -ForegroundColor DarkYellow
        Write-Host ''
        return
    }

    $env:GSD_HOME = $localHome
    $env:GSD_CODING_AGENT_DIR = $localAgent
    $env:GSD_LOCAL_PROJECT_ROOT = $projectRoot
    $env:GSD_LOCAL_LOADER = $currentLoader

    # Override gsd command in this shell to run local loader
    $script:GsdLocalActive = $true
    Set-Item -Path function:global:gsd -Value {
        if ([string]::IsNullOrWhiteSpace($env:GSD_LOCAL_LOADER)) {
            Write-Host 'local gsd not active. Run `8sync gsd local enter` first.' -ForegroundColor DarkYellow
            return
        }
        & node $env:GSD_LOCAL_LOADER @args
    }.GetNewClosure() -Force

    Write-Host '  [ok]      local scope activated. `gsd ...` now runs from current/.' -ForegroundColor Green
    Write-Host '  [note]    `8sync gsd local leave` or close shell to revert to global.' -ForegroundColor DarkGray
    Write-Host ''
}

function Invoke-GsdLocalLeave {
    Write-Host ''
    Write-Host '  [gsd local] leave' -ForegroundColor Cyan
    Remove-Item Env:GSD_HOME -ErrorAction SilentlyContinue
    Remove-Item Env:GSD_CODING_AGENT_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:GSD_LOCAL_PROJECT_ROOT -ErrorAction SilentlyContinue
    Remove-Item Env:GSD_LOCAL_LOADER -ErrorAction SilentlyContinue
    if (Test-Path function:global:gsd) { Remove-Item function:global:gsd -ErrorAction SilentlyContinue }
    $script:GsdLocalActive = $false
    Write-Host '  [ok]      local scope cleared. `gsd` uses global shim again.' -ForegroundColor Green
    Write-Host ''
}

function Invoke-GsdLocalFix {
    param(
        [switch]$DryRun,
        [switch]$Stable
    )

    $projectRoot = Resolve-GsdProjectRoot
    if (-not $projectRoot) {
        Write-Host '  [err]     No .gsd/ project root found.' -ForegroundColor Red
        return
    }

    $currentDir = Join-Path $projectRoot '.gsd\vendor\gsd-pi\current'
    $localAgent = Join-Path $projectRoot '.gsd\vendor\agent'
    if (-not (Test-Path $currentDir)) {
        Write-Host '  [err]     current/ missing. Run `8sync gsd local use baseline` first.' -ForegroundColor Red
        return
    }
    if (-not (Test-Path $localAgent)) {
        Write-Host '  [err]     local agent/ missing. Run `8sync gsd local init` first.' -ForegroundColor Red
        return
    }

    Write-Host ''
    Write-Host '  [gsd local] fix' -ForegroundColor Cyan
    Write-Host ("  scope     : {0}" -f $currentDir) -ForegroundColor DarkGray
    if ($Stable) { Write-Host '  [stable] applying stable patch profile' -ForegroundColor Cyan }

    # --- 1) Bridge local agent node_modules -> current/node_modules -------
    $currentNm = Join-Path $currentDir 'node_modules'
    if (-not (Test-Path $currentNm)) {
        Write-Host '  [warn]    current/node_modules missing. Run `npm install` inside current/ once.' -ForegroundColor DarkYellow
    } else {
        $agentNm = Join-Path $localAgent 'node_modules'
        $bridgeReady = $false
        if (Test-Path $agentNm) {
            try {
                $item = Get-Item -LiteralPath $agentNm -Force
                if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -and $item.Target -contains $currentNm) {
                    $bridgeReady = $true
                }
            } catch {}
        }
        if ($bridgeReady) {
            Write-Host '  [ok]      local agent/node_modules bridge already points at current/' -ForegroundColor Green
        } elseif ($DryRun) {
            Write-Host ("  [dry-run] junction {0} -> {1}" -f $agentNm, $currentNm) -ForegroundColor DarkYellow
        } else {
            try {
                if (Test-Path $agentNm) { Remove-Item -LiteralPath $agentNm -Recurse -Force -ErrorAction Stop }
                $null = New-Item -Path $agentNm -ItemType Junction -Target $currentNm -Force
                Write-Host '  [ok]      bridged local agent/node_modules -> current/node_modules' -ForegroundColor Green
            } catch {
                Write-Host ("  [warn]    bridge failed: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
            }
        }
    }

    # --- 2) Anthropic OAuth system prompt fix in current/ -----------------
    $anthropicShared = Join-Path $currentDir 'packages\pi-ai\dist\providers\anthropic-shared.js'
    if (Test-Path $anthropicShared) {
        try {
            $raw = (Get-Content $anthropicShared -Raw -Encoding UTF8) -replace "`r`n", "`n"
            if ($raw -match "params\.system = \[" -and $raw -notmatch "params\.system\.push\(") {
                Write-Host '  [ok]      Anthropic OAuth system prompt fix already applied in current/' -ForegroundColor Green
            } else {
                $oldBlock = @"
    if (isOAuthToken) {
        params.system = [
            {
                type: "text",
                text: "You are Claude Code, Anthropic's official CLI for Claude.",
                ...(cacheControl ? { cache_control: cacheControl } : {}),
            },
        ];
        if (context.systemPrompt) {
            params.system.push({
                type: "text",
                text: sanitizeSurrogates(context.systemPrompt),
                ...(cacheControl ? { cache_control: cacheControl } : {}),
            });
        }
    }
"@ -replace "`r`n", "`n"
                $newBlock = @"
    if (isOAuthToken) {
        params.system = [
            {
                type: "text",
                text: "You are Claude Code, Anthropic's official CLI for Claude.",
                ...(cacheControl ? { cache_control: cacheControl } : {}),
            },
        ];
    }
"@ -replace "`r`n", "`n"

                if ($raw.Contains($oldBlock)) {
                    if ($DryRun) {
                        Write-Host ("  [dry-run] patch {0}" -f $anthropicShared) -ForegroundColor DarkYellow
                    } else {
                        $updated = $raw.Replace($oldBlock, $newBlock)
                        [System.IO.File]::WriteAllText($anthropicShared, $updated, [System.Text.UTF8Encoding]::new($false))
                        Write-Host '  [ok]      patched Anthropic OAuth system prompt in current/' -ForegroundColor Green
                    }
                } else {
                    Write-Host '  [warn]    anthropic-shared.js has unexpected shape; skipped OAuth patch' -ForegroundColor DarkYellow
                }
            }
        } catch {
            Write-Host ("  [warn]    OAuth patch failed: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
        }
    } else {
        Write-Host '  [warn]    anthropic-shared.js not found in current/' -ForegroundColor DarkYellow
    }

    # --- 3) Provider label normalize --------------------------------------
    $labelPath = Join-Path $currentDir 'packages\pi-coding-agent\dist\modes\interactive\components\model-selector.js'
    if (Test-Path $labelPath) {
        try {
            $raw = Get-Content $labelPath -Raw -Encoding UTF8
            if ($raw -match 'anthropic:\s*"anthropic"') {
                Write-Host '  [ok]      provider label already normalized in current/' -ForegroundColor Green
            } elseif ($raw -match 'anthropic:\s*"anthropic-api"') {
                if ($DryRun) {
                    Write-Host ("  [dry-run] patch label {0}" -f $labelPath) -ForegroundColor DarkYellow
                } else {
                    $updated = $raw -replace 'anthropic:\s*"anthropic-api"', 'anthropic: "anthropic"'
                    [System.IO.File]::WriteAllText($labelPath, $updated, [System.Text.UTF8Encoding]::new($false))
                    Write-Host '  [ok]      normalized anthropic label in current/' -ForegroundColor Green
                }
            } else {
                Write-Host '  [ok]      label map uses dynamic provider; no patch needed' -ForegroundColor Green
            }
        } catch {
            Write-Host ("  [warn]    label patch failed: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
        }
    }

    Write-Host '  [ok]      local fix finished' -ForegroundColor Green
    Write-Host ''
}

function Invoke-GsdLocalInstall {
    param([switch]$DryRun)

    $projectRoot = Resolve-GsdProjectRoot
    if (-not $projectRoot) {
        Write-Host '  [err]     No .gsd/ project root found.' -ForegroundColor Red
        return
    }

    $currentDir = Join-Path $projectRoot '.gsd\vendor\gsd-pi\current'
    if (-not (Test-Path (Join-Path $currentDir 'package.json'))) {
        Write-Host '  [err]     current/package.json missing. Run `8sync gsd local use baseline` first.' -ForegroundColor Red
        return
    }

    Write-Host ''
    Write-Host '  [gsd local] install (runs npm install inside current/)' -ForegroundColor Cyan
    Write-Host ("  cwd       : {0}" -f $currentDir) -ForegroundColor DarkGray

    if (-not (Test-CommandExists 'npm')) {
        Write-Host '  [err]     npm not found. Install Node.js first.' -ForegroundColor Red
        return
    }

    if ($DryRun) {
        Write-Host '  [dry-run] npm install (no --global)' -ForegroundColor DarkYellow
        return
    }

    try {
        Push-Location $currentDir
        & npm install
        if ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) {
            Write-Host '  [ok]      npm install completed in current/' -ForegroundColor Green
        } else {
            Write-Host ("  [warn]    npm install exited with code {0}" -f $LASTEXITCODE) -ForegroundColor DarkYellow
        }
    } catch {
        Write-Host ("  [err]     npm install failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
    } finally {
        try { Pop-Location } catch {}
    }
    Write-Host ''
}

function Get-GsdWezTermRootLocal {
    if (-not [string]::IsNullOrWhiteSpace($script:ModulesDir)) {
        return [System.IO.Path]::GetFullPath((Join-Path $script:ModulesDir '..'))
    }
    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
}

function Ensure-GsdSandboxProject {
    param(
        [Parameter(Mandatory)] [string]$Name,
        [switch]$DryRun
    )
    $wez = Get-GsdWezTermRootLocal
    $sandbox = Join-Path $wez ("test\{0}" -f $Name)
    $gsdDir = Join-Path $sandbox '.gsd'
    $projectMd = Join-Path $gsdDir 'PROJECT.md'

    if ($DryRun) {
        Write-Host ("  [dry-run] ensure sandbox project: {0}" -f $sandbox) -ForegroundColor DarkYellow
        return $sandbox
    }

    if (-not (Test-Path $sandbox)) {
        $null = New-Item -Path $sandbox -ItemType Directory -Force
        Write-Host ("  [ok]      created sandbox folder {0}" -f $sandbox) -ForegroundColor Green
    }
    if (-not (Test-Path $gsdDir)) {
        $null = New-Item -Path $gsdDir -ItemType Directory -Force
    }
    if (-not (Test-Path $projectMd)) {
        "# gsd {0} sandbox`n`nCreated by ``8sync gsd local setup --version {0}``." -f $Name |
            Set-Content -Path $projectMd -Encoding UTF8
    }

    # Git init so submodule works (safe idempotent)
    if (-not (Test-Path (Join-Path $sandbox '.git'))) {
        try {
            Push-Location $sandbox
            & git init -q 2>&1 | Out-Null
            Write-Host ("  [ok]      git init in {0}" -f $sandbox) -ForegroundColor Green
        } catch {
            Write-Host ("  [warn]    git init failed: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
        } finally {
            try { Pop-Location } catch {}
        }
    }

    return $sandbox
}

function Invoke-GsdLocalSetup {
    param(
        [string]$Version = 'baseline',    # 'baseline' | 'latest' | '2.69.0' | '2.76.0' ...
        [string]$ProjectPath = '',         # explicit project path (skips cwd detect + sandbox)
        [switch]$DryRun,
        [switch]$SkipSubmodule,
        [switch]$SkipEnter,
        [switch]$Here                      # force use cwd even without .gsd/
    )

    $target = 'baseline'
    $explicitVersion = ''
    $lower = $Version.ToLowerInvariant()
    if ($lower -eq 'latest') {
        $target = 'latest'
    } elseif ($lower -eq 'baseline') {
        $target = 'baseline'
        $explicitVersion = $script:GsdPinnedVersion
    } elseif ($Version -match '^\d+\.\d+\.\d+') {
        $target = 'baseline'
        $explicitVersion = $Version
    } else {
        Write-Host ("  [err]     Unknown --version '{0}'. Use: latest | baseline | 2.69.0" -f $Version) -ForegroundColor Red
        return
    }

    # Resolve project root:
    # 1. --project <path>           explicit
    # 2. --here                     force cwd, create .gsd/ if missing
    # 3. cwd inside project         use it
    # 4. default                    auto-create wezterm/test/<target>/ sandbox
    $projectRoot = $null
    $sandboxCreated = $false

    if (-not [string]::IsNullOrWhiteSpace($ProjectPath)) {
        if (-not (Test-Path $ProjectPath)) {
            if ($DryRun) {
                Write-Host ("  [dry-run] mkdir {0}" -f $ProjectPath) -ForegroundColor DarkYellow
            } else {
                $null = New-Item -Path $ProjectPath -ItemType Directory -Force
            }
        }
        $projectRoot = [System.IO.Path]::GetFullPath($ProjectPath)
        # Ensure .gsd/ exists so this dir qualifies as a project
        $gsdDir = Join-Path $projectRoot '.gsd'
        if (-not (Test-Path $gsdDir) -and -not $DryRun) {
            $null = New-Item -Path $gsdDir -ItemType Directory -Force
            "# project created by 8sync gsd local setup" | Set-Content -Path (Join-Path $gsdDir 'PROJECT.md') -Encoding UTF8
        }
    } elseif ($Here) {
        $projectRoot = (Get-Location).Path
        $gsdDir = Join-Path $projectRoot '.gsd'
        if (-not (Test-Path $gsdDir) -and -not $DryRun) {
            $null = New-Item -Path $gsdDir -ItemType Directory -Force
            "# project created by 8sync gsd local setup --here" | Set-Content -Path (Join-Path $gsdDir 'PROJECT.md') -Encoding UTF8
        }
    } else {
        $detected = Resolve-GsdProjectRoot
        # Refuse if detected root is:
        #   - user $HOME (global ~/.gsd/ would pollute home)
        #   - wezterm config repo itself (we want sandbox under test/, not root)
        $homeNorm = [System.IO.Path]::GetFullPath($HOME).TrimEnd('\','/').ToLowerInvariant()
        $wezRootNorm = [System.IO.Path]::GetFullPath((Get-GsdWezTermRootLocal)).TrimEnd('\','/').ToLowerInvariant()
        $detectedNorm = if ($detected) { [System.IO.Path]::GetFullPath($detected).TrimEnd('\','/').ToLowerInvariant() } else { '' }
        $isHomeDetect = $detectedNorm -and ($detectedNorm -eq $homeNorm)
        $isWezDetect  = $detectedNorm -and ($detectedNorm -eq $wezRootNorm)

        if ($detected -and -not $isHomeDetect -and -not $isWezDetect) {
            $projectRoot = $detected
        } else {
            # Auto-create sandbox under wezterm/test/<target>/
            $sandboxName = $target
            Write-Host ''
            if ($isHomeDetect) {
                Write-Host '  [info]    cwd resolved to $HOME (global ~/.gsd/). Refusing to use as project.' -ForegroundColor DarkYellow
            } elseif ($isWezDetect) {
                Write-Host '  [info]    cwd is the wezterm config repo root. Not a valid sandbox target.' -ForegroundColor DarkYellow
            } else {
                Write-Host '  [info]    cwd is not a gsd project.' -ForegroundColor DarkYellow
            }
            Write-Host ("  [info]    auto-creating sandbox: wezterm/test/{0}/" -f $sandboxName) -ForegroundColor DarkYellow
            Write-Host '  [hint]    pass --here to use cwd, or --project <path> for explicit path.' -ForegroundColor DarkGray
            $projectRoot = Ensure-GsdSandboxProject -Name $sandboxName -DryRun:$DryRun
            $sandboxCreated = $true
        }
    }

    if (-not $projectRoot) {
        Write-Host '  [err]     could not resolve project root.' -ForegroundColor Red
        return
    }

    Write-Host ''
    Write-Host '  ==================================================================' -ForegroundColor Cyan
    Write-Host ('  GSD LOCAL SETUP   version={0}   project={1}' -f $Version, (Split-Path $projectRoot -Leaf)) -ForegroundColor Cyan
    Write-Host ('  path: {0}' -f $projectRoot) -ForegroundColor DarkGray
    if ($sandboxCreated) {
        Write-Host '  [sandbox] created under wezterm/test/ — gitignored, does not pollute wezterm repo' -ForegroundColor DarkGray
    }
    Write-Host '  ==================================================================' -ForegroundColor Cyan
    Write-Host ''

    # Save original cwd, push into project so Resolve-GsdProjectRoot returns it
    $origCwd = (Get-Location).Path
    try {
        if (-not $DryRun) { Push-Location $projectRoot }

    # --- Step 1: init layout ---------------------------------------------
    Write-Host '  [1/6] init layout' -ForegroundColor Yellow
    Invoke-GsdLocalInit -DryRun:$DryRun

    # --- Step 2: seed baseline (always, even for latest -- used as fallback) --
    Write-Host '  [2/6] seed baseline' -ForegroundColor Yellow
    $baselineVer = if ($explicitVersion) { $explicitVersion } else { $script:GsdPinnedVersion }
    $baselineDir = Join-Path $projectRoot (".gsd\vendor\gsd-pi\baseline-{0}" -f $baselineVer)
    if (Test-Path $baselineDir) {
        $hasFiles = $false
        try { $hasFiles = [System.IO.Directory]::EnumerateFileSystemEntries($baselineDir) | Select-Object -First 1 } catch {}
        if ($hasFiles) {
            Write-Host ("  [skip]    baseline-{0} already seeded" -f $baselineVer) -ForegroundColor DarkGray
        } else {
            Invoke-GsdLocalBaseline -DryRun:$DryRun -Source 'auto' -Version $baselineVer
        }
    } else {
        Invoke-GsdLocalBaseline -DryRun:$DryRun -Source 'auto' -Version $baselineVer
    }

    # --- Step 3: submodule latest ----------------------------------------
    if ($SkipSubmodule) {
        Write-Host '  [3/6] submodule skipped (--skip-submodule)' -ForegroundColor DarkGray
    } else {
        Write-Host '  [3/6] add submodule latest' -ForegroundColor Yellow
        $latestDir = Join-Path $projectRoot '.gsd\vendor\gsd-pi\latest'
        $latestPopulated = $false
        if (Test-Path $latestDir) {
            try { $latestPopulated = [System.IO.Directory]::EnumerateFileSystemEntries($latestDir) | Select-Object -First 1 } catch {}
        }
        if ($latestPopulated) {
            Write-Host '  [skip]    latest/ already populated' -ForegroundColor DarkGray
        } else {
            # Remove empty dir if init created it, so git submodule add can work
            if (Test-Path $latestDir) {
                try { Remove-Item -LiteralPath $latestDir -Force -ErrorAction Stop } catch {}
            }
            Invoke-GsdLocalAddSubmodule -DryRun:$DryRun -Ref 'main'
        }
    }

    # --- Step 4: use <target> --------------------------------------------
    Write-Host ('  [4/6] use {0}' -f $target) -ForegroundColor Yellow
    Invoke-GsdLocalUse -Target $target -Version $explicitVersion -DryRun:$DryRun

    # --- Step 5: install + build (if latest) + anthropic patch + fix ----
    Write-Host '  [5/6] install + patches + fix' -ForegroundColor Yellow
    Invoke-GsdLocalInstall -DryRun:$DryRun

    # If using latest, restore Anthropic OAuth (removed upstream) + build
    if ($target -eq 'latest') {
        Write-Host '  [latest]  restoring Anthropic OAuth (upstream removed for TOS compliance)' -ForegroundColor Cyan
        Invoke-GsdLocalApplyAnthropicPatch -DryRun:$DryRun
        Invoke-GsdLocalBuild -DryRun:$DryRun
    }

    Invoke-GsdLocalFix -DryRun:$DryRun -Stable

    # --- Step 6: enter (unless skipped) ----------------------------------
    if ($SkipEnter) {
        Write-Host '  [6/6] enter skipped (--skip-enter)' -ForegroundColor DarkGray
    } else {
        Write-Host '  [6/6] enter local scope' -ForegroundColor Yellow
        Invoke-GsdLocalEnter -DryRun:$DryRun
    }

    Write-Host ''
    Write-Host '  ==================================================================' -ForegroundColor Green
    Write-Host '  SETUP COMPLETE' -ForegroundColor Green
    Write-Host '  ==================================================================' -ForegroundColor Green
    Write-Host ''
    Write-Host ("  Active project : {0}" -f $projectRoot) -ForegroundColor White
    Write-Host ("  Active runtime : {0}" -f $target) -ForegroundColor White
    Write-Host ''
    if (-not $SkipEnter) {
        Write-Host '  Next: gsd                                 # start using local runtime' -ForegroundColor DarkGray
        Write-Host '        /login anthropic                    # login in interactive' -ForegroundColor DarkGray
    } else {
        Write-Host '  Next: 8sync gsd local enter               # activate local scope first' -ForegroundColor DarkGray
        Write-Host '        gsd                                 # then start' -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Host '  Check active version later: gsd --version   or   8sync gsd local' -ForegroundColor DarkGray
    Write-Host '  Switch version:             8sync gsd local use baseline|latest' -ForegroundColor DarkGray
    Write-Host '  Exit local scope:           8sync gsd local leave' -ForegroundColor DarkGray
    Write-Host ''
    } finally {
        if (-not $DryRun -and $SkipEnter) {
            # If we entered the project via Push-Location and user did NOT enter local scope,
            # restore cwd. If user entered local scope, stay in project dir (better UX).
            try { Pop-Location -ErrorAction SilentlyContinue } catch {}
        }
    }
}

function Show-GsdLocalHelp {
    Write-Host ''
    Write-HintSection 'GSD LOCAL -- project-scoped gsd-pi vendoring (never touches global)'
    Write-Host ''
    Write-Host '  Layout' -ForegroundColor Cyan
    Write-Host '    <project>/.gsd/vendor/gsd-pi/baseline-<ver>/   # immutable snapshot' -ForegroundColor DarkGray
    Write-Host '    <project>/.gsd/vendor/gsd-pi/latest/           # submodule, read-only' -ForegroundColor DarkGray
    Write-Host '    <project>/.gsd/vendor/gsd-pi/current/          # runtime + patches' -ForegroundColor DarkGray
    Write-Host '    <project>/.gsd/vendor/agent/                   # local ~/.gsd/agent equivalent' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  One-shot (recommended)' -ForegroundColor Yellow
    Write-Host '    8sync gsd local setup                  Baseline. Auto-creates wezterm/test/baseline/ if cwd is not a project' -ForegroundColor White
    Write-Host '    8sync gsd local setup --version latest Latest upstream. Auto-creates wezterm/test/latest/' -ForegroundColor White
    Write-Host '    8sync gsd local setup --version 2.69.0 Specific baseline version' -ForegroundColor White
    Write-Host '    8sync gsd local setup --here           Use cwd as project (creates .gsd/ if missing)' -ForegroundColor White
    Write-Host '    8sync gsd local setup --project <path> Use explicit path as project root' -ForegroundColor White
    Write-Host ''
    Write-Host '  Resolution order for project root' -ForegroundColor Cyan
    Write-Host '    1. --project <path>                         explicit' -ForegroundColor DarkGray
    Write-Host '    2. --here                                    force cwd (creates .gsd/ if missing)' -ForegroundColor DarkGray
    Write-Host '    3. cwd has .gsd/ or ancestor has .gsd/       use that project' -ForegroundColor DarkGray
    Write-Host '    4. default                                    auto-create wezterm/test/<latest|baseline>/' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  Then in that project' -ForegroundColor Yellow
    Write-Host '    gsd                              Start local gsd (already in scope after setup)' -ForegroundColor DarkGray
    Write-Host '    /login anthropic                 Inside gsd interactive' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  Switch runtime version' -ForegroundColor Cyan
    Write-Host '    8sync gsd local use baseline     Switch current/ -> baseline + install + fix' -ForegroundColor White
    Write-Host '    8sync gsd local use latest       Switch current/ -> latest + install + fix' -ForegroundColor White
    Write-Host ''
    Write-Host '  Individual steps (advanced)' -ForegroundColor Cyan
    Write-Host '    8sync gsd local                  Show layout status (which version active)' -ForegroundColor White
    Write-Host '    8sync gsd local init             Scaffold .gsd/vendor/ layout + docs' -ForegroundColor White
    Write-Host '    8sync gsd local baseline         Seed baseline from global or clone' -ForegroundColor White
    Write-Host '    8sync gsd local add-submodule    Add upstream gsd-2 at latest/' -ForegroundColor White
    Write-Host '    8sync gsd local install          Run npm install inside current/' -ForegroundColor White
    Write-Host '    8sync gsd local build            Run npm run build:core inside current/' -ForegroundColor White
    Write-Host '    8sync gsd local apply-anthropic-patch  Restore Anthropic OAuth (needed for latest)' -ForegroundColor White
    Write-Host '    8sync gsd local fix [--stable]   Apply stable patches to current/' -ForegroundColor White
    Write-Host '    8sync gsd local enter            Activate local runtime in this shell' -ForegroundColor White
    Write-Host '    8sync gsd local leave            Revert to global runtime' -ForegroundColor White
    Write-Host ''
    Write-Host '  Safety' -ForegroundColor Yellow
    Write-Host '    - no npm -g, no bun -g, no scoop changes' -ForegroundColor DarkGray
    Write-Host '    - global ~/.gsd/agent/ stays untouched' -ForegroundColor DarkGray
    Write-Host '    - leave the shell or run `local leave` to revert' -ForegroundColor DarkGray
    Write-Host ''
}

function Invoke-GsdLocalCommand {
    param([string[]]$Rest)

    $dryRun = $Rest -contains '--dry-run'

    $sub = if ($Rest.Count -gt 0 -and $Rest[0] -notlike '--*') { $Rest[0].ToLowerInvariant() } else { '' }

    switch ($sub) {
        ''               { Show-GsdLocalStatus }
        'status'         { Show-GsdLocalStatus }
        'help'           { Show-GsdLocalHelp }
        'init'           { Invoke-GsdLocalInit -DryRun:$dryRun }
        'baseline'       {
            $versionArg = ''
            $versionIdx = [Array]::IndexOf($Rest, '--version')
            if ($versionIdx -ge 0 -and $versionIdx + 1 -lt $Rest.Count) { $versionArg = $Rest[$versionIdx + 1] }
            $sourceArg = 'auto'
            $sourceIdx = [Array]::IndexOf($Rest, '--from')
            if ($sourceIdx -ge 0 -and $sourceIdx + 1 -lt $Rest.Count) { $sourceArg = $Rest[$sourceIdx + 1] }
            Invoke-GsdLocalBaseline -DryRun:$dryRun -Source $sourceArg -Version $versionArg
        }
        'add-submodule'  {
            $refArg = 'main'
            $refIdx = [Array]::IndexOf($Rest, '--ref')
            if ($refIdx -ge 0 -and $refIdx + 1 -lt $Rest.Count) { $refArg = $Rest[$refIdx + 1] }
            Invoke-GsdLocalAddSubmodule -DryRun:$dryRun -Ref $refArg
        }
        'setup'          {
            $versionArg = 'baseline'
            $versionIdx = [Array]::IndexOf($Rest, '--version')
            if ($versionIdx -ge 0 -and $versionIdx + 1 -lt $Rest.Count) { $versionArg = $Rest[$versionIdx + 1] }
            $projectPathArg = ''
            $projIdx = [Array]::IndexOf($Rest, '--project')
            if ($projIdx -ge 0 -and $projIdx + 1 -lt $Rest.Count) { $projectPathArg = $Rest[$projIdx + 1] }
            $here = $Rest -contains '--here'
            $skipSub = $Rest -contains '--skip-submodule'
            $skipEnter = $Rest -contains '--skip-enter'
            Invoke-GsdLocalSetup -Version $versionArg -ProjectPath $projectPathArg -Here:$here -DryRun:$dryRun -SkipSubmodule:$skipSub -SkipEnter:$skipEnter
        }
        'use'            {
            $target = if ($Rest.Count -gt 1 -and $Rest[1] -notlike '--*') { $Rest[1] } else { 'baseline' }
            $versionArg = ''
            $versionIdx = [Array]::IndexOf($Rest, '--version')
            if ($versionIdx -ge 0 -and $versionIdx + 1 -lt $Rest.Count) { $versionArg = $Rest[$versionIdx + 1] }
            $noAuto = $Rest -contains '--no-auto'
            Invoke-GsdLocalUse -Target $target -Version $versionArg -DryRun:$dryRun
            if (-not $noAuto -and -not $dryRun) {
                Invoke-GsdLocalInstall -DryRun:$dryRun
                Invoke-GsdLocalFix -DryRun:$dryRun -Stable
                Write-Host ''
                Write-Host ('  [done]    switched to {0}. Run `gsd` to start.' -f $target) -ForegroundColor Green
                Write-Host ''
            }
        }
        'install'                { Invoke-GsdLocalInstall -DryRun:$dryRun }
        'build'                  { Invoke-GsdLocalBuild -DryRun:$dryRun }
        'apply-anthropic-patch'  { Invoke-GsdLocalApplyAnthropicPatch -DryRun:$dryRun }
        'fix'            {
            $stable = $Rest -contains '--stable'
            Invoke-GsdLocalFix -DryRun:$dryRun -Stable:$stable
        }
        'enter'          { Invoke-GsdLocalEnter -DryRun:$dryRun }
        'leave'          { Invoke-GsdLocalLeave }
        default          {
            Write-Host ("  [err]     unknown subcommand '{0}'" -f $sub) -ForegroundColor Red
            Show-GsdLocalHelp
        }
    }
}
