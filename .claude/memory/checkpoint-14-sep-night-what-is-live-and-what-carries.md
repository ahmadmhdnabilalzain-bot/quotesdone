---
name: checkpoint-14-sep-night-what-is-live-and-what-carries
description: "READ FIRST on resume — state at ~22:10 UTC 14 Sep 2026, what's live, open PRs, founder decisions pending, carry-overs"
metadata: 
  node_type: memory
  type: project
  originSessionId: 5fbd934d-0d8b-4d31-9206-29d664d2fd4b
  modified: 2026-09-15T01:10:05.283Z
---

Provisional checkpoint, written at about 22:10 UTC on 14 Sep 2026 while helpers were still running. **Verify every
open item against GitHub and production before acting**; this is point-in-time. Next session's agenda:
[[agenda-15-sep-supplier-portal-then-audit-gaps]].

**Live.** A read-only audit found all 100 PRs merged to main since 13 Sep 18:00Z live in production:
- canonical `--all` = 0;
- all 48 changed functions redeployed after their merge;
- Vercel production = main.

Merged tonight:
- #661: IT duties 19–24 plus signed applies.
- #673: preview builds render without a DB target.
- #668, #669, #670 and #671.
- #675: restore-check lock bound plus an overdue alert.
- #677: WhatsApp notices must be UTILITY templates.
- #678: the threshold test accepts the "not recorded:" caps.

Branch pushes never deploy. `deploy-functions.yml` deploys only on main or a manual dispatch; I verified this.

**Open PRs at checkpoint:**
- **#672, backup retention.** Applied to production in dry run. Main's "repo and database agree" is red until it
  merges, because its 13 `fn_backup_prune_*` routines are live and not on main.
  - Never set `backup_prune_mode = 'delete'` until a revived full copy completes and `backup_prune_log` has been read.
  - The first complete full copy of each month is kept forever, and documents and inventories can never be
    selected (founder_instruction 383).
- **#676, statement via the live mailbox.** Code reviewed CLEAN. The last steps are tightening the VAT pattern to
  `value added tax - output`, applying, deploying `resend_inbound` and `accountant`, then re-reading email
  4073be03-2dfa-4fd2-8a7a-100ce089fcad.
  - Expected result: posted 1000/3000 1,000.00, 1000/7000 0.86, and 6300 for 199 ×2 and 9.95 ×2; closing balance 582.96.
  - Supersede inbound_messages #152.
- **Fixture-number guard.** Top priority. Tests sent 4 REAL SMS to +971500000042 (14 Sep 21:17–21:23Z) and one to
  …099 (13 Aug).
  - `login_otp`, `kyc`, `mobile_otp`, `send_sms` and `wa_inbound` had no fixture check; only `send_whatsapp` did.
  - A shared guard is being built.
- **#679, WhatsApp confirmed plus OTP inside sign-up** (founder_instruction 391). Waits for the guard.
  - Twilio silently falls back to SMS today, and the live #657 screen wrongly says "WhatsApp"; #679 fixes that.
- **Merged ~22:50–23:00Z:**
  - #676, which carries #672 (bfd2b0c);
  - #680, the Dropbox resume-offset fix (0f8f30e);
  - #568, the audit reports Part 1, 126 backend and 98 website findings (73db36d).

  `docs/audit/BACKEND_AUDIT_AND_ONE_YEAR_PLAN_2026-09-14.md` and `docs/audit/WEBSITE_AUDIT_AND_UPGRADE_PLAN_2026-09-14.md`
  are on main: the "audit from ~12 Sep" the founder means. They are Part 1 only, with no refutation pass yet.
  Main's "repo and database agree" is green again on 73db36d, and the backend deploy passed on 0f8f30e. Both
  post-deploy smoke runs on 73db36d passed (runs 34903033122 and 34903071871).
  Caveat: #684 was applied at 22:17Z and isn't merged, so main's database check will read red on the next push
  until #684 merges.

**Founder decisions, made ~22:40 UTC 14 Sep:**
1. **"delete test data"** (founder_instruction 407, open until done). The it_engineer is deleting only the fixtures:
   e2e runs 9209c732 and f41ef6de (2 ZZ DEMO customers, leads 123358/123375) and `phone_verifications` in the
   `+9715000000XX` range, with before and after counts. `wa_answer_log` and `agent_actions` are kept under the
   never-purge rule. Close 407 with the counts.
2. **"sign up keep the whatsapp option"** (founder_instruction 406, done). #679 keeps its three answers: same
   number / different number with a code / "I do not use WhatsApp".

**Changed tonight:**
- `gl_settings.bank_booking_on_hold` 1 → 0. Twilio messaging service MG81bbdce3da0da54cee15ce9951db63c4 (sender
  +12183166814) is wired to Verify WhatsApp. The Vercel Preview Supabase env entries were deleted.
- `app_secrets.github_token` was replaced; it expires 2027-08-31.
- Scheduled task `quotesdone-meta-whatsapp-otp-check` fires 17 Sep 10:00 Dubai. It checks Meta verification, and
  once the UTILITY replacements are approved it switches the 3 MARKETING templates with #677's `--switch`.
- 71 Verify auth templates are "received" at Meta, waiting on business verification.

**Carry-overs (after the supplier portal):**
- Customer terms v7 still print the commercial register number the licence does not print (the number is recorded only in docs/legal/company_identity_sources.json); founder_instruction 341 says trade licence only.
  Needs a v8.
