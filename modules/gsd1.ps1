# =============================================================================
# 8sync gsd-1 -- OpenCode .planning/ guide bridge
# =============================================================================

function Get-Gsd1ProjectPaths {
    $planningDir = Join-Path $PWD.Path '.planning'
    return [pscustomobject]@{
        PlanningDir   = $planningDir
        ConfigPath    = Join-Path $planningDir 'config.json'
        OcConfigPath  = Join-Path $planningDir 'oc-config.json'
        ProjectMdPath = Join-Path $planningDir 'PROJECT.md'
        RoadmapPath   = Join-Path $planningDir 'ROADMAP.md'
        StatePath     = Join-Path $planningDir 'STATE.md'
        ReadmePath    = 'C:\Users\Admin\Downloads\gsd-opencode-guide.md'
    }
}

function Show-Gsd1Help {
    $paths = Get-Gsd1ProjectPaths

    Write-Host ''
    Write-HintSection 'GSD-1 -- OpenCode .planning/ workflow (project-local)'
    Write-HintRow '8sync gsd-1 help'                    'Show this guide bridge for the .planning/ based GSD system'
    Write-HintRow '8sync gsd-1 status'                  'Check whether the current repo has .planning/config.json and related files'
    Write-HintRow '8sync gsd-1 guide'                   'Show the local guide path for the OpenCode GSD workflow'
    Write-HintRow '8sync gsd-1 setup'                   'Explain the recommended setup sequence for .planning/ based GSD'
    Write-Host ''
    Write-Host '  This namespace is documentation/status only.' -ForegroundColor DarkYellow
    Write-Host '  It does not replace the OpenCode slash commands from gsd-opencode.' -ForegroundColor DarkYellow
    Write-Host ''
    Write-Host '  Recommended flow:' -ForegroundColor DarkGray
    Write-Host '    1) Configure OpenCode providers/models in opencode.json' -ForegroundColor DarkGray
    Write-Host '    2) Use the OpenCode GSD commands to initialize the project:' -ForegroundColor DarkGray
    Write-Host '       /gsd-new-project --auto @prd.md' -ForegroundColor White
    Write-Host '       /gsd-settings' -ForegroundColor White
    Write-Host '    3) Confirm .planning/config.json exists in the repo root' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host ('  Guide: {0}' -f $paths.ReadmePath) -ForegroundColor DarkGray
    Write-Host ('  Current repo .planning/: {0}' -f $paths.PlanningDir) -ForegroundColor DarkGray
    Write-Host ''
}

function Invoke-Gsd1Status {
    $paths = Get-Gsd1ProjectPaths
    $rows = @(
        @{ Label = '.planning/'; Path = $paths.PlanningDir },
        @{ Label = 'config.json'; Path = $paths.ConfigPath },
        @{ Label = 'oc-config.json'; Path = $paths.OcConfigPath },
        @{ Label = 'PROJECT.md'; Path = $paths.ProjectMdPath },
        @{ Label = 'ROADMAP.md'; Path = $paths.RoadmapPath },
        @{ Label = 'STATE.md'; Path = $paths.StatePath }
    )

    Write-Host ''
    Write-Host '  [gsd-1] OpenCode .planning/ status' -ForegroundColor Cyan
    Write-Host ('  repo: {0}' -f $PWD.Path) -ForegroundColor DarkGray
    Write-Host ''
    foreach ($row in $rows) {
        $exists = Test-Path $row.Path
        $status = if ($exists) { 'ok' } else { 'MISSING' }
        $color = if ($exists) { 'Green' } else { 'DarkYellow' }
        Write-Host ('  {0,-16} {1,-8} {2}' -f $row.Label, $status, $row.Path) -ForegroundColor $color
    }
    Write-Host ''
    Write-Host '  If config.json is missing, initialize inside OpenCode with:' -ForegroundColor DarkGray
    Write-Host '    /gsd-new-project --auto @prd.md' -ForegroundColor White
    Write-Host '    /gsd-settings' -ForegroundColor White
    Write-Host ''
}

function Get-Gsd1ModelStack {
    param([string]$ModelArg)

    if ([string]::IsNullOrWhiteSpace($ModelArg)) { return $null }

    $aliases = @{
        'claude' = 'claude'
        'anthropic' = 'claude'
        'codex' = 'codex'
        'openai' = 'codex'
        'glm' = 'glm'
        'zai' = 'glm'
    }

    $result = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($token in ($ModelArg -split '\+' | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ -ne '' })) {
        if (-not $aliases.ContainsKey($token)) {
            Write-Host ("  [error] Unknown gsd-1 model brand '{0}'. Accepted: claude codex glm" -f $token) -ForegroundColor Red
            return $null
        }
        $id = $aliases[$token]
        if ($id -eq 'glm') {
            Write-Host '  [warn] GLM is temporarily disabled in gsd-1 auto-setup until the correct OpenCode provider ID is verified.' -ForegroundColor DarkYellow
            continue
        }
        if ($seen.Add($id)) { $result.Add($id) }
    }

    if ($result.Count -eq 0) {
        Write-Host '  [error] No usable gsd-1 providers remained. Use claude, codex, or claude+codex for now.' -ForegroundColor Red
        return $null
    }

    return $result.ToArray()
}

