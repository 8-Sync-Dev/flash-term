function Register-ShellEngineInits {
    # Run zoxide and starship init AFTER all aliases are registered.
    # Both spawn an external process and Invoke-Expression the output --
    # typically 50-150ms each. Moving them here means the prompt appears
    # with all aliases ready before the engines hook in.
    # zoxide: registers z / __zoxide_hook. cdi alias already points to z.
    # starship: overrides PROMPT_COMMAND / prompt function.
    if (Test-CommandExists 'zoxide') {
        try {
            Invoke-Expression (& zoxide init powershell | Out-String)
        } catch {}
    }

    if (Test-CommandExists 'starship') {
        try {
            Invoke-Expression (& starship init powershell)
        } catch {}
    }
}

function Set-ToolAliases {
    if (Test-CommandExists 'eza') {
        function global:ll { eza --icons=always --group-directories-first -lah @args }
        function global:lt { eza --icons=always --group-directories-first -lah --tree --level=2 @args }
    } else {
        function global:ll { Get-ChildItem -Force @args }
    }

    if (Test-CommandExists 'bat') {
        function global:catn { bat --paging=never --style=plain @args }
    }

    if (Test-CommandExists 'rg') {
        function global:ff { rg --files @args }
    }

    if (Test-CommandExists 'zoxide') {
        Set-Alias -Name cdi -Value z -Scope Global -Force
    }

    if (Test-CommandExists 'delta') {
        $env:GIT_PAGER = 'delta'
    }

    if (Test-CommandExists 'yazi') {
        function global:y {
            $tmp = [System.IO.Path]::GetTempFileName()
            yazi --cwd-file="$tmp" @args
            $cwd = Get-Content $tmp -ErrorAction SilentlyContinue
            if ($cwd -and $cwd -ne $PWD.Path) {
                Set-Location $cwd
            }
            Remove-Item $tmp -ErrorAction SilentlyContinue
        }
    }

    if (Test-CommandExists 'lazygit') {
        Set-Alias -Name lg -Value lazygit -Scope Global -Force
    }

    if (Test-CommandExists 'hx') {
        Set-Alias -Name e -Value hx -Scope Global -Force
    }

    if (Test-CommandExists 'procs') {
        Set-Alias -Name pss -Value procs -Scope Global -Force
    }

    if (Test-CommandExists 'btm') {
        Set-Alias -Name top -Value btm -Scope Global -Force
    }

    if (Test-CommandExists 'dust') {
        Set-Alias -Name du -Value dust -Scope Global -Force
    }

    function global:mkcd {
        param([Parameter(Mandatory)] [string]$Path)
        $null = New-Item -ItemType Directory -Path $Path -Force
        Set-Location $Path
    }

    function global:Reset-TerminalState {
        # Resets all terminal modes that TUI apps (OpenCode, vim, etc.) may leave
        # behind when they crash or exit uncleanly:
        #   - Mouse tracking off (normal, button, any-event, SGR extended)
        #   - Bracketed paste off
        #   - Alternative screen off
        #   - Cursor visible, not blinking
        #   - Application keypad mode off
        [System.Console]::Write(
            "`e[?1000l" +   # mouse tracking off
            "`e[?1002l" +   # button-event mouse off
            "`e[?1003l" +   # any-event mouse off
            "`e[?1006l" +   # SGR extended mouse off
            "`e[?1015l" +   # URXVT extended mouse off
            "`e[?2004l" +   # bracketed paste off
            "`e[?1049l" +   # exit alt screen
            "`e[?25h"   +   # cursor visible
            "`e[0m"         # reset all SGR attributes
        )
        [System.Console]::WriteLine()
        Write-Host 'Terminal state reset.' -ForegroundColor Green
    }
    Set-Alias -Name fix -Value Reset-TerminalState -Scope Global -Force

    Register-8SyncAlias

    # Engine inits last -- these are the slowest external calls (50-150ms each)
    # All aliases/completers are already registered before this runs
    Register-ShellEngineInits
}