- **Backups, investigated 22:10Z.**
  - The 609 pending, 28 waiting_source and 14 abandoned `doc_backups` rows are ALL `entity='zz_demo'` rehearsal
    rows. Real rows pending: 0. The summary is 122 expected / 122 backed up / 122 verified.
  - The pile grows with every rehearsal. Fix: PR "sales_engineer: a rehearsal never queues a backup", which makes
    `trg_doc_backups_admit` drop zz_demo rows and abandons the existing 637.
  - **The real gap:** no table export since 2026-09-07, `table_export_run` has 0 rows, and NO table export has ever
    reached Dropbox. The #664 pieces were deployed 21:56Z, the first run is due 23:00Z, and the overnight watcher
    checks it. The finding `duty:restore_table:export_stale` is correct.
  - **The Dropbox daily health check has never existed in production.** Fix: **PR #685**, "it_engineer: Dropbox is
    checked every day, login and space". It was reviewed CLEAN at ~22:45Z, verified by running it, and is NOT
    applied. It's 5th in the apply queue, after #684, #681, #682 and #683. At its slot it adds one comment naming the
    decision that a failed login plus an unread space reading leaves the open space finding untouched for that tick.
    - A real reading on 14 Sep: Dropbox is **11.6% full** (62.62 of 539.02 GB, pro individual), so there's room to
      backfill the 23 Jun–7 Sep exports. Their size isn't measured yet.
    - It also fixes a real bug in the shared `dropbox.ts`: no-argument endpoints sent an empty body, and
      `get_space_usage` answered 500. They now send `null`.
    - At apply: `apply_sql` the file, then deploy `dropbox_backup` and `resilience_ping`.
  - **Still to carry:**
    - backfill the 23 Jun–7 Sep exports into Dropbox once the quota is known;
    - genuine unmapped backup sources (`duty:backup_gap:*`): `quotes.original_file_path`, the `quote-files` bucket,
      `messages.attachment_path`, `customer_calls.recording_path`, `refunds.doc_path`, `supplier_dues.*`,
      `support/wa_document_intake`;
    - an open finding: the Dropbox account owner has not been accepted.
  - Apply order is serialized: test-money PR, then memo masking, then the two backup PRs.
  - Old #633 commit d49b9253, the Dropbox health check (login, 70%/85% quota, playbook), never landed.
  - It must be rebuilt through main's new-bug loop, not as a second founder email.
- 36 `founder_instruction` rows are open; 24 were closed with evidence tonight. Real gaps:
  - 143: hold notices aren't on WhatsApp.
  - 213: IT duties 1–8 have no runs.
  - 208: the backup backlog above.
