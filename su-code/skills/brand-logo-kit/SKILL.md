---
name: brand-logo-kit
description: Generate a complete brand identity kit — geometric SVG logo variants, square avatar, and rectangular cover/banner images (OG 1280x640, LinkedIn 1584x396) — rendered deterministically via HTML/CSS + headless browser. Use when the user asks for a "logo / avatar / bìa / cover / banner / brand kit" for a product or personal brand. Design language adapted from op7418/logo-generator-skill (SVG-first, extreme minimalism); NO image-gen API dependency. NOT for full websites (frontend-ui-engineering) or documents (business-brief).
---

# brand-logo-kit

Turn a brand name into a **defensible, editable identity kit**: SVG marks → avatar → covers.
First validated 2026-07-15 for **"8 Sync"** — the built example lives in `references/example-8sync/`
and IS the canonical template. Copy the HTML, keep the CSS, swap the mark + wordmark.

Upstream design playbook: https://github.com/op7418/logo-generator-skill (patterns vendored
below so this skill works offline).

## 0. STOP gates

- **Naming before drawing.** If the user is still deciding the name/suffix, give the naming
  assessment FIRST (core wordmark vs descriptor suffix). The logo is built on the **core**
  only, so suffixes (Dev/Tech/Labs) can rotate without a redesign.
- **SVG is the source of truth.** Every raster asset (PNG avatar, cover) derives from a
  committed `.svg`. NEVER ship an image-gen bitmap as the master logo — it is not editable,
  not scalable, and not reproducible.
- **6+ variants minimum** before the user picks. One option is not a choice.
- **Visual verify every render** — screenshot via the `browser` tool and LOOK at it. A
  clipped watermark or fallback font ships silently otherwise.

## 1. Design principles (distilled from upstream, non-negotiable)

viewBox `0 0 100 100`, `currentColor` for recoloring.

1. **1–2 core elements** max (≤ 5–6 shapes total).
2. **≥ 40% negative space.**
3. **Stroke 2.5–4**, dots r 2–8, gaps ≥ 8–12 (in viewBox units).
4. **Intentional asymmetry** — perfect symmetry is boring (e.g. numeral-8: top loop smaller).
5. **Restraint** — pure mono, no gradients/shadows in the master mark.
6. **Single focal point**; must read at 16×16 favicon.
7. **Structural weight** — thin sparse lines feel fragile; use solid mass or dense repetition.
8. **Rounded negative-space cuts** — punched holes are circles/rounded, never sharp.

Pattern vocabulary: tangent/overlapping circles (loops, sync, infinity), dot-matrix rings,
rotational dual arcs (sync/refresh), punched solid (negative space app icon), gooey nodes
+ S-curve (connection). Mixed compositions > parameter tweaks for variant diversity.

## 2. Pipeline

```
brand name ─► naming assessment (core vs suffix)        # words first
          ─► 6+ SVG variants (principles above)          # branding/logos/*.svg
          ─► showcase.html grid + rationale              # user picks
          ─► avatar.html (1024×1024, void style)         # square avatar
          ─► cover_*.html (1280×640 OG, 1584×396 LI)     # rectangular covers
          ─► browser tool: setViewport(exact px) → screenshot → PNG
          ─► read each PNG, visually verify              # fonts, clipping, contrast
```

Rendering = omp `browser` tool (headless Chromium), one screenshot per asset at the exact
pixel size, `omitBackground: true` for transparent logo PNGs. No Gemini/API key needed —
the upstream skill's Nano Banana showcase step is replaced by CSS "void style" backgrounds
(black `#0a0a0b` + SVG feTurbulence grain + radial highlight), see the example HTML.

## 3. Asset checklist per brand

| Asset | Size | File |
|---|---|---|
| Logo variants (SVG) | 100×100 viewBox | `logos/v*_name.svg` |
| Mark PNG (transparent) | 1024×1024 | `logos/v*_name.png` |
| Avatar | 1024×1024 | `avatar_1024.png` |
| OG / GitHub social | 1280×640 | `cover_og_1280x640.png` |
| LinkedIn cover | 1584×396 | `cover_linkedin_1584x396.png` |
| Brand board (1 page) | 1440×1900 | `brand_board.png` |
| Founder cover (LinkedIn/OG) | same sizes | `cover_*_founder_*.png` |

