function Set-HistoryExperience {
    # PSReadLine is already loaded in PS 5.1+ by default; skip the slow
    # Get-Module -ListAvailable scan and just try to configure it directly.
    # If it isn't present the try/catch swallows the error silently.

    try {
        # Basic readline options -- fast path, no module scan needed
        Set-PSReadLineOption -EditMode Windows -ErrorAction Stop
        Set-PSReadLineOption -PredictionSource History -ErrorAction Stop
        Set-PSReadLineOption -PredictionViewStyle ListView -ErrorAction Stop
        Set-PSReadLineOption -BellStyle None -ErrorAction Stop
        Set-PSReadLineOption -HistoryNoDuplicates -ErrorAction Stop
        Set-PSReadLineOption -MaximumHistoryCount 20000 -ErrorAction Stop
        Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete -ErrorAction Stop
        Set-PSReadLineKeyHandler -Chord 'Ctrl+d' -Function DeleteChar -ErrorAction Stop
        Set-PSReadLineKeyHandler -Chord 'Alt+c' -ScriptBlock {
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert('cdi ')
            [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
        } -ErrorAction Stop
        Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward -ErrorAction Stop
        Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward -ErrorAction Stop
    } catch {
        # PSReadLine not available or console doesn't support all features -- silent
    }

    if (Test-CommandExists 'fzf') {
        try {
            Set-PSReadLineKeyHandler -Chord 'Ctrl+r' -ScriptBlock {
                $historyPath = (Get-PSReadLineOption).HistorySavePath
                if (-not (Test-Path $historyPath)) { return }
                $history = Get-Content $historyPath -ErrorAction SilentlyContinue
                if (-not $history) { return }
                [array]::Reverse($history)
                $selected = $history | fzf --height=45% --layout=reverse --border --prompt='History> ' --no-sort
                if ($selected) {
                    [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
                    [Microsoft.PowerShell.PSConsoleReadLine]::Insert($selected)
                }
            } -ErrorAction Stop
        } catch {}
    }
}

function Register-8SyncCompleter {
    if ($script:EightSyncCompleterRegistered) {
        return
    }

    # Tab / inline completion for: 8sync <mode> <subcommand>
    $completer = {
        param($wordToComplete, $commandAst, $cursorPosition)

        $tokens = $commandAst.CommandElements | ForEach-Object { $_.ToString() }
        $count  = $tokens.Count

        # top-level modes
    $modes = @('help','status','reload','sync','clean','gpu','bg','hx','theme','opencode','forge','gsd','gsd-1','gguf','remove')

        # subcommands per mode
        $subMap = @{
            bg    = @('search','pick','set','open','rotate','list','clear','remove','help','--preview','--yandere','--safebooru','--all')
            hx    = @('lang','wrap','opacity','theme','bg','health','help')
            theme = @('status','list','help','style','scene','focus','cinematic','showcase','neon_glass','ice_glass','mint_glass')
            sync  = @('--check','--help')
            clean = @('help','--days','--dry-run','--envs','--projects','--all','--deep','--delete','--scan','--audit','--loop','on','off','now','status','profile','light','balanced','deep','--help')
            gpu = @('status','auto','off','help','--help','-h','0','10','20','30')
            opencode = @('export','apply','reinstall','fresh-install','deep-clean','uninstall-claude','install','setup','status','connect','help','cli','--cli','--dry-run','--force','--stable','--model','--plan','--claude=yes','--claude=max20','--claude=no','--openai=yes','--openai=no','--gemini=yes','--gemini=no','--copilot=yes','--copilot=no','claude-max','codex-max','gemini-max','glm-max','claude-codex-gemini','claude','codex','gemini','glm','groq','gguf')
            forge    = @('install','update','status','login','provider','uninstall','remove','help','--force','--dry-run')
            gsd = @('setup','fix','key','keys','status','local','global','model','add','connect','remove','help','init','baseline','add-submodule','use','install','build','apply-anthropic-patch','enter','leave','latest','promote','rollback','--dry-run','--auto','--pick','--stable','--force','--refresh','--allow-global','--balance','--plan','--model','--tier','--only','--planning','--exec','--use-model','--ref','--version','--from','--backup','--skip-submodule','--skip-enter','--no-auto','--here','--project','opus+sonnet+haiku','opus+sonnet','sonnet+haiku','sonnet','light','balanced','heavy','max','pro','normal','claude-max','claude-codex-review','codex-max','gemini-max','claude-codex-gemini','glm-max','claude','codex','gemini','glm','kimi','groq','copilot','gguf','--port','--name','zai','kimi-coding','groq','google','anthropic','openai','tavily','brave','ollama','context7','jina')
            'gsd-1' = @('help','status','guide','setup','--dry-run','--model','--plan','claude','codex','claude-codex')
            gguf     = @('serve','chat','list','info','presets','profiles','detect','hint','save','status','stop','help','--balance','--preset','max','high','medium','low','--profile','--engine-path','--model-path','--port','--ctx','--temp','--system','--gpu-layers','--threads','--parallel','--batch','--dry-run')
            remove   = @('claude-code','gsd2','gsd-2','--dry-run','--keep-home','--keep-npm-cache','help')
        }

        if ($count -le 1) {
            # still typing the command name itself -- nothing to complete yet
            return
        }

        if ($count -eq 2) {
            # completing the mode argument
            $partial = $tokens[1]
            $modes | Where-Object { $_ -like "$partial*" } |
                ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
            return
        }

        if ($count -ge 3) {
            $mode = $tokens[1].ToLowerInvariant()
            $partial = $tokens[$count - 1]
            if ($subMap.ContainsKey($mode)) {
                $subMap[$mode] | Where-Object { $_ -like "$partial*" } |
                    ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
            }
        }
    }

    try {
        Register-ArgumentCompleter -CommandName '8sync'  -ScriptBlock $completer -ErrorAction SilentlyContinue
        Register-ArgumentCompleter -CommandName '/8sync' -ScriptBlock $completer -ErrorAction SilentlyContinue
        $script:EightSyncCompleterRegistered = $true
    } catch {}
}
