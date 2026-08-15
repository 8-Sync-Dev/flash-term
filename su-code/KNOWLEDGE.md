<!-- 8sync:harness:begin -->
## 🧠 8sync harness

- **Always-on (đọc theo thứ tự; CORE đọc body ngay, SPECIALIST đọc khi task khớp):** codegraph → karpathy-guidelines → ponytail → assp-skill → impeccable → taste-skill → 8sync-cli → image-routing → locate-anything.
- **Cách tận dụng:** codegraph = explore code (query/callers/callees, không grep) · karpathy + ponytail = YAGNI, làm ít nhất, xoá > thêm · impeccable = design CHUẨN, BẮT BUỘC khi UI/design (đọc body lúc đó) + taste chống slop.
- **Output lớn (>~50 dòng) → BẮT BUỘC `headroom_compress`** trước khi vào context.
- **Sau mỗi thay đổi:** cập nhật `CHANGELOG.md` (Unreleased) + ghi học được vào file này (prefix `validated:` nếu test/build xác nhận, `hypothesis:` nếu chưa).
<!-- 8sync:harness:end -->

# KNOWLEDGE

Reusable conventions, gotchas, architecture lessons learned while working here.
Append `## YYYY-MM-DD` dated entries. Distill failures (`failure:`) and validated
flows (`validated:`) so future sessions don't repeat them.

## 2026-08-14

- failure: `ft up` was advertised in `Show-8SyncHint`, `Register-8SyncCompleter`, the `Leader+u`
  keybinding and the autoupdate notice, yet had **no arm in the `Invoke-8Sync` switch** and its
  `$script:UpTargets` was never declared — so it fell through to the help menu, and a direct
  `Invoke-UpCommand` iterated zero targets. Lesson: in this repo a verb is only real when all five
  wiring points exist (module function → dot-source in `wezterm-bootstrap.ps1` → dispatcher case in
  `modules/startup.ps1` → completer `$modes`/`$subMap` in `modules/shell.ps1` → hint row in
  `modules/core.ps1`), **plus** any `$script:` config it reads, which lives in
  `wezterm-bootstrap.ps1`, not in the module.
- failure: `if (Test-IsProjectPath -Path $p -or (Test-IsInsideGitRepo -Path $p))` — PowerShell binds
  `-or` as a *parameter* of the cmdlet, so the condition never evaluates as a boolean expression. Two
  live guards in `modules/clean.ps1` (env-delete project/git skip, and the `cargo audit` branch) were
  dead because of it. Always parenthesize each call: `((f -Path $p) -or (g -Path $p))`.
- validated: verify a repaired PowerShell predicate without running the destructive command — dot-source
  the bootstrap in a throwaway script and print the expression:
  `. ./wezterm-bootstrap.ps1 -Task Hint | Out-Null; ((Test-IsProjectPath -Path $p) -or (Test-IsInsideGitRepo -Path $p))`.
  Repo path → `True`, `%TEMP%` → `False`.
- failure: `pwsh -File .\wezterm-bootstrap.ps1` invoked from bash exits 64 — bash strips the backslash
  and pwsh receives `.wezterm-bootstrap.ps1`. Use `./wezterm-bootstrap.ps1`.
- validated: keybinding claims must be checked against the engine, not the source table —
  `wezterm --config-file ./wezterm.lua show-keys` exposed that `Alt+0` was a duplicate `ActivateTab(8)`
  and that two bindings are appended in `wezterm.lua` after `keys.lua` is loaded.
- validated: README/markdown can be proven before pushing — render it through GitHub's own pipeline:
  `jq -Rs '{text:.,mode:"gfm",context:"<owner>/<repo>"}' README.md | gh api --method POST /markdown --input -`
  then assert on the HTML (`<pre` count, `assets/*.png` references, `lang="mermaid"`). Mermaid blocks
  themselves validate with `mermaid.parse()` from the jsdelivr ESM build in the browser tool.
- validated: GitHub Pages here is `build_type: legacy` (Jekyll) with source `main /`
  (`gh api repos/<o>/<r>/pages`). Root-served `index.html` therefore needs `.nojekyll`, and keeping the
  site at the repo root preserves the existing `…github.io/flash-term/install.ps1` one-liner.
- failure: GitHub rejects more than **20 topics** (HTTP 422 on `gh repo edit --add-topic`). The repo is
  now at exactly 20 — swap, don't add. The repo *social preview* image has no REST endpoint; it must be
  uploaded through Settings → General.
- failure: in the browser tool's `run` scope, `wait(fn)` executes in **Node** (no `window`); poll the
  page with `page.waitForFunction('window.__done===true')` instead.
- validated: screenshots for docs should be generated from real command output (`-Task Hint` / `-Task
  Status`) rendered as HTML in headless Chromium — the images then cannot drift from the truth, and any
  false claim shows up while shooting them (that is how `imgcat` vs `chafa` was caught).
- validated: this repo's memory spine is `su-code/` and it is **committed**; the root `8sync/` folder is
  gitignored (`.gitignore:75`) leftover template from before the su-code rename. Handoff written into
  `8sync/` would never reach another machine.
- failure: no gitleaks pre-commit hook is installed in this clone (every `.git/hooks/*` is a `.sample`),
  so the secret gate the harness assumes silently does not run. Scan staged content manually.
- validated: `ft up sucode` / `ft sucode` pulls the latest release of `su-code` directly from `8-Sync-Dev/su-code` GitHub releases using the official `install.ps1` script (`irm https://8-sync-dev.github.io/su-code/install.ps1 | iex`), providing atomic update without cargo/build prerequisites.
- validated: Real usage screenshots showcase multi-pane workflow (Yazi file tree, Helix editor, theme picker, starry wallpaper) as `assets/preview.png` (1568x642) embedded across README (EN/VI) and GitHub Pages (`index.html`/`vi.html`).
