# SKILL: Append theme-matched slides to an existing PPTX (Windows)

**Owner:** Mouse (Content & Docs) · **Created:** 2026-07-16
**Use when:** you must add slides to an existing branded deck **without** rebuilding it, preserving
every existing slide exactly, on Windows (no LibreOffice).

## Principle
APPEND ONLY. Never touch existing slides. Clone the theme from a representative existing slide,
build new slides as flat shapes, then QA content + visual + regression before exporting.

## Workflow

1. **Back up** the deck + PDF (`Copy-Item ... _deckwork\orig.*`) for regression diffing.
2. **Probe the theme** with python-pptx: dump one "concept" slide and one "reference" slide —
   record every shape's L/T/W/H, fill, line, and each run's font/size/bold/color/spc. These become
   your constants (fonts, palette, eyebrow, card fills, footer position, page-number x).
3. **Reuse title icons** instead of drawing them. The icons are white-on-transparent PNGs. Extract
   with `shape.image.blob` (first PICTURE where `500000 < top < 750000` and `left < 900000`), save
   each, and build a **PIL contact sheet on a dark background** to pick semantically-fitting icons
   fresh-eyes. Re-add with `slide.shapes.add_picture(path, L, T, W, H)`.
4. **Add slides & strip placeholders:** `add_slide(layout)` copies layout placeholders — remove them
   (`for sp in list(slide.shapes): sp._element.getparent().remove(sp._element)`) then build your own
   shapes. Disable inherited shadows (`sp.shadow.inherit = False`).
5. **Content QA:** extract text of the new slides; assert exact command/identifier strings and no
   placeholder/lorem.
6. **Regression:** whitespace-normalize (`re.sub(r"\s+"," ",t).strip()`) and diff every original
   slide's text old-vs-new -> expect **0 mismatches**.
7. **Visual QA:** render new slides to PNG via **PowerPoint COM** and inspect with vision. Fix
   wrap/overflow, re-render.
8. **Export PDF** via COM (`pres.SaveAs(pdf, 32)`), overwriting the old one.

## Windows gotchas (hard-won)
- `scripts\office\soffice.py` **fails on Windows** (`socket.AF_UNIX`). Use PowerPoint COM
  (`win32com.client.Dispatch("PowerPoint.Application")`, `Open(..., ReadOnly=True, WithWindow=False)`,
  `Slides(i).Export(png,"PNG",1920,1080)`, `SaveAs(pdf,32)`).
