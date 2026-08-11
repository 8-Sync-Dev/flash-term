# =============================================================================
# 8sync harness -- omp AI coding harness for Windows (port of su-code model)
# =============================================================================
#   8sync .                       Resume the latest omp session in this repo
#   8sync . <name>                Create/resume a NAMED omp session (isolated)
#   8sync . new <name> [--worktree]  Create a fresh session (--worktree = git worktree)
#   8sync . ls   (or --list/--json)  List this repo's named sessions
#   8sync . mv <old> <new>        Rename a session
#   8sync . rm <name> [--force]   Remove a session (--force deletes transcript too)
#   8sync . merge <a> <b> ...     Land session branches into the current branch
#   8sync ai "<prompt>"           omp one-shot or interactive (add --print for stdout)
#   8sync harness                 Deploy skills + project memory + AGENTS.md + readiness
#   8sync harness up              Light refresh (re-deploy skills + consolidate memory)
#   8sync harness global          Deploy skills to ~/.omp (every omp project benefits)
#   8sync harness status          Health: omp, skills, codegraph, MCP, memory
# =============================================================================

# ── omp discovery ────────────────────────────────────────────────────────────

function Find-OmpExe {
    foreach ($name in @('omp', 'omp.exe')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    $local = Join-Path $env:LOCALAPPDATA 'omp\omp.exe'
    if (Test-Path $local) { return $local }
    foreach ($p in @(
        (Join-Path $HOME '.bun\bin\omp.cmd'),
        (Join-Path $HOME 'scoop\shims\omp.exe')
    )) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Get-OmpHome { Join-Path $HOME '.omp' }
function Get-OmpSkillsDir { Join-Path (Get-OmpHome) 'skills' }
function Get-HarnessSessionsRoot { Join-Path $HOME '.8sync\sessions' }

function Get-RepoSlug {
    # Safe directory name for per-project session isolation.
    $cwd = (Get-Location).Path
    $base = Split-Path $cwd -Leaf
    if ([string]::IsNullOrWhiteSpace($base)) { $base = 'default' }
    return ($base -replace '[^A-Za-z0-9._-]', '_')
}

# ── session registry + omp launch  (port of su-code here.rs / session.rs) ───

function Split-OmpArgs {
    # Separate args into omp flags (--key / --key=val / -p) and positionals.
    param([string[]]$Rest)
    $flags = @(); $pos = @()
    foreach ($a in $Rest) {
        if ($a -like '--*' -or $a -in @('-p','-c','-r','-e')) { $flags += $a } else { $pos += $a }
    }
    return @{ Flags = $flags; Positional = $pos }
}

# ── registry (~/.8sync/sessions/<repo-slug>/index.json) ─────────────────────

function Get-SessionKeyDir    { Join-Path (Get-HarnessSessionsRoot) (Get-RepoSlug) }
function Get-SessionIndexPath { Join-Path (Get-SessionKeyDir) 'index.json' }

function Read-SessionRegistry {
    $p = Get-SessionIndexPath
    if (Test-Path $p) {
        try {
            $reg = Get-Content -Raw $p -Encoding UTF8 | ConvertFrom-Json
            if ($null -eq $reg.sessions) {
                $reg | Add-Member -NotePropertyName sessions -NotePropertyValue @() -Force
            }
            return $reg
        } catch {}
    }
    return [pscustomobject]@{ last_used = $null; sessions = @() }
}

function Write-SessionRegistry {
    param($Reg)
    $dir = Get-SessionKeyDir
    $null = New-Item -ItemType Directory -Force -Path $dir -ErrorAction SilentlyContinue
    $sessions = @($Reg.sessions | ForEach-Object {
        $o = [ordered]@{ name = $_.name; session_dir = $_.session_dir; created = $_.created; last_active = $_.last_active }
        if ($_.worktree -and $_.worktree.path) {
            $o['worktree'] = [ordered]@{ path = $_.worktree.path; branch = $_.worktree.branch; base_branch = $_.worktree.base_branch }
        }
        [pscustomobject]$o
    })
    $payload = [ordered]@{ last_used = $Reg.last_used; sessions = $sessions }
    [System.IO.File]::WriteAllText((Get-SessionIndexPath), ($payload | ConvertTo-Json -Depth 6), [System.Text.UTF8Encoding]::new($false))
}

function Test-ValidSessionName {
    # Mirror su-code valid_name (letters, digits, '-', '_', '.'; <=64 chars),
    # plus a path-traversal guard: reject '.'/'..' so session_dir can't escape its key dir.
    param([string]$Name)
    if ($Name -eq '.' -or $Name -eq '..') { return $false }
    return ($Name -match '^[A-Za-z0-9._-]{1,64}$')
}

function Get-SessionByName {
    param($Reg, [string]$Name)
    @($Reg.sessions) | Where-Object { $_.name -eq $Name } | Select-Object -First 1
}

function Update-SessionTouch {
    # Bump last_active + set last_used, then persist.
    param($Reg, [string]$Name)
    $t = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $s = Get-SessionByName -Reg $Reg -Name $Name
    if ($s) { $s.last_active = $t }
    $Reg.last_used = $Name
    Write-SessionRegistry -Reg $Reg
}

# ── omp launch ───────────────────────────────────────────────────────────────

function Invoke-OmpLaunch {
    # Launch omp pinned to $Cwd with --session-dir $Dir.
    # $Fresh = start a NEW conversation (no --continue); otherwise resume.
    # $Flags = passthrough omp flags (--model/--smol/--slow/--plan/--thinking/...).
    # Pinning --cwd matters: omp `/new` inherits the launch root and does not
    # re-detect cwd, so a drifting cwd would land a child session in the wrong project.
    param([string]$Cwd, [string]$Dir, [switch]$Fresh, [string[]]$Flags)
    $omp = Find-OmpExe
    if (-not $omp) {
        Write-Host '  omp not found.' -ForegroundColor Red
        Write-Host '  Install omp first, then run: 8sync harness' -ForegroundColor DarkGray
        return
    }
    if ($Dir) { $null = New-Item -ItemType Directory -Force -Path $Dir -ErrorAction SilentlyContinue }
    $launch = @()
    if ($Flags) { $launch += $Flags }
    $launch += @('--cwd', $Cwd)
    if ($Dir)  { $launch += @('--session-dir', $Dir) }
    if (-not $Fresh) { $launch += '--continue' }
    & $omp @launch
}

# ── session title + relative time ───────────────────────────────────────────

function Get-SessionTitle {
    # Best-effort omp auto-title: first line of the newest *.jsonl in the dir is
    # {"type":"title","title":"..."}.
    param([string]$SessionDir)
    if (-not (Test-Path $SessionDir)) { return $null }
    $newest = $null; $newestTime = [datetime]::MinValue
    try {
        Get-ChildItem -Path $SessionDir -Filter '*.jsonl' -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.LastWriteTime -gt $newestTime) { $newestTime = $_.LastWriteTime; $newest = $_ }
        }
    } catch {}
    if (-not $newest) { return $null }
    try {
        $first = Get-Content $newest.FullName -TotalCount 1 -ErrorAction SilentlyContinue
        if ($first) {
            $v = $first | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($v -and $v.title) { return [string]$v.title }
        }
    } catch {}
    return $null
}

