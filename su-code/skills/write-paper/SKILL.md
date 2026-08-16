---
name: write-paper
description: Write an international-standard scientific research report (IEEE conference/journal style) from a code repository, at a target page count. Use when the user asks to viết báo / report nghiên cứu khoa học, produce a research paper or proposal from a repo, write a project up as an academic paper, auto-research and cite top-venue papers for a repo, or export a paper to a page-targeted PDF. It reads the repo, auto-researches papers (feynman + scrapling + web), cites them correctly (IEEE numeric, REAL metadata + page numbers), and renders to PDF via this repo's `--theme academic`.
---

# write-paper — repo → cited, page-targeted research paper (IEEE)

Turn a codebase into a standard scientific report. Two modes, one pipeline:

- **Mode A — Proposal** (`repo chưa làm` / early): a literature-grounded **đề xuất** —
  what to build and why, positioned against the state of the art.
- **Mode B — Retrospective** (`repo đã làm`): a report/paper describing the system that
  exists, positioned against related work, with evaluation and discussion.

The final artifact is a **PDF** produced by *this* repo's Markdown→PDF tool with
`--theme academic` (justified, 1.5 line-spacing, math support, serif on Windows),
sized to a **target page count**.

## Non-negotiables (read before anything)

1. **Never fabricate a citation.** Every `[n]` maps to a source you actually resolved
   (via `feynman paper …` or a fetched DOI/landing page). No real source → no citation.
   Hallucinated references are the #1 failure mode of AI papers — a fake DOI voids the
   whole report for a real venue.
2. **Verify, don't assume.** A paper is done only when the PDF renders, the page count
   is within target, and every reference resolves. Evidence = `pdfinfo` + rendered pages.
3. **Don't touch the PDF engine.** This skill *orchestrates*; it writes Markdown and calls
   the existing CLI. Theme/typography live in `src/report_github_md2pf/pdf/…` and already
   support academic style — do not re-implement them here.
4. **Page target is a gate, not a wish.** Render → count → expand/trim → re-render until
   within ± tolerance (default ±1 page). See §6.

## 0. Resolve inputs first (surface assumptions)

Before writing, pin these down. If the user didn't say, choose the sensible default and
state it (`→ correct me or I proceed`):

