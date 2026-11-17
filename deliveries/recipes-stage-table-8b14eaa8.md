# Structured recipes — stage vitals

Task: 8b14eaa8-9fbd-4295-bd36-7dc33d9e8635. Recorded run: 2026-11-14T06:48:39.108Z to 2026-11-14T06:59:20.855Z. All elapsed values below are seconds unless labeled otherwise.

**Completion: 634.211 s (10m34.211s). Capture: 618.401 s. Above the 265.225 s planning estimate: 368.986 s; above the 330 s target: 304.211 s.**

**Single longest stage: Full author pass 4, 121.055 s complete authoring (120.082 s provider). Author providers total 442.096 s, 69.708% of completion.**

Model calls: 30 established (1 classification + 5 author + 8 selection + 11 content + 5 visual), plus one next-visual-batch failure window whose provider dispatch is unconfirmed. Author-provider totals below do not pretend to include the unmeasured classification/selection/visual provider times.

## Initial classification generation

Model: openai/gpt-4o, selected by the verified routing policy. The work-routing event precedes the actual classification fetch; the next routing event is its successful fixed-text briefing. One classification call, no retry. The briefing itself is not another generation.

| Stage | Returned B | Exact provider elapsed | Enclosing window | Start UTC | End UTC | Outcome |
| --- | --- | --- | --- | --- | --- | --- |
| Initial work classification | not retained | not retained | 1.147 s | 2026-11-14T06:48:41.034Z | 2026-11-14T06:48:42.181Z | create_document_routed |

## Every author generation

Returned bytes are the actual model content, not deterministic reconstructed program bytes. All five responses have one semantic response and one transport call, zero automatic retries. The fifth is a layout patch, not a full rewrite.

| Stage | Returned B | Program B | Provider elapsed | Total author elapsed | Prompt B incl. contract | Outcome |
| --- | --- | --- | --- | --- | --- | --- |
| Full author pass 1 | 17932 | 20809 | 103.548 s | 103.903 s | 48610 | sealed_and_executed |
| Full author pass 2 | 17867 | 20747 | 106.272 s | 106.637 s | 70167 | sealed_and_executed |
| Full author pass 3 | 18837 | 21709 | 109.017 s | 109.422 s | 90074 | sealed_and_executed |
| Full author pass 4 | 20711 | 23595 | 120.082 s | 121.055 s | 110146 | sealed_and_executed |
| Layout-only patch | 148 | 23671 | 3.177 s | 3.487 s | 149998 | sealed_and_executed |

Model: anthropic/claude-sonnet-4.6. Prior vitals fields (storage pieces, first content, idle, prompt components and throughput) are preserved in the JSON companion. Program-byte throughput is not returned-content throughput, particularly for the 148-byte patch.

## Every selection generation

**Telemetry gap:** successful selection response bytes and exact provider durations were not retained. These are enclosing timestamp-derived selection/validation/preparation windows, NOT fabricated exact model timings. All are Sonnet 4.6, one observed transport attempt and zero observed retries.

| Stage | Purpose | Prompt B | Returned B | Exact provider elapsed | Enclosing window | Start UTC | End UTC |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Selection 1 | document_authoring | 112515 | not retained | not retained | 4.104 s | 2026-11-14T06:48:47.798Z | 2026-11-14T06:48:51.902Z |
| Selection 2 | document_build | 273018 | not retained | not retained | 5.185 s | 2026-11-14T06:50:44.643Z | 2026-11-14T06:50:49.828Z |
| Selection 3 | document_build | 377889 | not retained | not retained | 5.539 s | 2026-11-14T06:52:51.682Z | 2026-11-14T06:52:57.221Z |
| Selection 4 | document_build | 486092 | not retained | not retained | 5.713 s | 2026-11-14T06:54:58.917Z | 2026-11-14T06:55:04.630Z |
| Selection 5 | document_build | 603997 | not retained | not retained | 8.726 s | 2026-11-14T06:57:19.237Z | 2026-11-14T06:57:27.963Z |
| Selection 6 | document_build | 613156 | not retained | not retained | 6.808 s | 2026-11-14T06:58:01.334Z | 2026-11-14T06:58:08.142Z |
| Selection 7 | document_build | 773451 | not retained | not retained | 7.420 s | 2026-11-14T06:58:20.298Z | 2026-11-14T06:58:27.718Z |
| Selection 8 | closing_choice | 767068 | not retained | not retained | 13.682 s | 2026-11-14T06:58:59.652Z | 2026-11-14T06:59:13.334Z |

## Every content-check call