function Get-AgoString {
    param([long]$Secs)
    $d = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $Secs
    if ($d -lt 0) { $d = 0 }
    if     ($d -lt 60)    { return ("{0}s ago" -f $d) }
    elseif ($d -lt 3600)  { return ("{0}m ago" -f [int]($d / 60)) }
    elseif ($d -lt 86400) { return ("{0}h ago" -f [int]($d / 3600)) }
    else                  { return ("{0}d ago" -f [int]($d / 86400)) }
}

# ── git helpers ──────────────────────────────────────────────────────────────

function Invoke-GitCapture {
    param([string]$Dir, [string[]]$GitArgs)
    $git = Get-RealGitExe
    if (-not $git) { return [pscustomobject]@{ Ok = $false; Output = 'git not found' } }
    try {
        $output = & $git -C $Dir @GitArgs 2>&1 | Out-String
        return [pscustomobject]@{ Ok = ($LASTEXITCODE -eq 0); Output = $output.Trim() }
    } catch {
        return [pscustomobject]@{ Ok = $false; Output = $_.Exception.Message }
    }
}

function Get-CurrentBranch {
    param([string]$Root)
    $r = Invoke-GitCapture -Dir $Root -GitArgs @('rev-parse','--abbrev-ref','HEAD')
    if (-not $r.Ok) { return $null }
    $b = $r.Output.Trim()
    if ($b -eq 'HEAD') {
        $r2 = Invoke-GitCapture -Dir $Root -GitArgs @('rev-parse','HEAD')
        if ($r2.Ok -and $r2.Output) { return $r2.Output.Trim().Substring(0, [Math]::Min(7,$r2.Output.Trim().Length)) }
        return $null
    }
    return $b
}

function Test-WorktreeDirty {
    param([string]$Dir)
    $r = Invoke-GitCapture -Dir $Dir -GitArgs @('status','--porcelain')
    return ($r.Ok -and $r.Output.Trim() -ne '')
}

function New-SessionWorktree {
    # Create a git worktree + branch 8sync/<name> off the current HEAD.
    param([string]$Root, [string]$Name)
    $wtPath = Join-Path (Get-SessionKeyDir) (Join-Path 'worktrees' $Name)
    $null = New-Item -ItemType Directory -Force -Path (Split-Path $wtPath) -ErrorAction SilentlyContinue
    $branch = "8sync/$Name"
    $base = Get-CurrentBranch -Root $Root
    $exists = Invoke-GitCapture -Dir $Root -GitArgs @('show-ref','--verify','--quiet',"refs/heads/$branch")
    if ($exists.Ok) {
        $r = Invoke-GitCapture -Dir $Root -GitArgs @('worktree','add',$wtPath,$branch)
    } else {
        $r = Invoke-GitCapture -Dir $Root -GitArgs @('worktree','add','-b',$branch,$wtPath,'HEAD')
    }
    if (-not $r.Ok) {
        Write-Host ("  worktree create failed: {0}" -f $r.Output) -ForegroundColor Red
        return $null
    }
    Write-Host ("  worktree {0} -> branch {1} (base {2})" -f $wtPath, $branch, $base) -ForegroundColor DarkGray
    return [pscustomobject]@{ path = $wtPath; branch = $branch; base_branch = $base }
}

# ── session commands ─────────────────────────────────────────────────────────

function Resume-LatestSession {
    param([string[]]$Flags)
    $reg = Read-SessionRegistry
    if ($reg.last_used) {
        $s = Get-SessionByName -Reg $reg -Name $reg.last_used
        if ($s) {
            $cwd = if ($s.worktree -and $s.worktree.path) { $s.worktree.path } else { (Get-Location).Path }
            Write-Host ("  -> resume session '{0}' (latest)" -f $s.name) -ForegroundColor Green
            Update-SessionTouch -Reg $reg -Name $s.name
            Invoke-OmpLaunch -Cwd $cwd -Dir $s.session_dir -Flags $Flags
            return
        }
    }
    # No named session yet — omp default store (legacy 8sync . behavior).
    Write-Host '  omp: resuming latest session...' -ForegroundColor DarkGray
    Invoke-OmpLaunch -Cwd (Get-Location).Path -Dir '' -Flags $Flags
}

function Resume-NamedSession {
    param([string]$Name, [string[]]$Flags)
    if (-not (Test-ValidSessionName -Name $Name)) {
        Write-Host ("  invalid session name '{0}' (use letters, digits, '-', '_', '.'; <=64 chars)" -f $Name) -ForegroundColor Red
        return
    }
    $reg = Read-SessionRegistry
    $s = Get-SessionByName -Reg $reg -Name $Name
    if ($s) {
        $cwd = if ($s.worktree -and $s.worktree.path) { $s.worktree.path } else { (Get-Location).Path }
        Write-Host ("  -> resume session '{0}'" -f $Name) -ForegroundColor Green
        Update-SessionTouch -Reg $reg -Name $Name
        Invoke-OmpLaunch -Cwd $cwd -Dir $s.session_dir -Flags $Flags
    } else {
        Write-Host ("  no session '{0}' yet -- creating it" -f $Name) -ForegroundColor Cyan
        New-NamedSession -Name $Name -Worktree:$false -Flags $Flags
    }
}

