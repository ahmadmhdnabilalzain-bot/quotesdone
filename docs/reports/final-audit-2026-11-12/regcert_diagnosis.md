# Registration certification failures: diagnosis (workstream regcert_diagnosis, seat it_engineer)

Final audit, 11 Nov 2026. Subject: the paid supplier registration certification of 22:30-23:13 UTC on main 2cc9d1017
(run tags f5b09c50 and 2777f7ae), verdict NOT READY. Diagnosis and report only (ledger 1641): nothing was fixed, deployed,
applied or merged. Production was only read (SELECTs and the logs endpoint). The real supplier, lead 19398, was read, never touched.

## VERDICT: GO WITH FIXES

The three failed steps are two product defects, both introduced or exposed by today's #1947 ("the licence is stored before it is
read"), and neither is the harness, the container, the 4 s hedge of #1949 or the other audit load. The effort raise (ruling 1630) is at most a contributor: it did not move the typical licence read, but the slowest reads are slower since it went live. A real
supplier can meet both. Neither loses data for good and neither leaves a supplier stuck for ever, but one holds a finished
registration Pending for 10 to 40 minutes and the other tells a supplier our reader "has not finished" about a licence it finishes
reading half a second later. Until both are fixed the certification cannot be expected to pass twice (estimate in section 5).

## 1. What was tested

