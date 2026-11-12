**customer_journey workstream. VERDICT: NO-GO as it stands; GO WITH FIXES once B1-B3 are fixed and re-measured.** Nothing was fixed (ledger 1641).

The Write tool refused `REPORT.md` (subagents may not write report files), so the full report is below for you to save. Data and evidence files are in my folder.

**What works.** Typed request and drawing+BOQ request both ran request → interview → live matching (10/10 own suppliers matched by the product) → quotes → comparison → test reveal → invoice. Fees exact (AED 286.62 and 3,212.97, 3%). No identity leak either way. Drawing count 7/7 exact, redaction 0 leaks, full drawing chain 37/37 on re-run.

**BLOCKER**
- B1. Voice note refused every time (`transcription_daily_cap`): an unset cap parses as 0. Journey 3 could not start.
- B2. The supplier's request PDF says "Required by: Not stated … answers were not recorded" on 2/2 requests: the masking trigger drops `customer_requirements`.
- B3. Every supplier (8/8 quotes) gets "your quote needs a few more details before we can send it" in the same second it is approved.

**HIGH**
- H1. Chat replies p50 17.9 s, p95 29.1 s, max 29.9 s (portal gives up at 30 s); it re-asks answered questions because two model steps are cut at the turn clock (23 of 41 attempts today, 3 of 37 on 10 Nov).
- H2. Fresh comparison 42-74 s; the customer's page aborted at 30 s, 2/2.
- H3. Quotation reader stores no quantity, unit or rate (0/56 lines); customer then sees "failed our completeness check" on every quote.
- H4. One-sheet drawing: 67 s, 0 lines; drawing model call cut at the 55 s wall 4 of 5 times.
- H5. Supplier's quote preflight over the 20 s wait 6/8 times.
- H6. Repo teardown fails after any quotation-chat run (#1943's append-only table). **6 ZZ DEMO support rows of run d9a04dbc remain that I cannot delete** (cases 2235, 2236).

**MEDIUM:** nine, listed below (wrong "rules-only" label on the expert comparison, "Best value" on the rejected quote, garbled brand-hiding, internal markers in the customer's quotation, a mis-recorded answer, a gypsum firm invited to HVAC, senseless hold-desk asks, duplicate guard would cancel 6 of 8 quote notices, no budget asked).

**Spend:** USD 2.5074 of 3.00 (51ff3afd 0.3796, d9a04dbc 1.8652, afa3c1d5 0.2626, dry 0).

**Not done:** journey 3 after the microphone; reveal notices (demo handoffs are not filed, ruling 1199); the supplier's on-screen request detail; the fifth quote in each journey. Lead 19398: 0 matches, 0 notices.

---

# Customer journey and drawing: final audit, 11-12 Nov 2026

Seat: customer_support (auditor). Production, ZZ DEMO only, report only. Every match in every run was `is_demo = true`.

The chain itself holds, with the money right to the fil and no identity leak. Three things are broken on every use: a supplier's copy of the request loses everything the customer answered, every supplier gets a false "needs more details" message at the moment the quote is accepted, and the voice note does not work. The chat is slow and re-asks what the customer already said.

## What was tested

| # | Test | Pass bar | Measured | Result |
|---|---|---|---|---|
| 1 | Journey 1, text only (PVC wall panels, Dubai), run d9a04dbc | request to invoice through the product's doors | RFQ 165437 after 10 customer turns; 5/5 suppliers matched by the product; 4 quotes live (5th: N3); comparison right; reveal AED 286.62 = 3% of 9,554; invoice right | PASS with findings |
| 2 | Journey 2, text + drawing + BOQ (villa HVAC), run d9a04dbc | same, drawing read and redacted | RFQ 165438 after 9 turns; BOQ file read 10/10 lines in 1.5 s; drawing redacted 1/1 page but read 0 lines after 66.9 s; 5/5 own suppliers matched plus 1 gypsum supplier; 4 quotes live; comparison right; reveal AED 3,212.97 = 3% of 107,099; invoice right | PASS with findings |
| 3 | Journey 3, voice note (staff bus, Abu Dhabi), run d9a04dbc | voice note becomes a request | `transcribe` answered HTTP 429 `transcription_daily_cap` on the first note; nothing after the microphone ran | FAIL (B1) |
| 4 | Drawing count, synthetic 8-sheet CAD set, runs 51ff3afd and afa3c1d5 | every quantity exact (duct within 0.5%) | 7/7 exact in both runs (2,400 air devices read 2,400; duct 16,432.9 m read 16,433.2 m, 0.002%) | PASS |
| 5 | Drawing redaction, same set | 0 planted identity strings on any surface | 0 leaks on 6 surfaces: BOQ lines, 8/8 redacted pages (OCR; the control read all 8 planted strings on the original), request row, supplier inbox, both inquiry PDFs | PASS |
| 6 | Drawing chain after the count | request reaches the supplier's PDF with every counted item | 51ff3afd: not run, harness fault (22/24). Re-run afa3c1d5 with two canned answers corrected: 37/37; ready after 6 turns, RFQ 165439, live matcher matched the demo supplier, inquiry PDF carries 6/6 counted items with quantities | PASS |
| 7 | Customer identity hidden from suppliers | name, e-mail, phone, title block absent | 0 hits in the supplier-safe copy of both requests, both inquiry PDFs, the BOQ CSV; title block painted out | PASS |
| 8 | Supplier identity and brand hidden before reveal | no company, brand or model | 0 hits in both comparison analyses, both comparison PDFs and 8 customer quote PDFs | PASS |
| 9 | Quotes read from the uploaded PDFs | prices, VAT, validity, terms, lines | ex-VAT total 8/8; line count and amounts 8/8; lead time and warranty 8/8; quantity, unit, rate 0 of 56 lines; VAT amount 0/8; origin per line 0/56 | FAIL in part (H3) |
| 10 | Comparison: top 3, totals, AED, VAT | correct, expert | both rankings correct and well argued; every figure I recomputed was right (differences, +5% VAT, per-sqm rates, weighted scores) | PASS with findings (M1-M3) |
| 11 | Test-mode reveal | 3% ex VAT, nothing else; right supplier unlocked | TEST key 2/2; processing fee 0.00; chosen supplier's name, phone, e-mail unlocked, the other three stayed hidden | PASS |
| 12 | Invoice | right payer, amount, wording | 2/2: "3% of the AED 9,554.00 quotation AED 286.62", paid, balance 0, not subject to VAT | PASS |
| 13 | Notifications exist once, none sent | 0 dispatched; one per event | 142 rows, all `suppressed`; one per event per channel | PASS on safety, FAIL on content (B3, M8) |
| 14 | Chat latency | reply under 10-15 s | 19 turns: p50 17.9 s, p95 29.1 s, max 29.9 s; 12/19 over 15 s | FAIL (H1) |
| 15 | Teardown | leftovers 0, windows closed | 3 of 4 runs 0. d9a04dbc: repo teardown failed; after my second pass 6 support rows remain. All 4 windows closed | FAIL (H6) |

## BLOCKER

**B1. The request chat's voice note is refused every time.**
- Evidence: 00:05:41 UTC 12 Nov, a 44 s note: HTTP 429 `{"ok":false,"error":"transcription_daily_cap"}`. The customer read "Could not transcribe that recording. Please type it instead." [E1]. `agent_runs` has 0 `transcribe` rows in 20 days, so no cap was reached.
- Root cause (verified): `app_secrets` has no `voice_transcription_*` key. `sttConfig` reads a missing key as `''`, and `num('', 300, 0, 100000)` returns 0 because `Number('')` is 0 and inside the range (`supabase/functions/_shared/speech_to_text.ts:78`). `transcribe/index.ts:50` refuses when `today >= cfg.dailyCap`, i.e. `0 >= 0`. Introduced by ddebe5c0e (10 Nov 20:40).
- Scope: the server path, used when the browser has no speech recognition (the harness turns it off). Browsers with their own were not measured. `perSenderDaily` falls to 0 the same way; the WhatsApp door compares with `>` (`wa_inbound/hear.ts:53`) and was not tested here.
- Fix: in `num`, treat an empty or non-numeric string as "use the default"; test the unset key.

**B2. The supplier's copy of a request drops everything the customer answered.**
- Evidence: both inquiry PDFs say "Required by: Not stated", "Installation: —", "Warranty: —" and "The customer's answers on materials, installation, warranty and the required date were not recorded on this request" [E2, E3]. The customers had given 15 Dec 2026 and 2 years; 31 Jan 2027, a Japanese brand and a 5-year compressor warranty. `inquiries.spec.customer_requirements` holds them.
- Root cause (verified on the live function and both rows): `scrub_inquiry_contacts` builds `spec_masked` by dropping every top-level spec key whose value contains Arabic script. `customer_requirements` always carries `display.ar` and `label_ar`, so the whole key goes. The PDF reads only that key (`_shared/quote_documents/inquiry_document.ts:58-88`); so does the portal's "requested" block (`supplier_api/quote_review_actions.ts:106`, by code). Of 4 requests in the table, the 3 from September keep the key; both of today's lose it.
- The `new_inquiry` e-mail and WhatsApp text does carry the answers, so the notice and the document disagree.
- Fix: keep `customer_requirements` in the trigger and strip only its Arabic members; re-save existing rows.

**B3. Every supplier is told the quote "needs a few more details before we can send it" in the second it is sent.**
- Evidence: 8 of 8 live quotes, e-mail and WhatsApp. Quote c946acf8: 23:38:45 customer `new_quote`; 23:38:46 supplier `quote_coaching` "please add … a unit price on every line item, the brand and model for each item, labour / installation cost … and we will send it to the customer right away"; 23:38:47 supplier `quote_spec_released` "Your quote is approved … now with the customer". The supplier's PDF had a rate on every line.
- Root cause (verified): `fn_quote_coach` writes the notice whenever `fn_quote_structured_score` says not submittable, and is called at acceptance (`supplier_api/lib/quote_acceptance.ts:108,113`). The score fails because the reader stores no unit price (H3).
- Fix: do not coach a quote that was accepted or released; fix H3.

## HIGH

**H1. The chat is slow and re-asks what the customer already said.**
- Evidence: p50 17.9 s, p95 29.1 s, max 29.9 s. Four journey-1 turns took 28.9-29.9 s; the portal gives up at 30.0 s (`src/components/me/api.ts:26`). 0 turns timed out, 0 were left pending; the "still working" line showed at 8.3 s on 18/19.
- After each 29 s wait the customer got the fixed text "Thank you. A few specifications are still open…" listing questions already answered: wall size (given in the second message: 12 m x 2.8 m, 34 sqm), style (light oak, matt), supply or install (supply and installation) [E4]. Journey 2 asked the system type three times after the first sentence said "ducted split units concealed in the false ceiling".
- Root cause (verified in `ai_cost_log` and `inquiry_intake/turn_clock.ts`): the exact-spec reading (`customer_communication`) and the held reply (`conversation_reply`), both gpt-6-luna-pro, are cut at the 24 s turn budget with 0 output; by design a cut reading "is simply asked" and a cut reply falls back to the list. Today, three runs: 23 of 41 attempts cut (my journeys 13 of 22). 10 Nov, three runs: 3 of 37. Output tokens on the reading rose from about 1,100-1,300 to 1,600-2,100. Effort for these classes became medium on 11 Nov 10:14 (f78d2e916); the clock was last changed 3 Nov.
- Fix: low effort for these two steps, or run the spec reading beside the interview call. Do not lengthen the clock.

**H2. A fresh comparison takes 42-74 s; the customer's page stops waiting at 30 s.**
- Evidence: the customer's open page asked for the comparison when the second quote arrived and was aborted at 30,004 ms (journey 1) and 29,997 ms (journey 2). Fresh comparisons through the API took 55.0 s and 73.7 s; the four model calls took 41.5-70.6 s (USD 0.15-0.24 each). Cached answers took 1.5-2.3 s (6/6). On an abort the panel shows "We could not prepare the comparison report…" (`Comparison.tsx:56-67`, read in code, screen not captured).
- Root cause: `Comparison.tsx:74` uses the default 30 s; `quote_comparison` is high effort since 11 Nov.
- Fix: give that call the 150 s the comparison PDF already has.

**H3. The quotation reader keeps totals and loses quantity, unit, rate, VAT amount and origin.**
- Evidence: 8 PDFs, 56 lines, each with Qty, Unit and Rate. Stored `quote_items`: qty, unit, unit_price, country_of_origin all 0/56; `quotes.vat_amount` 0/8.
- What the customer sees: blank Qty/Unit/Rate columns [E5]; "No quantities or unit rates given" and, in red on every quote, "it failed our completeness check (score 55)" [E6]. Our own hold desk had released all eight.
- Root cause (verified): `quote_extract/quote_from_document.ts:35,128` builds a line as `{description, qty: "34 m2", amount}`: quantity and unit in one string, the rate computed and discarded.
- Fix: carry `qty`, `unit`, `unit_price` and the VAT amount through to `submit_quote`.
- Limit: where the reader left a term blank the harness typed the fixture's value, so a missed validity or payment term would not show.

**H4. A one-sheet drawing took 67 s and came back with no quantities.**
- Evidence: journey 2's sheet carries an equipment schedule and a legend with quantities. The customer waited 66.9 s and read "I could not pull a bill of quantities out of this file". On 10 Nov the same file gave 12 lines with models off. Across my three runs the drawing model call ended at 54.6-54.8 s with 0 output 4 of 5 times; the one that finished took 46.9 s. The 8-sheet set took 71.4 s and 69.3 s (the code count answered), a single sheet 55.9 s and 66.1 s.
- Root cause: `drawing_and_boq_analysis` is high effort since 11 Nov and meets the gateway's 55 s wall (`ai_gateway/handle.ts:472`). Why the fallback returned 0 lines for the villa sheet was not established.
- Fix: answer from the code reading when it has lines; let the model add only inside the wall.

**H5. A supplier's "check my quote" outlasts the portal's wait.**
- Evidence: the preflight took 66.6, 42.3, 43.8, 2.1, 1.8, 31.6, 42.0 and 35.7 s: 6 of 8 over the 20 s default (`src/components/portal/supplier/api.ts:74`; `QuoteForm.tsx:60`). The real submit took 3.1-4.4 s; reading the PDF 21.9-37.8 s.
- Fix: pass `REASONING_TIMEOUT_MS` to the preflight.

**H6. The repo's teardown fails on any models-on run that used the quotation chat.**
- Evidence: d9a04dbc: `23503 … "support_case" violates foreign key constraint "support_case_summary_version_case_id_fkey"`, twice. It left 3 customers, 15 approved ZZ DEMO suppliers, 2 requests, 140 suppressed notices, 18 auth users.
- Root cause (verified): #1943's `support_case_summary_version` is append-only (trigger `a00_support_case_summary_version_append_only`, ruling 1634) and references `support_case`; `demo_factory.teardown` knows neither it nor `support_case_promise`, stops there and runs nothing after. `fixtures.sweepStaleRuns` will meet the same error.
- What I did: a second pass with a copy of the teardown that skips such cases removed everything else. Remaining: `support_case` 2235 and 2236, `support_customer_profile` 1036 and 1037 (qd-d9a04dbc-sup4 / sup10@example.invalid), and their 2 summary versions.
- Fix (yours): a demo exemption in the append-only trigger or a guarded delete routine; add both tables to the teardown.

## MEDIUM

- **M1. The expert comparison is labelled rules-only.** "Comparison by our rules" with the badge "Ranked on stated figures — specs not assessed" above a report that assesses specs [E6]. `Comparison.tsx:74` treats any `analysis.disclaimer` as degraded; `quote_compare/index.ts:470` sets one on the expert path. Fix: use `j.degraded` alone.
- **M2. "Best value, Value 100/100" sits on the quote the comparison rejects** (Chinese panel, fire class E, 1-year warranty), under "It is a lower spec, not a saving" [E7]. Our review note on it names the warranty only.
- **M3. The brand hider rewrites ordinary words.** "None of the quotes say they priced model stated (shown after reveal) working" where the after-6-pm requirement belongs (four places); `generated_at: "model stated (shown after reveal):44:05.271Z"`; BOQ line 3's "(DSU-05, DSU-06)" replaced while lines 1-2 keep theirs. In `_shared/quote_generalise.ts`; not root-caused further.
- **M4. The customer's standardised quotation prints internal markers** ("na:brand: GI ductwork · na:model: … · names:ducting: …") [E5], and on all 8 quotes "Supplier's note: Read from the PDF file with no model: N priced line(s). Please check every figure before sending." Cause of the note (verified): `QuoteForm.tsx:44` puts the reader's `proposal.notes` into the notes-for-customer field.
- **M5. One answer was recorded against the wrong question.** "Ducting: Other: Daikin or Mitsubishi" (the AC brand), and "Warranty: at least 2 years" for "5 years on the compressors and 2 years on the installation" [E8]. The free-text spec has both right.
- **M6. A gypsum company was invited to the villa HVAC job** (1 of 6 invitations; the founder's demo supplier 126512): "concealed in the false ceiling" became the service key `gypsum.false_ceiling`.
- **M7. The hold desk holds every uploaded quotation (8/8, all released in one round) and asks for details that are stated or do not apply:** the refrigerant on lines whose specification says "R32", a refrigerant and a model for copper piping, a brand for "Repair of swollen MDF boards", warranty coverage the PDF states.
- **M8. Duplicate guard.** All `new_quote` notices on a request share one subject and body (`quote_acceptance.ts:52`). By the guard's own key, 6 of 8 e-mails and 6 of 8 WhatsApp notices repeat one sent 85-141 s earlier and would be cancelled for a real customer. Not observed as cancelled: demo rows are `suppressed`, a status the guard does not count. Fix: put the quote id in `dedupe_key`.
- **M9. The interview never asked a budget (0 of 2) and its first replies were poor.** Journey 2's first reply was the bare label "Thanks, noted. Unit type (wall split / ducted / cassette / floor)". Journey 1's first screen listed 12 fit-out and gypsum-partition items (landlord handover, MEP scope, acoustic rating) for a PVC panel job [E9]; it corrected on turn 2. Advice was thin.

## LOW

- The masker hides ordinary words in the supplier's copy: "In our [hidden] in Business Bay" (office), "a new G+1 [hidden]" (villa); 5 places.
- Quotation chat: the thread says "changes requested" about 17 s before the message and the list exist (2/2). The reader then asked for VAT basis, validity and warranty that the PDF states.
- `drawing_redact` answered 546 on 2 of 11 calls in each drawing run (attributed by time window); all 8 pages still came out.
- The customer's request card shows field names as labels ("Spec Warranty:", "Supply Install:") and two progress trackers.
- The redaction band clips the right edge of two room tags; still legible.
- "Trade HVAC / Air" cut short; "skirting.. Log in"; "Wallpaper" as the trade for wall panels; "win rate 0%" on a new supplier; the BOQ's file name stored as the drawing's.
- No e-mail or WhatsApp confirms to the customer that the request was posted.
- The drawing harness's "Arabic inquiry PDF" came back under the English file name; not looked into.

## The two questions I was asked to measure

- **(a) Duplicate guard:** 8 live quotes, 8 `new_quote` e-mails, 8 WhatsApp; none cancelled (demo). A real customer would have received 2 of 8 per channel (M8).
- **(b) Effort raise against unchanged timeouts:** confirmed in four places (H1, H2, H4, H5). No chat turn timed out or was left with a holding line and no answer; four came within 1.1 s of the cut.

## Latency (run d9a04dbc, ms)

| Step | n | p50 | p95 | max | Verdict |
|---|---:|---:|---:|---:|---|
| Customer portal data calls | 136 | 1,011 | 2,866 | 6,881 | ok; 7 over 3 s |
| Chat reply | 19 | 17,918 | 29,146 | 29,862 | too slow; 12 over 15 s |
| "Still working" line appears | 18 | 8,259 | 8,327 | 8,335 | as designed |
| Send to suppliers | 2 | 8,069 | | 8,686 | slow for a button |
| BOQ spreadsheet read | 1 | 1,508 | | | ok |
| Drawing read, one sheet | 1 | 66,921 | | | too slow, and empty |
| Comparison, fresh | 2 | 64,308 | | 73,654 | page gives up at 30 s |
| Comparison, cached | 6 | 1,853 | | 2,269 | ok |
| Comparison PDF | 2 | 3,872 | | 4,328 | ok |
| Customer quote PDF | 8 | 2,090 | 6,001 | 7,683 | ok |
| Reveal: session / confirm | 2 / 2 | 1,371 / 1,512 | | 1,537 / 1,514 | ok |
| Invoice PDF | 2 | 3,261 | | 3,379 | ok |
| Supplier: quotation PDF read | 8 | 32,646 | 37,721 | 37,774 | slow, inside its 90 s |
| Supplier: quote preflight | 8 | 38,842 | 58,651 | 66,629 | 6 of 8 over the 20 s wait |
| Supplier: quote submit | 8 | 3,913 | 4,385 | 4,447 | ok |
| Supplier: hold desk fill / approve | 8 / 7 | 5,108 / 4,794 | | 5,279 / 5,327 | ok |
| Supplier portal data calls | 22 | 1,018 | 1,684 | 1,759 | ok |

## Not measured, and why

- N1. **Reveal notices to supplier and customer.** `fn_seat_handoff` files nothing for a demo row (ruling 1199), so no ZZ DEMO journey produces `reveal_receipt` or `quote_accepted`; the screen says "The supplier has been notified". The last such rows are from 21 Sep 2026. The function's own rolled-back probe (`qd.probe_files_demo_handoff`) can prove it; I may not run writes.
- N2. **The supplier's on-screen request detail:** the harness photographed it before it loaded, both journeys.
- N3. **The fifth quote in each journey** (leaves out scope, quotation chat): the harness stopped on the 17 s gap. Each comparison ran on 4 quotes; the "excluded scope" note was not exercised.
- N4. **Journey 3 after the microphone.**
- N5. Arabic, phone screens, browsers with their own speech recognition.

## Spend (ai_cost_log by run tag)

| Run tag | What | Cap | Calls | USD |
|---|---|---:|---:|---:|
| 61b0e6a4 | dry run of journey 1, models off | 4 | 0 | 0.0000 |
| 51ff3afd | drawing harness | 0.80 | 35 | 0.3796 |
| d9a04dbc | journeys 1, 2, 3 | 2.50 | 99 | 1.8652 |
| afa3c1d5 | drawing harness re-run | 0.60 | 21 | 0.2626 |
| | **Total** | 3.00 | 155 | **2.5074** |

Inside d9a04dbc: the interview USD 0.97 (20 calls, about 0.05 a turn), four comparisons USD 0.78, everything else USD 0.11.

## Teardown (read back at 00:34 UTC)

| Run | Leftovers | Window |
|---|---|---|
| 61b0e6a4 | 0 | closed |
| 51ff3afd | 0; 0 of 9 named storage objects | closed |
| d9a04dbc | 2 support profiles, 2 support cases, 2 summary versions (H6); everything else 0 | closed |
| afa3c1d5 | 0; 0 of 11 named storage objects | closed |

## Harness notes

- No repo file, no file in `/tmp/claude-0/main-base` and no branch was changed. Audit copies in my `harness` folder: `evidence_pack_audit.mjs` (timing of every turn and call, a Try-again press if the portal stops waiting, a dump of the run's rows before teardown), `drawing_audit.mjs` (window cap, two corrected canned answers), `demo_factory_audit.mjs` (the H6 teardown workaround). `mkpatch.mjs` shows each change.
- Harness faults, not product: the comparison crop looks for a title the page no longer prints; the supplier-detail screenshot does not wait; the quotation-chat poll stops on the first non-"reviewing" state; the drawing harness answered "ceiling cassettes" with "No ceiling works"; one `spec_approve` returned status 0 to the harness while the server released the quote.
- `QD_ROUTE_FUNCTIONS_VIA_NODE=1` was set, so the container's 30 s cut decided nothing; the portal's own 30 s did.

## Evidence

Folder: /tmp/claude-0/-home-user-quotesdone/1e789c53-f6dc-5392-adad-7c77c9edb8b7/scratchpad/audit/customer_journey

- [E1] The audit's screenshot `3_voice_note/04_voice_note_1_transcribed_into_the_box.png` (session scratch, not in git: screenshots stay out of the repository per docs/reports/README.md; the quoted on-screen sentence above is the record).
- [E2] /tmp/claude-0/-home-user-quotesdone/1e789c53-f6dc-5392-adad-7c77c9edb8b7/scratchpad/audit/customer_journey/out/real/1_text_only/42_inquiry_as_sent_to_suppliers.pdf
- [E3] /tmp/claude-0/-home-user-quotesdone/1e789c53-f6dc-5392-adad-7c77c9edb8b7/scratchpad/audit/customer_journey/out/real/2_text_drawing_boq/42_inquiry_as_sent_to_suppliers.pdf
- [E4] /tmp/claude-0/-home-user-quotesdone/1e789c53-f6dc-5392-adad-7c77c9edb8b7/scratchpad/audit/customer_journey/out/real/1_text_only/10_customer_answer_7.png
- [E5] /tmp/claude-0/-home-user-quotesdone/1e789c53-f6dc-5392-adad-7c77c9edb8b7/scratchpad/audit/customer_journey/out/real/2_text_drawing_boq/quotations/Q1_as_the_customer_sees_it_p2.jpg
- [E6] /tmp/claude-0/-home-user-quotesdone/1e789c53-f6dc-5392-adad-7c77c9edb8b7/scratchpad/audit/customer_journey/out/crops/J1_cmp_a.png
- [E7] /tmp/claude-0/-home-user-quotesdone/1e789c53-f6dc-5392-adad-7c77c9edb8b7/scratchpad/audit/customer_journey/out/crops/J1_reveal_2.png
- [E8] /tmp/claude-0/-home-user-quotesdone/1e789c53-f6dc-5392-adad-7c77c9edb8b7/scratchpad/audit/customer_journey/out/real/2_text_drawing_boq/15_ready_summary_before_send.png
- [E9] /tmp/claude-0/-home-user-quotesdone/1e789c53-f6dc-5392-adad-7c77c9edb8b7/scratchpad/audit/customer_journey/out/real/1_text_only/03_customer_first_message.png
- Redacted drawing page a supplier downloads: /tmp/claude-0/-home-user-quotesdone/1e789c53-f6dc-5392-adad-7c77c9edb8b7/scratchpad/audit/customer_journey/out/real/2_text_drawing_boq/supplier_view/Job_165438_drawing_p01.jpg
- Chat transcripts: /tmp/claude-0/-home-user-quotesdone/1e789c53-f6dc-5392-adad-7c77c9edb8b7/scratchpad/audit/customer_journey/out/real/1_text_only/chat_transcript.txt and /tmp/claude-0/-home-user-quotesdone/1e789c53-f6dc-5392-adad-7c77c9edb8b7/scratchpad/audit/customer_journey/out/real/2_text_drawing_boq/chat_transcript.txt
- Numbers: /tmp/claude-0/-home-user-quotesdone/1e789c53-f6dc-5392-adad-7c77c9edb8b7/scratchpad/audit/customer_journey/out/real/ANALYSIS.txt (with `chat_turns.json`, `latency_calls.json`, `manifest.json` and the `rows_*.json` dumps beside it)
- Drawing runs: /tmp/claude-0/-home-user-quotesdone/1e789c53-f6dc-5392-adad-7c77c9edb8b7/scratchpad/audit/customer_journey/out/drawing/drawing_result.json and /tmp/claude-0/-home-user-quotesdone/1e789c53-f6dc-5392-adad-7c77c9edb8b7/scratchpad/audit/customer_journey/out/drawing/drawing_result_rerun.json
- Leftover and spend read-back: /tmp/claude-0/-home-user-quotesdone/1e789c53-f6dc-5392-adad-7c77c9edb8b7/scratchpad/audit/customer_journey/out/final_proof.txt
- Every read-only query used: /tmp/claude-0/-home-user-quotesdone/1e789c53-f6dc-5392-adad-7c77c9edb8b7/scratchpad/audit/customer_journey/sql