- WhatsApp: 3 templates were approved as MARKETING; UTILITY replacements were submitted.
- The first daily table export (#664) is due 23:00 UTC. The `restore_table:export_stale` and `:restore` findings close
  after it.
- The Vercel CDN warm-up was closed (#674): the Dubai edge (bom1) can't be warmed from GitHub, Supabase or a Vercel
  function.
- WhatsApp templates (#677 merged 251dd15). The UTILITY replacements were submitted and are "received" at Meta:
  - `customer_new_quote` ar: HXa6cd23eef4886b8496136387f24c4780
  - `supplier_doc_expiry` ar: HXbeac35e3f45aec40c85b4a7d5e71f6a0
  - `supplier_new_inquiry` en: HXf2241e60cde40cc72f759c5e7f8900e4

  The 17 Sep task runs `--switch`. Two gaps found:
  - `supplier_account_notice` has NO template, so its WhatsApp stays queued and only email goes.
  - `control_mode_code` in `wa_template_sids` points at a rejected AUTHENTICATION template, and nothing sends it.
    Remove it.
- **August statement booked (22:02Z 14 Sep):** gl_journal #692–#697, all posted.
  - Owner capital: #696, Dr 1000 / Cr 3000, 1,000.00.
  - Interest: #697, 7000, 0.86.
  - Fees: 4 × 6300 (199, 9.95, 9.95, 199).
  - Closing balance 582.96 on 2026-08-31.
  - founder_instruction 357 and 369 are closed.
- **Test money reached the real books.** The same booking tick posted gl_journal #690 (`commission_accrue`, Dr 1110
  3,978.30), sourced from `supplier_dues` #272. That is an E2E fixture (run e8095fdb, 16:49Z), and its supplier 123743
  and transaction d972947c were already deleted, leaving the due orphaned.
  - **PR #682** "accountant: test money never reaches the books". The review, ~23:00Z, was NOT clean, and #682 is NOT
    applied, so #690 is still posted. Fixes requested:
    1. Add both SQL files' MANIFEST lines (2 gaps).
    2. The earlier "proven" claim in commit 2ae91bf had no negative probe. Add real negative probes for a posted
       test-mode fee, a posted zz_demo bank charge, and an in-batch posting while the hold is 1.
    3. Close the gap: the loop check must also fail on a POSTED bank or capital journal whose `bank_statement_line`
       no longer exists (the #690 orphan class).
    4. After #681 merges, one real E2E through the changed teardown must prove `leftovers()` (now including
       `supplier_dues`) is 0.

    **Update ~23:10Z:** all three review findings are fixed at head 64ba908, as a new commit with no rebase:
    - the MANIFEST lines are in, with 0 gaps;
    - real negative probes are in savepoints, and the loop test passes 7/7 only if every one fires;
    - the orphan bank journal now fails the check.

    **The delta re-review is CLEAN (~23:30Z).** One open fact was verified by me read-only on production: 6 posted
    bank journals, 6 resolve to `bank_statement_line`, 0 orphans, 0 zz_demo. Still NOT applied; it's 3rd in the
    queue.
    - At its turn, the rolled-back rehearsal must pass under #684's tightened `fn_gl_journal_immutable`.
    - After #681 merges, one real E2E through the teardown must show `leftovers()` = 0.

    When applied, it will:
    - reverse #690 through `fn_gl_reverse` (new `source='reversal'`, `source_ref='690'`; #690 goes void);
    - set #272 to `status='reversed'` with a new `status_reason`;
    - add one guard, `fn_gl_fixture_or_orphan`, to every `fn_gl_sync_business` branch, `fn_expense_post_to_gl` and
      the incident-fix booking. Fixtures are skipped silently; orphans are skipped and open a `ledger_orphan`
      accountant finding;
    - make the E2E teardown delete money rows before the lead or customer, and stop if a due is already in the
      ledger.
  - The scan found only #690 live. #98, #131 and #140 are void and already reversed. `refunds` and `transactions`
    hold 0 rows.
  - The IT cleanup helper was told not to touch money or ledger rows.
- **Bank numbers in journal memos: FIXED LIVE, PR #684 unmerged.**
  - Applied 22:17Z, signed from bfd2b0c, before the helper got my hold message.
  - `fn_mask_bank_text` masks IBANs to `[IBAN]` and 8+ digit tokens to `[ref]`.
  - A trigger masks every `gl_journal.memo` write, the bank booking routines mask before truncating, and
    `fn_gl_journal_immutable` allows a posted memo to change ONLY to its masked form.
  - Redaction: 7 of 66 memos matched, now 0. Every other column and line fingerprint was unchanged. Verified
    independently: 0 IBAN memos, 0 memos with 8+ digit runs.
  - Being added: masking in `fn_accountant_bank_reconcile`'s payout-match evidence (the same leak).
  - **The review (~23:25Z) was NOT clean.**
    - **CRITICAL:** the LIVE `fn_mask_bank_text` uses a literal `replace()` per token, so overlapping tokens leak
      digits. Read-only on production, `'90000000 090000000X99999999'` returns `'[ref] 0[ref]X99999999'`: 9 digits
      survive, and the function isn't idempotent. No real memo leaks today (0 rows match). No new bank memo is due
      before the September statement, so there's no live exposure tonight, but it must be fixed before merge.
    - **Pre-existing loophole** in `fn_gl_journal_immutable`: a posted journal moved to a status other than posted
      or the controlled void becomes rewritable.
    - The helper is fixing both: a single positional mask pass or fixed point, overlap and idempotence probes, and
      posted journals may change only to the masked memo or to void via `fn_gl_reverse`. NOT re-applied yet; a
      delta review comes first.
    - **Fix pushed at 1320737 (~23:35Z), not applied.** The mask is now one positional regex pass. On production,
      read-only, the reviewer's input gives `[ref] [ref]`. There are 10 overlap and idempotence probes. A posted
      journal may only mask its memo or go void with the link (exactly `fn_gl_reverse`'s statement), and 8
      refusals are probed. A re-scan finds 0 of 66 memos would change.
    - **Void journals are terminal**, pushed at head **eab36e5** (not applied): after the reversal, no change and no
      delete, with 9 refusal probes, and #682's reversal path still passes. It also blocks a latent path:
      `fn_gl_post` doesn't check status and would re-post a void journal. The single review of `8b257b4..eab36e5`
      came back **CLEAN**. **Re-applied and pushed at head dbbddfe (~22:55Z 14 Sep UTC).**
      - All 6 routines read back identical, the embedded probes passed, and `canonical --all` = 0.
      - On production: `fn_mask_bank_text` gives `[ref] [ref]`, and 0 of 66 memos carry a number.
      - **MERGED: #684 as 37971d8, then #681 (the test-number guard) as 7ea8791**, ~23:00Z 14 Sep UTC. Main's deploy
        for 7ea8791 must finish before any E2E runs, since the guard only protects once it's deployed. A watcher is
        confirming the function versions.
      - **#682 APPLIED (~23:05Z).** Journal **821** reverses #690 (#690 is void and linked; the pair nets to zero at
        7,956.60 each side). `supplier_dues` #272 is `reversed` with its reason, and the `fn_gl_fixture_or_orphan`
        guard is live in every booking path.
        - `canonical --all` = 0, and the accountant loop test passes 7/7. The mirror was pushed as 4e34065, and a
          background merge runs once it's green.
        - The helper applied BEFORE the E2E. That's accepted: the booking guard had to be live before any E2E could
          raise a fixture charge.
        - **#681's guard is DEPLOYED.** Run 34906522034 succeeded at 23:01:11Z. On production: login_otp v63, kyc v60,
          mobile_otp v65, send_sms v60, wa_inbound v90 and send_whatsapp v73, all updated 22:59–23:00Z, after the
          22:56Z merge. From here no E2E can reach Twilio with a fixture number. The E2E gate is open for #682's
          teardown proof and #679's journey g.
      - **Tonight's first table export is RUNNING.** `table_export_run` stamp 2026-09-15, kind full, started
        23:00:35Z, heartbeat live. The 23:40Z watcher confirms it finished and reached Dropbox; its restore and
        export-stale findings should close after.
      - **At 23:40Z it had NOT finished.**
        - Attempt 1 failed with `kb_chunks: upload 2026-09-15/kb_chunks/page_0103.json: Forbidden` after pages
          0–102.
        - Attempt 2 is alive (heartbeat fresh) and restarted kb_chunks, at page 52, 205 MB done, 255 objects /
          310 MB in the bucket for tonight.
        - Not size (max page 4.4 MB against a 100 MB limit) and not MIME (json is allowed).
        - **Attempt 2 FAILED at 23:45:51Z on the SAME page 103**, with the same Forbidden error. It reached page 102
          at 23:43:48Z, so the failure is deterministic, content-based, not time-based. Status is `failed`,
          attempts 2, 396 MB of partial objects under `backups/2026-09-15/`. NO fresh full database copy tonight.
        - Prime suspect, UNPROVEN: a WAF in front of Supabase Storage answering 403 to attack-looking text in page
          103's rows. kb_chunks holds the IT/cyber knowledge (`it_security_deep`). The helper is checking the log body
          and the page content, plus retry behaviour, the partial objects, and whether a loud finding opened.
        - Cause UNPROVEN. My "the credential expires about 20 minutes in" idea doesn't fit the measured pace and is
          withdrawn.
        - **CAUSE PROVEN (~23:55Z): Cloudflare's WAF in front of Supabase Storage** refuses page_0103 as an attack.
          kb_chunks rows 185295 and 185342 are OWASP SQL-injection text.
          - Evidence: the gateway logs show no line for page 103, and a replay got the Cloudflare "Attention
            Required" page (ray a3b3449a0a596122).
          - Token expiry is out: the export uses the service-role key.
          - Attempt 2 restarted every table from scratch. Retries run about every 30 minutes until attempt 6, around
            01:45–02:00Z, and then the day is abandoned.
          - Storage doesn't grow (the same files are rewritten). No `_manifest.json` is written, so nothing reaches
            Dropbox. And NO finding was raised: a silent internal failure.
        - **Fix: PR #686** (`it-engineer/export-never-fails-on-its-own-token`, worktree `qd-export-403`).
          - It escapes WAF-trigger characters as JSON `\u` escapes, so pages round-trip identically.
          - Failures are classed internal (tried once) or provider (retried 3 times).
          - A new `fn_table_export_due` resumes a failed day from its refused page.
          - A loud `fn_it_duty_settle('table_export')` finding is raised on failure.
          - 5 tests. The SQL and the `backup` function must go live together.
          - In URGENT review, so it's live before attempt 6. Otherwise: a manual re-run, or the 16 Sep run.
          - **Reviewed CLEAN (~00:05Z).**
            - The `wafSafeJson` restore round-trip is byte-identical, and the restore drill is unaffected.
            - A resume never wipes earlier pages, and `fn_table_export_finish` re-verifies page counts.
            - Internal failures are tried once, provider failures 3 times, and findings go via `fn_it_duty_settle`
              only. Security is clean.
            - The LOW note: dead code at `backup/index.ts:228-232`.
            - The reviewer says resume widens the time a copy spans. It's still no worse in kind than a paged
              export.
          - **GO sent: SQL FIRST, then I merge**, so main's deploy ships `backup` about 5 minutes later.
          - Measured timeline (clock read, not guessed):
            - attempt 2 failed 23:45:51Z;
            - **attempt 3 started ~00:01Z** (at 00:05:15Z it was on lead_subcategory page 5) and will fail at
              kb_chunks page 103 around 00:15Z;
            - retries run about every 30 minutes, so attempt 4 comes around 00:30Z, and attempt 6 fails around
              01:45Z;
            - the merge chain b1zdiz3z9 started 00:05:37Z, with #686's head at 5de3c95. It stopped "NOT merged":
              the first head move (96a9da8, 00:06:39Z) was the helper's main-merge push, which came BEFORE the SQL
              apply, so the database check correctly failed. Lesson: a merge chain must wait for ALL checks green,
              not for the first head move;
            - **the SQL is LIVE**, measured 00:07:58Z: production `fn_table_export_due` carries the resume logic. The
              mirror head is bd8ecd5 and its checks were running. A new chain, b1hzum4nk, merges once everything
              is green, then confirms the `backup` deploy;
            - **The #686 delta review came back CLEAN to ship (~00:12Z).** `MAX_HOPS` 900 is a sane bound (about 7.5–9
              h). The only commits are that constant and the mirror; the rest came from main via #679. The MEDIUM: lines
              228-232 don't call `settle()` on the version-skew path. That's a one-time missed finding with no data
              loss and no false success. Merge #686 now; the one-line `settle()` fix follows as its own reviewed PR,
              "a failed export day always raises a finding".
            - **#687** "it_engineer: a failed export day always raises a finding" is built at 96f9277. It calls
              `settle()` in the leftover-failure branch through a new tested `leftoverFailure` helper, has 6 tests and
              no SQL, and is in review. After #686's deploy: if it landed before about 00:16Z, attempt 3 itself (at
              kb_chunks page 52 at 00:13Z, still at the head of its queue) may pass page 103 on the new code;
              otherwise it'll be attempt 4 at ~00:30–00:45Z.
            - **backup v9 DEPLOYED at 00:13:23Z**, measured. That was mid-way through attempt 3's kb_chunks (page 52 at
              00:13:18Z, page 69 at 00:15:19Z), and each hop is a fresh invocation, so page 103 gets uploaded
              escaped. Main at 27f853e: "repo and database agree", checks and deploy all succeeded; the smoke was
              running.
            - **#687 reviewed CLEAN (~00:16Z).** LOW: the tests assert `leftoverFailure`'s output, not the `settle`
              call inside the handler; that's a pre-existing architecture limit. A background chain merges #687
              (only if its head is the reviewed 96f9277) AFTER no smoke or deploy is running, so CI smokes don't
              overlap.
            - **The chain STALLED (~00:15Z), measured at 00:17:05Z.** It showed `running`, attempts 3, kb_chunks
              page 69 (unchanged since 00:15:19Z), heartbeat 163 s old, and page_0103 not in storage.
              - UNCONFIRMED cause: the `backup` v9 deploy at 00:13:23Z killed the in-flight hop, so no next hop was
                chained.
              - **REAL CAUSE (measured ~00:22Z): #686's `wafSafeJson` blows the edge CPU cap.** The deploy was
                harmless. The v9 hop at 00:14:22 returned 200 (page 69, hop 24); the next v9 hop ended 546, `CPU Time
                exceeded`, at 00:14:39.
                - `JSON.stringify` takes 2–10 ms per page; `wafSafeJson` takes 99–331 ms per page, about 1–3 s of CPU a
                  hop. The 30 s slice deadline only counts wall-clock time.
                - A 546 kills the worker, so the day stays `running` forever: no failure, no attempt used, and NO
                  finding. It's a silent failure caused by our own fix.
                - A stale running day resumes from page 69 without using an attempt (the #686 SQL, line 46). It's
                  eligible from 00:24:22, next ping about 00:30Z, but every v9 hop will hit the CPU cap again.
                - **PR 1 GO (~00:23Z):** "an export hop stays inside its CPU budget". It swaps in a native-regex
                  escape (byte-identical, 60–126 ms per page) and adds a per-hop budget of about 12 MB, so a full copy
                  is about 650–700 hops, under `MAX_HOPS` 900.
                - **PR 2 next:** "a stalled export day is never silent", a loud finding when `fn_table_export_due`
                  resumes a stale running day.
                - Lesson to write: a fix can create a NEW silent failure. Edge functions have a per-request CPU cap
                  that a wall-clock deadline doesn't bound.
                - The lesson is WRITTEN: `an-edge-function-has-a-cpu-cap-a-deadline-does-not-bound`.
                - **PR #689 built (~00:27Z), head 12cd16a:** a native-regex `wafSafeJson`, byte-identical to v1 at
                  54–106 ms per page (v9 took 123–309 ms); a 12 MB per-hop budget, so about 3 kb_chunks pages a hop;
                  `MAX_HOPS` 900 → **2000**, since a full copy is about 985 hops. 10/10 tests, `deno check` 0. It's
                  edge-only, with no SQL. In independent review.
                - **#690 reviewed CLEAN (~00:40Z).**
                  - Severity is high at once (`agent_facing`, affected > 0).
                  - It dedupes on a fixed key: repeat stalls bump `seen_count`.
                  - It closes on a successful day via `settle(stamp, null)`, which closes the `duty:table_export:%`
                    prefix.
                  - The `exception` wraps only the upsert; resume semantics are unchanged (no attempt used). The
                    `for update` lock is kept, and so are definer, search_path and revoke.
                  - **Order (deadlock rule):** merge #689 FIRST, since it has no SQL. Then apply #690 signed, then
                    merge #690. #690 is SQL-only, so no deploy or smoke.
                  - Verified by me, read-only (~00:41Z): the live `fn_table_export_due` body md5 prefix is
                    `0562a4fe`, as the author reported. `chain_stalled` isn't in the body, and there are 0
                    `chain_stalled` finding rows. So the author's BEGIN…ROLLBACK left production untouched, and #690
                    is NOT live.
                - **PR #690 built, head 1351dc1:** a `chain_stalled` finding at severity high whenever
                  `fn_table_export_due` resumes a stale running day, written directly via
                  `fn_it_engineer_finding_upsert` (not settle, so an open `day_failed` isn't closed). The author proved
                  it with BEGIN…ROLLBACK; the live hash `0562a4fe…` is unchanged. It's SQL and NOT applied. In
                  independent review.
                - At 00:27Z the run was `running`, attempt 3, kb_chunks page 69 (74 objects), hop 24, no heartbeat for
                  13 minutes. The ~00:30Z ping resumes it, and v9 will probably hit the CPU cap again until #689
                  deploys.
                - **Merge order:** #688 (its chain is waiting for quiet), then #689 (backup), then #690 (apply, then
                  merge), then #687 (after the copy is done, merged with main, because it also touches
                  `backup/index.ts`).
                - **The #689 review is NOT clean (~00:32Z).** Byte identity, resume, WAF-safety and linearity all
                  passed.
                  - MEDIUM: no no-progress guard. `st.hop++` runs even when nothing is stored, so a stuck chain with
                    `MAX_HOPS` 2000 burns about 16.7 h (was about 7.5 h) before failing: a silent window.
                  - LOW: time the dense-escape corpus too.
                  - LOW, pre-existing: `PAGE` bounds rows, not bytes; add a code note.
                  - The helper is adding a guard: after N=3 consecutive zero-progress hops, fail the day with an
                    internal `settle()`, persisted in state, with a test. Then a delta re-review.
                  - **Fixed at head 0c4c9b1 (~00:37Z).**
                    - The hop loop is refactored into a testable `runHop` in `table_export_core.ts`. An empty,
                      not-done read ends the hop.
                    - After 3 idle hops, it returns an internal failure through `index.ts`'s `if (failure)` block,
                      so `settle` then `finish`. `st.idle` is persisted and reset on progress.
                    - Tests: (f) tonight's page-69 shape fails after exactly 3 hops with no uploads; (f2) the
                      counter persists and resets.
                    - Dense corpus: 161–170 ms against a 2 s threshold. There's a `PAGE` rows-not-bytes comment.
                    - 12/12 tests, `deno check` 0.
                    - Its delta re-review was sent; the focus is on `runHop` preserving the old loop exactly.
                  - Measured live: the 00:30 resume's v9 hop died at 00:30:52 with 546 `CPU Time exceeded`. It's
                    still at page 69, hop 24, with no finding. That repeats each ping until #689 deploys.
                  - **#689 delta re-review CLEAN (~00:43Z), head 0c4c9b1.**
                    - `runHop` preserves the old loop exactly.
                    - The guard can't false-trip today, because `fn_table_export_page`'s `done := v_n < v_lim`
                      means 0 rows always implies done.
                    - An empty table stores `page_0000`, so it counts as progress.
                    - Optional carry-over: a comment at `IDLE_HOPS` pointing to that `done` invariant.
                  - A background merge chain for #689 at 0c4c9b1 runs after #688's smoke finishes and then confirms
                    the `backup` deploy. **Then** apply #690 signed and merge it. Then #687, after the copy is done.
                  - **#689's post-deploy smoke PASSED** (run 34915003050, 00:53:06Z), so main is fully green on the
                    CPU fix.
                  - **#689 MERGED as cee2cc4 at 00:48:32Z.** `backup` **v11** is live from 00:50:02Z. Checks, "repo and
                    database agree" and deploy all succeeded; the smoke was running. The next resume (about 01:00Z)
                    runs v11 from kb_chunks page 69. **GO sent for #690** (~00:54Z).
                  - **PROVEN LIVE (01:03–01:05Z).**
                    - The v11 resume at about 01:00Z stored **page_0103** (the WAF escape works). At 01:05:31Z it was
                      at hop 42, kb_chunks page 138, 139 kb objects, heartbeat 7 s old, still attempt 3.
                    - **#690's `duty:table_export:chain_stalled` FIRED** at 01:00:27Z (open, seen 1). It closes when
                      the day is done.
                    - About 985 hops in total, at about 4 hops a minute, so it should finish about 05:00Z.
                    - A long watcher (every 10 min) confirms `done`, `_manifest.json`, the `chain_stalled`,
                      `export_stale` and `restore` findings closing, and the Dropbox `EXPORT:2026-09-15` rows going
                      done.
                    - Then merge #687, after bringing main in and a re-review.
                  - **#690 MERGED as 89e8ffe at 00:55:54Z.** It's SQL-only, so no deploy or smoke. All of tonight's
                    export fixes are now merged and live: #686 (WAF escape and resume), #689 (CPU budget and
                    no-progress guard) and #690 (stall finding). Only #687 (the leftover-path `settle`) remains,
                    held until the copy is `done`. It will need main merged in (it conflicts with #689 in
                    `backup/index.ts`) and a re-review of the merged result.
                  - **#690 APPLIED (00:53:58Z), head 0f8be86.**
                    - Change log: one row, `qd-apply 5b77c11`. The live body md5 is `18a129cd…`, identical to the
                      proven rollback body, and it carries `chain_stalled`.
                    - `canonical --all` = 0, the mirror is committed, and a background merge runs once it's green.
                    - The 00:45 resume (still v9) moved page 69 → 76 before stalling. The ~01:00Z resume runs v11
                      from page 76, and will raise `duty:table_export:chain_stalled` for tonight's stall. That's the
                      first live proof of #690; the finding closes on a finished day.
                  - **#690 PREPARED (~00:46Z), head e6d6a67.** main (b7d57c6) is merged in cleanly, and the SQL and
                    MANIFEST are byte-identical to the proven 1351dc1. The paren check passes 5/5, and `canonical
                    --all` shows only its own undeployed `fn_table_export_due`. The apply is scripted in
                    `scratchpad/export-403/apply_690.sh`: merge main, apply, canonical = 0, export last, push,
                    then read back `chain_stalled` in the live body. It waits for GO after #689 merges.
                - At 00:29:07Z the export was still stalled (heartbeat 886 s old, hop 24, page 69). The only run in
                  progress was the 27f853e smoke (since 00:16:05Z), which is holding #688's merge chain.
                - **The ~00:30Z resume HAPPENED and DIED, confirming the CPU diagnosis on the live system.** The
                  heartbeat was touched at 00:30:29Z, when `fn_table_export_due` claimed the day. At 00:35:12Z it
                  was still hop 24, kb_chunks page 69, with 74 kb objects: the resumed v9 hop stored nothing before
                  the CPU kill. It'll repeat about every 15 minutes (next ~00:45Z) without using attempts or losing
                  anything, until #689 deploys.
              - Expected recovery: `fn_table_export_due` picks up a stale day after about 10 minutes. The #686 helper
                was asked, read-only, whether it resumes from page 69 or restarts, whether it uses attempt 4, and
                when.
              - **#687's merge is PAUSED** (merge chain bv3ltkq6g stopped): it redeploys `backup/index.ts`, and a
                mid-run deploy may stall the chain again. Merge #687 only AFTER tonight's 2026-09-15 copy is `done`.
              - If the cause is confirmed, write a lesson memory: deploy `backup` only between export runs.
              - #688 (login_otp only) doesn't touch `backup`, so it's safe to merge whenever it's clean.
            - **#686 MERGED as 27f853e at 00:11:43Z 15 Sep.** Main's deploy ships the new `backup` function; a watcher
              confirms the version and main's checks. Attempt 4 (~00:30–00:45Z) should run the fixed code, and export
              watcher buhv2aj6k will show whether it passes page 103.
            - **merge chain b1hzum4nk was STOPPED on purpose (~00:10Z).** The helper revealed an UNREVIEWED change in
              commit 96a9da8: `MAX_HOPS` 300 → 900 in `backup/index.ts`. A full copy is about 287 hops, and the hop
              count now carries across a resume. It also corrected the LOW note: lines 228-232 can fail a day once
              WITHOUT a finding if the deploy lands mid-run. That delta went to the #686 reviewer; merge only after
              it comes back CLEAN;
            - estimate: attempt 4 runs about 00:30–00:45Z, and a full copy takes about 3 h (287 hops × ~36 s), so it
              finishes about 03:30–04:00Z. 3 attempts remain. A reset script is drafted but NOT to be run without me
              (`scratchpad/export-403/reset_attempts_2026_09_15.sql`: refuses unless `failed` with ≥6 attempts, one
              row, logged).
            - if `backup` deploys by about 00:25Z, attempt 4 runs the fixed code. The old code leaves the queue
              empty on failure, so the new SQL restarts that day in full, gets past page 103 (the pages are
              escaped), and should finish.
        - **A separate bug** was found in the logs (23:16–23:38Z): `fn_it_engineer_finding_upsert`,
          `fn_registered_locale` and `agent_runs` inserts were refused 403, called with a signed-in USER's token
          right after `login_otp`. So a path can't record findings or runs, silently. A read-only investigation is
          running.
        - **ROOT CAUSE (~00:00Z):**
          - `login_otp/index.ts:7` has a module-level service-role `admin` client, and `mintSession` (line 73) runs
            `admin.auth.verifyOtp` on it. supabase-js then stores the user session there, so later calls carry
            the USER's token.
          - It was latent since 21 Jul (f5fa059). It became visible with 566c973 (14 Sep 16:54Z, customer_support),
            which added `registeredLocale(admin, …)` after `mintSession`.
          - 72 × 403 each on `fn_registered_locale`, `agent_runs` and `fn_it_engineer_finding_upsert`, 17:15:31Z to
            23:48:59Z. The registered language is never returned, and the failure reports are lost silently.
          - No sign-in failed. One internal account in the window, no customer. The grants are correct and must
            stay.
          - **The fix is dispatched:** a per-call client for `verifyOtp`, a grep for the same pattern elsewhere, a
            regression test, and an explicit assessment of cross-request bleed (a module-level client is shared
            across concurrent requests in a warm isolate).
          - **PR #688 built (~00:15Z):** "customer_support: sign-in never borrows the system's database client"
            (e9a4623 plus a graphify commit), now in independent review.
            - `login_otp` was the only caller of the pattern.
            - The bleed WAS possible across requests in a warm isolate, but `authenticated` has no grants on the
              flow's tables or routines. So no cross-user read was possible; the worst case was a silent failure for
              the second user. It didn't happen on 14 Sep: user-role calls only came right after a session was
              minted in the same request.
            - Measured 73 (not 72) of each 403, 16:55Z to 00:06Z, across 42 user IDs. 40 of those no longer exist
              in `auth.users` (likely E2E fixtures, not confirmed).
            - The tests fail on the old code and pass on the fix. After deploy, check that `edge_logs`
              `fn_registered_locale` shows 200 with role `service_role`, and 0 with role `authenticated`.
            - **Reviewed CLEAN (~00:20Z).** The reviewer reproduced both tests failing on main's code. The only
              verify call is the per-call `once` client; `mobile_otp` and `kyc` use the stateless
              `admin.auth.getUser(jwt)`; the harness hook is test-only.
            - **The grant claim was VERIFIED by me, read-only on production:** `authenticated` has NO grant on
              `agent_runs`, `app_secrets`, `customers`, `email_verifications`, `leads` or `phone_verifications`, and
              can't execute `auth_uid_by_email`, `fn_it_engineer_finding_upsert`, `fn_it_threshold`,
              `fn_otp_prefix_blocked`, `fn_registered_locale` or `rl_check`. So a cross-user read was impossible; the
              worst case was a silent failure.
            - A background merge chain, bp09e2hxe, merges #688 at its reviewed head once no smoke or deploy is
              running; it doesn't touch `backup`.
            - **#688 MERGED as b7d57c6 at 00:30:08Z.** `login_otp` v66 was deployed at 00:32:37Z; "repo and
              database agree", checks and deploy all passed. **Its post-deploy smoke PASSED** (run 34913744113,
              00:34:29Z), so the sign-in fix is proven live.
              #689 must wait for that smoke to finish before it deploys. **Morning carry-over:** after the first real sign-in, confirm
              `fn_registered_locale` 200 as `service_role` with 0 `authenticated` 403s (query in
              `scratchpad/login-client/logs.mjs`). Attempt 2 moved about 10 kb_chunks pages a minute (page 52 at 23:40:57Z, page 62 at 23:41:47Z),
          so page 103 is due around 23:46Z. The helper is reading the actual 403 body from the logs. Whatever it is,
          if it's our own code it's an internal cause, which breaks founder_instruction 208.
        - An it_engineer helper is diagnosing READ-ONLY and preparing the fix PR "a table export never fails on its
          own token", without touching tonight's run. A background watcher samples the export every 2 minutes.
        - `restore_table:export_stale` and `:restore` stay open until a full copy completes.
      - **#682 MERGED as 0318e36 (~23:05Z).** The ledger fix and the test-money guard are on main. The E2E teardown
        proof is still running (the gate is open because the guard is deployed).
        - **Main is green at 0318e36:** "repo and database agree" (run 34906955243) and "checks" (run 34906955244)
          both passed. No edge function changed, so there was no deploy or smoke run for it; that's expected.
      - **#683 APPLIED (~23:10Z), head 97e0e92.** Signed from e231eea (routine_change_log 7892); the trigger now
        drops rows that would have been relabelled `zz_demo`.
        - `zz_demo` pending and waiting_source went from 639 + 28 to 0; 697 are abandoned with one identical error.
          Of the 331 non-demo rows, 0 changed status.
        - `canonical --all` = 0, and the mirror is pushed. **MERGED as cec2d4c (~23:18Z).** Main is green there:
          "repo and database agree" (run 34907336916) and "checks" (run 34907336924) both passed. No function
          changed, so there was no deploy or smoke run for it.
      - **#685 APPLIED and DEPLOYED (~23:12Z), head a7bca5c.** `dropbox_backup` v50 and `resilience_ping` v80;
        `canonical --all` = 0, and the mirror is identical.
        - First real reading at 23:10:40Z: Dropbox is **11.6% full** (pro plan). Login, write, read and delete all
          OK, and no finding.
        - A background merge runs once it's green. Then #679 merges main once.
        - Note: the regenerated full mirror also re-lists `fn_ad_spend_daily_ceiling` and `fn_price_confidence`,
          which #685 didn't touch. It's a full production export, and the export check says it's identical.
      - **#685 MERGED as 2caff92 (~23:20Z). All five of tonight's fixes (#684, #681, #682, #683, #685) are merged
        and live.** #679 merges main once, now.
      - **#682's E2E teardown proof PASSED all four points** (run tag b4d25f10, journeys a–e, 23:02–23:11Z):
        1. Journey e ran the whole refund chain, and the teardown removed 1 `supplier_dues` row.
        2. `leftovers()` = 0.
        3. Nothing was written to `gl_journal` above #821, and no orphan finding opened.
        4. No fixture number reached a provider: 14 email, 2 SMS and 16 WhatsApp all suppressed, with no provider
           id.

        The report is at `scratchpad/test-money/e2e/2026-09-14T23-02-31/report.md`.
      - **Journey a failed on portal overview load time**: 11.5 s (en) and 4.0 s (ar) against a 2.5 s limit, while
        two E2E runs were loading production at once. Carry-over: re-measure the portal overview alone, since #670's
        parallel reads should have fixed it.
      - `qd_run:eac8b5e2`, opened 23:02:31Z, is the CI "IT engineer post-deploy smoke" for 7ea8791 (run 34906881699),
        not an abandoned run. **That smoke PASSED.** Main is fully green at 7ea8791: smoke, "repo and database
        agree" (34906522132), checks (34906522023) and the deploy (34906522034). The guard's six functions are
        confirmed live. **Lesson:** post-deploy smokes start by themselves after every deploy to main and run
        E2E against production, so a manual E2E must first check that no smoke is running. #679's journey g waits
        for that.
      - #685's original go (~23:18Z), the last in tonight's apply queue:
        1. merge main;
        2. add the reviewer's comment;
        3. rerun the threshold and Deno tests;
        4. apply signed;
        5. deploy `dropbox_backup` and `resilience_ping`, but not while an upload batch from tonight's export is in
           flight;
        6. run `canonical --all` = 0, then the mirror;
        7. make one `resilience_ping` call showing the Dropbox reading.
      - **#679 at head 7d3936c (~23:15Z).**
        - main is merged in (the only conflicts were graph files), and it now relies only on #681's
          `isDemoPhone()`; its own fixture door is deleted.
        - Journey g's "No" branch proves the refusal, then a harness-only database mark continues the screens.
        - Deno 12, `kyc/fixture_number` 5 and the portal test 11 pass; `deno check` and the typecheck exit 0.
        - Its independent review was launched ~23:15Z. **Journey g is held until #682's E2E finishes**, so there's
          one E2E at a time and `leftovers()` isn't polluted. Preview:
          quotesdone-next-u956xft39-quotes-done.vercel.app.
        - Its red "database is running what this repository says" (~23:20Z) is ONLY `trg_doc_backups_admit`: #683's
          trigger, merged into main as cec2d4c after #679 last merged main. It isn't #679's drift.
        - **#679 merges origin/main ONCE, after #685 merges**; merging earlier would only move the red to #685's
          live routines. Then journey g runs, once #682's E2E finishes.
        - **#679 was reviewed CLEAN at 7d3936c (~23:25Z).**
          - Only kyc's four gated actions write `whatsapp_*`, and `supplier_api`'s `PROFILE_COLS` excludes them.
          - Completion is refused server-side when no answer was given (`kyc accept_terms` and the supplier
            `reg_whatsapp` gate).
          - The Twilio VerificationCheck is bound to the same `To`.
          - Rate limit: 5 an hour, shared with SMS.
          - SMS fallback goes only to the same number and only on 68008/63118/63008, never on 60410.
          - "I do not use WhatsApp" nulls the number.
          - EN/AR are at parity, and no PII is logged.

          No re-review is needed after the main-only merge unless code changes. Merge once the checks are green and
          journey g passes.
        - **Main merged in at head 8898546 (~23:15Z; measured clock 23:19:41Z at the next read), with no conflicts.**
          The one E2E still running then was #685's post-deploy smoke (run 34907965715, since 23:14:57Z), which holds
          journey g.
        - **Main is fully GREEN at 2caff92:** the post-deploy smoke (34907965715), "repo and database agree", the
          deploy and checks all passed. No smoke or deploy is running, and `qd_run:eac8b5e2`'s fixtures are cleared
          (0 leads, 0 customers). **Journey g was released** to run alone against the 8898546 preview. Then merge
          #679 and close founder_instruction 391, 322 and 328.
        - **Journey g PASSED, 18/18, 0 leftovers (~23:37Z)**, running alone, with kyc v60 carrying the guard. The
          report is at `scratchpad/wa-signup/e2e/2026-09-14T23-37-13/report.md`.
          - "Yes" (EN) stores the mobile as the confirmed WhatsApp number with no code.
          - Every "No" (customer EN, customer AR in RTL, supplier) is refused with `captured: true`, 0
            verification rows (no Twilio request) and nothing stored, and the screens continue after the harness
            database mark.
        - **A new harness-only change at head 8d5da34:** `scripts/e2e/browser.mjs` forwards a preview's same-origin
          Supabase calls to the real project. That's needed because previews have no Supabase target by design
          (the `supaEnv` guard), which also means the earlier "17/17 preview" run really only proved the local kyc.
          The delta review came back **CLEAN (~23:45Z)**.
          - The route interception is Playwright-only and anchored to the preview origin's `/functions/v1/**`.
          - It forwards only the request's own auth and content-type headers to the fixed project host. No
            service-role key is involved, and `supaEnv.ts` is untouched.

          A background merge runs once green, then waits for the kyc/supplier_api deploy. Then close
          founder_instruction 391, 322 and 328 with the merge sha and kyc's post-merge version.
        - **#679 MERGED as d1c7364 at 23:43:05Z.** Deployed kyc v61 (23:45:35Z) and supplier_api v57 (23:46:38Z);
          "repo and database agree" and checks passed. **founder_instruction 391, 322 and 328 were closed** with that
          evidence. **Its post-deploy smoke PASSED** (run 34910421840, 23:47:25Z), so the WhatsApp sign-up step is
          proven live.
        - **All of tonight's PRs are merged:** #684, #681, #682, #683, #685 and #679. The only new open item is the
          export 403 fix. Note: my own estimates of the time ran ahead all night, so always read the clock
          (`date -u`) before stating a time. "The database is running what this
          repository says" is GREEN (run 34908177480), and every touched test passes again on the merged tree. The
          only step left is journey g, held until no post-deploy smoke or deploy is running.
      - Carry-over: `fn_gl_post` doesn't check the journal's status. The new trigger refuses re-posting a void
        journal, but `fn_gl_post` should check status itself; do it in a later small PR.
    - **Documented limit, not closed:** a number written with separators (`1234-5678-9012-3456`, `12.34.56.78`)
      splits into chunks under 8 digits and is not masked. Mashreq refs are unseparated, and grouped IBANs are caught
      by the IBAN pass, so this is acceptable for memos. Revisit if card-style numbers ever reach a memo.
  - **The 2 `run.mjs` fixture tests:**
    - "every duty's loop closes" fails on its global never-posted assertion versus the real #692–#695. That's
      pre-existing, not #684, and #682's test fix covers it.
    - "the warning, the hold, the founder-only lift" PASSES on the reviewer's runs.
  - f2382ff (reconcile evidence masking) is clean apart from the shared mask defect.
  - #682 (test money) must rebuild on #684's versions of `fn_accountant_book_bank_*` and `fn_gl_journal_immutable`,
    and must apply only after #684 merges.