Model: openai/gpt-4o. Source calls cover complete, unpaginated HTML. Each final call covers the complete extracted eight-page text in one request; there are no separate per-page content calls or independently confirmed per-page content verdicts. Every retained call returned HTTP 200 / finish=stop. Duration measures the request/response/validation attempt, not isolated model computation. JSON includes Event end time, duration-derived start and event identity.

An issues result can coexist with an item-grounding diagnostic: the checker preserves separately literal-grounded blocking findings even when the requested-item coverage structure fails validation. That does not establish a coverage pass or recover the rejected coverage quote.

| Checked bytes | Attempt | Retry | Measured elapsed | Response B | Content B | Outcome | Diagnostic |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Source 1 | 1 | 0 | 5.107 s | 4956 | 2896 | issues | grounding / item_requirement_anchor / item 0 |
| Source 2 | 1 | 0 | 4.984 s | 4856 | 2736 | unconfirmed | requested_items / item_identity / item 1 |
| Source 2 | 2 | 1 | 6.237 s | 4998 | 2945 | issues | grounding / item_requirement_anchor / item 0 |
| Source 3 | 1 | 0 | 3.870 s | 3367 | 1415 | unconfirmed | grounding / item_coverage_anchor / item 3 |
| Source 3 | 2 | 1 | 4.593 s | 4426 | 2406 | issues | grounding / item_requirement_anchor / item 0 |
| Source 4 | 1 | 0 | 6.933 s | 7182 | 4924 | pass | none |
| Candidate PDF | 1 | 0 | 6.728 s | 7050 | 4794 | unconfirmed | grounding / item_coverage_anchor / item 0 |
| Candidate PDF | 2 | 1 | 6.043 s | 7053 | 4794 | unconfirmed | grounding / item_coverage_anchor / item 0 |
| Source 5 | 1 | 0 | 6.124 s | 7198 | 4938 | pass | none |
| Delivered PDF | 1 | 0 | 8.454 s | 7050 | 4794 | unconfirmed | grounding / item_coverage_anchor / item 0 |
| Delivered PDF | 2 | 1 | 6.528 s | 7055 | 4796 | unconfirmed | grounding / item_coverage_anchor / item 0 |

| Check group | Attempts | Retries | Total elapsed | Terminal outcome |
| --- | --- | --- | --- | --- |
| Source 1 | 1 | 0 | 5.107 s | issues |
| Source 2 | 2 | 1 | 11.221 s | issues |
| Source 3 | 2 | 1 | 8.463 s | issues |
| Source 4 | 1 | 0 | 6.933 s | pass |
| Candidate PDF | 2 | 1 | 12.771 s | unconfirmed |
| Source 5 | 1 | 0 | 6.124 s | pass |
| Delivered PDF | 2 | 1 | 14.982 s | unconfirmed |

Content totals: 11 calls, 4 retries across 7 distinct source/final identities; 65.601 s. Both PDFs stop after two unconfirmed final checks and record degradation; no minutes-long retry loop. Source 2 and source 3 stop their retry after an issues finding rather than a pass.

## Every visual batch and every page

**Exact per-call provider durations and response bytes were not retained.** Model: openai/gpt-4o. Each row is one serial batch window, including PNG reads/hashes and response validation. Do not add a batch duration once per page. Page hashes and literal findings are retained in the JSON.

| PDF | Pages | Per-page outcome | Enclosing window | Exact provider elapsed | Retries | Window start UTC | Window end UTC |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Candidate PDF | 1, 2 | 1: pass; 2: pass | 2.365 s | not retained | 0 | 2026-11-14T06:57:50.779Z | 2026-11-14T06:57:53.144Z |
| Candidate PDF | 3, 4 | 3: issues (3 findings); 4: issues (3 findings) | 2.871 s | not retained | 0 | 2026-11-14T06:57:53.144Z | 2026-11-14T06:57:56.015Z |
| Candidate PDF | 5, 6 | 5: issues (3 findings); 6: issues (3 findings) | 2.946 s | not retained | 0 | 2026-11-14T06:57:56.015Z | 2026-11-14T06:57:58.961Z |
| Candidate PDF | 7, 8 | 7: pass; 8: pass | 2.299 s | not retained | 0 | 2026-11-14T06:57:58.961Z | 2026-11-14T06:58:01.260Z |
| Delivered PDF | 1, 2 | 1: pass; 2: pass | 2.399 s | not retained | 0 | 2026-11-14T06:58:51.726Z | 2026-11-14T06:58:54.125Z |
| Delivered PDF | 3, 4 | 3: unconfirmed; 4: unconfirmed | 3.384 s | not retained | 0 | 2026-11-14T06:58:54.125Z | 2026-11-14T06:58:57.509Z |

