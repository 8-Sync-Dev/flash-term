$errs = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile(
    'C:\Users\Admin\.config\wezterm\modules\bg.ps1', [ref]$null, [ref]$errs)
if ($errs.Count -eq 0) { Write-Host 'Parse OK' } else { $errs | ForEach-Object { Write-Host $_.ToString() } }
