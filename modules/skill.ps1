# =============================================================================
# 8sync skill -- manage the omp skill registry (add/list/update/remove/deploy)
# =============================================================================
# Skills are markdown (SKILL.md) clones from GitHub, deployed to ~/.omp/skills
# where omp auto-discovers them. The registry lives at agents/registry.json.
# =============================================================================
# Usage:
#   8sync skill list                 List registry + install/deploy status
#   8sync skill add <github-url>     Clone + register + deploy a skill
#   8sync skill update [name]        Re-pull a skill (or all)
#   8sync skill remove <name>        Remove from registry + delete
#   8sync skill deploy               Deploy all registry skills to ~/.omp/skills
# =============================================================================

function Get-OmpSkillsDeployDir {
    # Where omp auto-discovers skills.
    Join-Path $HOME '.omp\skills'
}

function Get-SkillInstallCache {
    # Local clone cache (gitignored). agents/skills/ per the .gitignore contract.
    if (Get-Command Get-AgentInstallRoot -ErrorAction SilentlyContinue) { return (Get-AgentInstallRoot) }
    Join-Path $PSScriptRoot '..\..\agents\skills'
}

function Read-SkillRegistry {
    $path = Get-AgentRegistryPath
    if (Test-Path $path) {
        try { return @(Get-Content -Raw $path | ConvertFrom-Json) } catch {}
    }
    return @()
}

function Write-SkillRegistry {
    param([array]$List)
    $path = Get-AgentRegistryPath
    $null = New-Item -ItemType Directory -Force -Path (Split-Path $path)
    $json = $List | Sort-Object { [int]$_.priority } | ConvertTo-Json -Depth 6
    if ($List.Count -eq 1) { $json = @($List) | ConvertTo-Json -Depth 6 }  # keep array shape
    [System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($false))
}

function ConvertTo-SkillName {
    param([string]$Url)
    $m = [regex]::Match($Url, 'github\.com[:/](?<owner>[^/]+)/(?<repo>[^/.?#]+)')
    if ($m.Success) { return $m.Groups['repo'].Value }
    return ($Url -replace '[^A-Za-z0-9]+', '-').Trim('-')
}

# ── deploy a skill to ~/.omp/skills (omp discovery) ─────────────────────────