- **Other open PRs:**
  - #681: the test-number guard. In review; merge FIRST, because post-deploy smokes can still text fixture numbers.
    The 4 texts to …042 were UNDELIVERED (Twilio 30005).
  - #683: rehearsals never queue backups. Reviewed CLEAN (ce156db), NOT applied. Waiting for its apply slot.
  - **Apply queue, strictly one at a time:**
    1. #684: already live; review, then merge. It must go first: while it's live and unmerged, every other PR,
       including #681 (which has no SQL), fails "the database is running what this repository says".
    2. #681: reviewed CLEAN at 22:45Z. Update its branch after #684 merges, then merge. Then #679 switches to its
       guard and gets reviewed.
    3. #682: merge main in, re-rehearse, apply, merge. Report the reversal journal id.
    4. #683: merge main in, re-dry-run, apply, merge.
    5. The Dropbox health-check PR.
- Fixture cleanup is done; founder_instruction 407 and 408 are closed with counts. 1 real customer and 22,264 real
  leads were unchanged.
- **A rehearsal window was left open by a crashed E2E run.** `qd_run:19e25f67`, opened 19:21Z 14 Sep, was never
  closed. An open window silences the failed-run watcher for up to 6 hours, so it self-expires about 01:21Z
  15 Sep. Fix: the E2E harness must close its window in a finally/teardown even when a run crashes, and a duty
  should flag a window older than its run. Not touched tonight.
- Pin the Supabase CLI version in `.github/workflows/deploy-functions.yml`. `supabase/setup-cli` with
  `version: latest` failed #672's "deploy changed functions" on 14 Sep with "Failed to resolve latest Supabase CLI
  release: rate limit exceeded" (a GitHub API limit); a rerun was requested.
- Merge queue at ~22:45 UTC, deadlocked. #672 and #676 were both applied before merge, so each fails "the database
  is running what this repository says" on the other's live routines:
  - #676 fails on #672's 13 `fn_backup_prune_*` routines, plus `fn_backup_source_registry` and
    `fn_it_backup_expected`;
  - #672 fails on `fn_accountant_statement_reader_defects`.

  The fix: #676's helper merges `origin/it-engineer/backup-retention` (b4858cb) into #676. Merging #676 then lands
  #672 too; after that, update and merge #680 and #568. Lesson: two PRs applied before merge deadlock each other's
  database check. The same happened with #661/#673 on 14 Sep. Apply one PR, merge it, then apply the next.

**Trap:** C:/Users/Opera/quotesdone is detached at 2b46435, with 8 superseded unpushed commits and one superseded
uncommitted test edit. Never build on it; always use a new worktree from origin/main.
