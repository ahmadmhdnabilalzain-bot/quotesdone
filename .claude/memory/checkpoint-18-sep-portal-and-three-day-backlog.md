---
name: checkpoint-18-sep-portal-and-three-day-backlog
description: "CHECKPOINT 18 Sep 2026: the supplier portal is complete, 23 changes merged, the seat/wiring audit and what it found, and what is still open"
metadata:
  type: project
---

Read first on resume. The founder's tab spec stays in [[supplier-portal-tab-spec-15-sep]].

**THE SUPPLIER PORTAL IS BUILT.** Services (free text + voice, the sales engineer's deterministic rewrite, the decoration→flooring implication map), Inquiries received, Quotations submitted with the review chat, Messages (reveal-gated), Documents, Insights. Instructions 438/439 delivered.

**23 merged on 18 Sep**, in order: #726 probe seeds its own lead · #727 the alias that killed nine IT duties · #728 the journey wall + outbox watcher split · #725 the quotation review · #731 customer overview prefetch · #732 picker index + interval slow-query duty · #730 drawing pages never silently dropped · #729 Services rewrite · #733 mandatory-six fixtures · #734 founder-alert email fallback · #735 skip links · #737 three more fixtures + a guard · #736 site-wide loading states (instruction 476) · #738 the crawl fix · #739 sanctions seats · #740 WhatsApp templates + display name · #741 four red checks · #742 workflow heartbeats + orphan clocks · #743 the IT learning gate · #744 configuration recorded once · #745 the org_tasks consumer · #746 the sanctions producer + orphan wiring · #747/#748 the export gate's lock_timeout.

**WHAT THE AUDIT FOUND (the pattern: everything was built, several things were never connected):**
- **The sanctions screening had NEVER run** — zero runs ever. It posted to a function that was never built, `net.http_post` swallowed the 404, and no cron existed. Now built (UN + UAE lists, parsed, recorded honestly) and deployed. **Still switched OFF: set `app_secrets.sanctions_screen_enabled='true'` to start it — the founder was asked and has not answered.**
- **The external watchdog could never report success**: caller waited 30 s for a 110 s function. Red for 4 days over a healthy system. Fixed, with a check that fails if the two numbers ever disagree again.
- **Only 2 of 8 workflows had a heartbeat.** Four added.
- **16 org_tasks had never been read** — real customer questions 9 days old. Now 11 handled, 5 queued honestly. One Arabic question's text is CORRUPTED AT REST (`?? ????? ?????`) — cause unknown, worth finding.
- **The IT loop could not close**: 110 incidents with no cause, because only a Claude session could write one. Now 80 close from playbook entries; 12 stay parked for classes nobody has evidenced.
- **doc_extract has no caller** — nothing has extracted document text since 12 Aug. Wired but SHUT behind `doc_extract_drain_enabled` (absent) because it calls ai_gateway. Same for `email_triage_enabled`.
- **The 66 IT emails were 11 causes**; 45 of them one burst on 14 Sep. The 320×-repeating alarms never emailed him — they were quiet ledger rows.
- **The export gate's 38% failure was a LOCK, not slowness** — 900 ms unblocked; any concurrent apply blocks it. My own parallelism was the cause.

**Meta is finished** (see [[the-meta-business-portfolio-and-the-licence-facts]] for the older facts): portfolio "Quotes Done" VERIFIED, system-user token that never expires, ad account `quotesdoneads` (2173068486950097) owned by the portfolio with a Visa on file, AED, spend 0, **both switches still off** (`meta_sync_enabled`, `meta_autospend_golive`) — instruction 492 forbids any spend until he says the launch is finished. WhatsApp display name "QuotesDone" APPROVED; all 13 templates approved; `login_code` + `supplier_account_notice` (EN+AR) submitted and PENDING. The US number stays (instruction 494). There is ONE business portfolio — the app and the system user merely share the name "QuotesDone automation"; Meta REFUSES to rename the system user ("invalid System User name"), so leave it.

**Open for the founder:** the sanctions switch; the two AI-gated switches while OpenRouter is held; four unrecorded provider caps + the .ae renewal date (accountant, budgets his); deleting 3 demo customers + 9 demo leads (tags 8a5b7ad5, 414bbb3e, e959e90a); the GitHub token's Checks: Read-only.

**Still in flight at 05:40Z:** the two Arabic tabs stuck `aria-busy` after #736, plus the E2E harness session dying mid-run and mislabelling itself as a portal defect; and the founder's task that a §4 `raise notice` probe prints NOWHERE (the management API discards NOTICE and apply_sql.mjs reads none) — resumed on the agent that measured it.


**SECOND HALF OF 18 SEP (05:00-08:00Z) — 34 merged in total.** #747/#748 the export gate takes a lock_timeout (its 38% failure rate was a LOCK, not slowness: any concurrent apply blocks it; unblocked it runs in ~900 ms) · #749 a §4  probe prints NOWHERE — the management API discards NOTICE and apply_sql read none, so 35 files carried a failure verdict nobody could read; probes now return a verdict ROW and the applier exits 3 · #750 Settings had a never-ending spinner (a rejected fetch set neither state) and the harness now mints a session per context · #751 a sanctions match is BANNED and sealed (instruction 516); before it, "banned" reached exactly ONE surface — the party could still be invited, messaged, revealed to a paying customer, sign in and change a quoted price · #752 the scheduler was never down: the DETECTOR missed its own ticks and mailed "SCHEDULER DOWN" · #753 fn_sales_assist could not see company_faq — the two FAQs were written 30 minutes AFTER the questions they answer, so the remediation loop closes into a table the sales seat cannot read; the corrupted Arabic question was recovered by token-length fingerprint · #754 the tick plans by STALENESS not list order (117s → 73s → 25s) · #756 sanctions auth (verify_jwt=false + internal credential) and the UAE parser (it had been downloading a Federal Decree PDF; the real list links are icons with no anchor text) · #757 the founder demo links.

**THE SANCTIONS SCREEN NOW RUNS.** UN consolidated 3,778 entries, UAE local list 618 (343 individuals, 275 entities), **0 hits** — only 4 of 22,268 leads meet the screening predicate and all 4 are ZZ DEMO, i.e. there are no real approved suppliers yet. .

**Instructions 515/516/519:** a sanctions match is banned + sealed, never deleted and cannot re-register; backups become INCREMENTAL — "we back up the extra stuff only since the existing is already there unless they got updated" (kb_chunks is 2.6 M rows / 9.2 GB copied IN FULL nightly = ~12 GB/day, ~1.7 TB against a 2 TB Dropbox allowance).

**The lesson that cost an hour:** an agent applied 3 routines to production by accident — its dry-run wrapper cannot roll back a file that carries its own  — and every open PR blocked on the resulting drift. The fix is always a canonical file carrying the LIVE body read back with .

**Running at hand-over:** the knowledge-library usefulness audit (is kb_chunks in ANY live answering path?) and the incremental-backup build.

**Still open for the founder:** the 4 unrecorded provider caps + the .ae renewal date; deleting 3 demo customers + 9 demo leads + 3 stale rehearsal windows; correcting apply-discipline §4's notice clause; and the Insights "company ranking" panel, which tells every self-registered supplier "no quote has been submitted yet" while its quotes exist (fn_supplier_tier reads supplier_score, which holds only scraped listings).

**Known, not chased:** `fn_sales_assist` cannot see `company_faq`, so answered questions were filed as knowledge gaps; the /me route ships 1.35 MB of JS; the main checkout at C:\Users\Opera\quotesdone sits on an old detached HEAD — run checks from a worktree.

## PAUSED 18 Sep ~09:00Z — the founder hit 98% of his weekly usage

He said: "i am 98% of weekly consumptions. i think we need to chill a bit" and "hold the knowledge for now as it will consume alot of tokens. we do it on sunday". **All agents stopped.** Nothing is running.

**RESUME ON SUNDAY — the knowledge chapter, instructions 520-523.** He authorised PERMANENT deletion of unrelated knowledge and set the bar: the sales engineer must hold "the brain of combined technical directors of all fields and sectors we cover" — materials and spec depth, the brands actually supplied in the UAE per sector with equivalence classes, and the engineering reasoning, all CODIFIED as rules the comparison engine executes (OpenRouter is on hold), each with citation, effective date, EN + full AR, labelled law / practice / manufacturer data. The doctrine (five admission tests) is in instruction 521 and was to be written to  — that file was NOT created before the stop.
  - Two agents were mid-flight when stopped: the purge (had confirmed a restorable copy exists, was building the classification rule) and the authoring (was starting gypsum, the trade with real quotations to prove against). Neither deleted anything. Nothing was applied.
  - The audit that triggered it: 2,512,942 of 2,614,397 kb_chunks rows are foreign bulk (IPCC, US Code, PostgreSQL manual, Debrett's 1921, Mrs Beeton 1907, an 1899 admiralty digest); the two biggest categories are aviation/maritime and marine safety; of 176 citations ever made the bulk supplied 3 and ALL THREE were wrong answers; 7.7% embedded; **0.6% Arabic**; an embedding backfill has burned ~37 hours of DB time on it.

**#760 (incremental backups) is OPEN and NOT applied** — and it corrected my brief: the export is NOT full nightly (Friday full, weekdays incremental since 14 Sep). Real defects it fixed: incremental was chosen BY NAME not size; deletes were never recorded; the restore drill SKIPPED every increment. Its finding for the founder: the 52 Friday full copies kept 12 months are **592 GB of the ~612 GB** — the daily copies are not what eats the 2 TB Dropbox allowance, the full-copy retention is. Retention is his decision.

**Also open, unmerged:** the rating fix + Arabic dates (agent stopped mid-work; the rating defect is LIVE —  500s,  has 0 rows, no rating has ever succeeded; my ruling: stars alone suffice, comment optional).

**The founder asked and I had not finished answering: WHICH SECTORS DO WE COVER?** He believes "everything except F&B". Measured so far: the directory sells 40 trades, the taxonomy named 25 (). Names confirmed include building_materials, engineering_consultancy, power_generators, heavy_equipment, labour_supply, safety_equipment, solar, chemicals, plastics_pipes, oilfield, home_automation, logistics_moving, packaging, marine, it_services — i.e. well beyond fit-out. **Finish this list first on Sunday**, because it defines the scope of the knowledge doctrine.