function Deploy-SkillToOmp {
    # Copy a cloned skill dir from the cache into ~/.omp/skills/<name>.
    param([Parameter(Mandatory)] [string]$Name, [switch]$DryRun)
    $src = Join-Path (Get-SkillInstallCache) $Name
    if (-not (Test-Path $src)) {
        Write-Host "  [skip]   ${Name}: not cloned yet" -ForegroundColor DarkYellow
        return $false
    }
    $dst = Join-Path (Get-OmpSkillsDeployDir) $Name
    if ($DryRun) {
        Write-Host "  [dry-run] would deploy $Name -> $dst" -ForegroundColor Yellow
        return $true
    }
    $null = New-Item -ItemType Directory -Force -Path (Get-OmpSkillsDeployDir)
    if (Test-Path $dst) { Remove-Item $dst -Recurse -Force -ErrorAction SilentlyContinue }
    try {
        # Robocopy the skill (handles long paths); fall back to Copy-Item.
        $rc = (Start-Process robocopy -ArgumentList "`"$src`" `"$dst`" /E /NFL /NDL /NJH /NJS /NP" -NoNewWindow -Wait -PassThru -ErrorAction SilentlyContinue)
        if ($null -eq $rc -or $rc.ExitCode -gt 7) {
            Copy-Item -Path $src -Destination $dst -Recurse -Force -ErrorAction SilentlyContinue
        }
    } catch {
        Copy-Item -Path $src -Destination $dst -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host "  [ok]     deployed $Name -> ~/.omp/skills/$Name" -ForegroundColor Green
    return $true
}

# ── AGENTS.md injection (omp-tuned, no GSD) ─────────────────────────────────

function Get-OmpAgentsSection {
    param([array]$Registry)
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('<!-- agents:max-skill:start -- managed by 8sync skill deploy -->')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('## Agent Skill Library (8sync)')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('**Rule:** Before any non-trivial task, read the mandatory skill first, then select by task type.')
    [void]$sb.AppendLine('Skills are deployed to `~/.omp/skills/`; omp auto-discovers them.')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('| Skill | When |')
    [void]$sb.AppendLine('|---|---|')
    foreach ($s in ($Registry | Sort-Object { [int]$s.priority })) {
        $mark = if ($s.mandatory) { ' **(mandatory)**' } else { '' }
        [void]$sb.AppendLine(("| `~/.omp/skills/$($s.dir)/`$mark | $($s.use_when) |"))
    }
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('### Project memory (auto-managed)')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('Read the relevant file BEFORE making decisions that depend on project context:')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('| File | When to read |')
    [void]$sb.AppendLine('|---|---|')
    [void]$sb.AppendLine('| `8sync/PROJECT.md` | Start of any session |')
    [void]$sb.AppendLine('| `8sync/STATE.md` | Before resuming work |')
    [void]$sb.AppendLine('| `8sync/KNOWLEDGE.md` | Before writing new code |')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('Never dump huge tool output into context. Summarize first, then read narrow slices.')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('<!-- agents:max-skill:end -->')
    return $sb.ToString()
}

function Update-ProjectAgentsMd {
    param([array]$Registry, [switch]$DryRun)
    $path = Join-Path (Get-Location) 'AGENTS.md'
    $section = Get-OmpAgentsSection -Registry $Registry
    $startMarker = '<!-- agents:max-skill:start'
    $endMarker = '<!-- agents:max-skill:end -->'

    $content = if (Test-Path $path) { Get-Content -Raw $path } else { '' }
    $pattern = "(?s)`n?<!-- agents:max-skill:start.*<!-- agents:max-skill:end -->`n?"
    if ($content -match $startMarker) {
        $new = [regex]::Replace($content, $pattern, "`n$section`n")
    } else {
        $new = ($content.TrimEnd() + "`n`n" + $section + "`n")
    }
    if ($DryRun) {
        Write-Host "  [dry-run] would update $path" -ForegroundColor Yellow
        return
    }
    [System.IO.File]::WriteAllText($path, $new, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  [ok]     injected skill section -> AGENTS.md" -ForegroundColor Green
}

# ── deploy verb (used by harness init) ──────────────────────────────────────

function Invoke-SkillDeploy {
    # Clone every registry skill (if missing), deploy to ~/.omp/skills, inject AGENTS.md.
    param([switch]$DryRun)
    $registry = Get-AgentSkillRegistry
    if ($registry.Count -eq 0) {
        Write-Host '  [info]   registry empty (agents/registry.json)' -ForegroundColor DarkGray
        return
    }
    foreach ($skill in $registry) {
        $cache = Join-Path (Get-SkillInstallCache) $skill.dir
        if (-not (Test-Path $cache)) {
            Write-Host ("  [info]   cloning {0}..." -f $skill.name) -ForegroundColor DarkGray
            if (-not $DryRun) { Clone-SkillRepo -Url $skill.url -Dir $skill.dir | Out-Null }
        }
        Deploy-SkillToOmp -Name $skill.dir -DryRun:$DryRun | Out-Null
    }
    Update-ProjectAgentsMd -Registry $registry -DryRun:$DryRun
}

# ── registry verbs ──────────────────────────────────────────────────────────

function Invoke-SkillList {
    $registry = Get-AgentSkillRegistry
    $cache = Get-SkillInstallCache
    $deploy = Get-OmpSkillsDeployDir
    Write-Host ''
    Write-Host '  8SYNC SKILL -- registry' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  name                  cloned   deployed   url' -ForegroundColor DarkGray
    foreach ($s in ($registry | Sort-Object { [int]$s.priority })) {
        $cloned   = if (Test-Path (Join-Path $cache $s.dir)) { 'yes' } else { 'no' }
        $deployed = if (Test-Path (Join-Path $deploy $s.dir)) { 'yes' } else { 'no' }
        $mand     = if ($s.mandatory) { '*' } else { ' ' }
        Write-Host ("  {0}{1,-21} {2,-7}  {3,-9}  {4}" -f $mand, $s.name, $cloned, $deployed, $s.url)
    }
    Write-Host ''
    Write-Host '  * = mandatory  |  deployed = present in ~/.omp/skills (omp auto-discovers)' -ForegroundColor DarkGray
    Write-Host ''
}

function Invoke-SkillAdd {
    param([Parameter(Mandatory)] [string]$Url, [string]$Dir, [switch]$DryRun)
    $name = if ($Dir) { $Dir } else { ConvertTo-SkillName -Url $Url }
    $registry = @(Read-SkillRegistry)
    if ($registry | Where-Object { $_.name -eq $name -or $_.dir -eq $name }) {
        Write-Host "  [skip]   skill '$name' already in registry" -ForegroundColor DarkYellow
        return
    }
    $maxPri = ($registry | ForEach-Object { [int]$_.priority } | Measure-Object -Maximum).Maximum
    if (-not $maxPri) { $maxPri = 0 }
    $entry = [pscustomobject]@{
        name      = $name
        display   = $name
        url       = $Url
        dir       = $name
        use_when  = 'on-demand'
        priority  = ($maxPri + 1)
        mandatory = $false
        builtin   = $false
        tags      = @('user')
    }
    $registry = @($registry) + $entry
    if (-not $DryRun) {
        Write-SkillRegistry -List $registry
        Clone-SkillRepo -Url $Url -Dir $name | Out-Null
        Deploy-SkillToOmp -Name $name | Out-Null
        Update-ProjectAgentsMd -Registry (Get-AgentSkillRegistry)
    } else {
        Write-Host "  [dry-run] would add $name <- $Url" -ForegroundColor Yellow
    }
    Write-Host "  [ok]     added $name" -ForegroundColor Green
}

function Invoke-SkillUpdate {
    param([string]$Name)
    $registry = Get-AgentSkillRegistry
    $targets = if ($Name) { @($registry | Where-Object { $_.name -eq $Name -or $_.dir -eq $Name }) } else { @($registry) }
    if ($targets.Count -eq 0) { Write-Host "  [skip]   no matching skill '$Name'" -ForegroundColor DarkYellow; return }
    foreach ($s in $targets) {
        Clone-SkillRepo -Url $s.url -Dir $s.dir | Out-Null
        Deploy-SkillToOmp -Name $s.dir | Out-Null
    }
    Write-Host '  skill update done.' -ForegroundColor Green
}

function Invoke-SkillRemove {
    param([Parameter(Mandatory)] [string]$Name)
    $registry = @(Read-SkillRegistry)
    $kept = @($registry | Where-Object { $_.name -ne $Name -and $_.dir -ne $Name })
    if ($kept.Count -eq $registry.Count) { Write-Host "  [skip]   '$Name' not in registry" -ForegroundColor DarkYellow; return }
    Write-SkillRegistry -List $kept
    foreach ($base in @((Get-SkillInstallCache), (Get-OmpSkillsDeployDir))) {
        $p = Join-Path $base $Name
        if (Test-Path $p) { Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Update-ProjectAgentsMd -Registry (Get-AgentSkillRegistry)
    Write-Host "  [ok]     removed $Name" -ForegroundColor Green
}

function Show-SkillHelp {
    Write-Host ''
    Write-Host '  8SYNC SKILL -- omp skill registry' -ForegroundColor Cyan
    Write-Host ''
    Write-HintRow '8sync skill list'              'List registry + clone/deploy status'
    Write-HintRow '8sync skill add <github-url>'  'Clone + register + deploy a skill'
    Write-HintRow '8sync skill update [name]'     'Re-pull one skill (or all)'
    Write-HintRow '8sync skill remove <name>'     'Remove from registry + delete'
    Write-HintRow '8sync skill deploy'            'Deploy all registry skills to ~/.omp/skills'
    Write-Host ''
}

function Invoke-SkillCommand {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Rest
    )
    if (-not $Rest -or $Rest.Count -eq 0) { Show-SkillHelp; return }
    $sub = $Rest[0].ToLowerInvariant()
    $dryRun = $Rest -contains '--dry-run'
    switch ($sub) {
        'list'    { Invoke-SkillList }
        'add'     {
            $url = if ($Rest.Count -gt 1) { $Rest[1] } else { $null }
            $dir = if ($Rest.Count -gt 2) { $Rest[2] } else { $null }
            if (-not $url) { Write-Host '  Usage: 8sync skill add <github-url> [dir-name]' -ForegroundColor DarkYellow; return }
            Invoke-SkillAdd -Url $url -Dir $dir -DryRun:$dryRun
        }
        'update'  { Invoke-SkillUpdate -Name $(if ($Rest.Count -gt 1) { $Rest[1] }) }
        'remove'  { Invoke-SkillRemove -Name $(if ($Rest.Count -gt 1) { $Rest[1] }) }
        'deploy'  { Invoke-SkillDeploy -DryRun:$dryRun }
        'help'    { Show-SkillHelp }
        default   { Show-SkillHelp }
    }
}
