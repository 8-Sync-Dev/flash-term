# CLAUDE.md


<!-- 8sync:skills:begin -->
## 🚨 STEP 0 — CODE INTELLIGENCE FIRST (codegraph + codebase-memory-mcp; bắt buộc)

Mọi câu hỏi về code → dùng code-intelligence engine TRƯỚC grep/read (tiết kiệm ~99% token). Bạn (AI) **PHẢI**:

1. **codegraph** (local index): `codegraph index .` 1 lần/session; rồi `codegraph query/explore/node/callers/callees/impact` thay cho `grep`/`rg`/`fd`/`Grep`/`Glob` và `Read` toàn file.
2. **codebase-memory-mcp** (MCP, LUÔN có trong tool list — gọi đúng tên đăng ký): `mcp__codebase_memory_mcp_search_graph`, `_trace_path`, `_get_architecture`, `_get_code_snippet` — knowledge graph 158 ngôn ngữ, query sub-ms. Full catalog visible (`query_graph`, `detect_changes`, …); server khác/mới thêm → 1 lệnh `search_tool_bm25`.
3. Tìm/hiểu/định vị code · impact · route→handler · dead code · architecture → ƯU TIÊN 2 engine trên. Chỉ `Read` raw file khi sắp SỬA nó (read-before-edit). Serena LUÔN có trong tool list: `mcp__serena_find_symbol` / `mcp__serena_find_referencing_symbols` / `mcp__serena_get_symbols_overview`.
4. **Nén những gì BẠN phát lại:** báo cáo / subagent prompt / nội dung dài sắp re-emit → `mcp__headroom_compress` (60–95% ít token). omp tự spill output quá dài ra artifact — KHÔNG paste lại blob đã spill vào context.

Lý do: 5 query cấu trúc ≈ 3.4k token vs ≈ 412k token grep từng file (−99%). Dump cả file / grep mù = đốt token = bug.

> ⚠ `codegraph` binary chưa cài. Chạy `8sync harness init` (auto cài) HOẶC `npx -y @colbymchenry/codegraph install` rồi quay lại đọc tiếp.

## 🚨 STEP 1 — skills 2 tầng: CORE (đọc ngay) · SPECIALIST + on-demand (đọc khi cần)

Mỗi skill = 1 directory (Agent Skills open standard): `SKILL.md` có frontmatter `name`+`description`. Skill vendored ở `su-code/skills/<name>/` (bản commit trong repo, mirror từ `~/.omp/skills/`). Mỗi skill liệt kê 1 lần.

### ⛔ CORE always-on — ĐỌC NGAY (body), trước tool call đầu tiên (không skip)

Nhỏ + dùng cho MỌI task. **Thứ tự = ưu tiên (đọc top-down).** Mở `SKILL.md` ở path dưới rồi mới gọi tool đầu tiên:

  1. `su-code/skills/codegraph/SKILL.md`
  2. `su-code/skills/karpathy-guidelines/SKILL.md`
  3. `su-code/skills/ponytail/SKILL.md`
  4. `su-code/skills/8sync-cli/SKILL.md`

### 🧩 SPECIALIST always-on — biết khả năng, đọc body KHI task khớp (progressive disclosure)

KHÔNG đọc body mỗi phiên (giữ prefix gọn, tiết kiệm KV-cache). Khi task khớp → mở `SKILL.md` tương ứng NGAY. **`impeccable` = design system CHUẨN, BẮT BUỘC mở body ngay khi có việc UI/design/redesign/audit** (kèm `references/house/*`); `assp` cho copy/offer; `taste` chống slop; `image-routing` khi xử lý ảnh/diff/PDF.

- `assp-skill` — `su-code/skills/assp-skill/SKILL.md`
- `impeccable` — `su-code/skills/impeccable/SKILL.md`
- `design-taste-frontend` — `su-code/skills/taste-skill/SKILL.md`
- `image-routing` — `su-code/skills/image-routing/SKILL.md`
- `locate-anything` — `su-code/skills/locate-anything/SKILL.md`

