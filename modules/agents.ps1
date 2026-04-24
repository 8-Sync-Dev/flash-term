# =============================================================================
# 8sync agents -- loader
# =============================================================================

$script:AgentsModuleDir = Join-Path $PSScriptRoot 'agents'

foreach ($moduleFile in @(
    '00-shared.ps1',
    '50-command.ps1',
    '55-max-skill.ps1'
)) {
    . (Join-Path $script:AgentsModuleDir $moduleFile)
}
