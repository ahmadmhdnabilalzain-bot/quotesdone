# Releasing "a paid reveal is reconciled, booked and timed" (13 Nov 2026)

Seats: accountant (the money files), it_engineer (the hand-over files, the index, the order). Written 13 Nov 2026 on the
coordinator's instruction (third review, item 6). The apply on 13 Nov is the reason this runbook exists: rolled-back
rehearsals on production held table locks long enough for live readers to time out. **Do not rehearse on production.**
Every file below was rehearsed on a LOCAL copy of the schema (`docs/runbooks/local-database.md`). This release is applied
once, by the main session, after the merge, following [release-without-ci.md](release-without-ci.md).

## What production holds (measured 13 Nov 2026, read only)

1 transaction, 4 quotes, 4 inquiries and 215 `gl_journal` rows (the coordinator's count). A later read the same day
showed 5 quotes. `refunds` holds 1 row, `accountant_reveal_reconcile_item` 60 and `agent_actions` 41,242 (173 MB).
Every table this release alters is small except `agent_actions`. No step rewrites a table. The risk is the
**wait for a lock**, not the work done under it.

## The rules for every SQL step

1. **When.** Start each apply at a minute that is a multiple of 5, plus 10 seconds (hh:00:10, hh:05:10, hh:10:10 ...).
   Most pg_cron jobs fire on those minutes, and 10 seconds later their short statements have finished. This release's
   own sweep runs at :08, :23, :38 and :53, so do not start an apply then.
2. **Before.** Run this read and go only when it returns no row:

   ```sql
   select pid, state, now() - xact_start as open_for, wait_event_type, left(query, 120) as query
     from pg_stat_activity
    where datname = current_database() and pid <> pg_backend_pid()
      and state <> 'idle' and xact_start < now() - interval '5 seconds'
    order by xact_start;
   ```

   A transaction that has been open for more than 5 seconds will make our ALTER wait, and every reader then queues
   behind the ALTER. If a row is there, wait for the next 5-minute slot and read again.
3. **The timeout.** Every file sets `lock_timeout = '1500ms'`. A step that cannot get its lock in 1.5 seconds FAILS with
   `55P03 canceling statement due to lock timeout`. Everything in it rolls back, because one file is one transaction.
4. **Retry.** On a lock timeout, wait 30 seconds, run the read in rule 2 again, then re-run the same command. Retry
   **at most 3 times**. After the third failure, stop and hand over with the pg_stat_activity rows. Never raise the
   timeout, and never run a step without it.
5. **After each step**, run its checks below before starting the next step. In the same commit, append the file as the
   LAST line of `scripts/sql/MANIFEST.txt` and delete its `scripts/sql/pending/<name>.txt` note. A file already in
   MANIFEST (re-applied) keeps its line.

## The order

### Step 1: the main file (accountant)

```
node scripts/apply_sql.mjs scripts/sql/a_paid_reveal_is_reconciled_booked_and_timed_by_the_accountant_from_the_moment_it_is_paid.sql --apply --ddl --seat accountant
```

These are the locks it takes, each held only to the end of the file (seconds):

- `transactions`: ADD COLUMN ×6 (no default, catalogue only), a backfill UPDATE of 1 row, and trigger z20 replaced in place.
- `stripe_dispute`: ADD COLUMN ×2, and trigger z60 replaced.
- `refunds`: the reason-code CHECK added in one statement (1 row scanned), triggers z59 (new) and z60.
- `accountant_reveal_reconcile_item`: its outcome CHECK (60 rows), and an UPDATE.
- `reveal_invoices` (0 rows) and `gl_journal` (215 rows): one unique index each.
- `seat_handoff_kind`: insert. Two new tables (with RLS and a policy each) and one pg_cron job, `accountant_payment_checks`
  at 8, 23, 38 and 53 minutes past each hour.

Checks after (read only):

```sql
select count(*) filter (where livemode is null) as mode_unknown, count(*) filter (where livemode = false) as test_mode,
       count(*) filter (where paid_at is not null) as with_paid_at from public.transactions;          -- 0 / 1 / 0 today
select tgname from pg_trigger where tgname in ('z59_overcharge_return_submitted', 'z60_payment_check_closes_when_the_return_settles',
       'a10_payment_check_stays_open_until_booked', 'z20_reveal_receipt', 'z60_dispute_reopens_the_payment_check');   -- 5 rows
select jobname, schedule from cron.job where jobname = 'accountant_payment_checks';                       -- 1 row
select has_function_privilege('authenticated', 'public.fn_reveal_window(uuid)', 'execute');              -- false
select count(*) from public.gl_journal where source = 'reveal_fee';                                        -- unchanged (test mode is never booked)
```

Then read its probe (it always raises, so it changes nothing): `node scripts/qsql.mjs scripts/sql/a_paid_reveal_is_reconciled_booked_and_timed_by_the_accountant_from_the_moment_it_is_paid_probe.sql`.
It must print `PROBE OK`. Read it after step 2 as well (its `[owner]` assertions need step 2).

### Step 2: the owner file of the hand-overs (it_engineer), re-applied

```
node scripts/apply_sql.mjs scripts/sql/the_it_engineer_closes_every_loop_it_opens.sql --apply --ddl --seat it_engineer
```

Locks: `agent_actions`, where trigger z61 is replaced in place with CREATE OR REPLACE TRIGGER (one SHARE ROW EXCLUSIVE lock,
no gap between a drop and a create). Also `seat_handoff_kind` and `founder_mail_policy` (inserts). It no longer builds an
index (step 2b does). Its section-14 probe runs inside the file and cleans up.

Checks after:

```sql
select position('fn_payload_names_a_live_payment' in pg_get_functiondef('public.fn_seat_handoff(text,text,text,text,text,jsonb)'::regprocedure)) > 0;  -- true
select count(*) from pg_trigger where tgname = 'z61_handoff_only_originator_closes';                     -- 1
```

### Step 2b: the index, concurrently (it_engineer)

```
node scripts/apply_sql.mjs scripts/sql/the_it_loop_reads_handoffs_by_kind_type_and_sender_on_an_index_built_concurrently.sql --apply --ddl --seat it_engineer
```

`CREATE INDEX CONCURRENTLY IF NOT EXISTS`, sent alone (apply_sql.mjs sends such a file outside a transaction). Production
already has the index, so this is a no-op there. Check: `select indisvalid from pg_index where indexrelid = 'public.agent_actions_kind_type_from_idx'::regclass;` returns true.

### Step 3: deploy the functions

```
node scripts/deploy_functions.mjs --ref=htdblwldjkcgjvmqkbeh --production stripe_webhook stripe_checkout stripe_confirm accountant reveal_invoice messages_api supplier_api
```

The apply comes first and is safe on its own. A sale the old code writes has `livemode` NULL (unknown), which is never
booked, numbered or counted until the new accountant runtime reads Stripe. Check: `node scripts/verify_deploy_parity.mjs`
on those seven slugs. The window readers (messages_api, supplier_api) call `fn_reveal_window` as the service role, which
is the only role granted it.

### Step 4: later, the sibling (sales_engineer)

`scripts/sql/a_paid_reveal_closes_the_request_and_everyone_on_it_is_told.sql`, on its own pending note. Its probe needs
steps 1 and 2. On 13 Nov it failed locally on `quote_quality_hold.accepted_md5` NOT NULL. Fixing that is the sibling
author's job, not this release's.

### Step 5: the redaction owner file (it_engineer), re-applied

```
node scripts/apply_sql.mjs scripts/sql/every_handoff_note_states_context_decision_open_asks_and_deadline_and_its_receiver_cites_it.sql --apply --ddl --seat it_engineer
```

The file is canonical for every routine it now defines. On 13 Nov the md5 of each production body matched this file
applied on a local copy, except `fn_handoff_citation_gaps`, whose later file is canonical, so it was removed here.
Locks on `agent_actions`:

- trigger a01 is replaced in place;
- the CHECK is dropped and re-added NOT VALID (ACCESS EXCLUSIVE for an instant, no scan).

Checks after:

```sql
select public.fn_handoff_redact('{"total": 135.000000000000000000, "a@b.example.com": ["call +971 50 123 4567"]}'::jsonb);
-- {"total": 135.000000000000000000, "[email]": ["call [phone]"]}  (no 22P02, the key redacted, the number untouched)
```

Then read its probe: `scripts/sql/every_handoff_note_states_context_decision_open_asks_and_deadline_probe.sql` must print
`PROBE OK` (section g covers keys, nesting, arrays, numbers and numeric strings).

### Step 6: only on the founder's yes

- `scripts/sql/the_company_recovers_no_input_vat_so_1150_is_moved_into_cost.sql` posts 27 correcting journals and moves AED
  284.41 out of 1150. Check: the 1150 balance is 0.00 and every journal is balanced (its probe).
- `scripts/sql/the_ceo_may_let_the_accountant_return_an_overcharge_itself.sql` adds one `ceo_standing_grant` row (cap AED
  500). Check: `select public.fn_agent_may_act('accountant', 'overcharge_return', 38.77);` returns may_act true.

Both take `lock_timeout = '1500ms'` and follow the same rules.

## If something goes wrong after an apply

Every step replaces routines and adds columns. Nothing is dropped or rewritten. To undo a routine, re-apply the previous
version of its file from git (`git show <sha>:<file>`), by the same rules. The new columns and tables are harmless if
they are left in place. A sale recorded while the new code was live keeps its `paid_at` and `livemode`, and those are
Stripe's facts.