### 🔎 On-demand — tên = trigger; mở `SKILL.md` của skill khi task khớp (mô tả ở frontmatter, KHÔNG nhồi ở đây)

- `ai-microservice-design` — `su-code/skills/ai-microservice-design/SKILL.md`
- `api-and-interface-design` — `su-code/skills/api-and-interface-design/SKILL.md`
- `branch-sync` — `su-code/skills/branch-sync/SKILL.md`
- `browser-testing-with-devtools` — `su-code/skills/browser-testing-with-devtools/SKILL.md`
- `ci-cd-and-automation` — `su-code/skills/ci-cd-and-automation/SKILL.md`
- `code-review-and-quality` — `su-code/skills/code-review-and-quality/SKILL.md`
- `code-simplification` — `su-code/skills/code-simplification/SKILL.md`
- `context-engineering` — `su-code/skills/context-engineering/SKILL.md`
- `debugging-and-error-recovery` — `su-code/skills/debugging-and-error-recovery/SKILL.md`
- `deep-research` — `su-code/skills/deep-research/SKILL.md`
- `deprecation-and-migration` — `su-code/skills/deprecation-and-migration/SKILL.md`
- `documentation-and-adrs` — `su-code/skills/documentation-and-adrs/SKILL.md`
- `doubt-driven-development` — `su-code/skills/doubt-driven-development/SKILL.md`
- `encore-eino-go` — `su-code/skills/encore-eino-go/SKILL.md`
- `feature` — `su-code/skills/feature/SKILL.md`
- `frontend-ui-engineering` — `su-code/skills/frontend-ui-engineering/SKILL.md`
- `full-flow` — `su-code/skills/full-flow/SKILL.md`
- `git-workflow-and-versioning` — `su-code/skills/git-workflow-and-versioning/SKILL.md`
- `idea-refine` — `su-code/skills/idea-refine/SKILL.md`
- `incremental-implementation` — `su-code/skills/incremental-implementation/SKILL.md`
- `interview-me` — `su-code/skills/interview-me/SKILL.md`
- `last30days` — `su-code/skills/last30days/SKILL.md`
- `nextjs-app` — `su-code/skills/nextjs-app/SKILL.md`
- `observability-and-instrumentation` — `su-code/skills/observability-and-instrumentation/SKILL.md`
- `performance-optimization` — `su-code/skills/performance-optimization/SKILL.md`
- `planning-and-task-breakdown` — `su-code/skills/planning-and-task-breakdown/SKILL.md`
- `ponytail-audit` — `su-code/skills/ponytail-audit/SKILL.md`
- `ponytail-debt` — `su-code/skills/ponytail-debt/SKILL.md`
- `ponytail-gain` — `su-code/skills/ponytail-gain/SKILL.md`
- `ponytail-help` — `su-code/skills/ponytail-help/SKILL.md`
- `ponytail-review` — `su-code/skills/ponytail-review/SKILL.md`
- `remote-compute` — `su-code/skills/remote-compute/SKILL.md`
- `research-paper` — `su-code/skills/research-paper/SKILL.md`
- `security-and-hardening` — `su-code/skills/security-and-hardening/SKILL.md`
- `senior-frontend` — `su-code/skills/senior-frontend/SKILL.md`
- `senior-security` — `su-code/skills/senior-security/SKILL.md`
- `shipping-and-launch` — `su-code/skills/shipping-and-launch/SKILL.md`
- `source-driven-development` — `su-code/skills/source-driven-development/SKILL.md`
- `spec-driven-development` — `su-code/skills/spec-driven-development/SKILL.md`
- `tauri-v2` — `su-code/skills/tauri-v2/SKILL.md`
- `test-driven-development` — `su-code/skills/test-driven-development/SKILL.md`
- `token-bench` — `su-code/skills/token-bench/SKILL.md`
- `using-agent-skills` — `su-code/skills/using-agent-skills/SKILL.md`
- `zai-vision` — `su-code/skills/zai-vision/SKILL.md`