function Build-Gsd1ConfigSpec {
    param([string[]]$Brands)

    if (-not $Brands -or $Brands.Count -eq 0) { return $null }

    $hasClaude = $Brands -contains 'claude'
    $hasCodex = $Brands -contains 'codex'

    $planModel = if ($hasClaude) { 'anthropic/claude-sonnet-4-6' } elseif ($hasCodex) { 'openai/gpt-5.3-codex' } else { '' }
    $execModel = if ($hasCodex) { 'openai/gpt-5.3-codex' } elseif ($hasClaude) { 'anthropic/claude-sonnet-4-6' } else { '' }
    $researchModel = if ($hasCodex) { 'openai/gpt-5.3-codex' } elseif ($hasClaude) { 'anthropic/claude-haiku-4-5' } else { '' }

    return [pscustomobject]@{
        Name = ($Brands -join '+')
        Plan = $planModel
        Execute = $execModel
        Research = $researchModel
        Overrides = [ordered]@{
            'gsd-planner' = $planModel
            'gsd-plan-checker' = $planModel
            'gsd-executor' = $execModel
            'gsd-phase-researcher' = $researchModel
            'gsd-verifier' = $planModel
            'gsd-debugger' = $planModel
            'gsd-doc-writer' = $researchModel
            'gsd-integration-checker' = $researchModel
        }
    }
}

function Resolve-Gsd1PlanSpec {
    param([string]$Plan)

    if ([string]::IsNullOrWhiteSpace($Plan)) { return $null }

    switch ($Plan.Trim().ToLowerInvariant()) {
        'claude-codex' {
            return Build-Gsd1ConfigSpec -Brands @('claude', 'codex')
        }
        default {
            Write-Host ("  [error] Unknown gsd-1 plan '{0}'. Valid: claude-codex" -f $Plan) -ForegroundColor Red
            return $null
        }
    }
}

function Read-Gsd1ProjectConfig {
    $paths = Get-Gsd1ProjectPaths
    if (-not (Test-Path $paths.ConfigPath)) {
        return [pscustomobject]@{ Path = $paths.ConfigPath; Data = [pscustomobject]@{} }
    }

    try {
        $raw = Get-Content $paths.ConfigPath -Raw -Encoding UTF8
        return [pscustomobject]@{ Path = $paths.ConfigPath; Data = ($raw | ConvertFrom-Json) }
    } catch {
        Write-Host ("  [error] Failed to read .planning/config.json: {0}" -f $_.Exception.Message) -ForegroundColor Red
        return $null
    }
}

function Write-Gsd1ProjectConfig {
    param(
        [Parameter(Mandatory)] [object]$Config,
        [Parameter(Mandatory)] [string]$Path,
        [switch]$DryRun
    )

    $json = $Config | ConvertTo-Json -Depth 20
    if ($DryRun) {
        Write-Host ''
        Write-Host '  [dry-run] Would write:' -ForegroundColor Yellow
        Write-Host ("  {0}" -f $Path) -ForegroundColor DarkGray
        $json -split "`n" | ForEach-Object { Write-Host ("  {0}" -f $_) -ForegroundColor DarkGray }
        Write-Host ''
        return $true
    }

    $dir = Split-Path $Path -Parent
    if (-not (Test-Path $dir)) { $null = New-Item -Path $dir -ItemType Directory -Force }

    try {
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($Path, $json, $utf8NoBom)
        return $true
    } catch {
        Write-Host ("  [error] Failed to write .planning/config.json: {0}" -f $_.Exception.Message) -ForegroundColor Red
        return $false
    }
}

function Set-Gsd1Property {
    param([Parameter(Mandatory)] [object]$Parent, [Parameter(Mandatory)] [string]$Name, $Value)
    if ($Parent.PSObject.Properties[$Name]) { $Parent.PSObject.Properties.Remove($Name) }
    $Parent | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
}

function Ensure-Gsd1ObjectProperty {
    param([Parameter(Mandatory)] [object]$Parent, [Parameter(Mandatory)] [string]$Name)
    if (-not $Parent.PSObject.Properties[$Name]) {
        $Parent | Add-Member -NotePropertyName $Name -NotePropertyValue ([pscustomobject]@{})
    }
    return $Parent.$Name
}

