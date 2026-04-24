# =============================================================================
# 8sync gsd -- loader
# =============================================================================

$script:GsdModuleDir = Join-Path $PSScriptRoot 'gsd'

foreach ($moduleFile in @(
    '00-shared.ps1',
    '05-plans.ps1',
    '10-setup.ps1',
    '20-interactive.ps1',
    '25-local.ps1',
    '27-global.ps1',
    '30-status.ps1',
    '40-gguf.ps1',
    '50-command.ps1',
    '55-nuke.ps1',
    '60-combo.ps1'
)) {
    . (Join-Path $script:GsdModuleDir $moduleFile)
}