### Quy tắc bất biến

- **Code-intelligence FIRST** (codegraph + codebase-memory-mcp) cho mọi câu hỏi explore code (Step 0). Bypass = bug.
- **Output > ~50 dòng → BẮT BUỘC `headroom_compress`** trước khi vào context — không dump thô.
- Đọc body **CORE** (codegraph → karpathy → ponytail → 8sync-cli) TRƯỚC tool call đầu tiên. **SPECIALIST** (assp · impeccable · taste · image-routing) đọc body KHI task khớp — `impeccable` bắt buộc ngay khi có việc UI/design.
- Skill **on-demand**: chỉ mở khi description khớp task hiện tại — đừng đọc thừa.
- Nếu skill có `scripts/` → ưu tiên invoke script đó thay vì viết lại logic.
- Khi áp dụng skill, **cite** rõ: ví dụ `su-code/skills/<name>/SKILL.md:line`.
- **Sau mỗi thay đổi:** cập nhật `CHANGELOG.md` (mục Unreleased) + ghi học được vào `su-code/KNOWLEDGE.md`.
- **Doc-hygiene**: chạy `8sync harness audit` khi đụng vùng có docs — path lệch→fix, doc rác/superseded→xóa (thêm doc phải kèm xóa cái cũ), oversized→trim.
- **Loop / STATE spine**: đọc `su-code/STATE.md` đầu phiên; rewrite ở mỗi phase-boundary (Goal·Checklist·Current·Next). Context gần đầy → handoff vào STATE + bài học vào KNOWLEDGE rồi reinit. Đo loop: `8sync harness bench`.
- **Loop discipline (C/D/E)**: implementer↔verifier qua `task` (verifier chạy build/test ĐỘC LẬP, verify-gate TRƯỚC commit); FAIL → ghi `failure:` vào KNOWLEDGE, đọc đầu phiên để khỏi lặp; quy trình `validated:` → distill vào `su-code/PLAYBOOKS.md` (index theo `When:`); autonomy L1 report · L2 assisted · L3 unattended — không tự `push`/PR ở L3 mặc định.
<!-- 8sync:skills:end -->



Guidance for AI agents (Claude Code, omp via su-code, Cursor, OpenCode, …) working in this repository.

## What This Is