| What | Pass bar | Measured | Result |
|---|---|---|---|
| A. Run 1 J4 (licence photo): sequence from edge_logs trace 01a1ccc2-e76e, ai_cost_log 102125, screenshot 09 | the screen shows number and authority | answer left 22:38:20.049, model's reading recorded 22:38:20.500, written 22:38:20.593; screen still "has not finished" with both fields empty at Submit | root cause established (F2) |
| B + C. Run 2 J1: sequence from edge_logs traces 01a1ccd0-7351 and 01a1ccd0-c1b8, ai_cost_log 102365/102371/102373 | activities read; approved within 60 s | licence 'read' written 22:53:21.408, overwritten by the profile read's stale copy at 22:54:03.301 | root cause established (F1) |
| Offline replay of B + C against main's own code, real fixtures (`repro/source_docs_lost_update.test.ts`) | the test must fail on main for the claimed reason | 2 of 2 FAIL on main with the same write order and final state as production; 2 of 2 pass with a scratchpad prototype of the fix | reproduced |
| The review's licence race, documents.ts:334 (`repro/late_licence_write.test.ts`) | row keeps the new file's readings | FAILS on main: file B's row ends with file A's number, authority and expiry | proved offline; not seen on production |
| Would C have resolved by itself (`repro/the_sweep_would_have_reread_it.test.ts`, sweep times from edge_logs) | the sweep selects the stuck licence | selected at the 23:16:03 sweep; fixture was torn down 23:07:50 | passes; inferred, not observed |
| Is the effort raise (ruling 1630) a cause | the same eight fixture licences, read before it reached main (12:43 UTC, with #1943) and after | before, n=57 (06:00-11:00): p50 8.5 s, p75 9.9, p90 12.0, max 14.1, median 583 output tokens, 18 over 9.5 s (32%). After, n=16 (this round): p50 8.4 s, p75 11.5, p90 15.9, max 23.2, median 730 output tokens, 6 over 9.5 s (38%) | median unchanged; tail heavier (2 of 16 above the earlier maximum: about a 3% chance if nothing had changed). A contributor to the 23.2 s read, not the defect |
| Is the concurrent audit load a cause | failed, retried or throttled attempts; lower token rate | license_extract 20 of 20 and supplier_doc_trades 30 of 30 ok on the first attempt, breaker closed, no 429; certification calls 84-137 tokens/s before the load, 80-122 under it | not a cause |
| Was #1949's 4 s hedge involved | a second licence read or a second process_docs for the lead | one license_extract call per licence (ai_cost_log); lead 157558 has exactly two process_docs requests (licence, profile) | not involved |
| The one real registration, lead 19398 (read only) | - | verified 7 min 52 s after the licence upload; met none of A, B, C | see section 4 |
| A paid re-run of J1 | only if the cause could not be established otherwise | not needed | NOT RUN (USD 0) |

## 2. The sequences

### A. Run 1, J4 mobile, lead 157552, L4_ajman_phone_photo.jpg (a photo: code can read nothing off it)
Request 01a1ccc2-e76e-7352-ab54-b96668dca385, received 22:38:07.726.
- 22:38:09.620 file stored; 09.805 the row names it (licence_read_state 'ours_failed'); 09.902 and 09.935 the row writes.
- 22:38:10.57 the model is asked (ai_cost_log 102125: openai/gpt-6-luna-pro, 9,414 in, 750 out, 9,997 ms, ok).
- 22:38:19.967 to 20.049: MODEL_ANSWER_BUDGET_MS (10 s, `_shared/licence_read_state.ts:73`) runs out; process_docs answers
  `license_read_state: 'ours_failed'`, `licence_read_after_answer: true`.
- 22:38:20.500 the model's answer is recorded; 20.593 its fields are written to the row (number, name, authority, expiry, state 'read').
- The form shows LICENCE_BEING_READ_NOTE and never asks again (`ProfileForm.tsx:127`, no poll in `upLicense`). Screenshot
  `run1/J4_mobile/09_agreement_accepted.png`, taken more than 10 s after the read landed: the note is still there and
  "Trade licence no." and "Licensing authority" are empty. The harness read the row 0.8 s after the answer and found it 'read', all five fields right.
- The registration itself went on normally: approved and verified in 3.1 minutes.

### B and C. Run 2, J1 desktop, lead 157558, L1_dubai_det_bilingual.pdf + P1_mep_contractor.pdf
Two requests write one jsonb value, `supplier_capabilities.source_docs`, each as read, then model call, then write of the whole value.

| UTC | request | call | effect |
|---|---|---|---|
| 22:52:55.505 | licence (…7351) | received | |
| 22:52:57.179 | licence | PATCH leads | code read number, name, authority, expiry: state 'read' 1.7 s in |
| 22:52:58.0 | licence | model asked (102365) | 7,395 in, 2,207 out, 23,226 ms, ok. The same file took 8.9 to 12.7 s in nine other reads today (937-1,014 out in the four later ones) |
| 22:53:07.260 | licence | POST supplier_capabilities | budget out: licence marked 'reading'; answer leaves (11.9 s) |
| 22:53:15.576 | profile (…c1b8) | received | 8.2 s after the licence answer (its upload began at 22:53:13.656, 6.3 s after) |
| 22:53:17.044 / 17.926 | profile | POST supplier_capabilities | profile marked 'reading' |
| 22:53:17.975 | profile | GET source_docs | SNAPSHOT: licence still 'reading' |
| 22:53:18.2 | profile | model reads together (102371, 36.6 s; 102373, 8.4 s) | given the profile only |
| 22:53:21.167 | licence | model answer recorded | 14 s after its answer left |
| 22:53:21.408 | licence | POST supplier_capabilities | licence 'read' with its 3 activities |
| 22:54:03.301 | profile | POST supplier_capabilities | writes its 22:53:17 snapshot: licence 'reading' again, `licence_check.activities: []` |
| 22:54:03.372 | profile | rpc fn_sales_engineer_verifies_supplier | a document is 'reading' |
| 22:54:13 | harness | Services tab | "L1_dubai_det_bilingual.pdf: reading (being read; if this stays, the read did not finish)"; activities [] (step B) |
| 22:54:17 | harness | Confirm my services | gate: pending, documents_being_read |
| 22:55:18 | harness | step C fails at 60,494 ms | leads.licence_read_state 'read' (the licence FIELDS), while the licence's entry in source_docs says 'reading' (its trade read) |

- B is not the cause of C. Both are the same lost write: the profile read computed `licence_check` from a snapshot with no read licence (B) and wrote the licence back as 'reading' (C).
- "documents_being_read" with read state "read" is not a contradiction: they are two records. `leads.licence_read_state` is the licence field reader; the gate's `v_doc_reading` looks at `source_docs.docs[].status`.
- No second licence read ran. #1949 hedges cheap reads in the browser only; process_docs is not hedged.
- Proof: the order of writes above (edge_logs, by trace_id), the state the harness saw, and the offline replay, whose writes are
  `licence:reading` / `profile:reading,licence:reading` / `licence:read,profile:reading` / `profile:read,licence:reading` and whose final state is
  `{"licence":"reading","profile":"read","licence_check_activities":[]}`. The request bodies are not in the logs, so the content of each production write is inferred from the code and the replay; the order and the outcome are measured.

**Would he have been verified without help?** Yes, later. The sweep (resilience_ping itlater, `supplier_api docs_reread`) reads a document again once it has been 'reading' for 10 minutes, then the gate runs again. Its probes are in edge_logs at :16 and :46 of every hour (16:15 to 23:16 UTC), so it runs every 30 minutes, not every 10. The mark was 22:53:07; the first sweep after 23:03:07 was 23:16:03; the fixture was torn down at 23:07:50. So for this supplier: Pending from 22:54:17 to about 23:16, 22 minutes; in general 10 to 40 minutes. Not observed (teardown came first): inferred from `stuckOf`, the 30-minute escalation `fn_supplier_doc_reading_escalate` (which also releases the hold) and the existing check `a_document_still_being_read_holds_the_supplier_and_reaches_the_sales_engineer.test.mjs`.
What he sees meanwhile: "Pending", with "we are still reading your company profile or catalogue; your registration is checked again as soon as that read finishes", and his licence listed as being read. He is asked for nothing.

## 3. Findings

### F1. BLOCKER. Two document reads of one supplier overwrite each other; a finished registration is held Pending 10-40 minutes
- Where: `_shared/supplier_doc_trades.ts` `proposeFromRead` (lines 472-522: snapshot at 474, model at 497, whole-value upsert at 512-515) and `markReading` (428-441). No lock, no version, no merge at write time. The model call between read and write took 4 to 60 s in this round (30 calls, mean 17.4 s).
- What opened it: #1947. The licence's model read may now finish after the answer (budget 10 s), and its trade read waits for it (`documents.ts:363`), so it can land while the profile, uploaded next, is with the model. In the 10:22 paid round, before #1947, the answer waited for the model: 12 of 12 journeys verified.
- The same loss needs no licence: a catalogue attached while the profile is with the model leaves the profile 'reading' and drops the trades read from it. The registration form offers "Product catalogs (up to 5)" beside the profile. Proved offline (second test); not seen on production.
- Consequences: gate pending / documents_being_read until the sweep (10-40 min); licence activities blank; every proposed service's licence judgement "unclear"; the sales engineer's licence-scope check not filed. Restored by the sweep for a text licence. For a photo or scan licence the activities came from the model and are not re-read by the sweep (inferred from `readDocForTrades`: no text layer gives 'needs_ocr').
- Smallest correct fix: (a) store through one SQL routine that locks the supplier's row and merges per document path, so a read only ever writes the documents it read (used by both `markReading` and `proposeFromRead`); (b) in `proposeFromRead`, after the model answers, read the row again and, when the set of read documents is no longer the set the model was given, read together again (at most twice). (b) alone is prototyped in `repro/supplier_doc_trades.prototype_fix.ts` (15 changed lines): both replays pass, licence 'read', 3 activities. (b) alone still leaves the two round trips between the re-read and the write; (a) closes that and was not prototyped.
- Proving test: `repro/source_docs_lost_update.test.ts` (fails on main, 2 of 2), to live beside `_shared/supplier_doc_trades.test.ts`; for (a), a SQL check with two concurrent calls.

### F2. HIGH. A photo or scan licence read in more than about 9.5 s is shown as "our reader has not finished", fields empty, and the form never updates
- Where: `MODEL_ANSWER_BUDGET_MS = 10_000` (`_shared/licence_read_state.ts:73`, #1947) against a model whose licence read takes p50 8.4 s, p75 10.0 s, p90 12.0 s, max 23.2 s (73 reads of the eight fixture licences today); `ProfileForm.tsx` `upLicense` has no second look.
- The budget was tight before the effort raise reached main: 18 of 57 morning reads of the same licences (32%) took over 9.5 s. The read time follows how much the model writes (80-95 tokens/s throughout, 476 to 2,207 output tokens), and it writes more since the raise (median 583 to 730 tokens), which lengthens the slow reads. Whether the effort setting reaches this model's request was not checked here (the effort workstream's subject).
- A text PDF hides it, because code reads the four fields 1.7 s in. Only a photo or a scan shows it. Today's photo and scan reads (18): 2 to 4 over the measured threshold (between 9.08 s, which passed, and 9.997 s, which failed). This round: 1 of 4.
- What the supplier sees: the sentence above in place of "Read your licence", both fields empty, until he leaves the form. Nothing blocks him and the row is right within a second.
- It also invites F3: the natural reaction is to upload the licence again.
- Smallest correct fix: when process_docs answers `licence_read_after_answer`, the form reads the row again (`readRow` already exists) every 2 s for up to 60 s and, once `licence_read_state` is no longer 'ours_failed', fills number, authority and expiry and shows "Read your licence"; while waiting it says the licence is being read, not that our reader did not finish. Raising the budget instead would hold every upload longer and still miss the tail.
- Related, speed: 15 of the 16 licence answers in this round took 9.0 to 12.5 s (the other 24.8 s, F6) because the answer waits for the model even when code already read all four fields (state 'read' at +1.7 s). Answering at once in that case would take about 10 s off the licence step for every text licence.
- Proving test: a unit test of the second look (as `licenceReceived` has), and the certification's "shown back" step, which should then wait for the form's own update.

### F3. HIGH. A slow licence read writes its fields onto a row that already names a different file (the review's finding: confirmed)
- Where: `supplier_api/actions/documents.ts` `askLicenceModel`, the write at line 334 and the issue-date write at 336: filtered by lead id only.
- Proved offline (`repro/late_licence_write.test.ts`, fails on main): licence A slow, licence B uploaded and read ("ZZ-B-0001", expiry 2028-02-02), then A's answer lands: the row names file B and holds "ZZ-A-0001", "ZZ Authority A", 2027-01-01, state 'read'. Not seen on production: no supplier uploaded a second licence within a read.
- Why it matters: the licence number, name and expiry decide the verification; an expired first file followed by the renewed one can leave the wrong date on the row.
- Smallest correct fix: the model's write carries `license_doc_path = <the path this call stored>` as a filter (through `updateLeadSettingAsideClashingLicence`); no row updated means the file was replaced and the reading is dropped.

### F4. MEDIUM. The text kept beside each document is never saved
- `saveText` uploads `<path>.read.txt` as text/plain; the supplier-docs bucket's allowed types do not include it. 23 of 23 uploads in the round answered 400 "mime type text/plain is not supported"; the bucket holds 0 such files.
- Effect measured: every together-read downloads and parses the other documents again (the licence is parsed twice in each journey). Effect inferred from code: after a model outage the sweep cannot re-read a document whose words came from the vision model (a scanned profile, a photo), because that text exists only in the missing file (`proposeFromRead` line 482 skips `photo_text`).
- Fix: allow text/plain on the bucket (a storage setting) or keep the text in a table; check that the file exists after a read.

### F5. MEDIUM. The "10-minute" re-read runs every 30 minutes
- Probes at :16 and :46 only. Code and the gate's own recommendation text say 10 minutes. With F1 fixed this matters only for a read that really died.

### F6. LOW, unexplained. supplier_api stopped answering for about 20 s at 22:45:42-22:46:05
- Run 1 J8's process_docs took 24.8 s: its model had answered at 22:45:54.3 and its 10 s budget ended at about 22:45:52, but nothing ran until 22:46:04.9; the sweep's docs_reread, received 22:45:46.0, was answered at 22:46:05.0. No step failed (budget 45 s). Same shape as docs/reports/2026-11-11-kyc-slow-requests.md, here with a caller inside Supabase, so it is not the container. Cause not established.

## 4. How often a real supplier would meet each

- Production history: one real registration with a licence exists (lead 19398). `agent_actions` holds one documents_being_read decision for a real supplier (his, 8 s) and no licence_being_read; no document is 'reading' now.
- Lead 19398, a real supplier, 11 Nov, read only: licence uploaded 06:45:22; model read 06:45:24-06:45:40 (16.1 s, in the request: the code then waited); number, name, authority and expiry on the row, state 'read'. Profile uploaded 06:47:46, 2 min 6 s later. Gate: reg_terms 06:47:48, documents_being_read 06:47:52, services_unconfirmed 06:48:00, approved 06:53:14 on his confirmation. He met none of A, B, C.
  Two things about his reading, outside this workstream: his profile's trades were "held" (three readings did not agree), so nothing was proposed from it and the sales engineer item 382385 is still pending; and code read his licence activity as a cut value (the leading words of the activity were lost; the value itself is not repeated here because it is a real supplier's).