function New-NamedSession {
    param([string]$Name, [switch]$Worktree, [string[]]$Flags)
    if (-not (Test-ValidSessionName -Name $Name)) {
        Write-Host ("  invalid session name '{0}' (use letters, digits, '-', '_', '.'; <=64 chars)" -f $Name) -ForegroundColor Red
        return
    }
    $reg = Read-SessionRegistry
    if (Get-SessionByName -Reg $reg -Name $Name) {
        Write-Host ("  session '{0}' already exists -- resume with: 8sync . {0}" -f $Name) -ForegroundColor Yellow
        return
    }
    $dir = Join-Path (Get-SessionKeyDir) ($Name -replace '[^A-Za-z0-9._-]','_')
    $null = New-Item -ItemType Directory -Force -Path $dir -ErrorAction SilentlyContinue
    $wt = $null
    if ($Worktree) {
        if (-not (Test-Path '.git')) {
            Write-Host '  --worktree needs a git repo (no .git here)' -ForegroundColor Red
            return
        }
        $wt = New-SessionWorktree -Root (Get-Location).Path -Name $Name
        if (-not $wt) { return }   # worktree failed — abort session create
    }
    $t = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $reg.sessions = @(@($reg.sessions) + [pscustomobject]@{ name=$Name; session_dir=$dir; worktree=$wt; created=$t; last_active=$t })
    Write-Host ("  created session '{0}'" -f $Name) -ForegroundColor Green
    Update-SessionTouch -Reg $reg -Name $Name
    $cwd = if ($wt -and $wt.path) { $wt.path } else { (Get-Location).Path }
    Invoke-OmpLaunch -Cwd $cwd -Dir $dir -Fresh -Flags $Flags
}

function Get-OtherRepoSessionCount {
    # Sessions stored under OTHER repo slugs (helps the "where are my sessions?" case).
    $root = Get-HarnessSessionsRoot
    if (-not (Test-Path $root)) { return 0 }
    $count = 0
    Get-ChildItem $root -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $idx = Join-Path $_.FullName 'index.json'
        if (Test-Path $idx) {
            try { $r = Get-Content -Raw $idx -Encoding UTF8 | ConvertFrom-Json; if ($r.sessions) { $count += @($r.sessions).Count } } catch {}
        }
    }
    return $count
}

function Show-AllSessions {
    # List every named session across all repo slugs under ~/.8sync/sessions.
    param([switch]$Json)
    $root = Get-HarnessSessionsRoot
    if (-not (Test-Path $root)) {
        Write-Host '  no sessions anywhere -- create one: 8sync . new <name>' -ForegroundColor Cyan
        return
    }
    $all = @()
    Get-ChildItem $root -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $idx = Join-Path $_.FullName 'index.json'
        if (Test-Path $idx) {
            try {
                $r = Get-Content -Raw $idx -Encoding UTF8 | ConvertFrom-Json
                $repoSlug = $_.Name
                foreach ($s in $r.sessions) {
                    $all += [pscustomobject]@{
                        repo = $repoSlug; name = $s.name; last_active = $s.last_active
                        last_used = ($r.last_used -eq $s.name)
                        title = (Get-SessionTitle -SessionDir $s.session_dir)
                        branch = $(if ($s.worktree) { $s.worktree.branch } else { $null })
                        session_dir = $s.session_dir
                    }
                }
            } catch {}
        }
    }
    if ($Json) {
        $all | ForEach-Object {
            [ordered]@{ repo=$_.repo; name=$_.name; last_active=$_.last_active; last_used=$_.last_used; title=$_.title; branch=$_.branch; session_dir=$_.session_dir }
        } | ConvertTo-Json -Depth 5
        return
    }
    if ($all.Count -eq 0) {
        Write-Host '  no sessions anywhere -- create one: 8sync . new <name>' -ForegroundColor Cyan
        return
    }
    $repoCount = @($all | ForEach-Object { $_.repo } | Select-Object -Unique).Count
    Write-Host ''
    Write-Host '  all sessions (--all)' -ForegroundColor Cyan
    $all | Sort-Object last_active -Descending | ForEach-Object {
        $star = if ($_.last_used) { '*' } else { ' ' }
        $title = if ($_.title) { $_.title } else { '(no messages yet)' }
        Write-Host ("  {0} {1,-16}/{2,-16} {3,-9} {4}" -f $star, $_.repo, $_.name, (Get-AgoString -Secs $_.last_active), $title) -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Host ("  total: {0} session(s) across {1} repo(s)   |   resume by name: cd into the repo, then 8sync . <name>" -f $all.Count, $repoCount) -ForegroundColor DarkGray
    Write-Host ''
}

