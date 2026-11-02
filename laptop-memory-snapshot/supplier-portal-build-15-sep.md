---
name: supplier-portal-build-15-sep
description: "15 Sep 2026 supplier-portal session — the three audits' findings and the three parallel builds (gate, catalogue reading, sign-up form); W4 parity deferred"
metadata: 
  node_type: memory
  type: project
  originSessionId: 5fbd934d-0d8b-4d31-9206-29d664d2fd4b
  modified: 2026-09-15T10:08:47.698Z
---

On 15 Sep 2026 the founder started agenda item 1 ([[agenda-15-sep-supplier-portal-then-audit-gaps]]) with "tomorrow has come, you can start".

**Production at the start:** 22,264 leads, 0 claimed, 0 approved, 0 quotes; `auto_approve_suppliers=true`; 15,305 `supplier_capabilities`, all directory-derived, 0 confirmed.

**What the audits found:**
- **Gate:** the mandatory six are enforced only in `supplier_api` `save_profile`, and a conflicting SQL definition, `fn_supplier_mandatory_check`, also exists.
  - `PROFILE_COLS` lets the browser write `license_expiry`, `license_doc_path` and `trade_license_no`.
  - Nothing verifies except auto-approve (no sales-engineer step).
  - An approved supplier is never re-checked, and `fn_is_matchable` lets a null status pass.
  - The expiry jobs never run.
  - Two supplier-facing texts are false: the "closes automatically" email and the "runs daily" claim.
- **Catalogues:** every profile and catalogue read needs the held LLM, so nothing is read.
  - The confirm panel shows only directory trades.
  - The `customer_api` fallback to `match_suppliers_kw` breaks exact-or-none.
  - There is no way to propose a new trade.
  - `save_profile` overwrites typed services.
  - A catalogue LLM refusal is recorded as `no_products_found`.
- **Sign-up:** the trade field is free text that doesn't match the 40 `taxonomy_trade` codes.
  - The emirate is asked twice, and fields have no required/optional labels.
  - There is no mobile format check.
  - `accept_terms:true` is always sent.
  - Raw English login errors show on Arabic pages.
  - `SupplierOnboarding.tsx` is dead code.
  - PR #679's WhatsApp step is on main and working.
- **Local checkout:** it is detached mid-rebase and 147 commits behind origin/main. Builders work in worktrees off origin/main.

**Builds launched ~06:35Z (worktrees; the orchestrator applies SQL serially):**
- **W1, gate (sales_engineer):**
  - one `fn_supplier_mandatory_six` with a DB trigger;
  - `fn_sales_engineer_verifies_supplier`;
  - `PROFILE_COLS` cleaned;
  - `fn_is_matchable` requires approved;
  - the expiry and exception sweep scheduled;
  - `save_profile` stops overwriting typed services;
  - terms accepted only when explicitly true.
- **W2, catalogue (sales_engineer):**
  - `_shared/doc_read` text goes through `fn_norm_trades` to become proposals in `CapabilityConfirmPanel`;
  - `taxonomy_trade_proposal` for new trades;
  - the kw fallback is removed;
  - an honest status when the LLM hold blocks a read;
  - `taxonomy_trade.label_ar`.
- **W3, sign-up UI (customer_support):**
  - a trade picker using the codes;
  - the emirate asked once;
  - required/optional labels, a UAE mobile check and a real terms flag;
  - AR login errors;
  - dead onboarding code deleted;
  - AR document labels.
- **W4, parity (deferred until W1–W3 merge, since they share `SupplierPortal.tsx`):**
  - one combined overview call and prefetch;
  - an unread badge and notification centre;
  - a supplier quote PDF and receipts;
  - an orders view and an activity timeline.

