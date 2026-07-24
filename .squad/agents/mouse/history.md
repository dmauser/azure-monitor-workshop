# Mouse — History (Summarized)

## Seed Context
- **Project:** azure-monitor-lab (Daniel Mauser / @dmauser).
- **Scope:** KQL, Workbooks JSON, docs, README, PPTX slides.
- **Deliverables:** 6 workbook JSONs + 5 KQL query sets + 4 design docs + 5 demo slides (39-43) + 2 observability/cost slides (44-45) + walkthrough doc.

## Completed Work

### Phase 1: Workbooks & KQL (2026-07-15)
- **6 workbooks:** overview, virtual-machines, app-service, aks, azure-sql, apm. All live in `workbooks/`.
- **5 KQL sets:** deployed to `kql/`. Use `<Scenario>_CL` tables; schema = PascalCase, no invented columns.
- **Theme:** Item types 1 (markdown), 9 (parameters), 3 (KQL). Shared `TimeRange` + `Workspace` parameters. Visualizations: timechart, grid, barchart, tiles.

### Phase 2: Design Docs (2026-07-15)
- **4 markdown docs:** architecture.md (Mermaid + ASCII ingestion flow), design-decisions.md (9 decisions: Logs API, DCR-per-scenario, RBAC, schema), data-model.md (full column contracts for 5 tables), troubleshooting.md (10 issues + fixes).
- **Schema conventions:** All names verified vs `mouse-kql-schema.md` + `tank-tables-dcr.md`. `bool` → `boolean` in DCR.

### Phase 3: Demo Slides 39-43 (2026-07-15)
- **Deck:** `docs/Azure-Monitor-Observability-Workshop.pptx`, 38 → 43 slides.
- **Layout:** Flat spTree (no placeholders); appended at end so appendix (34-38) stays intact. Theme reuse: Georgia navy title 24pt, Calibri eyebrow 11pt blue, card fill `F5F9FD`, accent circles (blue/teal/amber/red).
- **Gotcha:** PowerPoint COM used for render/PDF (soffice fails on Windows). Media re-compressed 1.6MB → 0.68MB.

### Phase 4: Observability Agent Docs & Slides 44-45 (2026-07-16)
- **Slide 44:** Azure Copilot Observability Agent preview (4 concept cards + limitations strip); reused s25 icon (people+gear).
- **Slide 45:** Monitoring Cost & Best Practices (6 rows, alternating pitfall/best-practice); reused s28 icon (coins).
- **Technique:** Icon extraction via python-pptx + contact sheet (PIL) for fresh selection.
- **Doc:** `docs/observability-agent-walkthrough.md` (preview walkthrough + APM scenario tie-in).
- **README:** Added 1-line link to walkthrough.
- **PDF:** Re-exported, 45 pages.

### Verified Facts
- **APM anomalies:** `errorrate` (deterministic floor → fires alert-amlab-apm-failure-rate Sev 2), `latency` (→ alert-amlab-apm-p95-latency).
- **Reseed command:** `.\scripts\reseed.ps1 -Scenario apm -Anomaly errorrate -Minutes 15`.
- **Alert:** `alert-amlab-apm-failure-rate` (Sev 2).
- **Table:** `APM_CL`.
- **Name prefix:** `amlab`.

### QA Status
- **Content QA:** PASS.
- **Visual QA:** PASS (PNG via PowerPoint COM).
- **Regression:** PASS (slides 1-43 unchanged, 0 diffs).
- **PDF:** 45 pages, updated.

## Cross-Agent Note: Tank Demo VM Module (2026-07-16)

**From:** Scribe (via Coordinator Tank manifest)  
**Date:** 2026-07-16T10:13:53-05:00  
**Note:** Tank has authored `docs/metrics-demo-vm.md` — the operational runbook for deploying and verifying the standalone Ubuntu demo VM (`vm-amlab-<uid>`) with guest metrics collection via AMA → DCR → law-amlab-<uid>. This complements your workbooks and troubleshooting guide for hands-on demos. Cross-reference if needed for metrics-flow walkthroughs.

## Learnings

### 2026-07-17 — Speaker notes on all slides + 5 References/Learn-More slides (deck -> 50)
Task: populate presenter notes on every content slide and append 5 theme-matched "References & Learn More" slides at module boundaries. Deck went 45 -> 50.

