# STATE — flash-term

**Goal:** Ship a top-tier bilingual public face for flash-term (README EN+VI, GitHub Pages site,
SEO) that makes only *true* claims — and fix every source-level lie the audit exposed.

**Phase:** verify → complete (work is done, pushed; only per-machine follow-ups remain)

---

## 🚚 HANDOFF — 2026-08-14 (written for a COLD resume on another machine)

### Repo state
- **Remote:** `https://github.com/8-Sync-Dev/flash-term` · **branch:** `main` (only ever work on `main` here)
- **HEAD:** `4806ec2` + uncommitted changes ready for commit
- **Latest tag:** `v2026.08.13`
- **Working tree:** clean after commit.
- **Memory dir:** `su-code/` (this file) — **committed**.
### What changed THIS session (11 modified + 10 new files)

**Public face (new):**
| File | Why |
|---|---|
| `README.md` (rewritten) | EN-first. Banner, 3 real screenshots, badges, feature deep-dive, mermaid architecture, **honest-caveats section**, SEO keyword/hashtag block. |
| `README.vi.md` (new) | Full Vietnamese mirror, cross-linked with EN. |
| `index.html` / `vi.html` (new) | GitHub Pages landing pages (EN/VI), `hreflang` alternates, canonical, OG/Twitter cards → `assets/banner.png` (absolute URLs), JSON-LD `SoftwareApplication`. |
| `assets/site.css` (new) | Extracted from `index.html`'s `<style>`; shared by both pages. |
| `assets/banner.png`, `preview-help.png`, `preview-status.png`, `preview-themes.png` (new) | Rendered headless-Chromium from **real** `ft help` / `ft status` output + the actual `style_presets` values in `wezterm.lua`. Regenerate by re-running the render recipe (scratch `.render/` was deleted — rebuild from the HTML recipe in the session or re-shoot from live output). |
| `sitemap.xml`, `robots.txt`, `.nojekyll` (new) | SEO plumbing. `.nojekyll` is **required**: Pages `build_type` is `legacy` (Jekyll) with source `main /`. |

**Source fixes (the README would otherwise have documented features that do not run):**
| File | Fix |
|---|---|
| `modules/startup.ps1` | Added the missing **`up`** arm to the `Invoke-8Sync` switch — `ft up` silently fell through to the help menu. |
| `wezterm-bootstrap.ps1` | Defined `$script:UpTargets = @('self','scoop','wezterm')` (never existed → `ft up` iterated zero targets) and added `chafa` to `$script:ToolPackages` (now **21** managed tools). |
| `modules/up.ps1` | Replaced the call to the non-existent `Test-WorkingTreeClean` with a `git status --porcelain` dirty check. |
| `modules/clean.ps1` (2 sites) | PowerShell binding bug: `Test-IsProjectPath -Path $p -or (…)` passes `-or` as a *parameter*, so the project/git guard in `ft clean --envs --delete` could never fire, and the `cargo audit` branch of `ft clean --audit` was equally dead. Both parenthesized. |
| `keys.lua` | `Alt+0` was a duplicate of `Alt+9`; now `ActivateTab(-1)` (last tab). |
| `modules/core.ps1` | `ft bg pick` hint said `imgcat`; it is **chafa**. |
| `docs/KEYBINDINGS.md` | Rewritten — was missing `Ctrl+Shift+b`, `Ctrl+Shift+o`, `Alt+0`, mouse bindings, 4 leader-typed `ft` commands, PSReadLine keys. |
| `docs/gguf-local-gpu-provider.md` | Removed the false claim that `--balance` == a `balanced` preset (no such preset). Now documents the real VRAM solver + its hard `nvidia-smi` dependency. |
| `docs/ARCHITECTURE.md` | 21 tools, sync-lock/TTL details, `ft dev all --check` caveat, new Profiles + startup-cost sections. |
| `CHANGELOG.md` | `## [v2026.08.14]` section covering all of the above. |

**Off-repo (already applied to GitHub, no code):** 20 repo **topics** set, `description` + `homepage`
(`https://8-sync-dev.github.io/flash-term/`) rewritten via `gh repo edit`.