**Progress (15 Sep ~07:20Z):**
- **#695, W3 sign-up:** merged as 2bc38f1. Two reviews approved it. Follow-up for the nits (onboard_sub spacing, a Required label on the WhatsApp answer) is in flight.
- **#697, W2 catalogue:** SQL `a_suppliers_documents_propose_trades_and_a_new_trade_is_reviewed_not_dropped.sql` applied; merged as f9ea692; edge deploy green.
- **#696, Dropbox drain + picker timeouts:** SQL `an_export_day_reaches_dropbox_when_it_finishes.sql` applied; merged as c0aab65. `dropbox_backup` is v59 (07:09Z).
- **#699, #695 nits:** merged as de78477.
- **#704 (Dropbox token reuse and single-flight refresh, claim release) merged as 9948090.** #706 (the schema mirror after the #703 drop) merged as a9534b8; main is green (repo/db agree + checks).
- **New founder tasks ~08:00Z:**
  - rewrite or retire the dead licence-gate checks in `verify_supplier_docs.mjs`;
  - the kyc accept_terms double certificate (kyc signs + trigger z21 signs → an orphan in signed-terms).
- Three helpers run demo fixtures on production concurrently; all were told to scope leftover counts to their own run.
- **#703, turnkey path exact-or-none:**
  - Merged as 3c327e0. The drop file `the_turnkey_path_asks_the_sales_engineer_and_the_keyword_matcher_is_dropped.sql` is applied AFTER the customer_api deploy (the reverse order), so a schema-mirror follow-up PR is needed after the apply.
  - `a_supplier_who_ignores_holds_is_warned_then_held.test.mjs` is broken by the six-gate; the demo-factory builder was told to fix it.
- **Audit re-read (agenda item 3) done at ~07:50Z.** Builders launched:
  - legal: re-issue the 6 legal_documents that still print the CR number;
  - outbound: the supplier_api search `claimed_by` leak, `fn_email_sendable`, `fn_notifications_release_held`, the contact_submit rate limit, the `supplier_account_notice` template (no Meta submission);
  - money: `qd_on_refund_resolved`, the `fn_gl_post` status check, two invoices per sale, the stale `control_mode`;
  - credentials: rotation wiring plus a third-party plan doc.
- **Stripe TEST webhook** we_1UFagpC45SqX5pVbj9BIZUSN also got the 5 dispute events at ~08:25Z (founder: "if its useful add it", instruction 433). Finding `duty:payment:test:webhook` closed by exact key.
- **#707 (the missing `scripts/kb/run_embed_backfill.mjs`)** merged as adb717c. A test run embedded 1,200 chunks with 0 failures.
- **#712 (certificate issued once):**
  - **The real race** is two concurrent `compliance_archive` sign calls: kyc + z21, or supplier_api then kyc. Measured 2 certificates in those cases.
  - **Fix, in compliance_archive only:** reuse a certificate newer than the acceptance, save with compare-and-set on the path, and the race loser deletes its render. No SQL.
  - **Orphans:** 15 demo orphans swept. 22 REAL orphaned certificates (3 Jul–13 Aug; 16 customer, 6 supplier) are listed and untouched; decide later.
  - The merge chain is running.
- **#714 merged as 7ec6773; resilience_ping v91 is live at 08:52Z.** It sends the service key to the accountant function; before that, 151 calls in 24 h were 401s, so fn_accountant_duties had never run.
- **#713 SQL applied ~08:58Z** (`fn_email_sendable`, `fn_notifications_release_held`, a guard that also fires on UPDATE). Its probe was wrong twice:
  - to_role 'admin' made a10 drop the row;
  - a `.invalid` address is demo, so the capture trigger suppresses it on insert.

  I fixed the probe and it now gives PASS=t. The probe edit is under independent review; the merge waits on that and on CI.
- **#719 (reversed dues are never owed) JUMPS the queue: next after #713.**
  - The old predicate would treat a reversed charge as owed: court filing, supplier ban, founder alerts, and counted in every finance total.
  - `fn_ban_overdue_dues` was anon-callable.
  - The fix is one predicate, `fn_supplier_due_is_owed`, used in 13 routines plus the finance_kpis view. Dashboard and forecast numbers move ON PURPOSE (settled, waived and cancelled leave receivables).
  - #272 is safe until 21 Sep: its supplier lead is gone and it isn't due yet.
