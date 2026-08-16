# LaTeX / IEEEtran backend (standardized, camera-ready)

The write-paper skill has **two render backends**. Pick per the target:

| Backend | Engine | Use when | Not for |
|---------|--------|----------|---------|
| **LaTeX / IEEEtran** (this doc) | tectonic (XeTeX) via `scripts/build_latex.sh` | Camera-ready, true **two-column IEEE**, real math, a venue/journal submission, "chuẩn LaTeX quốc tế" | Quick internal drafts with no toolchain |
| **ReportLab academic** (`ieee-format.md`, `render_paper.sh`) | this repo's `--theme academic` | Offline, fast, Vietnamese memo/report, single-column A4, no math | Camera-ready two-column or equation-heavy papers |

For anything the user calls an IEEE paper / international submission / needs equations,
**prefer the LaTeX backend**. Use ReportLab when offline or for a quick single-column draft.

## 1. Engine

`build_latex.sh` auto-detects `latexmk` → `tectonic` → `xelatex`, and if none exists it
installs **tectonic** (a single self-contained XeTeX binary, no system TeX Live) into
`~/.local/bin`. tectonic downloads its package bundle on first compile (network) and caches
it; later builds are fast. US-letter two-column is the IEEE standard — keep it.

```bash
bash agents/skills/write-paper/scripts/build_latex.sh papers/mypaper.tex papers/out 6
```

## 2. Authoring

Start from `references/ieee-template.tex` (IEEEtran `conference` class): title, authors,
`abstract`, `IEEEkeywords`, numbered sections, `equation`, `figure`/`table`, and a
`thebibliography` with IEEE entries. Fill every `<…>`.

- **Math**: native LaTeX (`amsmath`) — this is the reason to use this backend over ReportLab.
- **Full-width float** across both columns: `figure*` / `table*`.
- **Citations**: `\cite{key}` with `\bibitem{key}`; the `cite` package compresses `[1]-[4]`.
  For many references, use a BibTeX `.bib` + `IEEEtran.bst` instead of `thebibliography`.
  Metadata and entry formats: `references/ieee-format.md §2`. Real sources only
  (`research-and-citation.md`).

## 3. Vietnamese (and other Unicode)

tectonic is XeTeX, so `fontspec` works. For Vietnamese, point `fontspec` at a Unicode font —
the repo bundles DejaVu at `assets/fonts/`:

```latex
\usepackage{fontspec}
\setmainfont{DejaVuSerif.ttf}[Path=/abs/path/to/report-github-md2pdf/assets/fonts/,
  BoldFont=DejaVuSerif-Bold.ttf]
```

Plain English papers need no fontspec (default Latin Modern is correct). Do **not** use
`inputenc`/`babel`-only pdfLaTeX for Vietnamese — use XeTeX + fontspec.

## 4. Page targeting

Same render→measure→adjust loop as `ieee-format.md §3`, but IEEE two-column fits far more per
page (~800–1000 words/page). `build_latex.sh <tex> <out> <target>` prints a PAGE-GATE line.

## 5. Architecture reference — rendercv

`external/rendercv/` (submodule) is a mature example of the **data → templates → typesetting
engine → PDF** pattern: YAML/Markdown → Jinja2 → **Typst** → publication-grade PDF
(`src/rendercv/renderer/`, templates under `.../templater/templates/typst/`). Read it when you
want a themable, engine-typeset pipeline beyond a single IEEEtran template — Typst is a modern,
fast LaTeX alternative and a viable second engine if `typst` is installed. IEEE Typst templates
exist (e.g. `charged-ieee`); LaTeX IEEEtran remains the most widely accepted camera-ready form.
