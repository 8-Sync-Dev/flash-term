---
name: academic-paper
description: Produce a publication-grade academic paper as a LaTeX-compiled PDF in a standard venue format — IEEE conference/journal (IEEEtran, two-column) or arXiv/preprint (article + natbib), with real BibTeX citations. Use when the user asks to write/format a research paper, conference submission, arXiv preprint, IEEE paper, or a camera-ready draft that must follow a journal template. NOT for Vietnamese business reports (use business-brief) or CVs (use defensible-cv).
---

# academic-paper

Turn research into a **submission-grade paper PDF** in a real venue format. The
templates in `references/` ARE the design system — copy one, keep the structure,
swap the content. First validated 2026-07-14: `example-ieee.tex` (IEEEtran
conference, 2-column) and `example-arxiv.tex` (article + natbib) both compile
clean via tectonic.

## 0. STOP gates (before writing a single line)

- **Every citation is a real, verifiable reference.** Author, venue, year, and
  DOI must resolve. NEVER invent a paper, DOI, or author list to fill a `\cite`.
  A fabricated reference is instant desk-reject and destroys trust. If you cannot
  verify it (via `web_search` / the DOI record), it does not go in `refs.bib`.
- **Every number in the paper is reproducible from the paper.** Tables/figures
  must be backed by the Experiments section's protocol (data, splits, seeds,
  hardware). NEVER paste a metric you cannot trace to a run.
- **Pick the target format FIRST.** IEEE conference, IEEE journal, arXiv, or a
  named venue (NeurIPS/ICML/ACL…). It sets the class, column count, page limit,
  and citation style. Ask the user if unstated; default to IEEE conference.
- **Respect the page limit.** Conference papers have a HARD limit (often 6–8 +
  references). `build.sh` prints the page count — check it every build.

## 1. Pipeline

```
choose format ─► cp references/example-{ieee,arxiv}.tex  paper.tex    # template = design system
              ─► cp references/refs.bib  refs.bib                     # real citations only
              ─► swap content (title/authors/abstract/sections)       # keep the class + structure
              ─► scripts/build.sh paper.tex                           # tectonic → PDF (+ page count)
              ─► pdftoppm -png -r 110 → read cover/results page        # VISUAL verify (2-col, tables, refs)
              ─► cp *.pdf ~/Downloads/                                 # deliver
```

```bash
writter-ai/skills/academic-paper/scripts/build.sh paper.tex            # → build/paper.pdf
writter-ai/skills/academic-paper/scripts/build.sh paper.tex out/       # custom outdir
```

Engine is **tectonic** — a single binary that fetches `IEEEtran.cls`,
`IEEEtran.bst`, `natbib`, fonts, etc. from CTAN on demand and runs BibTeX
automatically. No multi-GB TeXLive install. `refs.bib` must sit next to the
`.tex`. Research citations in **parallel** — batch `web_search` calls, verify each
against its DOI/publisher record before adding it.

## 2. Which template

| Target | File | Class | Columns | Citations |
| --- | --- | --- | --- | --- |
| IEEE conference / journal | `example-ieee.tex` | `IEEEtran` | 2 (conf) | `cite` + `IEEEtran.bst`, numeric `[1]` |
| arXiv / preprint / venue | `example-arxiv.tex` | `article` | 1 | `natbib` + `plainnat`, `\citet`/`\citep` |

- **IEEE**: `\documentclass[conference]{IEEEtran}`; swap to `[journal]` for a
  journal. Authors go in `\IEEEauthorblockN`/`\IEEEauthorblockA`. Full-width
  floats use `figure*`/`table*`. Keep `\IEEEkeywords`.
- **arXiv/venue**: standard `article` (arXiv accepts it). To match a venue, drop
  its style file (`neurips_2024.sty`, `icml2024.sty`, `acl.sty`) next to the
  `.tex`, `\usepackage` it, and remove the `geometry`/`authblk` lines it
  replaces. `natbib` gives `\citet{}` (Author, Year) and `\citep{}` ([12]).

## 3. Document skeleton (the order reviewers expect)

Title → Authors/affiliations → **Abstract** (150–250w, no citations: problem,
gap, approach, headline number) → **Keywords** → **Introduction** (problem, gap,
contribution, ending in an explicit contribution list) → **Related Work**
(grouped threads, each with its limitation) → **Method** (reproducible, notation
defined once, numbered equations) → **Experiments** (data/baselines/metrics/
protocol) → **Results** (headline table first, then analysis) → **Conclusion**
(restate contribution + key number, one limitation, one next step) →
Acknowledgments → **References** (`\bibliography{refs}`) → Appendix.

## 4. tectonic / LaTeX gotchas (each already hit once)

- **`algorithmic.sty:11: Invalid UTF-8 byte`** on first IEEE build is **harmless**
  — a stray byte inside the CTAN package file itself, not your document; the PDF
  renders correctly. Do not "fix" it.
- **`Fontconfig warning: … invalid constant`** lines are system fontconfig noise,
  not tectonic errors — `build.sh` filters them. A real failure prints `error:`
  and produces no PDF.
- **`output directory … does not exist`**: tectonic v2 needs the outdir created
  first — `build.sh` does `mkdir -p`. Don't call `tectonic -X compile` with a
  missing `--outdir`.
- **First build is slow** (10–30 s) while packages/fonts download; subsequent
  builds hit the cache and are fast. Not a hang.
- **Undefined citation `[?]`**: the key isn't in `refs.bib`, or you edited the
  `.bib` — tectonic reruns BibTeX itself, so just rebuild; if still `[?]`, the key
  is wrong.
- **Missing `\label`/`\ref` → `??`**: rebuild once (cross-refs need the second
  pass); tectonic normally does the reruns automatically.

## 5. Verify (mandatory before "done")

`build.sh` prints `pages: N` — confirm it's within the venue limit. Then rasterize
and actually *look*: `pdftoppm -png -r 110 build/paper.pdf /tmp/p` and `read` the
first page (title/abstract/2-column flow) and the results page. Confirm: columns
balance and don't overflow the margin, equations/tables render (not raw source),
citations resolve to `[n]` (no `[?]`), figures placed, references list formatted.
Only then `cp` to `~/Downloads/` and hand over the path.

## 6. Housekeeping

The paper lives where the work belongs (its project dir / a scratch dir); the
**templates + this skill** are the durable asset. `build/`, `*.aux`, `*.log`,
`*.bbl` are throwaway — don't commit them. After a validated new venue/pattern,
fold the learning back here and tick `CHANGELOG.md` (Unreleased). Skill is
canonical in `writter-ai/skills/`, mirrored to `~/.omp/skills/`.
