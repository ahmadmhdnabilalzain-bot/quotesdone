---
name: sunday-plan-deep-portal-audit
description: "The plan the founder set for Sunday 20 Sep 2026: a hands-on deep audit of both portals, plus the queued removals and document gaps"
metadata:
  type: project
---

Set 18 Sep 2026 when he stopped work at 98% of his weekly usage. Instructions 520-528. **Read this before starting Sunday.**

## 1. The deep audit (instruction 528) — the main event
A hands-on browser walk, not an automated suite. Both portals, EN + full AR, desktop + phone, seeded with REALISTIC data so panels are not empty. Press every button and control, including ones no test reaches.
- Open a real conversation with the sales engineer on an inquiry; edit a quotation through the review and re-submit.
- Open EVERY generated file and judge it against our template: inquiry sheet, quotation, comparison report, invoice, receipt.
- The drawing pipeline: upload, redaction, how it renders, whether a supplier can actually read it.
- The BOQ pipeline: extraction, per-line confidence, units, how it reads to a supplier pricing it.
- He expects findings he has not thought of — report anything that looks wrong even when unasked. Judge each surface as a supplier or customer would: would this make me trust the platform, or leave it.

## 2. The four document gaps he found in ten minutes (do these too)
- **No inquiry PDF exists** on our template — the screen was built, the document never was (his spec of 15 Sep said the inquiry opens the sales engineer template).
- **The generated quotation is invisible to the supplier who owns it** —  appears only in the customer portal; the supplier never sees the document sent in their name.
- **Expiry dates are typed by hand** in Documents while  exists to read them — it runs through ai_gateway, so full auto-extraction is blocked by the OpenRouter hold; attempt-then-confirm with an honest fallback is available today.
- **Every document everywhere must offer View / Download / Replace / Remove** (instruction 524): Replace keeps the old version and re-runs extraction; Remove hides, never destroys, and is refused on sealed records (signed terms, paid invoice, sanctions) and on a mandatory-six document of an approved supplier without demotion.

## 3. Removals he ordered (instructions 525, 527, and 526)
- **3D company environment** and **supplier network map** — useless; delete code, tabs, the .gltf and any now-unused 3D library; report the bundle weight saved.
- **Negotiations**, both portals — supplier  and customer  + its parts, and the  function if unused. It is fetched on the customer overview load, so measure the request saved (that screen still fails its 2.5 s target on ar-mobile).
- **IBAN / bank details, entirely** — prove no money path depends on it (Stripe holds the rails) and PURGE any stored value, reporting the row count; holding an unused bank number is a PDPL liability.
- **Open question, not yet decided:** the supplier catalogue upload has run ONCE in its life (9 Sep) and  holds 0 rows; its file reading goes through the held ai_gateway. Ask whether it is worth keeping before launch.

## 4. The knowledge chapter (instructions 520-523) — held to Sunday
See [[checkpoint-18-sep-portal-and-three-day-backlog]] for the full brief: purge the unrelated 2.5 M rows permanently (classification first, nothing cited or authored in the delete set, restorable copy, audit record), and rebuild to the doctrine — technical-director depth per trade: materials and specs, the brands actually supplied in the UAE with equivalence classes, engineering reasoning, approvals; all CODIFIED as rules the comparison engine executes, EN + full AR, citation + effective date, labelled law / practice / manufacturer data.  was NOT written before the stop. Primary sources already verified are in [[uae-authority-source-facts-18-sep]].

## 5. Also open
- PR #760 (incremental backups) is open and UNAPPLIED; its finding: the 52 Friday full copies kept 12 months are 592 GB of the ~612 GB — retention is the founder decision, not the daily copies.
- The rating defect is LIVE:  500s,  has 0 rows, no rating has ever succeeded. My ruling: stars alone suffice, comment optional. Agent was stopped mid-fix.
- Finish measuring WHICH SECTORS we cover (40 trades sold, 25 named in the taxonomy) — it defines the scope of the knowledge work.
- The Insights ranking panel tells every self-registered supplier "no quote has been submitted yet" while their quotes exist.