function Show-SessionList {
    param([switch]$Json, [switch]$All)
    if ($All) { Show-AllSessions -Json:$Json; return }
    $reg = Read-SessionRegistry
    if ($Json) {
        $arr = @($reg.sessions | ForEach-Object {
            [ordered]@{
                name       = $_.name
                last_used  = ($reg.last_used -eq $_.name)
                last_active= $_.last_active
                title      = (Get-SessionTitle -SessionDir $_.session_dir)
                branch     = $(if ($_.worktree) { $_.worktree.branch } else { $null })
                dirty      = $(if ($_.worktree) { Test-WorktreeDirty -Dir $_.worktree.path } else { $null })
                worktree   = $(if ($_.worktree) { $_.worktree.path } else { $null })
                session_dir= $_.session_dir
            }
        })
        $arr | ConvertTo-Json -Depth 5
        return
    }
    if (-not $reg.sessions -or @($reg.sessions).Count -eq 0) {
        Write-Host ("  no named sessions in this repo ({0})" -f (Get-RepoSlug)) -ForegroundColor Cyan
        $other = Get-OtherRepoSessionCount
        if ($other -gt 0) {
            Write-Host ("  {0} session(s) exist in OTHER repos -- see all: 8sync . ls --all" -f $other) -ForegroundColor DarkYellow
        } else {
            Write-Host '  create one: 8sync . new <name>' -ForegroundColor DarkGray
        }
        return
    }
    Write-Host ''
    Write-Host ('  sessions . ' + (Get-Location).Path) -ForegroundColor Cyan
    foreach ($s in $reg.sessions) {
        $star = if ($reg.last_used -eq $s.name) { '*' } else { ' ' }
        $title = Get-SessionTitle -SessionDir $s.session_dir
        if (-not $title) { $title = '(no messages yet)' }
        if ($s.worktree) {
            $dirtyMark = if (Test-WorktreeDirty -Dir $s.worktree.path) { ' *dirty' } else { '' }
            $loc = "$($s.worktree.branch)$dirtyMark"
        } else { $loc = '-' }
        Write-Host ("  {0} {1,-18} {2,-9} {3,-24} {4}" -f $star, $s.name, (Get-AgoString -Secs $s.last_active), $loc, $title) -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Host '  resume: 8sync . <name>   new: 8sync . new <name> [--worktree]   rm: 8sync . rm <name> [--force]   all: 8sync . ls --all' -ForegroundColor DarkGray
    Write-Host ''
}

function Remove-Session {
    param([string]$Name, [switch]$Force)
    $reg = Read-SessionRegistry
    $idx = -1
    $list = [System.Collections.ArrayList]@($reg.sessions)
    for ($i = 0; $i -lt $list.Count; $i++) { if ($list[$i].name -eq $Name) { $idx = $i; break } }
    if ($idx -lt 0) {
        Write-Host ("  no session '{0}' in this repo" -f $Name) -ForegroundColor Yellow
        return
    }
    $s = $list[$idx]
    if ($s.worktree -and $s.worktree.path) {
        if ((Test-WorktreeDirty -Dir $s.worktree.path) -and -not $Force) {
            Write-Host ("  session '{0}' worktree has uncommitted changes at {1} -- commit/merge first, or: 8sync . rm {0} --force" -f $Name, $s.worktree.path) -ForegroundColor Red
            return
        }
        $wtArgs = [System.Collections.ArrayList]@('worktree','remove',$s.worktree.path)
        if ($Force) { $null = $wtArgs.Add('--force') }
        $r = Invoke-GitCapture -Dir (Get-Location).Path -GitArgs $wtArgs
        if ($r.Ok) { Write-Host ("  removed worktree {0}" -f $s.worktree.path) -ForegroundColor Green }
        else { Write-Host ("  could not remove worktree {0} (unregistering anyway)" -f $s.worktree.path) -ForegroundColor DarkYellow }
        $del = if ($Force) { '-D' } else { '-d' }
        $rb = Invoke-GitCapture -Dir (Get-Location).Path -GitArgs @('branch',$del,$s.worktree.branch)
        if ($rb.Ok) { Write-Host ("  deleted branch {0}" -f $s.worktree.branch) -ForegroundColor Green }
        else { Write-Host ("  branch {0} kept (unmerged?) -- git branch -D {0} to force" -f $s.worktree.branch) -ForegroundColor DarkYellow }
    }
    if (-not $Force) {
        Write-Host ("  unregistering '{0}' but KEEPING its transcript at {1} -- use --force to delete it too" -f $Name, $s.session_dir) -ForegroundColor DarkYellow
    } else {
        Remove-Item -Recurse -Force $s.session_dir -ErrorAction SilentlyContinue
        Write-Host ("  deleted transcript store {0}" -f $s.session_dir) -ForegroundColor Green
    }
    $list.RemoveAt($idx)
    $reg.sessions = $list.ToArray()
    if ($reg.last_used -eq $Name) { $reg.last_used = $null }
    Write-SessionRegistry -Reg $reg
    Write-Host ("  removed session '{0}'" -f $Name) -ForegroundColor Green
}

function Rename-Session {
    param([string]$Old, [string]$New)
    if (-not (Test-ValidSessionName -Name $New)) {
        Write-Host ("  invalid session name '{0}' (use letters, digits, '-', '_', '.'; <=64 chars)" -f $New) -ForegroundColor Red
        return
    }
    $reg = Read-SessionRegistry
    if (Get-SessionByName -Reg $reg -Name $New) {
        Write-Host ("  session '{0}' already exists" -f $New) -ForegroundColor Yellow
        return
    }
    $idx = -1
    for ($i = 0; $i -lt @($reg.sessions).Count; $i++) { if ($reg.sessions[$i].name -eq $Old) { $idx = $i; break } }
    if ($idx -lt 0) {
        Write-Host ("  no session '{0}' in this repo" -f $Old) -ForegroundColor Yellow
        return
    }
    $s = $reg.sessions[$idx]
    $newDir = Join-Path (Get-SessionKeyDir) ($New -replace '[^A-Za-z0-9._-]','_')
    if (Test-Path $s.session_dir) {
        try { Move-Item -Path $s.session_dir -Destination $newDir -Force }
        catch { Write-Host ("  rename dir failed: {0}" -f $_.Exception.Message) -ForegroundColor Red; return }
    }
    $s.name = $New
    $s.session_dir = $newDir
    if ($s.worktree -and $s.worktree.path) {
        $newBranch = "8sync/$New"
        $newWt = Join-Path (Get-SessionKeyDir) (Join-Path 'worktrees' $New)
        $rm = Invoke-GitCapture -Dir (Get-Location).Path -GitArgs @('worktree','move',$s.worktree.path,$newWt)
        if ($rm.Ok) { $s.worktree.path = $newWt }
        else { Write-Host ("  could not move worktree {0}" -f $s.worktree.path) -ForegroundColor DarkYellow }
        $rb = Invoke-GitCapture -Dir (Get-Location).Path -GitArgs @('branch','-m',$s.worktree.branch,$newBranch)
        if ($rb.Ok) { $s.worktree.branch = $newBranch }
        else { Write-Host ("  could not rename branch {0}" -f $s.worktree.branch) -ForegroundColor DarkYellow }
    }
    if ($reg.last_used -eq $Old) { $reg.last_used = $New }
    Write-SessionRegistry -Reg $reg
    Write-Host ("  renamed session '{0}' -> '{1}'" -f $Old, $New) -ForegroundColor Green
}

function Merge-SessionBranches {
    # Land session branches into the current branch, ECC-style: read-only
    # merge-tree preflight -> rebase-to-unblock -> merge -> cleanup.
    param([string[]]$Names, [switch]$KeepWorktree)
    if (-not $Names -or $Names.Count -eq 0) {
        Write-Host '  usage: 8sync . merge <name> [<name>...]  (lands each session branch into the current branch)' -ForegroundColor Yellow
        return
    }
    $root = (Get-Location).Path
    if (-not (Test-Path '.git')) {
        Write-Host "  merge needs a git repo at $root" -ForegroundColor Red
        return
    }
    if (Test-WorktreeDirty -Dir $root) {
        Write-Host '  main working tree has uncommitted changes -- commit or stash before merging' -ForegroundColor Red
        return
    }
    $target = Get-CurrentBranch -Root $root
    Write-Host "  merge -> $target" -ForegroundColor Cyan
    $reg = Read-SessionRegistry
    foreach ($name in $Names) {
        $s = Get-SessionByName -Reg $reg -Name $name
        if (-not $s) { Write-Host "  no session '$name' -- skipped" -ForegroundColor DarkYellow; continue }
        if (-not ($s.worktree -and $s.worktree.branch)) { Write-Host "  session '$name' has no worktree/branch -- skipped" -ForegroundColor DarkYellow; continue }
        $w = $s.worktree
        if ($w.branch -eq $target) { Write-Host "  session '$name' is on the target branch '$target' -- skipped" -ForegroundColor DarkYellow; continue }
        if (Test-WorktreeDirty -Dir $w.path) { Write-Host "  '$name' has uncommitted changes at $($w.path) -- commit first, skipped" -ForegroundColor Red; continue }
        $pf = Invoke-GitCapture -Dir $root -GitArgs @('merge-tree','--write-tree','--name-only',$target,$w.branch)
        if (-not $pf.Ok) {
            Write-Host "  '$name' ($($w.branch)) conflicts with $target -- rebasing to unblock" -ForegroundColor DarkYellow
            $rb = Invoke-GitCapture -Dir $w.path -GitArgs @('rebase',$target)
            if ($rb.Ok) { Write-Host "  rebased $($w.branch) onto $target" -ForegroundColor Green }
            else {
                $null = Invoke-GitCapture -Dir $w.path -GitArgs @('rebase','--abort')
                Write-Host "  '$name' still conflicts after rebase -- resolve in $($w.path), re-run" -ForegroundColor Red
                continue
            }
            $pf2 = Invoke-GitCapture -Dir $root -GitArgs @('merge-tree','--write-tree','--name-only',$target,$w.branch)
            if (-not $pf2.Ok) { Write-Host "  '$name' still conflicts -- skipped" -ForegroundColor Red; continue }
        }
        $mg = Invoke-GitCapture -Dir $root -GitArgs @('merge','--no-edit',$w.branch)
        if ($mg.Ok) { Write-Host "  merged '$name' ($($w.branch)) -> $target" -ForegroundColor Green }
        else {
            $null = Invoke-GitCapture -Dir $root -GitArgs @('merge','--abort')
            Write-Host "  merge of '$name' failed -- skipped" -ForegroundColor Red
            continue
        }
        if ($KeepWorktree) {
            Write-Host "  kept worktree $($w.path) + branch $($w.branch) (--keep-worktree)" -ForegroundColor Cyan
        } else {
            $null = Invoke-GitCapture -Dir $root -GitArgs @('worktree','remove','--force',$w.path)
            $null = Invoke-GitCapture -Dir $root -GitArgs @('branch','-d',$w.branch)
            $tmp = [System.Collections.ArrayList]@($reg.sessions)
            for ($i = 0; $i -lt $tmp.Count; $i++) {
                if ($tmp[$i].name -eq $name) { Remove-Item -Recurse -Force $tmp[$i].session_dir -ErrorAction SilentlyContinue; $tmp.RemoveAt($i); break }
            }
            $reg.sessions = $tmp.ToArray()
            if ($reg.last_used -eq $name) { $reg.last_used = $null }
            Write-Host "  cleaned up session '$name' (worktree + branch + transcript)" -ForegroundColor Green
        }
        Write-SessionRegistry -Reg $reg
    }
    Write-Host '  merge complete' -ForegroundColor Green
}

function Invoke-OmpSession {
    # `8sync .` session hub -- port of su-code here.rs/session.rs.
    #   8sync .                          resume the latest session (or omp default)
    #   8sync . <name>                   create-or-resume a named session
    #   8sync . new <name> [--worktree]  create a fresh session (--worktree = git worktree)
    #   8sync . ls  (or --list/--ls/--json)  list this repo's sessions; --all = every repo
    #   8sync . mv <old> <new>           rename a session
    #   8sync . rm <name> [--force]      remove a session (--force deletes transcript too)
    #   8sync . merge <a> <b> ...        land session branches into the current branch
    # Trailing --model/--smol/--slow/--plan/--thinking/etc. pass through to omp.
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Rest
    )
    $omp = Find-OmpExe
    if (-not $omp) {
        Write-Host '  omp not found.' -ForegroundColor Red
        Write-Host '  Install omp first, then run: 8sync harness' -ForegroundColor DarkGray
        return
    }
    $s = Split-OmpArgs -Rest $Rest
    $worktreeFlag = $s.Flags -contains '--worktree'
    $forceFlag    = $s.Flags -contains '--force'
    $keepWtFlag   = $s.Flags -contains '--keep-worktree'
    $allFlag      = $s.Flags -contains '--all'
    $listFlag     = $allFlag -or $s.Flags -contains '--list' -or $s.Flags -contains '--ls' -or $s.Flags -contains '--json'
    $jsonFlag     = $s.Flags -contains '--json'
    $flags = @($s.Flags | Where-Object { $_ -notin @('--worktree','--force','--keep-worktree','--list','--ls','--json','--all') })
    $pos = @($s.Positional)

    $verb = if ($pos.Count -gt 0) { $pos[0] } else { '' }

    # Reserved verbs can't be session names.
    switch ($verb) {
        'ls'    { Show-SessionList -Json:$jsonFlag -All:$allFlag; return }
        'list'  { Show-SessionList -Json:$jsonFlag -All:$allFlag; return }
        'rm'    {
            if ($pos.Count -lt 2) { Write-Host '  usage: 8sync . rm <name> [--force]' -ForegroundColor Yellow; return }
            Remove-Session -Name $pos[1] -Force:$forceFlag; return
        }
        'mv'    {
            if ($pos.Count -lt 3) { Write-Host '  usage: 8sync . mv <old> <new>' -ForegroundColor Yellow; return }
            Rename-Session -Old $pos[1] -New $pos[2]; return
        }
        'merge' {
            $names = if ($pos.Count -gt 1) { $pos[1..($pos.Count-1)] } else { @() }
            Merge-SessionBranches -Names $names -KeepWorktree:$keepWtFlag; return
        }
        'new'   {
            if ($pos.Count -lt 2) { Write-Host '  usage: 8sync . new <name> [--worktree]' -ForegroundColor Yellow; return }
            New-NamedSession -Name $pos[1] -Worktree:$worktreeFlag -Flags $flags; return
        }
        default {}
    }

    if ($listFlag) { Show-SessionList -Json:$jsonFlag -All:$allFlag; return }

    if ($verb -eq '') {
        Resume-LatestSession -Flags $flags
    } else {
        Resume-NamedSession -Name $verb -Flags $flags
    }
}