- **Never** name a helper script `inspect.py` — it shadows stdlib `inspect` and breaks `lxml`.
- Set `PYTHONIOENCODING=utf-8` before running scripts that print arrows / middots (console is cp1252).
- Keep scratch files under a `_deckwork\` dir; delete when done.

## Reference geometry (this project's deck, 12192000 x 6858000 EMU)
Title Georgia bold 24pt navy `0B2540`; blue title circle `0F6CBD` L502920/T457200/603504^2; icon
L665866/T620146/277612^2. Eyebrow Calibri bold 11pt `0F6CBD` spc=200. Cards `F5F9FD`/alt `EEF4FB`,
line `D8E3F0` w12700. Accents: `0F6CBD` `12A5A5` `E8A400` `D1495B` `3C9D57`. Code/strip navy `0B2540`,
label teal `5FD0D0`, body `E6EEF7`. Footer Calibri 9pt `5A7184` y=6437376; page number x=11292840.

## Placing appended slides mid-deck (sldIdLst reorder-into-position)
python-pptx always appends new slides at the END. To position them internally WITHOUT moving the
slide XML parts, reorder the `<p:sldId>` ordering entries in `presentation.xml`'s `<p:sldIdLst>`:
- `sldIdLst = prs.slides._sldIdLst` — children are `sldId` elements in DISPLAY order.
- Capture originals as `orig = list(sldIdLst)` BEFORE appending; the appended ones are the new tail.
- Build the desired order list (e.g. `orig[0:14]+[m1]+orig[14:21]+[m2]+…`), then
  `for e in list(sldIdLst): sldIdLst.remove(e)` and re-append each in the new order.
- Set the NEW slides' page-number text to their true final positions. If the constraint forbids
  altering originals' visible text, leave their baked-in page numbers alone (accept off-by-N after
  each insertion point) so the regression diff stays at 0 mismatches.

## Authoring speaker notes (only fill the empty ones)
- `txt = slide.notes_slide.notes_text_frame.text` — accessing `notes_slide` CREATES a notesSlide if
  absent (additive; does NOT change visible slide content — regression diff stays clean).
- Dump every slide's notes first; only author where empty. Never overwrite existing notes (respects
  prior authorship, keeps the diff minimal). Match the deck's existing notes house style.
- For demo slides, reuse ONLY confirmed commands / resource names from the slides + walkthrough docs +
  reseed scripts. Never invent commands or alert names.

## Curated reference / "Learn More" slides
- Verify EVERY link before baking: `curl.exe -s -o NUL -w "%{http_code}" -L <url>` — keep only 200s;
  `%{url_effective}` reveals redirect targets (drop dups that redirect to a link you already have).
- Layout: 2 columns (COLX=[502920,6217920] COLW=5486400, TOP0=1536192, LINK_H=545000). Group heading =
  thin accent bar (62000 wide) + Calibri bold 11pt accent-colored uppercase (spc=120). Each link = navy
  bold 11.5pt label (`r.hyperlink.address=url`) + gray 8.5pt Consolas display-URL beneath at y+265000
  (also hyperlinked). Signpost icon (project icon **s04**) in the header oval = "where to go next".
- Display URL: `full.replace("https://learn.microsoft.com/en-us/","learn.microsoft.com/")`; if >58
  chars, middle-truncate `d[:40]+"…"+d[-16:]` (hyperlink still targets the full verified URL).
- Method is `add_textbox` (not add_text_box). Slide wrappers re-create on each `prs.slides` access —
  collect XML-backed run objects in a list during creation instead of stashing attrs on Slide objects.
- Visual-QA the new slides only (COM `Slides(i).Export(png,"PNG",1920,1080)`) — watch the densest
  columns and any truncated long URL for wrap/overflow.

## Fixing baked-in STATIC page numbers to true positions
When a deck uses **static text** page numbers (not real slide-number fields), inserting slides mid-deck
leaves the originals off-by-N. To correct them to true 1..N:
- **Locate the footer run by shape coordinates, not name.** In this project the page-number shape sits at
  EXACTLY `left=11292840, top=6437376` EMU (bottom-right). Shape names vary ("Text 25", "Page",
  "TextBox 6") — match on L/T.
- **Ignore numeric decoys.** Content slides have numbered card shapes ("1".."7"); do NOT match "any short
  digit text". Only the shape at the exact footer L/T is the page number.
- **Static vs field:** if a number has DRIFTED from its display position it is static. Confirm by scanning
  the shape XML for `<a:fld ... slidenum>`; a real field auto-updates and must be LEFT ALONE. Report the
  static-vs-field split.
- **Edit surgically:** `runs = [r for p in tf.paragraphs for r in p.runs]; runs[0].text = str(pos)` and
  blank any extra runs. Only write when `old != new` so already-correct slides (e.g. appended refs slides)
  stay byte-identical → regression diff stays 0.
- Some slides (title, dividers, closing) may have **no** footer shape — leave them; don't add one.

## Grounding notes in the deck's own verified refs URLs + a Ref line (reusable)
When a deck already carries curated "References & Learn More" slides whose links you verified, REUSE those
exact URLs as the primary source set for doc-grounding the content-slide notes — don't re-curate.
- Extract them straight from the refs slides: iterate `run.hyperlink.address` on each refs slide's text
  frame. In practice a well-built deck's refs set already covers every feature on the content slides, so you
  add **zero new URLs** (and thus need no new curl verification — though re-verify the distinct used set anyway).
- Per content slide, add ONE explicit **"Doc anchor:"** bullet stating what the feature ACTUALLY is per the
  official page (conceptual definition — NOT numbers), then end with a final `• Ref: <full https URL>` bullet.
  The Ref bullet COUNTS toward the 3–6 budget (pointer, not a 7th point) → target 4–5 bullets incl. Ref.
- Validate the core definitions against the cloud's docs-MCP first (Azure = Microsoft Learn
  `microsoft_docs_search`); docs-MCP is authoritative. HARD RULE: no invented limits/SLAs/pricing/retention/
  preview behavior — soften any prior numeric/date claim you can't re-verify to conceptual form.
- QA table: per slide print bullet count (3–6), Ref present (Y/N), and the Ref URL domain (must be the
  official docs host). Then list every distinct URL used and confirm each is HTTP 200.

## Overwriting existing notes to a bullet "bar" (deliberate rewrite)
Distinct from the "only fill empty" pass: when the task is to REWRITE notes, overwrite via
`tf.clear(); tf.paragraphs[0].text = lead; then tf.add_paragraph().text = "• ..."`. Keep the existing
timing tag as the lead framing line; ground bullets only in the slide's own title/body + prior note
substance. **QA metric = bullet (•) count, not total lines** — a lead framing header line would otherwise
push a 6-bullet slide to 7 total and falsely fail a "3–6" check.
