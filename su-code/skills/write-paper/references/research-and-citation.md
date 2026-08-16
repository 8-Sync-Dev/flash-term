# Auto-research + citation pipeline (reference)

Read this at **Step 2 (research)** and **Step 5 (references)**. It gives the exact commands
for the research backends and a strict anti-hallucination protocol. The golden rule from
`SKILL.md`: **no resolved source → no citation.**

---

## 1. Backends and exact commands

### feynman — research-first shell (installed CLI, `feynman`)
The primary engine for paper discovery and **real** bibliographic metadata.

```bash
# Rank what to read first (transparent citation/method/reproducibility/provenance evidence)
feynman rank "aviation English workforce readiness assessment" \
  --expand-citations 20 --full-text-top 5 --synthesize

# Resolve ONE paper across OpenAlex / arXiv / DOI / PMID / PMCID / Europe PMC + full text
feynman paper 1706.03762 --fetch-full-text
feynman paper 10.1145/3292500.3330701 --fetch-full-text
feynman paper "Attention is all you need"

# alphaXiv client (see the alpha-research skill)
feynman alpha search "retrieval augmented generation" --mode semantic
feynman alpha get 2005.11401
feynman alpha ask 2005.11401 "What datasets were used and what were the metrics?"
feynman alpha code https://github.com/org/repo path/to/file.py
```
`feynman paper` is your **citation source of truth** — it returns authors, title, venue,
year, and identifiers you can format directly into an IEEE entry. If `feynman` is not set up
on this machine: `feynman setup` / `feynman doctor` (and `feynman alpha login` for alphaXiv).

### scrapling — bot-resistant page fetch (submodule `external/scrapling/`)
Use when a venue/publisher page has no clean API or blocks normal fetches (Cloudflare, etc.).
Its own agent skill: `external/scrapling/agent-skill/Scrapling-Skill/SKILL.md`
(`references/fetching/{static,dynamic,stealthy,choosing}.md`, `references/parsing/*`).

```bash
git submodule update --init --remote external/scrapling   # bootstrap / refresh reference
pip install "scrapling[fetchers]" && scrapling install     # only if you need to RUN it
```
```python
from scrapling.fetchers import Fetcher, StealthyFetcher
page = Fetcher.get("https://doi.org/10.1145/3292500.3330701")      # fast path
page = StealthyFetcher.fetch("https://ieeexplore.ieee.org/document/XXXX")  # anti-bot path
title = page.css_first("meta[name='citation_title']::attr(content)")
authors = page.css("meta[name='citation_author']::attr(content)")
year = page.css_first("meta[name='citation_publication_date']::attr(content)")
doi = page.css_first("meta[name='citation_doi']::attr(content)")
```
Most scholarly pages expose Highwire `citation_*` `<meta>` tags — the cleanest metadata
source when an API doesn't cover the venue.

### web_search + research skills
`web_search` for topic scoping, standards, docs, and locating a DOI/PDF. Compose the
`deep-research` and `literature-review` skills for a broad landscape pass before drilling in.

Preferred venues: **IEEE Xplore, ACM DL, arXiv, Springer, ScienceDirect (Elsevier), USENIX**;
metadata via **OpenAlex / Semantic Scholar**; **ResearchGate** to locate an author PDF (cite
the underlying venue, not ResearchGate).

---

## 2. Build the verified source pool

1. Derive 3–6 search topics from the repo brief (Step 1).
2. `feynman rank` each topic → shortlist by relevance + reproducibility evidence.
3. For every shortlisted paper: `feynman paper <id> --fetch-full-text` → capture metadata.
   Venue not resolved by feynman? `scrapling` the landing page for `citation_*` meta.
4. Record each source **once** in a working list (authors, title, venue, year, vol/no, pp.,
   DOI/URL, and the specific claim you'll cite it for).
5. **Drop anything you cannot resolve.** An unresolved source never becomes a `[n]`.

Target density: ~1.5–2 references per page (`ieee-format.md §3`).

---

## 3. Anti-hallucination protocol (mandatory)

Fabricated citations are the failure mode that voids a paper. Enforce all of:

- **Provenance for every entry.** Each `[n]` traces to a `feynman paper` resolution or a
  fetched page you actually retrieved. If you only "recall" a paper, verify it before citing.
- **Real identifiers only.** A DOI/arXiv id must resolve. Never invent a DOI, volume, or page
  range to make an entry "look complete" — omit the field instead.
- **Claim ↔ source match.** The cited source must actually support the sentence. Don't
  citation-pad with tangential references.
- **Page numbers for direct claims.** Quote or specific result → `[n, p. X]`.
- **Final resolve pass (Step 8).** Re-check every `[n]` resolves before declaring done.

If the literature is thin, say so in the paper ("to our knowledge, few works address …")
rather than inventing support.

---

## 4. Numbering & dedup

- Assign `[n]` by **first appearance** in the text; reuse the same number thereafter.
- One number per source (dedup by DOI/title). Merge duplicates found under different ids.
- Build the References list in ascending `[n]` order; format per `ieee-format.md §2`.

---

## 5. Worked micro-example

Repo brief → topic "adaptive web scraping for citation extraction".
```bash
feynman rank "adaptive web scraping resilience anti-bot" --full-text-top 3 --synthesize
feynman paper "Scrapling adaptive web scraping" || \
  python -c "from scrapling.fetchers import Fetcher; p=Fetcher.get('https://github.com/D4Vinci/Scrapling'); print(p.css_first('title::text'))"
```
→ resolved → entry `[3] K. Shoair, "Scrapling…," GitHub. https://github.com/D4Vinci/Scrapling (accessed …).`
→ in text: "We fetch bot-protected publisher pages with an adaptive scraper [3]."