function Register-8SyncAlias {
    # `ft` command dispatcher + alias + tab completion for flash-term (WezTerm config).
    # The AI harness lives in the separate `8sync` (su-code) binary -- not here.

    function global:Invoke-8Sync {
        param(
            [string]$Mode = 'help',
            [Parameter(ValueFromRemainingArguments = $true)]
            [string[]]$Rest
        )

        switch ($Mode.ToLowerInvariant()) {
            'help'   { Show-8SyncHint }
            'hint'   { Show-8SyncHint }
            'status' { Show-8SyncStatus }
            'reload' {
                # Re-dot-source all modules + re-register dispatcher + completer in current session.
                Write-Host '  Reloading ft modules...' -ForegroundColor DarkGray
                $bootstrapDir = Split-Path $PSCommandPath -ErrorAction SilentlyContinue
                if (-not $bootstrapDir) { $bootstrapDir = $PSScriptRoot }
                # PSScriptRoot inside the dispatcher closure is the startup.ps1 dir (modules/)
                $modulesDir = $bootstrapDir
                $moduleFiles = @(
                    'core.ps1','sync.ps1','shell.ps1','bg.ps1','helix.ps1',
                    'clean.ps1','theme.ps1','gpu.ps1','gguf.ps1','up.ps1','autoupdate.ps1','setup.ps1','dev.ps1','profile.ps1'
                )
                $ok = 0; $fail = 0
                foreach ($f in $moduleFiles) {
                    $path = Join-Path $modulesDir $f
                    if (Test-Path $path) {
                        try { . $path; $ok++ }
                        catch { Write-Warning "reload: failed to load $f -- $_"; $fail++ }
                    }
                }
                # Re-register dispatcher and completer with updated functions
                Register-8SyncAlias
                Write-Host ("  Reloaded {0} modules{1}" -f $ok, $(if ($fail) { ", $fail failed" } else { '' })) -ForegroundColor Green
                Write-Host '  All ft functions updated in current session.' -ForegroundColor DarkGray
                Write-Host ''
            }
            'sync'   {
                $checkFlag = $Rest -contains '--check'
                if ($Rest -contains '--help' -or $Rest -contains 'help' -or $Rest -contains '-h') {
                    Write-Host ''
                    Write-HintSection 'SYNC -- install and update managed tools via Scoop'
                    Write-HintRow 'ft sync'         'Install missing + update all managed tools'
                    Write-HintRow 'ft sync --check' 'Dry-run: show missing tools + available updates, no changes'
                    Write-Host ''
                } else {
                    Invoke-ToolSync -Check:$checkFlag
                }
            }
            'clean'  { Invoke-CleanCommand -Rest $Rest }
            'gpu'    { Invoke-GpuCommand -Rest $Rest }
            'bg'     { Invoke-BgCommand -Rest $Rest }
            'hx'     { Invoke-HxCommand -Rest $Rest }
            'theme'  { Invoke-ThemeCommand -Rest $Rest }
            'gguf'     { Invoke-GgufCommand -Rest $Rest }
            'setup'    { Invoke-SetupCommand -Rest $Rest }
            'dev'      { Invoke-DevCommand -Rest $Rest }
            'autoupdate' { Invoke-AutoupdateCommand -Rest $Rest }
            'profile'  { Invoke-ProfileCommand -Rest $Rest }
            default  { Show-8SyncHint }
        }
    }

    # `ft` is the flash-term command. `8sync`/`/8sync` are NOT aliased here -- that
    # name belongs to the su-code AI binary, which must not be shadowed.
    Set-Alias -Name 'ft' -Value Invoke-8Sync -Scope Global -Force

    Register-8SyncCompleter
}

