# ─────────────────────────────────────────────────────────────────────────────
# 8sync opencode — Export OpenCode bundle for cross-machine setup
# ─────────────────────────────────────────────────────────────────────────────

function Resolve-OpencodeBundlePath {
    param([string]$BundleDir = 'oc-bundle')

    if ([string]::IsNullOrWhiteSpace($BundleDir)) {
        $BundleDir = 'oc-bundle'
    }

    if ([System.IO.Path]::IsPathRooted($BundleDir)) {
        return $BundleDir
    }

    # Smart auto-detection: search known locations in priority order
    $candidates = @(
        Join-Path $PWD.Path $BundleDir                                              # 1. Current dir
        Join-Path $HOME '.config\wezterm\oc-bundle'                                # 2. Wezterm config (canonical)
        Join-Path $HOME $BundleDir                                                  # 3. HOME root
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    # Default to $PWD (will produce a helpful "not found" error downstream)
    return Join-Path $PWD.Path $BundleDir
}

function Convert-ToRelativePath {
    param(
        [Parameter(Mandatory)] [string]$BasePath,
        [Parameter(Mandatory)] [string]$FullPath
    )

    $baseWithSlash = if ($BasePath.EndsWith([System.IO.Path]::DirectorySeparatorChar)) { $BasePath } else { $BasePath + [System.IO.Path]::DirectorySeparatorChar }
    if ($FullPath.StartsWith($baseWithSlash, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $FullPath.Substring($baseWithSlash.Length)
    }

    return $FullPath
}

function Test-OpencodeExportExcluded {
    param([Parameter(Mandatory)] [string]$RelativePath)

    $normalized = $RelativePath -replace '/', '\\'

    if ($normalized -match '(^|\\)(lib|node_modules)(\\|$)') {
        return $true
    }

    $ext = [System.IO.Path]::GetExtension($normalized)
    return ($ext -ieq '.ps1' -or $ext -ieq '.py')
}

function Show-OpencodeHelp {
    Write-Host ''
    Write-HintSection 'OPENCODE -- Export portable setup bundle'
    Write-HintRow '8sync opencode'                    'Export ~/.config/opencode to ./oc-bundle (exclude lib, node_modules, *.ps1, *.py)'
    Write-HintRow '8sync opencode export [folder]'    'Export to custom folder (default: oc-bundle)'
    Write-HintRow '8sync opencode apply [folder]'     'Copy bundle -> ~/.config/opencode and run npm i'
    Write-HintRow '8sync opencode reinstall [folder]' 'Force reinstall (wipe ~/.config/opencode, then apply + npm i)'
    Write-HintRow '8sync opencode --dry-run'          'Preview files that would be exported/applied'
    Write-HintRow '8sync opencode apply --force'      'Force overwrite target folder before copy + npm i'
    Write-HintRow '8sync opencode status'             'Show source/bundle/npm readiness'
    Write-HintRow '8sync opencode help'               'Show this help'
    Write-Host ''
    Write-Host '  Target machine setup:' -ForegroundColor DarkGray
    Write-Host '    1) Copy/extract bundle folder (default: oc-bundle) into machine' -ForegroundColor DarkGray
    Write-Host '    2) Run: 8sync opencode reinstall [folder]   # force overwrite + npm i' -ForegroundColor DarkGray
    Write-Host '    3) If npm missing: scoop install nvm; nvm install <version>; nvm use <version>; npm i' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  Note: Do NOT push bundle to public repo with secrets in opencode.json.' -ForegroundColor DarkYellow
    Write-Host ''
}

function Invoke-OpencodeApply {
    param(
        [string]$BundleDir = 'oc-bundle',
        [switch]$DryRun,
        [switch]$Force
    )

    $bundlePath = Resolve-OpencodeBundlePath -BundleDir $BundleDir
    $autoDetected = ($BundleDir -eq 'oc-bundle') -and ($bundlePath -ne (Join-Path $PWD.Path $BundleDir))
    if (-not (Test-Path $bundlePath)) {
        Write-Host ("  [opencode] Bundle folder not found: {0}" -f $bundlePath) -ForegroundColor Red
        Write-Host '  [opencode] Searched: $PWD/oc-bundle, ~/.config/wezterm/oc-bundle, ~/oc-bundle' -ForegroundColor DarkGray
        return
    }

    $targetPath = Join-Path $HOME '.config\opencode'
    $bundleFiles = Get-ChildItem -Path $bundlePath -Recurse -Force -File -ErrorAction SilentlyContinue
    if (-not $bundleFiles -or $bundleFiles.Count -eq 0) {
        Write-Host '  [opencode] Bundle has no files to apply.' -ForegroundColor DarkYellow
        return
    }

    $actions = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($file in $bundleFiles) {
        $rel = Convert-ToRelativePath -BasePath $bundlePath -FullPath $file.FullName
        $dest = Join-Path $targetPath $rel
        $destDir = Split-Path $dest -Parent
        $actions.Add([pscustomobject]@{
            Rel     = $rel
            Src     = $file.FullName
            Dest    = $dest
            DestDir = $destDir
        })
    }

    Write-Host ''
    Write-Host '  [opencode] Apply bundle' -ForegroundColor Cyan
    $bundleLabel = if ($autoDetected) { "$bundlePath  (auto-detected)" } else { $bundlePath }
    Write-Host ("  bundle: {0}" -f $bundleLabel) -ForegroundColor DarkGray
    Write-Host ("  target: {0}" -f $targetPath) -ForegroundColor DarkGray
    Write-Host ''

    if ($DryRun) {
        Write-Host '  [opencode] DRY RUN -- no files written' -ForegroundColor Yellow
        if ($Force) {
            Write-Host '  [dry-run] would wipe target folder before copy (--force)' -ForegroundColor DarkYellow
        }
        foreach ($a in $actions) {
            Write-Host ("  [dry-run] {0}" -f $a.Rel) -ForegroundColor DarkYellow
        }
        Write-Host ("  Total files: {0}" -f $actions.Count) -ForegroundColor DarkGray
        Write-Host '  [dry-run] would run: npm i (inside ~/.config/opencode)' -ForegroundColor DarkYellow
        Write-Host '  [dry-run] then: restart OpenCode to auto-install plugins' -ForegroundColor DarkYellow
        Write-Host ''
        return
    }

    if ($Force -and (Test-Path $targetPath)) {
        # Delete contents but keep the directory itself — avoids "in use" error when cwd is inside target
        try {
            Get-ChildItem -Path $targetPath -Force -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction Stop
        } catch {
            Write-Host ("  [error] Failed to clear target folder contents: {0}" -f $_.Exception.Message) -ForegroundColor Red
            return
        }
    }

    if (-not (Test-Path $targetPath)) {
        $null = New-Item -Path $targetPath -ItemType Directory -Force
    }

    $copied = 0
    $errors = 0
    foreach ($a in $actions) {
        try {
            if (-not (Test-Path $a.DestDir)) {
                $null = New-Item -Path $a.DestDir -ItemType Directory -Force
            }
            Copy-Item -Path $a.Src -Destination $a.Dest -Force -ErrorAction Stop
            Write-Host ("  [ok]      {0}" -f $a.Rel) -ForegroundColor Green
            $copied++
        } catch {
            Write-Host ("  [error]   {0} -- {1}" -f $a.Rel, $_.Exception.Message) -ForegroundColor Red
            $errors++
        }
    }

    Write-Host ''
    Write-Host ("  Apply done. copied={0} errors={1}" -f $copied, $errors) -ForegroundColor $(if ($errors -gt 0) { 'DarkYellow' } else { 'Cyan' })
    Write-Host ''

    $npm = Get-Command npm -ErrorAction SilentlyContinue
    if (-not $npm) {
        Write-Host '  npm not found. Install Node/npm then run: cd ~/.config/opencode; npm i' -ForegroundColor DarkYellow
        Write-Host '    scoop install nvm' -ForegroundColor White
        Write-Host '    nvm install <version>' -ForegroundColor White
        Write-Host '    nvm use <version>' -ForegroundColor White
        Write-Host '    npm i' -ForegroundColor White
        Write-Host ''
        return
    }

    try {
        Push-Location $targetPath
        Write-Host '  Running npm i ...' -ForegroundColor Yellow
        npm i
        Write-Host '  npm i completed.' -ForegroundColor Green
    } catch {
        Write-Host ("  [error] npm i failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
    } finally {
        Pop-Location
    }



    Write-Host ''
    Write-Host '  [opencode] Setup complete!' -ForegroundColor Cyan
    Write-Host '  Next steps:' -ForegroundColor DarkGray
    Write-Host '    1) Restart OpenCode -- plugins (oh-my-opencode, supermemory, dcp) auto-install on startup' -ForegroundColor DarkGray
    Write-Host '    2) Add your API keys to ~/.config/opencode/opencode.json (provider.anthropic.options.apiKey)' -ForegroundColor DarkGray
    Write-Host '    3) MCPs that need local tools: serena (uvx), git-mcp (uvx), playwright-mcp (npx) -- ensure these are available' -ForegroundColor DarkGray
    Write-Host ''
}

function Invoke-OpencodeExport {
    param(
        [string]$BundleDir = 'oc-bundle',
        [switch]$DryRun
    )

    $source = Join-Path $HOME '.config\opencode'
    if (-not (Test-Path $source)) {
        Write-Host ("  [opencode] Source config not found: {0}" -f $source) -ForegroundColor Red
        return
    }

    $bundlePath = Resolve-OpencodeBundlePath -BundleDir $BundleDir
    $sourcePath = (Resolve-Path $source).Path

    $files = Get-ChildItem -Path $sourcePath -Recurse -Force -File -ErrorAction SilentlyContinue
    if (-not $files -or $files.Count -eq 0) {
        Write-Host '  [opencode] Source has no files to export.' -ForegroundColor DarkYellow
        return
    }

    $actions = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($file in $files) {
        $rel = Convert-ToRelativePath -BasePath $sourcePath -FullPath $file.FullName
        if (Test-OpencodeExportExcluded -RelativePath $rel) {
            continue
        }

        $dest = Join-Path $bundlePath $rel
        $destDir = Split-Path $dest -Parent
        $actions.Add([pscustomobject]@{
            Rel     = $rel
            Src     = $file.FullName
            Dest    = $dest
            DestDir = $destDir
        })
    }

    Write-Host ''
    Write-Host '  [opencode] Export bundle' -ForegroundColor Cyan
    Write-Host ("  source: {0}" -f $sourcePath) -ForegroundColor DarkGray
    Write-Host ("  bundle: {0}" -f $bundlePath) -ForegroundColor DarkGray
    Write-Host ''

    if ($actions.Count -eq 0) {
        Write-Host '  [opencode] Nothing to export after exclusions (lib, node_modules, *.ps1, *.py).' -ForegroundColor DarkYellow
        Write-Host ''
        return
    }

    if ($DryRun) {
        Write-Host '  [opencode] DRY RUN -- no files written' -ForegroundColor Yellow
        foreach ($a in $actions) {
            Write-Host ("  [dry-run] {0}" -f $a.Rel) -ForegroundColor DarkYellow
        }
        Write-Host ("  Total files: {0}" -f $actions.Count) -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    if (Test-Path $bundlePath) {
        try {
            Remove-Item -Path $bundlePath -Recurse -Force -ErrorAction Stop
        } catch {
            Write-Host ("  [error] Failed to clear bundle folder: {0}" -f $_.Exception.Message) -ForegroundColor Red
            return
        }
    }
    $null = New-Item -Path $bundlePath -ItemType Directory -Force

    $copied = 0
    $errors = 0
    foreach ($a in $actions) {
        try {
            if (-not (Test-Path $a.DestDir)) {
                $null = New-Item -Path $a.DestDir -ItemType Directory -Force
            }
            Copy-Item -Path $a.Src -Destination $a.Dest -Force -ErrorAction Stop
            Write-Host ("  [ok]      {0}" -f $a.Rel) -ForegroundColor Green
            $copied++
        } catch {
            Write-Host ("  [error]   {0} -- {1}" -f $a.Rel, $_.Exception.Message) -ForegroundColor Red
            $errors++
        }
    }

    Write-Host ''
    Write-Host ("  Export done. copied={0} errors={1}" -f $copied, $errors) -ForegroundColor $(if ($errors -gt 0) { 'DarkYellow' } else { 'Cyan' })
    Write-Host ''
    Write-Host '  Target machine:' -ForegroundColor Yellow
    Write-Host '    1. Copy all files from bundle folder -> ~/.config/opencode' -ForegroundColor White
    Write-Host '    2. cd ~/.config/opencode && npm i' -ForegroundColor White
    Write-Host '    3. If npm missing: scoop install nvm; nvm install <version>; nvm use <version>; npm i' -ForegroundColor White
    Write-Host ''
}

function Invoke-OpencodeStatus {
    $sourcePath = Join-Path $HOME '.config\opencode'
    $bundlePath = Resolve-OpencodeBundlePath -BundleDir 'oc-bundle'

    Write-Host ''
    Write-Host '  [opencode] Export Status' -ForegroundColor Cyan
    Write-Host ''

    $sourceOk = Test-Path $sourcePath
    Write-Host ("  {0,-40} {1}" -f '~/.config/opencode (source):', $(if ($sourceOk) { 'exists' } else { 'MISSING' })) -ForegroundColor $(if ($sourceOk) { 'Green' } else { 'Red' })

    $bundleOk = Test-Path $bundlePath
    Write-Host ("  {0,-40} {1}" -f './oc-bundle (default bundle):', $(if ($bundleOk) { 'exists' } else { 'MISSING' })) -ForegroundColor $(if ($bundleOk) { 'Green' } else { 'DarkYellow' })

    if ($bundleOk) {
        $bundleCount = (Get-ChildItem -Path $bundlePath -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
        Write-Host ("  {0,-40} {1}" -f 'bundle files:', $bundleCount) -ForegroundColor DarkGray
    }

    Write-Host ''
    $npm = Get-Command npm -ErrorAction SilentlyContinue
    $node = Get-Command node -ErrorAction SilentlyContinue
    $nvm = Get-Command nvm -ErrorAction SilentlyContinue

    Write-Host ("  {0,-18} {1}" -f 'node:', $(if ($node) { 'found' } else { 'MISSING' })) -ForegroundColor $(if ($node) { 'Green' } else { 'DarkYellow' })
    Write-Host ("  {0,-18} {1}" -f 'npm:', $(if ($npm) { 'found' } else { 'MISSING' })) -ForegroundColor $(if ($npm) { 'Green' } else { 'DarkYellow' })
    Write-Host ("  {0,-18} {1}" -f 'nvm:', $(if ($nvm) { 'found' } else { 'MISSING' })) -ForegroundColor $(if ($nvm) { 'Green' } else { 'DarkYellow' })

    if (-not $npm) {
        Write-Host ''
        Write-Host '  npm missing quick fix:' -ForegroundColor Yellow
        Write-Host '    scoop install nvm' -ForegroundColor White
        Write-Host '    nvm install <version>' -ForegroundColor White
        Write-Host '    nvm use <version>' -ForegroundColor White
        Write-Host '    npm i' -ForegroundColor White
    }

    Write-Host ''
}

function Invoke-OpencodeCommand {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Rest
    )

    $dryRun = $Rest -contains '--dry-run'
    $force = $Rest -contains '--force'

    $sub = 'export'
    $argStart = 0
    if ($Rest.Count -gt 0 -and $Rest[0] -notlike '--*') {
        $sub = $Rest[0].ToLowerInvariant()
        $argStart = 1
    }

    $bundleDir = 'oc-bundle'
    if ($Rest.Count -gt $argStart) {
        $candidate = $Rest[$argStart]
        if ($candidate -and $candidate -notlike '--*') {
            $bundleDir = $candidate
        }
    }

    switch ($sub) {
        'export' { Invoke-OpencodeExport -BundleDir $bundleDir -DryRun:$dryRun }
        'apply' { Invoke-OpencodeApply -BundleDir $bundleDir -DryRun:$dryRun -Force:$force }
        'reinstall' { Invoke-OpencodeApply -BundleDir $bundleDir -DryRun:$dryRun -Force }
        'install' { Invoke-OpencodeExport -BundleDir $bundleDir -DryRun:$dryRun } # backward-compatible alias
        'setup' { Invoke-OpencodeExport -BundleDir $bundleDir -DryRun:$dryRun }   # backward-compatible alias
        '--dry-run' { Invoke-OpencodeExport -BundleDir 'oc-bundle' -DryRun }
        'status' { Invoke-OpencodeStatus }
        'help' { Show-OpencodeHelp }
        default { Show-OpencodeHelp }
    }
}