**Notes-authoring approach (only fill the empty ones):**
- Dumped every slide's `slide.notes_slide.notes_text_frame.text` first. Slides 1-38 ALREADY had high-quality notes -> left untouched. Only slides 39-45 had empty notes -> authored those 7 in the existing house style (leading `TAG (X min).` framing + 3-6 short bullet-style talking points). Never overwrite existing notes; this keeps the diff minimal and respects prior authorship.
- Adding a notesSlide to a slide that lacks one is additive; it does NOT change visible slide content (confirmed by 0 regression mismatches).
- Live-demo slides (39-43): notes reuse the CONFIRMED reseed commands / alert names from the slides + `docs\observability-agent-walkthrough.md` + `scripts\reseed.ps1` — never invent commands/alert names. Slides 44/45 notes based on the walkthrough doc + verified on-slide content.

**sldIdLst reorder-into-position (place appended slides mid-deck):**
- python-pptx always appends new slides at the END. To place them internally, reorder the `<p:sldId>` ordering entries in `presentation.xml`'s `<p:sldIdLst>` — move ONLY the ordering entry; the slide XML part stays put.
- `sldIdLst = prs.slides._sldIdLst` ; children are the `sldId` elements in display order. After appending 5 slides (creation order M1,M2,M3,Apx,Final), rebuild the desired order list, then `for e in list(sldIdLst): sldIdLst.remove(e)` and re-append in the new order.
- Order recipe used: `orig[0:14]+[m1]+orig[14:21]+[m2]+orig[21:32]+[m3]+orig[32:43]+[apx]+orig[43:45]+[fin]` -> final positions 15 / 23 / 35 / 47 / 50.
- Page numbers: set the NEW slides' page-number text to their true final positions. Originals' baked-in page numbers were deliberately left unchanged (constraint: don't alter original visible text) -> accepted cosmetic off-by-N after each insertion point; 0 regression mismatches preserved.

**References-slide design (theme-matched, reused slide-44 header geometry):**
- Header: signpost icon (icon **s04**, "where to go next" motif) in blue oval `0F6CBD`; Georgia bold 24pt navy `0B2540` title; Calibri bold 11pt blue eyebrow (spc=200) "<MODULE> · OFFICIAL MICROSOFT DOCS".
- Body: 2 columns COLX=[502920, 6217920] COLW=5486400; TOP0=1536192; LINK_H=545000; GROUP_GAP=140000. Group heading = thin accent bar (62000 wide) + Calibri bold 11pt accent-colored uppercase (spc=120). Each link = navy bold 11.5pt label (hyperlinked) + gray 8.5pt Consolas display-URL beneath at y+265000 (also hyperlinked).
- Display URL = `full.replace("https://learn.microsoft.com/en-us/","learn.microsoft.com/")`; if >58 chars, middle-truncate `d[:40]+"…"+d[-16:]` — the hyperlink still points at the full verified URL. Keeps the long Azure SQL telemetry URL on one line, no overflow.
- ~6-10 links/slide, grouped by topic. Visual QA (COM PNG render of the 5 new slides at 1920x1080) confirmed no wrap/overflow on the densest columns.

**URL verification pattern:**
- `curl.exe -s -o NUL -w "%{http_code}" -L <url>` — keep only 200s; `%{url_effective}` reveals redirect targets (use to catch duplicate/canonical redirects).
- Dropped: 4 AIOps candidates 404 (aiops-investigations, investigations-overview, aiops-overview, copilot/analyze-monitor-data); `logs/manage-cost-storage` redirects to `logs/cost-logs` (dup) -> dropped; used canonical `fundamentals/cost-usage`.

**python-pptx / Windows gotchas re-confirmed:**
- Method is `add_textbox` (NOT add_text_box). Title circle: `MSO_SHAPE.OVAL` (cleaner than rect+prstGeom hack).
- Slide wrappers are re-created on each `prs.slides` access -> cannot stash attrs on a Slide and retrieve later; instead collect XML-backed run objects in a list during creation. Letter-spacing: `r.font._rPr.set('spc', str(spc))`. Hyperlink: `r.hyperlink.address = url`.
- COM render+PDF: `PowerPoint.Application` -> `Presentations.Open(path, ReadOnly=True, WithWindow=False)` -> `Slides(i).Export(png,"PNG",1920,1080)` and `pres.SaveAs(pdf, 32)`. (`scripts\office\soffice.py` still fails on Windows — no socket.AF_UNIX.)
- `PYTHONIOENCODING=utf-8` before any script printing arrows/middots; no heredocs in PowerShell (write .py to `_deckwork\`); never name a helper `inspect.py`.

**Key file paths:** target `docs\Azure-Monitor-Observability-Workshop.pptx` (+ .pdf); build/QA/render helpers under `_deckwork\` (deleted after); signpost icon `_deckwork\icons\s04.png`.

### 2026-07-17 (2) — Notes rewrite on slides 1-38 + baked-in page-number fix to true 1..50
Task: bring original slides' notes to the bullet "bar" (my 39-45 style) and correct the static page numbers that drifted after the 5 refs slides were inserted. Deck stays 50 slides.

**Locating the static page-number run (reliable):**
- The footer page number is a static text run in a shape at EXACTLY left=11292840, top=6437376 EMU (bottom-right, same across the deck). Match on those two shape coords — NOT on shape name (names vary: "Text 37", "Text 25", "Page", "TextBox 6").
- Do NOT match "any short numeric text" — several content slides have numbered card shapes ("1".."7") that are page-number-shaped decoys. Only the shape at that exact L/T is the footer page number.
- Static vs field: read the run text; if it has DRIFTED from the display position it is STATIC (a real slidenum field auto-updates). I also inspected each shape's XML for `<a:fld ... slidenum>` — ZERO fields; all 44 footer numbers are static text. Set `runs[0].text = str(pos)`; only change when different (keeps refs slides byte-identical → clean regression).
- 6 slides have NO footer page-number shape and were left alone: pos 1 (title), 5/16/24/36 (module/appendix dividers), 34 (Next Steps).

**Notes rewrite pass:**
- Original 1-38 notes were single dense narrative paragraphs. Converted each to a lead framing line (kept the existing timing tag e.g. "WELCOME (5 min).") + 3-6 "•" bullet talking points, grounded ONLY in the existing note substance + on-slide title/body. No invented facts.
- Overwrite via `tf.clear(); tf.paragraphs[0].text=lead; tf.add_paragraph()...` — this is the deliberate-overwrite case (task 1), distinct from the earlier "only fill empty" pass.
- Dividers (5/16/24/36) kept light: lead + 3 bullets. Demo slides 42-46/48/49 already at the bar (5-6 bullets) — untouched.
- QA metric = BULLET count (• lines), since the lead line is a framing header. All 45 content slides land 3-6 bullets; regression on visible body (excluding the footer run) = 0 mismatches across all 50.

**Gotchas:** counting "note lines" naively would flag demo slides 46/48/49 (7 total lines) as >6 — count bullets, not total lines. PDF re-export via COM `SaveAs(pdf,32)` as before; spot-rendered pos 16/17/27/47 to confirm the corrected numbers render and nothing shifted.

### 2026-07-17 (3) — Doc-grounding retrofit of slides 1-38 notes (Ref-line convention)
Task: re-ground each slide 1-38 talking point in OFFICIAL learn.microsoft.com concepts and end each with a "Ref:" line. Notes-pane only; no visible-shape edits. Deck stays 50 slides.

**Doc-grounding approach:**
- REUSED the exact canonical learn.microsoft.com URLs already baked & verified on the 5 refs slides (positions 15/23/35/47/50) as the PRIMARY source set. Extracted them straight from the deck via `run.hyperlink.address`. Needed ZERO new URLs — every slide 1-38 concept mapped onto a page already on a refs slide, so no new curl verification was strictly required (re-verified all 20 distinct used anyway → all HTTP 200).
- Each in-scope slide got ONE explicit "Doc anchor:" bullet stating what the feature ACTUALLY is per docs (metrics = per-namespace, time-series DB, near-real-time; Log Analytics = KQL query env; DCR+AMA = modern declarative guest collection; Workbooks = flexible canvas; DINE = deployIfNotExists; landing zone = CAF governed env; table plans = Analytics/Basic/Auxiliary; etc.). Validated the core definitions via Microsoft Learn MCP (`microsoft_docs_search`) before writing — docs-MCP is authoritative.
- Kept it CONCEPTUAL, no invented numbers: softened prior "commitment tiers at 100 GB/day" → "commitment tiers for high-volume workspaces", and "MMA retired Aug 2024" → "legacy Log Analytics agent (MMA) is retired — migrate to AMA" to avoid citing a date/limit I would need to re-verify.

**Ref-line convention (reusable):**
- Structure = lead framing line (unchanged timing tag) + 3-5 "•" bullets, where the FINAL bullet is `• Ref: <full https learn.microsoft.com URL>`. The Ref bullet COUNTS toward the 3-6 budget (it is a pointer, not a 7th point) — all 35 in-scope slides landed 4-5 bullets incl. Ref.
- QA metric stays "count • bullets" (lead line is a header). Coverage table also records Ref present (Y) + URL domain (must be learn.microsoft.com).

**Scope discipline:** only slides 1-38 minus refs 15/23/35 = 35 slides rewritten. 39-45 (lab-grounded) and refs slides untouched. `tf.clear()` overwrite. Regression on visible shape text (all shapes incl. page numbers) = 0 mismatches across all 50; page numbers still read 1..50; PDF re-exported via COM SaveAs(pdf,32).

### 2026-07-17 (4) — Service Health slide insert + doc + refs + notes + page-number refix (deck 50→51)
Task: add Service Health monitoring content — new walkthrough doc, one new deck slide at position 50 (between Cost slide 49 and refs slide 50→51), extend refs slide with 5 Service Health URLs, speaker notes, page-number refix to 1..51, README link, PDF re-export.

**Slide insert-at-position-50 technique (reused sldIdLst reorder):**
- Appended new slide at end via `add_slide(layout)`, stripped placeholders, built flat shapes (theme-matched: blue oval, Georgia 24pt title, Calibri eyebrow spc=200, 3 component cards with accent bars, right-column event classes + key facts + setup paths).
- Reordered `sldIdLst`: `orig[0:49] + [new] + orig[49:]` → new slide lands at position 50, refs slide moves to 51. 51 total slides.

**Notes injection for newly-created slide (no notes_text_frame):**
- A freshly-added slide's `notes_slide._element` has an empty `<p:spTree>` — no body placeholder → `notes_text_frame` returns None.
- Fix: captured a `<p:sp type="body" idx="3">` template from an existing slide's notes (slide 49), deep-copied it, cleared its `<a:p>` children under `<p:txBody>`, injected new `<a:p><a:r><a:t>` elements, and appended the `<p:sp>` to the new slide's notes `<p:spTree>`.
- Note: the body placeholder's `txBody` is under `{p:}txBody` namespace (not `{a:}`), but paragraphs inside are `{a:}p`.

**Refs slide update:** Added a SERVICE HEALTH section (teal accent bar + 5 hyperlinked URLs) in the right column. Title updated from "Observability Agent & Cost — References" to "Observability Agent & Cost & Service Health — References" (fits without overflow).

**Page-number refix:** Only 1 number changed (old pos 50 refs → now pos 51). The new slide already had "50" baked in during creation. No-footer positions unchanged: 1, 5, 16, 24, 34, 36. All 45 footer-bearing slides read correct positions 1..51.

**Doc:** `docs/service-health-alerts-walkthrough.md` — matches observability-agent-walkthrough.md tone/structure (front-matter, What It Is, Prerequisites table, Portal + IaC paths, Key Points, See Also). Grounded in the 8 official facts + 5 verified URLs.

**QA:**
- Slide count: 51. New slide at position 50. Refs at 51. PASS.
- Regression: 0 mismatches on original 50 slides' visible text (excluding page numbers). PASS.
- Page numbers: 45/45 correct (1..51 on footer-bearing slides). PASS.
- Notes on slide 50: 7 lines (1 lead + 6 bullets), Ref line present. PASS.
- Refs slide 51: 10 Service Health hyperlinks (5 label + 5 display-URL). PASS.
- PDF: 51 pages, re-exported 2026-07-17 16:13. PASS.
- README: link added under existing "New:" lines.