Delivered pages 5, 6, 7, 8: not reached by visual review; no verdict, no call duration and no retry. Delivered pages 3–4: the next loop batch failed/unconfirmed within its recorded window; the generic failure does not establish that its provider request was dispatched. Candidate page outcomes do not certify the changed delivered PDF.

### Literal candidate visual findings

- Page 3: Typography is somewhat cluttered, especially in the nutritional breakdown section. Suggest using more spacing to improve readability.

- Page 3: The transition between Recipe 1 and Recipe 2 could be clearer, possibly with a visual break or separator to delineate sections.

- Page 3: The color palette is minimal and functional, which works well, but small headers should be more distinct to enhance the hierarchy.

- Page 4: The list layout is cramped; adding some white space would improve legibility.

- Page 4: Typography consistency could be improved, particularly with the recipe list items—some items appear squeezed.

- Page 4: Consider using bullet points to better organize the preparation steps for clarity and flow.

- Page 5: Text alignment in callout box inconsistent

- Page 5: Callout box colors create low contrast

- Page 5: Stranded heading at base of page

- Page 6: Bulleted lists cramped; increase spacing for clarity

- Page 6: Avoidable orphan line at end of instructions

- Page 6: Excessive page length, consider splitting content

## Why there were four full passes

### Full pass 1 → 2

Source 1 was blocked solely by a requested_design_inadequate finding demanding a finalized polished PDF before the source was built. The next selection authored a new complete source.

- requested_design_inadequate — Beautifully designed PDF: The provided HTML source covers the recipes with structured headers and sections but does not yet demonstrate a finalized design layout as a visually polished PDF. Repair: Ensure the HTML source is converted into a well-designed PDF with a focus on editorial style, consistent typography, and appealing layout, utilizing branding colors and styles if a

### Full pass 2 → 3

Source 2 was blocked after one unusable check and one issues verdict. Findings included judging design unavailable in HTML and missing recipe-specific fat-loss explanations. The next selection authored a new complete source.

- underdeveloped_requested_item — Editorial Layout: The request called for a beautifully designed PDF with a considered editorial layout, but this cannot be evaluated in the HTML source. Repair: Ensure that the final PDF has a visually appealing and user-friendly editorial layout.

- underdeveloped_requested_item — High-Protein Diet Explanation: While the introduction provides an overview of why protein is important, it doesn’t fully explain why each specific recipe supports a high-protein fat-loss diet. Repair: Expand the explanation for each recipe to detail how it specifically supports a high-protein fat-loss diet.

### Full pass 3 → 4

Source 3 was blocked after one unusable check and one issues verdict. Findings demanded individualized calorie/protein explanations and an editorial-layout outline. The next selection authored a new complete source.

- underdeveloped_requested_item — total calories and protein per serving: The request requires detailed approximate calories and protein per serving to support a high-protein fat-loss diet. Only summary estimates are provided without individualized explanations. Repair: Enhance each recipe with specific explanations for the approximate calories and protein per serving to align with high-protein fat-loss benefits.

- underdeveloped_requested_item — editorial layout: The content lacks a clear editorial layout plan, focusing more on recipe details than presentation format described as editorial rather than decorative. Repair: Develop an outline or description of the intended editorial layout showcasing how it will be distinctly different from a simple list.

Full pass 4 receives a source pass and proceeds to build/proof. Its first rendered PDF then receives twelve visual findings across pages 3–6, causing the one 148-byte layout-only patch, followed by source check/build/proof of distinct final bytes. The final unconfirmed content checks did not trigger another full generation.

Full passes 2–4 alone cost 335.371 s of additional provider generation. The plan priced one complete response, not four. These are source-verdict-driven rewrites, not automatic author validation/transport retries. The source checker still demanded finished-PDF/editorial treatment before rendering; the earlier phase correction was not fully effective. Some recorded substantive explanation findings also contributed; this is not a claim that every objection was visual.

## Non-overlapping completion-clock accounting

Nested provider and complete-author stage clocks are separated. Classification, selection and visual rows are enclosing windows, not exact provider durations. All recorded stage intervals are checked for overlap before publication. Foreground command observations cover execution only, not API handoff or surrounding checks. Residual is arithmetic, not an invented measured stage; small cross-clock observation skew is included in it.

