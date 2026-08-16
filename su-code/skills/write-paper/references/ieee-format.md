# IEEE format + page↔word budget (reference)

Read this at **Step 3 (outline)** and **Step 5 (references)**. It defines the paper
structure, the IEEE reference-entry formats, and how many words a target page count buys
in *this repo's* `--theme academic` PDF (single-column A4).

---

## 1. Paper structure (IEEE spine)

```
Title (# H1 — becomes the document title)
Authors / affiliation line
Abstract        — 150–250 words, no citations, self-contained
Keywords / Index Terms — 4–7 terms
I.   Introduction        — problem, motivation, contributions (bulleted), paper map
II.  Related Work        — grouped by theme, each claim cited [n]
III. Method / System     — the approach or the built system (figures, equations)
IV.  Experiments/Results — setup, metrics, tables/plots, honest numbers
V.   Discussion          — interpretation, tradeoffs, threats to validity, limitations
VI.  Conclusion (+ Future Work)
Acknowledgment (optional)
References               — IEEE numeric, order of appearance
```

Numbering: use Roman numerals for top sections (`I.`, `II.`, …) and `A.`, `B.` for
subsections — this is the IEEE convention. In this Markdown→PDF tool, write them as
`## I. Introduction`, `### A. Motivation`.

**Mode A (proposal)** reshapes III–IV into: *Proposed Approach → Methodology → Expected
Contributions → Evaluation Plan → Timeline & Risks*. **Mode B (retrospective)** keeps the
full spine and fills IV with real results (or a qualitative analysis + limitations).

---

## 2. Reference-entry formats (IEEE numeric)

In-text: bracketed numbers — `[1]`, a range `[1]–[3]`, a list `[1], [5]`. Cite a page for a
direct claim: `[4, p. 7]` or `[4, pp. 7–9]`. Author names as **initials + surname**.

**Journal**
```
[n] J. K. Author, "Title of paper," Abbrev. Journal, vol. x, no. x, pp. xxx–xxx, Mon. year, doi: 10.xxxx/xxxxx.
```
**Conference paper**
```
[n] J. K. Author, "Title of paper," in Proc. Abbrev. Conf., City, Country, year, pp. xxx–xxx.
```
**Book**
```
[n] J. K. Author, Title of Book, xth ed. City, Country: Publisher, year, ch. x, pp. xxx–xxx.
```
**arXiv preprint**
```
[n] J. K. Author, "Title," year, arXiv:XXXX.XXXXX.
```
**Standard**
```
[n] Title of Standard, Standard number, Organization, year.
```
**Web page / software**
```
[n] J. K. Author or Org. "Page/Repo title." Site. URL (accessed Mon. Day, year).
```

Worked examples (real, correctly formatted — copy the shape):
```
[1] IEEE, IEEE Reference Guide. Piscataway, NJ, USA: IEEE, 2023. [Online]. Available: https://journals.ieeeauthorcenter.ieee.org/
[2] A. Vaswani et al., "Attention is all you need," in Proc. NeurIPS, Long Beach, CA, USA, 2017, pp. 5998–6008.
[3] K. Shoair, "Scrapling: adaptive, high-performance web scraping for Python," GitHub. https://github.com/D4Vinci/Scrapling (accessed Jul. 3, 2026).
```

> **ResearchGate / APA note.** ResearchGate hosts PDFs but imposes no citation style of its
> own — cite the underlying venue in IEEE. If the user explicitly wants **APA 7**:
> `Author, A. A. (Year). Title of the article. *Journal*, *vol*(issue), pp–pp. https://doi.org/xx`,
> with in-text `(Author, Year)` instead of `[n]`. Default remains IEEE numeric.

---

## 3. Page ↔ word budget (this tool, single-column A4, academic theme)

`--theme academic` renders single-column A4, ~11 pt body, 1.5 line-spacing, justified →
**≈ 450–550 words of prose per page**. Figures, tables, and the References list consume
space without prose, so budget them separately (a half-page figure ≈ −250 words).

| Target pages | Prose words (approx.) | Notes |
|--------------|-----------------------|-------|
| 4  | 1,800 – 2,200 | short paper / extended abstract |
| 6  | 2,800 – 3,400 | typical conference length |
| 8  | 3,800 – 4,600 | full paper |
| 10 | 4,800 – 5,800 | journal-ish |

Section split for a **6-page** paper (~3,000 prose words), tune proportionally:

| Section | Words |
|---------|-------|
| Abstract | 150–250 |
| I. Introduction | ~500 |
| II. Related Work | ~600 |
| III. Method/System | ~800 |
| IV. Results | ~500 |
| V. Discussion | ~250 |
| VI. Conclusion | ~150 |
| References | ~1 page (not prose) |

Reference density: aim **~1.5–2 resolved references per page** (e.g. 10–14 for 6 pages).

> **True two-column IEEE submission?** IEEE venue templates are two-column (~800–1000
> words/page) and require the official LaTeX/Word template — out of scope for this PDF tool.
> This skill produces a clean single-column A4 academic PDF; state that if the user needs a
> camera-ready venue template instead.

---

## 4. Figures, tables, equations

- **Figure/Table captions**: "Fig. 1. …" (below figures), "TABLE I …" (above tables).
  In Markdown, put a bold caption line adjacent to the image/table.
- **Equations**: use the **LaTeX/IEEEtran backend** (`latex-ieee.md`, native `amsmath`) for
  any math. The ReportLab `academic` `$$…$$` path is unreliable — avoid it; keep ReportLab
  documents math-free. Number equations `(1)`, `(2)` at line end if referenced.
- **Diagrams**: a ```mermaid block renders via kroki (needs network); offline → fallback box.
