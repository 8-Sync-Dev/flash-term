---
name: business-brief
description: Produce a polished, research-backed Vietnamese business brief (decision memo / strategic analysis / whitepaper) as a professional PDF via HTML→WeasyPrint. Use when the user asks for a "tài liệu phân tích / so sánh / báo cáo cho sếp / tài liệu training / whitepaper / decision doc" that must look sharp, cite real sources, and answer a business question. NOT for legal contracts/quotes (use vn-contract-docs) or CVs (defensible-cv).
---

# business-brief

Turn a business question into a **cited, boardroom-grade PDF**. First validated 2026-07-09:
`CloudGO-AI-vs-Custom-CRM-ERP-2026.pdf` (7 pages, VN, "AI tự build vs. thuê triển khai
CRM/ERP") — the built example lives at `references/example-cloudgo-crm-erp.html` and IS the
canonical template. Copy it, keep the CSS, swap the content.

## 0. STOP gates (before writing a single line)

- **Numbers must trace to a named source.** Every statistic, valuation, or failure rate on
  the page comes from a real report you fetched via `web_search`. If you can't name the
  publisher + report, it does not go in. NEVER invent figures.
- **Citation honesty.** Cite by **publisher + report title + bare domain**
  (`MIT Media Lab, Project NANDA — "The GenAI Divide" 2025 · media.mit.edu`). Do NOT paste
  deep/redirect URLs you're unsure resolve — a dead link destroys credibility faster than a
  missing one. The `§ Nguồn tham khảo` section lists names the reader can search.
- **Answer the actual question first.** `§0 Tóm tắt điều hành` must state the conclusion in
  one sentence, before any context. The reader (a busy boss) may read only that.

## 1. Pipeline

```
question ─► web_search (research, parallel)         # gather evidence + real sources
        ─► copy references/example-*.html            # the template = design system
        ─► swap content (VN)                          # keep the CSS, rewrite the body
        ─► scripts/build.sh <file.html>              # WeasyPrint → PDF (+ page count)
        ─► pdftoppm -png -r 96 → read cover/table/talk  # VISUAL verify, not just text
        ─► cp *.pdf ~/Downloads/                       # deliver
```

```bash
writter-ai/skills/business-brief/scripts/build.sh my-brief.html            # → my-brief.pdf
writter-ai/skills/business-brief/scripts/build.sh my-brief.html Out-2026.pdf
```

Research in **parallel** — batch the independent `web_search` calls in one turn. Prefer
primary/industry sources (Gartner, MIT, vendor security reports, named analysts) over blogs.

## 2. Document skeleton (proven order — persuasion + skimmability)

1. **Cover** (`section.cover`, `page-break-after`) — kicker, big `h1`, one-line `.sub`,
   orange `.rule`, a `.meta` table (Chuẩn bị cho / Người soạn / Ngày / Phạm vi), and a
   `.tagbox` stating the central question verbatim. First page has no footer (`@page :first`).
2. **§0 Tóm tắt điều hành** — the answer in one bold sentence + 4–6 bullets. Front-load it.
3. **§1 Bối cảnh** — frame/split the question so the comparison is fair (separate the
   conflated cases). End with the "3 con đường" `table.cmp`.
4. **§ Comparison** — `table.cmp` with an `th.axis` left column, colored `.pill`
   (`p-red`/`p-amber`/`p-green` = Yếu/TB/Tốt) per cell, `td.win` to highlight the winner.
5. **§ Dẫn chứng & số liệu** — a `.stats` row of 3–4 `.stat` boxes (big number + `.cap` with
   the source), then sub-sections per case study with a `.callout` "bài học" and a `.quote`.
6. **§ Giá trị / khuyến nghị** — where the value moves *to*, and what to change.
7. **§ Kịch bản trả lời khách** — `.talk` cards (`.q` objection in red, `.a` scripted reply)
   the user can read aloud. Close with a bold "câu chốt" `.callout`.
8. **§ Nguồn tham khảo** — numbered `ol.refs`, names + domains (see STOP gate).

## 3. Design system (tokens live in the template `<style>`)

- **Page**: A4, `20mm 18mm 18mm 18mm`; running footer = left brand · center classification ·
  right `counter(page)"/"counter(pages)`; `@page :first` blanks the footer.
- **Palette**: navy `#0f2b46` (headings/table head), orange `#d47a1e` (accent: `.rule`,
  `h2 .n`, stat numbers), body `#1f2733` on white. Callout variants: default amber,
  `.blue` `#10618f`, `.green` `#1c7c54`.
- **Type**: `Liberation Sans`/Arial 9.7pt, `line-height:1.5`, justified `p`. Section numbers
  via `h2 > span.n` (`§0`, `§1`, …) — manual, keeps a clean numbered spine.
- **Components** (class → use): `.stats`>`.stat`>`.big`+`.cap` (headline metrics),
  `table.cmp` + `.pill` (matrix), `.callout[.blue|.green]` + `.lbl` (takeaways),
  `.quote` + `.src` (pull-quotes), `.talk` + `.q`/`.a` (objection scripts),
  `.avoid-break` / `page-break-inside:avoid` on tables & cards so nothing splits ugly.

## 4. WeasyPrint gotchas (each already hit once)

- `WARNING: Deprecated -weasy-hyphens: none` is **harmless** — leave it; it just disables
  hyphenation for Vietnamese. Do not "fix" it into an error.
- Fonts render via **fontconfig aliases** (Liberation Sans↔Arial, Liberation Serif↔Times) —
  no font files needed on Linux; keep the `font-family` fallback chain.
- **Vietnamese text + `pdftotext` grep**: extracted text is often NFD-normalized, so a naive
  grep for `"Mã số thuế"` misses. Normalize both sides (`unicodedata.normalize('NFC', …)`)
  or grep an ASCII-safe substring. Don't conclude "the build didn't run" from a grep miss.
- **Always check page count** (build.sh prints it). A business brief is 4–8 pages; a sudden
  jump means a broken `page-break` or an oversized table — inspect, don't ship.

## 5. Verify (mandatory before "done")

Rasterize and actually *look*: `pdftoppm -png -r 96 <pdf> /tmp/b` then `read` the cover, one
comparison-table page, and the talking-points page. Confirm: pills/colors render, tables
don't overflow the margin, footer page numbers present (not on cover), no orphaned headings.
Only then `cp` to `~/Downloads/` and hand the path to the user.

## 6. Housekeeping

New brief lives where the work belongs (its project dir or a scratch dir); the **template +
this skill** are the durable asset. After a validated new genre/pattern, fold the learning
back here and tick `CHANGELOG.md` (Unreleased). Skill is canonical in `writter-ai/skills/`,
mirrored to `~/.omp/skills/`.
