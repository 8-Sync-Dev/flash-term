# =============================================================================
# 8sync gsd -- plans and preset guidance
# =============================================================================

function Show-GsdPlans {
    Write-Host ''
    Write-HintSection 'GSD Setup -- profiles and model stacks'
    Write-Host ''
    Write-Host '  Preferred style: use --model with one or more brands joined by +.' -ForegroundColor DarkGray
    Write-HintRow '8sync gsd setup --model codex'               'Single-brand stack: only OpenAI/Codex routes are generated'
    Write-HintRow '8sync gsd setup --model codex+glm'           'Cost/perf stack: Codex for planning, GLM for execution/simple workers'
    Write-HintRow '8sync gsd setup --model claude+codex+gemini' 'Big-three stack: Claude planning + Codex/Codex-adjacent planning + Gemini research'
    Write-HintRow '8sync gsd setup --pick'                      'Interactive picker: choose providers with fzf, then auto-generate routing'
    Write-HintRow '8sync gsd setup --auto'                      'No interaction: detect valid logins/keys and generate best available routing'
    Write-Host ''
    Write-Host '  Brand tokens accepted in --model ---------------------------------------' -ForegroundColor DarkGray
    Write-HintRow 'claude'   'Anthropic OAuth; strongest planning/review profile'
    Write-HintRow 'codex'    'OpenAI Codex/OpenAI OAuth; planning-heavy, kept out of exec fallback when unstable'
    Write-HintRow 'gemini'   'Google Gemini CLI OAuth; large context and strong research'
    Write-HintRow 'glm'      'ZAI key; strong execution/cost balance for large repos'
    Write-HintRow 'kimi'     'Kimi Coding key; very strong execution/subagent for price'
    Write-HintRow 'groq'     'Free/cheap worker tier for simple fan-out tasks'
    Write-HintRow 'copilot'  'GitHub Copilot OAuth; unlocks extra Gemini route'
    Write-Host ''
    Write-Host '  Legacy profile presets (still supported) --------------------------------' -ForegroundColor DarkGray
    Write-HintRow 'max'                 'Opus plan + kimi K2.5 exec + groq free workers'
    Write-HintRow 'pro'                 'Sonnet plan/completion + kimi+codex planning + groq free'
    Write-HintRow 'normal'              'No Claude cost: gemini plan + glm-5.1 exec + groq'
    Write-HintRow 'claude-max'          '100% Claude: Opus plan + Sonnet exec + Haiku workers'
    Write-HintRow 'claude-codex-review' 'Claude codes + Codex reviews: Opus plan, Sonnet exec, Codex validation/completion'
    Write-HintRow 'codex-max'           '100% OpenAI: gpt-5.4 plan + gpt-5.3-codex planning-heavy stack'
    Write-HintRow 'gemini-max'          '100% Google: gemini-3.1-pro plan+exec (2M ctx, free)'
    Write-HintRow 'glm-max'             '100% ZAI: glm-5.1 plan/exec + glm-4.x workers; no OAuth needed'
    Write-HintRow 'claude-codex-gemini' 'Best-of-three preset: Claude plan + Codex planning + Gemini research'
    Write-Host ''
    Write-Host '  Real examples -----------------------------------------------------------' -ForegroundColor DarkGray
    Write-Host '  8sync gsd setup --model codex' -ForegroundColor White
    Write-Host '      Use one ecosystem only. Good if you want predictable billing and simple mental model.' -ForegroundColor DarkGray
    Write-Host '  8sync gsd setup --model codex+glm' -ForegroundColor White
    Write-Host '      Good default for large coding projects: keep premium reasoning, offload execution/simple tasks to GLM.' -ForegroundColor DarkGray
    Write-Host '  8sync gsd setup --model claude+codex+gemini --dry-run' -ForegroundColor White
    Write-Host '      Preview the generated routing block before writing ~/.gsd/PREFERENCES.md.' -ForegroundColor DarkGray
    Write-Host '  8sync gsd setup --plan max' -ForegroundColor White
    Write-Host '      Apply the old curated preset directly.' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  Apply: 8sync gsd setup --model <brand[+brand...]>' -ForegroundColor DarkGray
    Write-Host '  Legacy: 8sync gsd setup --plan <name>' -ForegroundColor DarkGray
    Write-Host '  Check : 8sync gsd status   /gsd prefs   /model' -ForegroundColor DarkGray
    Write-Host ''
}