- A (F2): only photo and scan licences. This round 1 of 4; today's 18 such reads 2 to 4. Before #1947: 0 of 4 (10:22 paid round), because the answer waited.
- B and C (F1), licence then profile: needs the licence read to outlast the 10 s budget by more than the time to attach the profile. At the harness's pace (profile snapshot 10.6 s after the licence answer) that is a read over about 19 to 20 s: 1 of 73 fixture licence reads today, and 1 of the 12 complete journeys run since #1947. A person who takes 30 s or more to pick the next file would need a read over about 45 s: none in 102 reads over 8 days (max 37.3 s). The one real supplier took 2 min 6 s.
- B and C (F1), profile then catalogue within the profile's read (3-60 s): not measured on production; no real supplier has uploaded a catalogue.
- F3: needs a second licence upload within the first one's read; not observed.

## 5. What this means for the certification

Per paid certification (2 runs: 12 complete journeys, 4 photo or scan uploads), from today's distributions: F1 alone fails a round about 1 time in 6 (1.4% per journey), F2 alone between 1 in 3 and 2 in 3 (11% to 22% per upload). These are small samples (73 and 18 reads); the direction is firm, the figures are not. Changing the harness budgets would not pass either step: C needed 22 minutes, not 60 s.

## 6. Spend, teardown, what was not done