function Invoke-AiCommand {
    # `8sync ai [prompt]` -- one-shot or interactive. Pass-through model flags.
    #   8sync ai "fix the bug" --model glm --thinking high
    #   8sync ai "summarize" -p            # one-shot print mode
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Rest
    )
    $omp = Find-OmpExe
    if (-not $omp) {
        Write-Host '  omp not found. Install omp first, then: 8sync harness' -ForegroundColor Red
        return
    }
    $printMode = $Rest -contains '--print' -or $Rest -contains '-p'
    $s = Split-OmpArgs -Rest $Rest
    $flags = @($s.Flags | Where-Object { $_ -notin @('--print', '-p') })
    $prompt = ($s.Positional -join ' ').Trim()
    if ($printMode) {
        if (-not $prompt) { Write-Host '  --print requires a prompt.' -ForegroundColor DarkYellow; return }
        & $omp @($flags + @('-p', $prompt))
    } elseif ($prompt) {
        & $omp @($flags + @($prompt))
    } else {
        Write-Host '  omp: resuming latest session...' -ForegroundColor DarkGray
        & $omp @($flags + @('--continue'))
    }
}

# ── workflow verbs (port of su-code daily flow) ────────────────────────────

function Invoke-FindCommand {
    # `8sync find [kw]` -- rg/fd + fzf -> open in $EDITOR (fallback hx/helix/vi).
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Rest
    )
    $kw = ($Rest -join ' ').Trim()
    $files = $null
    if (Test-CommandExists 'rg') {
        if ($kw) {
            $files = rg --files 2>$null | Where-Object { $_ -like "*$kw*" }
        } else {
            $files = rg --files 2>$null
        }
    } else {
        $files = Get-ChildItem -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
    }
    if (-not $files -or $files.Count -eq 0) { Write-Host '  no files matched.' -ForegroundColor DarkYellow; return }
    $pick = if ((Test-CommandExists 'fzf') -and $files.Count -gt 1) {
        $files | fzf --height=45% --layout=reverse --prompt='Open> '
    } else { $files | Select-Object -First 1 }
    if (-not $pick) { return }
    $ed = $env:EDITOR; if (-not $ed) { foreach ($c in @('hx','helix','vi','code')) { if (Test-CommandExists $c) { $ed = $c; break } } }
    if ($ed) { & $ed $pick } else { Write-Host "  no editor found. File: $pick" -ForegroundColor DarkYellow }
}