| Category | Elapsed | Basis |
| --- | --- | --- |
| Initial classification window | 1.147 s | Timestamp-derived, exact provider unavailable |
| Author stages (four full + patch) | 444.504 s | Measured; includes 442.096 s provider + 2.408 s wrapper |
| Selection / closing windows | 57.177 s | Timestamp-derived, exact provider unavailable |
| Source content checks | 37.848 s | Measured attempts |
| Final content checks | 27.753 s | Measured attempts |
| Visual windows | 16.264 s | Timestamp-derived including page I/O / validation |
| Actual foreground commands | 20.232 s | Harness observations; cached guide excluded |
| Remaining routing, I/O, handoffs, capture, network | 29.286 s | Arithmetic remainder |
| Total to completion received | 634.211 s | Reconciles exactly to 634211 ms |

Planning reconciliation: 339.886 s more author-provider time than the planned 102.210 s, plus 29.100 s more other time than the planned 163.015 s, equals the full 368.986 s overrun. No speed improvement is established.

## Every actual foreground command

| Operation | Proposal | Measured elapsed | New execution | Outcome |
| --- | --- | --- | --- | --- |
| memory_read | 8cec075a-e5e9-453b-887b-c83d1e1b5449 | 0.084 s | yes | exit_0_complete |
| skill_index | ba5e928f-cfb2-4efc-bd1c-da9fdfec7b67 | 0.094 s | yes | exit_0_complete |
| skill_read | 3cac09fa-fe03-41e1-8824-8d4a62a7fd81 | not retained | no — original-bound cached guide | exit_0_complete |
| workspace_inventory | 5bc5ba29-c8b8-4ed5-a57e-495e3799671b | 0.110 s | yes | exit_0_complete |
| source | 96309b45-cb6a-4c74-baff-165a5bf85c74 | 0.773 s | yes | exit_0_complete |
| source | b8a2bc67-bbed-45b9-8dee-0123d469313e | 0.725 s | yes | exit_0_complete |
| source | 82ca0a9c-3e3a-46ac-98b3-05afd7b8f041 | 0.738 s | yes | exit_0_complete |
| source | b7450130-6419-4af3-a45b-a406ddceb043 | 1.075 s | yes | exit_0_complete |
| build | 7beecfbd-7e04-4d8a-8205-53754b8ce32e | 5.834 s | yes | exit_0_complete |
| independent_proof | 7dd52240-c636-467e-b003-87a47e9161fc | 2.024 s | yes | exit_0_complete |
| source | 126be6ae-8f1c-465c-921b-7122764a5cea | 0.742 s | yes | exit_0_complete |
| build | f5de22fb-ddd3-4401-ab17-a18700d1745e | 5.240 s | yes | exit_0_complete |
| independent_proof | ce8d58a4-5ea9-449f-b1b9-7a9a2f2d5f50 | 2.074 s | yes | exit_0_complete |
| memory_write | e08c6a37-dfde-4a52-aad7-346e187558e7 | 0.719 s | yes | exit_0_complete |

## Outcome and limits

Actual immutable PDF: 36,646 bytes / 8 pages; SHA-256 24ee8bf7eda8fdc5a4e4815a20d3db66f963cb9398a87c954e76b7537f0229e1. Capture/build/proof/download bytes agree. Content remains unconfirmed and final visual review unavailable: delivery closed, quality acceptance did not pass.

- The initial GPT-4o classification is a separate model call: only its 1147 ms enclosing window is retained, not response bytes or exact provider duration. The following briefing is fixed text, not another generation.

- No exact visual provider durations or response byte counts were retained. Every available page verdict and timestamp-bounded batch/failure window is included instead.

- Successful selection response byte counts and exact provider elapsed times were not retained. All observed selection starts and enclosing windows are included; missing is not zero.

- Delivered-PDF visual failure has only document_visual_review_unavailable; dispatch/HTTP/parser/uncertainty cause cannot be recovered. Pages 3–4 identify the next loop batch, not proof of provider submission.

- Content checks compare complete source/extracted text, not separate per-page calls. Neither failed final-content attempt confirms individual page coverage.

- Raw checker responses were not retained; the recorded grounding diagnostics are not sufficient to recover the rejected literal quote.

- Earlier delivered reports/PDFs remain unchanged. No new paid task, re-review, capture, deployment or device/browser interaction is performed for this accounting.

Provenance: 110 ordered owned frames, 14 receipts (13 new executions + one original-bound cached guide), 11 exact content-attempt Events. Raw evidence hashes and every page/hash binding are in the JSON companion. Only retained records were analyzed; zero new provider calls, remote commands or replays.

The JSON companion uses the established title/task identity/timings/authoring/providerGenerationMs/evidence/quality record envelope and preserves the earlier author-vitals field names. Original evidence reports are not overwritten.