| Input | Default | Notes |
|-------|---------|-------|
| **Repo path** | current repo | The subject of the paper. |
| **Mode** | infer from repo maturity | Has real code/results → B; skeleton/idea → A. |
| **Target pages** | 6 (A4) | Drives the word budget (see `references/ieee-format.md`). |
| **Format** | IEEE numeric `[n]` | ResearchGate/APA variants noted in `ieee-format.md`. |
| **Language** | match the source/user (VI or EN) | DejaVuSans renders Vietnamese safely. |
| **Output dir** | `./papers` (or user's) | PDF filename = markdown filename `.pdf`. |
| **Branding** | repo `author.yml` | Footer identity; academic footer is minimal. |

## 1. Research backends (the composed stack)

Full command reference: **`references/research-and-citation.md`**. One-liners:

- **`codegraph`** — read the subject repo without grep. `codegraph query "<symbol>"`,
  `codegraph context "<subsystem>"`. Build the repo brief (§3, step 1).
- **`feynman rank "<topic>" --expand-citations N --full-text-top N --synthesize`** —
  rank which papers to read first, with citation/method/reproducibility/provenance evidence.
- **`feynman paper <doi|arxiv|openalex|pmid|title> --fetch-full-text`** — resolve legal
  full text + **real bibliographic metadata** across OpenAlex / arXiv / DOI / PMID / Europe
  PMC. This is your citation-metadata source of truth.
- **`feynman alpha search|get|ask|code`** — alphaXiv paper search, read, Q&A, repo peek
  (see the `alpha-research` skill).
- **`scrapling`** (reference source: `external/scrapling/`, its own skill at
  `external/scrapling/agent-skill/Scrapling-Skill/SKILL.md`) — fetch bot-protected journal /
  publisher pages (`StealthyFetcher` bypasses Cloudflare) and extract bib metadata when an
  API doesn't cover the venue. `git submodule update --init --remote external/scrapling` to
  pull/refresh; `pip install "scrapling[fetchers]"` if you need to run it.
- **`web_search`** + skills **`deep-research` / `literature-review`** — topic scoping,
  SOTA landscape, and non-paper sources (docs, standards).

Top venues to prefer for citations: IEEE Xplore, ACM DL, arXiv, Springer, ScienceDirect
(Elsevier), USENIX, OpenAlex / Semantic Scholar (metadata), ResearchGate (locate PDFs).

## 2. Pipeline (both modes share this spine)

```
0 scope+inputs → 1 read repo → 2 auto-research (verified source pool)
→ 3 outline sized to pages → 4 draft (inline [n]) → 5 References (IEEE, real only)
→ 6 render academic PDF → 7 page-count gate loop → 8 QA + citation-resolve check
```

**Step 1 — Read the repo.** With `codegraph`/README/architecture, write a short *repo brief*:
problem, approach, key modules (`path:line`), data/algorithms, results if any. This is the
factual spine — the paper must not claim anything the repo doesn't support.

**Step 2 — Auto-research → verified source pool.** From the repo's domain, derive 3–6 search
topics. `feynman rank` each; `feynman paper --fetch-full-text` the top hits to capture real
metadata (authors, title, venue, year, vol/no, **pp.**, DOI). Use `scrapling` for venues an
API misses. Record each source once in a working `.bib`-style list; drop anything you can't
resolve. Aim for ~1.5–2 solid references per page.

**Step 3 — Outline to IEEE, sized to pages.** Map target pages → section word budget
(`references/ieee-format.md`). Standard IEEE spine: Abstract · Keywords · I. Introduction ·
II. Related Work · III. Method/System · IV. Experiments/Results · V. Discussion ·
VI. Conclusion · References.

**Step 4 — Draft in Markdown.** Copy `references/paper-template.md`, fill section by section,
insert `[n]` at every borrowed claim. Keep prose render-safe (see §7 pitfalls).

**Step 5 — References.** Emit the References section in IEEE numeric order-of-appearance,
each entry formatted per `ieee-format.md`, using **only** resolved metadata. Add page numbers
for direct/quoted claims.

**Step 6 — Render (choose backend, §4).** Camera-ready/two-column/math →
`scripts/build_latex.sh <paper.tex> <out-dir> [pages]` (LaTeX/IEEEtran). Quick offline
single-column draft → `scripts/render_paper.sh <paper.md> <out-dir> academic [pages]` (ReportLab).

**Step 7 — Page gate.** If pages < target: deepen Related Work / add a figure / expand
Results discussion. If > target: tighten prose, merge paragraphs, move detail to a table.
Re-render until within ±1 page.

**Step 8 — QA.** Render page images (`pdftoppm -png -r 100`), inspect: headings, justified
body, References formatting, Vietnamese diacritics, no leftover citation cruft. Re-resolve
every `[n]` one last time.

### Mode A (Proposal) emphasis
Weight toward **II. Related Work → Gap → III. Proposed approach/architecture → Methodology →
Expected contributions → Evaluation plan → Timeline/Risks**. Everything about the repo is
framed as *planned*, grounded by citations showing the gap is real and the approach is sound.

### Mode B (Retrospective) emphasis
Weight toward **III. System/Method (from the actual code)** and **IV. Evaluation** (real
numbers if the repo has them; otherwise a qualitative analysis + honest limitations). Related
Work positions the built system; Discussion covers tradeoffs and threats to validity.

## 3. Citation rules (summary — full protocol in `references/research-and-citation.md`)

- IEEE **numeric** `[n]`, numbered by first appearance; one number per source, reused.
- Each entry needs: authors, title, venue, year, and locator (vol/no/**pp.** or DOI/URL).
- **Direct claims cite the page** ("as shown in [4, p. 7]").
- Verify each source resolves (`feynman paper <id>`); dedup; drop unresolved.

## 4. Render backends & branding (choose per target)

Two backends. **Pick per the deliverable** (full guide: `references/latex-ieee.md`):

| Backend | When | Command |
|---------|------|---------|
| **LaTeX / IEEEtran** (standardized, camera-ready, **two-column**, real math) | an IEEE paper / venue or journal submission / equations / "chuẩn LaTeX quốc tế" | `bash agents/skills/write-paper/scripts/build_latex.sh papers/mypaper.tex papers/out 6` |
| **ReportLab academic** (offline, fast, Vietnamese, single-column A4, **no math**) | quick draft / memo / report with no toolchain | `bash agents/skills/write-paper/scripts/render_paper.sh papers/mypaper.md papers academic 6` |

`build_latex.sh` auto-provisions **tectonic** (self-contained XeTeX) if no LaTeX engine is
present; author from `references/ieee-template.tex`. The ReportLab path wraps
`uv run git-report … --theme academic` and reads `author.yml` for footer branding:

```bash
uv run git-report papers/mypaper.md --theme academic --author-config author.yml -o papers
```
```yaml
# author.yml — footer identity (academic footer stays minimal)
name: "Nguyễn Phương Anh Tú"
company: "8 Sync Dev"
template: "academic"
```

## 5. Verification checklist (Definition of Done)

- [ ] PDF renders; `pdfinfo` pages within target ± 1.
- [ ] IEEE structure present (Abstract → … → References).
- [ ] Every `[n]` resolves to a real source; References formatted per `ieee-format.md`.
- [ ] No citation cruft / PUA junk; Vietnamese (or EN) renders correctly.
- [ ] Claims about the repo are backed by the code (Mode B) or clearly *planned* (Mode A).

## 6. Pitfalls (verified)

- **Math** → use the **LaTeX backend** (`amsmath`), not ReportLab. The ReportLab `academic`
  theme's `$$…$$` path is unreliable (needs matplotlib and can mislay flowables); keep the
  ReportLab path math-free and route equations through LaTeX/IEEEtran.
- **ReportLab academic theme** = justified body, 1.5 spacing, grayscale headings, serif only
  on Windows (elsewhere falls back to bundled DejaVuSans — still correct).
- **Mermaid** needs network (kroki); offline → labelled fallback box, no crash.
- **Strip citation cruft** from pasted sources: ChatGPT wraps refs in PUA `U+E200…U+E201`
  (`\ue200cite\ue202…\ue201`) — remove before rendering or the PDF shows garbage.
- **Vietnamese** always works (DejaVuSans bundled); never "fix" fonts by forcing Helvetica.
- **No automated test suite** — smoke-verify by rendering + checking pages > 0.

## 7. Progressive disclosure

Read these only when you reach that step:
- `references/ieee-format.md` — structure, reference-entry formats, page↔word budget.
- `references/research-and-citation.md` — feynman/scrapling/web commands + anti-hallucination.
- `references/paper-template.md` — the render-safe IEEE Markdown skeleton (ReportLab path).
- `references/latex-ieee.md` + `references/ieee-template.tex` — the LaTeX/IEEEtran backend
  (camera-ready, two-column, math, Vietnamese via fontspec).
- `external/scrapling/agent-skill/Scrapling-Skill/SKILL.md` — Scrapling API when scraping.
- `external/rendercv/` — data→templates→Typst→PDF architecture exemplar for engine-typeset output.