function Invoke-NoteCommand {
    # `8sync note "msg" [-t tag]` -- append to 8sync/NOTES.md.
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Rest
    )
    $tag = $null
    $tagIdx = [Array]::IndexOf($Rest, '-t'); if ($tagIdx -lt 0) { $tagIdx = [Array]::IndexOf($Rest, '--tag') }
    if ($tagIdx -ge 0 -and $tagIdx + 1 -lt $Rest.Count) { $tag = $Rest[$tagIdx + 1] }
    $msg = @($Rest | Where-Object { $_ -notin @('-t','--tag',$tag) }) -join ' '
    if (-not $msg) { Write-Host '  Usage: 8sync note "your message" [-t tag]' -ForegroundColor DarkYellow; return }
    $dir = Get-ProjectHarnessDir; $null = New-Item -ItemType Directory -Force -Path $dir -ErrorAction SilentlyContinue
    $f = Join-Path $dir 'NOTES.md'
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm')
    $line = "- [$ts]$(if ($tag) { " #$tag" }) $msg"
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::AppendAllText($f, ($line + "`n"), $utf8NoBom)
    Write-Host "  noted -> 8sync/NOTES.md" -ForegroundColor Green
}

function Invoke-RunCommand {
    # `8sync run [dev|build|test|fmt|lint]` -- detect project type + run recipe.
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Rest
    )
    $verb = if ($Rest.Count -gt 0) { $Rest[0].ToLowerInvariant() } else { 'dev' }
    $recipe = $null
    if     (Test-Path 'package.json')  { $recipe = @{ dev='npm run dev'; build='npm run build'; test='npm test'; fmt='npm run fmt'; lint='npm run lint' } }
    elseif (Test-Path 'Cargo.toml')    { $recipe = @{ dev='cargo run'; build='cargo build'; test='cargo test'; fmt='cargo fmt'; lint='cargo clippy' } }
    elseif (Test-Path 'go.mod')        { $recipe = @{ dev='go run .'; build='go build'; test='go test ./...'; fmt='gofmt -w .'; lint='go vet ./...' } }
    elseif (Test-Path 'pyproject.toml' -or (Test-Path '*.py')) { $recipe = @{ dev='python .'; build='pip install -e .'; test='pytest'; fmt='black .'; lint='ruff check .' } }
    if (-not $recipe -or -not $recipe.Contains($verb)) {
        Write-Host "  no recipe for '$verb' (detected: $(if($recipe){'project'}else{'none'}))." -ForegroundColor DarkYellow
        return
    }
    Write-Host "  > $($recipe[$verb])" -ForegroundColor Cyan
    Invoke-Expression $recipe[$verb]
}

function Invoke-ShipCommand {
    # `8sync ship "msg"` -- git add -A && commit && push (+ optional gh pr create with --pr).
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Rest
    )
    $git = Get-RealGitExe
    if (-not $git -or -not (Test-Path '.git')) { Write-Host '  not a git repo.' -ForegroundColor DarkYellow; return }
    $msg = ($Rest | Where-Object { $_ -ne '--pr' }) -join ' '
    $wantPr = $Rest -contains '--pr'
    if (-not $msg) { Write-Host '  Usage: 8sync ship "commit message" [--pr]' -ForegroundColor DarkYellow; return }
    & $git add -A
    & $git commit -m $msg
    if ($LASTEXITCODE -ne 0) { Write-Host '  commit failed (nothing to commit?).' -ForegroundColor DarkYellow; return }
    & $git push
    if ($wantPr -and (Test-CommandExists 'gh')) {
        $gh = (Get-Command gh -ErrorAction SilentlyContinue).Source
        & $gh pr create --fill 2>&1 | Out-Host
    }
}