**flash-term** — a **WezTerm terminal configuration** + the **`ft` command** for **Windows 11**
(PowerShell). It is *not* an AI harness: it handles terminal **appearance**, **tooling bootstrap**,
and **convenience helpers**. The AI coding harness is a separate project —
[`su-code`](https://github.com/8-Sync-Dev/su-code), which provides the **`8sync`** command
(sessions `8sync .`, `8sync ai`, `8sync harness`, `8sync skill`, …). flash-term installs su-code for
you via `ft setup`.

Two layers in *this* repo:

- **Lua layer** (`wezterm.lua`, `keys.lua`) — appearance, fonts, keybindings, glass presets,
  background, shell launch.
- **PowerShell layer** (`wezterm-bootstrap.ps1` + `modules/*.ps1`) — the **`ft`** toolkit: tool sync
  (Scoop), dev runtimes, aliases, update-all, backgrounds, themes, GPU policy, cleanup, GGUF local
  models, profiles.

The `ft` dispatcher is the function `Invoke-8Sync`, aliased as **`ft`**. The name `8sync` is
deliberately **not** aliased here — it belongs to the su-code AI binary, which must not be shadowed.

## Architecture

```
WezTerm start
  └─ wezterm.lua                 reads current-{bg,opacity,style,gpu}.lua, sets config
       └─ launches PowerShell:   ". wezterm-bootstrap.ps1"
            └─ wezterm-bootstrap.ps1   dot-sources modules/, runs Task switch
                 ├─ core.ps1      hint (Show-8SyncHint), status, state, paths
                 ├─ sync.ps1 / up.ps1     tool sync + update-all
                 ├─ shell.ps1     PSReadLine, fzf, Register-8SyncCompleter (for `ft`)
                 ├─ startup.ps1   Invoke-8Sync dispatcher (aliased as `ft`), Start-WezTermShell
                 ├─ setup.ps1     full bootstrap; installs su-code (`8sync`) for AI
                 ├─ dev.ps1       dev runtimes (node/python/go/rust/chromium/docker/encore)
                 ├─ bg / helix / clean / theme / gpu / profile   WezTerm UX commands
                 ├─ gguf.ps1      local llama.cpp model management
                 └─ autoupdate.ps1   background update + release notifier
```

State is shared between Lua and PowerShell via small generated `.lua` files
(`current-bg.lua`, `current-opacity.lua`, `current-style.lua`, `current-gpu.lua`);
PowerShell writes them, Lua reads them on reload. `wezterm cli reload` is called after each write.

## Command Surface (`ft`)

- **Bootstrap:** `ft setup` (PATH + Scoop + managed CLI tools + dev runtimes + **installs su-code for AI**) · `ft dev [node|python|go|rust|chromium|docker|encore|all]` · `ft dev --check`
- **Tools/UX:** `ft sync` (install/update managed tools) · `ft sync --check` · `ft status` · `ft reload` · `ft clean [--days N|--deep|--scan|--audit|--loop on …]` · `ft gpu [N|status|auto|off]` · `ft theme [style] [scene]` · `ft bg <search|pick|set|rotate|list|…>` · `ft hx <lang|health|opacity|theme|…>` · `ft profile <list|create|clone|switch|open|delete>`
- **Update:** `ft up [self|scoop|wezterm] [--check]` (updates the config repo, Scoop tools, and checks WezTerm)
- **Background notifier:** `ft autoupdate [on|off|auto|now]`
- **Local models:** `ft gguf <serve|hint|save|status|stop|presets|profiles|…>` — runs a local llama.cpp server (OpenAI-compatible `/v1`) on your GPU.
- `ft help` shows the full menu.

> **AI coding** is the separate **su-code** project (`8sync`), not flash-term:
> `8sync .` (resume an AI session) · `8sync ai "<prompt>"` · `8sync harness` · `8sync skill` ·
> `8sync ship`. Installed by `ft setup` (`irm https://8-sync-dev.github.io/su-code/install.ps1 | iex`).
> See <https://github.com/8-Sync-Dev/su-code>.

## Conventions

- Color scheme **Catppuccin Mocha**; font JetBrainsMono Nerd Font; Mica backdrop + glass presets.
- **Graceful degradation:** every tool integration is guarded by `Test-CommandExists`; missing tools are skipped, never fatal.
- PowerShell style: `Verb-Noun`, `$ErrorActionPreference = 'Continue'`, `try/catch` around external calls, `Write-Host -ForegroundColor` for all user output (never `Write-Output` for messages).
- Lua style: 2-space indent, `require` at top, wrap `dofile` in `pcall`, trailing commas in tables.
- Adding an `ft` command: implement `Invoke-<Name>Command` in a module, dot-source it in `wezterm-bootstrap.ps1`, add a case to `Invoke-8Sync` (`startup.ps1`), add to `$modes`/`$subMap` in `Register-8SyncCompleter` (`shell.ps1`), and add `Write-HintRow` entries to `Show-8SyncHint` (`core.ps1`).
- Do NOT commit generated state: `current-*.lua`, `.state/`, `bg/`, `fonts/`.

## Validate

```powershell
# PowerShell syntax
$null = [System.Management.Automation.Language.Parser]::ParseFile("$PWD\wezterm-bootstrap.ps1",[ref]$null,[ref]$e); $e

# Source bootstrap non-interactively (shows the ft hint menu)
pwsh -NoProfile -ExecutionPolicy Bypass -File .\wezterm-bootstrap.ps1 -Task Hint

# Tool status
pwsh -NoProfile -ExecutionPolicy Bypass -File .\wezterm-bootstrap.ps1 -Task Status

# WezTerm config
wezterm --config-file .\wezterm.lua --version
wezterm cli reload
```