function Test-NerdFontInstalled {
    # Check 1: scoop manifest present (fastest, no assembly needed)
    $scoop = Get-ScoopCommand
    if ($scoop) {
        try {
            $info = & $scoop.Source info JetBrainsMono-NF 2>$null | Out-String
            if ($info -match 'Installed') { return $true }
        } catch {}
    }

    # Check 2: font files exist in user or system font folder
    $fontDirs = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'),
        'C:\Windows\Fonts',
        (Join-Path $HOME 'scoop\apps\JetBrainsMono-NF\current')
    )
    foreach ($dir in $fontDirs) {
        if ((Test-Path $dir) -and (Get-ChildItem $dir -Filter '*JetBrainsMono*' -ErrorAction SilentlyContinue)) {
            return $true
        }
    }

    # Check 3: registry (HKCU user fonts, no admin needed)
    foreach ($regPath in @(
        'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts',
        'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    )) {
        try {
            $regFonts = Get-ItemProperty $regPath -ErrorAction SilentlyContinue
            if ($regFonts -and ($regFonts.PSObject.Properties.Name | Where-Object { $_ -like '*JetBrainsMono*' })) {
                return $true
            }
        } catch {}
    }

    # Check 4: System.Drawing (requires explicit assembly load in PS 5.1)
    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
        $families = [System.Drawing.FontFamily]::Families | ForEach-Object { $_.Name }
        if (($families -contains 'JetBrainsMono Nerd Font') -or ($families -contains 'JetBrainsMono NF')) {
            return $true
        }
    } catch {}

    return $false
}

function Ensure-NerdFont {
    if ($script:NerdFontChecked) { return }
    $script:NerdFontChecked = $true

    if (Test-NerdFontInstalled) { return }
    Write-Host '[ft] JetBrainsMono Nerd Font not found.' -ForegroundColor DarkYellow
    Write-Host '  To install: scoop bucket add nerd-fonts && scoop install JetBrainsMono-NF' -ForegroundColor DarkGray
}

function Start-WezTermShell {
    $startupMode = Get-StartupMode
    $boot = [System.Diagnostics.Stopwatch]::StartNew()
    $phaseMs = [ordered]@{}
    $phase = [System.Diagnostics.Stopwatch]::StartNew()
    $runBackgroundChecks = Test-StartupBackgroundGate

    $markPhase = {
        param([Parameter(Mandatory)] [string]$Name)
        $phaseMs[$Name] = [math]::Round($phase.Elapsed.TotalMilliseconds, 1)
        $phase.Restart()
    }

    $psVer = $PSVersionTable.PSVersion
    if ($psVer.Major -lt 5 -or ($psVer.Major -eq 5 -and $psVer.Minor -lt 1)) {
        Write-Warning ('[ft] PowerShell {0}.{1} detected. Minimum supported: 5.1. Some features may not work.' -f $psVer.Major, $psVer.Minor)
        Write-Warning '[ft] Install pwsh 7+: scoop install powershell  or  https://aka.ms/powershell'
    }
    & $markPhase 'version-check'

    Ensure-PreferredPaths
    & $markPhase 'preferred-paths'

    if ($startupMode -ne 'light') {
        Ensure-NerdFont
    }
    & $markPhase 'font-check'

    $env:TERM_PROGRAM = 'WezTerm'
    if ($Host.UI -and $Host.UI.RawUI) {
        try {
            $Host.UI.RawUI.WindowTitle = 'WezTerm PowerShell'
        } catch {
            # Ignore if console doesn't support title setting
        }
    }
    & $markPhase 'terminal-meta'

    Set-HistoryExperience
    & $markPhase 'history'

    Set-ToolAliases
    & $markPhase 'aliases-and-engines'

    if ($runBackgroundChecks) {
        if ($startupMode -eq 'light') {
            Start-CleanLoopCheck
            & $markPhase 'background-checks(light)'
        } else {
            Start-AutoSync
            Start-BgRotateCheck
            Start-CleanLoopCheck
            Start-AutoupdateCheck
            & $markPhase 'background-checks(full)'
        }
    } else {
        & $markPhase 'background-checks(skipped)'
    }

    $missingPackages = @()
    if ($startupMode -ne 'light') {
        $missingPackages = Get-MissingPackages
    }
    & $markPhase 'missing-cache'

    if ($missingPackages.Count -gt 0) {
        Write-Host ('[ft] Missing tools: {0}. Run "ft sync" to install.' -f ($missingPackages -join ', ')) -ForegroundColor DarkYellow
    }

    $boot.Stop()
    Write-StartupProfile -Mode $startupMode -Phases $phaseMs -TotalMs $boot.Elapsed.TotalMilliseconds
    Show-AutoupdateNotice

    if ($env:WEZTERM_BOOT_TRACE -eq '1') {
        Write-Host ('[ft] startup {0}ms ({1})' -f [math]::Round($boot.Elapsed.TotalMilliseconds, 1), $startupMode) -ForegroundColor DarkGray
    }
}
