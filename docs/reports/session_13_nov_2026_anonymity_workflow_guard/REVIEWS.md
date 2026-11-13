# Independent review: sales_engineer-the-list-is-shown-the-moment-it-is-stored (fd962b3a6), 12 Nov 2026
VERDICT: MERGE. No blocker. Two SHOULD FIX items can land after the merge (they come from code that already existed). The branch merges cleanly onto origin/main (no file overlaps).

Code read: every changed line.
- `show()` is the old body of `load` moved word for word. On the poll path it gets the same `services_state` answer that the full load gets: same action, same shape, nothing thinner. Error handling stays in `load`: a failed poll changes nothing and asks again.
- These are unchanged: `keepText`, the reset rules, the screen-1 ticks restore for the same reading and their discard for a newer one, `qd-svc-step`/firstStep, `cards` answer merge, `asked`, and the confirmed path.
- Cadence: start to start is at least 2 s. Only one ask is in flight at a time. It stops at 10 minutes. The cleanup ignores a late answer after an unmount, a tab switch or a token change.
- The dashboard read fires once when the reading lands. `onStatus` dedupe compares all 4 fields.
- `servicesLeft` hides the "Why:" line only for reason=services_unconfirmed under the reading card. A licence hold has the `needed` card kind, so its line stays (I walked this: line visible throughout). action_required has no card.

Findings
1. SHOULD FIX (pre-existing race, slightly wider now). ServicesTab.tsx:236 vs :209.
   Problem: `load()` (after a Confirm or Update) and the poll's `onFinished` have no ordering guard. If a poll asked before the save's write lands after the save's `load()`, the older state is drawn. For a confirmed supplier mid-reading, that means a stale `capability.confirmed_at`, and screen-1 rows reappear.
   Fix: add `const seqRef = useRef(0)`. Take `const n = ++seqRef.current` before each fetch in `load` and inside `fetchState`, and draw only if `n === seqRef.current`. Alternatively, have `load()` call the poll's stop.
2. SHOULD FIX (pre-existing, same as main's `load({keepText:true})`). servicesRead.ts:14 `reloadSet(keep)` keeps `cur` and ignores fresh.
   Problem: a list that arrives live never pre-ticks `stated` proposals (ServicesTab.tsx:182). A page reload does pre-tick them.
   Fix: `setPropTicked(cur => new Set([...cur, ...statedKeys]))` when keep and `cur` holds no key of this reading.
3. NOTE: supplier_doc_trades.ts:553 (the "unchanged continuation" store) and markReading keep `source_docs.reading_progress`.
   Effect: a stale summary from a killed or continued read makes `stepALanded` true at the start of the next reading. The poll then runs at 2 s through step A (about 40 asks instead of 15), and the old summary shows.
   Fix: strip `reading_progress` in markReading.
4. NOTE: the `min-h-56` holder.
   - 390: 224 px holder with 66 px of bars. The summary block measured 436 px, so the hold does not cover a long summary on a phone.
   - 1440: summary content is 180 px in a 224 px block, a 44 px empty band.
   - Not reached by a finished or no-summary reading (the holder leaves with `profileState` 'reading').
   - A confirmed supplier whose only profile document is being re-read also gets the 224 px holder above his list. That is acceptable.
5. NOTE: the checks. Updated checks are not loosened in substance:
   - test 13 pins the guarded progress update.
   - the found-no-service check now pins `show(keepText)` and POLL_FOR_MS. The cap is proved behaviourally in servicesPoll.test.
   - the lands-on-step check pins `onStatus(next)`. Field comparison is pinned in servicesPoll.test.

What I ran (worktree removed afterwards; dev --webpack on 3181, stub of my own on 8881; harness in scratchpad/rev-show/)
- Tests: servicesPoll.test plus the 4 touched checks: 44/44 pass. Portal unit tests: 119/119. `tsc --noEmit`: clean. Full `scripts/checks/run.mjs`: every failure is outside the branch (production DB and `@/` alias in plain node, 7 files). None is in the 8 changed files.
- Real Dashboard shell, stored to on screen, no-step-A and fail/hold/confirmed runs at 390 unless noted:

  | Scenario | Width | Runs | Median | Worst |
  |---|---|---|---|---|
  | Warm (0.3 to 1 s answers) | 390 | 6 | 1.77 s | 2.38 s |
  | Cold (3 to 4 s answers) | 390 | 6 | 5.92 s | 6.80 s |
  | Warm | 1440 | 3 | 2.19 s | 2.60 s |
  | Cold | 1440 | 3 | 5.45 s | 7.16 s |
  | No step A (5 s cadence throughout) | 390 | 2 | 4.5 s | 5.4 s |
  | Reading fails | 390 | 2 | 0.9 s | 4.9 s |
  | Licence hold | 390 | 2 | 1.0 s | 2.5 s |
  | Confirmed supplier, new profile | 390 | 2 | 1.3 s | 2.5 s |
  | Confirmed supplier, new profile, cold | 1440 | 2 | 6.4 s | 6.5 s |

  For comparison, the author's main baseline: warm 4.2 s, worst 6.6 s; cold 8.9 s, worst 12.5 s.
- Requests after stored: 1 in all 34 runs. Dashboard reads after stored: 1 in all.
- Poll gaps: 5.1 to 6.0 s, then exactly 2.0 s (warm) or 3.1 to 3.9 s back-to-back (cold). Never under 2 s.
- CLS at the list's arrival: 0 in all runs. The 0.1718 seen in some runs is the initial "Loading your services" panel at about 1.9 s, which is not this change.
- No horizontal scroll.
- Race (3+2 runs): I typed in his words and ticked "Turnkey fit-out" 27 ms to 1.4 s before the list was drawn. After it was drawn, React state still held both. The screen moves to step 'understood' as on main.
- Full walk: list, then "Yes, all", 2 question cards, check, Confirm. The save sent 23 services, roles and asked=true, then "Done. Requests for these will reach you".

## FOLLOW-UP: sales_engineer-an-older-answer-never-redraws-the-services-step (01dc2d2d1), 12 Nov 2026
VERDICT: MERGE AFTER FIXES (item 1 is small). The branch merges cleanly onto origin/main.
1. SHOULD FIX: the guard can leave the poll dead.
   - Where: servicesPoll.ts:57 `if (j && j.ok && !profileReading(j)) { stopped = true; d.onFinished(j); return; }` together with ServicesTab.tsx:250.
   - When: the poll's older answer says "finished", a later-asked `load()` says "reading" (a new reading started between the two asks), and the load is drawn first. `onFinished` is then refused, but the poll has already stopped. `readingNow` stays true, so the effect never re-runs and the tab says "reading" until a reload.
   - Proof: scratchpad/rev-seq/order.mjs prints "load drawn, finished dropped | poll re-armed: false".
   - Fix: let `onFinished` return a boolean. In startReadingPoll write `if (j && j.ok && !profileReading(j)) { if (d.onFinished(j) !== false) { stopped = true; return; } }` and fall through to `arm(...)`. In ServicesTab write `onFinished: (j) => mounted.current && order.draw(n) ? (show(j as State, { keepText: true }), true) : false`.
   Otherwise the guard is correct and harmless:
   - The order is per mount (useRef), so a previous mount's poll is stopped by its cleanup and never numbered here.
   - After an error, the next answer draws (drawn stays 0 or below it).
   - A failed load says nothing only when a later ask exists.
   - Load and poll both in flight while the reading continues: the load is drawn, the older poll's progress is dropped (`newer` false), and the poll re-arms (order.mjs case 1).
2. Ticks: correct. supplier_services.ts:196 `ticked = firstRun || !base.confirmed ? [] : selected` and :207 `stated: ticked.includes(p.key)`. So `stated` is only ever true for a confirmed service.
   - The certification shape on my stub (390): unconfirmed first reading, 26 rows, 0 checked live and 0 after reload; propTicked is [] both times.
   - Confirmed supplier, new document: the same 5 keys live and on reload.
   - Confirmed supplier, older proposals on screen during the reading: live keeps 4 more keys from the older reading's rows, all of them his confirmed services. Nothing that is not his is ever ticked. This is NOTE-level (live ≠ reload only for rows no longer proposed).
   - Unticked-then-arrives and newer-replaces-older hold by arrivedTicks, which is unit-tested in a_supplier_is_asked_never_assumed test 15.
3. Server: correct. The compare-and-set still holds: the key is dropped from the `prevSrc` that the CAS compares, and 'moved' re-reads.
   - NOTE: by design (asserted in the new test), a catalogue mark wipes the step-A summary of a profile still being read. The together re-read then writes a new one. The "unchanged continuation" store can also drop a concurrent live read's progress; this is rare, and its only cost is the summary disappearing until that read's next write.
   - Deno: the touched file passed 9/9. All 10 test files importing supplier_doc_trades passed 140/140.
   - Deploy list confirmed: supplier_api, supplier_portal, supplier_catalog_ingest. resilience_ping reaches the re-read only over HTTP.
4. Interim block. The clamp marks its cut with "…" (screenshot clamp_390.png). The full summary is drawn on screen 1 (ServicesTab.tsx:515). Screen readers get the full text, and the holder is aria-hidden.
   - Heights: holder = block, 257.8 px at 390 and 166.3 px at 1440 (the author measured 235 at 390; the help line wraps differently).
   - CLS at step A and at the list's arrival: 0 in 5+7 runs. The only shift is the existing "Loading your services" panel.
   - SHOULD FIX (low), ServicesTab.tsx:612 `flex-nowrap ... [scrollbar-width:none]`: at 390 only 1 of 8 phrases is fully visible, with no scroll cue. His own words are the point of step A. Use two wrapped rows with a fixed max height and overflow hidden (the same in the holder), or end the row with a "+N" chip.
   - The chips are not tap targets, so the clamp hides no control.
5. Checks:
   - servicesPoll.test plus the touched checks: 50/50.
   - Portal unit tests: 123/123.
   - `tsc --noEmit`: clean.
   - The 12 checks naming touched files: 69/71; the 2 failures need production DB access (environment).
   - No assertion was loosened: each was re-pinned to the new code or added.
   - Walk (dev with webpack on 3182, stub on 8882), warm answers:

     | Run | Median | Worst |
     |---|---|---|
     | 390 (4 runs) | 1.67 s | 2.89 s |
     | 1440 (3 runs) | 1.16 s | 2.24 s |
     | Confirmed (2 runs) | 0.69 s | 1.82 s |

     Requests after the list is stored: 1 in every run. Dashboard reads after stored: 1. Cadence 5 s, then 2.0 s.

## FOLLOW-UP 2: commit 1b774e8f5 (on 01dc2d2d1), 12 Nov 2026
VERDICT: MERGE AFTER FIXES (one small accessibility fix).
1. FIX 1 is correct.
   - order.mjs now prints `poll re-armed: true` in all 3 orders. The new test fails on 01dc2d2d1 (1 of 3 fails) and passes here.
   - It cannot spin forever. Every tick asks under a new number, larger than anything drawn so far, so a refused finished answer is followed by an ask that IS drawn. That ask comes 2 s later (5 s while step A has not landed). The only exception is a load that is newer still, and once that load draws a finished state, `readingNow` goes false and the cleanup stops the poll. The 10-minute cap still applies.
   - An unmounted tab re-arms nothing: the cleanup sets `stopped` before `onFinished` can run (tested).
2. FIX 2, walked on the real shell (my own stub). Short input = 1 phrase, J9 length = 8 phrases, long = 20 phrases with one of 80 characters.
   - (d) Holder height = block height in every case: 291.5 px at 390x844 (the author measured 269.1, probably a different wrap of the help line) and 199.9 px at 1440x900. Layout shift 0 at step A and 0 at the list's arrival, all 6 runs.
   - (b) No flash of unpacked content: the first 5 animation frames all show the packed set. Rotating to 844x390 and back re-packs (390: 3 phrases + "+5 more"; 844: all 8), with no third row, no resize loop and nothing to hydrate (client data only).
   - NOTE (b): widths are measured once per width. If the web font loads after step A lands, a chip can wrap into the hidden third row and take "+N more" with it. Low risk, because step A lands 60 s or more after the page opens. Fix if wanted: re-measure on `document.fonts.ready`.
   - (a) First-fit reordering is acceptable. These are separate phrases, not a sentence, and screen 1 shows them all seconds later.
   - (c) "+N more" is not tappable. That is acceptable, because the full list follows on screen 1.
   - (f) A phrase wider than the row ends in "…" (`text-overflow: ellipsis`, plus a `title`). Nothing is hidden or cut without an ellipsis. No horizontal page scroll.
   - (e) SHOULD FIX at ServicesTab.tsx:935. Screen readers now lose the phrases counted in "+N more": at 390 the J9 run exposes 3 of 8 phrases, the long run 2 of 20. The measuring copy is aria-hidden, and the one-row list it replaced exposed all 24.
     Change: `<ul ref={ref} aria-hidden="true" className={PHRASE_ROWS} …>` plus, beside it, `<ul className="sr-only">{words.map((w) => <li key={w} dir="auto">{w}</li>)}</ul>`.
3. Checks and tests.
   - No assertion was loosened: three were re-pinned to the new `onFinished`, and the rows and packing checks were added.
   - servicesPoll.test.mjs: 16/16. The checks naming touched files: 73/73. Portal unit tests: 126/126. `tsc --noEmit`: clean.
   - All of it ran under `nice`, beside the gate: no Deno suite and no next build. The dev server, stub and worktree are removed.

## FOLLOW-UP 3: commit e34d999f9 (on 1b774e8f5), 12 Nov 2026
VERDICT: MERGE.
1. Screen readers: at 390x844 the accessibility tree has every phrase exactly once (8 of 8; 20 of 20; 1 of 1), and "+N more" is not announced. The sr-only list is 1x1 px and absolutely positioned: no height added, no horizontal scroll.
2. Holder = block: 291.5 px at 390 and 199.9 px at 1440. Layout shift 0 at step A and 0 at the list's arrival, all 6 runs. The first frames show the packed set straight away, with no flash.
3. NOTE (not blocking): the `document.fonts.ready` re-measure does not catch a late font. With the font responses delayed 10 s, `ready` resolved at about 150 ms, before the font started loading. The font swapped at 10.2 s, after step A: every chip narrowed (491 to 475 px) and nothing re-packed. It still stayed in 2 rows with nothing hidden, and the whole-page swap shift was 0.0034.
   - Risk: low. The width change was about 3%, and a narrower font only under-fills a row.
   - Fix if wanted: observe the invisible measuring copy (`probe`) with the existing ResizeObserver, or re-measure on `document.fonts` 'loadingdone', instead of `fonts.ready`.
4. Tests: `the_supplier_portal_does_not_move_under_his_thumb.test.mjs` passed 3/3. `tsc --noEmit` is clean. Everything ran under `nice`; no Deno suite and no next build. The dev server, stub and worktree are removed.

## FOLLOW-UP 4: commit 76b41ceeb (on e34d999f9), 12 Nov 2026
VERDICT: MERGE.
1. Late font. With the font files delayed 10 s and swapping in at about 10.2 s, after step A had landed (u and l, at 390 and 1440): the chip widths dropped about 3% (491 to 475 px, 1696 to 1633 px). The packing was unchanged at these widths. It always stayed 2 rows, nothing hidden, every chip inside the row, and "+N more" correct. The whole-page shift at the swap was 0.0034 at 390 and 0.0011 at 1440; that is the font swap itself, and the block adds 0.
2. The re-pack mechanism, proved directly by changing letter-spacing on the block (the same effect as a font change):
   - wider: 390 u went from 3 phrases + "+5 more" to 2 + "+6 more"; 390 l from 2 + "+18" to 1 + "+19"; 1440 l from 8 + "+12" to 7 + "+13".
   - narrower: 1440 l showed one more phrase (9 + "+11 more").
   - Never a third row, nothing hidden, layout shift 0.
3. No loop:
   - 15 s idle while the reading continues (polls every 2 s): 0 React commits and 0 DOM mutations in the block, at both widths.
   - One width change costs exactly 2 commits.
   - Rotating 390 -> 844x390 -> 390 re-packs (3 + "+5 more", then all 8, then 3 + "+5 more"), followed by 0 commits in the next 5 s.
   - No console errors (no "ResizeObserver loop").
4. Packed from the first frame. Holder = block: 291.5 / 199.9 px. Layout shift 0 at step A and 0 at the list's arrival (6 runs). The accessibility tree has every phrase once (1/8/20), "+N more" is not announced, and the sr-only list is 1 px with no horizontal scroll.
5. The thumb check passed 3/3; `tsc --noEmit` is clean. Everything ran under `nice`; no Deno suite and no next build. The dev server, stubs and worktree are removed.

## INTAKE — independent review of sales_engineer-intake-model-understands (6ef4d82ac; A1 6d5afc447, A7 cda66b9ae, A6 6ef4d82ac), 12 Nov 2026

VERDICT: A1 MERGE AFTER FIXES · A7 MERGE AFTER FIXES · A6 HOLD (A1+A7 alone at cda66b9ae: inquiry_intake + intake_requirements Deno 120/120 green).

Method: real `index.ts`/`handle.ts` on `_shared/twilio_free_harness.ts`, with labelled ZZ DEMO stand-in model JSON, run on the branch and on main (merge-base 3baffbc9a); Deno run with run.mjs's own flags. Scratch harnesses: scratchpad/rev_intake/zz_review_intake.test.ts, zz2.test.ts, zz3.test.ts, zz4.test.ts (logs: a1_*.log, o_*.log, r_*.log, a6_*.log). Production read once: 0 of 24 llm routes open (the model path is live), 0 inquiry_intake rows updated in the last 7 days.

### DEFECTS, most harmful first
1. [A6, PROVEN] RFQ 164464 is back. The real handler, given the misfiling stand-in from main's test (MEP <- "We need it finished by 15 December 2026.", authority approvals <- the warranty sentence) plus the four answers, returns status READY with blocking.open = [], and the brief stores both sentences under the wrong specs. On main the same turn stays needs_info with both specs open. Adding spec_evidence that quotes the customer verbatim changes nothing: the "own words" check passes because they are the customer's words, and the blocking gate counts a filled key as answered. Nothing else catches it. The repo records no case of the move firing in production (it is not logged anywhere), and no customer intake has run since it landed on 10 Nov. That means no evidence either way, not "safe".
2. [A6, test] an_answer_is_recorded_under_the_spec_it_answers.test.ts: the RFQ 164464 replay now feeds a stand-in that already obeys rule 16. All it still guards is that the prompt string is present and that the gate keeps open what the model left open. The HVAC test ("Budget around AED 20,000" filed under system_type) and the bus test ("Sharjah" filed under vehicle/seating) now feed the correct filing. So "a misfiling model cannot make a request ready" is no longer guarded anywhere.
3. [A7, PROVEN, gate red] every_arabic_message_is_written_not_translated.test.mjs, test 3: the branch adds a NEW unreviewed line, `inquiry_intake/handle.ts:919 : (ar ? 'شكرًا، دوّنت ذلك. ' …));`. The Arabic text is unchanged, but the line gained a `)`, so its hash changed. Main fails the same test only on Dashboard.tsx:259. Fix: re-add the reviewed hash for handle.ts:919 to scripts/checks/arabic_reviewed_strings.json, or keep that line's text identical.
4. [A7, PROVEN] A model slip overwrites a tapped answer. Setup: prev installation {v:'supply_only'} (tapped), the customer types "2 years" to the warranty question, and the model returns installation:'yes', warranty 24. Saved: installation 'yes'; main keeps supply_only. Cause: handle.ts:902 merges `{...reqAnswers, ...requirementsFromModel()}` unconditionally. It shows on the summary card before Send, which softens the harm. Fix (model-side, keeps 1664/1666): put the recorded answers in the prompt next to the requirements contract ("RECORDED: installation=supply_only (tapped). Change one only when the customer's later message changes it"). Alternatively, store `by:'tap'` and keep a tapped value unless the model's value differs AND this turn's asked key is that question.
5. [A7, PROVEN] Asking back at the last question loses the answer. Message: "within a month. Does the price include VAT?", with the model filling required_by and answer_to_question. The request goes ready and the reply draft is the code's "Thank you — that is everything suppliers need…". answer_to_question is dropped; the voice step only gets "Ask no question unless the message above asks one" and the raw message, with no facts, so it either ignores the question or improvises. Fix: handle.ts:928, in the else-branch of `if (!rs.complete && rs.next)`, i.e. when status is ready, prefix modelAnswer to the ready draft handed to the voice. The same loss happens on any non-requirements turn (answer_to_question is read only inside the requirements step).
6. [A1, PROVEN] An emirate given on a needs_info turn is not kept. The non-ready briefToSave (handle.ts:1072) has no `emirate`. Turn 1: the model reads Dubai and asks for the area. Turn 2: the model slips and gives none. Result: brief.emirate '', supplier count across the UAE, and no location question, because details.location = "Al Barsha" counts as answered. Main: Dubai. Fix: handle.ts:1072, add `...(emirate ? { emirate } : {})` to the non-ready brief.
7. [A1, PROVEN] Outage path (no model reading): the brief stores emirate 'Dubai' (buildBrief reads the location answer), but the supplier count is called with p_emirate null (handle.ts:1049 `emirate: emirate || null`), so the card's number is wider than dispatch, which uses brief.emirate. Main counted Dubai. Fix: handle.ts:1049, `emirate: emirate || brief.emirate || null`.
8. [A1, PROVEN] An off-list model value is dropped silently and never asked. These give brief.emirate '' and p_emirate null with status ready, because the location detail is filled: "Dubai Marina", "JLT", "DXB", "Dubai, UAE", "Ras al-Khaimah", "Abu Dhabi city", "إمارة دبي", "Abu Dhabi and Dubai", "UAE". Main gave Dubai for the count, but stored the raw value ("Dubai Marina") as brief.emirate, which create_inquiry then dispatches with. So dispatch is cleaner now; only the count/emirate is lost. Accepted correctly: Dubai, "dubai ", Al Ain, RAK, رأس الخيمة, الشارقة. Fix: classify.ts:122-127, add the hyphenated and "emirate of / إمارة" spellings. Better still, when the model's emirate is non-empty but off the list, treat location as open so the model asks once.
9. [A1, prompt, INFERRED] handle.ts:460, emirate "never guessed from a name or a word". This tells the model NOT to place JLT / Al Barsha / Khalifa City in their emirate, which a person would do in a second (ruling 1666). Reword: "never from a person's or company's name; an area that lies in one emirate places it there".
10. [A7, INFERRED] required_by is now latest-wins and the model gives {"days": N} "from today". Every later turn re-anchors the date, so "within a month" said on 1 Dec, re-read on 10 Dec, becomes 9 Jan; main kept the first date. Fix: ask for {"date"} computed from when it was said, or keep the stored date when the model's text is unchanged.
11. [A7, prompt] answer_to_question (handle.ts:453) has no limit on content. Price and refund claims are caught downstream (ai_reply moneyFiguresNotInBrief / policyProblems). Delivery or installation promises, and "a supplier will…", are not caught. The "never quote prices, promise suppliers" sentence exists only in the specialist identity, not the generic one. Add it to the field. No Gulf examples for the four answers (e.g. "أبي تركيب", "بس توريد", "ضمان سنتين"). Length: code slices at 600 characters mid-word (proven with 900 characters); the voice step compresses it.
12. [docs] docs/contracts/intake_answers.md:
    - "Code reads typed words … only … OpenRouter down": not quite. Code also reads them when the model's JSON did not parse (llmParseOk false).
    - "a tap = fixed label or suggestion": tappedAnswer also accepts a typed option value ("yes").
    - "asked something back is answered … and the question is asked again": false at the last question and outside the requirements step (5).
13. [public_site, INFERRED, low] public_site/index.ts:65-87 detectEmirate still reads visitor text by regex on a live path. It feeds the demand signal, the preview supplier count and skipping the location question, so the harm is low (nothing is filed; `\brak\b` is word-bounded; Al Ain is missing). Its comment, "The same emirate words inquiry_intake recognises", is now false. Follow-up, not a blocker.

### CLAIMS CHECKED
- Surfaces: only the portal (src/components/me/NewRequest.tsx, newRequest/helpers.ts) calls inquiry_intake. wa_inbound/customer_files.ts and sales_engineer/lib/inquiry_cap.ts insert inquiry_intake ROWS (carried_from), so WhatsApp and widget conversations reach this handler once the customer continues in the portal. E-mail does not.
- Deploy list: 13 confirmed, by the first-party import closure of each index.ts (the files verify_deploy_parity compares): customer_api, inquiry_intake, public_site, quote_compare, quote_extract, resend_inbound, reveal_invoice, sales_engineer, stripe_checkout, stripe_confirm, supplier_api, supplier_portal, wa_inbound. Only inquiry_intake behaves differently: requirementsStep and tappedAnswer are called only from handle.ts, and the default path of requirementsStep is unchanged. customer_api + wa_inbound + public_site: 321/321 on the branch.
- Calls: no second model call. answer_to_question is read from the same JSON, and every requirements-step turn has one voice call on both trees. Token figures are plausible from the diff, not measured.
- Outage path for the four answers: identical to main (R6: "Supply and fix please" -> yes; "what's the difference…" -> supply_only on both). Not worse, but still wrong for the question-back case.
- A1 wins over main (PROVEN): a stored Sharjah is kept when the model gives none (main: '', count null); a lowercase or Arabic emirate is canonicalised (main stored "dubai " / "الشارقة" raw).
- A7 wins over main (PROVEN): a changed answer replaces the old one; no "couldn't match" for 👍, "maybe", or "Supply and fix please"; the tapped label in any case is recorded.
- Tests: the 3 new files pass on the branch (16/16). On main, run.mjs fails all 3 at type-check. With --no-check, two of the files cannot load (no emirateOf / tappedAnswer), so their 12 tests cannot show a behavioural failure there, and the A6 file fails 3/4. The "13 of 16" figure could not be reproduced as stated.
- Deno: inquiry_intake + intake_requirements, branch 124/124; main + customer_api 198/198.
- Node checks naming touched files (7 files, 37 tests): 1 failure on both trees, the same one (PRODUCTION taxonomy check, 401 token). I could not reproduce the author's "41"; the sets match.

## SUPPLIER WORDS — review of sales_engineer-the-model-reads-what-the-supplier-wrote @ 9bc4b5d (A3/A4/A5/A9), 12 Nov 2026
Method: own detached worktrees (branch + merge-base 3baffbc9a), Deno through run.mjs's own flags (no -A), stand-in model answers only,
production SELECT only (catalogue labels). No paid call, no deploy/apply/push. Worktrees removed.

DEFECTS, most harmful to a registering supplier first
1. [PROVED] A3: a service his words say goes through a PARTNER is saved as his OWN with Add + Confirm. servicesRewrite returns
   meaning.proposals[].delivery='partner' (probe P4), but ServicesTab.tsx:432/438 feed every kept proposal into selection().more, and
   selection() with more=['swimming_pools.construction'] returns {stated:[k], partner:[], own:[k]} (ran src serviceQuestions.ts in node).
   The chip at ServicesTab.tsx:747-752 shows no partner mark. Same loss in capabilities.ts:100 (mapWords drops delivery -> "new_key"
   card option -> tapped as own). Smallest server-only fix: supplier_services.ts:447-451 drop proposal.partner from `offered` and keep
   each partner quote as an 'unmatched' own-words item (as the reading path does for partner phrases), until the tab marks partner rows.
2. [PROVED] A3: a mapping failure on chips the tab NEVER shows turns his typed line into a 503. readInTwoSteps maps step A's also_ask
   (rule 7, up to 8) and vague options too; servicesRewrite discards proposal.questions. Probe: "We do gypsum partitions" -> the claim
   was code-mapped, the ONLY step-B call was for two also_ask chips; failing that call => 503 services_rewrite_unavailable.
   So step B's ~11 s is often spent on discarded chips, and adds a failure mode.
3. [PROVED] Harness: 3 of 11 fixtures.mjs SERVICE_WORDS sentences are no longer "all exact labels" (hvac "Testing & commissioning",
   joinery "Wooden doors", waterproofing "Acoustic insulation" are each the label of TWO live services) -> model path -> service_keys=[]
   by design -> stateServices throws "rewrite named no service" (fixtures.mjs:473-475); stage2/nightly walks break and make paid calls.
   founder_demo_tour OWN_WORDS also goes to the model (paid). Fix: fixtures.mjs:443/445/447 drop the shared labels, and make
   every_demo_service_sentence_names_exact_taxonomy_labels assert the label is unique across trades.
4. [INFERRED, strong] A9: a 20-page priced PDF now has ONE vision call capped max:3000 output tokens (index.ts:302; gateway
   handle.ts:217 caps at route max) ~ 40-50 products; truncated JSON -> extraction_failed -> clearerCopyAsk ("send a clearer copy"),
   where the deleted code read up to 500 priced lines. Model down -> unread_llm_hold; copy says "will be read when the engine is
   back" but nothing re-reads a held catalogue (grep: only index.ts names the status); he must re-upload. The website already times out
   at 20 s (api.ts:74) because the server awaits readTrades() (the profile reading) - pre-existing, A9 adds a vision call before it.
5. [PROVED] A3: the exact-label path decides meaning by code and lists it ON: "Plastic" -> recycling_scrap.plastic, "Cameras" ->
   electronics_wholesale.cameras, no model (live catalogue). Shared labels (13 EN/9 AR) and label+qualifier correctly go to the model;
   Arabic labels match exactly (no folding) - sound; 20 labels containing commas can never match exactly (harmless, model path).
6. [PROVED] A3 latency: step A is a full profile read (223-trade prompt, rules 6-7) on one typed line + step B + readTaxonomy +
   serviceVocab reading both 1,151-row VECTOR columns it no longer uses (supplier_services.ts:410). Recorded minima 22+11 s; a
   2,000-char text is a small profile (18-75 s measured) + mapping -> past the tab's 90 s (api.ts:85): the tab says "Could not read"
   while the server finishes and discards. The tab keeps working meanwhile (only the Rewrite button is busy, spinner + "Our sales
   engineer is reading it…", no progress); the supply-only toggle re-runs the whole read.
7. [PROVED by reading] A3 model silent: 503 loses the mapping, not his words? It loses BOTH on the box (nothing shown); "Something else"
   keeps the words in the answer but never retries the mapping (mapOtherWords returns on []).

ANSWERS
1. Step A IS needed for typed text today: step B maps per trade slice and phrasesOf drops a phrase with no trade; skipping A means code
   picks the trade (against the ruling) or a new whole-catalogue mapping prompt. Cards make no model call to piggy-back on. Smallest
   correct change: readInTwoSteps opts.claimsOnly (supplier_profile_reading.ts:495: map only r.evidence phrases; :469 tell step A
   "a short text he typed: also_ask [] and vague options []"), pass through ProfileReader (:529, :573) and set it at
   supplier_services.ts:427. Claims code names (common for typed lines) then need NO step B: wait ~= step A (~22 s), and defect 2 goes.
2. Honest no-loss behaviour, storage exists: on !r.ok return 200 with his parts as 'unmatched' items (own_words; the tab already lists
   and saves them via services_save_rewrite.own_words, which reach matching) + meaning.state 'unavailable' and a plain line, instead of
   503 (supplier_services.ts:429-431). Something-else: same words kept; add a retry later (no 'owed' status exists today).
3. Unticked: model proposals need "Add" (kept set); their implications come back removed:true and are pre-dropped (ServicesTab.tsx:418);
   exact-path keys are listed ON (his typed labels, as before); implied ON only for a supplier with no reading (ruling 439, unchanged).
   Partner: defect 1. src/ untouched: #1960/#1972/#1975/#1976 (arrivedTicks, answerOrder) unchanged by this diff.
4. Nobody else reads it: no SQL/schema/migration names supply_only for suppliers; fn_services_effective/fn_match_capability/supplier
   count unaffected; it only drives the rewrite's implied list and the catalogue panel's note. Invited listings: no reading -> 'unsaid'
   -> false (was: word list could say true). Older source_docs: no field -> null -> unsaid. Select
   'profile_supply_only:source_docs->reading->supply_only' is valid PostgREST (same form as resilience_ping integrations.ts:97
   'message_id:raw->>message_id'; source_docs is jsonb; the reading is stored as source_docs.reading with ...r.reading so the key will
   exist). Not exercised by a test (fakeDb returns the row whatever the select); 0 production rows have a reading today.
5. Quotes are checked against non-licence docs only (checkReading), so owner names/addresses cannot become evidence; but the whole
   licence (owner names, nationality) now goes to the provider on EVERY step-A part (appended per part). Measured licences are 506-810
   chars; 6,000 lets a mis-filed document push a 4,000-char part past the measured envelope (6,000-char parts hit 112.5 s), and halving
   does not halve the licence: cap ~2,000 (supplier_doc_trades.ts:214). CAS store intact (two_reads 9/9 on branch). Stored sidecars
   in the old "Activities: a, b" form fall back to licenceFieldsFromText (comma split) - same as before, no regression.
6. rows_from_text had no other importer. See defect 4. Production 0 catalogues: A9 low exposure but a regression for big priced PDFs.
7. New file: 8/8 FAIL on merge-base for the asserted reasons (ran with an exactLabelsOf stub so the module loads), pass on branch.
   Deno, 17 files importing touched modules + hard-profile offline replay: 244 pass; two_reads fails only without SUPABASE_* env, 9/9
   with. Node checks naming touched files (16 files, 240/241 tests): identical failure set on branch and main (sanctions B/C,
   Arabic review, stage2 walk, Dashboard Arabic) - nothing added. Corrected assertions are honest (supply_only on a catalogue is now the
   reading's), but nothing now guards "a trader is told supply only" end-to-end with a model answer except the stand-in test.
   Re-pinned check pins exact source text (brittle, not weakening). founder_demo_tour + services_audience_is_not_a_service: PAID now
   (confirmed: their texts are not all exact labels). Free certification: NOT RUN (writes production); by code, the walk never uses
   the own-words box; its "describe" text in Something else -> stubbed model -> 503 -> no new_key card, words kept; completes.
8. Import closure (crawl of every index.ts): supplier_api, supplier_catalog_ingest, supplier_portal, sales_engineer, inquiry_intake
   (comment-only) - matches the claim; verify_deploy_parity widens any _shared change to all slugs. SQL: none needed.
9. Split: A5 (supplier_doc_trades.ts licence parts, supplier_profile_reading.ts licence.activities, test_reader) can ship alone after
   the cap fix. A4 is in the same prompt/checkReading/mergeReadings + withReading; ships with A5 (servicesRewrite part with A3).
   A3 (supplier_services.ts, capabilities.ts, fixtures.mjs) after fixes 1,2,3 (+ ans.1/2). A9 (supplier_catalog_ingest/index.ts,
   rows_from_text.* , supplier_documents_are_read_by_code.test.mjs, catalogue_read comments) held.

VERDICT: A3 MERGE AFTER FIXES (1, 2, 3; ans.2 strongly advised before Monday) · A4 MERGE · A5 MERGE AFTER FIX (LICENCE_TEXT_MAX ~2,000)
· A9 HOLD (output cap / paging, and a real retry for unread_llm_hold).

## LICENCE — independent review of origin/sales_engineer-licence-expiry-order @57684f60e (base 3baffbc9a), 12 Nov 2026

VERDICT: MERGE AFTER FIXES. It fixes the founder's case: on the real file, code now reads no expiry, where main read 2026-10-30. Both live paths store the model's 2027-10-29. The fixes below are what the ruling "no code first, 100%" still needs, plus one new red check in the local gate.

### Defects, most harmful first
F1 (HIGH, ruling; proved by running) Code still comes first whenever code reads all four gate fields and the expiry it reads is in the future.
  The first write stores code's values with licence_read_state='read'. That happens in licenceReadState(licenceLeftUnread(upd), 'pending') in
  supplier_api/actions/documents.ts (~l.285) and in supplier_portal/actions/documents.ts (~l.213), and the model is only asked after that write.
  I drove process_docs with a scratch harness: a text PDF where code reads expiry 2028-01-01, and a model that reads 2027-05-05.
    - model high: row and screen both show the model's 2027-05-05.
    - model low, or answers "unreadable": row and screen keep code's 2028-01-01, state 'read'. This is final.
    - model error or timeout: the same, after 2 calls to license_extract. docs_reread claims only 'ours_failed' rows, so it never reads the licence again.
    - model answers after the 10 s budget (late write): the answer shows code's 2028-01-01 with licence_read_after_answer=true. The row ends at 2027-05-05.
      waitsForLateRead (src/.../licenceReceived.ts:87) needs 'ours_failed', so the form never polls and the screen and the row disagree.
      The reverse case: the model reads a past date late. The screen says the licence is valid, and Submit then refuses it as expired.
  So a licence whose code-read date is wrong but in the future (another document's date, a print date) is ACCEPTED when the model fails.
  Later, the daily suspension job will also suspend on code's date. That is a refusal on code's reading, against the agreed design.
  Fix:
    - In both doors, while the model is pending, failed or off, the stored state is 'ours_failed' even when code filled every field.
      For example: licenceReadState(model==='read'||model==='unreadable' ? licenceLeftUnread(upd) : true, model).
    - Drop the `license_read_state === 'ours_failed'` condition from waitsForLateRead, so a late read is always polled.
    - Optionally, stop writing code's values (codeExpiryMayStand, codeFields.*) to the row at all, and show them only as "being read".
F2 (MEDIUM, gate; proved) Local gate is newly red: scripts/checks/every_external_host_and_secret_is_registered.test.mjs, "every secret the code reads is in the registry".
  The cause is licence_read_sends_the_pdf, read in license_extract/index.ts:78.
  Fix: add "licence_read_sends_the_pdf": "setting" next to document_expiry_ai in supabase/functions/_shared/integration_registry.json:311.
  That is the right home: app_secrets plus a "setting" registry entry is how document_expiry_ai is held.
  This is the only added failure across all 2,932 node checks; the other 411 fail the same way on main (401s, missing node_modules).
F3 (MEDIUM, ruling; proved) Code's issue date can blank the model's expiry. Example: the model reads an expiry with confidence 'high' but no issue date, and code read a later issue date.
  mergeLicenceReads (licence_model.ts:265) then sets the merged expiry to null.
  modelReadingToRow({…expiry 2027-10-29, issue null}, {issue:'2028-01-01'}) gives merged expiry null, row expiry unset, so the supplier is asked again.
  The reverse also happens: when the model's own pair fails the check, code's expiry fills the gap (source 'code'). The design says the dates are unread in that case.
  Fix: when modelIsSure(m), do not let code values take part in the expiry/issue pair. Use the model's pair, or nothing.
F4 (LOW-MED; proved) normDate (licence_extract.ts:22-28), which runs first inside normaliseLicence, has three faults:
    - a timestamp with an offset shifts the day back: '2027-10-29T00:00:00+04:00' gives 2027-10-28. A licence that expires today would be refused a day early.
      Commit 57684f6's slice(0,10) in mergeLicenceReads never sees the raw value, so it does not cover this.
    - a Hijri date passes: '1448/05/10' gives 1448-05-10, and checkLicenceRead keeps it, so it would be refused as "expired 1448".
    - an impossible date passes ('2027-02-30', and '10/29/2027' gives '2027-29-10'). The date column rejects it and the model's whole write fails. This one was already on main.
  Fix: take the leading YYYY-MM-DD when it is present, require a real calendar date, and require a year between 1990 and 2100.
F5 (LOW; inferred) Stale comments still say "code first":
    - supplier_api/actions/documents.ts:209, 228, 406, 423
    - licence_model.ts:79 (CodeReading)
    - the name of the test in an_unread_licence_field_is_held_never_approved.test.mjs
  dubaiToday also now has two homes (_shared licence_model.ts and src licenceExpiry.ts). Name one as the owner.
F6 (LOW; inferred) recordLicenceReadNote is awaited before the model's own row write (supplier_api ~l.413), on an insert that fires about 8 triggers. Move it after the write.
  The note itself is safe:
    - agent_actions has no check constraint on kind or status.
    - The insert triggers leave it as it is: agent 'sales_engineer' is active, nothing marks it sensitive, and it is not escalated.
    - fn_agent_action_work_sweep acts only on 'pending' and 'needs_review' rows.
    - A failed insert is caught and only logged.
F7 (LOW, the founder's recovery, outside the diff) ProfileForm.tsx:225 sets `license_expiry: ex.expiry || o.license_expiry`.
  When the model answers late, the read-only "Expiry" line keeps showing the old 30 Oct 2026 until the poll lands, and keeps showing it if the poll never lands. It is not the red "expired" alert.

### The founder's recovery (production read read-only; no personal data printed)
His lead is the only one with license_expiry = license_issue_date: expiry 2026-10-30, issue 2026-10-30.
  - Its state: approval null, registration not_due and not submitted, licence_gate_reason null, read_state 'read', no matching block.
  - No notification and no agent_actions row for it in the last 5 days.
  - Nothing else stale on the lead can stop him.
When he attaches the file again:
  1. Upload, then "Reading your licence…".
  2. process_docs reads by code: no expiry on the real file (proved). The first write sets license_expiry null and issue null, with state ours_failed.
  3. If the model answers within 10 s: expiry 2027-10-29 and issue 2026-10-30 are written, state 'read', and the form shows "expires 29 Oct 2027".
  4. If it answers later: the form says "being read" and polls for about 60 s, then fills the fields (see F7 for the stale expiry line meanwhile).
The "expired" message cannot come back unless the model itself reads a past date.

### Other answers
Retry (license_extract): one extra model call, and only when expiry ≤ issue. It cannot loop.
  - A second answer that passes the check replaces the whole first reading, other fields included.
  - Worst case per licence: 2 license_extract tries from supplier_api × 2 asks each = 4 gateway calls (main: 2).
Speed: on main, a text licence that code read in full answered in about 1–2 s. Now every licence waits up to 10 s (proved: 10,005 ms with a late model).
  license_extract now also parses the text of every PDF licence (about 200 ms on the real 3-page file).
  The rest of the form is not blocked; only the file picker is busy.
Switch: with no row it is off (sec() returns undefined). The main portal path (by path) already sends the PDF itself.
  When on, it adds the base64 PDF next to the page pictures; the request size grows by about 1.33 × the file.
  It is one lookup per call, without caching.
Tests:
  - The 3 new test files fail on main (type check or an assertion) and pass on the branch.
  - The 3 corrected stale tests reverse the old code-first assertions rather than loosen them; nothing else they protected is lost.
  - Every Deno test of supplier_api, supplier_portal, license_extract, wa_inbound and resend_inbound, plus the _shared importers, passes: 584 of 584.
e2e: a paid run still judges every licence step and J8. In a free run, an approved expired licence is still not deferred.
  New flake: in a paid run, J8 captures the screen once number and authority show (code values). With a late model (p90 12–16 s) the expired sentence has not landed yet, so "says expired before Submit" fails falsely. A real failure is not hidden.
Deploy list: the import graph from each index.ts gives exactly license_extract, supplier_api, supplier_portal, resend_inbound, wa_inbound, supplier_catalog_ingest and quote_extract. No SQL is needed.
Security: no PDF text reaches a prompt or a log in a new way. The note's detail holds code and model values (company name, licence number, dates) of the same kind agent_actions already holds.

## INTAKE 2 — re-review of b86d06035 (A6 reverted 0ac633e2d; fixes b86d06035), 12 Nov 2026

VERDICT: MERGE AFTER FIXES. One small fix (D1). D2 and D3 are not blockers.
Method: the same ZZ DEMO stand-in harness on the real handler, fresh worktree (scratchpad/rev_intake/zz3b, zz5, zz6, zz2, zz4), production read-only (fn_match_capability definition, coverage_emirates values).

DEFECTS
D1 [INFERRED from the production definition, not run] An "Al Ain" job is dispatched to almost no one.
  - classify.ts EMIRATE_NAMES maps 'al ain' and 'العين' to 'Al Ain'. Al Ain is not one of the seven, and no supplier coverage_emirates row says Al Ain: production values are dubai 7519, abu dhabi 3237, … and no al ain.
  - fn_match_capability keeps only suppliers whose stated coverage includes p_emirate, or who stated none. So emirate 'Al Ain' drops every Abu Dhabi supplier that stated its coverage. Proven on the harness: model value "Al Ain" gives brief.emirate 'Al Ain' and the count is called with p_emirate 'Al Ain'.
  - Main had the same behaviour (detectEmirate). But the new prompt itself says "Al Ain: Abu Dhabi", and the tap list leaves Al Ain out.
  - Fix: map 'al ain' and 'العين' to 'Abu Dhabi' in EMIRATE_NAMES. If the AADC utility line matters, keep "Al Ain" in brief.location.
D2 [low] "Asked once, then across the UAE" (F3, F5).
  - If the reply to "Which emirate is the job in?" is neither a tap nor read by the model (e.g. "the marina one", "the city of Dubai please"), the request goes ready with emirate '' and create_inquiry dispatches with emirate null. Suppliers in every emirate get it; the location text (e.g. "Marina") rides along.
  - That is a wider fan-out, not a wrong emirate. It is acceptable, since the model normally reads the reply. The summary card shows no emirate.
D3 [low] answer_to_question is still dropped on a turn where the model's own assistant_message is sent unchanged (the guard at handle.ts:1157 skips modelWrote). This only matters if the model splits the answer away from its own message. The comment "a reply the model wrote itself already answers" is an assumption.
Prompt only, not guarded in code: answer_to_question passes through the SAME guards as every code-composed reply.
  - Route: the prepend sits before voice() → intakeVoice → aiReply replyProblems → guardSupportReply.
  - Traced with replyProblems: it catches "20%" and "AED 500".
  - It does NOT catch "the supplier will install it for free and finish by 1 December" or "We will refund you if you are unhappy". The prompt's ban is the only line there, as for every other reply.

PROVEN FIXED
- A6 gone: slots.ts differs from main only by the added mergeRequirements, recordedRequirements and answerToQuestion; an_answer_is_recorded… is identical to main; the_models_filing… is absent. Main's RFQ 164464 misfiling stand-in (with and without evidence) stays needs_info with both specs open.
- Slips and changed answers:
  - N1: tapped supply_only, typed "2 years", the model returns installation yes but does not list it → kept as supply_only.
  - N2: "actually supply only" with installation listed in changed_answers → supply_only.
  - N2b: the same without listing → the old value is kept. This depends on the model listing the key.
- Lazy model (N3): if the model lists every key, a slip DOES rewrite. That is acceptable: it is the model's own declaration, and the card (requirement_questions) shows the value before Send.
- Answer at the last question (N6): "within a month. Does the price include VAT?" → ready, and the answer leads the ready draft once.
  - Whitespace-only value → nothing added (N7). A value equal to the next question is not doubled (N8).
- Emirate:
  - Dubai Marina, JLT, DXB, "Abu Dhabi and Dubai", UAE, "" and null each ask "Which emirate is the job in?" once, with the seven to tap.
  - Arabic: "في أي إمارة يقع موقع العمل؟" with the seven Arabic names. A tapped دبي → Dubai.
  - Ras al-Khaimah, "Dubai, UAE", "Emirate of Sharjah", "إمارة دبي" and "Abu Dhabi city" each normalise.
  - The normaliser is closed and exact: only prefixes and suffixes are stripped, then a whole-value lookup. "the city of Dubai please" → none.
  - A not-ready turn keeps the emirate (P1, P2). The outage count uses the brief's emirate (O1: Dubai).
- required_by: a recorded 2026-12-05 stays 2026-12-05 on two later turns where the model re-anchors 30 days. A change the model lists moves it.
- Docs and comment: docs/contracts/intake_answers.md now matches the code; the public_site comment is accurate.
- Tests:
  - inquiry_intake + intake_requirements: 129/129. public_site + customer_api + wa_inbound: 321/321. deno check is clean on the 4 entry points.
  - Node checks naming touched files: 37 tests, 1 failure (production 401), the same as main. a_partner_service + demand_forecast: the same 2 failures on main.
  - Arabic gate: fails only on Dashboard.tsx:259, as on main.

## INTAKE 3 — re-review of 46cf40a78 (Al Ain is Abu Dhabi, brief.al_ain), 12 Nov 2026

VERDICT: MERGE (whole branch at 46cf40a78). Harness: scratchpad/rev_intake/zz7.test.ts, the real handler with a stand-in model.

Proven by execution:
- Al Ain jobs. The model says "Al Ain" (en), "العين" (ar), or "Abu Dhabi" with brief.al_ain true. All three give:
  - emirate Abu Dhabi, counted with p_emirate Abu Dhabi;
  - utility line "AADC approval" / «موافقة شركة العين للتوزيع».
- Other emirates.
  - Khalifa City (Abu Dhabi) gives ADDC.
  - A Dubai job with a stray al_ain:true gives al_ain false and DEWA, so a slip cannot mislabel a non-Abu Dhabi job.
- Stored and carried values.
  - An in-flight brief holding emirate 'Al Ain' is normalised on read: Abu Dhabi, al_ain true, AADC.
  - A not-ready turn keeps both values.
  - A later turn where the model gives no emirate keeps al_ain.
  - Outage path (the deterministic interview read "Al Jimi, Al Ain"): Abu Dhabi, al_ain true, count Abu Dhabi, AADC.
- Tests and checks.
  - inquiry_intake + intake_requirements: 130/130.
  - deno check is clean on inquiry_intake and customer_api.
  - The Arabic gate fails only on Dashboard.tsx:259, as on main.

Read, not run:
- The deleted eight-value EMIRATES list had no other importer. Every other EMIRATES in the repository is its own seven-value list: src/components/me/format.ts, SupplierDiscovery, supplier_onboard, licence_extract, demo_factory, seo, and the public_site regex.
- 'Al Ain' as a stored value is still produced only by interview.ts parseEmirate, which handle.ts:1007-1009 now normalises.
- brief.al_ain is read nowhere in src/ or customer_api: an unknown key, never shown to the customer as text.
- The model writes al_ain inside brief, and the code reads it there.

Low, not blocking: a later turn where the model writes "Abu Dhabi" but omits al_ain resets it to false. The utility line then shows ADDC instead of AADC. Nothing else is affected (count, filing, dispatch).

## SUPPLIER WORDS 2 — delta 9bc4b5d57..1e4af251d (whole: origin/main...1e4af251d), 12 Nov 2026
VERDICT: MERGE AFTER ONE SMALL FIX (founder_demo_tour) — A3 MERGE, A4 MERGE, A5 MERGE; A9 is gone from the branch.
Defects (none blocks a registering supplier):
1. [PROVED by reading] founder_demo_tour.mjs:242: the --paid refusal comes AFTER makeDemoSupplier (:234) wrote a demo supplier to
   production and `finally` keeps it, so the next `--seed --paid` refuses as "already standing" until --teardown. Move the check to the
   top of seed() (:218).
2. [PROVED] Partner fact: his line "Pools through our partner ZZ DEMO Pools" is no longer offered (P4b: proposals [], own_words keeps the
   line), so no tap can make it his own SERVICE. But Confirm saves it as his own WORDS (selection() isP only knows card/stored partner
   words), and no partner card is drafted from the box or from "Something else" (mapWords now gets no partner proposal). The literal
   words survive; the partner mark does not. Follow-up, not tonight.
3. [PROVED] The 70 s bound is Promise.race + setTimeout (supplier_services.ts, REWRITE_DEADLINE_MS): the reply comes at the deadline
   with every part kept (P5: 106 ms with deadlineMs 100), but in-flight model calls are not aborted (paid, discarded). Acceptable.
4. services_audience_is_not_a_service.mjs: no network (every route fulfilled locally or aborted), but it stubs services_rewrite with
   service_rewrite.rewriteServices, which the server no longer calls: it proves a dead path. Retire it (or re-point at servicesRewrite with
   a stand-in reader) as a follow-up.
Proved by running (stand-in answers, live catalogue copy, no paid call):
- A9 gone: `git diff origin/main 1e4af251d -- supabase/functions/supplier_catalog_ingest scripts/checks/supplier_documents_are_read_by_code.test.mjs` is empty.
- claimsOnly: "We do gypsum partitions" with the chip-mapping call failing -> 200, gypsum.partitions offered, ONE call (step A, with the
  typed-text instruction). Document path (no claimsOnly) still maps chips: same stand-in -> chips sent to step B (and owed on failure),
  as before. Offline hard-profile replay 30/30.
- Model silent: 200, state 'unavailable', every comma part kept as own words, REWRITE_UNAVAILABLE_EN; ServicesTab shows it in the
  rewrite panel's alert line under the box (role=alert), the words as own-words rows, the textarea keeps his text. Stored only on Confirm
  (the line says so: "you can save them as they are"); nothing re-reads later.
- Exact labels: "Plastic", "Cameras", "Gypsum partitions, False ceilings, Decorative gypsum", Arabic "كاميرات المراقبة" -> 0 calls,
  service_keys [], offered because 'exact_label' (off until Add). A shared label ("Testing & commissioning") goes to the model.
  Callers: fixtures.stateServices and evidence_pack take exact_label offers; founder_demo_tour takes all offers; the tab adds by tap.
  All 11 SERVICE_WORDS sentences are exact against the LIVE catalogue (1,151 rows). The new uniqueness test FAILS on main's sentences
  (names the 3 shared labels) and passes here.
- ServicesTab: toggle is local (sets applied; supply-only drops every implied, never ticks anything); arrivedTicks/answerOrder/partner
  rows untouched. Typecheck NOT runnable without npm install (no @types/react in the deno-shaped tree); a tsc diff of ServicesTab on
  branch vs main shows no new non-environment error.
- Tests: new file 12/12; 19 Deno files importing touched modules + replay: 321 pass, 0 fail. 28 node checks (incl. servicesPoll,
  serviceQuestions, fixtures checks, the stage2 trade check): branch 316/320 and main 315/319, the same 4 failures (Arabic review,
  stage2 walk, certification judge, Dashboard Arabic): nothing new.
THE WAIT: no typed-text surface exists; liveProfileReader uses READ_SURFACE/MAP_SURFACE (both clock 'medium'). A surface of its own
  cannot go lower: supplier_trade_choice is a deciding class, and effortFor (effort_policy.ts:155-158) raises any 'low' on it back to
  the class (ruling 1630). Estimated saving from a separate surface: ~0 s. What would cut the wait (estimate, not measured): one combined
  read-and-map call for typed text (saves the 11-27 s step B when code cannot name the claims). Follow-up, not tonight. "In a second"
  is met only for exact catalogue labels (0 calls); one free-text line remains ~20-55 s by the author's recorded figures.
A5: LICENCE_TEXT_MAX 2,000 (supplier_doc_trades.ts:215). A4 unchanged.

## LICENCE 2 — the delta 57684f60e..01bbbb9af and the result against origin/main (12 Nov 2026)

VERDICT: MERGE for the founder and for new registrations. Two follow-ups are needed before Monday's free certification run, and before any approved supplier attaches a licence again.

### Proved by running (stub drive of the real code; code reads 2028-01-01, the model 2027-05-05; the row already held an old licence: OLD-1, 2026-10-30, read)
Code's 2028-01-01 appears on no row write in either door, in any case.
- process_docs (supplier_api):
  - high: answer in 51 ms. Row: expiry 2027-05-05, issue 2020-05-05, number, authority and name from the model, state 'read'. The form shows 2027-05-05.
  - unreadable (a 'low' answer becomes unreadable inside license_extract, except Arabic-only): every field cleared, 'file_unreadable'.
  - error: 2 calls to license_extract; every field cleared, 'ours_failed', the "being read" note.
  - late (12 s): the answer leaves at 10,023 ms with 'ours_failed' and licence_read_after_answer=true. The row turns 'read' with 2027-05-05 afterwards.
  - The old OLD-1, 2026-10-30 and old name are cleared in the first write in every case. license_activity is written by no path, here or on main.
- save_documents (supplier_portal): the same for high, unreadable and error.
  - late: answers at 10,007 ms, 'ours_failed', being_read; the late answer is dropped. docs_reread picks it up: cron every 5 min, claims rows 10 min × 2^tries after the read, so the first re-read is 10–15 min later, up to 8 tries (about 42 h), then the ceo seat.
- F3: a sure expiry with a later code issue date now gives expiry 2027-10-29 (was blanked). An impossible pair gives both dates unread, nothing from code.
- F4, normDate:
  - '…T00:00:00+04:00' → 2027-10-29. '2027-10-28T22:00:00Z' → 2027-10-28: the date as printed, not converted to Dubai time, which is right for something a document prints.
  - Unread: Hijri, 30 Feb, '12/31/2027', '29-Oct-27', '29/10/27'. Each fails the check and costs the ONE retry.
  - Read: '29/10/2027', Arabic-Indic digits, '29 Oct 2027', '29.10.2027'.
  - Old licences: '15 March 1998' → unread, while '1998-03-15' is read (inconsistent). Only that date is lost; the reading stands, but each such licence pays the retry.
  - Certificates: a two-digit year ('31-Dec-26') is now unread (main read it). 'Date to date' now takes the FIRST date (main: unread). Every other form is equal or better: main was a day early under any TZ ahead of UTC.
- F2: the registry check passes; only the production-token test fails, as on main.
- Tests: 586/586 Deno tests across the touched folders. Node checks naming the touched files: 238 pass; 26 fail, the same failures as on main (production token, sharp, social_comments). licenceReceived.test.mjs passes.
- Typecheck not run (no node_modules in the worktree); the gate runs it.

### Defects
A (MEDIUM, inferred from the live definitions read read-only; not driven): an approved supplier who attaches his licence again is un-verified.
  - The first write clears name, number, expiry and authority with 'ours_failed'. z20 fires on the change of license_doc_path, and fn_sales_engineer_verifies_supplier makes him 'pending' / licence_being_read with verified=false (plus a needs_review agent_actions row).
  - With the model up: the next write fires z20 again and auto-approval (pricing_config: on) restores him seconds later.
  - With the provider down: he stays unverified and out of matching until a re-read succeeds (10 min to about 42 h, then the ceo seat). On main a text licence kept him approved.
  - The nightly restore also lifts a licence_expired block when the expiry is null, and e-mails "active again".
  - Fix (SQL, needs the founder's yes): in fn_sales_engineer_verifies_supplier, an 'approved' supplier with v_ours_failed and source 'licence_changed' stays approved until the reading lands. Today only 3 approved suppliers hold a licence.
B (MEDIUM, inferred, e2e): a free run (models off) now leaves every licence 'ours_failed'.
  - waitsOnTheModel (scripts/e2e/registration_certification_judge.mjs:100) requires needsModel, so text-licence journeys that reach Submit will say FAIL on "approved and verified" instead of NOT RUN.
  - Fix: drop `!!needsModel &&` from line 100.
  - Demo leads are never re-read (fn_supplier_licence_reread_claim excludes them outside a fixture run). Their state lives on the demo row the purge removes.
C (LOW): the panel (`{(f.trade_license_no||f.license_authority) && <dl>}`) disappears while a new licence is read and comes back when read.
  - Content BELOW the licence step shifts by the panel's height. The picker and the status line above it do not move, so his thumb is not under a moving button.
  - A failed upload restores the old panel (was.panel).
D (LOW): a 'low' Arabic-only reading now writes its expiry, number and authority (not its name). That is the model's reading, as ruled.

### Other checks
- J8: the e2e looks again, bounded by the licence_read ceiling, until "expired" or an expiry shows. A real failure still fails.
- Submit is disabled only while `uploading`. process_docs answers in at most about 10 s plus the upload. The browser call aborts at 90 s (twice at most with a token refresh), and every branch, the catch included, clears uploading.
- F6: the note goes through afterResponse → EdgeRuntime.waitUntil, so it is kept alive, never awaited, and its errors are caught. Harmless if cut off.
- resend_inbound and wa_inbound are unchanged and model-only.
- Founder: his lead (expiry = issue = 2026-10-30, not submitted, approval null, so z20 does not fire). When he attaches the PDF again:
  - The panel empties and shows "Reading your licence…". The first write clears the old readings and sets 'ours_failed'.
  - Model within 10 s: 2027-10-29, issue 2026-10-30 and the model's number, authority and name are stored, 'read', and shown.
  - Model later: "being read", the form polls for about 60 s and then fills. If the model fails, a re-read in 10–15 min.
  - "Expired" can only come from licenceHasExpired on the model's own date.

## QUOTATIONS — origin/sales_engineer-the-model-reads-the-quotation cd7a00857 (401f25c4c + cd7a00857) on base 4b7091f08; merged with main 4218ca389 (12 Nov 2026, independent review)

Evidence (ZZ DEMO stand-in model answers, no model called, no database): scratchpad/qrev_attack/{attack,thread,spoof,main,det}.test.ts, run with the runner's own flags (no -A).

### Verdict
- 401f25c4c (quote_extract + extract_quote): MERGE AFTER FIXES (D2, D4).
- cd7a00857 (e-mail route): MERGE AFTER FIXES (D1, D3, D5, D6). Ship the two together or neither: 401f25c4c alone leaves main's email_quote calling extract_quote then submit_quote, i.e. the model's figures reach the customer unconfirmed by e-mail.
- Before Monday: yes, after D1-D4 (each a few lines). The branch removes a real path to a wrong price (main, proved below); D1/D2 are new paths to one. If the fixes cannot land tonight, HOLD both: main's e-mail route is at least gated by the hold desk, and quotations only start when customers post.

### Defects, most harmful first
D1 (PROVED, regression, e-mail) — a USD quotation reaches the customer as AED. proposalFromModel keeps amount 9,000 with review_reason 'foreign_currency'; emailQuoteRead calls it a quotation; emailQuote places it; emailedQuotationThread's read() gives text '' so working.foreign_currency is null; the thread review said "Quotation approved for submission ... prices are in AED" and Submit sent amount 9000 / price_ex_vat 9000. The reply e-mail tells him "a total of AED 9,000 excluding VAT". One tap. On main the e-mail route stopped at extract_quote's total_ambiguous (foreign_currency). Fix: supplier_api/email_quote.ts:111, before deps.review: `if (reading.proposal?.review_reason === 'foreign_currency') return { ok: false, stage: 'extract', code: 'quote_total_ambiguous', message: null, review_reason: 'foreign_currency' };` and restore main's reply sentence for that code in resend_inbound/quote_by_email.ts replyFor (the !r.ok branch, ~line 131). Add the case to email_quote.test.ts with a REAL proposalFromModel reading (the existing USD stub uses amount null, which quote_extract never returns).
D2 (PROVED by the real functions + QuoteForm's own prefill code, portal) — a VAT-inclusive quotation whose VAT is written is stored 5% low. Model answer total 9,450 incl. VAT, VAT 450 -> proposal amount 9,000 (ex VAT), vat_treatment 'inclusive', no `total` key. QuoteForm.tsx:45 prefills amount = pr.total ?? pr.amount = 9,000 with "Includes VAT" and the ex-VAT box blank; submit_quote's statedPrice then stores price_ex_vat 9,000 - 450 = 8,550. No warning is shown; one tap. Same shape existed on main only where the code reader detected 'inclusive' (rare); the branch makes it every model-read VAT-inclusive quotation. The e-mail thread path is correct (submitPayload sends price_ex_vat 9,000). Fix (either): model_reading.ts proposalFromModel return add `...(sp.treatment === 'inclusive' && total ? { total } : {})` (QuoteForm already prefers pr.total; 9,450 incl + VAT 450 -> 9,000), or QuoteForm.tsx:45 set exVat from pr.price_ex_vat and amount from pr.total_incl_vat when inclusive.
D3 (PROVED, cost/abuse + a false reply) — the model reads before the sender is verified. A mail with senderAuth=false from a claimed supplier's address with one open request: 7 reads (6 attachments, the cap at supplier_docs.ts `atts.slice(0, 6)`, + body), each a quote_extract call of up to 2 gateway attempts (<=14 paid calls, ~USD 0.0018 each), no per-sender limit; when the model is down the 'unread' reply is sent to the supplier's real address before verification. Fix: resend_inbound/quote_by_email.ts — move the `to/listed/proven/verifiedSender` block (lines ~192-199) above line 171 and return `nothing` (no read, no reply) for an unverified sender.
D4 (PROVED, portal + e-mail) — VAT added on top with no subtotal written is read 5% high. Following SYS ("total = with VAT when the quotation adds VAT"), the model returns total 9,450, VAT 450, 'exclusive', subtotal null; statedPrice treats amount under 'exclusive' as ex VAT -> price_ex_vat 9,450, prefilled with "Excludes VAT". A warning does appear but it blames the VAT ("AED 450 is not 5% of AED 9,450"), not the total. Fix model_reading.ts:91: when no discount, no subtotal, vat_amount and total given and stated !== 'inclusive', pass `subtotal: r2(total - vat)`.
D5 (PROVED by grep, e-mail) — the checker's warnings never reach the thread. model_reading.ts:20 says they are "put to him in the e-mail and in his quotation thread"; nothing in quote_review_flow/** reads `warnings`. The thread can say "approved for submission" (e.g. the advance-as-total case with no lines) while only the e-mail asked. Either feed proposal.warnings into the thread's first engineer message, or correct the comment and the reply wording.
D6 (PROVED, wording) — the 'unread' reply's subject "We are reading your e-mail for RFQ-x" promises work that nothing does: nothing retries (inbound_messages.raw = {quote_by_email:'unread', quote_inquiry_id}, needs_review true, files left to the profile path). quote_by_email.ts:126 -> "We could not read your e-mail for RFQ-x yet". Body text is fine.
D7 (minor) — options with VAT-inclusive option totals: base = option 1 incl. VAT, so a false "VAT is not 5% of AED 12,600" warning, and option amounts are stated as "excluding VAT" in the e-mail. A request_reference that is a bare number not in his open requests (e.g. the supplier's own quote number) turns a single-open-request mail into an 'ask'. An e-mail with one quotation + one unread file does not tell him the second was unread. A text body: the code checker is void (doc_read reads .txt as CSV; the "printed" filter drops its misreads), so an advance taken as the total with no lines is not questioned in a body.

### Checker attack (attack.test.ts)
1 fils / 0.99 AED off the total: silent (tolerance 1 AED; stored price unaffected). Whole VAT missing: asked. Discount (with subtotal): 1,700 correct; without subtotal: 1,785 with a VAT warning. Currency: AED/Dhs/د.إ/UAE Dirham/'' read as AED; USD/US$/SAR/'AED/USD' -> foreign_currency (portal: 422 "type your AED total", correct; e-mail: D1). Strings: "12,000"->12000, "12 000"->12000, "12.000"->12 (no warning), "١٢٬٠٠٠"->null, "1,2"->12, "12,000/-"->null, negative/0/"abc"->null, 1e9 accepted with no warning. Invoice the model calls a quotation: accepted, nothing asked (the supplier's Submit is the only gate, by design). is_quotation "yes"/missing -> not a quotation. Lines without prices: no line check. Low confidence: asked. Text-layer mismatch: note only, never blocks (confirmed). Warnings are plain English; nothing Arabic or internal reaches the supplier (old bilingual det note removed).

### Money path to the customer
- Portal QuoteForm: quote_extract (model) -> prefill + warnings -> his Submit -> submit_quote review + hold desk. Unconfirmed figures cannot pass without his tap; D2/D4 are wrong prefills one tap away.
- Portal quotation chat (quote_review_flow): CONFIRMED still code-first (quote_review_actions.ts:129 readQuotationFile). Today, unchanged by this branch: a quotation TYPED into the chat goes through readQuotationFile as 'typed_quotation.txt' -> "Grand Total AED 9,450" reads AED 9 (same function, proved on main); an Option A 12,000 / B 9,500 CSV uploaded there reads 24,000 / 19,000. The thread shows these figures and the review decides; he submits.
- E-mail: only to his thread; submit_quote is never called. Proved: the only `action: 'submit_quote'` builder is quote_review_flow/submit.ts submitPayload, reached only from quote_review_actions.ts:151 (signed-in review_submit) and the website; email_quote's review dep rejects submit. Identity: thread text is gen()-anonymised in quote_extract; submit_quote scrubs as for every upload; nothing reaches the customer before his Submit.
- Main (proved by running main's readQuotationFile/quoteByEmail): body "Grand Total AED 9,450 including VAT" -> AED 9 and submit called; A/B CSV -> 24,000 / 19,000; invoice CSV -> 3,150. Author's claims (3) and (4) hold.

### Tests, corpus, checks
Branch: 18 touched/importing Deno files 222 passed 0 failed; merged with main 4218ca389 (clean merge-tree, no shared files with #1978): 273 passed 0 failed (incl. the 207-case money corpus and 971-row brand corpus, unchanged files). Node checks naming touched files (19 files): merged 270/276, main 268/274, the same 6 failures (production/token, Dashboard Arabic, corpus authority) on both: nothing new. deno check of the 3 functions passes; deno lint no new problems (index.ts 9->8, quotes.ts 15->13). Re-pins: every_attachment_is_read swaps 'code before model' and the read_every_attachment door for asserts on the model door and model_unavailable; our_own_test_traffic 5->4 plus an assert on email_quote_read's subject: nothing real unguarded (the door removed is the one that priced by code). The money corpus now guards the checker, not the price shown.

### Speed, cost (production ai_cost_log, 30 days)
quote_extract USD 0.0018, avg 20.9 s, p90 30.4 s (n=57) — portal: one call (a second only when the answer has neither a total nor "not a quotation"), about main's code read + quoteTerms (USD 0.0013, 13 s). E-mail per quotation: N parallel quote_extract + the thread's engineer voice (supplier_api conversation_reply avg USD 0.026, greeting + review = 2 on a new thread) + readWorking 0.0013: about USD 0.03-0.055, higher than the author's 0.016; nobody waits on it. resend_inbound waits up to 120 s per read round + 120 s for the body round + email_quote: the webhook can run past 4 minutes on a slow model (inferred).

### Deploy order (verified by reading)
quote_extract -> supplier_api -> resend_inbound, no SQL; no other function imports the touched modules. New quote_extract + old supplier_api: old extract_quote falls back to readQuotationFile for not_a_quotation/model_unavailable (= main behaviour) and old email_quote submits the model's reading unconfirmed for those minutes (as main). Old resend_inbound + new supplier_api: email_quote (no reading) reads via the model and only places; old replyFor words the new shape as "saved as a draft, not sent" — safe. Reverse (new resend_inbound first): email_quote_read hits the JWT gate -> 'unread' replies; harmless but noisy. D2 ships with quote_extract regardless of the website.

## LICENCE 3 — PR #1982, origin/sales_engineer-approved-supplier-keeps-standing-while-licence-is-read @5b453e3e1 vs main 4218ca389 (12 Nov 2026)

VERDICT: MERGE AFTER ONE FIX (SQL, the session's or the founder's call) plus one marker. The code behaves exactly as the author's table says.

### Proved by running
I drove process_docs with stubs. The row held an approved supplier's accepted reading: OLD-1, Old Authority, expiry 2027-06-01, name, issue 2026-06-02, state read.
- approved, model high (renewed, 2028-05-05): all five fields are replaced by the model's as a set, state 'read'.
- approved, model high with a really expired date (2024-05-04): replaced, 'read'. The screen says expired, as it should.
- approved, model answers with no authority: authority is stored as null, the other fields are the model's, state 'read'.
- approved, error: the old five fields stay, 'ours_failed', the "being read" note, 2 calls to license_extract.
- approved, late (12 s): 'ours_failed' with the old fields at the answer (10,004 ms); the row becomes the model's set, 'read', when it lands.
- approved, unreadable: all fields cleared, 'file_unreadable'.
- pending, or approval null (the founder's case), error: cleared at once, 'ours_failed', exactly as merged.
- save_documents for an approved supplier, error or late: only the path, name, state and read time are written; the old fields are kept. high: the model's set.
Tests:
- The 2 new test files pass on the branch. Copied onto main they fail 3 of 6, the 3 approved-supplier cases.
- Every Deno test of supplier_api and supplier_portal plus licence_read_state passes (258/258).
- The 12 node or website test files naming touched modules pass 78/78, licenceReceived.test.mjs included.
- Typecheck not run (no node_modules in the worktree).

### Read from the live definitions (read-only, not executed)
- z20 fires for an approved supplier only when license_doc_path or licence_legal_name changes.
  - On the first write (new path, old fields, 'ours_failed'), fn_sales_engineer_verifies_supplier takes its FIRST branch: approved, with all four fields present and no mismatch. v_ours_failed is not checked before that branch, so he stays approved and verified.
  - The badge (verified_badges: verified, no hold, expiry ≥ today) stays on the old expiry.
  - The nightly fn_reconcile_doc_blocks keeps an expiry block, because the old past expiry is kept.
  - docs_reread (fn_supplier_licence_reread_claim) does claim him: 'ours_failed', up to 8 tries.

### Defects, most harmful first
L3-1 (MEDIUM): an approved supplier whose new licence is never read is never handed to anyone.
  - The re-read sweep stops after 8 tries (about 42 h).
  - The three-day hand-over to the ceo seat lives in fn_sales_engineer_decides_held_registrations, and that loop reads `approval_status = 'pending'` only.
  - So an approved supplier who attaches ANOTHER company's licence, or a forged or expired one, while the provider is down stays approved, matched and badged on the old reading for good, with the new file unread and nobody told.
  - The 42 h window itself is acceptable: the old reading is a valid reading of the document he was approved on. Silence after it is not.
  - Fix (SQL, apply discipline): in fn_sales_engineer_decides_held_registrations, also select `approval_status = 'approved' and licence_read_state = 'ours_failed' and licence_read_failed_since < now() - interval '3 days'`, and hand those to the ceo seat once per license_doc_path, the same way it does for licence_being_read.
L3-2 (LOW-MEDIUM): while the reading is pending, nothing a person or a rule relies on marks the file as unread.
  - The stored file is the NEW one; number, authority, name and expiry belong to the OLD one.
  - No admin or reviewer surface reads licence_read_state. Only the supplier's own form and Documents card do.
  - doc reviewers, the admin licence view and the Dropbox backup show the new file beside the old number with no marker.
  - Fix: show "new licence not read yet; values are from the previous licence" wherever license_doc_path is shown to staff (admin supplier view). At the least, say so in the verification log row that z20's first run writes (source licence_changed).
L3-3 (LOW): whether he is re-checked depends on the name. z20 re-runs for an approved supplier only on a doc-path or name change.
  - Renewal read with authority blank and a NEW name text: z20 runs and he drops to pending / licence_authority_unread. That is right under "the AI's reading is the reading": held for a person, never "expired".
  - The same renewal with the IDENTICAL name: z20 does not run, and he stays approved with authority null until some later save re-verifies him.
  - Fix: after the model's write in both doors, call fn_sales_engineer_verifies_supplier(id, 'licence_changed') when keepAccepted. Or add license_authority and trade_license_no to the approved branch of z20's WHEN clause (SQL).
L3-4 (LOW, already on main): approved plus unreadable clears the expiry, so the nightly RESTORE lifts a 'licence_expired' block and e-mails "your account is active again", while z20 holds him as pending / licence_unreadable.

### Website
- The form opens with an empty panel and the "being read" note when the row is 'ours_failed' (licencePanelOnLoad). Nothing stale is shown, and nothing shifts on load: the panel is simply not drawn.
- The Documents card shows "Being read" with LICENCE_BEING_READ_NOTE. For a NON-approved supplier in 'ours_failed' that replaces "Could not be read, please upload a clear PDF", which is right: the failure is ours, and licence_read_state rules that he is never asked.
- The founder: approval_status null, so keepsAcceptedReading is false and his re-upload behaves exactly as merged.

## QUOTATIONS 2 — fix commit 62ba18032 (head; main 4218ca389 merged as ab4a8825e), 12 Nov 2026
Evidence: scratchpad/qrev2_attack/{attack,thread,spoof,attack2}.test.ts (ZZ DEMO stand-ins through the real model_reading, email_quote, quote_by_email, quote_review_flow; no model, no DB).
VERDICT (branch as a whole): MERGE AFTER FIXES — N1 and N2 are each a few lines and should land before Monday; N3/N4 can follow. D1, D2, D4 (as asked), D6 are fixed and proved.
DEFECTS (P = proved by running)
N1 (P) A zero now produces a false question that BLOCKS the e-mailed thread. readFigure treats 0 as unreadable: zero-rated VAT 0 -> "We could not read the VAT ("0") as an amount. Please type it."; a free line at 0 and a model's discount/gross 0 likewise. On the e-mail route each becomes an open reading_to_confirm, so the thread cannot be approved until he "confirms" a question that makes no sense to him. Fix model_reading.ts:111: `if (n === 0) return { value: null, doubt: null };` before the `!(n > 0)` doubt (keep negatives/text as doubts).
N2 (P) D4's derivation now misprices the opposite layout. A model that returns total 9,000, VAT 450, 'exclusive' for "Total 9,000 + VAT 450" gets price 9,000 - 450 = 8,550, prefilled "Excludes VAT"; one tap on the form stores 8,550 (a question is shown, not blocking). Before the fix this stored 9,000. Code can tell the two apart by arithmetic: model_reading.ts:177, derive total - VAT only when 5% of (total - VAT) is within VAT_TOL of the VAT; when 5% of the total is, take the total as the subtotal (price 9,000, total incl. 9,450).
N3 (P) Quotations past the read cap and genuine-but-unauthenticated mails are lost silently, and the reply tells him the opposite. 6 PDFs with the quotation 5th: 4 reads (files 1-3 + body), outcome null, no reply from the route; the profile path then sends doc_received "we received 6 document(s) and our team will add them to your profile" (supplier_docs.ts:225-230, to the From address). The same reply now goes to a real supplier whose mail failed DMARC (main told him "Please send your quotation through the supplier portal"). Fix quote_by_email.ts: when files.length > MAX_READS-1 and no quotation was found, reply "we read only the first 3 attachments; please upload your quotation in the portal"; for an unverified sender with attachments and an open request, send main's 'unverified' reply to the sign-in address (no model call).
N4 (P) In the thread his correction is not taken: "no it is 9,540" and "total 9540" leave the amount at 9,000 and reading_to_confirm open (readReply parses neither against this issue). He can only re-upload or say yes; the model's only action there is confirm_reading. Not a money leak (nothing approves), but D5's "confirms or corrects" holds only for corrections by file.
Inferred: the model can slip into confirm_reading on an unrelated message (stand-in proved it clears the point: "what time is the site visit?" -> approved). His Submit is still required, so it is a lost question, not a sent price.
VERIFIED FIXED (P)
D1: USD/EUR/SAR/US$/'AED/USD' withhold every figure (amount, lines, rates, options null) with "Your quotation is priced in EUR ... please type your AED total"; 'aed', 'Dhs', 'د.إ', '' read as AED (as main). emailQuote returns quote_total_ambiguous/foreign_currency and places nothing; the reply is main's sentence. A mixed quotation where the model reports AED but a line is USD is caught only by the lines-vs-total question (model-dependent). Portal chat stays code-read with its own foreign-currency check.
D2/D4: 9,450 incl. VAT 450 -> form prefills 9,450 "Includes VAT", stored 9,000; e-mail thread 9,000. 9,450 with VAT 450 added, no subtotal -> 9,000 on both. VAT not stated -> prefill 9,000 with the VAT box blank, price_ex_vat null (basis asked, as main). VAT on part of the lines -> asked "the VAT or the price?".
D3: an unauthenticated mail: 0 reads, 0 replies. MAX_READS 4 in one parallel round; each read cut at 100 s; placement at 60 s: worst case about 160 s of route time (was 360+).
D5: Submit with the point open sends nothing; "yes" clears it -> awaiting_choice, then his Submit; a new upload replaces it; a code-read proposal in the existing portal chat gets no reading_to_confirm (unchanged behaviour).
D6: subject "We could not read your e-mail for RFQ-151767 yet"; the body promises no retry.
Checker: "12.000", "1,2", -500, text -> no figure, "We could not read your total ("12.000") as an amount. Please type it." (form box blank, he types it: not one tap); 1e9 asked as unusually large, 99,999,999 not; 0.99 AED off is now asked; an advance taken as the total in an e-mail body is now asked ("your file also shows AED 10,500").
OTHER: moved builders still identical to main; #1955 test sets and quote_from_document untouched; touched Deno suites 232 passed / 0 failed; deno check of the 3 functions passes; node checks 270/276 with the same 6 failures as main. Before Monday: yes, with N1+N2 (both one-line, no new path to the customer); N3's reply is the next most useful change.

## LICENCE 4 — #1982 delta 5b453e3e1..1e2450996 (L3-1 SQL, L3-2 marker, L3-3 re-verify), 12 Nov 2026

VERDICT: MERGE AND APPLY. Nothing blocks. Three small fixes can ride along or follow; none changes behaviour on production today.

### Proved by running
- Rehearsal of the file + probe, rolled back on production (`rehearse_sql.mjs`): "PROBE OK, rolled back", exit 0.
- The probe can fail. I rehearsed a mutant with '3 days' changed to '12 hours': exit 1, verdict "PROBE FAILED: day 1: handed over 1; day 4: handed 0 …".
  - The run used ZZ DEMO supplier 126512, ran the decider (new key approved_unread_to_ceo present) and queued 0 notifications.
- (a) The replaced decider against the LIVE pg_get_functiondef: the only differences are the new variable, the call, the new answer key and the trailing ';'. Nobody else's change is reverted.
- Every Deno test of supplier_api and supplier_portal plus licence_read_state: 250/250, including both branch test files.
  - Those files show: one marker row for the new file; a renewal printing the same name and read with no authority calls `fn_sales_engineer_verifies_supplier` with p_source 'licence_changed'; a non-approved supplier gets no marker and no call.
- (g) Run with the token:
  - canonical_routine_manifest: 0 findings.
  - canonical_routines.test: passes.
  - each_pending_sql_file_has_its_own_note: passes.
  - The new handed_on check passes, and so do a_licence_our_reader_failed_on_never_asks_the_supplier, only_a_readable_uae_authority_is_approved and the licence website tests.
  - Without the token only the production-token tests and the main-red corpus-authority test fail.

### Read from production (read-only)
- (b) Live decider: owner postgres, SECURITY DEFINER, search_path public, pg_temp, ACL {postgres, service_role}, one overload.
  - The new routine follows the same pattern: revoke from public, anon and authenticated on its one signature (timestamptz, bigint), grant to service_role.
  - CREATE OR REPLACE keeps the decider's ACL.
- (c) Caller: resilience_ping later_duties calls rpc('fn_sales_engineer_decides_held_registrations') with the service role and spreads the answer into its own object, so the extra key is harmless. No check parses that answer strictly.
- (d) Columns:
  - licence_read_failed_since is stamped by the BEFORE trigger a05_leads_licence_read_clock. It runs on any write of licence_read_state or license_doc_path, so both doors stamp it on 'ours_failed', the approved path included, and a re-read of the same path keeps it.
  - It would pick 0 rows on production now. 0 approved suppliers are in 'ours_failed'; 2 approved ZZ DEMO leads exist.
  - "Once per file" holds: same file, skip; a new file is a new clock key; a file later read leaves 'ours_failed' and is not picked.
- (e) The only routine reading the kind held_registration_for_ceo is the decider, and only as an "already done" check. fn_ceo_task_open just inserts an open ceo_task. Nothing rejects him or messages anyone, and his standing is untouched (the probe proves it stays approved).
- L3-2: the marker row is written for approved suppliers only, in the background (afterResponse), status auto_done (which the work sweep ignores), holding supplier_id and the file path only.
- L3-3: the call uses the service role. Its error is only logged, inside the model job, so it cannot fail the answer.
  - When the name changed, z20 also runs. The second run changes nothing, and with source 'licence_changed' it writes no log row. Harmless.
  - save_documents does not need the call: its one write carries the new path, so z20 runs on the new fields.

### Small defects (none blocking)
1. Probe step "kept" (probe.sql, the `update … set license_doc_path = v_path` line) writes the SAME path.
   - z20's WHEN clause for an approved supplier needs a path or name that is distinct, so z20 never runs there. The step proves nothing about z20, and its comment "so z20 runs" is false.
   - Fix: write `license_doc_path = v_path || '.zz_probe_new'`.
2. The new routine's WHERE has no demo exclusion; fn_supplier_licence_reread_claim has one.
   - Demo licences are never re-read outside a fixture run, so an approved ZZ DEMO with a new file left past 3 days would open a ceo task.
   - Fix: add `and not (coalesce(l.is_demo,false) or public.fn_is_demo_email(l.claimed_by) or coalesce(l.company_name,'') ~* '^\s*zz\s*demo')`.
3. `order by l.id limit 200` is applied before the "already handed" check, so past 200 handed rows the later ones would starve. The pending loop has the same pattern. Fix: move the not-exists into the WHERE. Counts are tiny today.
- Cosmetic: supplier_portal/actions/documents.ts about line 44: licIssue's comment now trails the acceptedKeptFor line.

### L3-4
Confirmed as the author reads it, and it is already on main:
- An approved supplier whose new file the model calls unreadable has his fields cleared, so his expiry becomes null.
- If he had a 'licence_expired' block, the nightly RESTORE lifts it and e-mails "your account is active again", while the gate holds him as pending / licence_unreadable.
Not worth holding Monday for: he is pending, so he is not matched. The fix is to make RESTORE require a non-null expiry later than the cut, in a later SQL change.

## QUOTATIONS 3 — 49ecd7c20 (on 62ba18032), merged uncommitted with origin/main e61a32973 (clean), 12 Nov 2026
Evidence: scratchpad/qrev2_attack/{attack3,n4b,aireply}.test.ts (ZZ DEMO stand-ins through the real code, on the merged tree).
VERDICT: MERGE AFTER FIXES — two one-line fixes (N5, N6); N1-N4 otherwise hold.
DEFECTS (P = proved by running)
N5 (P) "9540 incl VAT" in the thread drops his figure and clears the question. readReply returns only {vat_treatment: inclusive}; message.ts:239 counts 'vat_treatment' as a price answer, so to_confirm is emptied; the review approves and Submit sends price 9,000 'inclusive' (his 9,540 incl. = 9,085.71 ex VAT). Fix message.ts:239: remove 'vat_treatment' from the list (a VAT basis alone does not answer a price question).
N6 (P) N2's test passes both ways when the VAT is 20 AED or less, and 'incl' wins: "Total 400 + VAT 20" -> 380, "Total 380 + VAT 19" -> 361, "Total 20 + VAT 1" -> 19, nothing asked, one tap. Fix model_reading.ts at the `layout` line: when both differences are within VAT_TOL -> 'unknown' (he is asked), or take the smaller difference.
N7 (P with a stand-in; real-model risk inferred) The citation check stops invented words, not a wrong reading: a stand-in confirm_reading citing "site visit" from "What time is the site visit?" clears the question; "yes but add delivery 200" citing "yes" clears it with no delivery added. His Submit is still required and the generated quotation is shown to him first. Acceptable before Monday.
Minor (P): a correction to 9,540 with lines totalling 9,000 is approved with no lines-against-price question; a total "AED 0" is not asked (no price prefilled, so the review asks for one).
VERIFIED (P)
N1: VAT 0, discount/gross 0, a free line at 0 are treated as absent (no question); a total of 0 / "0.00" is asked: "We read your total as AED 0. Please type your total."
N2: 9,450/450 -> 9,000 (incl. 9,450); 9,000/450 -> 9,000 (incl. 9,450); 9,000/600 and 10,250/250 (mixed or zero-rated part) -> no price, he is asked which figure is his price before VAT; 21/1 -> 20; 9,450.01/450 -> 9,000.01.
N3: an unverified sender with attachments and an open request gets main's reply ("If it carried a quotation ...") at the SIGN-IN address only (spoofed sign-in or listed address, or an authenticated but unproven listed address), with 0 model reads; no attachments -> no reply. 6 files with no quotation among the 4 read -> "We read only the first 3 attachments ..." naming them. Both outcomes set needs_review and suppress doc_received; files still go to the profile/review path. An attacker gets no reply, so cannot probe which addresses are registered or make us mail a third party; a spoofer can make the real supplier receive one such mail per spoofed message (dedupe only per provider e-mail id; no per-sender daily cap in this route; I did not check whether a global outbound cap exists).
N4: "yes" cited -> cleared, then generate and his Submit; words not in his message -> not cleared; "no it is 9,540" -> price 9,540, said back as "noted: price excluding VAT AED 9540" before Submit; "make it 9.540" and "add 540" (figure not written) -> refused, the question stays open; Arabic digits ٩٥٤٠ -> 9,540; "not 9,000 but 9,540" -> 9,540; "you said 9,000?" with a stand-in correction -> 9,000 kept and cleared (the stand-in's slip, no price change).
ai_reply.ts: aiSystem renders byte-identical for existing request shapes (8 shapes × en/ar, old vs new); action_words and action_value are returned only for actions that declare them. Arabic gate: 5 hashes added, all code-parsing lines of model_reading.ts (71-73, 95, 204: Arabic-Indic digits, ٬/٫, د.إ/درهم); not supplier-facing; nothing else changed in the gate.
Merged-tree tests: touched + ai_reply importers' Deno tests 476 passed / 0 failed; deno check of the 3 functions clean; node checks 271/277 with the same 6 failures as main; #1955 sets, quote_from_document and quote_generalise untouched.
DEPLOY (deno info over all 78 functions): quote_extract -> supplier_api -> resend_inbound; plus, for parity (prompt unchanged), email_triage, inquiry_intake, marketing, marketing_social_inbox, resilience_ping, sales_engineer, site_assistant, wa_inbound (the only other functions whose graph contains _shared/ai_reply.ts; supplier_api already listed). No SQL.
Before Monday: yes, with N5 and N6.

## WRONG DOCUMENT — PR #1985 @eaa54b115 (origin/main e61a32973), 12 Nov 2026

VERDICT: MERGE AFTER FIXES. The rule's code is right. The prompt makes the rule depend on the model's own doubt, the accuracy run as written does not measure what production does, and the PR conflicts with #1982.

### Defects, most harmful first
D1 (HIGH, the founder's condition; inferred): the last prompt sentence is self-fulfilling.
  - The sentence: "When document_kind is not trade_licence, leave every licence field empty".
  - A real but unusual licence that the model calls company_profile, certificate or other with 'high' empties its own number, authority and expiry. All three conditions then hold, and it is refused as a wrong document.
  - The guard "it read no number, no authority and no expiry" is supposed to be independent evidence. The prompt makes it a copy of the classification.
  - Fix (licence_extract.ts, SYS_LICENSE, the last sentence): replace it with:
    "Always fill the licence fields with exactly what the file prints, whatever document_kind is: never leave a printed licence number, issuing authority or expiry date out because you think the file is not a licence."
  - Fix (wrongDocumentOf): condition 3 becomes "no authority AND no expiry". A profile footer often prints a licence number; a real licence always prints its authority and its expiry.
  - When the rule fires, normaliseLicence already drops every field, so nothing of a profile is stored.
  Which cases would be refused, under the branch and under the fix:
  - Refused rightly (not licences): chamber of commerce certificate, VAT/TRN certificate, tenancy contract, MOA/articles, establishment card, Emirates ID.
  - Ambiguous: a free-zone Certificate of Incorporation/Formation shown alone. Asking for the licence is defensible, but the sentence "a certificate" is blunt.
  - Never refused while authority or expiry is read: Arabic-only licence, angled photo, renewal receipt on page 1, CR extract, e-trader licence.
D2 (MEDIUM; proved by reading the suite): the accuracy suite does not ask what production asks.
  - scripts/e2e/document_intake_model.ts:56 still asks the model only when `licenceNeedsModel(c)` is true. Since #1978, production asks for EVERY licence. Licences that code reads in full are never sent, so their document_kind is never measured.
  - Nothing counts `doc.wrong_document`.
  - The corpus feeds no profile, catalogue or certificate into licence mode.
  - So the 243-answer replay proves only that an answer with no document_kind is never flagged (true by construction, the old-model fallback). The paid run, as written, proves the same for the subset code could not read.
  - Fix: at line 56, `const ask = true`. Count `out.filter(o => o.doc?.wrong_document)`. Add the corpus's P*/C* files and two certificates as licence-mode inputs.
  - Then run `node scripts/e2e/document_intake_accuracy.mjs --model gateway --cap-usd 0.30`.
    - It sends the BRANCH's SYS_LICENSE straight to ai_gateway, inside its own tagged rehearsal window with a cap enforced by the database.
    - It makes one ZZ DEMO subject, torn down after the run. The gate and match steps run in one transaction that rolls back.
    - Safe tonight. About 12 licences plus about 10 non-licences: under USD 0.05, capped at 0.30.
    - Pass means: 0 of 12 licences flagged, and every profile/catalogue/certificate flagged with its kind.
D3 (MEDIUM; inferred from the code paths and the live definitions): an APPROVED supplier who puts a profile in the licence slot loses his standing.
  - The profile becomes license_doc_path, so it is backed up as the trade licence ("Trade licence - …Company-Profile.pdf", as tonight).
  - Without #1982: the old readings are cleared, z20 holds him as licence_being_read, then licence_unreadable.
  - With #1982: 'unreadable' clears the accepted reading, and the re-verify makes him pending as licence_unreadable.
  - Fix: on a sure wrong document, put the previous license_doc_path and readings back (the approved supplier keeps his licence). Keep the wrong file only on the agent_actions row (detail.path), never as license_doc_path. For a supplier with no previous licence, leave the path null.
D4 (MEDIUM; inferred): after "This looks like a company profile…" he can still read the old wording.
  - The daily held-registration e-mail (fn_sales_engineer_decides_held_registrations, licence_unreadable branch, day 0/3/7): "We could not read the company name … upload a clearer copy".
  - serverCopy.ts:601 licence_unreadable.
  - verified_badges.ts:34 CLEARER on the Documents tab.
  - Fix: give the gate its own reason, or make those three ask wrongDocumentOnFile first.
D5 (MERGE; proved by a throwaway merge): #1985 and #1982 conflict in 7 files in EITHER order.
  - The files: licence_read_state.ts, supplier_api/actions/documents.ts, supplier_portal/actions/documents.ts, Documents.tsx, ProfileForm.tsx, licenceReceived.ts and licenceReceived.test.mjs.
  - Merge #1982 first (it is reviewed and its SQL is ready), then rebase #1985, applying D3's fix to the keepAccepted path.
  - Merging origin/main into #1985 alone is clean.

### Proved by running
- wrongDocumentOf with stand-in answers:
  - Not flagged: a licence called other/high with its number read; certificate/high with only an expiry read; company_profile/medium; trade_licence; unreadable; a missing field (old model); "Company_Profile"/"High" casing (exact match only); a profile with a number and name read; authority "N/A".
  - Flagged: company_profile/high with nothing read; certificate/high with nothing read.
- The 3 new test files fail on main (4 of 5) and pass on the branch.
- Every Deno test of _shared licence, supplier_api, supplier_portal, license_extract, wa_inbound and resend_inbound passes: 565/565.
- Node checks naming the touched files: 99 pass, with the same 4 environmental failures as on main. licenceReceived.test.mjs passes.

### Read, live and read-only
- fn_sales_engineer_writes: service_role may EXECUTE.
  - The missing arguments have defaults, so the rpc resolves.
  - It files a seat hand-off keyed by p_subject_id (licence_wrong_document:<lead>:<path>), so once per file.
  - For demo work it inserts a 'suppressed' notification and never sends.
  - The e-mail goes only to process_docs's own `email`: the signed-in supplier, or claimed_by on the re-read sweep.
- The six sentences are plain, polite, English and without blame. "Box below" fits the form and is close enough on the Documents tab.
- resend_inbound and wa_inbound are unchanged ("clearer copy" or review). J11 is NOT RUN in a free run and judged in a paid run; J1–J10 are untouched; the judge test needs `sharp`, which this tree does not have (the same as on main).
- Prompt growth: about 490 input tokens on top of thousands per page (the founder's profile took 24k), plus about 40 output tokens. The read time should not change measurably.

## QUOTATIONS 4 — dac43369c (fix on 49ecd7c20; main e61a32973 merged in), 12 Nov 2026
Evidence: scratchpad/qrev2_attack/attack4.test.ts and attack3/n4b re-run (ZZ DEMO stand-ins through the real code).
VERDICT: MERGE. No defect found that blocks it. One minor follow-up: the 9,540 total is not kept for the customer.
N5 (P): "9540 incl VAT", "9540 inc. vat", "9,540 inclusive", "9540 with vat", "٩٥٤٠ شامل الضريبة" (stand-in correct_total_incl_vat) -> price before VAT 9,085.71, VAT 454.29, said back "Noted: your total is AED 9,540 including VAT, which is AED 9,085.71 before VAT"; 9,085.71 × 1.05 = 9,540.00. "9540 + VAT", "9540 vat extra", "9540", "9540 net" (correct_price) -> 9,540. With no model action the price stays 9,000 and the question stays open (a VAT basis alone no longer clears it). "9540 excluding VAT" is still taken by the reply rules -> 9,540. Our "9,450 incl VAT?" quoted back with a stand-in slip -> 9,000 kept (no price change).
Minor (P): after an incl-VAT correction submit_quote stores price_ex_vat 9,085.71 with amount_as_stated 9,085.71 and treatment 'confirmed_on_portal', so the customer sees no 9,540 total and no "including VAT" basis. Follow-up at message.ts:147: carry vat_treatment 'inclusive' and the 9,540 total into the working so they reach submitPayload. The compared price and the fee base are correct.
Inferred: if the model picks correct_price for an "incl VAT" message, 9,540 is stored as the price before VAT (the stand-in proved the code accepts it). The two action meanings are distinct, and he sees the figure said back before he presses Submit.
N6 (P): with the proportionate tolerance every pair is decided correctly and nothing is asked: 21/1 -> 20, 20/1 -> 20, 105/5 and 100/5 -> 100, 399/19 and 380/19 -> 380, 420/20 and 400/20 -> 400, 9,450/450 and 9,000/450 -> 9,000. The same holds with 40 lines (168/8 and 160/8 -> 160) and with 0 lines (tolerance 5 fils; 1,296.30/61.73 -> 1,234.57). 9,909/472 (VAT rounded to whole dirhams) fits neither layout and is asked. Both layouts fit only when 5% of the VAT is within twice the tolerance (VAT of about 4 AED or less on 40 lines), and then he is asked.
Minors (P): a total of "AED 0" is now asked. The "yes, but …" instruction is in the prompt only. The unverified reply's outbox key 'quote_by_email:unverified:<lead>:<date>' is its own namespace (other replies key on the provider e-mail id), so it cannot suppress a different notice; it allows one such reply per company per day.
Tests: touched + ai_reply-importer Deno tests 477 passed / 0 failed; deno check of the 3 functions clean; node checks 271/277, the same 6 failures as main; #1955 sets, quote_from_document and quote_generalise untouched vs main. Deploy list unchanged from QUOTATIONS 3.

## ROLES AND SETTINGS (independent review of origin/sales_engineer-roles-and-verified-wording @3f7a48a4e + #1983, merged with origin/main e61a32973, 12 Nov 2026)

Merge of origin/main: clean, no conflict (arabic_reviewed_strings.json and nothing_a_supplier_reads_can_be_arabic.gated.json included).
Method: styled `next dev --webpack` (port 3130) mounting the real supplier Dashboard against a local ZZ DEMO stub (8830) that uses the LIVE
role vocabulary; Playwright at 390x844 and 1440x900, deviceScaleFactor 1. Scripts: scratchpad/rev-roles/{stub,roles,verify,ms}.mjs.

### VERDICT
(a) e-mail sharing switch: MERGE.  (b) roles: MERGE AFTER FIXES (b1, b2).  (c) verified wording: MERGE AFTER FIXES (c1, c2).

### DEFECTS, most visible to the founder first
b1 [PROVED, live data + screen] He will still see "designer". Live taxonomy_role: consultant's label is "Consultant / designer"
   (8 roles; no separate designer). The reading read `consultant`, so the fixed screen shows "Your role: Consultant / designer · Read
   from your company profile." (shots/role_one_390.png, role_one_1440.png). The author's screenshots invented a separate "designer" chip.
   Fix: relabel the role (SQL: taxonomy_role.label 'Consultant' for code consultant) and serverCopy.ts:245 ROLE_AR consultant 'استشاري';
   whether a designer role should exist is the founder's call.
c1 [PROVED] Half fixed: after he verifies by WhatsApp code in Profile, Documents still says "1 step left · Next step: Verified mobile
   number · Go to Profile" and the checklist row "Verified mobile number — to do" (shots/docs_founder_form_390.png), in every variant
   (WhatsApp code, SMS, declined). GetMatched draws ov.eligibility from the dashboard read; verify_sms never re-reads it.
   Fix: ProfileForm.tsx:121 and :124 (both success paths) also call a dashboard re-read (e.g. an onVerified prop that ProfilePanel /
   Dashboard wire to load(false, true)), not only dropWarmedReads().
c2 [PROVED by execution of mobileStatus + styled screen] "verified by WhatsApp code" is guessed: kyc whatsapp_choose 'same'
   (_shared/whatsapp_choice.ts:155-158 choosePatch) sets whatsapp_verified_at with NO code. A mobile verified by SMS whose owner then
   answers "Yes, same number" reads "Mobile number … verified by WhatsApp code" next to "Same as your mobile"
   (shots/settings_smssame_already_390.png). Fix: mobileState.ts:93 require `wa.opt === 'other'` (only verifiedPatch, i.e. a code typed
   back, writes 'other') or drop the channel and say "verified"; add that case to mobileState.test.mjs.
b2 [PROVED in stub; inferred for production] A role neither he nor the reading chose is shown as his: services_state returns the raw
   unconfirmed capability row; 14,744 of 14,747 rows are unconfirmed directory-import rows carrying roles ({supplier} 11,897,
   {contractor} 1,457, …). A directory lead who claims shows "Your role: Supplier / trading", unlabelled, ticked under Change, and the
   reading's role is ignored (shots/role_derived_390.png). 0 claimed suppliers have such a row today, so not yet live.
   Fix: ServicesTab.tsx:198 `const storedRoles = d.confirmed ? (d.capability?.roles || []) : []` and :508 `confirmed: d.confirmed ?
   d.capability?.roles || [] : []`; add the case to the_role_list_is_never_shown_as_a_suggestion.test.mjs.
c3 [PROVED, minor] The mobile line changes text while he looks: "verified" then "verified by WhatsApp code" 190-280 ms later (settings
   answer lands before kyc). When the number was verified outside this tab's ProfileForm (another tab or device), "not verified" shows for
   ~380 ms before kyc corrects it (settings_founder_elsewhere_390.png). Fix: render the mobile line only once kyc has answered (or a
   neutral "checking" state) in SupplierSettings.tsx:145/:165.
c4 [inferred] dropWarmedReads() clears ALL warmed tab reads (mailbox, projects, billing too), so after a verification those tabs lose
   their head start (5.7-5.8 s cold, measured 24 Sep). Only 'sup_tab:settings' needs dropping. Not blocking.
Not must-fix: "Verified WhatsApp number · <same number>" for opt 'other' equal to the mobile; correct, "Same as your mobile" would be kinder.
Pre-existing, not this PR: Account card heading and note run together at 390 ("ACCOUNTThese are set by…").

### WHAT HOLDS (proved by running)
(a) Settings is whole at 390/1440: Availability, WhatsApp number, Account, Your data; no empty panel, no orphan heading. The language
    control was already gone on main (ruling 1008: suppliers English only), so nothing became unsaveable; the T.language/langNote/english/
    arabic strings are dead (they were dead on main too). save_settings: an old page sending email_shared gets {ok:true, saved:[]} and only
    portal_updated_at is written; locale still stored 'en'. Live: 151 leads still hold email_shared=true (1 claimed), read by nothing.
    Spot-checked reveal.ts, stripe_confirm, customer_api/lib/pdfs.ts (redacts company/email/phone/whatsapp/website), send_outbox, and one the
    PR did not name: customer_api/actions/reviews.ts reads phone/email/website but returns 403 without revealed_at. pdf_native sets
    Author = QuotesDone, not the supplier. No leak found in what I read (not an exhaustive audit).
(b) one role: shown with the reading sentence; two roles: both, sentence; none: "Not chosen yet. Tap Choose…" with no chips; reading not
    landed: same ask, then his own pick (Contractor) survives the landing; confirmed earlier (contractor, reading consultant): Contractor,
    no sentence; untick all + Done: ask state, Confirm disabled, "Choose your role."; reload: back to the reading's role. Chips and buttons
    44 px. Role-box height identical ask vs chosen (97 px).
(c) Founder sequence (dashboard warms settings with mobile unverified → WhatsApp code in Profile → Settings): never shows "not verified".
    SMS code → "verified"; declined WhatsApp → "verified".
Tests: the 3 new check files fail on main (4/4, 5/5, 2/8) and pass here. 48 checks naming touched files: identical to main except the two
new ones (7 files red on both). Arabic gate: same 5 unreviewed lines on main and here (Dashboard.tsx:259, licence_fields.ts:125-126,
licence_extract.ts:30,185). documentLocale.test.mjs (2 fail) and me/newRequest/combineDefault.test.mjs (1 fail) are already red on main.
Portal unit tests: 12 files, identical except mobileState (fixed). tsc --noEmit: 0 errors. supplier_api Deno: 197 passed, 0 failed.
Deploy: supplier_api + website only (actions/profile.ts is bundled by supplier_api alone). b1 needs a SQL relabel if taken.

## ROLES AND SETTINGS 2 (head 473e6af0b, delta 3f7a48a4e..473e6af0b plus the whole against origin/main e61a32973)
VERDICT: MERGE AND APPLY. Order: deploy supplier_api; the website deploys at merge; apply the SQL right after. Either order is safe:
until the SQL is applied the screen reads "Consultant / designer · Read from your company profile", exactly as today, because the
English label comes from the database; the website change only alters the Arabic label, which no supplier sees.
b1 [proved] SQL: one statement, `... where code='consultant' and label is distinct from 'Consultant'`. It touches one row and
  applying it twice gives PROBE OK. The reverse statement matches the live label. Rehearsal PROBE OK, rolled back. Mutants fail the probe:
  no update, and an update of two rows. table_export_registry: taxonomy_role is no_writer, and file-level DML is not counted
  (every_table_is_exported… passes). canonical_routine_manifest: 0 drift. canonical_routines, each_pending_sql_file_has_its_own_note
  and the pending notes all pass. The old label survives only in migrations_history (seed history) and a test comment. No customer
  sees a role label (discovery returns codes). knowledge/ has no role label. With the post-SQL label the screen reads
  "Your role: Consultant · Read from your company profile."
b2 [proved] Directory-import row ({supplier}, unconfirmed): shows the reading's "Consultant" with the sentence, not "Supplier / trading".
  A confirmed contractor still shows "Contractor".
c1 [proved] After the WhatsApp code in Profile, Documents reads 7/7, "Verified mobile number ✓ done". There was no loading state
  (no aria-busy) and the form stayed mounted. Onboarding/ProfilePanel keep their `me`, so a re-read never resets what he typed.
c2 [proved] SMS, then "Yes, same number", gives plain "verified". A WhatsApp code gives "verified by WhatsApp code"; SMS gives "verified".
c3 [proved] The line reads "checking…" for 180-260 ms and then gives one final answer, with no flip. If kyc returns 500, "checking…"
  lasts 2.5 s and then the settings answer stands. If kyc hangs, "checking…" lasts 20.0 s (call() timeout) and then the settings answer
  stands. It never stays for good. The wording is acceptable.
c4 [read] Only 'sup_tab:settings' is dropped (tabPrefetch.forgetSettingsRead → prefetch.dropOne).
Re-pinned assertion (an_invited…:37): honest. It still pins onSaved={onDone} and only adds onVerified={onVerified}.
Tests: role check 7/7, sharing 4/4, mobileState 8/8, invited 4/4. Portal and me unit tests: only main's 3 red
(documentLocale 2, combineDefault 1). Arabic gate: only main's 5 lines. tsc 0 errors. supplier_api Deno 197 passed, 0 failed.
Screens: scratchpad/rev-roles/shots2/ role_one_390.png, role_one_1440.png, role_one_change_390.png, role_derived_390.png,
role_conf_390.png, docs_founder_form_390.png, settings_founder_form_390.png, settings_founder_form_1440.png, settings_smssame_already_390.png,
settings_kycfail_already_390.png, settings_kychang_already_390.png.

## PORTAL WALK FIXES B1 B2 (review of 3a3f5658c + 5407c924f, 12 Nov 2026, portal-walk reviewer)
VERDICT B1: MERGE. VERDICT B2: MERGE AFTER FIXES (D1, D2), and resolve the merge conflicts with #1984 as described in D3.
DEFECTS
D1 (B2, PROVED BY RUNNING) mobileChange.ts:24-27 verifiedWords says "Mobile number verified by WhatsApp code" for whatsapp opt 'same'. Ran it:
   {opt:'same', phone:=mobile, verified:true} -> "...verified by WhatsApp code". choosePatch('same') sets whatsapp_verified_at with NO code
   (_shared/whatsapp_choice.ts:155-158), so this is the exact mistake #1984 fixed. Fix: add `w.opt === 'other' &&` to the condition, or call
   mobileState.mobileStatus once #1984 lands, and test the 'same' case in mobileChange.test.mjs.
D2 (B2, INFERRED FROM CODE) After he verifies a NEW number by SMS, kyc verify_sms (kyc/index.ts:447) writes leads.phone and owner_phone_verified only.
   If his WhatsApp answer was "same number", whatsapp_phone keeps the OLD number (choosePatch stored it), so WhatsApp notices still go to the
   old phone while Settings says "Same as your mobile". (A code delivered BY WhatsApp re-points it via verifiedPatch; an SMS code does not.)
   B2 now invites this change. Fix in kyc verify_sms: when whatsapp_opt='same', also write whatsapp_phone=phone with whatsapp_verified_at.
   kyc is then added to the deploy list.
D3 (merge, PROVED) Throwaway merge of 473e6af0b into 5407c924f: 3 conflicted files, all trivial.
   Dashboard.tsx:317 and Onboarding.tsx:21,39 / ProfileForm.tsx:49: keep BOTH props (goTo and onVerified).
   ProfileForm.tsx:127: keep #1984's `verified()` and add B2's state reset:
   `if (j && j.ok) { setVbusy(''); verified(); setProvenPhone(uaeMobile(f.phone) || f.phone); setSmsSent(false); setSmsCode(''); loadKyc(); return; }`.
   After the merge, the line at ProfileForm.tsx:482 still calls B2's verifiedWords. Point it at mobileStatus so the wording has one owner.
LATER (inferred, not blocking)
- B1: emirateList (where_he_works.ts:25) shows only the seven names. The matcher reads the raw union (lower/btrim). An import address like
  "Dubai Investment Park" (8 such entries per the author) is hidden on screen, yet it makes "stated" non-empty, and the matcher then excludes
  him from every emirate-specific request until he saves.
- B1: the home emirate is now the first chosen emirate in fixed order (so Abu Dhabi wins), not the first he ticked. From Services it can
  replace a licence-derived leads.emirate whenever that emirate is unticked.
- B1: unticking every emirate on Services (sent []) falls back to the raw stored cap (supplier_services.ts:585), not to UAE-wide.
  He cannot clear the list there. This was already so before the fix.
- B1: fn_decide (live) reads `= any(coalesce(service_emirates, array[emirate]))`, so an empty array (UAE-wide) fails its emirate filter.
  This was already so; registration with no emirates ticked still writes [].
- B2: in the registration form (not edit mode), editing the box after verifying still shows "Mobile verified", while the server keeps the old
  number silently. Unchanged by B2. A number another supplier already holds is not checked by kyc (already so).
ATTACK RESULTS (checked and holding)
- (1) Matcher: the LIVE definitions were read, read-only. fn_match_capability and fn_sales_engineer_supply_gap use the union of the two
  columns, and an empty union means UAE-wide. fn_decide, fn_supplier_market and fn_supplier_opportunities read leads.service_emirates,
  which every save now writes. So unticking removes the emirate everywhere.
- (2) Half-write: the lead side is written first. If the cap write then fails, the union equals the old list, matching is unchanged, and he
  gets an error. The emirate shows again, which is truthful because it is still matched. Validation runs before any write.
- (5) Registration path: with no capability row, `update` touches 0 rows and does not error; Services later confirms the coverage.
  The edit-mode Profile no longer sends emirates.
- (7) No read writes anything: me_row and servicesState only select.
- (8) The score item is completable from Services.
- B2: the code is sent to the NEW number (sendSms uses the box). Save omits the unverified number and the server also keeps a verified one
  (phoneWrite). Double-tap is guarded (vbusy). A third party cannot move the number: kyc writes `.eq('claimed_by', email)` from the session.
- Screens (author's 390 shots): no dead end; "Keep my verified number" and the WhatsApp/SMS links are 44 px; the saved note shows below Save.
TESTS (run here)
- Deno, with the repo's flags `--no-lock --node-modules-dir=none`: _shared/{where_he_works,supplier_capability,supplier_services,
  supplier_services_save}, supplier_api/, sales_engineer/ -> 330 passed, 0 failed. `deno check` of supplier_api and sales_engineer: OK.
  `deno lint` of the 6 changed .ts: OK.
- Node: whereYouWork, mobileChange, supplier_profile_score: pass. The 23 node checks that name touched files: 3 fail, and all 3 need the
  production token here (HTTP 401 / seed refused). Their files are unchanged by the branch, so the failures are not the branch's.
- tsc --noEmit: 0 errors (incremental build).
DEPLOY LIST, by import graph: supplier_api and sales_engineer (operator.ts imports supplier_capability.ts) are correct. No other function
imports where_he_works.ts or supplier_capability.ts; inquiry_intake imports only service_vocabulary. Add kyc if D2 is fixed.

## WRONG DOCUMENT 2 — #1985 @7b236a982 on #1982 c31ce6c57 (12 Nov 2026)

VERDICT: MERGE AFTER ONE FIX (W1). Then apply the backup SQL (MERGE AND APPLY), with W2 as a one-line follow-up or folded in now.

### Defects, most harmful first
W1 (HIGH, a wrong document approved; proved up to the row, the approval step inferred):
  - Since the prompt now says "always fill the licence fields", a chamber of commerce membership certificate read as kind 'certificate'/high fills number, authority, name and expiry. wrongDocumentOf then lets it through (authority and expiry are read), and normaliseLicence stores it AS the licence.
  - My stub drive of process_docs (new supplier, Dubai Chamber certificate): the row holds number 777001, authority "Dubai Chamber of Commerce and Industry", expiry 2027-12-31, the company name, state 'read'.
  - Read-only on production: fn_licence_authority_class gives 'uae' for Dubai Chamber(s), the Abu Dhabi and Sharjah chambers, Dubai Municipality and GDRFA (an establishment card). With auto-approval ON and a matching name, the gate can APPROVE him on a chamber certificate.
  - The same was possible on main (no kind was asked then). Now the model says "this is a certificate" and the code ignores it.
  - Fix (licence_extract.ts, next to wrongDocumentOf; both doors):
    - When document_kind ∈ NOT_A_LICENCE_KINDS at 'high' or 'medium' and wrongDocumentOf is null (licence-like fields read), store NO fields and set the state 'ours_failed'. He is held as licence_being_read, never asked, and goes to the ceo seat after 3 days.
    - Write an agent_actions row (status needs_review): "the model read licence-like fields but says it is a <kind>".
    - A real licence wrongly called 'certificate' then costs a person's look, never a refusal.
  - Follow-up SQL: fn_licence_authority_class should not class chambers, municipality or GDRFA as licensing authorities.
W2 (MEDIUM, backup; inferred from the live definitions):
  - The filter `ours_failed → null` has no time bound. A real licence the provider cannot read is never filed as "Trade licence" until something changes its state. That is up to 42 h of re-reads, then a ceo task that may record the fields without leaving 'ours_failed'.
  - The STORAGE SWEEP in fn_enqueue_doc_backups_backfill (every stored file no rule filed, after 1 h) does copy it, as Storage/supplier-docs/<path>. So nothing is lost. But if the sweep has filed the path first, the later "Trade licence" row may be deduped away.
  - Fix: `case when coalesce(s.licence_read_state,'')='ours_failed' and s.licence_read_at > now() - interval '15 minutes' then null else s.license_doc_path end`. The wrong-document decision lands within seconds (16 s measured), so 15 minutes covers it, and a slow real licence is filed as "Trade licence" after that.
W3 (LOW, ProfileForm.tsx:303 `if (licWrong) …`): a NOT-approved supplier whose READ licence was put back still cannot Submit for 3 days (wrongDocumentNote(me) persists while the row names restored_to), although the restored licence is valid. Fix: block only when the restored file is none: `if (licWrong && !me.license_doc_path)`, using the path the row was put back to.

### Proved by running (stub drive of the real process_docs; license_extract answering through the branch's own normaliseLicence)
- New supplier + profile:
  - The path is written first, then put back to null; the row ends with state null.
  - The answer carries licence_wrong_document=company_profile with no fields.
  - Late (12 s): the answer says 'ours_failed' and polls; the row ends with path null. A note row is written, and the e-mail goes out because the answer had left.
- Approved + profile, in time or late: the row ends exactly at the old licence (path, OLD-1, expiry, issue, name, state 'read'). Marker and wrong-document rows are written.
- Pending with a READ licence + profile: restored to the old licence, state 'read'.
- wrongDocumentOf (new rule):
  - Not flagged: a licence called other/high with number and authority read.
  - Flagged, nothing kept: a profile at high confidence with only a footer licence number.
- Tests: Deno 575/575 (touched folders plus the 3 new files). Node checks naming the touched files: 140 pass. The 4 failures are environmental or the apply window:
  - registration_certification_judge and the_stage2_walk lack `sharp`, as on main.
  - The corpus-authority test is red on main.
  - canonical_routines, and canonical_routine_manifest (2 findings): fn_sales_engineer_hands_unread_approved_licences_to_ceo is ALREADY live, and the decider is #1982's body, while main's canonical file is older. That is the apply-then-merge window of #1982; it clears when #1982 merges. fn_enqueue_doc_backups is not flagged.
- Backup SQL:
  - Against the live pg_get_functiondef: exactly one changed line (Trade licence → case … 'ours_failed' then null) plus the trailing ';'.
  - Owner postgres, SECURITY DEFINER, search_path pinned, ACL {postgres, service_role}, one overload. CREATE OR REPLACE keeps it.
  - Called by the z70 statement trigger (fn_backup_kick on a licence-path change), the 6-hourly fn_backup_kick cron, the backfill and the IT coverage routines.
  - Rehearsal (rolled back): "PROBE OK". A mutant without the change: exit 1, "PROBE FAILED: unread: queued 1". Seat it_engineer is right: it is the backup's routine.
- Put-back side effects: the a05 clock trigger resets licence_read_tries to 0 and clears licence_read_failed_since; portal_updated_at keeps the upload time; z20 fires again on the restored path, which is harmless.

### Item 4 and the paid run
- A new supplier with nothing restored has no licence on the row. He is never pending with a licence reason, so the held-registration e-mail ("clearer copy"), serverCopy licence_unreadable and the Documents CLEARER line are never reached.
- On Submit the form stops with the wrong-document sentence. If he reloads, the 3-day note keeps saying it. The server's Submit refusal would say "trade licence" missing, which is consistent.
- `node scripts/e2e/document_intake_accuracy.mjs --model gateway --cap-usd 0.30`:
  - It sends THIS checkout's SYS_LICENSE straight to ai_gateway, so it needs no deploy, and asks the model for every licence (`ask = true`).
  - Calls: 12 licences, 6 non-licences in licence mode, the profile and photo reads, and the trade chooser.
  - It writes on production: one rehearsal_window row (cap enforced in the database), one ZZ DEMO subject that is torn down, ai_cost_log rows, and a gate and match transaction that rolls back.
  - It needs `sharp`: run it from a checkout of this branch whose node_modules is the lockfile tree, or it stops at corpus generation before any paid call.
  - Pass means the line "wrong document: 0 licence(s) flagged (must be 0); 6 of 6 non-licences named", plus no regression in the licence field scores.
- Run it again after W1 with a chamber certificate added as a negative.

## DATA COPY (independent privacy + SQL review of customer-support-readable-data-copy @1ec1d75b6, merged with origin/main e61a32973: no conflicts)
VERDICT: MERGE AFTER FIXES (6 must-fix below). SWITCH THE EXPORT OFF NOW: not required tonight IF the SQL is applied tonight; measured exposure today is latent, not active (details in A).

A. LIVE ROUTINE (read with pg_get_functiondef; counts only) — PROVED
- (1) REAL. Live supplier copy = to_jsonb(t) / to_jsonb(r) over transactions/refunds by supplier_id: customer_id, payment_ref, Stripe invoice no., hosted + PDF invoice links (bearer links to the customer's billing details), refund_note, receipt URL. Probe on live: "supplier copy carries the customer's payment; ... customer's id". Exposure TODAY: 1 transaction in the whole database (ZZ DEMO), 0 refunds reachable, 0 non-demo supplier reveals. Latent: it bites on the first real reveal of a registered supplier (one real supplier registered yesterday).
- (2) REAL, as described (customers 33 cols, leads whole row incl. notes, claim_token, embeddings, approval_decided_by; transactions ack_token). It is the person's OWN row except the transaction/refund parts in (1).
- (3) REAL, proved: live `l` = `lower(le.email) = em`; 1 of 2 non-demo registered suppliers has login <> listed address (gets no company/quotes). Cross-account case (customer verifying a listed address claimed by someone else): 0 today; unverified customers excluded by fn_pdpl_my_verified_email (JWT email must be a verified customer or claimed owner) — so the attacker must control the listed mailbox. Would have handed owner DOB, Emirates ID, signatory, terms IP, claim_token.
- (4) REAL: tails of customers.phone/whatsapp_phone (unverified) and leads.phone/phone_e164/whatsapp/whatsapp_phone matched by LISTED email, any date.
- (5) MILDER than described: unsent mails are listed WITH their status (they are his records, mislabelled as "sent"); quotations absent: confirmed.
- Blocked chat: unfiltered, 0 blocked rows. redacted_body: unused (0 rows), so body = what the recipient saw.
- Other doors: live routines executable by authenticated returning whole rows: none SECURITY DEFINER (7 matches, all INVOKER/RLS, none an export). customer_api 'me' returns the full customers row (chat_strikes, repeat_disputer, disputes_filed, merged_into, signed_terms_path, is_demo: internal labels about HIM, no other party, no token). supplier_api 'me' (lib/me_row.ts ME_COLUMNS) returns ai_review_notes (model output) and storage paths of his own documents; no notes/claim_token/embeddings. Not urgent; worth trimming.

B. NEW ROUTINE — owner postgres, SECURITY DEFINER, search_path pinned, CREATE OR REPLACE, revokes restated; live ACL of both = {postgres=X} only, so only pdpl_request_me (authenticated) reaches it; selector = JWT email via fn_pdpl_my_verified_email, no parameter chooses whose data. Diff vs live: only the two bodies; nothing else reverted. Field list reviewed: no token, staff name, note, vector, storage path or other-party payment remains. Supplier gets reveal date + rfq ref + category + his ack date, plus refund date/status/reason code: author's "only the date" is right for payment data; the customer's contact after a paid reveal reaches his copy only via the e-mails we sent him (which he holds legitimately). Customer copy carries no supplier identity (no name in transactions; supplier text only via delivered chat). DEFECTS:
- MUST 1 (privacy, inferred from code + schema): line 71 `unnest(array[l.phone, l.phone_e164])` treats phone_e164 as verified. Verification writes ONLY leads.phone (kyc/index.ts:447); phone_e164 is the scraped listing number (marketing/lead_sourcing.ts) and no trigger syncs it (0 triggers). Today 0 diverge. Fix: `select l.phone ...` only.
- MUST 2 (privacy): line 87/160 bound is per ACCOUNT (earliest of customer opened / supplier terms), not per NUMBER. A number changed later to a recycled one brings the previous holder's chats from account-open onward. Use whatsapp_verified_at for whatsapp numbers (columns exist on both tables); and exclude a number verified by more than one account: measured 1 such number shared by 2 real (non-demo) accounts — each copy would carry the other's WhatsApp chats.
- SHOULD: line 148 also drops the person's OWN blocked messages (his words; mark "not delivered" rather than omit). Line 139 omits reason_note (what the customer wrote). Missing vs privacy policy §2/§8: request attachments (voice recordings, photos, drawings) not even listed; company_profile/catalogue docs; his own data-request history (pdpl_requests); signed-terms certificate. AI-derived reading of his services/summary: `services`/`summary` already shown; internal scores rightly not. WhatsApp-before-account trade-off: right for self-service, the PDF says so.

C. PROBE — pure (no writes), raises, demo rows only (@example.invalid + is_demo): cannot reach a real person. Run: new file + probe = PROBE OK (rolled back); probe on LIVE = PROBE FAILED (payment, id, internal fields, unsent mails, 9-digit tails) — author's claim confirmed. MUTANTS (rolled back, all PROBE OK = probe blind): m3 no WhatsApp date bound; m4 lead matched by listed email (leak 3 back); m5 blocked chat included; m6 supplier company name added to the customer's transactions (pre-reveal identity). MUST 3: add assertions killing these four (definition checks on pg_get_functiondef for claimed_by/since/blocked are acceptable since writing wa_messages fires triggers; plus "customer copy contains no key/name of the supplier"). canonical_routine_manifest: this file listed PENDING; its 2 findings are other routines (fn_sales_engineer_decides_held_registrations, fn_sales_engineer_hands_unread_approved_licences_to_ceo) = main's. Pending-note test 5/5. Seat: customer_support.

D. my_data_pdf — door OK: signedInUser (admin.auth.getUser: signature, expiry, revocation; service/anon keys have no user -> 401); export read via PostgREST with the PERSON's JWT (RLS + routine log apply); service role reads only letterhead; body role only picks presentation (roleFor), no id accepted; no storage write; Cache-Control no-store; attachment `QuotesDone-my-data-YYYY-MM-DD.pdf` (no name); siteCors = quotesdone.com/.ae (+www) and own Vercel hosts, bearer header (no cookies). Fetch-timeout 46 = baseline. GAPS: MUST 4 new red `every_external_host_and_secret_is_registered` (fixtures.ts:58 invoice.example.invalid: add to not_integrations or move into a *.test.* file). MUST 5 no public.function_owner row for my_data_pdf: every_deployed_function_has_an_owner goes red the moment it deploys (add `insert ... ('my_data_pdf','customer_support')` in SQL). MUST 6 verify_jwt: author says false "like customer_documents", but config.toml is generated from LIVE and deploy_functions.mjs passes no flag, so the first deploy is the CLI default (true). Decide and write it down; with true check the CORS preflight still answers. SHOULD: no rate limit (each call = pdpl_requests + operator_log rows + export + render; a signed-in loop is unbounded): cap per e-mail per hour in pdpl_request_me; no size cap on WhatsApp/e-mail history (long history -> edge timeout, not a leak); observe.ts:249 records a thrown error's message (render errors only; low).

E. DOCUMENT (page images read: supplier 6 pp, customer 3, Arabic 3): template + page x of y on every page, nothing clipped, Dubai time written out, no keys/null/[]/ISO; Arabic RTL, shaped, Latin digits, mixed lines correct. Emoji in words: acceptable and honest; no emoji font in the repo (only qd_sora/qd_ar). renderer change opt-in (`b.lines`, no existing caller sets it): PROVED byte-identical vs origin/main render.ts on an EN and an AR certificate-shaped document.

F. WEBSITE — buttons disabled while busy; focus to "Open your PDF"/retry; object URLs revoked on unmount and token loss, but NOT on the next download (PrivacyControls.tsx:26 comment says they are; fix the code or the comment); nothing in URL/history/localStorage; JSON as utf-8 Blob. iOS (INFERRED, WebKit not run): delivery is again fetch -> Blob -> object URL -> programmatic <a download> click, the SAME mechanism as tonight. What failed tonight was the CONTENT (JSON shown as text, Latin-1); with application/pdf Safari shows its download prompt / opens the PDF viewer with Share, and if the click after `await` is ignored for lack of a user gesture, the focused "Open your PDF" link (a real tap) opens it. Acceptable; verify on the founder's iPhone before declaring done.

G. TESTS (run): my_data_pdf deno 10/10; pdf_native + certificate 67/67; privacy.test.mjs 12/12; tsc --noEmit clean; every_pdf_we_issue_is_on_our_template 45 + 4/4; region-pinned, undeployed-function, dynamic-import, signed_in_user, prelaunch doors, anon secdef: pass. Arabic gate: 1 fail each, in files this branch does not touch (main's). deno lint: 3 no-import-prefix (estate convention, 84 files). NEW failure: external-host registry (MUST 4).

H. DEPLOY ORDER — "apply SQL before merge" is impossible (apply_sql refuses text not on origin/main), and the website deploys at merge. Real order: merge -> website live (PDF button 404 -> "Try again"; JSON keeps working on the old routine) -> apply SQL + function_owner row -> deploy my_data_pdf. Window harmless (no leak: document.ts prints named fields only and reads only the reveal date from the old routine). Rollback: website revert; delete function; never roll the SQL back to #1237 (restores the leaks).
Proof scripts: scratchpad/rv-dc/{cnt,doors,shared,e164,red}.sql, rv-dc/mut/m3..m6.sql.

## WRONG DOCUMENT 3 — #1985 @7bba511eb (W1/W2/W3 fixes), 12 Nov 2026

VERDICT: MERGE AFTER ONE FIX (F1). Apply both SQL files as they are. F2 to F5 can follow after Monday. W1 is closed for well-formed answers through every door. W2 and W3 are fixed as claimed.

### Defects, most harmful first
F1 (MEDIUM; proved by running a stub drive of the real process_docs on the sweep door): the re-read sweep undoes D3 and W3.
  - The case: the first read failed (provider down or timeout), so the row holds the file in 'ours_failed'. docs_reread then calls process_docs with that same path, and the model now says "sure company profile".
  - The "put back" restores `sup`, which already IS the wrong file. Result: the profile stays as his licence file in 'ours_failed'. tries are not capped, so there are up to 8 paid re-reads of about 24k tokens each, and each writes another licence_wrong_document row.
  - blocks_submit=false, so Submit is NOT stopped. After 15 minutes the file is filed in Dropbox as "Trade licence". He is held as licence_being_read until the ceo task on day 3.
  - The same happens to an approved supplier, and to an approved supplier's held (iii) file: not capped, re-asked up to 8 times.
  - Fix, supplier_api/actions/documents.ts:
    - :449, inside `if (wrongDoc || (heldDoc && keepAccepted))`: when `sameFileReread`, there is nothing to restore. Write `{license_doc_path: keepAccepted ? sup.license_doc_path : null, licence_read_state: keepAccepted ? 'ours_failed' : null, licence_read_tries: 8}`, plus LICENCE_READINGS_CLEARED when !keepAccepted.
    - :416–417: pass restored_to / blocks_submit as `sameFileReread && !keepAccepted ? null / true : (current)`.
    - Add the sweep case to a_company_profile_in_the_licence_slot_is_named.test.ts.
F2 (LOW-MED; inferred by reading): a (iii) row gets contradictory messages.
  - The Documents tab shows BOTH LICENCE_BEING_READ_NOTE ("we read it again automatically": false, tries=8) and the held sentence. Documents.tsx:280 needs `&& !d.wrong_document_message`.
  - After Submit, registrationReceived says "Nothing is needed from you" and verified_badges says "We are still reading your trade licence". For a chamber certificate that answer is wrong: he should send his licence.
  - No mail or WhatsApp is sent for (iii), ever. The ceo task is the only follow-up.
  - Fixing the first is one line. The second can wait until after Monday: a person is asked at once anyway.
F3 (LOW; proved by running): a malformed answer falls to (i) "licence", and the chamber's fields are stored.
  - The malformed answers: 'High', 'Certificate', a null or missing confidence, a new kind string, or no field at all. No response schema enforces the field: license_extract sends the same SYS_LICENSE to whatever model the gateway uses, and parses JSON only.
  - Backstop: once the authority SQL is applied, a chamber, GDRFA or FTA authority classes 'unknown', so it is held as licence_authority_unconfirmed and never approved. A VAT certificate has no expiry, so it is held too.
  - Safe for real licences ('Trade Licence' or 'trade_license' → (i)). Fix later: lowercase and trim both fields in licenceJudgementOf.
F4 (LOW; read): the paid certification step J11 expects the old state.
  - scripts/e2e/supplier_registration_certification.mjs:400 expects `licence_read_state === 'file_unreadable'`. Since D3 a new supplier's sure profile leaves path and state null, so J11 would go red on the correct outcome.
  - Use `!row.license_doc_path`.
  - Also: licence_extract.ts:235 still says "its state is 'file_unreadable'". That is stale.
F5 (LOW; read): a (iii) file is filed in Dropbox as "Trade licence" for good after 15 minutes. That includes a chamber certificate, and F1's profile.
  - A (ii) file in time is never filed as "Trade licence". Only the backfill's storage sweep files it, under its storage path.
  - Tonight's founder profile row in Dropbox is not touched by this PR. It needs a manual removal.
  - After Monday: leave out 'ours_failed' rows with licence_read_tries >= 8, or give them their own label.

### Item 1, misjudging a real licence (read and run)
- A real licence reaches (ii) only when the model calls it a non-licence kind at 'high' AND reads no authority AND no expiry. My unit run: "certificate/high, nothing read" → wrong_document. Any authority or expiry read → (iii); 'medium' → (iii).
- The prompt names DED/DET, free zone, e-trader, CR page, Arabic-only, a photo, a renewal receipt, a free-zone Certificate of Incorporation/Formation/Registration and "a licence inside a larger file" as trade_licence, and asks for "high only when certain".
- The prompt does not name professional, industrial or tourism licences. One of those can only be held, never refused, while its authority or expiry is read. Add them to the list later.
- (iii) never blocks Submit (blocks_submit false; licDone true; tests pass). The ceo task opens at once, as one ceo_task row; nothing pings the founder.
- The accept path is a raw row write of the fields plus licence_read_state='read'. z20 fires on license_expiry / licence_legal_name and re-verifies, and approves only if auto-approval and the name pass. There is no screen and no operator tool. That is acceptable for Monday's volume only if a session is on hand.
- The decider's once-mark key `licence_being_read:<path>` equals holdLicenceForPerson's clock, so day 3 opens no second task. licence_being_read is never closed or rejected by the decider.
- The paid accuracy run (with the chamber and establishment negatives) has not been shown on this head. The false-positive rate on real licences is therefore unmeasured.

### Proved by running
- licenceJudgementOf / normaliseLicence, 26 cases:
  - chamber, establishment card, VAT and FTA at high/medium → wrong or held, never a field stored;
  - 'low', 'High', 'Certificate', a null or missing confidence, a new kind, no kind → licence (F3);
  - an array kind → held.
- Deno: 75 files (_shared licence/wrong, supplier_api, supplier_portal, license_extract, wa_inbound, resend_inbound): 582 passed, 0 failed.
- Node: licenceReceived.test.mjs 15/15. `tsc --noEmit`: clean.
- run.mjs --deno-only not run: the gate is running in /tmp/claude-0/gate.
- Rehearsals (rolled back): both files with their probes → PROBE OK.
- Probes alone against live → PROBE FAILED (chambers → uae; "unread: queued 1").
- Mutants: chamber list removed → FAILED; the 15-minute bound removed → "unread 16 min: queued 0" FAILED.

### Read from production (read-only)
- Both live bodies equal the files' bodies except the stated lines: authority = one list plus one `if`; backup = the one 'Trade licence' tuple. Each has one overload, owner postgres, ACL {postgres, service_role}, search_path pinned; the backup is SECURITY DEFINER, the class INVOKER/IMMUTABLE.
- Leads with an authority: 4, all approved, all 'uae' before and after (DET, the DET fixture, Sharjah Publishing City). No real supplier changes class. Applying it re-evaluates no one.
- Strings tested:
  - 'unknown' only for: chamber(s) in any form (incl. "Dubai Chamber … – DED" and "Sharjah Chamber … / SEDD", which become a hold, not a refusal), Dubai Municipality (incl. "Dubai Municipality Free Zone"), بلدية دبي, غرفة…, GDRFA and FTA.
  - Ajman, Fujairah, Dibba Al Fujairah, UAQ and RAK municipalities, بلدية الفجيرة, and every free zone and DED/DET string: unchanged.
- Deploy list = import closure of the touched _shared files: license_extract, quote_extract, resend_inbound, supplier_api, supplier_catalog_ingest, supplier_portal, wa_inbound. Complete.
- Doors:
  - wa_inbound: isConfidentLicence needs !unreadable → doc_reviews.
  - resend_inbound: writes the path, clears old readings, stores no field. This is pre-existing: an approved supplier e-mailing a non-licence loses his readings, as on main.
  - supplier_portal: fields only when !unreadable.
  - Sweep cap: tries < 8 in both routines; the a05 clock resets tries only on a path change.

### #1987 overlap and order
- #1987's fn_enqueue_doc_backups is live-minus-this-change: line 290 is plain `s.license_doc_path`. Rebased after this apply, its 'Trade licence' tuple must be exactly this file's `case when coalesce(s.licence_read_state,'')='ours_failed' and s.licence_read_at > now() - interval '15 minutes' then null else s.license_doc_path end`, and its probe must be rehearsed again.
- Order:
  1. Apply the authority SQL, then the backup SQL. Both are safe with the old code.
  2. Merge. The website ships, and with the old functions the behaviour is today's.
  3. Deploy the 7 functions at once.
- Not the reverse: new functions under the old website make a new supplier's sure profile read "being read".

## PORTAL WALK FIXES 2 (PR #1989, head 8fb0da128, second review, portal-walk reviewer, 12 Nov 2026)
VERDICTS: B1 MERGE (fix R4 soon). B2+D1+D2 MERGE AFTER FIXES R1, R2. S items MERGE AFTER FIXES R3, R5.
DEFECTS, most harmful first
R1 (D2, inferred from code) A WhatsApp number is marked verified when nobody ever proved it or said it is on WhatsApp.
   On "same" plus an SMS code, waAfterMobileVerified (_shared/whatsapp_choice.ts, choosePatch 'same') writes whatsapp_phone = the NEW
   number and whatsapp_verified_at = now. His "same" answer was about the old number.
   login_otp confirmedWhatsApp (login_otp/index.ts:256-268) reads exactly that pair. It will now send his sign-in code by WhatsApp to a
   number that may not be on WhatsApp, and notices go there too. That is the ledger 1670 class: two proofs merged into one.
   Fix: for SMS proof with opt 'same', return {whatsapp_opt:null, whatsapp_phone:null, whatsapp_verified_at:null, whatsapp_asked_at:null}.
   The dashboard prompt (waNeedsPrompt) then asks "Is +971… also your WhatsApp?" for the new number.
   Keep verifiedPatch for a code delivered on WhatsApp; that one is real proof.
   Writes per case, as built:
   - same + SMS: phone=new, owner_phone_verified=true; wa opt same, phone new, verified_at now, asked_at now. This is R1.
   - same + WhatsApp code, or any answer + WhatsApp code: verifiedPatch, i.e. opt 'other', proven. Correct.
   - other / none / no answer + SMS: WhatsApp columns untouched. Correct.
   Not a hole:
   - Inbound sender lookup fn_whatsapp_owner (LIVE, read-only) resolves 'same' through leads.phone plus owner_phone_verified, not through
     whatsapp_phone, and a number on two accounts names NOBODY ("one party or nobody"). So no mis-route, and D2 does not widen it.
   - Supplier B cannot take A's WhatsApp without the code sent to A's handset.
   - login_otp imports whatsapp_choice.ts, but only gains an unused export: its behaviour is unchanged.
R2 (B2, inferred from code; worse than main) On the REGISTRATION form, editing the mobile after verifying it still shows "Mobile verified".
   Main: save_profile wrote the new number and cleared the flag, and Submit was refused "still needed: verified mobile". Visible.
   Branch: phoneWrite returns 'kept', the old number is kept silently, and registration succeeds. He believes the new number is his.
   Fix before Monday: ProfileForm.tsx:135, drop `isEdit &&` from changedNo, and also show MOBILE_CHANGE.saved_kept when not isEdit (:~395).
R3 (S10, inferred) A dispute is not idempotent across a retry.
   dispute_charge uses p_subject_id = due.id + ':' + Date.now() (supplier_api/actions/profile.ts:283).
   After a 20 s timeout the form says "Your query was not sent" (Billing.tsx dispute()). The server may well have recorded it, and a retry
   then creates a second handoff to the accountant.
   Fix: on j.code timeout or network, say "We could not confirm it was sent; please wait for our e-mail before sending again".
   Server: key the subject on due.id + a hash of the reason, or refuse a second open charge.disputed for the same due.
   What holds: double-tap is blocked (useBusy pending); a refused send keeps the typed text; the ownership check is unchanged (404 not
   yours); the reason is capped at 1,000 characters in the client (maxLength) and on the server (slice).
   Gaps: an empty reason is refused only in the client; I did not trace how staff read the payload.
R4 (B1, inferred) Unticking every emirate on Services shrinks his coverage silently.
   The screen says "Not set: all of the UAE". supplier_services.ts:585 instead falls back to the RAW cap.coverage_emirates, which is
   narrower than the union he was shown, and writes it to BOTH columns.
   Production (counts only): 3 approved claimed suppliers, all with both lists set and every value canonical; 2 disagree.
   For those 2, untick-all narrows matching to the old capability list.
   No other path shrinks or widens an approved supplier:
   - his reads write nothing;
   - Services sends the union;
   - the docs and inbound_email fill only an empty service_emirates, and today none is empty;
   - fn_decide's empty-array drop affects nobody today.
   Fix: line 585, `: emirateList(declaredEmirates, cap?.coverage_emirates)`. Or treat an explicit [] as UAE-wide and write [] to both.
R5 (S7, seen in the author's shot after_S6_S7_quote_form_android.jpg; code QuoteForm.tsx ~122) The quote line items sit in a
   min-w-[460px] row inside overflow-x-auto.
   At 360 and 390, "Unit" is cut, and "Unit price" and Remove are off screen behind an unhinted sideways scroll.
   Unit price is what makes the quote "ready to send".
   Fix: below sm, lay each line out as Description on its own row, then Qty / Unit / Unit price (grid-cols-3), with no min-width.
CHECKED AND HOLDING
- D1: the Profile line takes mobileStatus (#1984); it says "by WhatsApp code" only for opt 'other'.
- B2 edit flow: the old number stays in force until the code; Keep / wrong code / Change number all have a way out; the code goes to the new number.
- S1/S2: the code step has "Cancel deletion"; the warning box is now dark and readable.
- S3: "not saved" plus "Sign in again".
- S8: contact links are 44 px.
- S9: the due row fits at 360.
- S11: Insights holds its places.
- S13: management@quotesdone.com is the address /contact publishes (12 times on the live page).
  /contact, /supplier-agreement and /privacy all answer 200 locale-less on quotesdone.com.
- S4: iso_doc_path is the same class as license_doc_path, company_profile_doc_path and egr_doc_path, which `me` already sends.
  Own row only (claimed_by = his e-mail). Opening one still needs a signed URL (inferred: private bucket).
- S6: the check scans every .tsx in portal/supplier (deep) plus portal/ (top level), so conditional boxes are covered (dispute, line
  items, delete code, OTP).
  MUTANT PROVED: QuoteReviewChat textarea back to 14 px -> the check fails naming :289. It checks the font size only, not the 44 px height.
TESTS (run here, under nice)
- Every new node test fails on origin/main: all 10 new files, plus the privacy and profile-score additions, S1/S2 included.
  All pass on the branch: 106/106 portal unit tests.
- Deno (repo flags): kyc, supplier_api, sales_engineer, _shared/whatsapp_choice, where_he_works -> 333 passed, 0 failed.
  `deno check` of kyc, supplier_api and sales_engineer: OK.
- tsc --noEmit (full, not incremental): 0 errors.
- Arabic gate: the same failure set as origin/main (both run on full trees).
- The 402 node checks that name touched files: no failure on the branch that main lacks.
CONFLICTS AHEAD (throwaway merges)
- #1985 (7bba511eb): ProfileForm.tsx imports and me_row.ts (import plus return line). Trivial: keep the union service_emirates AND
  licence_wrong_document.
- #1987 (fc7b50bc6): Onboarding.tsx (onExists prop: take both), ProfileForm.tsx:466-516, actions/profile.ts imports and :111-140,
  me_row.ts ME_COLUMNS. Mechanical, but profile.ts must keep phoneWrite and where_he_works plus #1987's trading_name/personName lines,
  and must NOT bring back phoneChanged or the raw service_emirates write.
DEPLOY LIST: supplier_api, sales_engineer, kyc + website. Confirmed by the import graph; no SQL.

## DATA COPY 2 (second review, PR #1986 head e97cefab0; throwaway merge with origin/main: no conflicts)
VERDICT: MERGE AND APPLY. No leak of one person's data into another's copy and no anonymity breach (no class-(d) item) found on the new head. Three follow-ups below do not block the merge.

DEFECTS (most harmful first)
1. PROBE GAP (proved): 2 of my 7 new mutants pass the probe: x4 (a supplier's copy lists every quotation on a request he quoted, so competitors' quotes) and x7 (the customer's phone added to a supplier's reveal row). The ROUTINE does neither, so this is not a leak; the probe is just blind to it. Fix in _probe.sql: (a) check `s->'quotations'` count = count(quotes where supplier_id = v_sup); (b) check the customer's phone / whatsapp_phone digits are absent from `st`, the same way his name and e-mail are checked.
2. RATE LIMIT RACE (inferred, not run: no prod writes): pdpl_request_me counts and then inserts with no lock, so N parallel calls all pass. The ceiling becomes "3 + concurrency", not 3. Fix: add `perform pg_advisory_xact_lock(hashtext('pdpl_export:' || v_em));` before the count. Low harm: signed-in, own data only.
3. MINOR: an expired session mid-wait (401) shows "Something went wrong. Please try again." where "Please sign in again" would be the truth (privacy.ts errorText). Also: the probe's pending note still says the probe "prints PROBE FAILED" on live, but on live it now stops with an error (fn_pdpl_norm_phone does not exist yet). And the probe depends on demo rows (a ZZ DEMO reveal pair, a demo supplier chat message, a reserved-number WhatsApp row nobody verified); if a harness clean-up removes them, the probe fails closed and blocks the apply. That is safe, but someone has to know it.

PROVED BY RUNNING
- The new file plus its probe: PROBE OK (rolled back).
- The author's 6 mutants: each PROBE FAILED for its own step (i1 W3, i2 W2, m3 W1, m4 L1, m5 B1, m6 N1).
- My 7 new mutants: 5 FAIL, 2 pass (defect 1).
  - FAIL x1: supplier gets the customer's payment rows again
  - FAIL x2: whole-row to_jsonb(customers)
  - FAIL x3: mail to others that mentions him, and unsent mail
  - FAIL x5: customer name and e-mail added to the supplier's quotations
  - FAIL x6: claimed_by condition dropped
  - pass x4, x7 (defect 1)
- Probe safety:
  - It writes only demo leads/customers/messages fields: whatsapp_phone, whatsapp_verified_at, phone_e164, email, blocked.
  - The only HTTP triggers on those tables (qd_sign_customer/qd_sign_supplier, pg_net) fire on email_verified / owner_email_verified / accepted_terms_at, which the probe never touches. pg_net only queues, and the queue rolls back with the transaction.
  - It always raises at the end, prints only a verdict, and never writes wa_messages.
  - It cannot reach, mail or message a real person, and cannot commit.
- my_data_pdf_is_owned_by_customer_support.sql rehearsed clean. Its shape matches function_owner: PK on function_slug, owner in the allowed list, non-blank note, on conflict do update, so it is idempotent.
- Callers of the replaced routines (live pg_proc + code):
  - fn_pdpl_phone_tails: used only by fn_pdpl_export_data, so the change from 9-digit tails to whole numbers breaks no caller.
  - fn_pdpl_export_data: used only by fn_pdpl_carry_out. carry_out is reached by pdpl_request_me (both portals, PDF and JSON) and by fn_pdpl_verify (the operator / e-mail-code path). The JSON door and the operator path therefore get the fixed routine too: no leaky door remains.
  - Signatures and return types are unchanged; owner postgres; SECURITY DEFINER; search_path pinned.
  - Grants: the helpers are revoked from public, anon, authenticated and service_role (matches live {postgres=X}). pdpl_request_me keeps authenticated and service_role and is revoked from anon, as live.
- Shapes on production (counts only):
  - Verified numbers with no dated proof: 2 of 4 customers and 1 of 3 claimed suppliers. They count from account opening / terms acceptance, not from nothing and not from all time.
  - wa_messages rows with no inbound text: 0, so every row starts from the person (no broadcast/outbound-only rows).
  - Inquiry documents by kind: drawing 2, invoice 1. The invoice is the customer's own reveal invoice, written by the accountant trigger. Quotation PDFs sit on ref_table 'quotes' and are never listed.
  - Lead documents by kind: licence, profile, catalog.
- Tests:
  - Pass: my_data_pdf + pdf_native Deno 71/71; privacy.test.mjs 13/13; tsc clean; every_external_host_and_secret_is_registered 8/8, including the app_secrets test, which passed here; every_pdf_we_issue_is_on_our_template 4/4; pending notes 5/5.
  - Fetch timeouts: 46, the baseline.

COLUMN AUDIT (new head)
- Supplier's copy:
  - His company: names, contacts, licence, TRN, DOB, Emirates ID, terms, IP, cert date, his doc names.
  - His quotations; reveal date, request reference and category, his acknowledgement date.
  - Refund on his quotation: date, status, reason code only.
  - Delivered chat, plus his own undelivered messages, marked.
  - Mail sent to his address (last 500 + total + unsent count) and mail from his address.
  - WhatsApp on his own unshared verified numbers, from verification (last 500 + total + withheld count).
  - His privacy requests; his opt-out.
  - Nothing of the customer's identity or payment before or after a reveal, except what we actually mailed him.
- Customer's copy:
  - His account, requests and raw input, his request files (drawings, his own invoice).
  - His payments with his invoice link; his refunds with his own note and receipt.
  - The same chat, mail and WhatsApp rules.
  - No supplier name or id anywhere (N1 / m6 / x-mutants).
- No token, staff name, note, score, flag, vector or model cost in either copy.
- Mail is matched only by exact lowercased to_email / from_email = his verified address. CC lists are not stored or printed.

WHATSAPP RULES (read and probed)
- Numbers are compared as exact normalised digits (00 dropped, 05x and 5x mapped to 9715x, spaces and + stripped), never by suffix. '+971 050…' with a trunk 0 does not normalise, which can only miss his own messages, never leak someone else's.
- A number verified by A and later by B: if A no longer holds it, B gets it from B's own verification time and A gets nothing for it. If A's row still holds it, it is shared, so neither gets it. Correct.
- The same person with a customer account and a supplier account under two e-mails: he gets none of that number's messages. The copy says so and gives management@quotesdone.com: the right trade for Monday. With one e-mail for both roles it is not counted as shared.
- Inferred minor: since = MIN(used_at) for the same number on the same e-mail. A number given up and re-verified later counts from the first verification; harmless in practice.

DOOR (my_data_pdf)
- Session: signedInUser → admin.auth.getUser (signature, expiry, revocation). The person's own JWT is forwarded to PostgREST, which verifies it again.
- No lead id, customer id or e-mail is read from the body, query or headers. `role` only picks which copy is drawn, from the person's own export.
- No staff impersonation path; aal2 not needed.
- No storage, bucket or link at all: the bytes go back in the response, no-store, with a fixed filename. So "signed link / revocation / retention" does not apply.
- observe logs status and time only.
- siteCors limits origins; the token is a Bearer header, no cookies.
- verify_jwt = false is now in config.toml (line 145).
- 429 too_many_exports maps to the plain sentence "try again in 10 minutes".

PDFs: re-rendered myself (pdftoppm) and looked: template and page x of y on every page, no keys, ISO stamps, null or [], Dubai dates, emoji in words, the withheld-number sentence, privacy-requests section. Arabic is right-to-left and shaped.

WEBSITE: iPhone gets no automatic save, only a "tap to open" link (a real gesture), which fixes the risk I raised in round 1. Double tap is blocked by busy. Object URLs are now revoked on replace, sign-out and unmount.

ORDER: merge (website) → apply SQL → owner row → deploy my_data_pdf. In the gap the PDF button says "Something went wrong"; the JSON button and the operator path keep working on the old routine until the apply, then the fixed one. Rollback: revert the website and delete the function. The SQL is rolled forward only; never restore the #1237 bodies, which brings the leaks back.

Proof scripts: scratchpad/rv-dc/mut2/x1..x7.sql, rv-dc/{trg,trg2,dep2,shape2}.sql.

## WRONG DOCUMENT 4 — delta 7bba511eb..80d729eb (F1–F4; origin/main cf394736d merged in), 12 Nov 2026

VERDICT: MERGE AND APPLY. F1 to F4 are fixed, proved by running. No must-fix. The order is unchanged: authority SQL, then backup SQL, then merge, then the 7 functions.
- SQL: the PR's two SQL files and their probes are byte-identical. The only scripts/sql change in the delta is main's consultant-role pair, which does not belong to this PR. The merge's other overlap, ProfileForm.tsx, adds only #1984's onVerified lines; the PR's lines are intact.
- F1 (my stub of the real process_docs, sweep door, each run twice):
  - New supplier, sure profile: path, state and readings null; tries 8; restored_to null; blocks_submit true (row and `me`); 1 review row; 0 tasks.
  - Approved supplier, sure profile: path kept; 'ours_failed'; tries 8; ZZ-OLD-0001, expiry, issue date and 'approved' untouched; blocks false.
  - Approved supplier, held (iii): as above, with 1 review row and 1 ceo task over two answers.
  - New supplier, held (iii): file held, fields null, tries 8, 1 row and 1 task.
  - tries=8 stops the sweep re-asking. The claim needs tries < 8; the a05 reset happens only on a path change, and the one path change is to null, where the state is null too. (In my forced second run, the approved/profile case writes a second licence_wrong_document row. Production never makes that second call.)
- The admitted gap (an approved supplier's wrong file sits beside his accepted readings until day 3) is safe for Monday:
  - The file is never served to a customer. customer_api reads license_doc_path only for badge presence, and the badge uses the accepted expiry.
  - The gate uses the accepted readings, and the file is kept out of the trade read.
  - It is filed in Dropbox as "Trade licence" after 15 minutes. That is F5, after Monday.
  - Small, after Monday: on the approved held (iii) case, #1982's day-3 hand-over keys 'approved_licence_unread:<path>'. holdLicenceForPerson marks 'licence_being_read:<path>', so a second ceo task opens on day 3.
- F2: Documents.tsx:280 now also needs `!d.wrong_document_message`. The two notes cannot show together. The new condition hides only the being-read note; the unread line already had the same guard, and ExpiryRead is unchanged.
- F3, the 26 answers plus 18 hostile kinds:
  - Now taken in their normal form: 'High', ' Certificate ', 'Certificate', 'Company Profile', 'company-profile'.
  - Real-licence strings all stay (i) licence: 'Trade Licence Certificate', 'Commercial License', 'licence certificate', 'certificate of incorporation', 'free zone licence', رخصة تجارية, 'trade_licence/renewal', 'Licence', 'e-trader licence', 'Commercial Register', 'professional licence', 'industrial licence'.
  - Only 'Certificate' and 'Other' (case variants of the enum's own values) can reach (ii), and only at 'high' with no authority and no expiry read. That is the same rule as their lowercase forms, so it adds no new danger.
  - Still (i): 'certain', a null or missing doubt, a new kind word, no kind field. The authority SQL is the backstop.
- F4: J11 now checks `!row.license_doc_path` (syntax-checked). registration_certification_judge.test.mjs: 28/28.
- Tests:
  - The author's 5 new tests fail on 7bba511eb (4 FAILED; the new-supplier held sweep case already passed there, as expected) and pass on 80d729eb.
  - The delta head's touched folders, 75 Deno files: 587 passed, 0 failed. licenceReceived 15/15. Non-sweep paths are unchanged: every earlier test passes.

## PORTAL WALK FIXES 3 (delta 8fb0da128..2f435b09d, portal-walk reviewer, 12 Nov 2026)
VERDICT: MERGE. R1-R5 and the S6 height check are fixed. No new defect blocks.
- R1 (code + live, read-only). Once a new mobile is proven by SMS, an answer of "same" is cleared to null in all four columns.
  A code delivered on WhatsApp still proves the number (verifiedPatch). Answers other / none / no answer are left untouched.
  - Sign-in: login_otp confirmedWhatsApp (:256-268) needs whatsapp_verified_at plus a matching phone, so his code goes by SMS (or e-mail
    sign-in) exactly as before the WhatsApp question existed.
  - Inbound: live fn_whatsapp_owner matches nobody for a cleared answer, the same as a supplier who never answered.
  - Re-ask: waNeedsPrompt (terms_signed && !asked) asks again, approved suppliers included, on the next dashboard load
    (supplier core Dashboard.tsx:57 reads kyc once on mount, so not within the same visit).
  - Approved supplier unaffected: no live matcher or gate reads whatsapp_opt. The readers are only notice routing, opt-out and growth
    measures. save_profile asks the WhatsApp question only while !wasApproved, and fn_supplier_mandatory_six does not read it. Meanwhile
    WhatsApp notices are skipped ("no WhatsApp number confirmed") and e-mail and SMS continue.
- R2 (code). changedNo now applies to registration too. Submit is refused with reg_mobile, with "not verified … Keep my verified number"
  beside the box, and the payload never carries the unverified number.
  - Branches agree: verify new; Keep; typing the old number back by hand (digits compare equal, so not changed); clearing the box
    (changed, so refused until Keep).
  - The approved Profile-edit path is unchanged: the missing-list is built only when approval_status !== 'approved'.
- R3 (code + live, read-only).
  - fn_seat_handoff's target_id is p_type || ':' || p_subject_id, i.e. 'charge.disputed:<due>:<ms>'. The lookup
    'charge.disputed:<due>:%' is anchored by the colon, so due 12 never matches 123.
  - Live accountant handoff statuses are only done (492) and pending (14), so "not in (done,failed)" is correct.
  - Empty or blank reason: 400. Another supplier's due: 404, unchanged.
  - A truly simultaneous pair can still file two, since select-then-insert is not atomic. The client blocks double taps and the
    accountant would see two rows, so it is harmless at this scale.
  - Lost answer: the new copy "sending again is safe" is now true.
- R4 (code). [] is written as all seven to both columns, and the screen shows seven ticked. A missing list keeps the union.
  - A narrow supplier is never widened without his action: Services always sends his union; Profile edit sends no list; the docs and
    inbound_email paths only fill an empty service_emirates.
  - Residual: capabilities.ts confirm_capability can still write [] (no caller in src/). LATER.
- R5 (author's shots after_R5_quote_lines_{android,iphone,desktop}). Every field is on screen at 360 and 390 with its label, Remove is
  reachable, and desktop shows the single row as before. The width selectors use nth-of-type, so the inserted phone-heads div does not
  shift them.
- S6 height. MUTANT PROVED: removing min-h-11 from ServiceQuestions.tsx:155 makes the check fail, naming :155.
TESTS (run here, under nice)
- All 7 changed or new tests fail on 8fb0da128 and pass on 2f435b09d (zoom, billingDispute, mobileChange, quoteFormLabels,
  whatsapp_choice, where_he_works, one_dispute_per_charge).
- Deno: kyc, supplier_api, sales_engineer, whatsapp_choice, where_he_works -> 337 passed, 0 failed. deno check: OK.
- Portal unit tests and checks: 124/124 pass. tsc --noEmit (full): 0 errors.

## SIGN-UP — PR #1987 @fc7b50bc6, merged with origin/main 6d992429e (clean), 12 Nov 2026

VERDICT:
- Stage 1 (the form asks less): MERGE AFTER FIXES S1–S3. It is shippable before Monday if it goes out in the exact order under DEPLOY.
- Stage 2 (the certificate follows the licence): MERGE AND APPLY after Stage 1. Small, rehearsed, and its probe fails on a mutant.

### Defects, most harmful to a registering supplier first
S1 (HIGH, deploy; inferred from the code): the website goes live AT MERGE, but supplier_api is only deployed afterwards.
  - Until then, the new form's no-name create_company reaches the OLD create_company: `name.length < 2` gives 400 enter_company. Every new sign-up sees "Enter your company name." on a form that has no name box; there is a retry button, but no way forward.
  - The new supplier_api accepts a typed name too (test "a name that IS sent is still checked"), and the old form never sends trading_name. So:
    1. Deploy supplier_api and compliance_archive FROM THE MERGE COMMIT within minutes of the merge, or deploy the branch's functions just before merging.
    2. Then apply SQL 1. It is safe before or after: 0 rows have a blank name today, so the old code never meets it.
    3. Then SQL 2.
  - If a sign-up submits between the merge and SQL 1, the old mandatory six lists 'reg_name' ("company name") to a supplier with nowhere to type it. The window is short, but name it.
  - Rollback: promote the previous Vercel deployment; redeploy the previous supplier_api and compliance_archive; re-apply the three routines' previous canonical files; drop trigger z22. The trading_name column can stay.
S2 (MEDIUM, a new red in the local gate; proved): src/lib/supplierRegistrationReads.test.mjs:42 still expects `if (j && j.ok) onReady(j)`, and the code now reads `if (j && j.ok) { onReady(j); return; }`.
  - The behaviour holds; the check is stale.
  - Fix: `/if \(j && j\.ok\) \{? ?onReady\(j\)/`.
  - Every other failing node check fails the same way on main: Arabic review, invited-listing static and production, corpus authority, the judge's sharp.
S3 (MEDIUM, Dropbox and record; inferred from the live definitions): an unnamed supplier is not filed by fn_enqueue_doc_backups at all.
  - That covers licence, profile, signed-terms certificate, company details and correspondence.
  - The STORAGE SWEEP (backfill, files older than 1 h) does copy the stored files, under Storage/<bucket>/<path>, so nothing is lost if he abandons.
  - doc_backups is unique on (bucket, path), so once he is named, the "Trade licence", "Company profile" and "Signed Terms" rows for files the sweep already took are skipped (`on conflict do nothing`). His named folder then never holds them.
  - Fix: file an unnamed supplier under a stable folder "Suppliers/<category>/Registration <id>/", which trg_doc_backups_admit anchors, or, once named, have the sweep's rows re-filed to the named path. Do not leave him out.
  - The sweep's own registry decides whether signed-terms is swept; I did not prove it is.
S4 (MEDIUM, combine with #1985): SQL 1 and #1985's a_licence_file_is_filed_in_the_backup_only_once_it_is_read.sql both replace fn_enqueue_doc_backups from the same live body. Whichever is applied second reverts the other.
  - Fix: before either is applied, rewrite the SECOND file from the first one's text, so it carries both the blank-name guards and the 'ours_failed' case.
  - Order: this PR's SQL 1 first (merging sooner), then #1985's file rebuilt on it.
  - Git merges: #1984 conflicts in Onboarding.tsx; #1985 conflicts in ProfileForm.tsx and licenceReceived.ts.
S5 (LOW-MEDIUM, the record; inferred): full_name is required by the form but not by the server.
  - accept_terms with no full_name records the acceptance with no name (an old cached build, a direct call).
  - A second accept_terms with another full_name changes signatory_name after the acceptance. The time, IP and hash stay; a later z22 re-issue then prints the new name.
  - Fix: profile.ts accept_terms: when !stands, require personName(body.full_name). When stands, leave signatory_name as it is.
S6 (LOW, pre-existing): clientIp trusts the FIRST X-Forwarded-For entry, which a client can set. Prefer cf-connecting-ip or x-real-ip, or the last proxy-appended entry.
S7 (LOW, Arabic-only licence; inferred): the licence has no English legal name, so company_name stays '' and the gate holds him as licence_unreadable. The held-registration mail then asks for "a clearer copy", which cannot help; it was the same hold on main, but he now has no name at all ("Dear Sir or Madam"). A person must name it: route Arabic-only to the ceo seat rather than to "clearer copy".

### Proved by running
- SQL 1, live pg_get_functiondef diff:
  - fn_supplier_mandatory_six: only the reg_name line.
  - fn_sales_engineer_verifies_supplier: only the stated four changes (no "name updated" mail from blank, the listing flag, the six re-read, reg_name never the reason).
  - fn_enqueue_doc_backups: only the blank-name guards.
  - Owner, SECURITY DEFINER, search_path and ACL are as live.
- Rehearsed and rolled back: SQL 1 + probe PROBE OK; SQL 2 + probe PROBE OK.
- Mutants:
  - The "updated" mail restored → "PROBE FAILED: a: told your company name was updated …".
  - z22 without its submitted/blank clause → "PROBE FAILED: a certificate that must stand was re-issued (1)".
- The probes also prove:
  - The listing is flagged to it_engineer and never taken.
  - A licence naming another claimed company leaves the name blank and is held as a mismatch.
  - Unread is held on the licence; nothing is approved without a name.
- Deno:
  - supplier_api, compliance_archive, supplier_portal and the licence tests: 310/310.
  - The 3 new test files fail on main (4 failures) and pass here.
- Offline: fetch-timeout 0 findings (46, the baseline); ssrf 18/18. Typecheck and lint not run: I did not link node_modules.
- Certificate rendered through pdf_native with a ZZ DEMO row, then turned into a PNG and looked at.
  - QuotesDone letterhead; rows Full name, Company (the licensed name), Trade licence no., Authorised signatory.
  - Before the read it says "Not yet read from the trade licence" and draws no licence row.
  - The empty "Accepted at" was my stub's field names, not the renderer.
- Production, read-only:
  - leads has no anon or authenticated grants. trading_name is reachable only through the API and no customer-facing select names it.
  - leads_claimed_by_lower_uidx stops a second row on a double tap or a second tab; the second gets a retry, then company_exists → load.
  - fn_match_capability does not read sector. fn_supplier_trade and fn_supplier_opportunities use sector only after confirmed trades, so removing the picker loses no matching.
- The author's walk:
  - 6 runs, each with one page error "Cannot read … 'roles'": ServicesTab reads d.vocabulary on an action the stub does not answer. ServicesTab is not in this diff; I infer the stub, not the product.
  - The invite/iphone "return lands accepted" step is marked FAIL, but its screenshot shows "Supplier Agreement — Done, Accepted by …", so the check is at fault.
  - The same screenshot shows "issued … once your trade licence is read" beside a licence already read: a stale sentence (low).

### Other answers
- Order: he can upload a licence before accepting. The server does not gate it; Submit stops on reg_terms ("Signed supplier terms").
- Taps: −1 typed name, −1 category picker, −1 "Create" tap; +1 typed full name, +1 "Accept" tap.
- z22:
  - It fires only on a licence name or number change; it is not fired by its own write (it updates no leads row), so it cannot loop with z20.
  - It sends a pg_net call to compliance_archive with force (no reply is awaited; a failure leaves the first certificate standing) and writes one auto_done agent_actions row. It mails nobody.
  - It runs for ZZ DEMO too (harmless).
  - Invitation door: a licence read after Submit is not re-issued, because the listing name is not blank. That certificate keeps the listing's name and no licence number. Acceptable for Monday; note it.
- Stage-3 notes:
  - Drop the optional contact name now: it duplicates the full name, and the screenshot shows both.
  - Keep the WhatsApp question.
  - Leave the emirates to the portal-walk fix.

## DATA COPY 3 (delta review, PR #1990 head 65552fd6a; throwaway merge with origin/main: no conflicts)
VERDICT: MERGE AND APPLY. Every point below was proved by running unless it says "inferred".
1. Extended data-copy probe:
   - Run alone against live: PROBE OK.
   - It now catches my two misses: x4 fails at Q1 (a rival's quote listed) and x7 fails at P1 (the customer's phone in the supplier's copy).
   - Still failing as before: x1, x2, x3, x5, x6, and the author's i1, i2 and m3 to m6, each at its own step.
   - The rival listing and quote it creates: the listing is checked to be is_demo inside the probe, uses an @example.invalid address, and both rows exist only inside the rolled-back transaction.
   - Triggers: no insert trigger on quotes, leads or pdpl_requests calls the web directly or writes a notification queue (25 checked). pg_net only queues, and the queue rolls back with the transaction. Inferred: a trigger that calls a helper which reaches the web was not traced one level down. Even so, nothing can commit or be sent.
   - No real supplier or customer row is touched.
2. The lock (a_burst_of_data_copy_requests_is_counted_one_at_a_time.sql):
   - Diffed against the live pg_get_functiondef: the ONLY difference is `perform pg_advisory_xact_lock(hashtext('pdpl_export:' || v_em));`, placed right before the count.
   - It sits after the `v_em is null` return, so the key is never null.
   - The lock is transaction-scoped, so it ends with the call. A hashtext collision between two e-mails only serialises them for a moment.
   - Owner postgres, SECURITY DEFINER and search_path are unchanged; there is 1 overload; the ACL {postgres, service_role, authenticated} is kept, revoked from anon/public and granted to authenticated, as live.
   - File plus probe: PROBE OK. Probe alone on live: PROBE FAILED ("does not lock"), as it should.
   - Pending notes correct. The probe cannot reproduce a real parallel burst (its note says so); the lock's placement is checked against the routine's definition.
3. Website:
   - A 401 from the door, or a thrown "rpc … answered 401", now says the existing reviewed "Your session has expired. Please sign in again." (portalText session_expired, EN/AR; suppliers get EN). No new Arabic.
   - A 503 still says try again; the 429 sentence is unchanged.
   - privacy.test.mjs: 14/14 on the branch; the new test fails on main's privacy.ts/PrivacyControls.tsx (13/1). tsc clean on the merged tree.
Proof scripts: scratchpad/rv-dc/q3.sql plus the mutants in rv-dc/mut2 and fixes/data-copy/mut.

## SIGN-UP 2 — #1987 @add2c9d10, reviewed as 40d01d390...add2c9d10 (12 Nov 2026)

VERDICT:
- Stage 1: MERGE AND APPLY with the forced order below, plus R2 (two more functions to deploy).
- Stage 2: MERGE AND APPLY last.
- R3 and R4 are small follow-ups that need not hold Monday.

### Release sequence (forced: the new supplier_api's `me` selects leads.trading_name, so it 500s before SQL 1)
1. Merge #1989, then #1987.
2. Immediately apply SQL 1 (a_supplier_is_named_by_his_trade_licence_not_by_typing.sql, PROBE OK).
3. Deploy supplier_api, kyc, compliance_archive, customer_api and supplier_portal (see R2).
4. Apply SQL 2 (the_acceptance_certificate_follows_the_trade_licence.sql), after compliance_archive is live.
Safe at every instant:
- Before the new site is served (2–3 min): old form against old functions. SQL 1 never touches a named row (0 blank names today).
- New site with old supplier_api: create_company answers enter_company, and Onboarding.tsx:80 shows "We are updating registration right now. Please try again in a minute." with Try again. That is the window to keep short.
- Old supplier_api with trading_name present: it never reads the column, so it is fine.
- Rollback: previous Vercel deploy; previous functions; drop trigger z22; re-apply the three routines' live text saved before step 2. The column can stay.

### Defects, most harmful first
R1 (MEDIUM, ordering, proved by reading): me_row.ts:28 ME_COLUMNS includes trading_name and licence_legal_name. A supplier_api deployed BEFORE SQL 1 breaks every supplier's portal. The author's order (functions before merge) is impossible anyway, because the apply tool needs the file on main. Hold to the sequence above.
R2 (MEDIUM, deploy list, proved by the import graph): customer_api and supplier_portal also import changed modules: _shared/supplier_terms.ts and _shared/supplier_registration.ts (the reg_name wording). The list of three leaves deploy parity red, and the portal says "company name" until they are deployed. Deploy all five.
R3 (LOW-MEDIUM, the record; inferred):
  - The second accept_terms (a NEW terms version) writes signatory_name AND contact_name = the typed name (profile.ts:73), overwriting a contact person who differs from the signatory. On the first review it was set only when empty. Keep `contact_name` only when empty: `if (!String(sup.contact_name ?? '').trim()) names.contact_name = fullName`.
  - save_profile still accepts signatory_name in PROFILE_COLS (lib/fields.ts) after acceptance. The form has no box for it and sends the stored value, so only a direct API call can change it. Drop signatory_name from upd when sup.accepted_terms_at is set.
R4 (LOW, probe strength, proved): a mutant that re-files by prefix (`d.path like x.path || '%'`) still answers PROBE OK. The code itself matches the exact (bucket, path) and dedupe 'SWEEP:%', so there is no collision today. Add a lead whose id is a prefix of the probe's (e.g. g and g||'0') so the probe would catch it.

### Proved by running
- SQL 1, diffed against LIVE now:
  - fn_supplier_mandatory_six: only the reg_name line.
  - fn_sales_engineer_verifies_supplier: only the four reviewed changes.
  - fn_enqueue_doc_backups: only the not-until-named guards plus the re-file UPDATE. #1985's 15-minute 'Trade licence' expression is intact.
  - Owner, SECURITY DEFINER, search_path and ACL are as live.
- Rehearsals, rolled back:
  - SQL 1 + probe: PROBE OK. SQL 2 + probe: PROBE OK.
  - Probe 1 alone on live: PROBE FAILED (f/a reg_name, the "updated" mail). Probe 2 alone on live: fails (no function).
  - My mutant without the 15-minute clause: "PROBE FAILED: the 15-minute rule of #1985 is gone".
- The re-file UPDATE:
  - It matches exact bucket and path and dedupe_key 'SWEEP:%' only, never a row in 'processing' and never a demo row (outside sandbox).
  - Only suppliers renamed from a blank name are re-filed. It resets them to pending once, and its new dedupe 'S:…' no longer matches, so it is idempotent.
  - It costs one join per enqueue call.
- Tests:
  - Deno, every test in supplier_api, supplier_portal, compliance_archive, kyc, where_he_works, whatsapp_choice, the wrong-document tests and the licence/terms tests: 376/376. That includes the tests of #1989 and #1985 and the new Arabic-only and agreement tests.
  - Node: mobileChange, whereYouWork, registrationDraft, licenceReceived, supplierRegistrationReads, the registration-form check, signup trade codes, services checklist and fixture_mobile: 62/62.
  - The certification judge (node_modules linked): 28/28. J1–J11 intact.
  - `tsc --noEmit`: exit 0.
- The three re-pins (supplier_services_checklist, whereYouWork, the registration form) are legitimate. Each now asserts the emirates are ABSENT from registration and PRESENT in ServicesTab, so they are stronger, not weaker. The form check adds guards for "no company shown for a wrong or held file", "Submit stops only when nothing was restored" and the soft-fail.
- Production, read-only:
  - 2 real claimed suppliers, both approved and accepted, both with a NULL signatory.
  - acceptanceNeedsName is false whenever accepted_terms_at is set, in all three doors, so neither can be locked out at the next terms version.
- Emirates (G):
  - Registration no longer writes service_emirates, so a new supplier's list stays NULL until he sets it on Services.
  - Live fn_match_capability unions coverage_emirates and service_emirates and passes `cardinality(stated) = 0`, so NULL or [] means all UAE. He receives requests once approved.
  - fn_decide (ceo "invite_ranked" only, called by fn_reason_apply_ceo__escalation_meaning) would skip him on an emirate filter. That is not dispatch.
  - 0 recent self-registrations have NULL emirates today, so this is new, but harmless to matching.

### Inferred from the code
- Combined cases:
  - (a) Profile in the licence slot: put back to none, the wrong-document sentence shown, the company panel hidden (`!licWrong`), Submit stopped because nothing was restored.
  - (b) Chamber certificate: held for a person ('ours_failed', fields not stored); Submit allowed; the gate says licence_being_read. reg_name is filtered out of the reason and of save_profile's stillNeeded, so he is never asked to type a name.
  - (c) A mobile change after acceptance keeps the verified number until the new one is verified (phoneWrite). A later z22 re-issue prints the current phone.
  - (d) A licence naming a claimed company: the name stays blank, he is held as licence_name_mismatch, and the e-mail says it is "already registered by another account".
- Arabic-only (F):
  - It is computed only in the readable branch (wrong and held are separate branches) and only when no English legal name was merged. An ordinary licence whose English name is read never trips it.
  - Held 'ours_failed' with tries 8, so no sweep. A person names it; it is never approved without a name and never rejected. The decider's clock key matches, so there is one ceo task.
  - The two gaps (the generic line after a reload; the Documents-tab door, which would ask for "a clearer copy") are acceptable for Monday.

## BOOKKEEPING 1988
PR #1988, head 3ca5dadd0. Verdict: MERGE. No blocking defect.

Defects (minor, none need a fix before merge):
- `.claude/memory/every-document-is-a-pdf-in-our-template.md`, "How to apply": the bullets on attachments we composed, a machine-readable copy beside the PDF, and `docs/reports/` staying Markdown are the session's extrapolation. They sit under the founder's two verbatim quotes with no marker. The parenthetical ("Code's Done" is the phone's spelling) is also an inference stated as fact.
- `.claude/memory/signup-asks-the-least.md`: "his own certificate showed only a first name" and "the session added ... and told him" are the session's own account, not marked as such. The long quote is flagged verbatim and uses an ellipsis marker. Neither point blocks merge.

Verified:
1. MANIFEST: exactly 6 lines added at the end, in the stated order, no other line changed. All 6 files exist on the branch. No duplicates (0). No `_probe.sql` among the 6. Every listed file exists on disk. (The 46 manifest lines containing "_probe" are the same on main and are not from this PR.)
2. pending/: exactly the 6 matching `<name>.txt` deleted. No probe note deleted, and the 41 `_probe.sql` files without a note are the same count on main and branch. No pending note remains for any MANIFEST entry (0). Every non-probe `.sql` outside MANIFEST still has its note (0 missing). No orphan notes (0). No regression introduced.
3. `scripts/checks/each_pending_sql_file_has_its_own_note.test.mjs` fails on: PENDING.txt back, empty note, a file both pending and in MANIFEST, a note naming a missing file. The branch hits none of these. Reasoned from the check's logic, and the same sets were computed by hand. Would pass.
4. Memory: front matter (name, description, metadata type/modified) matches neighbours. The two index lines are in MEMORY.md and point at files that exist. The `[[...]]` links resolve (`nothing-is-done-until-a-browser-proved-it`, `the-llm-understands-code-only-checks`). `_shared/doc_template.ts` and `pdf_native/` exist. Founder quotes are marked verbatim. No e-mail address, phone number, secret or model identifier found.
5. `document_intake_model.ts`: exactly two lines removed, both `deps.budget.left = 40;` (L81, L116). On main, `liveTradeDeps` returns `{ readProfile: liveProfileReader(...) }` with no `budget`, so the lines could only throw. Nothing else in `scripts/e2e/` reads `deps.budget` (the other grep hits are unrelated words).
6. Commits: the 4 non-merge SQL/memory commits and the e2e commit each carry both trailers exactly (Fable 5.2 plus the session URL). Prefixes are it_engineer, sales_engineer, customer_support, sales_engineer and it_engineer. The 4 merge commits are excepted. No other model identifier.
7. Changed paths (11): `.claude/memory/MEMORY.md`, `.claude/memory/every-document-is-a-pdf-in-our-template.md` (A), `.claude/memory/signup-asks-the-least.md` (A), `scripts/e2e/document_intake_model.ts`, `scripts/sql/MANIFEST.txt`, and the 6 deleted `scripts/sql/pending/*.txt`. Nothing else.

## SIGN-UP 3 — #1987 add2c9d10..69d637087 (12 Nov 2026)

VERDICT: MERGE AND APPLY stands.

- The delta is 5 files, so the merge of main 881fdaa4e brought nothing beyond #1989, which the branch already held. SQL 1 is byte-identical to add2c9d10's, so my live diff still holds.
- R3a: profile.ts:74 now sets contact_name only when it is empty.
- R3b: profile.ts:114 deletes signatory_name from the save when `sup.accepted_terms_at` is set. `sup` is read at :108, before this call, so a FIRST acceptance through save_profile still records the signatory.
- the_agreement_is_accepted_at_its_own_step.test.ts: 9/9 on 69d637087. On add2c9d10 the same file fails 3 (the two R3 tests and the updated name test).
- R4, rehearsed and rolled back: SQL 1 + the new probe answers PROBE OK. My prefix mutant now fails: "g: a file whose path only begins with his licence's path was re-filed as his". The probe's extra row (entity_id '0', path probe1672x/…) is rolled back by the CHK raise and touches no real row.
- The header's APPLY ORDER line (sql:41-44) is stale. The pending note says the forced order supersedes it, which is acceptable for the apply. Correcting the comment after the apply, with a re-diff, is optional.

## WRONG DOCUMENT 5 — PR #1992 @83e14965e on origin/main 5008c9ac4, 13 Nov 2026

VERDICT: MERGE AFTER ONE FIX. The fix narrows the new rule to the case that was measured.
- W1 is still closed. Proved by running my stand-ins plus 4 new answers: no chamber, establishment card, VAT or FTA answer at high or medium stores a field (each is wrong or held). A company profile, catalogue or ID document at 'high' with number, authority and expiry read: normaliseLicence empties every field, and the outcome is wrong_document. The establishment card called identity_document/high is now named rather than held, which is a better outcome.
- The author's tests cover what I would have stubbed:
  - Upload door, new supplier: path and state null, Submit blocked, 0 ceo tasks.
  - Upload door, approved supplier: accepted reading and file kept, Submit not blocked.
  - Sweep door, new supplier: path null, tries 8, Submit blocked.
  - Sweep door, approved supplier: reading and approval untouched, tries 8.
  - supplier_portal: nothing written.
  - Run: the 4 new tests FAIL on main (with --no-check: 4 failed, 20 passed). On the head, 75 Deno files: 612 passed, 0 failed. Corpus and accuracy node checks: 6/6 and 2/2. No fetch at import.
- Deploy list = the import closure of licence_extract.ts: license_extract, quote_extract, resend_inbound, supplier_api, supplier_catalog_ingest, supplier_portal, wa_inbound. No SQL.
- THE DESIGN QUESTION. As written, a real licence page that the model reads (authority AND expiry both filled) is refused outright whenever it says one of the four kinds at 'high'. Cases where that can happen:
  - an Emirates ID or passport scanned in the same PDF in front of the licence: identity_document's definition lacks "with no licence in it";
  - a quotation or product list in front of the licence: catalogue and quotation_or_invoice lack that clause too;
  - a profile pack with the licence on page 6.
  - The prompt does say "also when a licence appears anywhere inside a larger file … then read the licence" (SYS_LICENSE, line 14), but only company_profile repeats "with no licence in it".
  - For a new supplier, that refusal blocks Submit. The founder's second demand is the one that cannot be undone.
- The measured case had an authority but NO expiry ("contains no licence page or expiry date"). Both demands are met by this rule:
  - never-a-licence kind at 'high' → named UNLESS both authority and expiry were read;
  - both read → held (a person looks; Submit is never blocked; nothing stored).
  - It costs only a held sentence for a profile whose footer prints a validity date. It also lets the 243-answer replay guard stand as it was.
- The changed replay assertion (company_profile → certificate) IS a weakened guard. It removes the proof that no recorded real-licence answer is ever named wrong under a confused kind. Under the rule above it can be restored unchanged, since every recorded licence reads both fields.
- FIX:
  1. licence_extract.ts:308 → `const a = read(ai.license_authority), e = read(ai.expiry_date); if ((NEVER_A_LICENCE_KINDS as readonly string[]).includes(kind) ? (a && e) : (a || e)) return null;`. licenceJudgementOf then holds it, as it already does for certificate/other; update the :227 and :268 comments.
  2. Test file:
     - In the 12-row table, 'profile, number+authority+expiry', 'catalogue, all read', 'quotation, all read' and 'identity document, expiry read' → 'held_for_person' (QUOTES has both).
     - Add a row 'profile, number+authority, no expiry' → 'wrong_document'.
     - Restore the replay's `document_kind: 'company_profile'`.
  3. supplier_api and supplier_portal new tests: drop expiry_date from QUOTING_PROFILE / QUOTING (the measured shape).
  4. document_intake_corpus.mjs profile_quoting_licence: drop "| Valid until: 30/06/2027" from the footer (the measured shape), keeping company_profile as the expected kind.
  5. Optional prompt line: add ", with no licence in it" to catalogue, quotation_or_invoice and identity_document.

## DATA COPY 4 (PR #1993, head fb460e024; already up to date with origin/main)
VERDICT: MERGE AFTER FIXES. There is one untrue sentence (the must-fix below). Everything else holds.

MUST FIX: document.ts:71 and its Arabic twin at :144.
- `cfiles_note` says "The files on your company record, by name and date", which reads as the complete list.
- But supporting documents (certificates, project references) are kept under ref_table 'supplier_supporting', not 'leads', so the list leaves them out. Measured live: 7 such rows, and 1 real registered supplier has them. His copy would be untrue today.
- Change the note to: "Your trade licence, registration, profile and catalogue files, by name and date. Certificates and project references you added are in the Documents tab of your portal." The Arabic must be reviewed again.
- Or include the supporting documents (that needs SQL).

1. THE E-MAIL AND WHATSAPP SENTENCES ARE TRUE (proved).
- Every non-code e-mail goes through notifications: invitations, reminders and duty mails are send_outbox rows, and the other mail tables only record hand-offs.
- Only login_otp and kyc send directly through _shared/resend_send.ts, and both send one-time codes only. So the disclaimer about codes covers exactly the mail that is not listed.
- Notification statuses: only 'sent' means sent (sent 1265; queued, held, skipped, cancelled and suppressed are the rest). cc_emails is used on 0 rows.
- "From a verified number of yours" is accurate.
- Wording (non-blocking): line 41 would be plainer as "We have no record of any e-mail we sent you, other than one-time codes." That is still true.
- Line 44 lists "notices about your account, requests, quotations and payments", but the list can also hold invitations. Add "for example".
- The Arabic (lines 116/119) says the same thing. Arabic gate: no line in document.ts is unreviewed. The only failures are in files this PR does not touch (Dashboard, ProfileForm, serverCopy, licence_fields, licence_extract, supplier_registration), which are main's. The supplier-Arabic check passes 151/151.

2. THE 10-MINUTE HOLD AFTER A REFUSAL.
- It is a component timer counted from the refusal. A reload re-enables the button and the server refuses again with the same sentence: fine.
- It is cleared when the token goes null (sign-out) and on unmount, so the button is never disabled for ever.
- The refusal is announced to screen readers (role=alert).
- Minor: if the portal swaps token A straight to token B without passing through null, B waits up to 10 minutes. Fix: reset `limited` on any token change (PrivacyControls.tsx:67 depends on [token], so key the reset on token, not !token).
- privacy.test.mjs: 16/16 on the branch; it fails on main's code.

3 + 4. CODES IN WORDS AND ONE DOCUMENTS LIST.
- Looked at the pdf2 pages: one documents list, then the signed agreement; WhatsApp updates as a sentence; the source shows as "A test account" or "A public business directory or website"; no raw code, key, ISO date or batch name anywhere. pdftotext finds only file names.
- Nothing of his was dropped: the documents and the supplier's certificate date moved into the documents list, and the customer's certificate date stays.
- Mutant: removing the 'held' label fails "walk 4 … en held -> Held". document.test.ts has 10 tests, all pass (not 15).
- The Arabic copy was not re-rendered in pdf2.

5. FACTORY TEARDOWN IS SAFE.
- An address must come from the run's own selector AND match `qd-<tag>-%@example.%` or `delivered+qd-<tag>-%@resend.dev`.
- Proved on live with SELECTs: an unknown tag, an empty tag and an IN (null) each match 0 rows.
- Foreign keys: erase_files cascades from pdpl_requests; the vault has no cascade but is deleted first; no triggers on the four tables.
- The steps run before leads and customers are deleted.
- The new check passes 3/3, fails on main, and fails on a domain-pattern mutant.
- Gap (not a safety issue): the second purge path (demo_factory.mjs:1688) does not call pdplSteps.

6. TESTS AND DEPLOY.
- tsc clean.
- pdf_native is not in the diff and nothing it imports changed.
- Deploy: my_data_pdf, and the website at merge. No SQL.

## WRONG DOCUMENT 6 — PR #1992 delta 83e14965e..537c91f09, 13 Nov 2026

VERDICT: MERGE.
1. licence_extract.ts:311-313 is exactly the WD5 rule: `NEVER ? (a && e) : (a || e)` returns null, so the answer is held. The certificate/other guard is unchanged. The comments at :227, :248 and :268 say the same.
2. The 13-row table is right, including:
   - ID with expiry and no authority → wrong_document;
   - ID with authority and expiry → held;
   - the measured profile → wrong_document;
   - profile, catalogue or quotation with everything read → held.
   - normaliseLicence empties every field in both outcomes.
3. The replay uses company_profile again and the assertion is unchanged; it passes (243 answers replayed, 225 guarded). "As before" is true. The assertion guards on authority OR expiry, which is stricter than the rule, and it holds because no recorded answer reads exactly one of the two.
   - I checked the 18 uncovered answers: all 18 are blank reads (no name, no number, no authority, no expiry).
   - A blank read that the model calls company_profile/high would be named a wrong document instead of "could not read". That gap dates from #1985 and is acceptable: either way he is asked for his licence, and nothing is stored.
4. Door tests:
   - The measured shape is named on upload, on the sweep and in supplier_portal.
   - Authority plus expiry is held on upload and on the sweep: nothing stored, Submit not blocked, one review row, one ceo task, tries 8 on the sweep. supplier_portal also writes one review row and one task.
5. The corpus fixture no longer prints a validity date.
6. The recorded P1 answer from run d29f5749 (in the test) gives wrong_document with the company-profile sentence.
Run: the three files pass 27/27 at 537c91f09. With the 83e14965e code under the new tests, 4 fail: the two held door tests, the replay, and the table. The recorded-P1 test passes there too, as it should: it was already named.

## DATA COPY 5 (PR #1993, delta fb460e024..0518b2478)
VERDICT: MERGE. Every point below was proved by running.
1. document.ts:73 is true.
   - The list holds documents with ref_table 'leads' (on live: licence, profile, catalog) plus leads.license_doc_name and egr_doc_name; egr is printed as "Commercial registration".
   - On live, 0 claimed leads have a profile path or catalogue paths without a document row, and no other ref_table belongs to a claimed lead apart from supplier_supporting, which the sentence now points to.
   - The Arabic says the same thing and is in the reviewed strings (0 my_data_pdf lines unreviewed).
2. :41 "We have no record of any e-mail we sent you, other than one-time codes." is true: only the code senders bypass notifications. The codes line now appears only when e-mails are listed; both states are true.
   :44 now says "for example", in English and Arabic.
3. PrivacyControls.tsx: the hold lifts on any token change. privacy.test.mjs passes 17/17; the new test fails on fb460e024 (16/1).
4. Purge (demo_factory.mjs:1693):
   - With tag null, the regex shape `^qd-[a-z0-9]+-[^@]+@example\.(com|invalid)$` / `^delivered\+qd-…@resend\.dev$` covers every run's factory addresses. That is the purge's purpose, and it is still restricted to the purge's own accounts. A real person cannot match: example.com/.invalid are reserved, and resend.dev "delivered+" is a test sink.
   - On live: purge addresses 3, privacy requests 0. An empty or undefined tag matches 0 rows.
   - A '%' tag would widen the LIKE, but newRun refuses any tag outside /^[a-z0-9]{4,16}$/ (demo_factory.mjs:199), so no wildcard can reach it.
   - The factory check passes 4/4 and fails on a mutant with the tag removed from the pattern (3/1).
5. my_data_pdf tests 15/15. The pdf3 page images (supplier page 2, Arabic customer page 2) show the new sentences, with no raw codes.

## BOOKKEEPING 1991
Verdict: MERGE AFTER FIXES (two wording fixes, no code or data defect). Head e2b2b28f1 confirmed; origin/main head is 5ac05433f.

Defects (both in docs/reports/2026-11-12-evening-releases.md):
1. Line 10-11, "the 17-step check ... (`npm run gate`)": scripts/ci/local_gate.mjs on main defines 30 steps (lines 82-138); I found no source for 17. Fix: "The **local gate** is the session's own full check (`npm run gate`)" or the true count.
2. Table header "State at 00:40 UTC, 13 Nov" but the 1669 row cites #1993 and a second walk, which the file dates 02:00 UTC. Fix: header "State at 02:00 UTC, 13 Nov". Related: monday-readiness.md says "ten more changes followed" at 00:40, while the releases table lists 13 PRs after #1978 (1979-1982, 1984-1990, 1992, 1993); say "thirteen" or "several".
Minor wording for a non-technical founder: J1/J2/J6/J11 (only J6 and J2 are glossed), "ceo seat", "PROBE OK", "preflight", "hash", "9.1 s" style units are unexplained; add one line of definitions (J = the numbered test journeys; PROBE OK = the database self-test passed).

Verified OK:
1. MANIFEST: exactly 3 lines appended at the end, in the stated order; all 3 files exist on the branch; no duplicates; no _probe line. Production: pdpl_request_me, fn_sign_supplier_again_when_his_licence_is_read, fn_supplier_mandatory_six present; trigger z22... on leads present; leads.trading_name present; pdpl_request_me contains pg_advisory_xact_lock = true.
2. pending/: exactly the 3 matching non-probe notes deleted (3 D, 7 lines); all _probe.txt notes remain; the 5 remaining non-probe notes have no MANIFEST entry (no stale note); no other pending change.
3. e2e: one line changed, now fill('Accepting'); the later full-name fill untouched. supplier_terms.ts personName requires >=2 words containing letters, so the old three-word 'ZZ DEMO Accepting' was always accepted.
4. Memory: only heading/label lines changed in both notes; no founder-quote line in the diff; no secret, contact detail or model name.
5. Report: PRs #1976-#1993 named are on main (1976/77/83 not re-grepped beyond the readiness note; 1978-1982, 1984-1990, 1992, 1993 seen in log); every SQL file named exists and is in MANIFEST after this PR; ledger matches production (1662 done, 1663/1664/1666 standing, 1668/1669/1670 done, 1671/1672 standing; also 1665 done, 1667 standing); spend 10.262 and AED 0.3061 = USD 0.083 agree; "being fixed" no longer appears; the NOT proven section does not contradict the proven table. No e-mail, phone, secret or model name in the file (grep clean).
6. Commits (5 non-merge): each has both exact trailers, seat prefix (it_engineer, sales_engineer, customer_support), no other model name.
7. Diff is exactly nine paths: 2 memory, evening-releases (A), monday-readiness, the e2e file, MANIFEST, 3 pending deletions.
Not verified (needs run logs): counts such as 63 documents/80 calls, 13 leaky variants, 48 passes.

## BOOKKEEPING 1991 delta
Verdict: MERGE. Head fe17aa7d8; diff e2b2b28f1..fe17aa7d8 touches only the two report files; two new commits (it_engineer prefix) carry both trailer lines.
1. Gate paragraph true against local_gate.mjs on main: 30 STEPS rows; 12 carry prod:true (receipts, fn-owner, duty-clock, model-matrix, registry-sync, manifest, deploy-parity, export, advisors, edge-logs, anon-definer, alarms-quiet); with npm-test skipped that leaves 17 offline steps (incl. deno-suite and the post-step tree-unchanged). "13 not part of it: 12 + npm-test" correct. Unverifiable from code (run history): the #1992 build-folder restart and "17 of 17" wording in session messages.
2. Header now "State at 02:00 UTC". 3. Readiness note says "thirteen more changes"; release-table rows after #1978 count 13 (1980, 1979, 1982, 1981, 1984, 1986, 1985, 1989, 1990, 1988, 1987, 1992, 1993).
4. Glossary true: J1 desktop/direct normal licence, J2 mobile/invite link, J6 mobile/public (direct) door, J11 company profile in licence slot (certification lines 75-89). PROBE OK, ceo seat and hash explanations are plain and accurate; the "401/preflight" jargon row was also simplified.
No other change, no personal detail or model name added.

## DATA COPY 6 (CORS) (PR #1994, head 346acb1a3)
VERDICT: MERGE. One optional hardening is listed below. Each point says whether it was proved by running or inferred.
1. LIVE TODAY, REAL CHROMIUM, NO INTERCEPTION (proved).
   - Page quotesdone.ae/portal, fetching my_data_pdf with the site's headers (apikey + Authorization + Content-Type, cache:'no-store'): BLOCKED "Failed to fetch".
   - The same fetch without apikey: HTTP 401, so readable.
   - So apikey is the whole defect. In Chromium, cache:'no-store' does NOT add cache-control/pragma to the preflight. That matches the Fetch standard: those headers are appended in HTTP-network-or-cache fetch, after the CORS-unsafe header list is computed.
   - Safari: not run (no WebKit on this machine). By the spec it does not need them either. Optional, costs nothing: add `cache-control, pragma` to door.ts:17, or drop `cache:'no-store'` at PrivacyControls.tsx:43, since the response is already no-store.
2. HEADERS ON EVERY RESPONSE (read).
   - siteCors (_shared/site_origins.ts:106-114) wraps EVERY response the handler returns (OPTIONS, 200, 401, 429, 503, 500), echoes Access-Control-Allow-Origin for quotesdone.com/.ae and their www forms, and sets Vary: Origin.
   - Expose-Headers: Content-Disposition is kept.
   - No Allow-Methods is needed: POST is a CORS-safelisted method.
   - Only gateway-made errors (546/504) carry no ACAO; the page then says "Something went wrong", which is still true.
   - Site CSP connect-src lists https://htdblwldjkcgjvmqkbeh.supabase.co. The site sends no COEP/CORP. nosniff with application/pdf is fine.
3. TESTS (run).
   - my_data_pdf: 15/15. door.test asserts apikey, authorization and content-type are each allowed, and FAILS on main's door.ts (4/1).
   - New check: 3/3.
   - Gap: the unit test calls `handle`, not the siteCors wrapper, so ACAO itself is not unit-tested.
4. CHECK BLIND SPOTS (read).
   - It sees only `fnUrl('<literal>')` calls whose headers are an inline object.
   - It does NOT see 8 dynamic callers: me/api.ts, supplier/api.ts, comms, orders, predict, SupplierRelationship, SupportRatingPrompt, and fetchRetry (a helper; its callers build the request). It also misses the boot-prefetch inline script.
   - I checked those by hand: every one sends only Content-Type + Authorization.
   - Every function the site calls has a literal allow-list in its own folder containing both (doc_extract allows '*').
   - forwardToFunction and instrumentation run server-side (no CORS); supaRpcAs goes to PostgREST (Supabase's own CORS).
   - Result: no other portal call is blocked today.
   - Its other limits: headers passed as a variable or spread, and allow-lists that come from a shared helper (there are none today).
5. REAL PERSON PATH.
   - door/pdpl_request_me have no run-tag or demo branch; tags only label observe() runs.
   - The demo walks already reached the live function server-side, so SUPABASE_ANON_KEY and PostgREST-as-the-person work there.
   - The brand fonts and lockup answer 200 from the public bucket (run). Null arrays are handled by list().
   - RISK (measured locally, under load): rendering 500 e-mails + 500 WhatsApp messages takes 1.5 s; 100+100 takes 0.7 s. One live address has 302 sent notifications (max WhatsApp per number 36).
   - Test FIRST after deploy: the founder's own supplier account on his iPhone. Then the address with the most mail: if it gets 546 / no answer, lower the 500 cap.

## LESSON 1995
Verdict: MERGE AFTER ONE WORDING FIX (no factual error found). Head 056c72887 on 286c72c2a; diff is exactly the three expected paths (memory note new, one MEMORY.md index line, correction block in the evening report).
Fix (memory note, "How to apply", 4th bullet): "Its blind spots, said in the file: calls whose headers come through a variable or a spread, and a function whose allow-list comes from a shared helper." The check file states only the second (allow-list not in the function's own folder is named). The first is not said in the file, and there is an unstated third: callsWithHeaders reads headers with /headers\s*:\s*\{([^}]*)\}/, which stops at the first "}", so any header after a `${...}` template value (e.g. content-type after PrivacyControls' `Bearer ${token}`) is not seen. Reword to "Its blind spots: calls whose headers come through a variable or a spread, a header written after a `${...}` value in the same object, and a function whose allow-list comes from a shared helper (the last is named by the check)" or add the first two to the file's header comment.
Verified: (1) PrivacyControls.tsx line 44 sends apikey, Authorization, Content-Type to my_data_pdf; door.ts line 45 now allows authorization, content-type, apikey, x-client-info, cache-control, pragma; eadac561a line 35 allowed only authorization, content-type; check file exists and its self-test reproduces the defect. (2) Run-tag interception is scripts/e2e/browser.mjs line 130 `ctx.route((u) => carriesRunTag(u, BASE), ...)`, whose predicate (line 102, "exact project host and path prefix") is only the Supabase /functions/v1/ path; note says "test factory" but it is the e2e harness (browser.mjs, demo_factory.mjs only supplies the credential): optionally say "test harness". (3) Count is exactly 25 non-test functions whose literal is only authorization, content-type: cad_convert, claim_lookup, compliance_archive, customer_api, customer_documents, customer_portal, drawing_redact, extract_text, inquiry_intake, kyc, messages_api, mobile_otp, pdf_native, quote_compare, refund_flow, refunds_api, reveal_invoice, rfq_flag, stripe_checkout, stripe_confirm, supplier_api, supplier_catalog_ingest, supplier_onboard, supplier_pay, supplier_portal (44 functions have a literal; the rest allow apikey too, one '*', inbound_email adds x-webhook-secret). (4) Merge commit 286c72c2a is 08:20:01+04:00 = 04:20:01 UTC; correction dated 04:25 UTC. (5) Front matter matches neighbours (name, description, metadata type/modified); index line points at the file; [[nothing-is-done-until-a-browser-proved-it]] and [[release-lessons-of-the-12-nov-fix-round]] exist (lesson 14 is there); ledger 1679 is the founder's wordless iPhone screenshot at 07:49 Dubai showing exactly "Something went wrong. Please try again." (the app's message, not his words, and the note does not put words in his mouth); no secret, contact detail or model name. (6) Correction is dated, sits above the findings table, rows left as written; row line 46 ("Walked signed-in ... twice"), line 97 (the walk row) and line 121 (real iPhone "the founder's own phone is the proof") are covered by it. (7) Only THREE non-merge commits exist on the branch (2167f6e5d, effd9100c, 056c72887), not four; each has both exact trailers and the it_engineer: prefix.
Not verifiable here: edge-log "two OPTIONS 200 and no POST", the six clean-context walks and their 2.9-3.4 s timings, "live preflight sweep of 27 functions", "eight helper callers".

## LESSON 1995 delta
Verdict: MERGE (head 95b82798d; commit has both trailers and the it_engineer: prefix; diff is only the check file and the memory note).
1. Ran the file in a scratch copy (src and supabase symlinked, folder deleted): 3 tests pass, 20 calls seen, my_data_pdf = apikey, authorization, content-type. Reader probes: `Authorization: 'Bearer ' + (ok ? a : b)` yields no `a`; quoted dashed key, multi-line object and trailing comma read correctly; `headers: h` returns null (call silently skipped, which the file header now says); `{ ...h }` returns [] (recorded with no headers, passes; also covered by the header's "spread").
   Unlisted edge cases, none present in src today and all minor: a `}` inside a quoted string value (`'x}y'`) ends the object early and later headers are missed (false negative); a quoted value containing `, word:` yields a false key (loud false positive); a nested object value (`a: {b: 1}`) yields `a` and `b` as keys (loud false positive). The doc comment says "string values are dropped" but only backtick strings are; reword to "template strings and `${...}` are dropped". Optional.
2. The header's "does NOT see" list matches the code (variable/spread, non-fnUrl-literal calls, deployed function answers). "Eight helper callers read by hand" is not verifiable from code.
3. Memory note says "test harness (`scripts/e2e/browser.mjs`)" in both places and the blind-spot sentence matches the file's header.
Note: the scratch run used the checkout's working tree for src and supabase (branch claude/sleepy-johnson-5fg2g9, clean), not origin/main.

## READER DECIDES 1 — PR #1996 @54f8884d9 (cut from eadac561a; a throwaway merge with origin/main 286c72c2a is clean), 13 Nov 2026

VERDICT: MERGE AFTER ONE FIX (R1). Fold in R2, which is small. Check R4 on the first deploy.

### Defects, most harmful to a real supplier first
R1 (MEDIUM; inferred by reading; the founder's fear): a certificate or other at 'high' with an authority AND an expiry read is now REFUSED on one reader's word. There is no second read, and a new supplier cannot Submit.
  - The prompt (SYS_LICENSE) does cover these as trade_licence:
    - "ANY trade or commercial licence or any part of one" covers a "Commercial Licence Certificate";
    - "a Commercial Register certificate page" covers a "Certificate of Commercial Registration";
    - e-trader is named, and so is a free-zone Certificate of Incorporation/Formation/Registration.
  - It does NOT name an Industrial, Professional or Tourism licence. A reader that calls a real DED professional licence 'other' or 'certificate' at 'high' refuses a licence page it has just read.
  - Fix, no prompt change and no paid re-run: licence_extract.ts:303 becomes `if (read(ai.license_authority) && read(ai.expiry_date)) return null;` for EVERY non-licence kind (drop the NEVER_A_LICENCE_KINDS condition).
    - Such a file then goes to the second read: the other family, whose question names "an economic department or a free zone authority". The cost is USD 0.015 and about 12 s, and only for files that print both fields.
    - A chamber certificate is still named, by the second reader. Re-pin the test rows "certificate, authority+expiry → named" to "second read".
  - The WAY sentence and the refused-twice task are a fallback, not a fix: the supplier has to notice and write in, and a person then makes a database write.
R2 (LOW; read): WhatsApp does not tell him the reader's sentence.
  - media.ts puts the named message in `note`. But media_in.ts:130-133 builds the pending reply from `r.seen` ("kept for our team: …"), and `note` is unused there.
  - Fix: in media.ts set `seen: named ?? seen`.
  - The WhatsApp door also never calls recordWrongDocument, so refused-twice cannot fire on WhatsApp.
R3 (LOW): refused-twice opens one task per supplier FOREVER. A second, different file refused twice later opens nothing. That is acceptable.
R4 (VERIFY ON DEPLOY): licence_pages.ts:29 imports `npm:unpdf@0.11.0` dynamically. A failure is caught as null, so the page rule would be silently off.
  - The same literal-specifier pattern runs in production elsewhere (pdf_text.ts, dwg.ts, sharp).
  - Prove it with one free call to the deployed license_extract with N1_long_profile_12_pages.pdf: it must answer guard 'too_many_pages' before any model is asked.

### Proved by running
- licencePageCount on every registration fixture: the L* licences 1 page; P* profiles 1–2; N1 12 (refused).
  - Synthetic PDFs: 12 pages → 12; /Count 3 over 12 page objects → 3 (read by the reader, the safe direction); /Count 12 over 3 objects → 3 (not refused); 300 pages in 6 ms; 5000 pages in 86 ms (pdf.js reads /Count, not every page); damaged or not a PDF → null (read as before).
- The four test files: 36/36. On main 11 of the 29 runnable tests fail, and the new file cannot load.
- Mutants: the page guard moved after the model call → FAILED; a second read asked for a non-held answer → FAILED.
- 79 Deno files in the touched folders: 624 passed, 0 failed. No src change, so tsc was not needed. The new sentences are English-only server strings, as suppliers read English (ruling 1008).
- Production, read-only:
  - document_expiry_ai = 'on', so the page rule and the second read are reachable for real uploads today.
  - fn_licence_authority_class('Dubai Chamber…') = 'unknown' (the W1 SQL is live).
  - agent_actions has no CHECK on kind, so the 'licence_refused_twice' and file_sha (detail jsonb) inserts cannot fail. No SQL is needed.
  - fn_ai_route_review_for with vision:
    - first read by luna-pro → second by sonnet (fallback opus);
    - first by sonnet (itself the fallback) → second by luna-pro (fallback qwen flash);
    - first by gemini → luna-pro.
    - Never the same family. counterpart_model is the SERVED model (handle.ts `model: used`).
- Deploy list = import closure, complete: license_extract (licence_pages, licence_second_read), quote_extract, resend_inbound, supplier_api, supplier_catalog_ingest, supplier_portal, wa_inbound.

### Read (inferred)
- The second read runs only for a held (iii) first answer: never for trade_licence or a 'high' refusal (the mutant proves it), and once per call.
  - The sweep never reaches a held file again (tries 8) or a refused one (put back). A row in 'ours_failed' from a provider failure can cost first + second read on each of its 8 tries at most.
  - No per-supplier cap exists. Upload cost doubles only for unsure files.
  - No independent reviewer → used_llm:false → no parse → held, never licence. A malformed second answer → held (exact trade_licence/high only).
- Timing: supplier_api waits up to 120 s for license_extract, so the late answer is written by its in-flight job and shown by the late-read poll.
  - The Documents tab (supplier_portal) aborts at 10 s. A first read already takes 21–23 s, so that is pre-existing: 'ours_failed', then the sweep.
- W1: a chamber certificate the second reader calls trade_licence/high is stored, but its authority classes 'unknown' (licence_authority_unconfirmed): held, never approved. Enough for Monday, since it needs both readers wrong.
- The e-mail door (supplier_docs.ts:157-170): a refused or held file writes nothing to the lead, so an approved supplier's standing is untouched. The reply quotes the sentence to the sender, matched by email/claimed_by as before.
- Page rule 8: defensible. A DET licence with its MOA in one 12-page PDF is refused, but the sentence says "attach just the licence pages", with a way to a person.
- Still waiting on a person, and none has a screen (each is a ceo task plus a database write):
  - second reader unsure: rare;
  - refused twice;
  - licence_authority_unconfirmed;
  - an Arabic-only licence name (#1987);
  - an approved supplier's unread licence on day 3 (#1982).
  - A reader could later decide refused-twice (ask the second family before the task) and the unknown authority (a direct question on the authority). The other three need a person or another read.
- J12 in a FREE run cannot reach license_extract, so it cannot prove the page rule. The unit run above plus the R4 deployed call prove it.

## DROPBOX TREE 1 — PR #1997 @17dfe2758 (13 Nov 2026)

VERDICT:
- (a) The filing structure: MERGE AFTER FIXES D1 and D3–D5. The rule and the SQL are sound and rehearsed.
- (b) The credential scope and the door: MERGE AFTER FIX D2.
- (c) The migration: HOLD until (a) is applied and its worker is proved on one row. It reads correctly and rehearsed clean (below).
- Merges: none conflicts. Main 286c72c2a merged cleanly; #1996 (sales_engineer-the-reader-decides-what-is-a-trade-licence) merged cleanly.

### Defects, most harmful first
D1 (HIGH, the backup stops marking; proved by reading row.ts:124/145): the new worker writes `moved_from: null` in EVERY done-mark, the plain upload included.
  - Deployed BEFORE the SQL adds doc_backups.moved_from (the author's order), every successful upload fails to be marked: PostgREST refuses the unknown column. Each run then re-uploads and the queue never drains, for everyone.
  - Fix:
    - Either row.ts:124/145 sends moved_from only when `'moved_from' in row`,
    - or split `alter table ... add column moved_from` (sql:66) into its own first file.
  - Safe order:
    1. merge;
    2. apply the column, or the whole file;
    3. deploy customer_api and dropbox_backup;
    4. MANIFEST.
  - In the gap, the OLD worker meets 'quotation' rows and moved_from rows. It fails the 'quotation' rows (retryable). It UPLOADS the re-filed rows at their new path instead of moving them, so it leaves a second copy, never a loss. Pause the dropbox_backup cron for the few minutes, or accept a handful of duplicates in Storage/.
D2 (HIGH for a credential, proved by reading): the grant `scope || array['customer_api']` (sql:273) is the WHOLE function. requireInternal(…, 'customer_api') guards three doors: quotation_for_backup, compare_arabic_finish (renders and SENDS a comparison report to a customer) and rematch_waiting (runs the matcher and e-mails suppliers). The backup credential can now trigger customer and supplier messages.
  - Fix: a door-specific scope. customer_api/index.ts:74 becomes `requireInternal(admin, secret, 'customer_api.quotation_for_backup')`, and sql:273 grants that scope only.
  - From outside: the door needs the service key as bearer AND a valid internal credential, so no customer or supplier JWT and no anon can reach it.
D3 (MEDIUM, a company's files can land in another company's folder; inferred): fn_dbx_supplier_folders numbers same-name companies by `row_number() over (partition by lower(cat), lower(name) order by r.id)`.
  - The plain folder belongs to the LOWEST lead id, recomputed on every run.
  - When an older listing (lower id) is later claimed and licensed under the same name in the same category, the established supplier is renamed "- licence <no>" and his whole folder moves. The newcomer takes the plain folder at once, while those moves are still pending or failing (to/conflict throws). Until they finish, two companies share one folder.
  - The same applies to two names that differ only after fn_dbx_component's 200-character cut.
  - Fix: order the partition by who OPENED the folder first: the created_at of his 'S:<id>:details' row, then id. An existing folder is then never taken over.
D4 (MEDIUM, a stale document presented as current; the author's own gap): a quote revised in place keeps its 'SQ:<lead>:<quote>' row done and is never re-rendered. The job folder then shows an old "Quotation <job>.pdf" as the quotation.
  - Fix before relying on job folders: key the generated row on the quote's updated_at or revision (dedupe 'SQ:<lead>:<quote>:<rev>'), and send the previous one to Job …/Earlier versions/.
  - Few quotes exist today, so the fix can follow the merge but must precede the first real job.
D5 (MEDIUM, the probe no longer guards #1985; proved): my mutant that disables #1985's 15-minute "Trade licence" rule (fn_dbx_supplier_files) still answers PROBE OK. #1987's probe checked it; this one does not.
  - Fix: add to the probe the position() check of `l.licence_read_at > now() - interval '15 minutes'` inside fn_dbx_supplier_files.
D6 (LOW-MEDIUM, inferred): the customer's request folder loses the supplier's original quotation.
  - The supplier section runs first and claims (bucket, path) for 'SQO:'; the CUSTOMER DOCUMENTS insert ('Q:') then conflicts and is skipped. Step 1 also MOVES any existing customer-side Q: row into the supplier's job folder.
  - Today 0 Q: rows exist, but from now on the customer's Quotes/ never holds the original. Decide whether that is wanted; if both, copy the generated quotation rather than move.
D7 (LOW, inferred):
  - A correspondence or case-summary row that is 'processing' when a folder moves finishes in the old folder. Later runs compare against the new Company Details folder, and step 1 does not cover correspondence, so it stays behind for good.
  - The old folder is never removed: empty folders accumulate.
  - The founder's 4 SWEEP rows (files no longer on his row) stay under Storage/: the Earlier versions branch takes only 'S:<id>:' keys.
D8 (LOW, cost): the correspondence block calls fn_dbx_supplier_folders() (every registered supplier, each with fn_dbx_main_category) once per new supplier message, and enqueue calls fn_dbx_supplier_files twice. 299 ms is measured on today's 2 suppliers; it grows with suppliers × messages.

### Proved by running
- Live diffs (pg_get_functiondef now):
  - trg_doc_backups_admit: only the id anchor, now limited to his own rows.
  - fn_support_case_summary_backup_enqueue: only v_base = fn_dbx_supplier_folder(), which returns false when there is no folder (the summary waits).
  - fn_enqueue_doc_backups: only the supplier section (the folder move, the re-file, the insert from fn_dbx_supplier_files) and the correspondence folder. #1985's 15-minute rule is carried inside fn_dbx_supplier_files. #1987's not-until-named rule and its re-file are superseded by the general rule: a folder exists only with a name and a category, and step 1 re-files any SWEEP row by (bucket, path).
  - Owner, SECURITY DEFINER, search_path and ACL are as live.
  - The new routines are definer except fn_dbx_original_name (immutable, invoker). All have a pinned search_path and are revoked from public, anon and authenticated, one overload each.
- Rehearsals (rolled back):
  - File + probe: PROBE OK.
  - Probe alone on live: fails (fn_dbx_main_category is missing).
  - My mutant: a no-trade supplier gets 'Uncategorized' → "PROBE FAILED: a supplier with no trade still has a folder; …; an Uncategorized folder".
  - My mutant without the 15-minute rule: PROBE OK (D5).
- Category on live (a temporary copy of the function, not saved):
  - 158318: "Real estate brokerage & property management", the label of real_estate_services. It has 19 evidence items.
  - 19398: "Oilfield & Industrial Supplies", reached by the group-size step: no model evidence, 8 trades.
  - The rule ranks only stored model evidence (trade, licence='covered') and his confirmed order; there is no keyword match, and ties fall to ordinality, so it is deterministic.
- Names: fn_dbx_safe strips \ / : * ? " < > | and control characters and trailing dots or spaces; an empty name becomes '_'. Arabic and emoji are kept. 0 of 223 active trade labels carry a refused character.
- Migration (c), rehearsed with the guard bypassed, together with the file, all rolled back:
  - 39 rows: 158318 has 15 (11 in Suppliers/, 4 SWEEP in Storage/); 19398 has 24.
  - 35 moves are queued, 0 rows are left in a legacy or uncategorized path, and 0 two rows share a target.
  - One "Trade licence" each.
  - The profile is relabelled "(sent as trade licence)" into Earlier versions, together with the duplicate licence.
  - The 3 test acceptances are archived. 0 other suppliers are re-queued and 0 leads rows are touched.
  - It is not idempotent but safe: a second run raises on its own counts.
  - Every move is a worker row (moved_from), so Dropbox and the table cannot disagree.
  - Dropbox listed read-only: Suppliers/ holds 38 files (19398: 24, not 26; the founder: 11; tests: 3) and no other file. So "every other folder is empty" is true for files; the 74 _archive records do not leave files in Suppliers/.
  - The empty-folder archive is a manual folder move by the operator. List again just before it.
- Tests:
  - Deno dropbox_backup and customer_api: 154/154 (move, quotation door, pdfs).
  - Node checks naming the touched files: 108/109. The one failure, deploy_parity_detects_a_stale_file, fails on main too.
  - canonical_routine_manifest: 0 findings. Pending notes check passes. fetch-timeout: 0 findings (46). ssrf: 18/18.
  - an_unfinished_sign_up_is_never_a_customer: a legitimate re-pin (the old slug/uncategorized rule is replaced by the rulings 1680/1682 rule, with stronger asserts).

### Inferred
- The quotation filed is the customer's pre-reveal copy, so in his own folder the supplier sees his own quote with his brand and model generalised. It carries the request summary or scope in the customer's words; I have not seen whether that text is contact-masked.
- Render one ZZ DEMO quote through the door (op 'sandbox') before the first real job, and read it for the customer's name, phone, e-mail and company.
- A failed render is a 503 for that row only and is retried; the run goes on. A destination conflict throws for that row only.
- Each quotation is one pdf_native render, so a large backlog of live quotes takes several runs.

## READER DECIDES 2 — PR #1996 delta 54f8884d9..7779ba246 (R1, R2; origin/main 286c72c2a merged in), 13 Nov 2026

VERDICT: MERGE. One small follow-up, not blocking: pass the reader's sentence as `must` (below).
- R1 (licence_extract.ts:300): the rule is now `read(authority) && read(expiry)` → second read, for every non-licence kind. NEVER_A_LICENCE_KINDS has no reference left anywhere in the tree (tests and scripts/e2e included).
- Stand-ins, proved by running:
  - DED professional licence, other/high, both fields read → second read → trade_licence/high → stored (authority DET, expiry 2027-06-30).
  - Chamber certificate, both read → second read → named.
  - Chamber certificate, validity only → named at once.
  - Measured profile (authority, no expiry) → named at once.
  - Profile with both → second read → named.
  - A malformed second answer ('Trade Licence' / 'certain') → held.
  - other/medium → held.
  - The first reading never stores a field, so W1 stays closed. Every door goes through normaliseLicence, and the sweep tests pass.
- R2 (WhatsApp):
  - media.ts records the wrong document with its file SHA, so refused-twice now fires on WhatsApp too (the author's test proves it). Nothing is written to the licence record.
  - media_in.ts hands the model "tell them exactly this, word for word: <sentence>", unless his caption already filed the file as a profile or similar.
  - The reply goes only to the sender (`From`).
  - If the model fails or the guard refuses its text, he gets the fixed held receipt. The turn is replayed later from `results`, which now carries the sentence, so he is told something true.
  - Not enforced: the model can still paraphrase the sentence. Fix: pass the reader's sentences as `must` to `sayFor('supplier')(…, 'en', must)` at media_in.ts:~139. The gateway's reply guard already enforces `must` on other lanes.
- Tests, proved by running:
  - The four files plus the WhatsApp test: 41/41.
  - The WhatsApp test against the 54f8884d9 wa_inbound code: FAILS (1 of 5), as it should.
  - Both mutants still fail: the page guard moved after the model call, and a second read asked for a non-held answer.
  - 79 Deno files in the touched folders: 625 passed, 0 failed.

## DROPBOX TREE 2 — #1997 @ef45d7f7c, delta from 17dfe2758 (13 Nov 2026)

VERDICT: MERGE. Apply and deploy may come in either order. Hold the migration until the sandbox check written into its own header is done. One low fix (E1) can follow.

### Each claim, against the code
1. Either order: TRUE (read).
   - Apply first, old worker deployed: fn_doc_backups_next and fn_doc_backups_sandbox_next (sql:386/424) hand quotation, quotation_customer and moved_from rows only to a run id containing 'moves1'. The old worker's ids do not, so those rows wait. Every other row works as today.
   - Deploy first, SQL not applied: movedCleared (row.ts) names moved_from only when the row carries it, so done-marks never touch the missing column. No quotation or move rows exist yet.
   - move.ts:23: before moving, it checks the old path still holds this row's own hash. Otherwise it uploads its own copy, never moving another file.
2. The door: reachable only with the service key AND a credential holding the new scope 'customer_api.quotation_for_backup'. sql:360 grants only that, and compare_arabic_finish and rematch_waiting still require 'customer_api' (test plus my mutant below). No JWT or anon can reach it.
   - It returns only {bucket, path, ref, side} of the file it rendered. It never returns a person. It reads the customer's name, e-mail and phone only to scrub them.
3. What each file shows:
   - The supplier's Job copy: the request passes through identity_scrub.inboxField with seedTerms(name, e-mail, phone, project). A name, phone, e-mail, web address or project name is redacted, and a field with any residue is withheld whole. If the buyer cannot be read, all request text is withheld. It is still rendered as the pre-reveal page, so his OWN brand and model are generalised and he is "Supplier A". That is not a leak, but it is less than the founder allowed ("his own name in his own folder is fine").
   - What is NOT removed: an area or villa number written in free text that is not the project's name ("Al Barsha, villa 12"). That is the same gate the supplier inbox serves today, so the supplier already sees it. If ledger 1683 means stricter, the inbox shares the gap: say so to the founder rather than fix one copy.
   - The customer's Quotes/ copy: rendered side 'customer'. His own words stay; before a reveal the supplier is masked (supplierIdentities, generalised lines); after a reveal it names the supplier.
4. "Earlier versions" overwrite: the earlier revision is renamed "<name> - <Dubai YYYY-MM-DD HH24MI>.pdf" (sql:478). Two revisions filed within one minute get the same name, and the second upload overwrites the first, so that revision is lost from Dropbox; the row and its render in backups/generated stay.
   - E1 (LOW): add seconds or the revision hash: `to_char(…,'YYYY-MM-DD HH24MISS')` or `|| ' ' || right(d.dedupe_key, 12)`.
   - The earlier row keeps its own rendered bucket/path, so the earlier file carries the OLD figures, not a re-render.
5. Enqueue (~550 ms): it runs in dropbox_backup. z70 → fn_backup_kick → pg_net, debounced to once per 60 s, plus the pg_cron second scheduler. It is never inside a supplier's or customer's own write, so the user's wait is unaffected.
6. The migration:
   - It cannot run by accident: v_ok = 0 and founder_instruction has no id 0, so it raises HELD.
   - It deletes nothing: updates of doc_backups rows plus one fn_enqueue call.
   - The folder name is licence_legal_name, else company_name: his licensed name.
   - Personal data in the repo: three test-acceptance folder names in its path list (sql:89–91), one of which reads like a person's name. It was already there in the first round. Prefer matching by dedupe_key or id.
7. Mutants, rehearsed with the repository's rolled-back tool. All 4 FAIL as they should:
   - a no-trade supplier gets 'Uncategorized';
   - #1985's 15-minute rule dropped;
   - the plain folder ordered by id instead of opened_at (D3);
   - the backup scope widened back to 'customer_api' (D2).
   - File + probe: PROBE OK. The probe alone on live: fails (no function).
- Tests: Deno dropbox_backup, customer_api, my_data_pdf and identity_scrub: 175/175. The new node check passes, 3/3.

## ANONYMITY F2 DOORS 1
Independent review, 13 Nov 2026, of origin/sales_engineer-what-a-supplier-receives-names-no-customer-no-area-no-old-supplier @44fb1e069 against origin/main. Worktree /tmp/claude-0/review-f2 (removed). Production was read with SELECT only (pure masking functions on probe strings, grants, the definitions of fn_edit_inquiry, fn_supplier_workspaces, fn_supplier_opportunities and fn_supplier_safe_text). No model calls, no writes.

VERDICT: FIX

1. Three doors that send customer text to every matched supplier still use the name-only scrub (the L3 pattern this branch was meant to close). PROVED by running the code:
   - customer_api/actions/inquiry_lifecycle.ts:108 `rfq_note`: scrubIdentity(raw, full_name) is passed to mailMatched. Input "Access is via the back gate of Villa 15, Al Barsha 2, near Mall of the Emirates; Makani 12345 67890." reaches the e-mail word for word, Makani included.
   - inquiry_lifecycle.ts:68 `add_missing_specs`: name-only scrub, then fn_inquiry_add_missing_specs e-mails the answers and writes them into spec. The answer "Al Barsha 2, villa 15" comes through unchanged.
   - messages_api/index.ts:140 `clarify_answer`: stripContact with the name and project only, then e-mailed to every matched supplier and listed in clarify_list. "The site is Villa 15, Al Barsha 2, near Mall of the Emirates." comes through unchanged.
   This branch makes the leak more likely, not less: suppliers now see only the emirate, so "where exactly is the site?" becomes the obvious question, and this thread is where the customer answers it. The Arabic route (holdForEnglish, then finishEnglish) e-mails the model's English with no gate after it.
   Fix: route all three texts (and the English text in finishEnglish) through supplierLine(text, buyer, requestSeeds(buyer, spec)) via buyerOf. When the gate withholds the text, keep it for the customer and send nothing to suppliers.
2. Address keys other than `location` are never reduced, and the new "The brief" table in the inquiry PDF now prints them. Production category_specs asks for the area under location_floor ("Which emirate/area, and what floor level"), property_location, emirate_location, location_area, emirate_building and property, and asks about access under `access`.
   _shared/site_location.ts:33,112,125 handle ADDRESS_KEY='location' only. Run: splitSite({location_floor:'Al Barsha 2, 3rd floor'}) and then supplierBrief served "Al Barsha 2, 3rd floor" unchanged. The same result for property_location, emirate_location and access, and for "JLT Cluster D, Dubai" and "apartment, Dubai Marina, 12th floor".
   This is the deterministic interview path (buildBrief, the expected path under the model hold). It stores the customer's answer under that key and no site_location.
   Fix: make ADDRESS_KEY a list (location, location_floor, property_location, emirate_location, location_area, emirate_building, property, or a key regex /location|address|emirate_/) in splitSite and supplierSpec, and add those keys to the planted test.
3. A live portal door outside the gate: supplier_portal `workspaces` (dashboard.ts:89, market.ts:166) runs fn_supplier_workspaces, whose project.title is shown in CollaborationWorkspace.tsx:195 to every matched supplier before a reveal. The title is fn_supplier_safe_text(summary_masked), the DB mask only.
   PROVED on production: fn_supplier_safe_text(mask_project_identity(mask_contacts('Kitchen fit-out in Al Nahda, Sharjah; villa 15 Al Barsha 2 near Mall of the Emirates; existing quote AED 32,816.70'))) returns the input unchanged. These are the three live L1 summaries the author says are "fixed on read"; that is true of supplier_api only.
   Its revealed test is `exists transactions` with no revealed_at (L6 again, in SQL).
   Fix: in supplier_portal, replace project.title for an unrevealed supplier with the supplier_api gate (supplierField(forSource(summary)) with requestSeeds), or with the category and emirate only. fn_supplier_opportunities (requirement = raw_input_masked, the whole chat) has the same flaw but is latent: it lists only status 'open', which no inquiry has.
4. A revealed supplier receives the OLD supplier's identity. supplier_api/actions/inbox.ts:208 serves `revealed ? i.spec` whole, so spec.old_supplier_terms (e.g. "ZZ DEMO Falcon Trading LLC", "FT/Q/2026/0412") goes to the revealed supplier. The summary is served raw too, without forSource, so a price the customer wrote about the old offer reaches him. The reveal releases the customer, not the competitor (rulings 1683/1686).
   Fix: for a revealed supplier, drop old_supplier_terms (only it) and apply forSource to the summary.
5. Gate regression: scripts/checks/nothing_a_supplier_reads_can_be_arabic.test.mjs is 151/0 on main and 150/4 on this branch. The four failures:
   - RfqParts.tsx:191 'الماركة / المواصفة' and core/Projects.tsx:65 'الموقع' are Arabic shown to suppliers (ruling 1008).
   - quotation_gate.ts and quotation_parties.ts contain Arabic regex terms that are not on the gated list.
   Fix: remove the Arabic UI strings from the supplier components and add the two regex files to nothing_a_supplier_reads_can_be_arabic.gated.json.
6. The quotation gate destroys quantities and specifications, so a supplier can no longer price the line (drawing_boq/quotation_gate.ts):
   a. Line 42 (the money shape with NOT_A_MEASURE backtracks). "Porcelain tiles 2,400.00 m2" becomes "Porcelain tiles.00 m2", "Cable 1,250.50 m" becomes "Cable.50 m", and "Paint 12,000.00 sqft" becomes "Paint sqft".
      Fix: `(?![\d.])` after the figure, and sqft/ft2 in NOT_A_MEASURE.
   b. REF at line 48 removes standards and pipe classes. "DN-100-PN16" goes, "EN-1504-2" goes, "ASTM-C-920" goes, and "SS-316-L handrail" becomes "Stainless handrail".
      Fix: apply REF only to tokens with a year, a labelled reference, or the document's own prefix. Never apply it to a token whose prefix is a standard or material (EN|BS|ASTM|DIN|ISO|SS|DN|PN|UL).
   c. Lines 93-99 take the first word of the firm's name as a party, and the old_supplier_terms then become seeds at every door (what_a_supplier_receives.ts:167). For "Marble Trading LLC", "Steel Engineering LLC", "Glass Contracting LLC" and "Granite Interiors", the words marble, steel, glass and granite are removed from every line ("Marble threshold, steel door frame" becomes "threshold, door frame"), and from the summary and spec at every door.
      Fix: skip a first word found in the trade or material lexicon (the pack glossary). Seed the full firm name and the reference only.
   d. customer_api/actions/documents.ts:98 makes the file name a party term. tiles.pdf removes "tiles" from every line, and kitchen.pdf removes "kitchen".
      Fix: use the file name as a term only when it carries a legal form or a reference shape.
   e. quotationProse, applied to every quotation summary at every door (TERMS_SENTENCE): "Supply and fix tiles to 2 bathrooms, total area 85 m2." becomes "" (the word "total"), and "Wall tiles; rates to include adhesive" becomes "Wall tiles".
      Fix: drop a sentence only when it also holds a money shape.
7. Site seeds erase common words (site_location.ts:96-97, noNum). The site "Unit 1204, Tower 2" seeds "unit" and "tower"; "Gate 3" seeds "gate"; "Springs 3" seeds "springs"; "Street 12", "Phase 2", "Cluster 4", "Hall 2" and "Room 5" behave the same. PROVED:
   - "Split AC █ 2.5 TR", "Cooling █ motor", "Outdoor █ stand", "█ valve DN100", "door closer █ and gas █".
   - "Replace 4 split AC units" is withheld whole. In edit_inquiry that means a permanent 422 `summary_names_you`. The form always re-sends the summary, so a budget-only edit is refused too, and the customer is never told which word the gate objected to.
   Fix: never add the bare noun after a number is stripped when it is a unit or building word (unit|tower|block|gate|street|road|phase|cluster|sector|zone|hall|room|store|springs|lakes|meadows…). Keep the "noun N" phrase only.

AFTER MERGE
- looksPriced: a drawing whose text reads "flow rate … amount" or carries a cost table is routed as a quotation (no pages, and the customer is told "a quotation from another supplier"). "95/-" prices, Arabic heads (سعر الوحدة/الإجمالي), prices in words, and scans or photos are missed by the code backstop and left to the model, so their pages still go to drawing_redact. Add /\d\s*\/-/, the Arabic heads and "U.Price + Total", and send a customer BOQ that has rates with its own wording.
- The old supplier survives in: a house brand built on its prefix ("FT-Seal"), a partial name ("FALCONLINE" becomes "LINE brand"), and its slogan. A second reader is needed for these.
- The CSV omits `specification`. edit_inquiry stores the redacted text over the customer's own summary ("Repaint villa in █"). Store it as written and let the doors gate it.
- edit_inquiry and create_inquiry accept any `emirate` string from the browser. Reduce it to the seven.
- quote_extract receives the raw summary (supplier_api/actions/quotes.ts:94).
- A quotation and a real drawing attached together: the drawing's pages are dropped (briefSource = quotation).
- Prompt growth: drawing_boq SYS +~1.9k characters (KIND_RULES, about +57%); intake rule 17, the site_location shape and the file note +~1.8k characters. Measure against ruling 1619. Sufficiency is judged generically by drawing_boq, not against category_specs; only the intake frames it by checklist. "Send it as it is" is a prompt instruction only. unknown_keys is honoured by code and nothing traps the customer, but Arabic phrasing is unverified (model run needed).
- Q7 holds: edits after a reveal are refused (fn_edit_inquiry v_paid). The edit notice is fixed text. Other suppliers' inbox and projects are keyed on their own transactions with revealed_at.

WHAT HOLDS (run)
- supplier_api inbox, inquiry_pdf, the inquiry_documents/review doors (via inbox), new_inquiry e-mail, notifyLosers and the WhatsApp parameters. The `location` key on all 10 author cases.
- The four PDFs (pdftotext + pdftoppm at 40 dpi): no page images (pdfimages 0), neutral properties, no price on the careless quotation, priceable. On the careless quotation "as per standard detail" is left over and the subtitle is blank.
- Grants: anon/authenticated have no SELECT on inquiries, the view, rfq_clarification or notifications. Realtime cannot deliver.

TESTS
- deno: supplier_api 256/0, customer_api 90/0, drawing_boq 96/0 (1 ignored), inquiry_intake 120/0, messages_api+send_whatsapp 33/0.
- `npx tsc --noEmit` exit 0.
- node: the new check plus the two edited ones, 37/0. The edited checks are not weakened: the regexes were renamed and one count went from 3 to 4.
- every_arabic_message_is_written_not_translated fails on main too (pre-existing). nothing_a_supplier_reads_can_be_arabic: regression (item 5).

MUTANTS (16)
- Caught 9:
  - M1a: customer-only keys not dropped.
  - M1b: inbox spec served through supplierField.
  - M2: e-mail back to the name-only scrub.
  - M3: looksPriced always false.
  - M4: gate keeps basis.
  - M5: create_inquiry trusts the browser's brief_source.
  - M6: no site seeds.
  - M8: inbox reveal without revealed_at.
  - M14: forSource is identity.
- Survived 7:
  - M7: the PDF prints site_location.
  - M9: edit_inquiry never refuses.
  - M10: notifyLosers sends the raw summary.
  - M11: old_supplier_terms not seeded.
  - M12: the analyze_drawing quotation route disabled.
  - M13: inbox quotation re-gate removed.
  - M15: every supplier gets the raw spec (supplier_api full suite 256/0).
  (survivors re-run on their full folder suites: M15/M13 supplier_api 256/0, M10/M12/M9 customer_api 90/0, M7 supplier_api+drawing_boq 352/0 — none caught)

## WORKFLOW W2 SALES 1
Independent review of origin/sales_engineer-a-paid-request-is-closed-and-everyone-on-it-is-told (3c73d110a) vs origin/main, 13 Nov 2026.

VERDICT: FIX (2 merge-blockers, then the rest).

1. supabase/functions/_shared/stated_price.ts:195 + line_specs/vat.ts:78-79. A quotation that says it is zero-rated or exempt can no longer be submitted. storedPrice now writes vat_treatment 'zero_rated'/'exempt' (I ran it: storedPrice(statedPrice({amount:12000,text:'This supply is zero-rated.'})) gives vat_treatment 'zero_rated'). Production's constraint quotes_vat_treatment_known only allows exclusive/inclusive/not_registered/not_stated/confirmed_on_portal (SELECTed live), so supplier_api/actions/quotes.ts:377 fails with 23514. Smallest fix: in section 8, drop and re-add the constraint with the two new values, and add a probe line that inserts a zero_rated quote.
2. Ruling 1008 (suppliers get English only). nothing_a_supplier_reads_can_be_arabic fails 3 tests on HEAD and passes 151/0 with main's copies of the same files. The Arabic: serverCopy.ts notice_quote_not_selected/notice_request_closed, review.ts:113-115 (the figAr question), sanitize.ts:57-58. The gate is red. Fix: drop the Arabic.
3. SQL:192 and 269-271. Writing status 'closed' at the payment, when no other quotation is live, ends the request everywhere isClosedRequest/CONCLUDED is read: messages_api clarify_ask; the customer's rfq_note; WhatsApp files from the customer (wa_inbound); resend_inbound supplier_docs (documents the revealed supplier e-mails are no longer matched to the request); supplier submit. fn_sales_engineer_request_outcomes skips 'closed', so "completed without award at 60 days" never runs and the outcome stays 'revealed' for good. 'closed' already meant a split parent whose parts all ended. v_other (257-261) leaves out a quotation still in the 24h quality hold (status 'draft'), so the close fires z31 -> fn_quote_holds_close_without_decision('request_ended'): a quotation still in that hold is dropped, the customer never sees it and the supplier is not told. reveal_guard.ts:164 records the earlier decision that a revealed or completed request is not closed. Smallest fix: keep status 'revealed', record the end in reveal_open_until/request_reveal_outcome, and make canReveal read that. At the least, count draft and quality-held quotes as live.
4. SQL:463-472. The duty closes the whole request when the EARLIEST open record's date passes. A second reveal paid on day 4 has its window, which the customer is shown in requestTracker as "until <later date>" (inquiries.reveal_open_until = greatest), cut off at the first reveal's deadline. Fix: close when inquiries.reveal_open_until <= now().
5. The probe cannot fail on 3 of the 5 mutations (rehearsed): m1 closes with a live quote: caught. m2 tells the chosen supplier: caught. m3 dedupe removed: PROBE OK. m4 duty closes a reopened request: PROBE OK. m5 wrapper replaces the original handler with '{}': PROBE OK. Add: D then tick, still 'reopened'. A asserts reveal_receipt and quote_accepted for ta. A second paid reveal on ia sends no second quote_not_selected.
6. Supplier portal QuotationsTab.tsx:141 and InquiriesTab.tsx:157,222 show aed(lang, q.quote_amount), and money.ts turns null into 0. A held quote now shows the supplier "AED 0" for his own quotation. Fix: ?? amount_as_stated (select it in quote_review_actions.ts:94).
7. SQL:366-380. A refund re-opens the request even when no live quotation is left, and also for a reveal with no request_reveal_outcome row (reveals before this merge). Status goes to 'revealed' with a date that nothing ever closes. Suppliers already told "closed, yours will not be revealed" are not told it re-opened. Fix: re-open only when an outcome row exists and a live quote remains.
8. reveal_followup: a list nobody reads. All three kinds are passive mirrors of existing duties (so the customer gets no second message; that holds). An escalation writes text and jsonb and reaches no one: no hand-over, no finding. Fix: raise a hand-over or finding on escalation, or drop the table and read customer_followup/supplier_response_watch.
9. The model decision (SQL:288-310, 419-449) adds nothing. Its facts are a count, a boolean and trade/emirate/rfq_no. keep_open is the code default and does nothing. close_now only takes the customer's option away (lost 3%) and sends a mail sooner. The cost claim holds (ai_cost_log 30d routine_employee_reasoning gpt-6-luna-pro avg AED 0.0076, n=1529). The answer is guarded: options only, a late answer, a second answer and a refunded request each change nothing. But the held question is not cancelled when the duty closes first, so it is still paid for. Remove it, or give it something to judge.
10. The close text (SQL:142) says "the customer went ahead with another supplier's quotation". That is false after a refund (the revealed supplier never answered) with no second reveal.

HOLDS (checked): every routine has its revoke and pinned search_path, with one signature each. RLS is on, with a deny policy and anon/auth revoked, on both tables. Trigger a20 is BEFORE UPDATE OF status, assigns NEW only (no recursion), and neither rfq_complete nor mask writes status. The handler runs at z20 after the row with fee_status 'paid' exists (reveal_sale.ts:46-51), so the chosen supplier is correctly excluded. File+probe: PROBE OK, rolled back (safe_replay always raises and fingerprints). W1 order: W1 neither redefines fn_sales_engineer_acts_on_handoff nor upserts the reveal.paid kind, and W1(+1150 file)+W2+probe also gave PROBE OK. If the original handler raises, the wrapper raises and the hand-over is marked failed, as before. reveal.paid is originator_closes=true, so the sender reads evidence.request. Hand-overs open in production: 0 (reveal.paid 40, refund.paid 31, all done). Rows section 8 would null in production: 0. A held quote is kept out of the customer's list and refused by canReveal, so no NULL fee reaches a customer. SQL readers filter >0 or use avg. app_fee goes to NULL (margin_rate(null)=0.03 × null). /1.05 is rounded to the fils. The customer never saw the gross of a held quote, so he sees no change of price. Suppliers' notices carry only the rfq_no/trade/emirate they already had, so there is nothing to triangulate. Demo: fn_seat_handoff files nothing for a demo payload, and fn_seat_clock_refusal blocks fixture->real. Webhook replay: quote_id is unique, the outcome row is keyed on the PK, and dedupe_key is per supplier per event. The notices are e-mail only (no WhatsApp cost).
Gaps check: default mode is identical to base (5 pass/12 fail). Rehearsal mode passes GAP 8/9/10. His explanation for the 2 HOLDS that fail there is TRUE: the trace shows reveal.paid 'pending' because of originator_closes, and delivery.result comes back only after a send outcome. One softening: revealPaidBranch absorbs the wrapper's routines whenever the wrapper exists, without checking that seat_handoff_kind points at it.
Runs: deno quote_extract 66/0, supplier_api 245/0, supplier_portal 51/0, _shared 2264/1 (catalogue_read tesseract, needs network, unrelated). tsc exit 0. a_paid_reveal_closes_the_request 6/0. every_report_and_handoff_comes_back 4/0 (proxy). payments_are_the_accountant 5/2 (one 502, and "production fn_seat_handoff_types() is not the repository's list": W1's unapplied file, not this branch). Arabic check 148/3.
Minor: a supplier's second VAT answer is ignored (first wins, and he cannot correct it). The /1.05 figure is our derivation and vat_amount is not stored, so say "derived" to the customer. "Unsubscribe" suppression does not stop the new types unless they are added to fn_opt_out_types. 39 deliveries run inside the Stripe insert transaction (latency on the payment path).

AFTER MERGE: apply with the constraint fix BEFORE deploying supplier_api. Rehearse W1 then W2 in the release (it passed). Watch the first real reveal: request_reveal_outcome row, unchosen notices, then the duty close. Decide whether the 1 pre-merge paid reveal needs an outcome row.

FOR THE FOUNDER, differently from the author:
a) Should a paid request ever stop a second reveal? Each one is 3%. reveal_guard deliberately allowed it. I would let the customer reveal for as long as the quotes are valid and end only the supplier notices.
b) Telling losers "the customer opened another supplier's quotation" at the payment is a loss notice that may be reversed the next day, and it invites chasing. I would tell them once, at the close or the hire.
c) Drop the model call. The founder pays for judgement, and this question has nothing to judge.

## ANONYMITY F1 TEXT 1
Independent review of origin/sales_engineer-nothing-below-the-emirate-and-no-name-crosses-in-text @1c8e63e15 (base 2cef71f27), 13 Nov 2026. Offline only; no production call, no model call. Drivers and outputs: scratchpad/rv/ (corpus.ts, over.ts, names.ts, leaks.ts, perf*.ts, dos.ts, prof.ts, mut.sh, probes/).

VERDICT: FIX. Leak closure is real (C door 11 -> 0 of 46; A 18 -> 2 of 31, and 0 of 31 on the tree merged with the sibling). But it ships a ReDoS that hangs a supplier-facing door, a 4x CPU cost that takes review_cpu_budget near or over its budget, and about 114 ordinary trade strings it now damages.

FIX (most harmful first)
1. ReDoS, identity_text.ts PHONE_WORDS_RE (DTOK `(?:\+|00)?[0-9٠-٩]{1,4}` with an empty-able DJOIN, `{2,24}`, then `(?![\w…])`). A run of 104 or more digits (a serial, or an OCR table with its spaces lost) never finishes. scrubIdentityText("Serial numbers: <104 digits> end") took more than 60 s and was killed. 100 digits takes 174 ms; main takes 9 ms on 108 digits. Every scrubber, every inbox read, clarify_ask and submit_quote runs this, so one customer can stall every matched supplier's inbox. Smallest fix: a digit token must end at a non-digit, `[0-9٠-٩]{1,4}(?![0-9٠-٩])`, or a required separator between digit tokens. Add a 200-digit row to the test.
2. CPU budget, supplier_api/review_cpu_budget.test.ts. CONFIRMED: inboxBoq takes 698-722 ms (main 45-68) and the whole path 1048-1084 ms (main 254-358) against a 1200 ms budget, so it fails on a slower machine (the sibling measured 1455 ms). Cause: identity_places.ts placeSpans builds `new RegExp` for about 700 gazetteer entries on every string and runs each over it. That costs 340 ms per 1200 BOQ cells; the whole scrubIdentityText costs 522 ms (main 15). The LANDMARK_EN check rebuilds all ENTRIES per candidate (50 KB of "near Xyz," = 524 ms). knownNameRe(fragments) is rebuilt per cell (38 ms per 1200). The cold first call is about 80-200 ms. A short field costs 0.7 ms against 0.009 on main. Fix: one combined case-insensitive alternation compiled at module load (or reset lastIndex, never `new RegExp`). Exit early when that prefilter, a premises word, a cue word or a digit-plus-place shape is absent. Precompile the landmark test. Cache knownNameRe per name.
3. Over-redaction, 114 of 411 legitimate sentences wrongly changed (421-sentence EN+AR corpus, measured against the base; 10 marked arguable or expected left aside):
   a. identity_text.ts LABEL_EN, the new verb labels plus personSpan's one-word rule. Damaged: "Manual Call Point", "Call Point, break glass", "Contact Adhesive", "Door Contact Switch", "Auxiliary Contact Block", "Magnetic Contact Sensor", "Contact Clamp", "Contact Block NO+NC", "Nurse Call Station", "Call Bell", "Call Button", "Phone Socket", "Reach Truck", "Reach Stacker", "WhatsApp Business" (15). A supplier's question "Should we include the Manual Call Point?" reaches the customer as "Manual [removed]". Fix: require a person-name shape (2 words, or a first-name list) after call/contact/reach/phone/whatsapp. Otherwise, at minimum, add these product nouns to NOT_A_NAME.
   b. identity_places.ts LANDMARK_EN accepts any 2 Title-Case words after near/next to/behind/close to/in front of. Damaged: "next to Main Distribution Board", "beside Pump Room door", "behind False Ceiling", "in front of Main Entrance", "close to Water Tank", "near Fire Exit Door", "opposite Lift Lobby", "close to Kitchen Sink", "next to Fire Hose Reel", "adjacent to Electrical Room", "near the Main Gate", "Behind Reception Desk", "In front of Swimming Pool deck" (13), all now [removed]. The rule also crosses a full stop: "near Jebel Ali. Christopher style chairs" lost "Christopher". Fix: a named landmark needs a LANDMARK_WORDS noun or a gazetteer hit. Drop the caps>=2 rule, or give it a room/equipment stop-list. Stop at [.;].
   c. BUILDING_EN and ROAD_EN treat "<Title word> Tower/Building/Road/Street" as a named place. Damaged: "Liebherr Tower Crane", "Potain tower crane", "BAC Tower", "Evapco Tower", "Telescopic Tower light", "Pre-Engineered Building", "Siemens Building Technologies/Automation", "Honeywell Building Solutions", "Modular Building", "Portable Building", "Reflective/Cat Eye/Solar Road Studs", "Concrete Road Barrier", "Asphalt Road works", "Gravel Road", "Wall Street finish", "3rd Street sign", "Street 2 lanes", "flat M10 washer" (22). Fix: add crane|studs|barrier|technologies|automation|solutions|fill|light to the after-noun exclusions. Add pre-engineered|modular|portable|telescopic|asphalt|gravel|reflective|concrete|solar to the generic sets. Add lanes and M-sizes to NOT_COUNT.
   d. Gazetteer words that are brands, colours or ordinary words, matched without a cue: Deira (blue tiles), Hatta stone, Masdar, Julphar, Akoya, Villanova, Al Barari, Rolla, Hoshi, Liwan, Shamal (wind), Arjan, Karama, International/Global village/City walk/Town square/Media city in lower case, ^MOE (Ministry of Education, matched with no cue), ^TECOM. The cue word "in" or ":" also fires on colours and ranges: "in Marina blue", "Colour: Marina blue", "Available in Jumeirah collection", "Colour: Liwa sand", "in Al Ain white" (24). Fix: mark these `~` (cue-only); make the multi-word "city/village/walk/square" names case-sensitive; and stop a cue word from turning a cue-only name into a place when a colour, range or collection noun follows it.
   e. DOC_NO's second alternative takes any XX-YYYY-NNN: "Drawing A-2026-101", "DWG-2025-0034", "ID-2026-118 door schedule", "AC-2024-12", "Approval ref DM-2024-0123" (5). Fix: anywhere, only codes whose prefix is the supplier's initials or Q/QTN/INV/PI. Leave the label form as it is.
   f. BANK acronyms. "EI" is a fire rating ("EI 60/90/120"), and nearby "payment/transfer/check" makes it a bank. "FAB shop drawings", "CBD board" and "DIB connector" go the same way next to a payment word (6). "ADCB approved valuer" is always removed. Fix: drop EI; require bank/iban/a/c within the line for any acronym.
   g. SIGNATURE takes the customer's own instruction: "Quotation must be signed and stamped", "Signed and stamped LPO required", "Company stamp required", "Authorised signature on the delivery note", and the Arabic "الختم والتوقيع مطلوب" (5). Fix: only when a name or a bracket follows, or as a line on its own.
   h. Arabic premises have no NOT_COUNT. "فيلا ٣ غرف نوم", "فيلا ٥ غرف", "شقة ٣ غرف", "منزل ٣ غرف", "فيلا ١٥ متر واجهة", "قطعة ٥٠ سم" (a piece, 50 cm), "قطعة ١٢ مم", "قطعة 2 × 3 متر", "شارع 7 متر عرض" all become [removed]. "برج الإنارة" (lighting tower) is removed; "سلسلة جميرا" becomes دبي (11). Fix: an Arabic NOT_COUNT (غرف|غرفة|متر|م|سم|مم|طابق|طوابق|×|x), and add الإنارة to BUILDING_AR's exclusions.
   i. "Delivery to Abu Dhabi, Al Ain and the Western Region" -> "Delivery to Abu Dhabi and the Abu Dhabi" (garbled). Fix: an emirate already named is not added a second time.
4. Name fragments (knownNameRe fragments: house-brand root, initials). Of 24 supplier names, 14 damage their own quotation. Electra -> "Electrical" lost; Concept -> "Concealed"; Precision; Thermo Tech -> "Thermal", "Thermostat"; Stainless Solutions -> "Stainless"; Construct -> "Construction"; Hydrotech -> "Hydrostatic"; Brightway -> "Brightness"; Ceramic World -> "Ceramic". Initials: Unique Power Systems -> "UPS"; Steel Tech -> "ST-37"; Dubai Cable -> "DC-12V". Customers: Christopher -> "Christmas", Richard -> "Richardson", Mohammed Ali -> "MA-01". Al Noor, Best Paint, Gulf Trading, Smart Home, Royal Marble, A B C and "Falcon grey RAL 7012" behave acceptably: only the name itself goes. Fix: drop the 5-letter-root rule, or require that the root word is NOT an English dictionary or trade word; demand at least 3 extra letters; and match it only when it is not a prefix of any ordinary word. Initials: keep the doc-number form only (initials+[-/]+digit+year).
5. Tests that bless a leak, or miss one. quote_generalise.corpus.json "hide" rows pin "Of fice 000, ZZ Business Centre, Dubai, UAE" (8 rows): the supplier's office number (OCR-split "Of fice") and its building cross. The flip from Al Quoz stopped at the area. Fix: pin "Dubai, UAE"; add Centre/Plaza/Complex/Mall to the building nouns and an OCR-split "Of fice/Sh op" form. The four MUST-KEEP -> REDUCED flips and the two keep->hide rows are each required by ruling 1683 (all name a place below the emirate). Nothing else was weakened: the check regex went from {0,400} to {0,900} and accepts `seeded`, which is still one gate.
6. Untested changes (mutants that survive): stripSupplierQuestion has no test at all (M4: index.ts back to stripContact, 93/93 pass). The CSV mask (M5: compareTable given [] again, all pass), because the careless-model test feeds the CSV text that was already anonymised. Known-name-first in maskContacts (M8 survives). Add one clarify_ask test with "Falcolux / Daikin FTKF50" and one CSV test with "balance on completion - Desert Brush team" in raw payment_terms.
7. Leaks still open (shared list, 18 of 60 new probes): tatweel "البرشـاء ٢"; "الجميرا" (ال form missing); Arabic-decimal coordinates "٢٥٫١١٢٣، ٥٥٫٢٠٠١"; "Barsha2"; "Jumeirah 3", "Al Safa 2" (a cue-only name with a sector number should count without a cue); "Springs 5", "Meadows 2" (case-sensitive "^The …" only); "JVC, District 12" / "District 12"; "Uptown Mirdif" -> "Uptown Dubai"; "Sector E-23"; "Burjuman Centre"; "Land no. 373-4512"; "… Boulevard"; "Frond K"; "V-15"; "villa fifteen"; "Cedre Villas". Fix: strip tatweel and normalise ال before the Arabic entries; a digit after a cue-only name is the cue; District/Sector/Frond/Land + number as premises; add Boulevard to the roads; ٫ and Arabic-Indic digits in COORDS.

AFTER MERGE (sibling aeb239218; 44fb1e069 too): both merge clean, with no conflicts. On the merged tree every new test of both branches passes (supplier_english 10, quotation 7, nothing_below_the_emirate 22, portal titles 1, identity_places 6, identity_text 11, careless model 4, customer corpus 2, review_cpu_budget 2, though it is close to its budget). A's 31 probes through supplierLine/supplierField/stripContact, with and without a stored site: 0 leaks of 62. The author's claim is proved. The PDF line does NOT read "in Dubai" when the site is stored: the site seeds are painted before the reducer, so "at Al Barsha 2" becomes "Renovation of two bathrooms" (aeb239218; it was "at █" at 44fb1e069). Without a stored site it reads "at Dubai". Acceptable, but "in/at Dubai" would be the better outcome: paint the seeds that are emirate-reducible after the reducer.

FOR THE FOUNDER: "CIF Jebel Ali", "FOB Jebel Ali port", "ex Jebel Ali" and "Ex works JAFZA" now read "CIF Dubai" etc. Is a port or free-zone delivery term "below the emirate"? Also, stripSupplierQuestion turns "Grohe or Hansgrohe?" into "premium German brand or premium German brand?", and "UPS" into "branded".

RUNS: deno _shared 2272 passed 1 failed (the tesseract wasm read permission, the same failure on the base: 2263/1), supplier_api 246/0, quote_extract 70/0, messages_api 3/0, customer_api 90/0. Check a_supplier_sees_only_its_own_match 30/30. Mutants (93 targeted tests): caught M1 reducer-returns-input (11 fail), M2 cue rule dropped (3), M3 FIRM_EN left context reverted (2), M6 unit not anonymised (1), M7 phone words off (4), M9 landmark off (2), M10 other-script off (2). Survived: M4 stripSupplierQuestion not called, M5 CSV mask lost, M8 known name not first in maskContacts.

## WORKFLOW W1 MONEY 1
Independent review of origin/accountant-a-payment-is-known-booked-and-timed-from-the-moment-it-is-paid @ a6beed86b (base origin/main), 13 Nov 2026. Worktree /tmp/claude-0/review-w1 (removed). Production read only (SELECT + rolled-back rehearsals through scripts/ci/rehearse_sql.mjs, whose safe_replay always raises and proves nothing committed). No deploy, apply, merge, push, Stripe or paid model call.

VERDICT: FIX. The books balance and the VAT handling is right, but the element/healed payment path never reconciles, the Invoicing fee is booked twice, and a live payment can be treated as a demo and vanish from the books.

### What was verified
- Live vs mirror: all 9 routines he replaces (7 named + trg_reveal_window, trg_reveal_receipt) are byte-identical in production and in the mirror (diff 0 lines). No live fix is reverted.
- Rehearsals (rolled back): main+probe PROBE OK; 1150+probe PROBE OK; 1150->main, main->1150, sibling->main, main->sibling, each with each probe: PROBE OK.
- Mutants against the main probe: M1 journal 1 fils off: CAUGHT (the reconcile handoff fails, no journal). M2 demo posts a real journal: CAUGHT. M3 a second invoice number on replay: SURVIVES. M4 window from insert time (INSERT path): SURVIVES (the probe only moves paid_at on UPDATE; it never inserts a sale that already carries paid_at, the element/heal path). M5 sweep resolves exceptions: CAUGHT.
- deno: reveal_invoice 15/0, stripe_webhook 11/0 (incl. drill_webhook_replay), accountant 53/0, _shared money tests (charge_facts, reveal_reconcile, reveal_args, reveal_sale, reveal_fee*, payment_handoffs) 46/0. The full _shared run stopped on an unrelated tesseract wasm read permission.
- node, one file at a time, NODE_USE_ENV_PROXY=1: every_report_and_handoff_comes_back 4/0, handoff_kinds_are_data 2/0, the_reveal_invoice_handoff_states_its_note 2/0, the_reveal_invoice_is_the_accountants 1/0, every_pdf_we_issue_is_on_our_template 4/0, reveal_work_is_the_sales_engineers 2/0, a_money_column_is_never_negative 17/0, a_paid_reveal_with_no_sale 7/0, canonical_routine_manifest_applies_at_merge 8/0. payments_are_the_accountant 5/2: the first failure is the production kind list missing the 6 new kinds (expected while unapplied); the second was HTTP 502 from the production API (not judged). canonical_routines.test 0/1 ("reported nothing" in this environment; not compared on main). src/ unchanged, so tsc was not run.
- Merge with origin/sales_engineer-a-paid-request-is-closed-and-everyone-on-it-is-told: one add/add conflict in scripts/it/a_paid_reveal_is_known_to_every_seat_with_a_step.gaps.mjs, and it is mechanical: take the sibling's file and add 'paid_at',paid_at to traceSql. The SQL applies in either order. Gaps on a merged rolled-back rehearsal (rehearse_a_paid_reveal_trace.mjs with W1's SQL): 9 pass / 8 fail. GAP 1, 5, 6, 8, 9, 10 pass. GAP 2, 3, 4, 7 fail because the rehearsal carries no Stripe figures, so the reconcile waits by design (his probe proves them by injecting figures). GAP 11 and GAP 12 fail on the code. Two HOLDS fail on the sibling's own fixture as well: a rehearsal artefact.

### Books, by hand (gl_settings: Invoicing 0.5% + 5% VAT; ceil to the fils)
| case | 1050 Dr | 6100 Dr | 4000 Cr | 2300 Cr | 6110 Dr / 2200 Cr | balanced |
|---|---|---|---|---|---|---|
| domestic, fee 777.60, card fee 34.48 | 743.12 | 34.48 | 777.60 | - | 4.09 | 781.69 = 781.69 |
| international, fee 777.60, card fee 32.90 (3.9%+1 + VAT) | 744.70 | 32.90 | 777.60 | - | 4.09 | yes |
| fee 1.01 (Stripe's AED 2 minimum refuses the charge; if forced, card fee 108 > gross 101 gives net -0.07, and fn_gl_post / the money checks refuse it) | -0.07 | 1.08 | 1.01 | - | 0.01 | refused, and the hourly sweep aborts on it (item 8) |
| overcharge 38.77 (gross 816.37) | 781.89 | 34.48 | 777.60 | 38.77 | 4.29 | 820.66 = 820.66 |
| zero fee | not posted: fn_reveal_fee_journal returns ready=false; after 1 h the check becomes a 'facts_unreadable' exception to the CEO for a free reveal | | | | | |

No VAT line. Revenue = the fee exactly (least(fee, gross)). The card fee comes only from the balance transaction, and nothing is posted until it is known (no estimate, so there is no true-up and no double estimate). Posted lines are immutable (trg_gl_lines_immutable / trg_gl_journal_immutable): no path updates or deletes a posted line, and the 1150 reclass is 27 new journals.

### FIX, most harmful first
1. supabase/functions/stripe_webhook/index.ts:142 and supabase/functions/accountant/actions/reconcile.ts:78 (with _shared/reveal_args.ts:29 and _shared/reveal_reconcile.ts:262 now writing paid_at at insert). The charge facts are written with `.is('paid_at', null)`. Every element-flow sale recorded by the webhook, and every sale healed by the hourly sweep, already has paid_at, so stripe_amount_received_fils and stripe_bt_* are never written. fn_accountant_reconciles_reveal then waits, and one hour later it files a 'facts_unreadable' exception to the model and the CEO for a correct payment. Smallest fix: gate the facts update on `.is('stripe_amount_received_fils', null)` and write paid_at in a separate update `.is('paid_at', null)`.
2. SQL :298/:311-315 (fn_reveal_fee_journal). The live fn_accountant_book_stripe_fees (called by fn_accountant_duties) already books every 'stripe_fee'/'tax' balance transaction, which includes the Invoicing fee and its VAT, as Dr 6100 / Cr 1050 when Stripe bills it. The new per-sale accrual, Dr 6110 / Cr 2200, books the same cost a second time. Nothing ever debits 2200, so it grows forever (the "trued up monthly" in the gl_accounts description is not built). Fix: drop the accrual, or make fn_accountant_book_stripe_fees clear 2200 (Dr 2200 / Cr 1050) up to the accrued balance instead of debiting 6100.
3. SQL :211-216 fn_reveal_is_demo = fn_transaction_is_demo (customer.is_demo OR supplier lead.is_demo OR inquiry provenance qd_run). Stripe's live/test key is chosen by the payer's auth e-mail (stripe_checkout isDemoEmail), and livemode is never stored. A LIVE payment by a real customer for a quote from a demo-flagged supplier, or on an inquiry carrying qd_run, gets: no journal, no reveal.paid, no reconcile, no sale.made, no founder-brief line. :852 then deletes its check after 14 days and :850 purges its shadow, so the evidence is gone too. Measured today: 0 such quotes, but nothing prevents one. Fix: store transactions.livemode (the webhook's sigMode / PaymentIntent.livemode); fn_reveal_is_demo returns false when livemode; a live payment touching a demo identity is a 'live_payment_on_demo_identity' exception; never purge a non-test check.
4. Missing Stripe figures are never fetched again. recordStripeFee runs once, and the heal sweep calls recordFee only for sales it creates. The SQL sweep (:833) re-reads only the database, so the header claim "facts still missing are re-read" (:51) is false. Because fn_gl_sync_business section 1 no longer posts with an estimated fee, one Stripe read failure means the sale is never booked and becomes a CEO exception. Fix: the accountant runtime's hourly reconcile reads the PaymentIntent for every check in waiting_for_facts or facts_unreadable and writes the facts through the same write-once update.
5. A second exception on the same payment reaches nobody. fn_seat_handoff deduplicates 'payment.exception:<tx>' against any handoff that has not failed, and fn_reason_hold deduplicates 'payment_exception:<tx>' against any question already answered. So a dispute that reopens the check (:870) and the sweep's re-escalation after the CEO's 'investigate' (:670 nulls ceo_handoff_id) both get back the OLD closed ids. 'investigate' is a dead end: nobody gathers anything, and the item stays open for good. The CEO's option 'refund_difference' (:642) says "the accountant executes it and the sales engineer tells the customer". Nothing does either, so 2300 keeps the 38.77, the customer is never told, and the check never resolves. Fix: suffix the dedupe keys with an opening counter; reword the option to say what really happens; and turn an approved difference into fn_refund_request (partial) or a ceo_report to the founder.
6. Double posting under concurrency. There is no unique index on gl_journal(source, source_ref) for reveal_fee, refund_paid or dispute_*: gl_journal_one_live_entry_per_bank_or_fee_line covers only the bank and stripe_fee sources. fn_gl_sync_business :916 calls fn_gl_post_reveal_fee without the check-row lock that the reconcile holds, so a webhook reconcile and the cost tick can both pass the existence check at :327. Fix: add 'reveal_fee', 'refund_paid', 'dispute_withdrawn', 'dispute_won' to that partial unique index, or take pg_advisory_xact_lock(hashtext('reveal_fee:'||p_tx)) in fn_gl_post_reveal_fee.
7. :260 Invoice numbers are burned by rehearsals. Under qd.probe_files_demo_handoff='on', fn_reveal_is_demo returns false, so every rolled-back probe (this probe at apply-on-merge and in PR rehearsals, the journey proofs) calls nextval. nextval is never rolled back, which contradicts the header at :251 ("no gap a rehearsal made"). reveal_invoices.invoice_no also has no unique constraint. Fix: number with fn_transaction_is_demo (no GUC bypass) and add a unique index on reveal_invoices(invoice_no). The sequence is not gapless; for a business not registered for VAT that is acceptable, but do not claim it.
8. :828-855 The sweep has no per-row exception handling. One transaction whose reconcile raises (for example fn_gl_post refusing a line) aborts the whole hourly sweep: no escalations, no purge. Wrap each row in begin/exception and raise an it_engineer finding.
9. GAP 11 (the receipt carries no date). reveal.paid carries refund_window_sentence_en/ar (:783-796), but fn_sales_engineer_acts_on_handoff (unchanged) and the sibling's wrapper never print it, so the customer's receipt carries no date. In the checkout flow paid_at is null at insert, so the payload's date counts from revealed_at, and trg_reveal_window then moves refund_deadline when paid_at lands: the payload is stale. The deadline also keeps the payment's time of day while the customer is told only a date. Fix (sibling seat): print the sentence from transactions.refund_deadline at send time; set the deadline to 23:59:59 Asia/Dubai of the 5th working day, or print the time.
10. "fn_reveal_refund_window_ends is the one source" (:28) is not true. fn_refund_state counts chase and notify from revealed_at. fn_refund_nonresponse_eligibility counts Fri+Sat as the weekend and ignores public_holidays (pre-existing and wrong since 2022). messages_api/mailbox.ts:55 and supplier_api/actions/inbox.ts:258 hard-code fn_add_working_days(revealed_at, 5). The sibling's fn_sales_engineer_closes_on_reveal hard-codes 5. Since 0 windows are open in production, nothing moves today.
11. reveal.reconcile stays 'waiting' for good once the verdict is an exception: :370 returns early, and no step closes reconcile_handoff_id after the CEO decides. It will show as an overdue handoff. Fix: fn_reason_apply_ceo__payment_exception completes it.
12. Smaller. fn_originator_checks_delivery :1412 closes a notice as 'already_on_<channel>' when the twin is only queued, suppressed, held or skipped, so a notice that arrives on neither channel is never escalated; treat only sent/delivered as carried. fn_accountant_files_reveal_invoice :1177 tells the sales engineer "Our invoice ... is attached to the notice", which is untrue (invoice_ready has no attachment). The probe's founder-brief assertion is vacuous: 'Sales today' also matches "Sales today: none.". Add mutant-killing assertions for M3 and M4, and assert that a demo payment is absent from the founder brief and the five numbers.

### After merge
- A dispute's fee is not booked (it comes as part of the dispute adjustment, not as 'stripe_fee'), so 1050 will not tie to Stripe's balance. A refunded charge that is later disputed books Dr 6900 twice.
- 1b books every refund as a full refund (total_charged). If the CEO-approved overcharge refund is ever executed, the refund of the difference will be booked as the whole charge. Read refunds.amount_fils.
- trg_reveal_window: clamp paid_at to least(paid_at, now()) (it is not checked for the future).
- GAP 12. Exact change in the it_engineer's owner file scripts/sql/the_it_engineer_closes_every_loop_it_opens.sql (fn_seat_handoff), which needs W1's fn_demo_shadow_record applied first. Replace `... <> 'on' then return null; end if;` with:
    ... <> 'on' then
    perform public.fn_demo_shadow_record('handoff', p_type, p_from, p_to, coalesce(p_payload, '{}'::jsonb) || jsonb_build_object('subject_table', p_subject_table, 'subject_id', p_subject_id));
    return null; end if;
  W1 then removes its own `if v_demo then fn_demo_shadow_record(...) else fn_seat_handoff(...)` pairs (:797-811, :550-555, :590-597, :711-714), or every handoff is shadowed twice.

### 1150 file
- The treatment is right. A business that is not registered for VAT cannot reclaim input VAT, so the VAT is part of what the service cost (non-recoverable taxes are part of cost). The asset in 1150 (AED 284.41 measured) does not exist.
- The correction is 27 new journals: Dr expense / Cr 1150, and the reverse for JE-98. They are dated today in the open period, so the earlier months stay as filed and Nov carries the prior-period effect; that is immaterial.
- fn_expense_post_to_gl is redefined ONLY in the 1150 file. The main file's fn_gl_sync_business section 3 is unchanged from live (it already books the gross). Applying the main file first does NOT change future expenses before the founder confirms. No FIX here.

### For the founder, in plain words
- Revenue on payment, or deferred until the 5-day window passes? He books the 3% as earned when paid and books a later refund as an expense (6900). The stricter treatment books revenue net of expected refunds, or holds it in 2400 until the window closes, and books refunds against revenue. Choose one.
- Stripe's 0.5% Invoicing fee: book it when Stripe actually bills it (it already is), or estimate it on every sale? It cannot be both: today it would be counted twice.
- An overcharge (money above the 3%): it sits as owed to the customer. Who refunds it, how fast, and what is the customer told? Today nobody executes the refund and nobody tells the customer.
- A card dispute: Stripe's dispute fee is not booked. Book it, or accept that Stripe's balance will not tie to the books by that amount?
- 1150: move AED 284.41 of VAT into cost (the correct treatment for an unregistered business). The file waits for his yes.

## ANONYMITY F2 DOORS 2
Delta review of 44fb1e069..aeb239218 (3ea420c14, aeb239218), 13 Nov 2026. Worktrees: HEAD, origin/main, F1, and HEAD+F1 merged locally (merged clean, never pushed); all removed afterwards. The only production calls were SELECTs and rolled-back rehearsals.

VERDICT: FIX. The round-1 leaks are closed. Four new defects are below. F2 must land together with F1 or after it.

1. Access answers are over-redacted (_shared/site_location.ts:41-95). reducePlace keeps only words on the PLAIN allow-list, and `access` / `access_constraints` / `emirate_access` are address keys.
   - Measured on 40 realistic access answers: 31 of 40 lose information, all 5 Arabic among them.
   - Examples removed: "service lift available", "work only after 6 pm", "building management NOC required", "no parking for trucks", "goods lift max 1.5 tons", "crane access from street side", "height restriction 2.5m at entrance", "لا يوجد مصعد".
   - A supplier cannot price access he is never told about. The removed text also becomes site_location seeds ("service lift available" is now a seed).
   - Fix: take the access-type keys out of reducePlace. Gate them like free text (siteSeeds plus F1's identity_places), removing only a premises word with its number and named places.
2. The customer never sees KEPT_FROM_SUPPLIERS.
   - Clarifications.tsx:46,55 and MissingSpecs.tsx:53 show `notice` only when `held_for_english`.
   - So an answer kept from suppliers (`kept_from_suppliers:true`) reads to him as sent, and the supplier's question stays unanswered.
   - The wording itself is clear in English and Arabic: it says the site goes to the supplier whose quotation he opens. It fires only on a withheld text, so it would not nag, but it does not name the part that caused it (the edit refusal does).
   - Fix: also show the notice when `j.kept_from_suppliers` is set.
3. Edit regression (customer_api/lib/edit_summary.ts emirate branch, with InquiryCard.tsx:81). The form always sends `emirate: eEmirate || null`.
   - A request with no emirate now gets 400 `emirate_unknown` on every edit, summary-only edits included.
   - Run: editDecision({summary:'Kitchen refit', budget:null, emirate:null}) returns 400.
   - Fix: treat null or '' as "no change".
4. The workspace title before a reveal is "Plumbing sanitary work in Dubai", with no job number (supplier_portal/before_reveal.ts:13, and the SQL title). Two same-trade jobs in the same emirate cannot be told apart in his own list.
   - Fix: append the job number. Read rfq_no in the SQL project object and use supplier_api jobNo in portalTitle.
   - Also: the SQL label (initcap) reads "Plumbing Sanitary work" and the Deno label "Plumbing sanitary work"; align them.
   - The revealed supplier does get the full title back: the Deno layer passes the row through, and the SQL uses the summary when revealed_at is set.
5. Merge order. On F2 alone, forSuppliers sends "Access is via the back gate in Dubai, Al Barsha 2, near Mall of the Emirates" and "Al Barsha 2, █" when the place was never stated in a site key. On HEAD+F1 these come out as "…back gate of Dubai." and "Dubai". Merge F1 first or together; do not deploy F2 alone.

ROUND-1 ITEMS (re-run)
- Items 1, 2, 3, 4, 6 and 7 are closed:
  - Address keys reduce to "Dubai, 3rd floor".
  - Seeds keep their number: AC unit, cooling tower, units, springs and gate valve all survive.
  - Quantities ("2,400.00 m2", "12,000.00 sqft") and DN-100-PN16, EN-1504-2, ASTM-C-920 and SS-316-L survive; material firm names and file names are no longer terms.
  - "total area 85 m2" survives. Money still goes ("AED 32,000", "95/-", rate and amount rows).
  - Leftover over-removal: "Model HD-2020-W" becomes "Model", because a year-like number reads as a reference.
- Item 5: nothing_a_supplier_reads_can_be_arabic passes 155/0.
- Mutants:
  - My 7 survivors are all caught now. M9 and M12 were rewritten so they compile.
  - 7 new mutants: N3 (finishEnglish ungated), N4 (workspaces raw) and N6 (revealed keeps old terms) are caught by behaviour tests. N1, N2 and N5 (clarify_answer, rfq_note and add_missing_specs ungated) are caught only by the source-grep check.
  - N7 (revealedBy without revealed_at) survives.

ITEM 3 SQL
- `rehearse_sql.mjs` with file and probe: PROBE OK, rolled back.
- Probe mutant 1 (title = summary): PROBE FAILED on two live workspaces. Mutant 2 (file names kept): the probe still passes, because no unrevealed matched inquiry has a document; that branch of the probe can never fail on today's data.
- Checklist: one signature each (bigint); revoke from public, anon and authenticated; search_path pinned; CREATE OR REPLACE; pending notes present. Production: anon and authenticated cannot execute fn_supplier_workspaces / opportunities / quote_recommend / safe_text / product_match.

DOOR SPOT-CHECK (SELECT plus code)
- Not reachable, confirmed: every view that reads inquiries; inquiries, rfq_clarification, notifications, messages, transactions, leads and customers for authenticated. Realtime publishes inquiries, transactions, leads and customers, but has no grant to deliver through. drawing-files and quote-files are private. No push sender exists. WhatsApp templates carry no summary. product_match strips `to_reason`.
- His claim "none executable by anon/authenticated" is wrong in letter only: fn_marketplace_analytics, fn_ops_metrics and fn_strategy_metrics are executable by anon (security invoker, aggregates, no inquiry text). fn_customer_document_refs is executable by authenticated (the customer's own documents, used by the `documents` RLS policy). None of these is a supplier door.
- No unlisted door found.

AFTER MERGE
- pricedKind misses integer rates ("Rate Amount … 85 10200"), an Arabic quotation and prices in words. These fall to the model, and their pages are pictured.
- (f) The customer's own budget rates are deleted from the reading. Only the original file keeps them, so neither the customer view nor the sales engineer has them as data.
- A kept rfq_note shows suppliers an empty note card (answer null, answered_at set).
- add_missing_specs writes spec.site_location by read-modify-write, which can race.

TESTS
- On HEAD: deno supplier_api 266/0, customer_api 90/0, drawing_boq 98/0, supplier_portal 52/0, messages_api 3/0, inquiry_intake 120/0. tsc 0. The new production check passes 2/0.
- On HEAD+F1: supplier_api 268/0, customer_api 90/0, drawing_boq 98/0, inquiry_intake 120/0, messages_api 3/0, supplier_portal 52/0, quote_extract 70/0, send_whatsapp 30/0. _shared: 2273 passed, 1 failed (catalogue_read).
- catalogue_read (tesseract) fails on origin/main too: the test needs to read the tesseract wasm in the Deno cache, which `--allow-read=.` does not allow. It is an environment failure, not a code one.
- review_cpu_budget passes on all four trees when the machine is idle. Three runs each: main ~270 ms, F2 ~265, F1 ~975, merge ~1000, against a 1200 ms budget. The cost is F1's, and the test fails under load.
- PDFs (6 in pdfs_after, read as text and as images): no page image anywhere, no price, no old supplier, no area. The address PDF keeps "Dubai, 12th floor" and "service lift, loading bay at the back". The quotation+drawing PDF lists Job_160501_drawing_p01.jpg. All can be priced.

## WORKFLOW W2 SALES 2
Delta review of 530152b47 (follows 3c73d110a). All ten items from SALES 1 are fixed or answered. The new design (A status stays 'revealed', B reveal period, C no model) is sound.
VERDICT: FIX. Three small items before merge (1-3), three that can follow (4-6).
1. The probe cannot catch two of the four new-design mutants (rehearsed). n1 (the 30-day cap removed): PROBE OK. n4 (a refund re-opens a request with no live quote: `if ... live_quotes_left = 0` -> `if false`): PROBE OK. It catches n2 (a quality-hold draft not counted as live) and n3 (a05 lets a new supplier quote). Of the old mutants it catches m1, m2, m3b, m4, m5a (receipt dropped) and m5b (request step dropped). m3 (his dedupe removed) passes, as he says: the delivery layer's own key still blocks the duplicate. Fix: add a case whose quotes expire later than first+30d and assert reveal_open_until = first+30d. Add a refund case with an outcome row and no live quote, and assert it is not re-opened.
2. SQL:149-154, 176-179. The "remains available until D" notice is sent with the loose predicate: every quote not 'withdrawn' (plus quality-hold drafts). Suppliers whose quote is 'expired', 'rejected' or past its expires_at are told it "remains available to the customer until D", which is false. D is also never re-sent: z33 (a withdrawal or a moved expiry) and a second reveal (records_reveal:256) both move inquiries.reveal_open_until, but the first notice keeps the old date. Smallest fix: use the live predicate (lines 104-108) for 'reveal_open', and drop the date ("while it is valid") or re-tell once when it moves.
3. SQL:519-523 and 571-575. The request steps' exceptions are swallowed into evidence.request.error and nothing else. No seat is told: no finding, no company_event. The hand-over still closes (reveal.paid waits for the accountant because originator_closes=true, with evidence.request; refund.paid completes with it). Smallest fix: call fn_it_engineer_finding_upsert('reveal_request_step:'||p_id, ...) in both handlers.
4. SQL:586 (refund.paid). The customer is told "You are welcome to post the request again; we will introduce you to another supplier" even when fn_sales_engineer_reopens_after_refund has just re-opened this request, with quotations he can still reveal until D. Fix: when v_request->>'reopened' is true, say that instead. The re-open also runs BEFORE the refund message, not "after the messages" as his note says. Harmless.
5. supplier_api/actions/quotes.ts:244-251 then 425. If the payment lands between the pre-check and the insert, a05 raises P0001 and failed() answers the generic 500. Fix: map 'REQUEST_REVEALED' to the 409 inquiry_revealed sentence.
6. review.ts: the kept Arabic is main's old sentence, which no longer translates the new English question. It is never shown (SupplierPortal.tsx:43 lang = 'en'; e-mails lang 'en'), but QuoteReviewChat.tsx:106 would render body_ar if lang were ever 'ar'. Low.

VERIFIED BY RUNNING
- File+probe: PROBE OK, rolled back.
- Merged with W1 at its current head a6beed86b (1150 file, reconcile file, then his): W2 probe PROBE OK, W1 probe PROBE OK. W1 still neither redefines fn_sales_engineer_acts_on_handoff nor touches the reveal.paid row; it supplies refund_window_sentence_en/_ar.
- Handler vs production's live pg_get_functiondef (diffed now). Exactly four changes plus a revoke:
  - v_request declared;
  - the EN and AR refund-window sentences from the payload, coalesced to '' when absent;
  - records_reveal in begin/exception after the two messages, returned as 'request';
  - reopens_after_refund in begin/exception, returned as 'request'.
  Nothing else differs.
- Apply discipline: all 10 routines have a revoke and search_path 'public','pg_temp'. request_reveal_outcome has RLS on, a deny policy and anon/auth revoked. The re-added constraint validates the whole quotes table (a brief ACCESS EXCLUSIVE).
- Triggers: a05 BEFORE INSERT sorts after a01_quote_demo_and_real_never_pair and before the mask, quality and trg_quote_expiry_b triggers. z33 is AFTER UPDATE OF status, expires_at and writes only inquiries, so it cannot recurse; it fires after z31.
- Edges:
  - Other quotes expiring in 2 h: the period ends then, canReveal refuses, and the duty sends "ended" within the hour.
  - A revision with a new expiry: z33 extends the period, capped at 30 days from the first reveal (re-anchored at a refund re-open).
  - A second reveal on day 20: the reveal_open key is per request, so nobody is told again (m3b is caught).
  - a05 covers the only TS insert path (quotes.ts:425; production has no SQL inserts into quotes). Split parts are their own requests. A supplier whose earlier quote was withdrawn may quote again (his row exists). A supplier with a saved draft row may submit it. One who only typed and never saved gets the inquiry_revealed sentence.
- quote_amount NULL:
  - TS readers spot-checked: stripe_checkout:88 refuses (canReveal comes first), quote_compare orders nulls last, inbox.ts:85 uses ||Infinity, InquiryCard never sees held quotes, quotedAmount shows "as stated". inbox.ts:41 now selects amount_as_stated.
  - Production SQL readers: 21 functions and 2 views. I read the 8 that do arithmetic or ordering; all are NULL-safe (>0 filters, nulls last, concat drops NULL). fn_supplier_apply_change prints "currently AED " || NULL, which drops that entry (cosmetic).
- Local runs:
  - deno: quote_extract 66/0, supplier_api 245/0, supplier_portal 51/0, _shared 2264/1 (the same unrelated tesseract test).
  - tsc: exit 0.
  - Arabic check 151/0; a_paid_reveal_ends_its_reveal_period 9/0; request tracker 11/0.
  - Gaps check: default 5/12, same as base. Rehearsal passes GAP 8/9/10 and now follows only routines the branch calls.
- payments_are_the_accountant (proxy): 5/2. These failures are not this branch's:
  - "production: the live conversations and the triggers that start them": production has two handoff kinds the repo list lacks, support.promise_due customer_support->customer_support and ->sales_engineer. This is drift already on main; payment_handoffs.ts is untouched here.
  - "production: the whole refund ladder on ZZ DEMO fixtures, rolled back": "fetch failed" at 232 s, a network drop.

AFTER MERGE: apply W1, then W2 (rehearsed in that order), BEFORE deploying supplier_api. Watch the first real reveal: the outcome row, D on the request, the notices, then the duty's end. Add support.promise_due to payment_handoffs.ts (separate).

FOR THE FOUNDER:
a) The Supplier Agreement says "A quotation is valid for 30 days from submission". trg_quote_expiry defaults to 14 days, and this design ends the customer's option on that date. Should the default be 30 days?
b) No new quotations after the first reveal: a customer who wants more must post again, and the tracker does not tell him so. Should he be offered "ask for more quotes"?
c) Suppliers are given a date ("until D") the platform may later move. I would not promise a date in these notices.

## ANONYMITY F3 DRAWINGS 1
Independent review of origin/sales_engineer-a-drawing-reaches-a-supplier-with-no-owner-no-area-no-map @04656058f (5 commits). 13 Nov 2026. Offline only; worktree removed.
**VERDICT: FIX.** I planted 19 identity cases: 10 PUBLISHED WITH IDENTITY, 5 CLEAN, 4 HELD. Over-redaction: the CAD file keeps 58 of 83 quoting strings (main kept 83 of 83), and one sheet had its pool geometry cut out.
Generators and drivers are in scratchpad/review_f3/ (make_attacks.py, make_v15.py, make_quoting.py, cad_attack.ts, run_vec.ts, run_quoting.ts, grep_pdf.py, filters_attack.ts). They write to pdf/ and q/. The PNG rasters stand in for pdf.js (poppler).
**Runs**
- Deno suites he names plus wa_inbound, drawing_redact and customer_api: 443/0.
- Three-branch merge (this branch + text be6847b8b + supplier 2c3a8946a): no conflicts, 735/0.
- Gate step redact-page: 6/6.
- scripts/checks drawing set: 37 pass. The 3 failures are the production halves (401 / invalid token).
- scan-redact (19 min): not run, because the branch is not merge-worthy.
- The scanned-drawing check's greps were re-pointed at the new code, not dropped. The scan re-read was deliberately LOOSENED (scan_redact `wasContent`): a re-read line over first-pass content that fails only the vocabulary no longer holds. Named identity still holds.
- The WhatsApp test was not weakened.
### FIX (most harmful first; input → what breaks → smallest fix)
1. **pdf_text_positions.ts:181.** The tokenizer does not skip inline-image data (BI…ID…EI), and inline images are not reported as images.
   - v08: one inline image's bytes hold "(" and a later one's hold ")". Everything between them goes unread: "OWNER MR ZZ DEMO KAREEM, VILLA 15, AL BARSHA 2, TEL 050 123 4567" is PUBLISHED in the preview and in the released vector PDF, and pdftotext extracts it.
   - v07: an inline-image map "AL BARSHA 2 VILLA 15" reads imgs=0 and is published in both.
   - Fix: skip ID…EI and report it as an image, so L2 covers it.
2. **Text the reader cannot decode is seen by no rule and no model on a vector page.**
   - v12: a Type3 font with glyphs /g1../gN and no ToUnicode draws "AL BARSHA 2 VILLA 15"; published in both.
   - v01: text as filled outlines outside the strip ("AL BARSHA 2 / VILLA 15 / MR ZZ DEMO KAREEM"), as an AutoCAD SHX export writes it; published in both.
   - The DXF case: text exploded to LINEs is drawn on the preview and kept in the file.
   - Fix: run scan_redact's OCR floor over the preview raster outside the boxes, or hold a page that has a Type3/no-ToUnicode font or glyph-shaped path clusters outside the strip.
3. **src/components/me/pdfRaster.ts:49.** pdf.js renders annotations by default; pdfPages never reads /Annots.
   - v15: a FreeText markup "Owner Kareem asks for blue tiles - Villa 15 Al Barsha 2" is in the published preview.
   - Fix: `annotationMode: AnnotationMode.DISABLE`, or read /Contents and /AP into runs.
4. **pdf_text_positions.ts:94.** A stream ends at the first "endstream" (/Length is ignored).
   - v09: a note "(SEE SPEC endstream endobj)" hides the owner line that follows. The PREVIEW is published with it; the file is held by pdf_vector_redact.ts:236.
   - Fix: honour /Length, and put the same reader-vs-pdf-lib equality check on the preview path.
5. **drawing_location.ts:34-37.** The vector route is a deny-list outside the strip.
   - v03 published, in both outputs: "E 492 310.25 N 2 778 104.60", "25.1134 N, 55.2006 E", "V-15", "ARJAN", "AL WARQAA 1" (spelling variant), "DUBAILAND".
   - The CAD preview draws "V-15".
   - Fix: add E/N grid and lat/long shapes and V-\d+; take the text branch's gazetteer (see After merge).
6. **Tiling pattern.** v06: a /Pattern cell draws "ARJAN PLOT 6512 VILLA" over a rectangle outside the strip. pdfPages never reads pattern cells, so the preview publishes it readable, and the released file renders it too. Fix: read pattern and CharProc streams as forms.
7. **Strings readerStrings never sees.** pdf_vector_redact.ts:314 skips every Form, and PDF names are never read. Released in v05c/v06c:
   - an unused Form XObject in /Resources ("OWNER AL BARSHA SOUTH");
   - /BaseFont "ZZDemoCoralPools-ArjanVilla";
   - /PageLabels "AL BARSHA SOUTH - 1", which every viewer shows in its page box;
   - a /Dests key, a /StructTreeRoot /Alt, and an OCG name.
   - On this branch residualScan has no place rule, so all of these pass.
   - Fix: add PageLabels, Dests, StructTreeRoot and MarkInfo to DROP_DOC; drop XObjects that are never Do'd; rename the fonts.
8. **cad_file_redact.ts:92 and the subset proof cover TEXT_ENTS only.** cad_attack.ts released a DXF with:
   - "AL BARSHA" in an ACAD_TABLE cell (group 1), an LTYPE name and description, a DICTIONARY key and a LAYOUT name;
   - the firm "ZZDEMO-CORAL" in $DIMSTYLE, a STYLE name, an .shx file and a .ctb file;
   - the printer "\\ZZDEMO-…-PC".
   - Fix: every string group outside drawn text passes plainOk or is emptied or renamed; ACAD_TABLE joins TEXT_ENTS.
9. **anonymise.ts:380, OVER-REDACTION.** A "KEY PLAN" label with no picture or frame under it gets a fixed 25%×20% *region*.
   - v17 (label above the pool plan): the preview blacked out the pool. The vector PDF was RELEASED with the pool outline, the shallow/deep break and "SHALLOW END … FFL -1.20" cut (lines 45→26, runs 47→22). The verifier allows anything inside a region.
   - Fix: in that case cover the label only and hold; never cut paths in a fallback region.
10. **OVER-REDACTION, CAD file regression.** The DXF now obeys the allow-list. On my 3 quoting sheets (83 strings), main kept 83/83; the branch keeps 58/83:
    - pool 19/27: lost TOWER CRANE, PLOT BOUNDARY, STREET LIGHT, FLAT ROOF, BS EN 16582, N, REV B POOL DEPTH REVISED, "THE VILLA POOL SHALL BE TESTED…";
    - SLD 15/28: lost BS 7671, IEC 61439, LOAD (KW), TOTAL CONNECTED LOAD 45.6 KW, DEMAND FACTOR 0.8, EARTH PIT EP-1, DEWA METER, CIRCUIT, SPARE, LOAD SCHEDULE, SINGLE LINE DIAGRAM, …BS 7430, VOLTAGE DROP 2.1 %;
    - fit-out 24/28: lost FLAT ROOF, BUILDING CORE, PAINT JOTUN FENOMASTIC, "ALL WORKS IN THE VILLA…".
    - The CAD preview improved: pool 11→19, fit-out 22→24.
    - The PDF preview keeps 82/83 (lost PLOT BOUNDARY), and the vector PDF keeps 56/56 on two sheets.
    - PREMISES_NO also withholds "UNIT 1200 W", "TOWER B" and "BUILDING A".
    - "N" is lost by the lone-letter rule; it is fixable by allowing N/S/E/W beside a closed arrow. Scale numbers are lost because a run is cut whole; that is fixable by cutting the span, not the run.
    - Fix: add standards (BS|IEC|EN + number), schedule and electrical words; make these sheets a permanent fixture.
11. **pdf_vector_redact.ts:375 joins runs with "\n".** STREET_ADDRESS then spans "C40\nTOWER CRANE\nSTREET LIGHT", so the clean pool sheet's vector file is HELD (also on main). After the merge, placeSpans spans the same joins. Fix: scan run by run.
12. **pdf_filters.ts:120 and pdf_text.ts:32.**
    - /Predictor 2 /Columns 0 never advances `r` (infinite loop, killed at 30 s), so the request hangs.
    - Flate has no output cap: 310 KB became 300 MB (1.15 GB RSS). LZW output is an unbounded number[]. ASCII85 "uuuuu" decodes instead of failing.
    - Fix: if row<1, return null; cap every decoder (e.g. 64 MB → null → hold).
13. **wa_inbound/customer_files.ts:140.**
    - `held` is never read by the reply, so the customer is told "suppliers are shown it only with the customer's details removed" even when the drawing is held.
    - A scanned PDF from WhatsApp is never queued for the scan route.
    - A phone photo is silently never offered to suppliers.
    - Attaching is safe: only a recorded, complete, one-path run attaches. It attaches to the NEWEST open request.
14. **drawing_code_floor.ts:21 and drawing_redact/index.ts:482.** The floor reads one page alone, with seeds = body.seed_terms, which documents.ts never sends. A personal name outside the strip on sheet 2 is left to the model alone. Yes, documents.ts should pass seed_terms, and the floor should take the whole set.
### HOLDS / CLEAN
- **Clean:** white and 1% grey text; /Rotate 90; an incremental update; mirrored, 180°, 270° and skewed runs (one trailing glyph shows); a rotated road name and a plot number; Arabic owner, villa (Arabic-Indic digits) and area; a site photo; mailto and maps links; JavaScript, an attachment, the outline, XMP and /Info are dropped.
- **HELD:** an outlined title block; a page 2 with no strip (the whole set, all-or-nothing); a title block at the left or top.
- **Mutants** (10 test files):

  | Mutant | Tests that fail |
  |---|---|
  | keepOnlyDrawn no-op | 4 |
  | key-plan cover off | 2 |
  | strip not split | 1 |
  | **readerStrings returns ""** | **0: no test covers it** |
  | decode failure treated as empty text | 1 (incidental, the G2 test) |
  | code floor returns [] | 1 |
### Scans and photos (6, 7)
- The scan-route outputs in pdfs_after are HELD. I went by the file names and his statement; I did not re-run it.
- **What the customer is told** (portalText.ts:280): "Drawing held … Your request goes without it — or press Cancel". It never asks for a vector PDF, the CAD file or a sharper scan. Suppliers are not told a drawing exists.
- **The scan route never runs today.** It runs on the CAD worker, a GitHub workflow, and Actions is off (ledger 1564). At 9–17 min a page, 3 pages pass SCAN_JOB_MS (30 min), so the job is rejected and held.
- **JPG/PNG:** held (index.ts:516) → scan queue → held.
- **Where a model alone still decides:** a PDF page WITH a text layer whose identity is not text (item 2) and no server boxes. The find and verify models alone decide what of it is covered.
### After merge (9)
- The text branch exports placeSpans/reducePlaces from identity_places.ts, not `locationBelowEmirate`, so drawing_location.ts:18 reads undefined and the two gazetteers drift.
- On the merged tree, identityShapesIn gains 'place'. The file verifiers then HOLD v05c/v06c and the CAD-table area (held, not cut), but v01/v03/v07/v08/v12 and the v06 preview still publish.
- **Glue:** `import { placeSpans } from './identity_places.ts'` in drawing_location.ts and drop the local GAZETTEER. Keep PREMISES_NO/NUMBER_PLACE, because placeSpans needs a cue for bare labels.
- The union over-holds only through item 11. No single run of the 83 quoting strings matched.
### Second reader must see
The rendered PREVIEW and the rendered vector file, as pixels, for every vector page. What it has to catch:
- outlined, Type3 and pattern text;
- maps, QR codes and logos drawn as paths;
- annotations;
- communities missing from every list;
- a name in prose.

## ANONYMITY F2 DOORS 3
Narrow delta review of aeb239218..ad932e645, 13 Nov 2026. Worktrees: the branch, and the branch merged locally with origin/sales_engineer-nothing-below-the-emirate-and-no-name-crosses-in-text (F1) at its current head. The merge was clean and was never pushed. Both worktrees were removed afterwards.
VERDICT: MERGE, released TOGETHER with F1 (F1 first, or in the same deploy). Nothing is blocking.

1. Access answers are free text now, and keep what a supplier needs.
   - My original 40 (rewritten here, 35 EN and 5 AR): 0 of 40 changed. Twenty new answers ("container parked outside the community gate", "lift booking 48 hours in advance", "door width 90cm", 5 Arabic): 0 of 20 changed.
   - Eight planted places:
     - On the branch alone, the premises-with-number words (Villa 15, Tower 2, Makani, coordinates, gate 3, فيلا 15) become "the site" and go to the customer-only site key. Area names without a number survive: "Al Barsha 2", "Business Bay", "on the Al Barsha side", "near Mall of the Emirates", "البرشاء 2".
     - On the merge, all 8 of 8 are clean: "back gate on the Dubai side, no lift", "in Dubai, park in basement", "الموقع دبي، لا يوجد مصعد". That confirms F1 is required.
2. The kept-text notice now reaches the customer.
   - keptNotice names the kept part, in English and Arabic.
   - Clarifications.tsx:47,56 and MissingSpecs.tsx:53 show it whenever `kept_from_suppliers` is set.
3. Edit: an emirate of null or '' now means no change (verified). "Al Barsha" in the emirate field still gets 400.
4. The title reads "Fitout work in Sharjah · Job N" in both before_reveal.ts portalTitle and the SQL; the SQL now carries rfq_no.
   - SQL file and probe rehearsed on production through `rehearse_sql.mjs`: PROBE OK, rolled back.
   - Probe mutant 1 (title = summary): PROBE FAILED on 2 workspaces. Probe mutant 2 (file name kept): PROBE FAILED, because the probe now plants its own documents row.
5. The merge-order test is skipped on the branch alone (supplier_api: 1 step ignored) and runs and passes on the merge.
   - Extras verified: "Model HD-2020-W" survives.
   - pricedKind: integer-rate BOQ → 'priced'. Arabic quotation with a party → 'quotation'; with "السادة" and درهم → 'priced'. HVAC "flow rate … amount" → null.
   - customer_rates is a customer-only key, dropped at every door including the revealed copy.

THE HOOK (reducibleSeed). I ran the merged tree with and without a one-line re-export added to identity_text.ts. The output was identical both ways:
- "Fit-out (re:BarshaGardenVilla) bathrooms" → WITHHELD.
- "Fit-out of the ZZ DEMO Barsha Garden Villa…" → "Fit-out in Dubai, two bathrooms".
- Stored site, summary "…at Villa 15 Al Barsha 2 near Mall of the Emirates, Dubai" → "Bathroom renovation at Dubai".
- Site only in free text: "Bathroom at villa 15 Al Barsha 2 near Mall of the Emirates" → "Bathroom at Dubai". "البرشاء 2 فيلا رقم 15" → "دبي".
- The new-inquiry e-mail falls back to "Bathroom renovation work (Dubai)".
- Specifications survive: 300x600mm, Grohe Rapid SL 38772001, BS EN 997.
The re-export is therefore optional for safety; add it so the two branches agree.

MUTANTS: my 7 round-2 mutants.
- Caught by behaviour tests: N3 (finishEnglish ungated), N4 (workspaces raw), N6 (revealed keeps old terms), N7 (reveal without revealed_at).
- Caught only by the source-grep check: N1 (clarify_answer ungated), N2 (rfq_note ungated), N5 (add_missing_specs ungated), each 4 of 5. No behaviour test drives these three handlers.

TESTS
- Branch:
  - deno: supplier_api 272/0, customer_api 90/0, drawing_boq 99/0, inquiry_intake 120/0, messages_api 3/0, supplier_portal 53/0, quote_extract 66/0, send_whatsapp 30/0, supplier_english 10/0, identity_text 8/0.
  - tsc 0. nothing_a_supplier_reads_can_be_arabic 155/0.
- Merge: supplier_api 274/0, customer_api 90/0, drawing_boq 99/0, inquiry_intake 120/0, messages_api 5/0, supplier_portal 53/0, quote_extract 70/0, send_whatsapp 30/0, supplier_english 10/0, identity_text 11/0.
- Six PDFs, text and images: no image, no price, no old supplier, no area. The address PDF keeps "Dubai, 12th floor" and "service lift, loading bay at the back". The careless chat PDF reads "Access: the site gate, [contact hidden until reveal], no lift".

RELEASE ORDER
1. F1 and F2 together.
2. Apply the title SQL with its probe and the MANIFEST line.
3. Deploy: supplier_api, customer_api, messages_api, supplier_portal, drawing_boq, inquiry_intake, and the function that runs finishEnglish.

AFTER MERGE
- Behaviour tests (stubbed db) for rfq_note, clarify_answer and add_missing_specs; today only a source grep guards them.
- Grammar: "Bathroom renovation at Dubai" should read "in Dubai".
- "site in JLT cluster D tower 2" becomes "site in Dubai cluster D tower 2" in free text: an unnamed cluster and tower survive.
- F1's review_cpu_budget runs about 1,000 ms against a 1,200 ms budget and fails under load. catalogue_read fails on main too (the tesseract wasm is outside `--allow-read=.`).
- An Arabic quotation with no party and no currency, or prices written in words, is left to the model.

RESIDUE FOR A MODEL-BASED SECOND READER (code cannot catch these)
- Places missing from the gazetteer, or misspelled, in either language; unnumbered building or project names; and combinations of floor, building kind, trade and emirate that point to one site.
- The old supplier's house brand, slogan or style; prices written in words, inside pictures or as percentages.
- Glued or obfuscated contacts and names; and model English of an Arabic answer that restates a place.

## WORKFLOW W2 SALES 3
Narrow delta review of cac1536ff (follows 530152b47). VERDICT: FIX, one item, and it is about the probe; everything else is MERGE-ready.
1. W2 probe lines 57/81/116/125/158 against the money side's current head 88564ff63. W1's trg_reveal_receipt now files reveal.paid only when paid_at is set, and only for livemode<>false; anything else goes to demo_shadow_trace. The W2 probe inserts transactions with neither, so after W1 it fails across the board (A:no_handoff, A:no_receipt, B..D; rehearsed). With the same probe given `livemode, paid_at` = `true, now()` on those 5 inserts: PROBE OK, merged after W1's new files plus W1's fn_seat_handoff. The W1 probe also gives PROBE OK on that merge. Smallest fix: add those two columns to the 5 inserts (and to rehearse_a_paid_reveal_trace.mjs). Without it the release rehearsal goes red, although production behaviour is fine.
Note (W1's problem, not W2's): W1's 4-file set cannot be replayed whole. the_it_engineer_closes_every_loop_it_opens.sql raises 23514 (ledger 1013: an it.finding handoff closed without citing its note), and main's applied copy of that file raises the same on replay. So I rehearsed W1's three new files plus its new fn_seat_handoff body.
VERIFIED BY RUNNING (all rolled back, SELECT-only):
- His file + probe: PROBE OK.
- Mutants, all 10 caught: m1, m3b, m5b; n1 (C:not_capped), n2 (A:until), n3 (A:new_quote_taken), n4 (F:reopened_with_nothing_live, F:refund_message). My extra two are also caught: the finding silenced (G:no_finding, G:no_event) and a date put back into the notice (A:wording).
- fn_sales_engineer_request_step_failed: revoked; search_path 'public','pg_temp'; SECURITY DEFINER. It calls fn_it_engineer_finding_upsert with 9 arguments, matching production's only signature (text,text,text,text,integer,jsonb,text[],text[],text). Its own exception guard means telling can never undo the sent messages.
- Notices carry no date, and "available/open again" goes only to suppliers whose quote is live. The refund message follows the re-open in EN and AR.
- The 409 mapping: request_revealed.test.ts passes, and a mutant (isRequestRevealed returns false) fails it. quotes.ts:426 maps the insert error. The test covers the helper, not the call site, which I read.
- The hand-added hash 077f5cb794a6 is legitimate. It gates the Arabic VAT question in review.ts exactly as the other ~1300 gated lines are gated. Supplier surfaces never render it: SupplierPortal.tsx:43 has lang = 'en' as a constant, the Arabic check's "constant English" test passes, and supplier e-mails are lang 'en'. It opens nothing.
- Local runs: supplier_api deno 246/0; tsc exit 0; Arabic check 152/0; a_paid_reveal_ends_its_reveal_period 9/0; tracker 11/0.
- Minor: the customer tracker no longer shows the date until which he can open other quotations ("while they are valid"), though the server knows it (reveal_open_until). His option can end silently at the 30-day cap.
RELEASE JUDGEMENT: safe to apply and deploy in front of real customers and suppliers AFTER the money-side SQL (W1, then W2, before supplier_api), once item 1 is done so the release rehearsal is green. Nothing else blocks. After merge: watch the first live reveal end to end (outcome row, notices, duty end); confirm reveal_sale.ts writes paid_at and livemode (W1), since without paid_at no reveal.paid is ever filed.
THE THREE RULES AS BUILT, for the founder:
- New quotations: once a customer has paid to reveal one quotation, the request accepts no new quotations. Suppliers who already quoted may still revise or add an option. A new supplier is told "no longer taking new quotations". The customer is told to post a new request for more.
- Other quotations: after that first reveal, the customer may pay to open any other quotation on the request while it is valid (its stated validity, else 14 days), but never later than 30 days after the first paid reveal. A refund for a supplier who never responded re-opens this if a valid quotation remains.
- The other suppliers: each is told once, with no date and no customer details, "The customer has opened one quotation on request N. Your quotation remains available to the customer while it is valid." When the period ends they are told "Request N has ended", plus "the customer went ahead with another supplier" only if a hire of another supplier is recorded.

## ANONYMITY F1 TEXT 2
Delta review of be6847b8b (was 1c8e63e15; base 2cef71f27). Everything was run, offline. Drivers: scratchpad/rv/ (over.ts, over2.ts + corpus2.ts, leaks2/3.ts, adv.ts, ws*.ts, rul.ts, tb*.ts, wyg.ts, csv.ts, mut2/3.sh).
VERDICT: MERGE AFTER 3 SMALL FIXES (1-3). The precision goal holds: 0 of 421 sentences wrongly changed with 4 supplier/customer name pairs; 0 of 153 NEW sentences (MEP, joinery, landscape, ELV, signage, marine, catering; 30 Arabic). The only changes are rulings or the supplier's own name.
FIX
1. identity_places.ts acceptance (~:377): a weak premises next to a cue-only name accepts neither, so the most common UAE letterhead address crosses whole: "Office 302, Al Mulla Building, Deira", "Office 14, Hatta", "Warehouse 7, Masdar", "Shop 3, Karama", "Unit 4, Al Karama" are all unchanged. The same text with ", Dubai" or "Al Rigga" is removed. Fix: a weak premises with a number, beside a cue-only gazetteer name (SEP_STRICT), accepts both. Add these 5 rows.
2. anonymise.ts:154 plot (and :159 premises_no): COUNT_AFTER follows a run of digits that can backtrack, so the lookahead is beaten by giving a digit back. "PLOT 3451 M2" -> "█1 M2"; "Plot 6457 sq" -> "█7 sq" (residual: plot). This feeds titleBlockBoxes. Fix: `[\d٠-٩\-\/]*(?![\d٠-٩\-\/])` before COUNT_AFTER.
3. Tests rewritten to pass, against the binding memory note ("the corpus keeps planting what was loosened"). The planted fixtures were edited, not marked: identity_text.test.ts LEAKED "Contact Rashid Khan" -> "Contact: Rashid Khan", "ask for Rashid at the gate" -> "...Rashid Khan", "transfer to Mashreq" -> "Bank: Mashreq". The careless-model test's exclusions/notes are now the labelled forms ("Contact:", "Mr. Rashid"). Fix: keep the old strings as SECOND_READER rows asserted to still leak (so a later fix is seen), beside the new labelled ones.
NOT BLOCKING (do in the same PR if cheap)
4. ReDoS guard: the adversarial test catches a revert only by HANGING. N1 (the `(?![0-9٠-٩])` guard removed) never finished; the suite was killed at 900 s, because the time limit is read after the call returns. Run each input in a Worker with terminate() at the limit.
5. Pre-existing, not his but he claims "nothing hangs": after one warm call, a run of 1,000 spaces takes 6.5-7.3 s in scrubIdentityText on base AND branch (PHONE_UAE_INTL alone 1.9 s; 2,000 spaces > 60 s). A pasted BOQ with wide blank columns does this. Add a whitespace-run input to his test and collapse `[ \t]{2,}` before the patterns.
6. CSV name mask (M5 survives): his CSV test uses full legal names, which FIRM_EN catches without maskNames. REPORT_C's own string "balance on completion - Desert Brush team" still crosses compareTable WITH maskNames (maskContacts is whole-name). It is not live: quote_compare's generaliseDeep, with fragments, removes it first. Add that row and pass knownNameRe(n, {fragments:true}) in the CSV.
7. "Al Barsha 2 - 23B Street" -> "Dubai - 23B Street": an alphanumeric street number is not a STREET_NO. Abu Dhabi sector codes cross: "Mussafah M-37" -> "Abu Dhabi M-37", "Khalifa City SE-45", "Shabiya ME-10". Precise rules: `\d{1,3}[A-Z]\s+Street`; `[A-Z]{1,2}-?\d{1,3}` after Mussafah/Khalifa City/MBZ/Shabiya.
MEASURED
- Probes: C 46 -> 2 (his number: "Contact Rashid Khan" unlabelled, "Falcolux"); A 31 -> 2 (e-mail door) and 0 of 62 merged with the sibling ad932e645; my 60 -> 4 (his four). New 40 probes: 12 leak. Among them item 1's address case, item 7's sector codes, "Al Wasl area", "cluster 22", "Ajman Industrial 1", "المدينة الصناعية بالشارقة ١٣", "Saadiyat Beach villas no. 40", "behind Al Ghurair Centre", "near Dubai Hospital, Deira".
- Given-up rows: Falcolux and "Cedre Villas" are truly beyond a precise rule. "villa fifteen" is a narrow rule (villa + number-word not followed by a count noun). "Meadows 2" / "JVC, District 12" are precise when they follow a gazetteer name ("Meadows|Springs|Lakes \d{1,2}"; "District \d{1,2}" beside JVC). "Contact Rashid Khan" is precise with a given-name list (Contact + a listed first name + a Title word).
- Timing: review_cpu_budget total 267-273 ms idle (base 204-239), 337-370 ms with two suites running beside it (base 278-317). inboxBoq 91-121 ms (base 48-102). Passes.
- Adversarial (scrub / inboxField): "Al-Al-..." 50 KB 3.2 s / 19.3 s (base 2.0 / 12.9: pre-existing, worse); 50 KB Al Barsha Industrial run 18/106 ms; Arabic place run 116/161; 3,000 service sentences 79/364; 5,000 distinct supplier names 1.07 ms/call (base 0.28).
- Caches: NAME_CACHE cleared at 2,000 entries (bounded); SENT_MEMO holds one text. Bounded, no leak. 20,000 names: heap +81 MB transient (base +23).
- Drawings: drawing_boq 91/0 and drawing_redact 7/0 on the branch (same as base). Merged with the drawing branch 04656058f, no conflicts: its new tests 7/7 + 9/9 + 4/4, drawing_boq 91, drawing_redact 7, the check 4/4. Auditor B title-block strings not flagged: 2 of 18 (base 4). The two left are "2026/BP/55821" and "CPC-AB2-V15-P-101"; both were also missed on base. Only item 2 is new damage.
- "What you get": the renderer did not mask it on main, but it is NOT live. compare_csv/compare_pdf read quote_compare, whose last gate (index.ts:304, generaliseDeep) already turns "Falcon Trading LLC supplies…; call 050 123 4567" into "the supplier supplies…; call [removed]". A defence-in-depth fix.
- Rulings: 20 delivery terms x 2 doors and 20 brand questions, each with the supplier's own name, phone and Al Quoz planted. Terms and brands kept 60/60; leaks 0.
- Sibling ad932e645: merges clean. supplier_api 274/0, drawing_boq 99, messages 5, quote_extract 70, customer_api 90, supplier_portal 53, inquiry_intake 120, _shared 2280/1 (tesseract, as on base). Checks 30/30, 5/5, 3/3. every_checklist_question...address_key fails only on a production 401 (environment). The stored-site sentence reads "...at Dubai".
- Test windows: the source window 900 -> 1200 chars is still meaningful (the growth is comments; the body is 6 lines).
- Mutants (115 targeted tests; caught = some test fails): caught M1, M2, M4, M6, M7, M9, M10, N2 ("What you get" unmasked), N3 (count guard dropped). N1 (ReDoS guard) is caught only by a hang. Survived: M3 (equivalent: the second loop already trims the lower-case lead), M5 (item 6), N4 (reducibleSeed ignored: no test pins "at Dubai" in this branch; the sibling's test does). M8 gave no result (the run printed nothing).
AFTER MERGE: run all three branches together (text + sibling + drawings) once; keep item 1's rows in the shared corpus.
SECOND READER LIST: house brands from the supplier name (Falcolux); initials outside the quotation register ("FT team", "UPS" of Unique Power Systems); a short name made only of common words ("Emirates Steel"); "Contact/call <Name>" with no label; unlisted sub-communities and clusters (Cedre Villas, Khannour); place numbers in words; Meadows/Springs/JVC district numbers until the rules in "Given-up rows" exist; a landmark with no cue or no chain name; prose places ("the villa behind the mosque").

## WORKFLOW W1 MONEY 2
Delta review of 88564ff63 + 186263cd2 (round 1 was a6beed86b). Production was only read: SELECTs and rolled-back rehearsals. Worktrees removed. VERDICT: FIX. Most of the 12 items and R1-R6 are really built and proven. Four defects remain, and one of them stops a clean sale from ever being booked.

### Verified by running
- **Rehearsals:** main+probe PROBE OK; main + owner-file fn_seat_handoff + 1150 + sibling cac1536ff: main probe OK, 1150 probe OK, sibling probe FAILED (item 3).
- **Mutants:** the main probe catches 6 of 9: journal off by 1 fils, test mode posting a real journal, the window from insert time on the insert path, the sweep closing an item, livemode ignored, the accrual back. Three survive:
  - a second invoice number on replay. It is harmless: the on-conflict clause keeps the first number, and the mutant only burns a sequence value;
  - a refund booked at total_charged: the probe matches "2300 38.77" but never checks the 1050 credit;
  - fn_reveal_clock_start from insert time: no reader of the window is asserted.
- **Gaps:** on the merged rehearsal with Stripe-shaped figures (fee 135.30): 15 pass / 2 fail. Both failures are the two HOLDS that fail in any rehearsal, because nothing is delivered inside a rolled-back transaction. On the sibling's own unchanged rehearsal script: 8 pass / 9 fail (no paid_at, so no reveal.paid).
- **deno:** reveal_invoice 15/0, stripe_webhook 11/0, accountant 53/0, stripe_checkout 11/0, messages_api 3/0, supplier_api 244/0 (his 2 failures did not reproduce), _shared money tests 42/0.
- **node:** every_report 4/0, handoff_kinds 2/0, reveal-invoice checks 2/0 and 1/0, every_pdf 4/0, a_paid_reveal_with_no_sale 7/0, reveal_work 2/0, a_money_column 17/0.
  - payments_are_the_accountant 5/2: production lacks the new kinds (expected while unapplied); the refund-ladder replay fails "fn_payload_names_a_live_payment does not exist" (item 4).
  - every_alarm 11/1: fn_notifications_the_same_message_is_sent_once (a_notice_is_a_duplicate_only_of_the_same_event.sql, 11 Nov, not his) is unregistered. The same test fails on origin/main. I saw one unregistered routine, not two.
- **Production read:** live == mirror for the 9 routines from round 1; still unchanged. The 3 refund routines differ from live ONLY by the overcharge_return branch.
- **Holidays (his correction is right):** 25 confirmed dates through 2027-12-03, and fn_is_working_day skips them. From 4 Dec 2027 every holiday counts as a working day.
- **Journals by hand, all balanced, no VAT, no 6110/2200:**
  - fee 777.60, card fee 34.49 instead of 34.48: Dr 1050 743.11 / Dr 6100 34.49 / Cr 4000 777.60;
  - international, card fee 32.90: 744.70 / 32.90 / 777.60;
  - AED 1.01: Stripe's AED 2 minimum refuses it. If forced, the net is -0.07, and the sweep now isolates that row with a finding.

### FIX, most harmful first
1. **A clean sale whose month-to-date total ends in .00 is never booked.**
   - Where: SQL :642-651 fn_reveal_month_revenue (stripe_amount_received_fils/100.0 gives scale 20) → sale.made month_total_aed = 135.00000000000000000000. Production's fn_handoff_redact phone regex `\m00[0-9][0-9 -]{5,}` rewrites the decimals into "[phone]", the JSON becomes invalid (22P02), fn_seat_handoff raises, and fn_accountant_reconciles_reveal rolls back: no check, no journal, no CEO.
   - Reproduced on production with a SELECT, and in the merged rehearsal: fee 135.00 crashes, fee 135.30 passes. Every retry fails until another sale changes the total.
   - Smallest fix: round(...,2) in fn_reveal_month_revenue (and on every numeric in a handoff payload). After merge: fn_handoff_redact should redact string values only.
2. **An overcharge return marks the whole sale as refunded.**
   - fn_refund_request sets transactions.refund_status='requested' and refund_requested_at. fn_refund_decide sets it 'approved'; fn_refund_settle later sets 'succeeded'/'refunded' with refund_amount_aed 38.77.
   - fn_refund_ladder_sweep skips 'approved'/'succeeded'/'refunded', so the customer loses the non-response refund ladder on the fee.
   - The portal and invoice read "refunded", and a stale CEO task "Decide refund N … To approve: write a row" is left open.
   - Fix: for reason_code 'overcharge_return', do not write transactions.refund_* in fn_refund_request, fn_refund_decide or fn_refund_settle, and close the ceo_task in fn_payment_check_returns_difference.
3. **The sibling's probe fails once both branches merge.** reveal.paid now waits for paid_at (:1273), the sibling probe inserts sales without it, so its "A:no_handoff …" fails, and apply-on-merge of the sibling will refuse. Fix (sibling seat): its probe and rehearse_a_paid_reveal_trace.mjs set paid_at and livemode the way stripe_webhook does.
4. **The owner-file edit depends on an unapplied file.** Every canonical replay of the owner file (payments_are_the_accountant refund ladder, canonical_routine_manifest REPO->PROD) fails until the main file is applied and in MANIFEST. Fix: the release order below, in one sitting; say so in both pending notes.
5. **A sale can stay unbooked forever** (SQL :862-869, :611-625).
   - If Stripe's figures never arrive and the CEO answers money_is_correct (or a final question resolves the check), the check resolves.
   - It then leaves fn_accountant_payment_checks_to_read, the brief's "awaiting" and "open" counts, and section 1 (which needs stripe_fee_fils). The sale is never booked and never shown again.
   - Fix: a live check is not resolved while no reveal_fee journal exists; it stays in to_read, and the brief counts live paid sales with no journal.
6. **A LIVE payment not recorded, on a demo-flagged customer, is still shadowed** (R2 says never). The payment.unrecorded payload carries no transaction_id, so fn_payload_names_a_live_payment is false and the owner file's fn_seat_handoff shadows it: the IT finding and the customer notice are not filed. The accountant's reconcile item still sees it.
   - Fix: fn_accountant_payment_unrecorded adds 'livemode': true when not p_demo, and fn_payload_names_a_live_payment honours it.
7. **Smaller:**
   - fn_payment_check_returns_difference :772 writes ceo_approval decided_by 'ceo' even under the accountant's standing grant: use p_by.
   - The a00 overcharge branch does not refuse a second overcharge_return on the same payment (a01 caps the total only): add a NOT EXISTS.
   - The probe should assert the refund's 1050 credit and one reader of fn_reveal_window.

### The owner file (2)
- **The 4 it would revert:**
  - fn_it_loop_reverify (canonical: the_it_loop_reverify_walks_cleared_findings_first_so_a_close_is_never_starved.sql);
  - fn_it_ceo_silence_watch (an_accepted_report_is_reviewed_when_its_review_date_arrives.sql);
  - fn_it_daily_line (the_it_engineer_reads_gmail_postmaster_daily_and_a_spam_spike_stops_the_invitations.sql);
  - fn_it_loop_tick (the_it_alert_tick_opens_its_backlog_within_budget_and_escalates_first.sql).
- **Why the file is stale for them:** these files sit later in MANIFEST, so canonical_routine_manifest.mjs (highest MANIFEST position wins) names them canonical. The other 9 owner routines equal live.
- **What apply_sql.mjs does:** it applies the WHOLE file and reads back every routine the file defines; it has no notion of canonical. Worse, the file's own section-14 probe now raises on production (trg_handoff_close_cites_its_note refuses its close; seen in a rehearsal), so a whole apply aborts.
- **No later file may define fn_seat_handoff** (handoff_kinds_are_data.test.mjs).
- **The correct, repeatable release:** in an it_engineer commit, delete the 4 superseded definitions and their revokes from the owner file, and make section 14 close through fn_seat_handoff_complete. The file then holds only routines it is canonical for, and re-applies cleanly.

### Release order (main session)
1. `node scripts/apply_sql.mjs scripts/sql/a_paid_reveal_is_reconciled_booked_and_timed_by_the_accountant_from_the_moment_it_is_paid.sql --apply --ddl --seat accountant`
   - Append the file to MANIFEST and delete its pending note.
   - Not between 22:00 and 23:30 UTC (the nightly ZZ journey): until step 3, the old code writes livemode NULL, and NULL counts as live, so a test payment would be booked.
2. `node scripts/apply_sql.mjs scripts/sql/the_it_engineer_closes_every_loop_it_opens.sql --apply --ddl --seat it_engineer` (after the owner-file fix above).
3. Deploy within minutes: stripe_webhook, stripe_checkout, stripe_confirm, accountant, reveal_invoice, messages_api, supplier_api.
4. The sibling's SQL, after its probe sets paid_at.
5. 1150: only on the founder's yes. the_ceo_may_let_the_accountant_return_an_overcharge_itself.sql: never without him.

### After merge
- fn_handoff_redact on JSON text (item 1's root cause).
- public_holidays ends 3 Dec 2027: add a finding when fewer than 12 months are listed.
- A sale whose paid_at fell back to insert time keeps it (write-once). It is later than Stripe's real time, so the customer is favoured.
- The customer is told "being returned now" before the second seat has cleared the refund.

### For the founder, in plain words
- **Revenue when paid (R5):** done.
- **Stripe's Invoicing fee:** booked once, when Stripe bills it (R1): done.
- **Money charged above the 3%:** returned through the refund path on the CEO's yes, and you are e-mailed and WhatsApped within the hour. But today that return also wrongly ends the customer's 5-day non-response refund on the fee (FIX 2).
- **A card dispute's fee:** now booked.
- **A sale that Stripe never confirms:** if the CEO says "the money is correct", it is never booked (FIX 5). Decide: should it be booked with Stripe's published card rate and corrected later, or kept open until Stripe answers?
- **1150:** waits for your yes.

## WORKFLOW W1 MONEY 3
Delta 09b79561e + 1c3e41d62 (round 2 was 88564ff63 + 186263cd2). Nothing was rehearsed on production. Sources are marked [L] local Postgres 16, [R] reading, [P] a light SELECT on production. The local cluster was built from the mirror per local_from_mirror.mjs, with stand-ins for auth/storage/cron/net/vault. It ran under /tmp/pg-review-w1 on port 55441, because the sandbox resets the permissions of /tmp/claude-0 so postgres could not use it. It is deleted.
- Did not load on PG 16: 27 vector columns (loaded as real[]), 26 routines with vector signatures, 17 hnsw/ivfflat indexes, seat_exam_item. None of them is on the money path.
- Seeded from production [P]: reference tables (pricing, gl_*, seat_handoff_kind, holidays, grants, mail policy, task states) and the ZZ DEMO fixture rows the probes use. No app_secrets, no real person.
VERDICT: FIX. The money-side fixes hold. Four items remain: the overcharge return for a real customer, the lock budget, the sibling's probe, and the redaction proposal.

### Verified
- **[L] Files and probes:**
  - main file + whole owner file + main probe: PROBE OK;
  - main + owner + sibling 5acacfaf2 + 1150: main probe OK, 1150 probe OK;
  - sibling probe FAILS: quote_quality_hold.accepted_md5 NOT NULL. [P] Production has the column NOT NULL, with no default and no trigger, so his "all three probes OK" does not reproduce.
- **[L] Mutants:**
  - caught: test mode posts a real journal, window from insert time, sweep closes an item, livemode ignored, refund at total_charged, clock from insert time (fn_refund_state);
  - caught by error rather than by a verdict: journal 1 fils off (fn_gl_post refuses), accrual back (FK on 6110);
  - survive: a second invoice number on replay (benign: on-conflict keeps the first number), and unknown mode treated as live inside fn_reveal_is_live (harmless: fn_gl_post_reveal_fee :417 and the reconcile keep unknown unbooked).
- **[L] Item 1:** a clean LIVE sale of AED 135.00 is matched and booked (1050 130.08 / 6100 4.92 / 4000 135.00) and the CEO is told. month_total_aed "135.00": the crash is gone.
- **[R+L] Items 2, 4–7 and (a)/(b) are built as claimed:**
  - the refund diffs vs live touch only overcharge_return;
  - the owner file is now canonical for all 10 of its routines and re-applies whole cleanly [L];
  - 29ac49f5 is backfilled to test [L], from its /test_ links [P];
  - NULL mode is never booked; the runtime tries the live key, then the test key.
- **[P]** Production holds 1 transaction, 4 quotes, 4 inquiries, 215 gl_journal rows (not ~4k), 0 refunds of the new kind. The model hold is OFF.
- **deno:** reveal_invoice 16/0, accountant 53/0, stripe_webhook 11/0, money tests in _shared 35/0. The gaps check and the node checks that replay on production were not run (forbidden).

### FIX
1. **An overcharge return for a REAL customer stalls, but is announced as done** (main :835-861 and :1004).
   - fn_refund_decide → fn_high_stakes_gate. With the hold off [P] and the customer not a fixture, the clearance is 'pending' and the answer is awaiting_second_seat. The refund stays 'requested'.
   - The routine still closes the "Decide refund" task as done, and the customer is told "it is being returned to your card now".
   - If the second seat agrees, trg_high_stakes_review decides it again [P], and it pays. If it disagrees, nothing decides it again: the money never moves, the check stays open "until Stripe confirms" forever, and the customer has been promised a refund. His demo rehearsal passed only because a fixture is waved through.
   - Fix: close the task and queue the notice only when v_fin.ok. On awaiting_second_seat, set the task to 'blocked' with the reason. On a disagreement, hand the check back to the CEO.
   - Readers of that task [P/R]:
     - ceo_agent inbox (open/working/blocked tasks; it also lists refunds still 'requested', so the stall stays visible there);
     - fn_ceo_daily_run, fn_ceo_queue_work, fn_ceo_closes_answered_handoffs, fn_ceo_task_open, fn_transaction_refund_outcome_follows_through, fn_external_refund_is_verified;
     - fn_ceo_refund_decision_metric matches 'Decide refund case #' (refund_case), so it is not this task.
2. **The lock budget.**
   - [L] A blocked apply fails at the timeout, rolls back, and leaves nothing applied. But a reader that arrived 1 s later waited 2.0 s, so readers wait up to the full lock_timeout. 3 s is over budget: use '1500ms' (or '1s') and retry.
   - [L] The owner file has NO lock_timeout and takes ACCESS EXCLUSIVE on agent_actions (DROP TRIGGER z61; 37k rows, the busiest table) plus a ShareLock (CREATE INDEX IF NOT EXISTS). Add the timeout, and use CREATE OR REPLACE TRIGGER (ShareRowExclusive).
   - [L] The sibling takes ACCESS EXCLUSIVE on quotes and inquiries with no timeout. Add one. Validating quotes_vat_treatment_known scans 4 rows, which is nothing; the risk is waiting for the lock, not the scan.
   - NOT VALID followed by VALIDATE inside the same transaction saves nothing (ACCESS EXCLUSIVE is held to commit) but is harmless.
3. **The sibling's probe:** set accepted_md5 (or let the code under test create the hold) before anything is applied.
4. **The fn_handoff_redact proposal fixes the crash [L] but is incomplete.**
   - Object KEYS are no longer redacted ({"a@b.com": …} stays).
   - A money STRING "135.000000000" still becomes "135.[phone]" (valid JSON, wrong value).
   - Fix: redact keys too, and anchor both phone patterns with (?<![0-9.]).
   - Release it through its own owner file, under the same lock rules.
5. **Smaller:**
   - The a10 trigger keeps a LIVE check open forever when the sale cannot be booked (fee 0, or fully refunded before Stripe's figures arrive), so it is re-read every hour forever. Give it a terminal state.
   - :2606 grants fn_reveal_window (SECURITY DEFINER) to authenticated: any signed-in user can read any transaction's clock. Keep it to service_role.

### The real apply (scripts/apply_sql.mjs, [R]+[L])
- It sends `set application_name…; <file>` as ONE multi-statement query, which is one implicit transaction [L]. `set local lock_timeout` works.
- A lock timeout comes back as an SQL error (HTTP 400). Only 429/5xx are retried, so it fails fast with no partial state.
- A 5xx after a commit would re-send the whole file. The file is idempotent.
- [L] The main file runs in about 0.1 s at production's row counts. It holds ACCESS EXCLUSIVE on transactions, refunds, stripe_dispute and accountant_reveal_reconcile_item, and a ShareLock on gl_journal and reveal_invoices (writes blocked for that ~0.1 s). Fine.

### Release procedure (main session; total stall ≤ 1.5 s)
- **T-10 min (fixes in place):** lock_timeout '1500ms' in the main, owner and sibling files; the sibling probe fixed; FIX 1 done.
- **Quiet time:** not 21:30–23:30 UTC (nightly ZZ journey at 22:00) and not peak hours. Start on a minute that is a multiple of 5, at +10 s: the accountant seat duties run at minutes 1–4 of each 5.
- **Before:** [P] `select pid, now()-xact_start, left(query,80) from pg_stat_activity where state<>'idle' and xact_start < now()-interval '1 s'` must show nothing on transactions/refunds/stripe_dispute/agent_actions/quotes/inquiries.
- **T+0:** `node scripts/apply_sql.mjs scripts/sql/a_paid_reveal_is_reconciled_booked_and_timed_by_the_accountant_from_the_moment_it_is_paid.sql --apply --ddl --seat accountant`. On a lock timeout, wait 30 s and retry, at most 3 times; then stop and look at what holds the lock.
  - [P] check: livemode/paid_at columns present, cron job accountant_payment_checks present, 29ac49f5 livemode=false.
  - Add the file to MANIFEST and delete its pending note.
- **T+2:** `node scripts/apply_sql.mjs scripts/sql/the_it_engineer_closes_every_loop_it_opens.sql --apply --ddl --seat it_engineer`. Same retry rule.
- **T+5:** deploy stripe_webhook, stripe_checkout, stripe_confirm, accountant, reveal_invoice, messages_api, supplier_api. Rows written in the gap are livemode NULL = unknown: never booked, and resolved by the hourly reconcile.
- **Later, separately:** the sibling (same procedure, --seat sales_engineer); the fn_handoff_redact owner file; the 1150 file and the grant only on the founder's yes.
- **After each step:** [P] statement-timeout errors in agent_runs for the last 10 minutes; open locks; `select count(*) from transactions where livemode is null` (it should fall to 0 within the hour once the deploy is live).

### For the founder, in plain words
- Revenue is booked when paid. Stripe's fees are booked when Stripe bills them. A dispute's fee is booked.
- A payment whose mode is unknown waits, unbooked, until Stripe answers.
- **A return of money charged above the 3% needs the CEO's yes AND the second seat's.** Today the customer is told "being returned" before the second seat agrees. Decide: may an overcharge return skip the second seat (it is money that was never ours), or must the customer wait for it?
- **1150:** still waits for your yes.

## WORKFLOW W3 POOL 1 — independent review of origin/ceo-every-seat-reads-one-pool-and-every-hand-over-comes-back @ d45aa1e55 (13 Nov 2026)
Marks: LOCAL = PG16 throwaway cluster loaded from the mirror (triggers/checks off for fixtures); READ = code; SELECT = production read.
Cluster was made in /tmp/pg-review-w3 (the sandbox refused chmod on /tmp/claude-0, so postgres could not reach /tmp/claude-0/pg-review-w3).

VERDICT: FIX. The pool works mechanically and the probe passes LOCAL, but it feeds a CEO seat that does not judge, escalates into
nothing anyone reads, misattributes authorship, and cannot see most of the company's hand-overs.

1. THE CEO SEAT DOES NOT DECIDE, AND THE POOL IS WIRED INTO A DEAD PATH (SELECT+READ). app_secrets.ceo_model_slot has 0 rows, so
   ceo_agent/index.ts:384-385 returns "skipped" and the pool call at ceo_agent/index.ts:407 never runs. The CEO's it.finding "answer"
   is fn_seat_answers_it_finding: code returning 'ceo acknowledged "…". Its playbook has no deterministic remedy' with replied_at = created_at
   (sample #403375, 0 s). CEO think.answer judgements stopped on 1 Nov (30 days: 334 think.answer to 1 Nov, 96 knowledge_refresh,
   16 lesson_reapproval, 7 management_review, 6 target_forecast...). Correct numbers: 216 pending it.finding (105 ceo, 39 se, 33 mkt,
   25 cs, 12 acc), 189 overdue, 194 carry escalated_report_id, which the new escalation skips. So the new rule touches none of them.
   Smallest fix: for agent='ceo', stop the code acknowledgement (leave it unreplied) and add one CEO duty that runs think() (seat ceo,
   surface ceo.it_finding, a short list of choices: fix now / assign to a seat / accept the risk with a reason / founder) on N findings per tick, with the
   pool block, closing through fn_seat_handoff_complete. Do not gate it on ceo_model_slot.
2. AN ESCALATION GOES NOWHERE ANYONE ACTS ON (READ+SELECT). fn_handoff_overdue_escalate only sets a flag and emits handoff.overdue.escalated.
   The CEO sees one count in a digest its model never reads (see 1). fn_founder_brief_overdue_handoffs has no caller on this branch or
   the accountant branch (grep 0). Day one (SELECT, same WHERE): 14 escalations, not a flood: 10 to ceo, 4 to the founder (ceo.revise x2,
   ceo.root_cause x2). Nobody sees those 4. Silent seat is wrong when replied_at is set and the kind is not originator-closed: support.case_open x4,
   backup.remediate x1 name a receiver that already answered. The "once" is not tested: mutant M3a (drop the escalated/silence guards)
   gives PROBE OK. dedupe_key hides it, while the row is re-stamped every 15 min. Starvation: "order by a.id limit 100" then
   "continue" for rows not yet due. Fix: put now() > due in WHERE; file a ceo_task or hand-over to the superior; call the founder lines from
   fn_founder_brief in the same release.
3. THE FOUNDER'S TEST, BLOCKS PRINTED LOCAL:
   it_engineer/supplier: "13 Nov 13:03 sales_engineer: supplier.approved -- Gulf Steel Trading LLC verified=true". Usable, but the AUTHOR IS
   INVENTED: fn_emit_supplier_approved fires on any approval with actor 'system', and the timeline names the type's owner seat.
   A model will say "the sales engineer verified him" after the founder or code approved him, even when verified=false. Say "approved
   (recorded by code)".
   Paid reveal: sales_engineer on {inquiry_id} sees only "quote.received" / "rfq.created -- open". The reveal.paid hand-over is keyed
   transactions/tx and its payload has no inquiry_id (SELECT keys), so "the customer paid" is invisible. The CEO (subject null) reads
   "1 reveal.paid ... Notable: reveal.paid tx-1 11:04": an id, with no amount or outcome. sale.made is missing from the CEO's day because its owner row is 'none'.
   Accountant on {transaction_id}: "accountant: reveal.paid to sales_engineer -- answered: …; sale.made to ceo -- open with ceo". Good.
   Complaint: the sales_engineer on {customer_id} sees nothing. support.case_open is keyed 'support_case', which fn_pool_kind does not map.
   SELECT 30 d: of ~24,000 hand-overs only 20 have a subject table the pool maps (transactions 9, refunds 8, leads 3). Invisible:
   it_engineer_finding 6,842, notifications 6,390, support_case 44, sales_knowledge_gap 66, seat_deliberation 13, inquiry_intake 4. The accountant
   branch keys payment.exception as 'tx#n', so that misses too. Fix: cross-keys from detail (customer_id, inquiry_id,
   transaction_id), split on '#', map support_case.
4. THE CAP CUTS THE IMPORTANT LINE (LOCAL). With 6 answered hand-overs on a subject, the block is exactly 1,300 characters and both "Waiting on
   you" and "YOUR HAND-OVERS" are cut. seat_pool.ts:61 then adds a ~100-char header and slices again. Mutant M4 (cap 100000) gives PROBE OK:
   the probe cannot fail on the budget. Fix: put the hand-overs first, cut the timeline to fit, and have the probe assert a block at the cap.
5. THE SEED (READ+LOCAL). For 60 hand-over echo types the owner is the alphabetically first RECEIVER, not the producer:
   it.finding->accountant, ceo.directive/month_directive/revise/root_cause/improvement/decision_closed->accountant,
   delivery.result->accountant, reveal.paid/refund.paid/refund.request_checked/invoice.issued/nonresponse.charge_raised->sales_engineer
   (sender accountant), refund.requested->accountant (sender se), knowledge.request->ceo (sender cs), mailbox.supplier_reply/invite.reply
   ->sales_engineer (sender marketing), payment.exception->ceo, payment.unrecorded->it_engineer (sender accountant). Rule: owner =
   seat_handoff_kind.from_seat. 83 of 101 types have no audience beyond the owner. Live kinds with NO row: complaint.due,
   support.human_requested, support.decision_objection, payment.failed, payment.received, charge.disputed, fraud.money_held,
   refund.declined, subscription.payment_failed, and the accountant branch's overcharge.customer_notice. The check still passes, because test 1
   uses a static 13 Nov fixture plus a hand-written SIBLING_TYPES (proved: no row for handoff.overcharge.customer_notice.sent and the test passes).
   Derive the required set from seat_handoff_kind and the fn_emit call sites. main.sql:85 "delete from event_subscription" wipes
   the founder's edits on any re-run: insert only rows that are missing instead. Must act, and nothing filed: request.step_failed (sales_engineer
   re-runs; entity_type 'handoff', so it is not on the inquiry's timeline either), delivery.result failures (customer_support resends;
   no audience at all), supplier.applied (verification rests on a duty; the pool only counts it).
6. THE deliberation.review CLOSER CLOSES A 'revise' THAT NOBODY ACTED ON (SELECT). Day one it closes deliberation 21591 (final verdict 'revise', task done)
   as "Review read". All 10 others pending are revise or reject. Close only on an agreeing verdict; otherwise hand the verdict to the author.
7. LEAK (LOCAL). The external block holds kinds and states only. The supplier-audience block had no name, price or site, and M5 was caught.
   It still puts internal hand-over names ("knowledge.request to sales_engineer (open)") and other parties' activity on a shared inquiry (a
   rival's quote.received, later reveal events) into a supplier's prompt. That gives away competitive state, not identity. Fix: for an external
   audience, return only rows whose actor or subject is that party. Demo and real stay apart (M1 caught; the timeline is subject-scoped). The
   internal digest sends supplier company names and raw ids (tx-1, #40793) to the provider; those ids are noise.
8. AUTHORITY JSON IS DOCUMENTATION, NOT ENFORCEMENT (READ). In 10 of 10 sampled "grant" entries (marketing.publishing, sales.matching x2,
   sales.intake x2, support.reply, sales.scope_validation, ceo.final_internal_authority x3), the grant is checked by 0 SQL routines
   and 0 TS call sites. fn_agent_may_act has one SQL caller. Dangerous on Monday: marketing.outreach_reply (SELECT: sales.invitation
   active=false; 330 notifications typed *invit* in 7 days); resend_inbound/email.unsubscribe_request (customer_support changes
   consent with no grant); org_task.faq_answered (org_authority 0 rows). The other 13 quote-readiness gaps are lower.
9. COST (LOCAL). Busy day (5,000 heard events and 500 open): digest build 2,082 ms (his 112 ms at today's ~80 heard/day); all six
   context calls 22 ms; timeline 10 ms with the indexes and 68 ms without. Plain EXPLAIN on prod without the indexes: parallel seq scans of agent_actions
   (173 MB) and company_event (74 MB, twice) on every call, so the indexes must be live before the deploy. fn_seat_pool_context builds the digest
   INLINE when no row exists (first call, or the demo scope). That can pass the 1.5 s TS timeout and keep running with no abort; return '' instead.
   The TS fallback is sound: reject, throw or timeout all give '' (seat_pool.ts:53-67). Extra input is ~250 tokens x ~258 judgements a day
   (SELECT), roughly 65k tokens a day. The duty cannot pile up: fn_seat_duty_run uses skip locked and every duty has its own job.
10. THE APPLY LOCK IS NOT "AN INSTANT" (READ). main.sql:56 drops the trigger FIRST, so ACCESS EXCLUSIVE on company_event (it blocks SELECT
   and every fn_emit from every table's trigger) is held until COMMIT of the whole file. The file takes 40 ms LOCAL; production also fires
   seat_duty's z70 playbook trigger. Move the drop to the last statement.
Integration (git merge-tree): each pair of the three branches conflicts in one place only: add/add on
scripts/it/a_paid_reveal_is_known_to_every_seat_with_a_step.gaps.mjs. No file overlaps the anonymity branches (identity_text.ts,
what_a_supplier_receives.ts, inquiry_intake/*).
Runs: deno _shared + ceo_agent: 2,272 passed, 1 failed (catalogue_read.test.ts:107 tesseract/event loop: a file this branch does not touch, environment).
Node checks: every_seat_reads_one_pool 5 passed and 5b skipped (the rehearsal runs only with QD_POOL_RELEASE_REHEARSAL=1, confirmed);
every_report_and_handoff_comes_back 6 of 6. Probe LOCAL: PROBE OK (sizes 475-971). Mutants: M1 demo into real CAUGHT; M2 another subject's rows CAUGHT
(only because the 6-line limit pushes the probe's rows out); M3a escalate twice SURVIVES; M3b twice without dedupe CAUGHT; M4 cap removed SURVIVES;
M5 full text to an external reply CAUGHT. tsc: not run (src/ unchanged).
SAFE APPLY (after the fixes): (a) off-peak; each index file alone, outside a transaction, with "set statement_timeout = 0" for that session.
The 8 s cap kills a CIC and leaves an INVALID index that "if not exists" then hides, so check pg_index.indisvalid after each and redo
if false. Each holds SHARE UPDATE EXCLUSIVE (DML goes on) for seconds and waits for older transactions. (b) The main file with the trigger drop
moved last, lock_timeout 3s, expected under 1 s; re-run on a lock timeout. (c) Deploy every function that imports think or ai_reply. Never rehearse on prod.
TELL THE FOUNDER: "The CEO seat decides nothing today. The CEO's 'acceptance' of the IT findings is one line of SQL that replies
'acknowledged, no remedy' in 0 seconds. The CEO's model judgement is switched off (ceo_model_slot not set), and its other model judgements
stopped on 1 Nov. The shared pool would hand news to a seat that does not think, and its escalations land with that seat. First make the CEO judge
each finding with the model, then add the pool."
AFTER MERGE: watch seat_pool_digest.built_at advance every 15 min, ceo.company_pool avg_ms and failures, the first handoff.overdue.escalated
rows and who acts on them, company_event inserts during the apply window, and pg_index.indisvalid on the three indexes.

## ANONYMITY F1 TEXT 3
Narrow delta of 405661a36 (was be6847b8b). Run offline; drivers scratchpad/rv/ (c3.ts, bl.ts, ph2.ts, corpus3.ts, over3.ts, mut4.sh, probes/).
VERDICT: FIX (2 blockers, both small), then MERGE with the sibling. Every claim on my items holds except where noted below.
BLOCK
1. Collapsing runs of blanks (identity_text.ts scrubIdentityText and friends) REOPENS a phone leak on the supplier-to-customer doors. PHONE_UAE_* refuse a number followed by ` <digits>` (BOQ-row guard). Column-spaced text kept that boundary; one space loses it. "Sales contact    050 123 4567    12,500.00": the base gives "[removed]" on save and door; 405661a36 passes "Sales contact 050 123 4567 12,500.00" on both (inbox withholds). Fix: cap blank runs at TWO characters (`[ \t ]{3,}` -> two spaces), not one. On the base, "Sales contact  050 123 4567  12,500.00" is caught and 3,000 x "  x" runs in 1 ms. Plant this row.
2. Three-way merge (text + sibling ad932e645 + drawings 0a51ffb14): no textual conflict, but the drawings test a_drawing_reaches_a_supplier_with_no_owner_no_area_no_map.test.ts fails 2 (L3 :31, items 1-11 :167): `"ARJAN" passed as drawing content`, `v03_location_shapes: released with "ARJAN"`. The drawings branch alone passes 11/11. F1 made Arjan cue-only (to keep "Arjan model chair"), and a title block's bare "ARJAN" no longer counts. A semantic conflict that RELEASES a drawing naming the area. Fix: in the drawing path (or for an ALL-CAPS standalone token on a title-block line), cue-only gazetteer names count. Re-run that file on the 3-way tree.
CHECKED, HOLDS
- My 5 addresses: removed ("Office 302, Al Mulla Building, Deira" -> "Dubai"; "Shop 3, Karama" -> "[X]", Karama being Dubai/AD). Count guard: "PLOT 3451 M2", "Plot 6457 sq" kept whole; "PLOT NO 373-1234" still removed.
- Restored planted rows: asserted to still cross (identity_text.test.ts:304-308, careless test :118-125). Good.
- Adversarial test: clean in 24 s. With the ReDoS guard reverted it FAILS in 173 s. Acceptable for the gate. Faster still: stop the whole test at its first breach.
- Blanks: 1,000/5,000 spaces, tabs, NBSP, U+3000, thin space, 2,000 line breaks: all 0-30 ms. BUT output spacing changes even where nothing was removed: "Item 1    Ceramic tiles    10 nos    450.00" -> single spaces on every door, and "  Line two   indented" loses its indent. Tabs and line breaks are kept. The customer and supplier PDFs print single-spaced cells. Say so in the PR, or (preferable) collapse only for matching via the 2-space cap of item 1.
- 574 corpus x 3 name pairs: 0 wrongly changed (only "Falcon grey" under Falcon, and the rulings). 80 NEW sentences aimed at his rules: 5 wrongly changed + 3 arguable. Wrong:
  - "Greens 4 trays microgreens" -> "Dubai trays…"
  - "Meadows 2 bags seed mix" -> "Dubai bags…"
  - "MBZ-1 panel" -> "Abu Dhabi panel"
  - "Deira 3 piece set" -> "Dubai piece set"
  - "Industrial Area lighting fixture" -> "[X]lighting fixture" (also eats the space)

  Arguable: "villas no. 40 to 45 on the drawing", "Al Wasl area rug", "Mussafah supplier type ME-10". Fix: the Meadows/Greens/Springs/Lakes + number rule only before villa|cluster|street|, or after a place cue; the sector-code rule needs a letter-digit code with a hyphen after the community, not "MBZ-1"; cue-only + number not before piece|set|seater|nos|kg|bags|trays. Not a release blocker (scope words, no identity).
- Rulings: ports and brands 60/60 kept, 0 leaks. Probes: C 46 -> 2; A 31 -> 2 (e-mail; 0 of 62 merged with the sibling); my 60 -> 1 (Cedre Villas); my 40 -> 1 (Khannour). Confirmed.
- Merged with the sibling (+ drawings): suites supplier_api 275, drawing_boq 99, drawing_redact 11, messages 5, quote_extract 71, customer_api 90, supplier_portal 53, inquiry_intake 120, wa_inbound 230, pdf_native 59 all pass. _shared 2292 with 4 failures: tesseract (as on base) + the 2 ARJAN failures of item 2. Checks 30/30, 5/5, 6/6, 4/4, 3/3; the address-key check fails only on a production 401.
  - "re:BarshaGardenVilla" is withheld. A stored site reads "Renovation of two bathrooms in Dubai". "at Villa 15, Al Barsha 2, Dubai" reads "at Dubai" (cosmetic).
  - locationBelowEmirate resolves (returns ["Villa 15","Al Barsha 2","near Mall of the Emirates"]); no caller uses it yet.
  - "Haddad Family Office" -> "█ Family Office" on the portal.
- Mutants: 11 of 14 caught (M1, M2, M4, M5, M6, M7, M9, M10, N3, N4, plus N1 via the Worker). M3 is equivalent. N2 survives (quote_compare's generaliseDeep covers it). M8 does not compile. Suites on this head alone: _shared 2281/1 (tesseract), supplier_api 247, quote_extract 71, messages 5, customer_api 90, drawing_boq 91, drawing_redact 7. review_cpu_budget passes.
RELEASE JUDGEMENT (F1 + F2): after items 1 and 2 (an hour's work, each with a planted row), yes: safe to put in front of real customers and suppliers, with the second reader on the list below still owed. Nothing else blocks.
AFTER MERGE: run the three-branch tree once more; adopt corpus3's 80 rows into the permanent corpus; boq_from_text.ts:38 e-mail pattern (his 1.9 s on 50 KB "Al-Al-"): apply his proposed bound in the owner's PR.
FOR THE FOUNDER (plain words): The code layer now reliably removes, on every door both ways: e-mails, web and social addresses, UAE phone numbers (also written in words or split), TRN, licence, IBAN and account numbers, P.O. boxes, the supplier's and customer's own names (also in the other script), labelled people ("Contact:", "Regards,", "Eng."), document numbers, bank names, signature blocks, and every place below the emirate it knows by name or shape: villa/flat/plot/office numbers, streets, about 400 UAE communities in English and Arabic, Makani, coordinates and what3words. Each becomes its emirate, which is allowed to cross. Measured on 654 ordinary trade sentences, it changes none of them, and keeps port terms and brands where you ruled they pass. It does NOT reliably catch, and a model-based second reader is still needed for: a person named without a label ("Contact Rashid Khan", "call Rashid"); a supplier's house brand or nickname built from its name ("Falcolux", "FT team", "Emirates Steel"); a sub-community or cluster nobody listed ("Cedre Villas", "Khannour"); a landmark with no cue word; and places described in prose ("the villa behind the mosque").

## ANONYMITY F3 DRAWINGS 2
Delta review: 04656058f → a58c2fc45 (8 commits). Offline: no production edge call, no paid model call. Worktree removed.
**VERDICT: FIX.** None of the fixes is big. The design (pixel gate + string reading + code floor) is sound and, on my corpus, closes 9 of the 10 leaks I found. Three gate rules are untested, the CAD file is held whenever a block name is marked, and the merge with the text branch reopens a leak.

**Runs**
- Deno on the head: 453/0 on my set. Merged with text 405661a36 + doors ad932e645: no textual conflicts, 696 pass / **2 fail** (FIX 4).
- Hostile filters: every one returns null quickly. A 300 MB Flate bomb is cut by the 64 MB cap; /Predictor 2 /Columns 0 no longer hangs.
- Tests not weakened: the vocabulary assertions moved to isVocabularyContent, and a floor test was added.

**My 19 identity cases, with three stubs**
- **FAITHFUL** (boxes what is there): 0 published with identity. A PDF file is never released today (awaiting_pixels).
- **LAZY** (find nothing, gate says clean after the floor), which is the same as **ALWAYS-CLEAN**: residue on the model path = v01 outlined site labels, v12 Type3 text, **v02 the whole outlined TITLE BLOCK** (consultant, client, villa, area, plot, drawing no).
  - The floor detects those "rows of text drawn as shapes" (it counts 10) but only lowers confidence; it does not cover them.
  - Everything else in my corpus is covered by the code before any model looks.
  - His counts are confirmed, except that he lists v01 and v12 and not v02.
- **An OCR stub** is no fair stand-in. OCR reads text at the full 2600 px but cannot see a logo, a QR code or a map. A real model sees those, but not small text.
- **What a real model gets:** the page goes at 2600 px long edge (MAX_EDGE, MAXW); Anthropic models downscale to about 1568 px.
  - A1: a 7 pt line arrives at about 7.6 px per em (5 px caps), then about 4.6 px (3 px caps). Unreadable.
  - A3: about 9 px per em after the downscale.
  - So a lazy or blind model passes small title-block text that only the floor can cover.

### FIX (most harmful first)
1. **drawing_redact/index.ts:446-466 (verify_file) and customer_api/lib/drawings.ts:339.** The released PDF is "verified" on JPEGs the customer's browser sends.
   - Nothing checks that the images are of the pending file, or that their number equals its page count (`slice(0, 20)`; 1 image of a 5-page file releases pages 2–5 unseen).
   - Fix: the server counts the pending file's pages (pdfPages) and requires images.length === pages (≤ 20, or hold).
   - Also check each image's aspect against its MediaBox, and that the image's ink lies in the regions where the file's text and lines are, so it is the same page.
2. **Three gate rules no test catches** (my mutants survive):
   - (a) the CAD file's first-look rule: `g.calls > 1` removed at index.ts:435;
   - (b) a bad index in the strings answer ignored instead of holding: drawing_string_reading.ts:61;
   - (c) more than MAX_STRINGS strings read as "no identity": :68.
   - Each is one test.
3. **CAD file HELD whenever the model marks a BLOCK name** (a firm's logo block, the commonest case).
   - Measured: `count of block ZZDEMO_CORAL_LOGO (now ZZDEMO_CORAL_LOGO): 1 -> missing`.
   - Cause: removeStrings renames it NAME_n, but verifyCadRedaction counts through the old `blocks` map (cad_file_redact.ts:212-219).
   - Fix: merge rs.renamed into the map that verify uses.
4. **Merge regression.** After the merge, drawing_location.ts defers to the text branch's locationBelowEmirate, and the local gazetteer is dead code.
   - ARJAN (missing from both lists) and DEIRA / JVC (need a "Location:" cue, which a drawing label never has) stop being places.
   - 2 tests fail; v03 is released with "ARJAN".
   - Fix: union the two answers (`locationBelowEmirate('Location: ' + t)` OR GAZ_RE) and add Arjan to identity_places.
5. **The model never sees past character 200** (drawing_string_reading.ts:52, `slice(0,200)`).
   - A general-notes MTEXT line of 240 characters ending "…SITE CONTACT MR ZZ DEMO KAREEM … NEXT TO THE SPINNEYS": the model reads up to "SITE CONTACT MR".
   - In my run the floor caught the rest; a name with no cue would stay.
   - Fix: split long strings into ≤200-character pieces and remove the whole string if any piece is marked.
   - Also: pure numbers ("6512", a plot number on its own) are never sent to the model.
6. **False holds, item 11 left half-fixed.** verifyCadRedaction still joins strings with "\n".
   - On 20 ORDINARY drawings with no identity: CAD file HELD 4/20 (street_address / firm_en across joined lines), vector PDF HELD 2/20.
   - The PDF preview also loses "PLOT BOUNDARY" (8 times; he says it is kept, but that is true on CAD only), plus "STAIR 2", "RAMP 1:8" and "LEVEL 2" on 5/20 sheets.
   - CAD preview: 0 losses. DXF and CAD previews on my 3 quoting sheets: 83/83, confirmed.
7. **The floor should cover what it detects.** "Rows of text drawn as shapes" inside a strip band with a frame (v02) are counted, not boxed. Fix: box them inside the right/bottom edge band; elsewhere, lower confidence as now.
8. **Two string reads per CAD file, not one.** Mode 'cad' and mode 'file' each call readCadStrings, and the portal and WhatsApp call both. Cache: model_policy.cache_ttl_min is 0 for redaction_detection, and ai_cost_log keeps only a prompt hash, so the strings are not stored in clear.
   - read_strings runs on max_tokens 1200: a long identity list truncates → held.
   - Not in the pixel budget.
9. **Smaller items.**
   - Stale comment at index.ts:~630 ("OCR worker does not run while Actions is off").
   - Layer-name case: an entity on "a-owner-albarsha" was renamed "4" while the table's "A-OWNER-ALBARSHA" became "1" (the file still parses; AutoCAD makes the layer).

### Gate logic (2)
Every write I found goes through a recorded run that passed the gate:
- `drawing_redacted_paths`: documents.ts → drawing_hold.ts (complete runs only); wa_inbound:134; inquiry_create:265 (from the composer); the worker's publishPages after `gate`.
- Signing: drawing_pages, recorded paths only.

How the loop and the answers behave:
- Re-ask loop: round 3 not clean → held. A painted-then-clean page is published (previews only; files need the first look).
- Malformed answer, boxes off the page (clamped to nothing), "unsure" or "addressed" → held.
- Injection: the system prompt says the page is evidence. On text-layer pages, instructingRuns are covered before the model looks; on outlined or scanned pages only the model's obedience protects. "addressed: true" holds.
- Model hold or no key → every route held.

Budget:
- 122 calls per **storage path** per 24 h. A re-upload gets a new path and a new budget (a cost cap only).
- Pages over 20 are never rendered (MAX_DRAWING_PAGES).
- A page past the budget → `pixels_budget` → the set is held all-or-nothing. The customer gets the general held text, with no budget wording.

### What each format gets (5)

| Upload | main today | after this branch |
|---|---|---|
| Vector PDF (portal) | code-boxed preview, no model; vector file if verified | preview after the pixel gate; **file always held** until verify_file is wired |
| DXF / small DWG (edge) | allow-list preview; DXF with L1 leaks | string read + gated preview; file on a first-look gate |
| Large DWG | routine, code only | routine → edge string read + gate |
| Scan / photo | held (OCR worker holds every test sheet) | **published if the find model and a model of another family agree; no code floor** |
| WhatsApp PDF | held | held (file mode only) |
| WhatsApp CAD | CAD preview (+ file) | the same, gated |
| WhatsApp photo | not offered to suppliers | not offered; now said |

**The three NOT CLOSED items.**
- The vector-file wiring is not a blocker: the file stays held and previews go.
- The confirm step is product, not anonymity.
- The scale bar cut whole is a content loss.

**Interface the portal needs** (customer_api action `verify_released_file`):
- In: run_id (an `awaiting_pixels` run the customer owns), plus the pages of the PENDING file, which the server signs and the browser downloads.
- The browser renders them with pdfRaster.rasterisePdf (annotations off) and sends `{ images[] }` with `page_count`.
- The server checks count, aspect and ink against pdfPages of the pending file, then calls `verifyReleasedFile`.
- Out: `{ path }` or `{ held, reason }`, shown to the customer.
- Who: the sales_engineer (customer_api plus NewRequest's confirm step, which shows the customer the exact pages).

### Runners (6)
I was WRONG to say the scan route never runs.
- list_triggers shows "QuotesDone — CAD read worker (every 2 h)", cron `15 */2 * * *`, enabled; last run SUCCEEDED 08:16:03–08:16:41 UTC today. It runs `scripts/cad_read_worker.ts`.
- The repository proves only the comment at customer_api/lib/drawings.ts:70-84 and CAD_READER_EVERY_MS, and that nothing dispatches Actions.
- On this branch the worker reads the strings and gates every page through edge mode 'gate'. It needs `cred_fn_customer_api` from app_secrets.
- Edge: DXF, small DWG (LibreDWG wasm), PDF previews, and now scans and photos on the model path.
- Also wrong in my first review: suppliers ARE told a drawing exists (supplier_api `drawing_withheld`, since 22 Sep).

### The e-mail pattern (7)
`boq_from_text.ts:38` takes 1.68 s on 50 KB of "Al-…" and 0 ms with his pattern. But his `{1,64}` with the lookbehind leaves an address with a 70-character local part WHOLE. The lookbehind alone is O(n) and removes it. It is the text/doors author's file, not this branch's.

### Mutants (8)
His suite catches 3 of my 6:
- caught: "no answer = clean", "clean ignores regions", "readerStrings returns nothing";
- missed: "file accepted after re-checks", "a bad strings index ignored", "too many strings read as content".

### Cost per set (from the code)

| Drawing | Calls | USD |
|---|---|---|
| Vector PDF, 20 pages | 20–60 preview calls + 20 file calls | 0.36–0.72 |
| CAD drawing | 2 string reads (gpt-6-luna-pro, size-dependent, not capped) + 1–3 preview calls + 1 file call | about 0.03 + strings |
| Scan or photo, per page | 1 find call + 1–3 gate calls | about 0.02–0.04 |

Cap: USD 1.10 per upload path.

### Tell the founder on Monday
1. From this branch on, no drawing reaches a supplier unless a second AI model has looked at the exact page and found nothing.
2. While the AI models are on hold or out of credit, **no drawing goes to any supplier at all**: the request goes without it, and both sides are told.
3. A PDF drawing goes as checked page images, not as the PDF file, until the portal step is built.
4. CAD drawings keep every quoting note (83 of 83).
5. Scans and phone photos can now go, but they rest on the two models alone. On large A1 sheets the small title-block text is too small for a model to read, so a model can miss it.

## REPLAY GUARD AND ACCEPTANCE 1
Branch it_engineer-a-suppliers-certificate-is-written-in-time-and-never-silently-lost @4685d455f (3 commits on main 35f9cec60), 13 Nov 2026. Nothing was rehearsed on production. [L] local Postgres 16 built from the mirror at /tmp/pg-review-guard:55461 (deleted), [R] reading, [S] light SELECT on production.

VERDICT: FIX. The product fixes hold. The guard stops the exact file shape of 13 Nov, but it still lets most other lock shapes hold a live table for up to 120 s. The pending SQL's probe can never answer PROBE OK on the production schema.

1. replay_guard.mjs:51-91, misses that repeat the incident [L]. maskSql blanks quoted names and dollar bodies, so all of these PASS with a 120 s hold:
   - `alter table "public"."quotes"`, and `drop policy/trigger "a b" on quotes`;
   - DDL in a DO block or EXECUTE, or in a function the file then calls. The committed idiom `do $$ if not exists(pg_constraint) then alter table public.customers add constraint` (3 files) was refused only because of other lines;
   - `drop index` (AccessExclusive on the table [L]);
   - a new table with `references quotes` (ShareRowExclusive on quotes [L]);
   - `create or replace view` (AccessExclusive on the view [L]); refresh materialized view;
   - the 2nd table of `truncate a, quotes` or `lock a, quotes`; storage.objects; auth.users.
   - `create table if not exists <existing hot table>` exempts that table. Committed the_it_engineer_hands_the_founder_a_session_he_can_start_from.sql PASSES with CREATE INDEX and ENABLE RLS on it_engineer_finding.
   - 88 committed files that PASS do UPDATE/DELETE on hot tables: row locks held for up to 120 s.
   Correctly passed: create or replace function, grant/revoke (no table lock [L]), comment (ShareUpdateExclusive [L]), create index concurrently. Over-refused: validate constraint, lock table … in access share mode (harmless).
   Measured queue [L], live reader C with statement_timeout 8 s:
   - old, no lock_timeout, behind a 15 s read: C cancelled at 8.04 s;
   - guard (lock_timeout 1 s) behind the same read: C waited 0.83 s;
   - acceptStall, cut at 5 s: C waited 4.65 s and survived;
   - quote_items ALTER + 12 s probe (not in the list, 120 s): C cancelled at 8.03 s;
   - DO-block ALTER on quotes + 12 s probe: C cancelled at 8.04 s.
   SMALLEST FIX: cut EVERY production replay at 5 s (transaction_timeout 5s, not 120s). That bounds every miss, row locks included, below 8 s whatever the regex sees, and anything longer is rehearsed locally. Keep the regex only as the early refusal.
2. replay_guard.mjs:38-43, the hot list is stale on day one [S, pg_stat totals].
   - 3 of its 24 names are not tables: quote_lines, login_otp, conversation_turn.
   - Missing tables on live paths: quote_items (427 K reads, the quotation path), it_refusal_policy 11.6 M, sales_knowledge 9.3 M, model_registry 7.0 M, it_hold_signature 6.9 M, decision_policy 2.0 M, seat_duty, wa_messages, supplier_score, inquiry_matches, storage.objects.
   Recommendation: drop the list. The rule should be "any lock stronger than RowExclusive on any existing relation", read from pg_class once before sending; item 1's 5 s cut makes this safe.
3. The pending probe never passes on production [S: customers.is_demo attgenerated='s'; L].
   - probe:8-12 inserts is_demo, which is a generated column: "cannot insert a non-DEFAULT value".
   - probe:22-26 builds `'PROBE FAILED…' || r1` (text || jsonb resolves to jsonb): "invalid input syntax for type json" on every run.
   - With both fixed (drop is_demo; add r1::text and the like), the run through his own rehearse_sql.mjs with QD_LOCAL_DB_URL gives PROBE OK. His committed probe fails the same way.
   - Mutants: caught = re-sign twice within 5 min, and a signed customer re-signed. Survive = demo counted as real, the finding re-keyed every hour, a customer with no acceptance re-signed, escalation never fires (>=300), escalation row duplicated.
   - Fix: add three fixtures: 3 prior auto_done rows (expect escalated 1, then 0); tos_accepted_at null (expect posted 0); a demo-only gap (expect real 0).
   - The file itself is clean: grants per signature, search_path pinned, no table, and pg_cron never overlaps a job. Lock table for the real apply [L]: cron.job, cron_registry and writer_seat at RowExclusive only, and the guard passes it.
4. apply_sql.mjs:265-283 is not behind the guard.
   - It sends one POST with no BEGIN/COMMIT, so the file runs as one implicit transaction and a lock timeout rolls all of it back [R]. Retries: 10 s fixed, 6 tries, only on a lock timeout.
   - It sets no statement or transaction timeout. A file's own later `set lock_timeout` wins over the 2 s: 3 s in two of the week's files, 15 s in one committed file. A backfill (`update public.quotes`, `update public.transactions` on this week's branches) holds its locks unbounded.
   - Fix: run tightenLimits with a 2 s cap in apply too, and add `set local transaction_timeout='60s'` when stallsLiveUsers is non-empty.
   - The 5xx re-send of a whole file is in dbPost (pre-existing, 7 tries).
5. safe_replay.mjs:152 passes opts through to db.mjs sql() with retry=true. If the session that transaction_timeout terminates comes back as a 5xx, the replay is re-sent up to 7 times, each holding up to 5 s. (Inferred: not tested on production, by rule.) Fix: force retry:false on the production path.
6. The default is still production. npm-test with a token runs 8 rehearseChain checks plus replaySql checks on production (now behind the guard). daily canonical_routine_manifest --all and the parity steps read production; I found no other DDL replay in them [R].
   - About 40 scripts (scripts/kb, scripts/agents, scripts/load) POST to database/query directly and bypass the guard.
   - Fix: replaySql refuses production unless `target:'production'` or QD_REPLAY_ON_PRODUCTION=1 is given, and the local DB becomes one script (commands below).
   - The advisory lock is fine: it is transaction-scoped, freed when the holder dies, and the file's own advisory waits are bounded by lock_timeout 1 s. It does not serialise apply_sql.
7. supplier_api/context.ts:22-25: `cause` can carry personal data into agent_runs. 233 committed `raise exception … %` messages name an email, phone or name. Fix: replace emails and phone numbers in `cause` before annotate.
8. kyc/index.ts:30-41: termsNotRecorded awaits the finding RPC after up to about 27 s of retries. Behind the same lock that is another 8 s, which is past the customer page's 30 s abort, so he sees err_timeout instead of the sentence. Fix: waitUntil the RPC.
9. tightenLimits does not catch `set lock_timeout to default`, `reset lock_timeout`, `reset all` or set_config(…). No committed file uses them (low).
10. spec_fill (workflow.ts:463-471, 552-557) works for a sequential re-press. Two tabs, or a double submit in flight, both see notified_at null and both deliver (as before: there is no compare-and-set). If the 2nd updateHold fails after a delivery, the next press delivers again. Fix: update the hold from not-awaiting to awaiting, returning id, before deliver (not a blocker).

PRODUCT, verified:
- The retries are idempotent: the same values within one request, and a compare-and-set in compliance_archive.
- The customer's ProfileGate on 503: busy cleared, it stays on the step and shows message/message_ar ([L] scratch errText test, EN+AR, removed afterwards).
- The supplier's ProfileForm on 503 shows terms_cert_failed and stops. A timeout at 20 s goes on, by design.
- The acceptance IS enforced on the server: create_inquiry requires tos_accepted_at (customer_api/actions/inquiry_create.ts:101), and a supplier's quote requires accepted_terms_at (supplier_api/actions/quotes.ts:213). Not a blocker. No other edge function inserts inquiries.
- supplier_api accept_terms (profile.ts:78) answers a lock blip as a generic 500: put it through writeRecorded too.
- Missing tests: (a) kyc handler with customers.update answering 57014 three times, expecting 503 terms_not_recorded and no certify call; (b) a ProfileGate source test that `terms_not_recorded` never calls onDone.

SUITES: Deno, branch (kyc, compliance_archive, supplier_api, _shared): 2536 passed, 0 failed, 1 ignored. Merged locally with nothing-below-the-emirate, what-a-supplier-receives and a-paid-request: no textual conflict; kyc+compliance_archive+supplier_api+line_specs 399/0; deno check of the 3 functions OK. tsc exit 0. Node checks: replay guard 7/0, acceptance 4/0, rehearse_this 9/0. No test was weakened: the expected prefix regex was updated, and is stricter.
OPEN BRANCHES (guard): the 4 main files are REFUSED on production, so the operator rehearses them locally and applies with apply_sql. Notes per branch:
- accountant: sets 3 s; update transactions;
- the_it_engineer_closes_every_loop_it_opens: non-concurrent index on agent_actions;
- sales_engineer: update quotes;
- ceo: sets 3 s; its 3 index files are CONCURRENTLY, pass, and apply alone.

LOCAL DB (worked; to become scripts/db/local_pg.sh):
  mkdir -p /tmp/pg-X && chown postgres /tmp/pg-X
  su postgres -c "/usr/lib/postgresql/16/bin/initdb -D /tmp/pg-X/data -A trust -U postgres && /usr/lib/postgresql/16/bin/pg_ctl -D /tmp/pg-X/data -o '-p 55461 -k /tmp/pg-X' -l /tmp/pg-X/pg.log start"
  node scripts/db/local_from_mirror.mjs --sql-only=/tmp/pg-X/schema.sql
  psql -h /tmp/pg-X -p 55461 -U postgres -f standins.sql   # roles; schemas extensions/auth/storage/cron/net/vault; pgcrypto+uuid-ossp in extensions, pg_trgm; auth.users/uid/role/email/jwt; storage.objects/buckets/foldername; cron.job/schedule/unschedule/alter_job; net.http_post/http_get/_http_response; vault.secrets/decrypted_secrets (file: scratchpad copy rg_standins.sql)
  sed -E '/CREATE EXTENSION IF NOT EXISTS (pg_cron|pg_net|supabase_vault|vector|pg_stat_statements|pgcrypto|"uuid-ossp"|pg_trgm|plpgsql)/d; s/\bvector\([0-9]+\)/real[]/g; s/public\.vector\b/real[]/g' /tmp/pg-X/schema.sql > /tmp/pg-X/local.sql
  for p in 1 2 3 4; do psql -h /tmp/pg-X -p 55461 -U postgres -q -f /tmp/pg-X/local.sql >/tmp/pg-X/pass$p.log 2>&1; done
    # 808 tables, 2175 routines, 374 policies, 403 triggers, 110 cron jobs all inactive; left out: 27 vector routines, 16 hnsw, seat_exam_item
  seeds for probes: app_secrets cred_db_internal + project_ref (dummy); org_role + org_agents rows for each seat (FK + addressee trigger)
  QD_LOCAL_DB_URL='postgresql://postgres@%2Ftmp%2Fpg-X:55461/postgres' node scripts/ci/rehearse_sql.mjs <file> <probe>
  The local DB is Postgres 16, which has no transaction_timeout.

RELEASE ORDER:
  1. Items 1, 2, 5, 6 (the 5 s cut on every production replay; local by default) before anyone rehearses again.
  2. Fix the probe (item 3); rehearse it locally.
  3. Merge; deploy kyc, compliance_archive, supplier_api.
  4. apply_sql the pending file with its MANIFEST line (RowExclusive on cron.job, cron_registry and writer_seat only).
  5. Then the three open branches' files: local rehearsal, then apply_sql.
AFTER MERGE: count terms_not_recorded:* and certificate_not_recorded:* findings and the agent_runs `cause` values daily for a week. Items 4, 7, 8, 10 and the supplier_api accept_terms retry are follow-ups.

## ANONYMITY RELEASE (TEXT + DOORS) FINAL
Final release review of origin/sales_engineer-anonymity-text-and-doors-released-together at 1f450d57d (origin/main 35f9cec60 + F1 f8086debc + F2 ad932e645), 13 Nov 2026. Offline only: worktrees /tmp/claude-0/review-rel-anon and review-rel-base (origin/main), both removed. A throwaway local Postgres 16 with stub tables was used for the SQL, then removed. Nothing ran against production except the address-key check's own SELECT half. Drivers and outputs: scratchpad/relrev/ (ph.ts, fresh.ts, over.ts, corpus654.ts, c3.ts, amerged.ts, p_l40.ts, p_l60.ts, new30.ts, old.ts, old2.ts, hl.ts, graph.mjs, trial_fixes.diff, suite_*.txt, fix_*.txt, x_*.txt).

VERDICT: FIX items 1 and 2 (both are in code that is new in this release, and both break "an old supplier never reaches new suppliers"). Item 3 goes in the same round. Then MERGE.
1. The old supplier's name, written without its legal form, reaches every matched supplier, including the new-inquiry e-mail headline.
   - Where: supplier_api/what_a_supplier_receives.ts:62 (requestSeeds) and drawing_boq/quotation_gate.ts:176-180 (termsToKeep keeps only the maximal name).
   - Input: termsToKeep(quotationTerms(["Noor Interiors LLC", …])) gives ["Noor Interiors LLC", refs]. Then:
     - summary "Tiling works as listed in the Noor Interiors quotation" (briefSource quotation) gives the e-mail "A customer is requesting quotes for: Tiling works as listed in the Noor Interiors quotation (Dubai)."
     - "noor interiors was too slow" passes unchanged.
     - "Blue Lagoon Contracting LLC" gives "Blue █ Contracting".
     - "Qasr Al Fan Decoration L.L.C" gives "Qasr Al Fan █", and the trade word "Decoration" itself becomes a seed.
   - Smallest fix: in requestSeeds, also seed each old term with its legal-form tail removed (llc, l.l.c, fze, fzco, fz llc, est, co, company, trading, ltd, wll, plc) when two or more words remain. Tried locally: closes all of these, and the e-mail reads "…in the █ quotation". Plant the rows.
2. The old supplier's prices pass quotationGate when written in Arabic-Indic digits or as "dirhams".
   - Where: drawing_boq/quotation_gate.ts:32-33 (CUR, NUM `\d` = ASCII only) and :113 (`/\d/` filter).
   - Input: BOQ descriptions "Porcelain tiles 60x60, ١٢٠ درهم للمتر", "Tiles at 120 dirhams per m2" and "Grout, rate ٤٥٫٠٠" come out unchanged on our inquiry. quotationProse also keeps "السعر السابق ٣٨٥٠٠ درهم" and "120 dirhams per sqm".
   - Smallest fix:
     - CUR += `[Dd]irhams?`
     - NUM = `[\d٠-٩۰-۹][\d٠-٩۰-۹,٬]*(?:[.٫][\d٠-٩۰-۹]+)?`
     - :113 filter `/[\d٠-٩۰-۹]/`
   - Tried locally: all 3 lines become "Porcelain tiles 60x60, للمتر" / "Tiles at per m2" / "Grout".
3. A supplier's phone in a TAB-separated row next to a price crosses to the customer.
   - Where: _shared/identity_text.ts:41 (NO_GROUP_AFTER). capBlanks only handles runs of 3 or more.
   - Input: "Sales contact\t050 123 4567\t12,500.00" is unchanged on save, at the customer door, in Q&A and in redactText. The same happens with a single NBSP, and with a single space (that one by the BOQ guard's design). The inbox withholds it.
   - Pre-existing: origin/main gives identical output, so this is not a regression. It is the commonest paste (Excel or TSV).
   - Smallest fix: `(?!${D})(?:(?=\t)|<the two existing look-aheads>)`, so a tab ends the number. Tried: closes it.
   - With all 3 trial fixes applied: _shared 2285/1 (tesseract only), supplier_api 275, drawing_boq 99, customer_api 98, messages 5, quote_extract 71, inquiry_intake 120, supplier_portal 53. Fresh 60: 0 changed. The 654 corpus is unchanged. Probes C 2, A 0/62, l40 1, l60 1. The diff is in relrev/trial_fixes.diff.

(1) BLOCKERS, verified on the combined tree
- "Sales contact    050 123 4567    12,500.00": every door removes it. Save gives "Sales contact  [removed]  12,500.00". Door, inbox and e-mail line give "Sales contact [removed] 12,500.00". Q&A and redact remove it too.
- Variants: 2 spaces CLOSED, 2 tabs CLOSED, 3 NBSP CLOSED. 1 tab LEAKS and 1 NBSP LEAKS (item 3, both on main too). A leading indent is kept: "    Tel  [removed]  2  nos".
- Drawing option:
  - "ARJAN" alone: text [] / drawing ["ARJAN"]. "MEADOWS" and "DEIRA" alone: drawing only.
  - "LOCATION: ARJAN, DUBAI" counts in both modes. A title-block line "AL BARSHA" counts in both.
  - "Arjan model chair" and "ARJAN MODEL CHAIR": never counted.
  - No caller in this release passes {drawing:true}. drawing_location.ts is F3's and is not in this release, so blocker 2 is latent here. F3 must call it when it lands.
(2) OVER-REDACTION
- 60 fresh sentences (48 EN, 12 AR; HVAC, tiling, joinery, IT, solar, catering, rebar…): 0 wrongly changed. Q&A turns ٠-٩ into 0-9 in 6 Arabic rows, with the same values; origin/main does the same.
- 654 corpus with Falcon Trading / Omar Haddad: only "Falcon grey" x2 under the supplier's own name (save and door), plus the decided villas row. With Blue Star Technical Services / Fatima Al Mansoori: only the villas row. The 9 #arguable rows are as the test decides.
(3) LEAKS
- C 46 at the customer door: 2 ("Contact Rashid Khan", "Falcolux"), both on the second-reader list.
- A 31: 0 of 62, with and without a stored site.
- Predecessor 60: 1 (Cedre Villas). Predecessor 40: 1 (Khannour).
- My 30 new probes:
  - CLOSED, customer to supplier (C2S): Mudon; Al Furjan; Mirdif + City Centre; access "behind Arabian Ranches"; "Al Khail Road side"; stored project; phone in words; spaced e-mail; Arabic owner labelled and in prose; Plot 6457-321; GPS; JVT District 4; Ibn Battuta Mall.
  - CLOSED, supplier to customer (S2C): Al Quoz showroom; DIP Unit 12; phone in words; spaced e-mail; "Falcon team"; coordinates; Plot 597-1234 Jebel Ali; Arabic labelled person + phone; القصيص office.
  - LEAKS on the known list:
    - "الدخول من جهة الورقاء" (bare community, no cue)
    - "Oasis Heights project" (unlisted project)
    - "thirty-eight thousand dirhams" (words)
  - LEAKS, NEW:
    - old supplier name without legal form (FIX 1)
    - "120 dirhams per sqm" (FIX 2 on the quotation path)
    - tab phone row (FIX 3)
    - "the last contractor quoted AED 38,500" in a customer's free text or clarify answer. The code makes no claim here outside quotation prose (forSuppliers does not apply forSource). Add it to the second-reader list.
  - Grammar only: "Warehouse on Dubai", "[removed] [removed]".
(4) TIMING
- The adversarial test passes in 19 s.
- review_cpu_budget, run 3 times while the _shared suite and another session's deno test were running (load 2.5-3): 284 / 306 / 408 ms against 1,200 ms.
(5) SUITES, combined tree
- deno: customer_api 98/0, drawing_boq 99/0 (1 ignored), inquiry_intake 120/0, messages_api 5/0, quote_extract 71/0, supplier_api 275/0, supplier_portal 53/0.
- _shared 2285/1 (1 ignored). The only failure is catalogue_read.test.ts:107, a tesseract wasm read permission; it fails the same way on origin/main.
- Bundle importers also run: drawing_redact 7, quote_compare 7, wa_inbound 228, resend_inbound 42, reveal_invoice 14, all 0 failed.
- tsc exit 0.
- node checks: what_a_supplier_receives 5/5, a_supplier_sees_only_its_own_match 30/30, nothing_a_supplier_reads_can_be_arabic 155/155, a_drawing_read_is_not_cut_off 3/3, address-key 2/2 (production SELECT half included).
(6) SQL, before_a_reveal_a_supplier_portal_title_is_the_trade_and_the_emirate.sql: routine replacements only.
- Run on local PG16 stub tables inside BEGIN…ROLLBACK, with pg_locks read for the session:
  - CREATE OR REPLACE fn_supplier_workspaces: AccessShareLock on inquiries, inquiry_matches, messages, transactions, documents, quotes (body validation); RowExclusiveLock on pg_proc and its toast.
  - CREATE OR REPLACE fn_supplier_opportunities: AccessShareLock on leads, supplier_capabilities, inquiries, inquiry_matches, transactions, quotes.
  - 2 x REVOKE: pg_proc RowExclusiveLock only.
  - Nothing above AccessShare on a user table, so it waits only behind an ALTER TABLE, VACUUM FULL or DROP. Keep apply_sql's lock_timeout.
  - SECURITY DEFINER and search_path public, pg_temp are kept.
  - Stub output: unrevealed "Fitout work in Sharjah · Job 160501", "Job file (drawing)", requirement and estimated_value null. A revealed row keeps the summary.
- ORDER: either order is safe.
  - Old function + new routine: the old function passes the routine's output through, and that output is already safe.
  - New function + old routine: before_reveal.ts overwrites the title, file names, requirement and value for every inquiry without revealed_at.
  - Recommended: deploy supplier_portal first, then apply, then run the probe (PROBE OK), add the MANIFEST line and delete the pending note.
(7) DEPLOY LIST: 22 functions, from the static and dynamic relative-import closure of each index.ts against the 39 changed source files:
- accountant, customer_api, doc_extract, drawing_boq, drawing_redact, inbound_email, inquiry_intake, license_extract, messages_api, public_site, quote_compare, quote_extract, resend_inbound, resilience_ping, reveal_invoice, sales_engineer, stripe_checkout, stripe_confirm, supplier_api, supplier_catalog_ingest, supplier_portal, wa_inbound.
- deploy_functions.mjs widens any _shared change to all 76 functions whose index.ts names _shared/. That is a superset, and it is safe.
- verify_deploy_parity compares every first-party module in the deployed ESZIP, so any of the 22 not redeployed shows STALE.
(8) WHAT USERS WILL NOTICE IN THE FIRST HOUR
- Customer:
  - Uploading another supplier's quotation, the chat says: "This is a quotation from another supplier. I have rebuilt it on our own inquiry for the suppliers: N items, with no prices, no names and no reference numbers of the old supplier. Its pages are not shared."
  - A priced file: "Your file carries prices. Its N items go to the suppliers with quantities and specifications; the rates in your document are not shared."
  - Any other file: "From your file I understood N items."
  - These are followed by "What I understood: …", a numbered item list, and either "It is enough for a supplier of this trade to quote from." or "It is not yet enough to quote from: a supplier would still need …. I will ask you about these; you can also say "send it as it is", and the suppliers are told what is not known."
  - A note or answer that names his site or contact: "The part naming your site or your details ("…") is kept with your request and not sent to the suppliers. Write the rest without it and send again if they need it; your exact site goes to the supplier whose quotation you open."
  - Edit refused:
    - "This description cannot be sent to the suppliers as written because of "…". Take that out and describe the work: the suppliers see the emirate, and your exact site goes to the supplier whose quotation you open."
    - "Choose one of the seven emirates."
    - "We could not check this text for your own details just now. Please try again in a moment."
  - In supplier quotations and the compare sheet, a supplier's area becomes the emirate ("Visit our showroom in Dubai", "Warehouse on Dubai"). Gaps of 3 or more blanks print as 2. A supplier called Falcon loses "Falcon" from "Falcon grey": "[contact hidden until reveal] grey".
- Supplier:
  - Portal titles before a reveal read "Fitout work in Sharjah · Job 160501". Files read "Job file (drawing)". Opportunities show no requirement and no estimated value.
  - Inbox and e-mail: "Renovation of two bathrooms in Dubai"; "[site details withheld]" when the site has no emirate; the e-mail falls back to "Bathroom renovation work (Dubai)".
  - A kept note reads "The customer added details about the site, which are released when the customer opens your quotation."
  - A kept answer reads "The customer answered. The site details in the answer are released when the customer opens your quotation; price on the emirate and the request, and state any assumption."
  - A quotation-built inquiry has the section "Items to quote" and the note "The customer already holds a quotation for this work from another supplier. Its items, quantities, units and the makes it specifies are listed here on our template; that supplier's prices, name, references and pages are not shared. Quote your own price for each line."
  - Its e-mail says "The items of the customer's existing quotation are listed on our inquiry: no prices, no names, no references of the old supplier."
  - New labels: basis "As listed in the customer's document"; "Not stated: confirm the quantity"; "Specified: <make>" on RFQ rows; "Site: <site>" on revealed projects.
  - "villas no. 40 to 45 on the drawing" reads "[removed] on the drawing".
RELEASE STEPS
1. Items 1-3 with planted rows. Re-run the 654 corpus, C, A and the 30 probes in relrev/new30.ts.
2. Merge via PR. Run the local gate (npm run gate).
3. Deploy the 22 functions above (supplier_portal included).
4. apply_sql the title file with --ddl. Run the probe (PROBE OK). Add the MANIFEST line and delete the pending note in the same commit.
5. Run verify_deploy_parity for the 22 functions.
6. In the first hour, read one live supplier inbox and portal page and one customer quotation PDF.
AFTER MERGE
- forSuppliers should apply forSource on quotation-built requests (clarify answers and notes that state the old price).
- termsToKeep should not seed a trade word ("Decoration").
- F3 must call placeSpans with {drawing:true}.
- Second reader: add "an old price in a customer's free text".

## WORKFLOW W1 MONEY 4 (FINAL)
Final review of origin/accountant-a-payment-is-known-booked-and-timed-from-the-moment-it-is-paid @ 5747d5f62, 13 Nov 2026. Worktree /tmp/claude-0/review-w1-final, LOCAL Postgres 16 at /tmp/pg-w1-final:55481 (both removed). Tags: [L] local database, [R] reading, [S] light SELECT on production (only: quotes metadata, 3 ZZ DEMO fixture rows, reference tables, routine ACLs, default ACL). Nothing rehearsed, applied, deployed, merged or pushed; no Stripe or model call.

VERDICT: FIX. The books, the window, test/live/unknown mode, one journal per event and the CEO hand-back all hold under execution. Five defects remain; the first tells a real customer something false before the refund exists.

### FIX, most harmful first
1. **An overcharge return e-mails the customer "We have your refund request ... you get back everything you paid" the moment it is approved, before Stripe** (main :904 → live trigger z30_refund_request_hands_to_accountant → refund.requested → fn_accountant_acts_on_handoff → refund.request_checked → fn_sales_engineer_acts_on_handoff writes refund_request_received). [L] non-demo customer: delivery.request to the customer while the refund is 'approved', no stripe_refund_id; one more per retry (S4b: two). The probe never runs the hand-over queue, so it cannot see it. Fix: redefine fn_refund_request_hands_to_accountant in the main file with `and NEW.reason_code is distinct from 'overcharge_return'`; probe: run fn_seat_handoff_act on every open hand-over of the payment and assert no customer delivery.request before stripe_refund_id.
2. **The 1150 file reverses itself on a second apply** (the_company_recovers…sql:40). The loop picks its own vat_input_reclass journals (they carry 1150 lines). [L] applied twice: 54 reclass journals, 1150 back to 284.41, its probe PROBE FAILED. apply_sql re-sends a whole file after a 5xx, so one lost response undoes it. Fix: `and j.source <> 'vat_input_reclass'` in that WHERE.
3. **A sale refunded in full before Stripe's figures is later booked as revenue** (main :449, :599, :1934). [L] S13: closes as nothing_to_book (correct), 1b books an ESTIMATED Stripe fee 6100/1050 23.55 (real 34.48); then the figures arrive and a dispute reopens the check: the reconcile posts Dr 1050 743.12 / 6100 34.48 / Cr 4000 777.60 on a fully refunded sale: revenue +777.60, 1050 off by 754.05. Fix: the refund branch of fn_reveal_nothing_to_book = "refunded in full and no reveal_fee journal" (drop `stripe_fee_fils is null`); fn_gl_post_reveal_fee returns null when that holds; 1b's unbooked branch books Stripe's own fee only and waits while it is unknown. Add the probe (mutant M14 survives).
4. **A guard refusal of the return is not handed back** (main :904-908 are outside the begin/exception at :912). [L] S4d: a00 raises (overcharge_return_names_no_stripe_reference) → fn_reason_apply_ceo__payment_exception raises: no blocked task, the CEO's hand-over stays pending, the decision is lost. Fix: move :904-908 inside the block.
5. **The local gate is red**: every_alarm_is_quiet_on_a_healthy_day fails on fn_accountant_reconciles_reveal (raises reveal:sale_notice_failed, not in REGISTER) [R/offline]; add a relay entry at :374. The sweep's "a healthy day has neither" is false from 4 Dec 2026: calendar:public_holidays_running_out fires whenever public_holidays reaches < 365 days ahead (last date 2027-12-03).
6. **Smaller.** (a) A blocked task is never closed when the CEO decides again (S4b: 112 stays 'blocked' beside the new 113): close it in fn_payment_check_returns_difference. (b) [L] deadlock: fn_accountant_payment_check_snapshot (:765) locks the check row then the invoice advisory lock; the webhook's reconcile takes them the other way. Data stayed right (1 journal, 1 number); take the advisory lock first. (c) A Stripe-dashboard refund is never booked: fn_refund_settle writes it with no transaction_id and 1b joins on it (:1935) [L S6, AED 100 partial]; match `or (f.transaction_id is null and f.stripe_payment_intent = t.payment_ref)` in 1b and in nothing_to_book. (d) fn_handoff_redact: two keys that both redact to "[phone]" collapse (one value dropped); "00 971 50 123 4567" is not redacted; "PO 0012345678" is. (e) A zero-fee reveal takes a QD-INV number. (f) The grant file has no lock_timeout, although the runbook says it has.

### Verified [L]
- **Applies:** main → owner → index (alone) → redact → 1150, twice in a row: no error. Probes: main PROBE OK (with the third ZZ quote 3f0e7209 seeded; section D needs it), redact PROBE OK, 1150 FAILED after the second apply (FIX 2).
- **Journals by hand, all balanced, no VAT line, no 6110/2200:**
  - 777.60 domestic: 1050 743.12 / 6100 34.48 / 4000 777.60;
  - 135.00: 130.08 / 4.92 / 135.00, sale.made month_total "135.00", no crash;
  - international: 744.70 / 32.90 / 777.60;
  - overcharge 38.77: + Cr 2300 38.77; return: Dr 2300 38.77 / Cr 1050 38.77;
  - full refund: Dr 6900 777.60 / Cr 1050; partial (linked): 6900 100.00;
  - dispute: Dr 6900 777.60 + fee 6100 55.00; won: Dr 1050 / Cr 6900 and the check closes; lost: stays with the CEO;
  - refunded then disputed: Dr 1100 777.60 + fee 55.00;
  - zero fee: nothing_to_book, CEO task done;
  - test mode, non-demo account: shadow only, ZZ-TEST number, no agent_actions, no journal;
  - live on a demo customer: booked + live_payment_on_test_identity;
  - unknown mode: waiting, no number, listed in the brief; once live, booked.
- **Overcharge end to end, non-demo:** after 45 min the CEO and the founder are told; the CEO's 'refund_difference' gives refund 3877 'approved' with no second seat and the task 'working'; on submit the task closes and the notice goes; Stripe confirms and the check closes; transactions.refund_* untouched. Failure branches: Stripe cancelled → blocked + occurrence 2 + CEO asked again; failed → blocked; decision refused (probe E) → blocked. The guard raise does not (FIX 4).
- **Replay:** duplicate and out-of-order facts, paid time, reconcile ×3, hourly read, sweep ×2, cost tick ×2, a replayed insert → 1 journal, 1 number, 1 reveal.paid, 1 sale.made, 1 receipt delivery request. Four sessions racing: still one of each, plus the deadlock in 6(b).
- **Window:** paid Fri 13 Nov 15:23 Dubai → Fri 20 Nov 23:59:59; the sentence says "20 Nov 2026 at 23:59 UAE time".
- **Mutants (15):**
  - caught by verdict: unknown booked, test posts, test numbered, live-demo unbooked, accrual, dispute fee, refund at total_charged, a10 off, window end time, second seat, early notice, failed return not handed back, unique index + lock dropped;
  - caught only by an error: notice failure undoes the books (M08);
  - survives: the full-refund nothing_to_book branch (M14).
  - No probe covers the z30 e-mail, the grants or the deadlock.
- **Grants:** fn_reveal_window and fn_reveal_clock_start: postgres + service_role only [L]. Production's default ACL for postgres is postgres + service_role [S], so no new routine reaches anon/authenticated. fn_refund_state keeps its live PUBLIC execute [S]; it is an invoker and only refund_flow calls it. RLS is on with one deny-all policy on demo_shadow_trace and accountant_reveal_payment_check.
- **Sibling 5acacfaf2:** confirmed, it fails on accepted_md5 NOT NULL. Probe lines 59-60 become:
  `insert into public.quote_quality_hold (quote_id, inquiry_id, supplier_id, flags, accepted_md5, held_at, release_due)`
  `select qa4, ia, s4, '["zz_probe"]'::jsonb, public.fn_quote_quality_content_md5(q), now(), now() + interval '24 hours' from public.quotes q where q.id = qa4;`
  With that: sibling PROBE OK, applied twice, main probe still OK. Its file also needs `set local lock_timeout = '1500ms';`, and :383-384 and :408-409 should become `create or replace trigger`.
- **deno:** stripe_webhook 11/0, stripe_checkout 11/0, accountant 53/0, reveal_invoice 16/0, messages_api 3/0, supplier_api 244/0 (run from the repo root); stripe_confirm has no tests; _shared money tests 75/0.
- **node, offline (no token, no proxy; production halves skipped):** 19 files pass. every_alarm fails 7/1 (FIX 5).

### Lock table (local timing; every file sets lock_timeout 1500ms except the grant file and the sibling)
| file | statement | table | mode |
|---|---|---|---|
| main, 82 ms | ADD COLUMN ×6, backfill UPDATE, z20 CREATE OR REPLACE TRIGGER | transactions | AccessExclusive to commit |
| main | ADD COLUMN ×2, z60 trigger | stripe_dispute | AccessExclusive |
| main | DROP/ADD CHECK, z59/z60 triggers | refunds | AccessExclusive |
| main | DROP/ADD CHECK, UPDATE | accountant_reveal_reconcile_item | AccessExclusive |
| main | CREATE UNIQUE INDEX | gl_journal, reveal_invoices | Share (blocks writes) |
| main | INSERT | seat_handoff_kind, cron.job | RowExclusive |
| owner, 63 ms | z61 CREATE OR REPLACE TRIGGER, the in-file probe | agent_actions | ShareRowExclusive (blocks writes) |
| owner | RLS on, inserts | seat_handoff_kind | AccessExclusive |
| index | CREATE INDEX CONCURRENTLY | agent_actions | ShareUpdateExclusive (alone, outside a transaction) |
| redact, 37 ms | a01 trigger, DROP/ADD CHECK NOT VALID | agent_actions | AccessExclusive for an instant, no scan |
| 1150 | journals | gl_journal, gl_journal_lines, gl_accounts | RowExclusive |
| grant | INSERT | ceo_standing_grant | RowExclusive |
| sibling, 177 ms, NO timeout | ADD COLUMN | inquiries | AccessExclusive |
| sibling | CHECK, 2×DROP+CREATE TRIGGER, DROP NOT NULL, UPDATE | quotes | AccessExclusive |
| sibling | trigger | transactions | ShareRowExclusive |
| sibling | new table | request_reveal_outcome | (new) |

apply_sql sends `set application_name; <file>` as ONE implicit transaction (a CONCURRENTLY file alone), and retries only on 429/5xx (it re-sends the whole file, hence FIX 2).

### The corrected release (runbook lines that are wrong: 72, 138, 144 run probes on PRODUCTION; 116; 148)
- **0.** FIX 1-5 merged. The sibling gets its probe lines, its lock_timeout and CREATE OR REPLACE TRIGGER. Probes are run on a LOCAL copy only.
  - Never run one on production. The main probe executes CREATE OR REPLACE FUNCTION on fn_refund_decide and fn_accountant_tells_ceo_of_sale, and writes transactions, refunds and gl rows inside a production transaction.
  - After each step only the read-only SELECT checks.
- **Timing:** not 21:30-23:30 UTC (the nightly ZZ journey) and not :08/:23/:38/:53. Start at hh:m5:10 after the pg_stat_activity read is empty. Retry 3 × 30 s.
- **Order:**
  1. main (accountant) + MANIFEST;
  2. owner (it_engineer);
  3. index alone. If `indisvalid` is false: `drop index concurrently public.agent_actions_kind_type_from_idx;` and re-run;
  4. deploy the seven functions from the merged main within minutes, then verify_deploy_parity;
  5. the sibling's SQL, then its functions, from a main that holds both branches. supplier_api is in both, so never deploy it from a checkout that lacks either;
  6. the redact owner file;
  7. the 1150 file (fixed) and the grant file (with a lock_timeout added), only on the founder's word. Before any re-run of 1150 after a 5xx, SELECT count(*) of vat_input_reclass journals.
- **A payment between the apply and the deploy [L]:** it is written with livemode NULL. It is never numbered or booked and the brief lists it as "Stripe mode not known". The receipt waits until the sweep stamps the insert time (15-30 min). At the next hourly run the new runtime reads Stripe's mode and figures and books it. A test payment by a non-demo account in that gap gets real hand-overs and a receipt, which is why the journey window is excluded.

### For the founder, in plain words
- The 3% is booked as earned the day it is paid; a later refund is booked as a cost. Alternative: hold it until the 5-day window closes. Your choice.
- Stripe's card fee is booked from Stripe's own figure. The 0.5% Invoicing fee is booked when Stripe bills it, never estimated. A dispute's fee is booked; a won dispute gives the money back.
- Money charged above the 3% is held as owed to the customer. It goes back only on the CEO's yes, with no second review. The customer is told once Stripe has it. Any failure goes back to the CEO. FIX 1 must land first: today the customer would wrongly be e-mailed that a full refund is being considered.
- A reveal refunded in full before Stripe reports its fee earns nothing. Only the fee Stripe keeps should be a cost (today it is estimated).
- Our invoice numbers are unique but may skip a number; that is allowed because we are not VAT-registered. Decide whether a free (zero-fee) reveal should take one.
- 1150: AED 284.41 of VAT we paid on expenses cannot be reclaimed, so it moves into cost. Say yes after FIX 2.
- The grant letting the accountant return up to AED 500 itself is yours alone to give.

## WORKFLOW W3 POOL 2 — second independent review of origin/ceo-every-seat-reads-one-pool-and-every-hand-over-comes-back @ eed8432be (13 Nov 2026)
Marks: LOCAL = PG16 at /tmp/pg-w3-2:55491 from the mirror + org_role/org_agents/org_reporting_edge/seat_handoff_kind/decision_policy/founder_mail_policy rows read by SELECT; READ = code; SELECT = time-bounded production read (plain EXPLAIN only). Nothing rehearsed, applied or deployed on production. No paid model call.

VERDICT: FIX. The pool's plumbing works (probe PROBE OK LOCAL, also on the money+sales+pool merge), it leaks nothing (SELECT), and the CEO now really asks a model. But the CEO's decision changes nothing anyone does, every decision is bounced straight back to him as "overdue", escalations go to the wrong boss, the daily cap does not cap re-asks, and the apply takes ACCESS EXCLUSIVE on the busiest tables. Most harmful first:

1. THE CEO'S DECISION IS CEREMONY (LOCAL+READ). main.sql:1697-1704 files ceo.decision_closed; its handler fn_seat_takes_the_ceo_decision closes it in 0 s by code (LOCAL: hand-overs 4/5/6 status done, decided_at-created_at 00:00:00) with "read_by it_engineer". No seat reads ceo_next_step or due_at; fix_now and duplicate_of carry no review_at, so fn_ceo_files_judgements (:1599-1600) never revisits them; a fix_now nobody does is never seen again. The it.finding still closes only when fn_it_loop_reverify sees the fault clear (READ), exactly as before. Smallest fix: a new kind `ceo.fix_ordered` (handler answers "waiting", originator_closes, reply_within 7 days) for fix_now/chase, so it sits in the seat's "Waiting on you" and escalates if ignored; give fix_now review_at = due_at and duplicate_of a close step.
2. EVERY DECIDED FINDING BOUNCES BACK TO THE CEO (LOCAL). After the decision, awaiting = 'it_engineer re-verification' and due is still created_at + 4 h (:1790-1800), so the next tick escalates it to the CEO and files ceo.overdue_handoff: LOCAL, 3 decisions (fix_now, accept_risk 14 days, needs_founder) -> 3 overdue questions "it_engineer owes the close ... since 13 Nov 15:26", 15 min later. 566 of 968 it.findings to the CEO in 14 days carry escalated_report_id (SELECT); the other ~40% will bounce and eat the shared cap. Fix: in fn_handoff_overdue_escalate skip rows with evidence ? 'ceo_decision' until its review_at/due_at.
3. ESCALATION GOES TO THE SENDER'S BOSS, NOT THE SILENT SEAT'S (:1809-1812). Day one (SELECT, same WHERE): 15 escalations, 5 to the founder, all "ceo.revise/ceo.root_cause/backup.remediate ceo -> sales_engineer/customer_support/it_engineer": the CEO's own staff are silent and the founder is asked to chase them, by e-mail AND, since fn_notify_founder gets level 'high', WhatsApp when admin_mfa_phone is set, every day. A silent CEO is escalated to the CEO himself. Fix: v_sup := superior of v_silent (org_reporting_edge child_role_id = v_silent); 'founder' only when v_silent = 'ceo'; level 'info'.
4. THE CAP DOES NOT CAP (LOCAL+SELECT). fn_ceo_judgement_room counts rows CREATED today (:1546-1548); fn_ceo_ask re-arms an old row (:1568-1570) without counting it. LOCAL: 60 re-asks in 12 ticks with asked_today = 0; bound 5/tick x 96 = 480 a day. Re-armed rows keep their old created_at, and fn_reason_held_due serves the oldest first, so they jump every other seat's held questions on the shared replay (2 rows a tick). The money cap uses AED 0.0106 per CALL (SELECT: 561 calls, avg 25.5k prompt tokens); a think() is a plan + an answer (+ a re-pass), so a question is 2-3 calls: AED 0.50 is really ~1.0-1.5 a day. Fix: count re-arms (stamp a rearmed_at, count greatest(created_at, rearmed_at) today); unit = cost per held question.
5. THE APPLY TAKES ACCESS EXCLUSIVE ON BUSY TABLES (LOCAL pg_locks + SELECT pg_trigger). Production has trg_company_event_dispatch, so :1931 takes ACCESS EXCLUSIVE on company_event (blocks reads too), upgraded from the SHARE ROW EXCLUSIVE taken at :1926. On ANY re-run, the three `drop trigger if exists zz_pool_link` take ACCESS EXCLUSIVE on agent_actions, seat_judgement and company_event. The order company_event -> agent_actions -> seat_judgement -> company_event(upgrade) means up to 3 lock waits of 1.5 s with event writes blocked throughout: up to ~4.5 s of stalled fn_emit/hand-over writes for each try, not "milliseconds". The runbook's lock table is wrong on both. Fix (all verified LOCAL): `create or replace trigger zz_pool_link` (SHARE ROW EXCLUSIVE only); replace trg_company_event_dispatch()'s BODY with `return null` (no table lock) and drop the trigger later in its own file; order agent_actions, seat_judgement, company_event. Then apply_sql.mjs (one implicit transaction) can apply it off-peak with lock_timeout 1500ms and a re-run on timeout.
6. THE DIGEST LOSES A LATE COMMIT FOR GOOD (LOCAL, :1331). An event with id 1001 that commits after 1002 was classed is never classed: ticks 2 and 3 classed 0, and the CEO's count stays 1. This is not self-healing (the dispatcher's 24 h lookback is). Fix: `e.id > max(event_id) - 5000 and not exists (select 1 from pool_event_class c where c.event_id = e.id)`.
7. THE FOUNDER'S OWN EXAMPLE STILL CANNOT SAY WHO (SELECT). supplier.approved is always written with actor 'system' and a payload of city/company/verified/lifecycle_stage: no approved_by. So IT always reads "the platform (automatic): a supplier was approved", even when the sales engineer verified him. It is honest, but it is not "IT knows the sales engineer verified". Fix: fn_sales_engineer_verifies_supplier sets qd.approved_by and fn_emit_supplier_approved writes it into the payload (fn_pool_who already reads approved_by; LOCAL shows "sales_engineer: a supplier was approved: Gulf Steel Trading LLC" once it is there).
8. ACCEPT_RISK HAS NO LIMIT (READ). Every finding gets the same options. A critical security or money finding can be accepted for 14 days by the seat alone, against the founder's money/destructive rule. Fix: drop accept_risk from the options when severity is critical or blast is money/security.
9. DUPLICATES ARE NOT OFFERED (LOCAL, real rows). :1618-1619 compares the first two ':' parts, so the two real findings profile_model_read_failed:156984 and :156992 (same title, same fixture brochure, 502 ai_error) are never offered as duplicate_of. Fix: also match on an identical title or the first part.
10. AN OPEN COMPLAINT CAN FALL OFF THE BLOCK (LOCAL). The timeline orders by time only. In my second run the sales engineer's customer block filled 1,192 chars with 11 lines of quote.received/rfq.created, triggers' duplicates included, and the complaint.due line was cut. Fix: open hand-overs on the subject first, then events; collapse identical lines.
11. RESOLVER LOOKUPS DEFEAT THE PRIMARY KEY (prod EXPLAIN: Seq Scan on leads 19k, support_ceo_report 5.5k, notifications). `x.id::text = …` at :978-994 and :1159-1171. LOCAL cost per row: +0.47 ms per notification event, +0.84 ms per CEO-report hand-over, +0.2 ms for a plain event; linear in table size. Fix: compare `id = nullif(..)::bigint/uuid`, guarded by a regex.
12. THE PROBE AND CHECKS MISS THE SAFETY PROPERTIES (LOCAL). My 10 mutants: only R10 (always to the founder) is caught. These survive the probe and every static assertion: R1 per-tick cap removed, R2 money cap removed, R3 24 h re-ask guard removed, R4 'ceo judgement' guard removed, R5 the supplier sees money events, R6 no rework hand-over, R7 trigger exceptions propagate, R8 the founder's daily mail not deduplicated, R9 accept_risk with no review date. Add probe assertions for at least R1/R2/R3, R7 (force a resolver error and see the insert succeed), R6 and R8.
13. Smaller:
  - The back-fill never ends: past 30 days it walks the agent_actions/company_event PK index below min(src_id) every tick (prod EXPLAIN: backward index scan with a created_at filter).
  - Findings already cleared (closed_at set, waiting for learning) are still filed to the CEO: add `f.closed_at is null`.
  - Each needs_founder item repeats in the founder's mail every day, with no way for his answer to come back.
  - A trigger subtransaction per row overflows the 64-subxact cache when one transaction inserts more than 64 events.

WHAT HOLDS:
- Trigger safety (READ): `exception when others` wraps the work, so a resolver error cannot block the row; only a cancel can. The cost is in item 11.
- Leaks (SELECT): of 24,487 hand-overs in 30 days, 0 carry an e-mail or phone in the outcome text the timeline prints. Of 101 open CEO findings, 0 carry a non-company e-mail or a phone in the evidence the prompt carries.
- Supplier and customer blocks (LOCAL): the supplier's own block shows "the account was approved" and "a quotation was received": no rival, no name, no amount, no seat. The customer's block uses neutral words only.
- Demo scope: probe M1 holds.
- Context call (LOCAL): 19-36 ms on a supplier with 60 events and 500 open hand-overs. Production plain EXPLAIN shows index scans for the waiting query, the CEO's filing and the back-fill batch.
- Seed (LOCAL+SELECT):
  - 794 rows on 303 types. Owners are producers in 40 sampled rows, and every live 30-day type is covered (5a, SELECT).
  - A re-apply keeps an edited row (5b, LOCAL).
  - Only 13 types are domain events; the rest are hand-over echoes.

FOUNDER'S TEST, PRINTED LOCAL:
- IT on the supplier the sales engineer verified: "sales_engineer: a supplier was approved: Gulf Steel Trading LLC (steel, Sharjah)". This holds only when approved_by is recorded, which production never does (item 7).
- IT on the auto-approved supplier: "the platform (automatic): a supplier was approved: Auto Approved Co (hvac, Ajman), licence not verified".
- Sales engineer on the request: "accountant: reveal.paid to sales_engineer -- answered, waiting on accountant re-verification", plus 4 quotations and "payment received".
- The CEO's day: "4 quote.received ... 1 reveal.paid ... Notable: a customer paid the reveal fee of AED 135.00 on request 2 (painting, Dubai)".
- The complaint: seen in run 1, cut in run 2 (item 10).
- Would they act differently? IT and the CEO, yes. The sales engineer, only if the complaint survives the cut.

THE CEO PROMPT (3 real open critical findings, SELECT):
- The question: 'IT finding #N: "Supplier invitations held: the GlockApps verdict answered fail:below_bar:microsoft..." (critical, open since 28 Oct, seen 16 times). As CEO, decide...'
- The case it carries: title, where, evidence with the remedy, affected, seen, still_open.
- The 9 options: fix_now x5, accept_risk, needs_founder x3.
- It is enough to choose. But "fix_now:accountant" for a mail-placement fault is noise, the duplicates are missing (item 9), and nothing says accept_risk is off-limits for money or security.
- Replay of the same answer: fn_reason_held_resolve re-applies (the last answer wins on the finding; the ceo.decision_closed hand-over is deduplicated by target_id). Harmless.
- The model hold: the replay respects it. The duty keeps filing 30 a day under the hold, and up to ~210 wait for the day it lifts.
- Plainly: a real judgement, with no consequence.

SIBLINGS (LOCAL merge money 5747d5f62 + sales 5acacfaf2 + this):
- Textual conflicts: only scripts/it/a_paid_reveal_is_known_to_every_seat_with_a_step.gaps.mjs (1 hunk with money: paid_at; 5 hunks with sales).
- No routine is defined by two of the three branches. No seat_handoff_kind row is written by two of them: the IT-loop file the money runbook re-applies inserts with `on conflict do nothing`, so fn_ceo_takes_it_finding wins in any order. That is right.
- Applied money -> IT loop -> overcharge -> VAT -> note -> sales -> pool: every file applies. Probes:
  - pool: PROBE OK on the merge;
  - hand-over note: PROBE OK;
  - money: needs a production transaction ("not in production");
  - VAT: no reclass journal (needs data);
  - sales: fails on quote_quality_hold.accepted_md5 NOT NULL (the sibling's own known failure).
- Runbook §3 is WRONG against the money branch's fn_founder_brief: its accumulator is v_body, and v_pool is undeclared, so the two lines do not compile. Correct form: declare `v_pool jsonb;`, then after `v_body := v_body || public.fn_founder_brief_ceo_lines(v_from, v_to);` add `v_pool := public.fn_founder_brief_overdue_handoffs(8); if (v_pool->>'count')::int > 0 then v_body := v_body || E'\nThe CEO needs you on ' || (v_pool->>'count') || ' item(s): ' || (select string_agg(l, '; ') from jsonb_array_elements_text(v_pool->'lines') l); end if;`. Then retire fn_ceo_tells_the_founder_daily, or he is told the same items twice a day.

AUTHORITY:
- Five verified, by greping every fn_agent_may_act/fn_support_may_act call:
  - sales.intake: 0 checks;
  - ceo.final_internal_authority: 0;
  - support.reply: 0;
  - marketing.publishing: 0 live routines (the text sits only in a file);
  - sales.matching: IS checked, on sales_engineer operator 'match' (operator.ts:84, 403 without a grant), but not on the six SQL points the map lists.
- The map undercounts TS checks: accountant refund with amount (refunds.ts:37) and the operator `cls` gates. "1 of 121 checked" is too low, though it is right in spirit.
- For the founder, unchecked decisions that touch money, consent or what is sent, most dangerous first:
  1. Supplier invitations (marketing.outreach_reply): 330 sent in 7 days with sales.invitation inactive.
  2. Unsubscribe (resend_inbound/email): customer_support changes a person's consent.
  3. The CEO's accept_risk on any finding, money and security included (new here).
  4. The CEO's refund checklist (ceo.final_internal_authority).
  5. Every customer reply (support.reply): content gates only, no grant.
  6. org_task.faq_answered: org_authority has 0 rows.

RUNS:
- Node: every_seat_reads_one_pool 7 pass + 5a pass (SELECT, with the proxy); 5b pass (LOCAL); 5c skipped. every_report_and_handoff_comes_back 6/6 (its production half is SELECT). Gaps check offline: 17 tests, 5 pass, 12 fail, as he said.
- Deno _shared + ceo_agent: 2,275 passed, 1 failed (catalogue_read.test.ts:107 tesseract, environment, a file this branch does not touch), 1 ignored.
- Mutants: see item 12.

SAFE APPLY (after the fixes):
1. Off-peak, at a minute where the read in the money runbook's rule 2 shows no long transaction.
2. apply_sql with lock_timeout 1500ms, items 5's fixes in.
3. On a lock timeout, wait 30 s and re-run.
4. Check pg_trigger (zz_pool_link x3; the dispatcher's body is a no-op).
5. Release order money -> sales -> pool.
6. The founder-brief lines go in the money file, or in this one after it.
7. Deploy the think/ai_reply/support_reply importers, ceo_agent and resilience_ping.
8. Never rehearse on production while working.
9. Watch: seat_duty ceo.company_pool avg_ms/failures; the held questions for ceo.* per day (count re-arms); handoff.overdue.escalated by escalated_to; company_event insert latency in the apply minute.

TELL THE FOUNDER:
- "Your CEO seat had never made a decision. Its replies to IT findings were one line of code, and its model judgement was switched off by a setting that never existed.
- This change makes the CEO actually think about each finding with a model, up to 30 a day, for a few dirhams.
- But today its decision is only written down. Nobody is made to act on it, and the same finding comes back to it as 'overdue' 15 minutes later.
- Late work by the CEO's own staff would be sent to YOU, daily, instead of to the CEO.
- The accountant seat is idle the same way: 0 judgements in 7 days.
- Fix those four things first. Then the CEO is a manager, not a filing clerk."

## WORKFLOW W1 MONEY 4 (FINAL) — re-verification, 13 Nov 2026 20:10-21:00 UTC
Re-issued brief; the section "WORKFLOW W1 MONEY 4 (FINAL)" above already reviews the SAME head 5747d5f62 (sibling still 5acacfaf2). This run rebuilt everything from scratch (worktree /tmp/claude-0/review-w1-final, LOCAL Postgres 16 /tmp/pg-w1-final:55481, both removed) and re-executed it. Tags [L] local, [R] code/offline, [S] light SELECT (reference tables, the ZZ fixture, 8 routine ACLs).

VERDICT: FIX — unchanged. Every finding of the section above reproduces; nothing new is more harmful.
- origin/main moved 2de366c08 → 35f9cec60 (4 commits, dropbox_backup + MANIFEST only); no shared file; merge-tree clean [R].
- [L] main/owner/index/redact/1150 applied twice: rc 0 each (main 95-110 ms, owner 66 ms, index 30 ms, redact 36 ms, 1150 50 ms). Main probe OK, redact probe OK, 1150 probe FAILED after the 2nd apply (54 reclass journals, 1150 = 284.41): FIX 2 confirmed; cause is the WHERE at :37-42 picking its own vat_input_reclass journals.
- [L] journals identical to the section above (777.60 → 743.12/34.48/777.60; 135.00 → 130.08/4.92, month_total "135.00"; intl 744.70/32.90; overcharge Cr 2300 38.77 and return Dr 2300/Cr 1050; full refund 6900 777.60; partial 6900 100.00; dispute +6100 55.00, won reverses, lost stays; refunded+disputed Dr 1100; zero fee nothing_to_book; test → shadow + ZZ-TEST number, no journal; live demo booked + live_payment_on_test_identity; unknown waits, books once live). Paid Sat 14 Nov 00:13 Dubai → Fri 20 Nov 23:59:59.
- [L] FIX 1 confirmed: overcharge return approved, refund 'approved', stripe_refund_id none → the sales engineer's hand-over writes a customer delivery.request "we received your request to refund the reveal fee ... the full amount" (agent_actions 217).
- [L] FIX 3 (S13 + dispute books 4000 777.60 on a fully refunded sale, after 6100 23.55 estimated), FIX 4 (S4d guard raise: no blocked task), 6a, 6c, 6e reproduce.
- [L] Replay R1 and the apply-to-deploy gap: 1 journal, 1 number, 1 receipt; unknown-mode sale waits, insert time after 16 min, booked by the hourly read.
- [L] The same 15 mutants: 13 caught by verdict, M08 only by an error, M14 (full-refund nothing_to_book) survives.
- [L] fn_handoff_redact: as 6(d); add: a phone stored as a JSON NUMBER (971501234567) is left as is (by design: numbers untouched).
- Grants [L/S]: fn_reveal_window, fn_reveal_clock_start service_role only; fn_reveal_refund_window_ends is granted to authenticated on purpose (:222, pure date arithmetic read by trg_reveal_window) — harmless. Production fn_refund_state still has PUBLIC execute [S]. RLS + one deny-all policy on demo_shadow_trace and accountant_reveal_payment_check [L].
- Sibling [L]: applies twice; its probe fails on accepted_md5 NOT NULL; the two-line replacement in the section above gives PROBE OK and leaves the main probe OK. No lock_timeout; :383-384 and :408-409 drop+create triggers; :88-89 re-adds a validated CHECK on quotes (full scan under ACCESS EXCLUSIVE; 5 rows today).
- deno [R]: stripe_webhook 11/0, stripe_checkout 11/0, accountant 53/0, reveal_invoice 16/0, messages_api 3/0, supplier_api 244/0, stripe_confirm none; _shared money (14 files) 102/0 run from the repo root.
- node offline [R]: 37 payment/hand-over checks; every non-production half passes except every_alarm #5. NEW: that test is ALSO red on origin/main (fn_notifications_the_same_message_is_sent_once not in REGISTER); the branch adds fn_accountant_reconciles_reveal. Both need a REGISTER/relay entry before the local gate is green.
- Cosmetic: a test-mode check resolves with "straight match: booked and reported by code" although nothing is booked.
The release procedure and the founder's plain-words list in the section above stand unchanged.

## ANONYMITY RELEASE (TEXT + DOORS) FINAL — second independent run
This is a second, independent run of the same brief on the same head: 1f450d57d, origin/main 35f9cec60 + F1 f8086debc + F2 ad932e645. The branch has not moved since the run above, which was appended at 2837. My probes are all new. Of the earlier drivers, only the auditor C copy (c3.ts, which is identical to the auditor's own file), amerged.ts and p_l40/p_l60 were re-run. Drivers and outputs are in scratchpad/relanon/. Tags: LOCAL = local database, READ = from code, SELECT = production read. On production I ran only three light SELECTs (two routine definitions, one count) plus the address-key check's own SELECT half.

VERDICT: FIX. I agree with the earlier run's items 1-3 and reproduced each one with my own inputs. I add item 4, a new leak of a shape the code claims to handle (small). Item 5 is an over-withholding defect that this release makes visible to customers. Items 1-4 then MERGE; item 5 may follow.
1. **An old supplier's name without its legal form reaches every matched supplier, including the new-inquiry e-mail headline.** READ+run.
   - Where: drawing_boq/quotation_gate.ts:176-180 (termsToKeep keeps only the maximal name) and :141 (the first word is kept only with 5+ letters and only if it is not a trade word); supplier_api/what_a_supplier_receives.ts:62.
   - Input: summary "Tiling works as listed in the Noor Interiors quotation".
     - Terms ["Noor Interiors LLC", ref]. The e-mail gives "A customer is requesting quotes for: Tiling works as listed in the Noor Interiors quotation (Dubai)".
     - "Blue Lagoon Contracting LLC" gives "Blue █ Contracting".
     - "Qasr Al Fan Decoration L.L.C" gives "Qasr Al Fan █", and "Decoration" becomes a seed.
     - "Atlas Glazing FZE" gives "█ Glazing".
     - (relanon/fix1.ts)
   - Fix: in requestSeeds, also seed every old term with its legal-form tail removed (llc, l.l.c, fze, fzco, est, co, company, trading, ltd, wll) when 2+ words remain. Never seed a trade word alone.
2. **The old supplier's prices pass when written in Arabic-Indic digits or as "dirhams".** quotation_gate.ts:32-33 (CUR has no "dirhams"; NUM is `\d`, ASCII only) and :113.
   - On the BOQ, "بلاط بورسلين ٦٠×٦٠ السعر ٨٥ درهم للمتر" and "Grout and skirting at 22 dirhams per metre" come out unchanged at the gate and in the supplier inbox.
   - The e-mail of a quotation-built request keeps "السعر السابق ٤١٢٠٠ درهم".
   - Shapes CLOSED: "85 AED/m2", "rate 18 per sqm".
   - Fix: CUR += `[Dd]irhams?`; NUM = `[\d٠-٩۰-۹][\d٠-٩۰-۹,٬]*(?:[.٫][\d٠-٩۰-۹]+)?`; :113 `/[\d٠-٩۰-۹]/`.
3. **A phone between ONE tab or ONE no-break space and a price crosses.** _shared/identity_text.ts:41 NO_GROUP_AFTER.
   - Input: "Site engineer\t052 765 4321\t3,250.00" is unchanged at save, the customer door, Q&A, redactText and the shared scrubber. The same holds with a single NBSP. The inbox withholds it.
   - origin/main gives the identical output, so this is not a regression. It is the commonest paste (Excel or TSV).
   - Fix: let a tab or NBSP end the number: `(?:(?=[\t ])|<existing look-aheads>)`.
4. **NEW: the access key leaves the second half of a hyphenated plot or villa number.** _shared/site_location.ts:55 PREMISES_NO (and :56 AR).
   - Input: access answer "Plot 681-2290, need boundary wall". supplierBrief serves `{"access":"the site-2290, need boundary wall"}` and the door backstop keeps it.
   - "Plot No. 373-4512" gives "the site-4512"; "Villa 12-3, gate B" gives "the site-3, gate B".
   - The field and text doors remove the whole number.
   - Fix: number part `[A-Z]?\d+[A-Z]?(?:[-/]\d+[A-Z]?)*` (AR: `[0-9٠-٩]+(?:[-/][0-9٠-٩]+)*`). Tried: all three are closed, and "Gate 2, lift max 1.5 tons" and "gate 3 opens 8 am" keep their measures (relanon/fix4.ts). Plant the rows.
5. **(Pre-existing, but now shown to customers) A first or last name that sits inside a trade word withholds the field.** _shared/anonymise.ts:212-215: residualScan reads seeds as bare substrings.
   - Inputs: Rami Khoury + "Ceramic wall tiles"; Tom Hall + "Hallway lights"; Sara Ward + "Wardrobes"; Grace Hill + "Walk-in chiller"; Mark Stone + "marking out". Each is WITHHELD.
   - The 654 corpus with the Grace Hill pair withholds "Chilled water pipe…" and "Walk-in chiller…".
   - What is NEW is that the customer sees it:
     - The edit is refused with 'This description cannot be sent to the suppliers as written because of "rami"…' (customer_api/lib/edit_summary.ts:31-36).
     - Notes and answers get the kept notice '…("rami") is kept with your request…'.
     - The supplier reads "The customer added details about the site…".
   - Fix: in the residual scan, a one-word name seed counts only at a word start or a capital letter. "RamiKhoury" and "re:BarshaGardenVilla" are still held.

(1) BLOCKERS
- "Sales contact    050 123 4567    12,500.00" is removed on all 7 doors. Save gives "Sales contact  [removed]  12,500.00"; door and inbox give "Sales contact [removed] 12,500.00".
- My column variants:
  - 2 spaces CLOSED, 3 tabs CLOSED, 3 NBSP CLOSED, mixed " \t " CLOSED.
  - A leading tab indent is kept: "\tOffice  [removed]  2  sets".
  - 1 tab LEAKS and 1 NBSP LEAKS: item 3, the same on main.
- Drawing option:
  - "ARJAN" and "Arjan" alone are counted in drawing mode only. "SITE: ARJAN" counts in both modes.
  - "Arjan model chair" and "ARJAN MODEL CHAIR" are never counted.
  - "JUMEIRAH VILLAGE" alone on a title-block line: drawing mode takes "JUMEIRAH" only.
  - "Greens 4 trays microgreens" is kept.
  - No caller in this release passes {drawing:true}. That waits for F3.
(2) OVER-REDACTION
- My 60 fresh sentences (48 EN, 12 AR: lighting, AC, rebar, concrete, solar, catering, IT, joinery, lifts, pest control, cold room, valves and others): the anonymity code changed 0.
  - The brand generaliser (origin/main, by design) changed 5. One of them is wrong and pre-existing: "1.5 HP" became "1.5 premium American brand" (horsepower read as the HP brand).
- The 654 corpus (645 non-#arguable) with Falcon Trading/Omar Haddad: only "Falcon grey" x2 (the supplier's own name) and the decided villas row.
- With Marina Glass Works/Grace Hill: the villas row, plus the 2 "chiller" rows of item 5.
(3) LEAKS
- C 46 at the customer door: 2 ("Contact Rashid Khan", "Falcolux"), both known.
- A 31: 0 of 62 identity leaks. "AED 32,816" stays in the customer's own free text; this is on the second-reader list as "an old price in a customer's free text".
- Predecessor 60 → 1 (Cedre Villas). Predecessor 40 → 1 (Khannour).
- My 31 (relanon/new30.ts), 18 CLOSED:
  - C2S: Arjan; Al Warqa 1; access "Damac Hills gate"; stored project; old name with a stored quotation (first word "Sahara" seeded); phone in "oh"-words; spaced e-mail; Arabic owner after "الاسم:"; GPS pin; Makani.
  - S2C: Al Sajaa factory; phone in words; spaced e-mail; Plot 33-77 Ras Al Khor; GPS; bare kestrelsupplies.ae.
  - BOQ: "85 AED/m2", "rate 18 per sqm", "as per Sahara Fitout detail".
- 13 LEAK. Known list:
  - lower-case "arabian ranches 3" (no stored site);
  - "بوابة المزهر" (bare community);
  - "Sunset Crest Residence project" (unlisted project);
  - Arabic one-word name "للتواصل: خالد";
  - old prices in customer free text ("AED 41,200", "95 AED per sqm"; forSuppliers does not apply forSource);
  - "Sahara Fitout…" on a request with no stored quotation;
  - "Kestrel installers" under the fixture name "ZZ DEMO Kestrel Supplies LLC". This is fixture-only: with the real form "Kestrel Supplies LLC" the door removes it.
- 13 LEAK. NEW:
  - BOQ Arabic digits, BOQ "dirhams" and the e-mail with Arabic digits (item 2);
  - "Plot 681-2290" access (item 4).
(4) TIMING
- The adversarial test passes in 22 s.
- review_cpu_budget, run 3 times while the adversarial test ran: 290 / 286 / 390 ms against 1,200 ms.
(5) SUITES, run from the repository root
- deno:
  - customer_api 98/0, drawing_boq 99/0 (1 ignored), inquiry_intake 120/0, messages_api 5/0, quote_extract 71/0, supplier_api 275/0, supplier_portal 53/0;
  - _shared: FAILED | 2285 passed | 1 failed | 1 ignored (3m42s) (the only failure is catalogue_read.test.ts:107, the known tesseract wasm read).
  - A first pass run from supabase/functions failed 18 tests on read permissions only. It is invalid and is not counted.
- tsc exit 0.
- node checks:
  - a_drawing_read 3/3, a_supplier_sees_only_its_own_match 30/30, what_a_supplier_receives 5/5, nothing_a_supplier_reads_can_be_arabic 155/155;
  - address-key 2/2, with its production SELECT half.
(6) SQL. LOCAL: PG16 /tmp/pg-relanon:55501, full mirror (808 tables, 2,175 routines).
- Locks:
  - CREATE OR REPLACE fn_supplier_workspaces: AccessShare on documents, inquiries, inquiry_matches, messages, quotes, transactions.
  - CREATE OR REPLACE fn_supplier_opportunities: AccessShare on inquiries, inquiry_matches, leads, quotes, supplier_capabilities, transactions.
  - Both take RowExclusive on pg_proc's toast. The 2 REVOKEs touch the catalog only.
  - Nothing above AccessShare on a user table.
- SELECT: production's pg_get_functiondef of both routines equals the file except for the intended hunks (title, file name, rfq_no, requirement, value). ACL: anon and authenticated have no EXECUTE.
- Applied, with seeded ZZ rows (relanon/seed.sql):
  - The unrevealed supplier sees "Fit out work in Sharjah · Job 160501", "Job file (drawing)", and requirement and value null.
  - The supplier with a transaction but no revealed_at is treated as unrevealed (correct).
  - The probe gives PROBE OK (4 entries, 2 files).
  - Production has 5 unrevealed pairs (SELECT), so the probe's unordered LIMIT 200 cannot miss the planted file today.
- Residual (pre-existing): AFTER a reveal, the title and requirement show raw summary_masked, including "existing quote AED 32,816.70" (the old supplier's price). Before this release, safe_text did not strip prices either. Follow-up: apply forSource after a reveal in workspacesBeforeReveal/opportunitiesBeforeReveal.
- Order: either order is safe (READ).
  - Old function + new routine: main's portal passes the routine's output through, and that output is now safe.
  - New function + old routine: before_reveal.ts rewrites every inquiry without revealed_at.
  - Deploy supplier_portal FIRST anyway: fn_supplier_quote_recommend is fixed only in TS (recommendBeforeReveal).
(7) DEPLOY: 22 functions (relanon/graph.mjs: static and dynamic relative imports of each index.ts against the 40 changed non-test sources). The list is the same as the earlier run:
- accountant, customer_api, doc_extract, drawing_boq, drawing_redact, inbound_email, inquiry_intake, license_extract, messages_api, public_site, quote_compare, quote_extract, resend_inbound, resilience_ping, reveal_invoice, sales_engineer, stripe_checkout, stripe_confirm, supplier_api, supplier_catalog_ingest, supplier_portal, wa_inbound.
(8) FIRST HOUR. The texts are as listed in the run above, verified in code. In addition:
- A customer whose name sits inside his trade word sees the refusal or the kept notice of item 5.
- Gaps of 3 or more blanks print as 2 in saved quotations.
- Portal titles read "Fit out work in Sharjah · Job 160501" (the category "fit_out" becomes "Fit out").
RELEASE STEPS
1. Fix items 1-4 with planted rows (5 if cheap). Re-run relanon/new30.ts, fix1.ts and fix4.ts, the 654 corpus, C, A, p40 and p60.
2. Run npm run gate, then merge via PR.
3. Deploy supplier_portal, then the other 21.
4. apply_sql the title file, run its probe (PROBE OK), and add the MANIFEST line with the pending note deleted in the same commit.
5. verify_deploy_parity for the 22.
6. In the first hour, read one live supplier portal page and inbox, and one customer quotation PDF.

### WORKFLOW W3 POOL 2 — re-run of 13 Nov evening (same head eed8432be), the brief's own tests
Marks: LOCAL = PG16 /tmp/pg-w3-2:55491 from the mirror + org_role/org_agents/edges/seat_handoff_kind/decision_policy/founder_mail_policy
copied by SELECT; READ = code; SELECT = time-bounded production read. Nothing rehearsed, applied or deployed on production; no model call
(stub answers through fn_reason_held_resolve, exactly what replayHeld passes). The section above (11:39) is an earlier pass on the same
head; everything it says that I re-ran held. This pass adds the founder's four tests, the flood, the cap on day 2, timings and locks.
Scenario scripts and outputs: SP/w3r2/ (s_ab, s_c, s_f, s_ceo, s_ceo2, s_cap, s_flood, bench, locks_*).

VERDICT: FIX. Applies twice (3,245 ms cold, 140 ms re-run), PROBE OK alone and after money+sales, leaks nothing, the CEO really asks a model.
But the pool hides the work a seat owes, blames the wrong seat when it is late, and the CEO's decisions still change nothing.

FOUNDER'S TESTS (LOCAL, real code paths: leads update -> fn_emit_supplier_approved; transactions.revealed_at -> trg_reveal_receipt):
(a) PARTLY HOLDS. Every seat asked about the supplier reads "the platform (automatic): a supplier was approved: <name> (steel, Sharjah)";
    IT's company-today counts "1 supplier.approved"; marketing/CS/CEO digests carry it. Nobody is ADDRESSED (digest only, read the next
    time that seat's model runs), and no event says WHO verified (actor 'system', no approved_by). There is no customer-verified event at all.
(b) PARTLY HOLDS. CEO and CS digests: "a customer paid the reveal fee of AED 135.00 on request 3 (painting, Dubai)". SE on the request:
    "accountant: reveal.paid to sales_engineer -- answered, waiting on accountant re-verification". CS's outcome reaches the SE ("answered:
    sent (notification 3)"). The SE's outcome is on the hand-over but the sender reads only "answered, waiting on ..." (pending rows print no
    answer). The ACCOUNTANT's digest says "nothing you follow happened" on the day of the payment: it subscribes to no payment.received /
    reveal echo, only *.failed. CEO: no step, so no outcome. Books: none (money branch). With money+sales applied the same fixture goes to
    reveal.reconcile -> accountant held judgement (accountant.payment_exception); the accountant's block still does not list it as owed (item 1).
(c) PARTLY HOLDS. A knowledge.request CS->SE left 8 days: the next tick escalates it once and files a CEO question. But the handler had
    answered "waiting: a knowledge entry ..." in 0 s, so the silent seat is computed as the SENDER: the CEO is asked "customer_support owes
    the close of an answered hand-over"; the SE (who owes it) reads nothing; CS reads "1 answered hand-over you sent and must close", not
    that it is late or escalated. Comes back to the sender: no. Reaches the CEO: yes, with the wrong culprit. The probe's case C passes only
    because its fixture has no replied_at.
(d) FAILS. fn_agent_may_act returns route 'ceo_case_decision' and nothing files it; the CEO duty takes only it.finding and overdue rows. No
    seat can ask "from 1 to 2"; no decision is written; the asker reads nothing. The branch adds 0 grant checks (1 / 99 / 21 unchanged).

FIX, most harmful first:
1. OWED WORK IS INVISIBLE TO THE SEAT THAT OWES IT (LOCAL). fn_seat_pool_waiting :1379 counts only rows with no replied_at, and every
   "waiting" handler stamps replied_at. Flood: 500 supplier.applied -> 500 event.act hand-overs to the SE in 2 ticks; the SE's block shows
   none of them. Same for reveal.reconcile to the accountant and knowledge.request to the SE. Fix: to_me = receiver = seat and (no replied_at
   or awaiting names this seat, case-insensitive, or the handler's reply was 'waiting').
2. THE SILENT SEAT IS WRONG FOR "WAITING" ANSWERS (:1803 + :1382; LOCAL (c), SELECT 60 d: ~11 open rows today: knowledge.request x6,
   ceo.lesson_reapproval_overdue x3 "the CEO seat to approve", ceo.root_cause x2 "the seat reasons"). The regex is case-sensitive ("CEO"
   never matches 'ceo') and an awaiting that names no seat falls back to the sender. Fix: `~*`; "the seat"/no seat named -> the receiver.
3. THE CEO'S DECISION IS CEREMONY AND BOUNCES (LOCAL, confirms the 11:39 items 1-2). Stub answers fix_now:sales_engineer / accept_risk /
   needs_founder:money were applied; ceo.decision_closed to IT and to the SE were closed by fn_seat_takes_the_ceo_decision in 00:00:00; the
   SE's pool then shows nothing owed. Next tick all 3 decided findings were escalated back to the CEO ("it_engineer owes the close").
4. ESCALATION GOES TO THE SENDER'S BOSS (:1811; LOCAL #10602): marketing silent on a ceo.revise -> escalated to the FOUNDER, whose daily
   mail line reads "The CEO is late: ceo.revise to marketing, marketing owes an answer". Fix: superior of v_silent; founder only if v_silent='ceo'.
5. THE DAILY CAP DOES NOT CAP (LOCAL s_cap): day 1 call 31 correctly refused (room 0); day 2, 27 re-armed old questions (uncounted) + 19 new
   = 46 live against a cap of 30, asked_today 19. Fix: count re-arms (rearmed_at).
6. THE APPLY STALLS EVENT WRITES (LOCAL): first apply holds SHARE ROW EXCLUSIVE on company_event/agent_actions/seat_judgement and ACCESS
   EXCLUSIVE on company_event (dispatcher drop); a re-run takes ACCESS EXCLUSIVE on all three. With one open agent_actions writer the apply
   failed at 1,601 ms on line 1927 and a concurrent company_event insert waited 1,350 ms. Fix as in 11:39 item 5 (create or replace trigger;
   neuter the dispatcher body; drop it later alone).
7. ACCEPT_RISK IS OFFERED ON A CRITICAL SECURITY FINDING (LOCAL #30, blast security): options were fix_now x5 (marketing for a security
   fault), accept_risk, needs_founder x3. Fix: no accept_risk when critical or security/money; offer fix_now only to seats that own the area.
8. THE CEO READS "? owes the next move" (fn_pool_say :1192-1194 reads silent_seat from the hand-over's detail, not detail.silence or the
   event payload; LOCAL flood digest). Fix: read d->'silence'->>'silent_seat'.
9. THE PROBE IS DATA-DEPENDENT (probe :89/:119): once 30 CEO questions were asked today it fails "B: the finding was not filed" (LOCAL,
   check 5b). Fix: set items = asked_today + 5 before case B.
10. The accountant hears no payment (seed): add accountant digest rows for payment.received and handoff.reveal.paid.sent.
11. A pending hand-over's answer is not printed to its sender (fn_seat_pool_timeline: answered rows print only "waiting on"); print evidence.reply.

CEO DUTY (LOCAL+READ): a real judgement: think() gets the question, the finding (title, severity, where, evidence+fix, seen, still open,
previous decision) and the pool (subject finding:<issue_key>), and chooses among 9-10 options on the routine route; different facts can
give different choices. Stubs: act/wait/escalate applied; malformed ("escalate_to_board") decides nothing (ceo_judgement_refused, asked
again after 24 h); model down: stays held, failed after 3 tries, re-armed next day (nothing lost); model hold: replay claims nothing.
Founder mail: one e-mail (queued, mode email) "The CEO asks (money, IT finding #27): Do we pay for ...". His answer has no way back.
FLOOD (LOCAL, 500 supplier.applied + 500 quote.received in one hour; prod peak 843 events/hour SELECT): digest classed 1,000 in 390 ms;
dispatch 200 hand-overs a tick; 2 days later 100 escalations a tick; CEO questions 5 a tick / 30 a day; no model storm, but 300 CEO
questions queue for 10 days and the SE is never told (item 1).
COST PER WRITE (LOCAL, 1,000 inserts, prod-like 5k reports / 2k notifications): company_event 0.04 -> 0.33-0.43 ms; hand-over 1.8-2.7 -> 2.7-3.6 ms.
LEAKS: none found. External blocks neutral (customer: "a quotation was received" x2; supplier: his own quote only; rival not linked); all
33 new routines revoked from anon/authenticated (LOCAL); event_subscription/event_delivery/company_event/agent_actions not readable by
anon/authenticated on production (SELECT). Internal blocks carry supplier names and customer prices; the founder audience reads them by design.
SEED (LOCAL+READ, 30 sampled): 290 echo-type owners are all a sender of that kind (21 kinds exist only on the money branch); 13 domain types
true to their emitters; request.step_failed/reveal_outcome/reveal_period_ended/reopened are emitted only by the sales branch.
SIBLINGS: no routine defined by two branches; merge-tree conflicts only on the gaps .mjs (add/add, all three pairs); money's IT-loop file
inserts it.finding->ceo with `on conflict do nothing`, so fn_ceo_takes_it_finding survives either order. Money (4 files) + sales + pool
re-applied LOCAL: all exit 0, PROBE OK.
RUNS: node every_seat_reads_one_pool 7 pass (5a SELECT), 5b fails only for item 9, 5c skipped; every_report_and_handoff_comes_back 6/6;
gaps 5 pass / 12 fail.
Deno (run from repo root, --allow-read=.) _shared + ceo_agent: 2,275 passed, 1 failed (catalogue_read.test.ts:107, the known tesseract one), 1 ignored. (Run from supabase/functions the same flags give 63 false failures: --allow-read=. then cannot read ../../../scripts.)
Release order: money -> sales -> pool (all three re-apply cleanly either way); the pool only after items 1-6 are fixed; founder-brief lines per the 11:39 section.

## ANONYMITY RELEASE (TEXT + DOORS) — check of the five fixes
Independent check of origin/sales_engineer-anonymity-text-and-doors-released-together @ e2d78a0f3 (fix commit over 1f450d57d), 13 Nov 2026. Offline only, no database, nothing on production. Every result is LOCAL (code run) or READ. Each driver was run on e2d78a0f3 and on 1f450d57d side by side. Drivers and outputs: scratchpad/fixcheck/ (attack.ts with 63 inputs, extra.ts, draw.ts, tok.ts, nbsp*.ts, head/ base/ trial/ outputs, trial_fixes.diff, suite_*.txt). Worktrees: review-rel-anon, -base and -trial, all removed.

VERDICT: FIX. Items 1 and 2 below are regressions made by this commit. Items 3 and 4 are small. Then MERGE. All four were tried together in one tree (trial_fixes.diff, 4 files, +9/-5 lines). That tree closes them and changes no reviewer row.
1. Fix 3 erases a tab-separated BOQ row as a phone. Where: _shared/identity_text.ts:75. `SP` (the MOB_ANY separator) still includes \t, and the new `(?=\t)` in NO_GROUP_AFTER skips the decimal and group guards.
   - Input: "05\t4\t250\t1000\t50.00" (item, qty, rate, amount, VAT) gives "[removed]\t50.00" at shared, save, door, Q&A and inbox. "05\t6\t120\t4500\t540,000.00" fails the same way. 1f450d57d kept both.
   - Fix: `const SP = '(?:(?!\\t)[\\s\\-\\u2010-\\u2015])'`, so a tab never joins a number, as the commit says.
   - Cost: "Mob\t050\t123\t4567" (one number split over 3 cells) is no longer removed at shared, save, door or redact. Q&A still removes it. This is acceptable.
2. Fix 5 reopens joined Arabic names, and it is quadratic.
   - Where: _shared/anonymise.ts:146-156.
   - The inbox now sends "Almansoori Villa" (Fatima Al Mansoori), "Binzayed family majlis" and "Delivery to Mohammedali" to suppliers. 1f450d57d withheld all three.
   - The drawing residual no longer holds "Almansoori" or "Owner:Almansoori". This affects pdf_vector_redact.ts:172/328, cad_file_redact.ts:225 and scan_redact.ts:240/248, and also cad_render.ts:376/430, where seedHit does not catch them either (READ).
   - gateDrawingBoq still drops these lines through ocrMisreads (LOCAL).
   - All-capitals text is held as before ("ALMANSOORI", "CERAMIC" are still held).
   - Fix, part 1: still count the seed when the rest of the token is another seed or a name particle (al, el, bin, bint, bu, abu, abd, abdul, abdel, ibn, ali).
   - Fix, part 2: bound the token walk to 48 characters. One 100 KB token 'xrami'x20000 takes residualScan 43.7 s (1f450d57d: 0.3 s). supplierField on 50 KB takes 14.0 s (was 3.3 s). Bounded, it takes 1.3 s. Add this input to the adversarial test, which does not catch it today.
3. Fix 2 leaves a dangling currency word, and the second gate eats a size.
   - Where: drawing_boq/quotation_gate.ts:51. The Arabic label branch takes no currency after the figure.
   - The gate turns "بلاط ٦٠×٦٠ السعر ٨٥ درهم للمتر" into "…٦٠×٦٠ درهم للمتر". supplierCopy (what_a_supplier_receives.ts:120) then gates again and the supplier reads "بلاط ٦٠× للمتر".
   - This breaks the "idempotent" claim at :188. The ASCII-digit case was already wrong on 1f450d57d; the fix extends it to Arabic digits.
   - Fix: append `(?:\\s*${CUR}${UNIT_AFTER})?` to that branch.
4. Fix 4: "Gate 3-4 pm deliveries" becomes "the site-4 pm", and "Office 9-5 hrs" and "Unit 12-14 mm glass" fail the same way. The output is the same on 1f450d57d.
   - The number backtracks to "3" and the measure guard cannot see past "-".
   - Fix: site_location.ts:57 guard `(?![\d.,\-/]*\s*(?:…))`.
   - The right reading of "Unit 12-14 mm glass" is to keep it (glass thickness), and the trial keeps it.
   - "Road 6-8 m wide" still gives "█-8 m wide" through anonymise premises_no COUNT_AFTER. This is pre-existing and goes on the follow-up list.
(1) Drivers on the fix head, compared with 1f450d57d:
- C stays at 2 at the door (same rows). A: 0 of 62, and the JSON is byte-identical. p60: 1. p40: 1.
- relrev/new30: 7 → 6.
  - The tab row is CLOSED.
  - The Noor Interiors row is now CLOSED in field_site, line_site and access. It still shows in nosite and clarify, because those runs carry no stored terms (expected).
  - The spaced e-mail row was WITHHELD and is now painted ("email █ @ █. com"). Right.
- relanon/new30: 13 → 10. BOQ Arabic digits, BOQ dirhams and the plot row are CLOSED, and the e-mail with Arabic digits no longer leaks. The new damage is the "٦٠×" row (item 3).
- fix1: all 5 names are CLOSED (headline "…the █ quotation"). fix4 rows: closed. s1 tab row: closed on all 7 doors.
- Fresh 60: 0 changed (relrev). relanon: 5, all from the brand generaliser, same as before.
- 654 corpus: Falcon 3=3. Blue Star 1=1. Grace Hill 3 → 1: both "chiller" rows now pass.
(2) My 63 inputs (12-15 per fix; LOCAL, attack.{head,base,trial}.out):
- Fix 1: 0 leaks reopened, 0 damage from this fix.
  - Exceptions: "Haddad & Co" written as "Haddad" leaks (one word left, by design).
  - "Delta Pumps Est." seeds "Delta" and "Pumps". This comes from termsToKeep, it is pre-existing, and it is already on the follow-up list.
  - Arabic ذ.م.م / ش.ذ.م.م, "Est.", three-word names and trade-named firms ("Steel Trading LLC": "Steel railing" survives) are all correct.
- Fix 2: all 6 must-remove cases are closed (AED 120/m2, 120 dhs, Persian ۳۵ درهم, Dirham, ٤٥٫٥٠). Quantities ٨٥ م٢, ١٢ قطعة, "Dirhamco" and model ٢٫٥ are kept. The only damage is item 3.
- Fix 3: all 6 must-remove cases are closed. Regression: item 1.
  - Pre-existing and identical on 1f450d57d: the inbox withholds "03\t120\t4500\t54000"; Q&A eats the date cell "05-12-2026\t2"; "PN 0501234567-A" is removed as a phone.
- Fix 4: all 6 must-remove cases are closed (681-2290, 12/3, 4B-12, 7/2A, فيلا ١٢-٣, قطعة ٦٨١/٢٢٩٠). Damage: item 4.
- Fix 5: these are kept: Ceramic, Hallway, chiller, MacHallister, Disgraceful.
  - These are still removed: ramiVilla, VillaRami, RAMIVILLA, rami_villa, rami15, Rami's, Al-Khoury.
  - Leaks: item 2. Arabic is unchanged (سامي inside سامية is still withheld, as before).
- Single NBSP: I partly disagree with leaving it. Even with a label, "Tel: 052 765 4321 3,250.00" crosses at save and door, and so does the same line with NBSP or "Mobile …12,500.00" (pre-existing).
  - A phone label should override the group/decimal guard. This goes on the second-reader list and is not a blocker.
(3) Loose-scan callers: the supplierField/redactBoq doors, heldParts (the customer refusal text), inquiry_create (customer BOQ hold), drawing_identity_gate, pdf_vector_redact, cad_file_redact, scan_redact and cad_render. Each change is described in item 2.
(4) Timing: the adversarial test passes in 25 s. review_cpu_budget runs in 359 ms of 1,200 ms (load 3.9). Tab-heavy 50-100 KB inputs show no change. The only slowdown is item 2.
(5) Suites on e2d78a0f3: supplier_api 278/0, drawing_boq 100/0 (1 ignored), customer_api 98/0. _shared 2285/1: the only failure is catalogue_read.test.ts:107 (tesseract), as expected.