function Invoke-DoctorCommand {
    # `8sync doctor` -- health: omp, wezterm, scoop, git, tools, skills, memory.
    $r = Get-HarnessReadiness
    Write-Host ''
    Write-Host '  8SYNC DOCTOR' -ForegroundColor Cyan
    Write-Host ''
    function Row($label, $ok, $detail) {
        $mark = if ($ok) { '[ok]   ' } else { '[miss] ' }
        $color = if ($ok) { 'Green' } else { 'DarkYellow' }
        Write-Host ("  $mark{0,-10} {1}" -f $label, $detail) -ForegroundColor $color
    }
    Row 'omp'      $r.OmpFound   $r.Omp
    Row 'wezterm'  ([bool](Get-Command wezterm -ErrorAction SilentlyContinue)) 'terminal'
    Row 'scoop'    ([bool](Get-ScoopCommand)) 'tool manager'
    $git = Get-RealGitExe; Row 'git' ([bool]$git) $(if($git){$git}else{'not found'})
    Row 'pwsh'     ($PSVersionTable.PSVersion.Major -ge 5) ('PS ' + $PSVersionTable.PSVersion)
    Row 'skills'   ($r.SkillCount -gt 0) ("$($r.SkillCount) in ~/.omp/skills")
    Row 'agents'   ($r.AgentsCount -gt 0) ("$($r.AgentsCount) omp subagents")
    Row 'codegraph' $r.Codegraph $(if($r.Codegraph){'available'}else{'optional'})
    Row 'gitleaks' $r.Gitleaks  $(if($r.Gitleaks){'available'}else{'optional'})
    $mem = Get-ProjectHarnessDir; Row 'memory' (Test-Path (Join-Path $mem 'PROJECT.md')) $(if(Test-Path $mem){$mem}else{'run: 8sync harness'})
    Write-Host ''
    Write-Host '  8sync . to start coding.' -ForegroundColor Green
    Write-Host ''
}

# ── project memory + managed .gitignore ─────────────────────────────────────

function Get-ProjectHarnessDir { Join-Path (Get-Location) '8sync' }

function Get-MemoryTemplate {
    param([string]$Kind)
    switch ($Kind) {
        'PROJECT' {
            return @"
# PROJECT

**One-liner:** _describe this project in one line_

## Tech stack
- _add: language, framework, runtime, package manager_

## Goals
- _what success looks like_

## Constraints
- _hard limits: performance, RAM, OS, deadlines_
"@
        }
        'STATE' {
            return @"
# STATE

**Goal:** _current objective_
**Phase:** _discuss | plan | execute | verify | complete_

## Checklist
- [ ] _step 1_
- [ ] _step 2_

## Current
_where you are right now_

## Next
_the single next concrete action_
"@
        }
        'KNOWLEDGE' {
            return @"
# KNOWLEDGE

Reusable conventions, gotchas, architecture lessons learned while working here.
Append `## YYYY-MM-DD` dated entries. Distill failures (`failure:`) and validated
flows (`validated:`) so future sessions don't repeat them.
"@
        }
    }
    return ''
}