function Invoke-Gsd1SetupFromModel {
    param([string]$Model, [string]$Plan, [switch]$DryRun)

    $spec = $null
    if (-not [string]::IsNullOrWhiteSpace($Plan)) {
        $spec = Resolve-Gsd1PlanSpec -Plan $Plan
    } else {
        $brands = Get-Gsd1ModelStack -ModelArg $Model
        if ($brands) {
            $spec = Build-Gsd1ConfigSpec -Brands $brands
        }
    }
    if (-not $spec) { return }

    $configFile = Read-Gsd1ProjectConfig
    if (-not $configFile) { return }

    $config = $configFile.Data
    Set-Gsd1Property -Parent $config -Name 'resolve_model_ids' -Value 'omit'
    Set-Gsd1Property -Parent $config -Name 'model_profile' -Value 'balanced'
    Set-Gsd1Property -Parent $config -Name 'research' -Value $true
    Set-Gsd1Property -Parent $config -Name 'plan_check' -Value $true
    Set-Gsd1Property -Parent $config -Name 'verifier' -Value $true

    $overrides = Ensure-Gsd1ObjectProperty -Parent $config -Name 'model_overrides'
    foreach ($entry in $spec.Overrides.GetEnumerator()) {
        Set-Gsd1Property -Parent $overrides -Name $entry.Key -Value $entry.Value
    }

    Write-Host ''
    Write-Host ("  [gsd-1] Setup  model={0}" -f $spec.Name) -ForegroundColor Cyan
    Write-Host ("  dest     : {0}" -f $configFile.Path) -ForegroundColor DarkGray
    foreach ($entry in $spec.Overrides.GetEnumerator()) {
        Write-Host ("  {0,-24} {1}" -f ($entry.Key + ':'), $entry.Value) -ForegroundColor DarkGray
    }
    Write-Host ''

    $ok = Write-Gsd1ProjectConfig -Config $config -Path $configFile.Path -DryRun:$DryRun
    if ($ok -and -not $DryRun) {
        Write-Host ("  [ok] {0}" -f $configFile.Path) -ForegroundColor Green
        Write-Host '  Restart OpenCode after changing .planning/config.json if the session already loaded GSD.' -ForegroundColor DarkGray
        Write-Host ''
    }
}

function Show-Gsd1SetupHint {
    $paths = Get-Gsd1ProjectPaths

    Write-Host ''
    Write-Host '  [gsd-1] Setup hint' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  This is the .planning/ based OpenCode GSD line.' -ForegroundColor DarkGray
    Write-Host '  It is separate from "8sync gsd", which manages C:\Users\Admin\.gsd\PREFERENCES.md.' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  Supported quick setup via 8sync:' -ForegroundColor DarkGray
    Write-Host '    8sync gsd-1 setup --model claude+codex' -ForegroundColor White
    Write-Host '    8sync gsd-1 setup --plan claude-codex' -ForegroundColor White
    Write-Host ''
    Write-Host '  Full workflow inside OpenCode:' -ForegroundColor DarkGray
    Write-Host '    /gsd-new-project --auto @prd.md' -ForegroundColor White
    Write-Host '    /gsd-settings' -ForegroundColor White
    Write-Host ''
    Write-Host '  Expected project files after setup:' -ForegroundColor DarkGray
    Write-Host ('    {0}' -f $paths.ConfigPath) -ForegroundColor White
    Write-Host ('    {0}' -f $paths.OcConfigPath) -ForegroundColor White
    Write-Host ''
}

function Invoke-Gsd1Command {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Rest
    )

    $sub = if ($Rest.Count -gt 0) { $Rest[0].ToLowerInvariant() } else { 'help' }
    switch ($sub) {
        'help'   { Show-Gsd1Help }
        'status' { Invoke-Gsd1Status }
        'guide'  {
            $paths = Get-Gsd1ProjectPaths
            Write-Host ''
            Write-Host ('  Guide: {0}' -f $paths.ReadmePath) -ForegroundColor Cyan
            Write-Host ''
        }
        'setup'  {
            $dryRun = $Rest -contains '--dry-run'
            $modelArg = ''
            $planArg = ''
            $modelIdx = [Array]::IndexOf($Rest, '--model')
            if ($modelIdx -ge 0 -and $modelIdx + 1 -lt $Rest.Count) {
                $modelArg = $Rest[$modelIdx + 1]
            }
            $modelEq = $Rest | Where-Object { $_ -like '--model=*' } | Select-Object -First 1
            if ($modelEq) {
                $modelArg = $modelEq -replace '^--model=', ''
            }
            $planIdx = [Array]::IndexOf($Rest, '--plan')
            if ($planIdx -ge 0 -and $planIdx + 1 -lt $Rest.Count) {
                $planArg = $Rest[$planIdx + 1]
            }
            $planEq = $Rest | Where-Object { $_ -like '--plan=*' } | Select-Object -First 1
            if ($planEq) {
                $planArg = $planEq -replace '^--plan=', ''
            }

            if ([string]::IsNullOrWhiteSpace($modelArg) -and [string]::IsNullOrWhiteSpace($planArg)) {
                Show-Gsd1SetupHint
            } else {
                Invoke-Gsd1SetupFromModel -Model $modelArg -Plan $planArg -DryRun:$dryRun
            }
        }
        default  { Show-Gsd1Help }
    }
}
