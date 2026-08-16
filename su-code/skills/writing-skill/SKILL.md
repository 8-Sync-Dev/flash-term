---
name: writing-skill
description: Master router and guide for all writing, documentation, publication, research papers, business briefs, contracts, and PDF generation. Use whenever the user asks to write, draft, format, or generate a document, paper, report, brief, contract, ADR, spec, literature review, or PDF. Automatically routes to the optimal specialist skill (academic-paper, business-brief, vn-contract-docs, documentation-and-adrs, paper-writing, literature-review, defensible-cv).
---

# writing-skill

Master router for all writing and document production tasks in `8sync`. When a user asks to write, draft, format, or produce any document, paper, report, contract, or PDF, use this decision matrix to route immediately to the specialist skill and canonical template.

## 1. Decision Matrix & Skill Router

| Document Type | Primary Trigger / Goal | Target Specialist Skill | Engine / Tool | Output Format |
|---|---|---|---|---|
| **Academic / Research Paper** | IEEE paper, arXiv preprint, conference submission, camera-ready draft | `academic-paper` | Tectonic (LaTeX) | Publication PDF (IEEE 2-col / arXiv 1-col) |
| **Business Brief / Strategic Report** | Executive brief, decision memo, comparison report, whitepaper, training doc | `business-brief` | WeasyPrint (HTML+CSS) | Boardroom PDF (CSS tokens, §0 Summary) |
| **Legal Contract & Quotation** | Hợp đồng dịch vụ, thỏa thuận hợp tác, báo giá, phụ lục (VN law 2026) | `vn-contract-docs` | WeasyPrint (HTML+CSS) | Print-ready PDF A4 (Pháp lý VN) |
| **Technical Spec & ADR** | Architecture decision record, API spec, RFC, system design doc | `documentation-and-adrs` | Markdown / Mermaid | Markdown / PDF |
| **Literature Review** | Paper survey, taxonomy matrix, state-of-the-art summary | `literature-review` | Markdown / LaTeX | Markdown / BibTeX |
| **Research Draft & Paper Structuring** | General paper draft, section skeleton, claim-evidence mapping | `paper-writing` | Markdown / LaTeX | Markdown / TeX |
| **Resume & Professional CV** | Professional CV, executive resume, career profile | `defensible-cv` / `linkedin-cv-sync` | RenderCV / WeasyPrint | Professional PDF |

---

## 2. Master Document Routing Flow

```
User Prompt (Write/Format/Draft)
      │
      ├── Academic Paper / arXiv / IEEE ────────► SKILL: academic-paper (LaTeX + Tectonic)
      ├── Strategic Brief / Report / Memo ──────► SKILL: business-brief (HTML + WeasyPrint)
      ├── Legal Contract / Báo Giá (VN) ────────► SKILL: vn-contract-docs (Legal HTML + WeasyPrint)
      ├── ADR / Architecture / Technical Spec ──► SKILL: documentation-and-adrs (Markdown + Mermaid)
      └── Paper Survey / Literature Review ─────► SKILL: literature-review (BibTeX + Taxonomy)
```

---

## 3. Universal Writing Principles & Pipeline

1. **Route & Grounding First:**
   - Select the target specialist skill from the decision matrix.
   - Read the specialist skill's `SKILL.md` before drafting.
   - Gather real data and citations in parallel (`web_search` / paper DOI lookup). NEVER fabricate citations, DOIs, or statistics.

2. **Template-Driven Execution:**
   - Copy the specialist skill's canonical template (e.g. `example-ieee.tex` or `example-cloudgo-crm-erp.html`).
   - The template IS the design system — preserve CSS/LaTeX styling tokens, swap content cleanly.

3. **Front-Load Value:**
   - **Business Briefs:** Start with `§0 Tóm tắt điều hành` (one-sentence conclusion + executive bullets).
   - **Academic Papers:** Abstract (problem, gap, approach, headline number) + explicit contribution list.
   - **Contracts:** Clear identity block (Bên A / Bên B), scope, price, and clear legal basis.

4. **Compile & Visual Verification:**
   - Run the skill's build pipeline (`scripts/build.sh` for Tectonic or WeasyPrint).
   - Enforce page limits (conference paper limits, brief page counts).
   - Rasterize PDF (`pdftoppm -png -r 110`) and visually inspect cover, tables, and page breaks before delivery.

5. **Delivery:**
   - Deliver compiled PDF to `~/Downloads/` or project outdir.
   - Return exact file path and executive summary to the user.
