---
name: a-supplier-profile-is-read-first-and-mapped-second
description: "12 Nov 2026, ruling 1647: the supplier reader is two steps (read with trade names only, then map to keys), never 'held'; the tick list is stated+verified+mapped and unticked; partner/shown/vague are asked (slice 4 shows the cards); the hard-profile set is the measurement; the reading runs at medium because of its clock"
metadata:
  type: project
  modified: 2026-11-12
---

**What the reader is (reader `supplier_doc_trades@5`, `_shared/supplier_profile_reading.ts`).** Step A reads all of a supplier's documents
with our 223 trade NAMES only and returns every claim with its sentence and basis (stated / shown / partner / brand), the vague
statements with one question, also-ask candidates, the licence's fit. Step B maps each phrase to the keys it IS, against only the
slice of the catalogue for the trades named (+ adjacent + umbrella). Code only checks (`checkReading`, `applyMapping`) and decides
(`proposalOf`, pure): stated + verified + mapped = the tick list, UNTICKED; partner = listed and marked, never ticked by "Tick all";
no key = his own words; partner, shown, vague, a trade with no service, the licence mismatch = question rows in the shape of the
`supplier_service_question` table (type `SupplierServiceQuestionDraft`; slice 4 stores and shows them). There is no "held" any more.
The one-call chooser (`choiceSystem`, `checkChoice`, `settleReadings`, the second look) is DELETED; tests fake the model with
`supplier_profile_reading.test_reader.fakeReader`, whose answers go through the real two steps.

**The measurement is the hard-profile set** (`scripts/e2e/services_hard_profiles/`, 16 ZZ DEMO files, answer keys written before
any reading): `run.mjs plan | read | run --paid --cap-usd`, `score.mjs`, `record.mjs` -> `recorded.json`, replayed offline every
commit by `the_hard_profiles_are_read_offline.test.ts` at USD 0. A change to either prompt or to the reader's input breaks the replay
("no recorded answer"): record a new paid run (about USD 0.17 for the 16 files). Held out from tuning on 12 Nov: H05, H07, H10, and
the new H13-H15 (written before tuning).

**Effort.** Step A runs at MEDIUM BECAUSE OF ITS CLOCK (`effort_policy.SURFACES['supplier_doc_trades.profile_reading']`): at high it
took 45-113 s a call and 2 of 6 readings died at the gateway's 115 s wall (run 62033fde). Step B (mapping) fits at high. Parts are
4,000 characters, five at once (a 5,300-character glossy profile took 112.5 s in one call at 6,000).

**Lessons.** A model given the whole catalogue plus precision rules suppresses everything the catalogue cannot name: separate
reading from mapping. A trade card for every caption-only trade crowds out the main trades (asked as 'shown' cards, biggest first).
An umbrella built from every service of every touched trade is noise: main trades only (2+ listed services, at most 3).
Report: `docs/reports/2026-11-12-supplier-service-profiling.md` (Part 6 is the build).

**After the review of branch 2 (12 Nov, run c0afdde7 is the recording).**
- A trade is LISTED only through a stated claim mapped to a key in it, and is his at Confirm only when he ticked in it (client and server,
  `keepTickedProposed`).
- Code maps names and approved aliases first; the model maps the rest 8 a call, all at once, failed calls in halves; unmapped = owed ->
  `unavailable` -> sweep. Never silently "his own words".
- The mapping request must not depend on timing: replay found it.
- The step-A result is stored as `reading_progress` for the tab.
- Do not kill a process on a shared port without checking its cwd: other engineers run stubs and dev servers on this machine
  (I killed the slice-4 stub on 8787 once).