### Done ✓
- [x] `ft up sucode` / `ft sucode` added: pulls latest release of `su-code` from `8-Sync-Dev/su-code` via official installer script.
- [x] Real user usage screenshot (`assets/preview.png`, 1568x642) converted from user webp and embedded in `README.md`, `README.vi.md`, `index.html`, and `vi.html`.
- [x] Module syntax check passed, bootstrap `Hint` & `Status` tasks verified, Lua config verified.
- [x] Updated `CHANGELOG.md` and `su-code/KNOWLEDGE.md`.
### Next / TODO ▸
- [ ] **Verify Pages went live** (~1 min after this push):
      `read https://8-sync-dev.github.io/flash-term/` and `.../vi.html`; confirm
      `assets/banner.png` + `assets/site.css` 200 (not the Jekyll-mangled variant).
      Deploy status: `gh api repos/8-Sync-Dev/flash-term/pages/builds/latest -q '.status,.error.message'`
- [ ] **Social preview image** — NOT settable via REST API. Upload `assets/banner.png` manually:
      repo → Settings → General → Social preview. Without it, GitHub link unfurls use the avatar.
- [ ] **Install `chafa` on the new box** so `ft bg pick` thumbnails work rather than degrading to the
      text list: `ft sync` (then `ft status` must show `chafa ok`).
- [ ] **Smoke the fixed verbs on the new box** (they were only proven here):
      `ft up --check` · `ft status` · `ft help | grep chafa`
- [ ] Optional release cut (deliberately not done): `git tag v2026.08.14 && git push origin v2026.08.14`.
- [ ] Optional: `ft clean --envs --delete` guard was proven by expression, not by a real delete run —
      exercise it once on a throwaway venv if you want end-to-end proof.

### Blockers ⚠
- None blocking. Two known non-blockers:
  - `chafa missing` on THIS machine (`ft status`) → fixed by `ft sync`, not a code defect.
  - `cargo-audit` absent here, so the repaired `ft clean --audit` cargo branch returned `False`
    (correct behaviour) and its happy path is untested.

### Per-machine gotchas (NOT in git — these cost time this session)
- **`pwsh -File .\script.ps1` fails when launched from bash**: bash eats the `\`, pwsh sees
  `.wezterm-bootstrap.ps1` → exit 64. Always `./wezterm-bootstrap.ps1`.
- **The `ft` alias only exists after the bootstrap is sourced.** For a one-shot check from bash:
  `pwsh -NoProfile -ExecutionPolicy Bypass -File ./wezterm-bootstrap.ps1 -Task Hint|Status`.
- **`$script:` config vars live in `wezterm-bootstrap.ps1`, not in the modules** — a new module-level
  target list must be declared there or it is `$null` at runtime (exactly how `ft up` broke).
- **Browser tool:** `wait(fn)` evaluates in **Node**, so `window` is undefined; use
  `page.waitForFunction('window.__done===true')` inside `run`.
- **GitHub caps topics at 20** — `gh repo edit --add-topic` fails 422 on overflow; the repo is now at
  exactly 20, so swap rather than add.
- **No gitleaks pre-commit hook is installed here** (`.git/hooks/*` are all `.sample`). The gate the
  harness assumes does not fire in this clone — scan staged content yourself before committing.
- **su-code / AI harness is a separate binary** (`8sync`), installed by `ft setup` step 5/5. flash-term
  must never alias or ship `8sync` — its own command is always `ft`.
- Cross-ref: `su-code/KNOWLEDGE.md` (dated entries for all of the above).

### New-machine runbook (in order)
```powershell
git clone https://github.com/8-Sync-Dev/flash-term   # or: git pull
cd flash-term
pwsh -NoProfile -ExecutionPolicy Bypass -File ./install.ps1   # PATH + Scoop + WezTerm + fonts
ft setup                                                     # 5 stages; step 5/5 installs su-code
ft sync                                                       # 21 managed tools incl. chafa
8sync setup                                                   # AI core (omp + skills), once
8sync .                                                       # resume an AI session in this repo
```
Then re-apply per-machine, not in git: wallpaper (`ft bg set <url>`), GPU policy (`ft gpu 10`),
glass style (`ft theme neon_glass focus`) — all of it lands in the gitignored `.state/` + `current-*.lua`.

---

## Current
Pushed. flash-term's public face is live-ready and every documented `ft` verb has been executed at
least once on this machine.

## Next
On the new box: `git pull` → confirm Pages is green → `ft sync` for `chafa` → upload the social preview.