Cover layout that validated: mark left · wordmark (core name only) · suffix as bordered
badge chip (`DEV`) · muted handle line (`GITHUB.COM/...`) · oversized ghost mark right at
~4–5% white opacity as watermark (no filled dots in the watermark — they blob).
Background = mesh of 2–3 brand-hue radial-gradients ≤14% alpha + feTurbulence grain.

**Founder edition** (personal-profile covers): brand column left (mark + mini lockup),
then name (+nickname muted) · role · gradient hairline · 3 mono lines — products (accent
`#7fb2ff`) / credibility metrics / contact+socials (muted, smallest). EVERY metric on the
image must be verified same-session (research.json, or live scrape YT `subscriberCountText`
/ TikTok `followerCount`) and logged in the provenance sidecar; user-provided handles are
contact info, not metrics — use verbatim. Facebook blocks scraping (400) — never guess counts.
**LinkedIn safe zone**: the profile photo overlaps the banner's bottom-left ~300×150px on
desktop (worse on mobile) — start content at `padding-left:~300px` on 1584×396. Mono
contact lines clip silently: budget ~10.5px/char at 16px GeistMono + letter-spacing, or
drop to 13.5px / `.03em`.

**Typography**: real fonts are vendored at `references/fonts/` (OFL, from anthropics/skills
`canvas-design`): **Outfit** Bold/Regular = wordmark & headlines (geometric — harmonizes
with circular marks), **GeistMono** = handles/labels/code, Bricolage Grotesque &
Instrument Sans as alternates. Load via `@font-face` with a relative `fonts/` path and
wait ~400ms after `goto` before screenshotting. NEVER ship the system-font fallback.

## 4. Traps

- **Font fallback**: Inter is usually absent on CI/Linux — use the vendored
  `references/fonts/` pack via `@font-face`; verify the wordmark render, don't assume.
- **Watermark opacity**: ≥ 7% competes with the wordmark; 4–5% is right on `#0a0a0b`.
- **`fill-rule="evenodd"`** for punched marks; every cutout subpath must be closed (`Z`).
- **Degenerate subpaths** (`a 0 0 ...`) render stray artifacts — lint the `d` string.
- Emoji/UTF-8 fine in HTML, but keep captions ASCII-spaced (`letter-spacing: .3em`) for
  the studio look.
- **NEVER build weave/interlock effects with SVG `<mask>`** — Chromium rasterizes masked
  strokes with visible faceting (polygon edges) at large render sizes. Build gaps
  GEOMETRICALLY: stroked arcs with `stroke-linecap="round"`, gap half-angle
  `asin(gap_r / ring_r)` around each intersection. Validated fix 2026-07-15.
- **Multiple inline SVGs on one page**: `<defs>` ids (`g8`, `m8`) collide silently — the
  first wins. Suffix ids per instance when embedding variants in a grid.
- **"Ấn tượng" checklist**: a plain geometric mark is rarely enough. Winning formula =
  double-reading (8 = two interlocked rings = sync) + bold stroke (7–9) + electric
  gradient (`#22D3EE → #4F7CFF → #A855F7`) on `#0a0a0b`. Keep a mono twin for print.

## 5. External arsenal (verified 2026-07-15 — see outputs/brand-design-research.md)

Pull these BEFORE designing to raise the ceiling; full provenance in
`outputs/brand-design-research.provenance.md`.

- **anthropics/skills** → `skills/canvas-design` (design philosophy + ~40 bundled OFL
  fonts — use these for wordmarks instead of the system-font fallback),
  `skills/brand-guidelines`, `skills/algorithmic-art`. Apache-2.0.
- **gilbarbara/logos**, **VectorLogoZone** — thousands of real pro SVG logos; benchmark
  your mark side-by-side against neighbors in the target industry before finalizing.
- **ghosh/uiGradients**, **megh-bari/pattern-craft**, **steveschoger/hero-patterns** —
  curated gradients + background patterns for covers/showcase stages.
- **op7418/logo-generator-skill** — upstream of this skill (patterns vendored in §1).
- Heavy vector-gen models (**OmniSVG** 17–26GB GPU, StarVector, SVGDreamer): cloud/HF
  Space only. **Do NOT attempt local image-gen on ≤4GB VRAM laptops** — FLUX GGUF runs
  at 5–40 min/image; code-driven SVG beats it for logos on quality AND speed.