- **Queue:** #713 → #719 → #711 → #716 → #718. #713 merged ece6c4d; #719 SQL applied (13 routines, probe CHK ok; its prod check read the predicate via read_only role → 42501, fixed to read prosrc) and merging.
- **The CEO sweep works (the #718 tick at 09:30Z):**
  - It decided 100 sales_engineer reports (status completed); 714 are still 'sent', about 7 h of ticks at 100 per tick.
  - 0 founder alerts; every notification in the window was demo → suppressed.
  - **Follow-up (not built):** the total rose 796 → 814 during the tick. The smoke/E2E demo sends are suppressed by design, and the sales engineer's delivery watch then files each one as "did not arrive (not_sent)" to the CEO. That's noise: the watch should not report a send suppressed as demo (last_error 'captured: a demo recipient…').
- **REGRESSION I caused (found ~10:05Z):**
  - **Cause:** #716's STORAGE SWEEP plus #720's LEGACY EXPORTS sections made `fn_enqueue_doc_backups()` take 50.65 s. dropbox_backup calls it via PostgREST under the 8 s statement_timeout, so from 09:24Z EVERY enqueue failed with a statement timeout. That logged once at 09:29Z, then went silent behind a 60-min log throttle. ZERO new doc_backups rows were created for any document, not only the backfill.
  - **Why the probes missed it:** they ran as postgres, where the 8 s limit doesn't apply.
  - **Stopgap:** a manual postgres enqueue every 20 min (loop b128msq8g, 6 runs); the first run queued 400.
  - **Fix builder (it_engineer):** split off the backfill routine, make the sweep cheap, raise a finding on any enqueue failure.
  - **Lesson:** after applying anything that changes a routine called over PostgREST, time it under `set local statement_timeout='8s'`. A green probe run as postgres proves nothing about the 8 s path.
- **QUEUE EMPTY ~09:40Z:** #716 merged as 486d506; #720 applied (its probe returned CHK ok, so no export is pruned without a verified copy; the 13 GiB backfill has started) and merged as 2cb8c26. Every PR from 15 Sep is merged.
- **Founder confirmed the mandatory six are final** (instruction 434); the trade stays optional. He wants to review the portal "one by one". A ZZ DEMO screenshot run of every portal tab (EN and AR) is queued behind the post-deploy smokes; it never uses a real login.
- **#718 merged as 49e96ca (~09:21Z).**
- **#716 SQL applied ~09:24Z.**
  - Its branch had graphify-out conflicts as well as the MANIFEST ones (a builder had committed graphify output); took main's graphify-out.
  - The worktree agent-ab3cedc0a172b5c5e was on #720's branch and had to switch to #716's first.
  - The probe printed CHK ok: "swept once, 200 then 200 rows, 4 of 4 exclusions held". The backfill of 893 files has started.
  - Mirror committed at 1ef1b66; the merge chain is running. #720 comes after #716 merges.
- **Legal is proven on the LIVE site ~09:20Z.** Checked 12 pages: /{en,ar}/{terms,privacy,refund-policy,disclaimer,complaints,acceptable-use}. All return HTTP 200 with 0 × "2883503" and 11–15 × licence "1633275"; Vercel deploy 16c1761 succeeded. (There is no /legal/ path; the pages sit at /[locale]/<doc>.)
- **#721 (payment duty ignores test-mode demo rehearsals) merged as 1983a83.**
  - The rule is test mode + an isDemoEmail payer; live mode is never excluded and metadata is never trusted.
  - No SQL. The 8 duty:payment:test:* findings should close through fn_it_duty_settle on the first IT run after resilience_ping redeploys.
- **#711 merged as 16c1761. #718 SQL applied ~09:18Z** (9 routines; fn_it_loop_tick now runs the CEO and originator steps; check 4/4); merge chain running.
- **#716 APPROVED** after the round-3 re-review. **#720** (head 7faa292) is STACKED on #716:
  - it files the 5,199 legacy exports (13.15 GiB), at most 200 queued at a time;
  - storage deletes an export only when its backup row is done AND verified;
  - Dropbox copies are pruned only after the storage delete, and verified ones only. That closes a hole where a never-uploaded file was "pruned".
  - ETA 2–4 h after apply.
- **Apply order, serialized:**
  1. `every_stored_document_source_is_registered_for_backup.sql`
  2. `every_stored_file_reaches_dropbox_and_the_backup_gap_duty_raises_only_real_gaps.sql`
  3. probe `every_stored_file_reaches_dropbox.probe.sql`
  4. merge #716
  5. update #720, then apply `every_old_export_reaches_dropbox_and_no_export_is_pruned_without_a_verified_copy.sql`
  6. probe `no_export_is_pruned_without_a_verified_copy.probe.sql`
  7. merge #720
- **PDPL note (undecided, for the PDPL owner):** export pages are whole-table dumps, so erasure never purges an erased person's rows from Dropbox copies until retention prunes that day.
- **#718 (CEO reads every report; two-way handoffs):**
  - FINAL APPROVE at head 8e1f56c, after 4 review rounds. The fixes covered stubbed/cancelled sends counted as reached, reveals closing with the supplier send unverified, a stuck queue head, and more.
  - Apply order: merge main, keep the MANIFEST line last, then `the_ceo_decides_every_sales_engineer_report_and_every_sender_closes_its_handoff.sql` with `--apply --ddl`, then the check, then the mirror. NEVER re-apply `the_it_engineer_closes_every_loop_it_opens.sql` afterwards (it resets the handoff kinds).
  - Follow-ups:
    - sales_engineer/index.ts:377 ask_accountant logs answered billing questions as "not answered" until the accountant verifies them; fixing it needs a deploy;
    - `fn_sales_engineer_reports_complete` waits on non-'done' remediations;
    - no WhatsApp/SMS attempt before a recipient is marked "unreachable";
    - the 200-row re-check scan cap.
- **#711 (legal registry without CR 2883503) SQL applied ~09:13Z** with `--ddl`, since the data-only file is otherwise skipped. 6/6 checks pass, including production: no live legal doc, signed body, knowledge row or routine carries the number. 0 real customers or suppliers are forced to re-accept. Pushed; the merge chain is running (the merge also redeploys the site's legal.json via Vercel). Next applies: #716 and #718, both awaiting re-review.
- **#719 merged as 866d463 (~09:12Z).** Its DB check failed twice because Supabase's logs API returned HTTP 500 ("Failed to get project's logs") inside the attack-pattern step, which fails closed. This was intermittent: main passed at 09:00 and a manual log query answered. Fixed by re-running the failed job; the check was never weakened. Next apply is #711.
- **ACCOUNTANT RAN FOR THE FIRST TIME at 09:00:37Z** (resilience_ping v91): HTTP 200, duties errors [], monthly close Aug 2026 filed to the CEO (net AED -1,955.45, cash 582.96), refunds executed 0. Notifications created were all demo → suppressed; 0 founder alerts.
- **Payment duty noise:** 8 open duty:payment:test:* findings = Stripe TEST-mode demo reveals (6× AED 3,728.30 sessions, 2 refunds) whose books the harness tore down. A builder (accountant) is making the duty recognise provably-demo test objects; live stays strict.
- **GitHub token lacks Checks read:** the live_code IT reading gets 403 on check-runs (basis unavailable, no finding). Needs the founder to add "Checks: Read-only" to the fine-grained PAT — asked 15 Sep.
- **Quiet window done 08:43Z:** #708 merged as 514ba46; #717 merges next, then the #714 apply.
- **#716 (backup-gap registry):**
  - Built. Of the 51 findings, 44 are real gaps (now filed by a storage sweep, backfill 893 files / 51 MB) and 7 are reasoned exemptions (the PDPL erasure ledger, the doc_backups destination, knowledge source labels, demo-assets).
  - Its round-3 fix still needs a re-review; the builder was told to get it.
- **DECISION (founder's standing rule "never lost"):** the 5,199 dated export files (13 GB, 23 Jun–7 Sep, possibly the only copy of rows deleted 7 Sep) WILL be backed up to Dropbox, and nothing may prune an export without a verified Dropbox copy. The builder is making this a separate PR.
  - It's safe meanwhile: `fn_backup_prune_mode()` = dry_run unless app_secrets `backup_prune_mode` = 'delete'. The last prune run (06:31Z) was dry_run.
- **#712 merged as bb6b939 (~08:40Z).** The post-deploy smokes for 5d746e7 and bb6b939 ran at the same time (demo leads 124997-124999, tag 3310b21b, belong to them). #708, then #717 (verify_supplier_docs rewrite, no SQL, 14/17; the 3 licence-reading checks are blocked by the OpenRouter hold) merge in the quiet window before the #714 apply. #714 is prepared locally in worktree agent-a00f64992b4f0fe39 (main merged, MANIFEST line restored at fad46fb, NOT pushed).
- **Merged ~08:35Z:** #710 as 5d746e7 and #709 as fb76178 (SQL `a_rotated_credential_stays_valid_until_the_run_that_retires_it.sql` applied). The quiet-window chain then merges #712 and #708 (no SQL). Next applies, one at a time: #714 heartbeat, #713 outbound, #711 legal, #716 backup-gap.
- **#709 (credential rotation):**
  - **Rotation is running:** it lives in the daily `rotation` duty inside `fn_it_duties_scheduled`. The audit's "not running" was wrong; `rotated_at` is NULL because nothing is due until ~1 Nov (90-day threshold).
  - **Three defects fixed:** the 24 h overlap expired before the next run could extend it (now 72 h); the extension compounded; two credential labels were mismatched.
  - Adds `docs/security/THIRD_PARTY_KEY_ROTATION.md` and 12 `it_expiry` rows for third-party keys.
  - Founder history: 9 Sep he said "no need for credentials rotate, remove it", then on 14 Sep approved the IT duties including rotation. The later approval was treated as current.
- **The seat audit claim "fn_it_duties_scheduled has no caller" is WRONG:** the hourly otp duty ran 13 times today. The heartbeat builder was told to find the real caller and never double-call.
- **#711 (legal):** 6 docs re-issued, plus 3 agent_knowledge rows and 3 kb_chunks. 0 real customers or suppliers are forced to re-accept. Data-only apply; the CI never ran because of the MANIFEST conflict (I merge main at apply time).
- **#715:** merged as 41369de. It adds the dropbox_access_token name to the mirror, which unblocked every PR's DB check.
- **#710 (money):**
  - SQL applied ~08:22Z in this order: `only_a_draft_journal_can_be_posted.sql`, then `control_mode_is_retired_with_its_template_and_its_minutes.sql`. MANIFEST reads 0.
  - The mirror was pushed and the merge chain is running; the merge deploys reveal_invoice.
  - qd_on_refund_resolved was already gone: the one rail raises the 3% via z40 → fn_accountant_refund_settled → fn_accountant_raise_nonresponse_charge.
- **#707:** updated from main; its merge chain is running.
- **Open PRs:**
  - #708 holds test;
  - #709 credential rotation;
  - #711 legal CR;
  - #712 certificate once;
  - #713 outbound (the DB reviewer's re-check is pending);
  - #714 heartbeat (the classification checks are failing; the builder was told to fix the cause).
- **Probe follow-up (reviewer nit on #713, not built):** `the_demo_guard_holds_and_releases.probe.sql` has never tested a NON-demo recipient on INSERT; its only address is `.invalid`, which is demo, so capture suppresses it. Add a second address outside `fn_is_demo_email`'s patterns (example|test|invalid|localhost), e.g. `@guard-probe-real.qd-review-only`, in the same always-rolled-back block, and assert it is 'held' and not 'suppressed'. It's safe because send_outbox reads committed rows only.
- **Loose ends, 15 Sep ~08:15Z (not yet built):**
  - **Secret keys made at run time:** #704 inserts `dropbox_access_token` into app_secrets at run time. The schema mirror lists key names, so every open PR's DB check went red at ~08:02Z; fixed by mirror PR #715. The key should be seeded by SQL so the mirror carries it first.
  - **`fn_kb_embed_harvest`:** casts the response body to JSON before checking the status. One non-JSON body blocks harvest.
  - **kb-embed-backfill.yml:** its comment claims 531 rows/min; ~179 was measured, so the ~2.44M-row backlog is years away at 30 min/day.
  - **`drain_authoritative_embeddings.mjs`:** dead code (calls kb_embed, deleted 8 Sep).
  - **Stripe test webhook:** its finding `duty:payment:test:webhook` was closed in error at 08:10Z and REOPENED. Asked the founder whether to add the dispute events to test mode.
- **Founder actions, DONE 15 Sep ~08:10Z (he said "yes for both"):**
  - **Stripe:** the live webhook we_1TqVtRC45SqX5pVbEbnsquAL now has 14 events: the original 9 plus the 5 `charge.dispute.*` from `_shared/stripe_events.ts`. Changed through the Stripe API, `enabled_events` only (founder_instruction 425).
  - **Access:** `it_access_known` now holds vercel/ahmadmhdnabilalzain-1500 and dropbox/dbid:AADF32qp79e_CC8vnHWFCsBeJi1nrvRy03k, accepted_by founder via `fn_it_access_accept`; both `duty:access` findings are closed (founder_instruction 426). Don't re-ask either.
- **#702, W4 parity:**
  - merged as 3bfa2e9 (no SQL, 3 reviews APPROVE WITH NITS);
  - one `dashboard` action replaces 3 overview calls;
  - unread badge and bell;
  - supplier `quote_pdf`, `receipts` and `receipt_pdf`;
  - `leads.emirate` is set from the first service emirate;
  - the activity timeline was not built.
- **#701:** merged as 4cf0cd2. Redeployed supplier_api v66 and supplier_catalog_ingest v56 (07:47Z); supplier_portal v56 (07:41Z) came from the #702 merge.
- **#701, Arabic trade words:**
  - SQL `an_arabic_document_names_its_trades_in_arabic.sql` applied (MANIFEST 0; the push was 442c64f); the merge chain requires the checks workflow;
  - aliases for all 40 codes, and `fn_norm_trades` folds text with `fn_ar_norm`;
  - execute on it is revoked from public, anon and authenticated.
  - Proven live on phrases:
    - النجارة والديكور → joinery + interior_fitout;
    - التكييف → hvac;
    - ألمنيوم وزجاج → aluminium + glazing;
    - السباكة → plumbing;
    - "هيئة كهرباء ومياه دبي" and "حديقة الصفا" → none.
- **#700, e2e demo supplier meets the six:** merged as d0f2512. The proof run passed with 0 leftovers. The demo_factory fix for the staging scripts is a separate builder, told to build on #700's `makeSupplier` `approval` option.
- **#698, merged as 325a3e1 (07:14Z).** W4 parity plus the `leads.emirate` fix were launched right after, as one builder.
- **#698, applied ~07:10Z:** the first apply failed and rolled back whole, because both probes inserted the generated column `leads.is_demo`. Fixed by dropping that column from the inserts; the ZZ DEMO name, the example.invalid email and the fixture phone still make each row demo. All 3 files are now applied and the MANIFEST reads 0. Merge conflicts with #697 were import lines only in `supplier_api` and `supplier_portal`, resolved as a union minus the dead `registrationMissing` and `SUPPLIER_AGREEMENT_*` imports.
- **#698, W1 gate:** waits for #696 to merge. Then apply in this order:
  1. `the_mandatory_six_have_one_definition_and_the_sales_engineer_verifies.sql`
  2. `the_sales_engineer_closes_a_registration_left_incomplete_for_fourteen_days.sql`
  3. `a_supplier_is_matchable_only_once_approved.sql`

  Deploy `supplier_api`, `supplier_portal`, `kyc` and `resilience_ping` (merging to main does it).
- **Open follow-ups:**
  - Turnkey-path keyword matching (a builder is in flight).
  - Arabic-only documents propose no trades (`taxonomy_trade` aliases are English only).
  - `leads.emirate` is no longer set at sign-up.
  - W4 parity.

**Decided without asking:**
- "Name" means company name; the contact name is optional.
- The WhatsApp answer stays required (founder instruction 391).
- Sign-in by mobile is unchanged, per [[no-observe-mode-plain-login]].
