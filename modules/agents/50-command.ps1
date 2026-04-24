# =============================================================================
# 8sync agents -- command dispatcher
# =============================================================================

function Show-AgentsHelp {
    Write-Host ''
    Write-Host '  8SYNC AGENTS -- AI agent skill management' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  Commands:' -ForegroundColor DarkGray
    Write-HintRow '8sync agents max-skill'               'Install all skills to Forge/.gsd/Claude Code + RTK + force-load rules'
    Write-HintRow '8sync agents max-skill --dry-run'     'Preview all changes, no writes'
    Write-HintRow '8sync agents max-skill --only <name>' 'Install single skill (e.g. --only ui-ux-pro-max)'
    Write-HintRow '8sync agents max-skill --skip-token-save' 'Skip RTK/token-save setup'
    Write-HintRow '8sync agents list'                    'List all skills with install status and URLs'
    Write-HintRow '8sync agents check'                   'List skills + HTTP check all URLs for liveness'
    Write-Host ''
    Write-Host '  Skill Registry (agents/registry.json):' -ForegroundColor DarkGray
    $registry = Get-AgentSkillRegistry
    foreach ($skill in $registry | Sort-Object { [int]($_.priority) }) {
        $mandatory = if ($skill.mandatory) { ' [mandatory]' } else { '' }
        Write-Host ("    [{0}]{1,-2} {2,-20} {3}" -f $skill.priority, $(if ($skill.mandatory) {'*'} else {' '}), $skill.name, $skill.use_when) -ForegroundColor DarkGray
    }
    Write-Host ''
}

function Invoke-AgentCommand {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Rest
    )

    if (-not $Rest -or $Rest.Count -eq 0) {
        Show-AgentsHelp
        return
    }

    $sub     = $Rest[0].ToLowerInvariant()
    $subRest = if ($Rest.Count -gt 1) { $Rest[1..($Rest.Count - 1)] } else { @() }

    $dryRun  = $Rest -contains '--dry-run'

    switch ($sub) {
        'max-skill' {
            $skipTs  = $Rest -contains '--skip-token-save'
            $onlyIdx = [Array]::IndexOf($Rest, '--only')
            $only    = if ($onlyIdx -ge 0 -and $onlyIdx + 1 -lt $Rest.Count) { $Rest[$onlyIdx + 1] } else { $null }
            Invoke-AgentMaxSkill -DryRun:$dryRun -SkipTokenSave:$skipTs -Only $only
        }
        'list' {
            Invoke-AgentListSkills
        }
        'check' {
            Invoke-AgentCheckLinks
        }
        'help' {
            Show-AgentsHelp
        }
        default {
            Show-AgentsHelp
        }
    }
}