function Initialize-ProjectMemory {
    param([switch]$DryRun)
    $dir = Get-ProjectHarnessDir
    if (-not (Test-Path $dir)) {
        if ($DryRun) { Write-Host "  [dry-run] would create $dir\" -ForegroundColor Yellow; return }
        $null = New-Item -ItemType Directory -Force -Path $dir
    }
    foreach ($kind in @('PROJECT', 'STATE', 'KNOWLEDGE')) {
        $f = Join-Path $dir "$kind.md"
        if (Test-Path $f) {
            Write-Host "  [ok]     8sync/$kind.md exists (kept)" -ForegroundColor DarkGray
        } else {
            if ($DryRun) { Write-Host "  [dry-run] would seed 8sync/$kind.md" -ForegroundColor Yellow; continue }
            [System.IO.File]::WriteAllText($f, (Get-MemoryTemplate -Kind $kind), [System.Text.UTF8Encoding]::new($false))
            Write-Host "  [ok]     seeded 8sync/$kind.md" -ForegroundColor Green
        }
    }
}

function Initialize-ManagedGitignore {
    # Add a managed block to the project .gitignore (idempotent).
    param([switch]$DryRun)
    $gi = Join-Path (Get-Location) '.gitignore'
    $marker = '# -- 8sync harness (managed) --'
    $block = @"
$marker
.codegraph/
.cache/
8sync/skills/
.env
.env.*
!.env.example
# -- /8sync harness --
"@
    $existing = if (Test-Path $gi) { Get-Content -Raw $gi } else { '' }
    if ($existing -match [regex]::Escape($marker)) {
        Write-Host '  [ok]     .gitignore: harness block present' -ForegroundColor DarkGray
        return
    }
    if ($DryRun) { Write-Host '  [dry-run] would append harness block to .gitignore' -ForegroundColor Yellow; return }
    $content = if ($existing) { $existing.TrimEnd() + "`n`n" + $block + "`n" } else { $block + "`n" }
    [System.IO.File]::WriteAllText($gi, $content, [System.Text.UTF8Encoding]::new($false))
    Write-Host '  [ok]     .gitignore: harness block added' -ForegroundColor Green
}

# ── codegraph / MCP readiness ───────────────────────────────────────────────

function Get-HarnessReadiness {
    $omp = Find-OmpExe
    $ompVer = if ($omp) { (& $omp --version 2>$null | Select-Object -First 1) } else { 'not installed' }
    $skillsDir = Get-OmpSkillsDir
    $skillCount = if (Test-Path $skillsDir) { @(Get-ChildItem $skillsDir -Directory -ErrorAction SilentlyContinue).Count } else { 0 }
    $codegraph = [bool](Get-Command codegraph -ErrorAction SilentlyContinue)
    $gitleaks  = [bool](Get-Command gitleaks -ErrorAction SilentlyContinue)

    # omp native state: config at ~/.omp/agent/config.yml; subagents at ~/.omp/agent/agents
    $agentDir    = Join-Path (Get-OmpHome) 'agent'
    $configPath  = Join-Path $agentDir 'config.yml'
    $agentsDir   = Join-Path $agentDir 'agents'
    $agentsCount = if (Test-Path $agentsDir) { @(Get-ChildItem $agentsDir -Filter '*.md' -ErrorAction SilentlyContinue).Count } else { 0 }

    return [pscustomobject]@{
        Omp         = if ($omp) { $ompVer } else { 'not installed' }
        OmpFound    = [bool]$omp
        SkillsDir   = $skillsDir
        SkillCount  = $skillCount
        Codegraph   = $codegraph
        ConfigPath  = $configPath
        ConfigFound = (Test-Path $configPath)
        AgentsCount = $agentsCount
        Gitleaks    = $gitleaks
    }
}

# ── harness verbs ───────────────────────────────────────────────────────────

function Invoke-HarnessInit {
    param([switch]$DryRun)
    Write-Host '  [1/3] Skills -> ~/.omp/skills ...' -ForegroundColor Cyan
    if (Get-Command Invoke-SkillDeploy -ErrorAction SilentlyContinue) {
        Invoke-SkillDeploy -DryRun:$DryRun
    } else {
        Write-Host '  [skip]   skill deployer not loaded (agents/00-shared)' -ForegroundColor DarkYellow
    }
    Write-Host ''
    Write-Host '  [2/3] Project memory (8sync/) ...' -ForegroundColor Cyan
    Initialize-ProjectMemory -DryRun:$DryRun
    Write-Host ''
    Write-Host '  [3/3] Managed .gitignore ...' -ForegroundColor Cyan
    Initialize-ManagedGitignore -DryRun:$DryRun
    Write-Host ''
    Show-HarnessStatus
}

function Invoke-HarnessUp {
    param([switch]$DryRun)
    if (Get-Command Invoke-SkillDeploy -ErrorAction SilentlyContinue) {
        Invoke-SkillDeploy -DryRun:$DryRun
    }
    # Consolidate KNOWLEDGE.md if large (light touch).
    $k = Join-Path (Get-ProjectHarnessDir) 'KNOWLEDGE.md'
    if (Test-Path $k) {
        $lines = (Get-Content $k -ErrorAction SilentlyContinue | Measure-Object).Count
        if ($lines -gt 200) {
            Write-Host "  [info]   8sync/KNOWLEDGE.md has $lines lines -- consider archiving" -ForegroundColor DarkYellow
        }
    }
    Write-Host '  harness refreshed.' -ForegroundColor Green
}

function Show-HarnessStatus {
    $r = Get-HarnessReadiness
    Write-Host ''
    Write-Host '  8SYNC HARNESS -- readiness' -ForegroundColor Cyan
    Write-Host ''
    $ompColor = if ($r.OmpFound) { 'Green' } else { 'Red' }
    Write-Host ("  omp:        {0}" -f $r.Omp) -ForegroundColor $ompColor
    Write-Host ("  skills:     {0} in {1}" -f $r.SkillCount, $r.SkillsDir) -ForegroundColor DarkGray
    Write-Host ("  agents:     {0} omp subagent(s) (~/.omp/agent/agents)" -f $r.AgentsCount) -ForegroundColor DarkGray
    $cgColor = if ($r.Codegraph) { 'Green' } else { 'DarkYellow' }
    Write-Host ("  codegraph:  {0}" -f $(if ($r.Codegraph) { 'available' } else { 'not found (optional)' })) -ForegroundColor $cgColor
    Write-Host ("  omp config: {0}" -f $(if ($r.ConfigFound) { $r.ConfigPath } else { 'absent (run omp once)' })) -ForegroundColor DarkGray
    Write-Host ("  gitleaks:   {0}" -f $(if ($r.Gitleaks) { 'available' } else { 'not found (optional pre-commit)' })) -ForegroundColor DarkGray

    $mem = Get-ProjectHarnessDir
    if (Test-Path $mem) {
        Write-Host ("  memory:     {0} (PROJECT/STATE/KNOWLEDGE)" -f $mem) -ForegroundColor DarkGray
    } else {
        Write-Host '  memory:     not seeded (run: 8sync harness)' -ForegroundColor DarkYellow
    }
    Write-Host ''
    if (-not $r.OmpFound) {
        Write-Host '  Install omp, then run: 8sync harness' -ForegroundColor Yellow
    } else {
        Write-Host '  Start coding:  8sync .' -ForegroundColor Green
    }
    Write-Host ''
}

function Show-HarnessHelp {
    Write-Host ''
    Write-Host '  8SYNC HARNESS -- omp AI coding harness' -ForegroundColor Cyan
    Write-Host ''
    Write-HintRow '8sync .'               'Resume the latest omp session in this repo'
    Write-HintRow '8sync . <name>'        'Create/resume a NAMED omp session (isolated)'
    Write-HintRow '8sync ai "prompt"'     'omp interactive with a seed prompt'
    Write-HintRow '8sync ai "prompt" -p'  'omp one-shot print mode (non-interactive)'
    Write-HintRow '8sync harness'         'Deploy skills + seed project memory + AGENTS.md + readiness'
    Write-HintRow '8sync harness up'      'Light refresh (re-deploy skills + memory check)'
    Write-HintRow '8sync harness global'  'Deploy skills to ~/.omp (all omp projects benefit)'
    Write-HintRow '8sync harness status'  'Health: omp, skills, codegraph, MCP, memory'
    Write-Host ''
}

function Invoke-HarnessCommand {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Rest
    )
    $sub = if ($Rest -and $Rest.Count -gt 0) { $Rest[0].ToLowerInvariant() } else { '' }
    $dryRun = $Rest -contains '--check' -or $Rest -contains '--dry-run'

    switch ($sub) {
        'init'    { Invoke-HarnessInit -DryRun:$dryRun }
        'up'      { Invoke-HarnessUp -DryRun:$dryRun }
        'global'  {
            Write-Host '  Deploying skills globally to ~/.omp/skills ...' -ForegroundColor Cyan
            if (Get-Command Invoke-SkillDeploy -ErrorAction SilentlyContinue) {
                Invoke-SkillDeploy -DryRun:$dryRun
            }
            Write-Host '  Global deploy done. Every omp run now sees these skills.' -ForegroundColor Green
        }
        'status'  { Show-HarnessStatus }
        'help'    { Show-HarnessHelp }
        default   { Show-HarnessHelp }
    }
}