- Spend by this workstream: USD 0. No model was called, no fixture made, no window opened. The optional paid J1 re-run was not used.
- The round under diagnosis, from ai_cost_log by tag: f5b09c50 USD 0.0381 (24 calls), 2777f7ae USD 0.0294 (24 calls). The harness printed 0.0316 and 0.0218 (21 calls each): it counted before J8's three trade reads landed.
- Teardown of that round, checked: leads 157549-157565 left 0, their capability rows 0, its two rehearsal windows closed.
- Not done: no fix in the repository, no branch, no worktree (ledger 1641). The fix prototype and the three tests live only in `repro/`. main-base was not modified (`git status` clean).
- Not measured: the content of each production write (bodies are not logged); the sweep's re-read of lead 157558 (torn down first); whether code reads the real supplier's four fields (his file was not opened); the SQL half of F1's fix.

## 7. Files

- `repro/source_docs_lost_update.test.ts`: F1, fails on main; `QD_READER=$PWD/supplier_doc_trades.prototype_fix.ts` passes.
- `repro/supplier_doc_trades.prototype_fix.ts`: main's reader with the 15-line prototype (imports point at main-base).
- `repro/late_licence_write.test.ts`: F3, fails on main (takes 10 s).
- `repro/the_sweep_would_have_reread_it.test.ts`: passes on main.
- `c*.sql`, `l*.sql`, `r*.sql`, `h*.sql`, `g*.sql` with their `.json`: every query behind a number above; `logs.mjs` reads the logs endpoint.
Run each test from `repro/` with `deno test -A --no-lock <file>`.
