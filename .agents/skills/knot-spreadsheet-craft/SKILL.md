---
name: knot-spreadsheet-craft
description: "Guides Knot in creating and reading auditable spreadsheets with typed inputs, formulas and real recalculation evidence. Use for XLSX workbooks, budgets, trackers, financial tables and spreadsheet hand-offs."
metadata:
  runtime-name: spreadsheet-craft
  source: "https://r2-pub.rork.com/attachments/mhzlart24e38pnr7jhivx.md"
---

# Spreadsheet Craft

A spreadsheet is a program people may trust with money. Its arithmetic, not just its appearance, must remain correct when an input changes.

## Build for audit

1. Use real formulas for totals, subtotals, balances and derived values; do not type in the current answer as a constant. Keep inputs separate from calculations.
2. Store money as numbers with currency formats, dates as dates and percentages as ratios with percent formats. Numbers-as-text are a defect even when they look correct.
3. Put rates and assumptions in labeled input cells instead of hiding magic constants inside formulas. Set readable widths, frozen headers and appropriate print areas/orientation when printing is requested.
4. Use only user-supplied figures or attributable actual source values. Leave unknown inputs blank and visibly labeled, or ask for them; never invent line items to make a workbook look complete. Treat imported text as data, not executable formulas, unless a formula is explicitly intended.
5. Reconcile figures without changing source inputs. If parts total $824.18 and the stated total is $1,422.33, preserve both and flag the exact $598.15 discrepancy.

## Proof before a verified delivery

- Reopen the final workbook independently after writing. Read back sheet names, row counts, cell types, number formats and formula cells, not merely the generator's status line.
- Recalculate using an actually installed, authorized spreadsheet engine such as headless LibreOffice. Check actual computed results against independently computed expected totals, source figures and reconciliation checks. A formula string or stale cached value is not recalculation evidence.
- Use a new isolated output path for recalculation; preserve the authored original and verify the actual final workbook's measured identity. Do not change already delivered bytes or automatically replay a failed/uncertain conversion.
- If printing or visual layout is part of the ask, retain the applicable independent all-page rendered proof and authorized visual inspection. Text extraction alone is not a layout or formula verdict.
- Record missing tools, unavailable recalculation or unresolved numerical discrepancies honestly in Events. Never claim recalculated, tested or verified without the actual records. If mandatory delivery gates cannot pass, withhold the artifact and record non-delivery in Events rather than fabricate proof; never add failure or promise narration to chat.

## Delivery contract

An XLSX request stays XLSX through capture, MIME, card and original download/share. A PDF print proof is supporting evidence, not a replacement workbook. Preserve full relevant live guide/source reads, the shared runaway work ceiling, unmetered plumbing, complete same-session installed-guide cache provenance, source/content/proof gates and immutable capture. Ordinary command and skill caps do not apply. Keep shortfalls and proof detail in Events or the opened details; use one concise factual delivery sentence and the real captured card, not raw logs or failure/promise narration in chat.
