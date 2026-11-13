## REPLAY GUARD AND ACCEPTANCE 1: review of 4685d455f

**VERDICT: FIX.** The product fixes hold. The guard has three problems:
- It blocks the exact 13 Nov file shape, but many other lock-taking shapes still pass with a 120 s hold.
- The hot-table list is out of date already.
- The pending SQL's probe cannot reach PROBE OK on the production schema.

Nothing was rehearsed on production. Labels: [L] = run on a local Postgres 16 built from the mirror (since deleted), [R] = read in the code, [S] = a light SELECT on production.

### FIX list, most harmful first
1. **The guard misses lock-takers (`scripts/lib/replay_guard.mjs:51-91`).** `maskSql` blanks out quoted names and `$$` bodies, so all of these pass with a 120 s hold [L]:
   - quoted names: `alter table "public"."quotes"`, `drop policy "a b" on quotes`;
   - DDL inside a `DO` block, an `EXECUTE`, or a function the file then calls;
   - `drop index` (takes ACCESS EXCLUSIVE on the table);
   - a new table `references quotes` (takes SHARE ROW EXCLUSIVE on quotes);
   - `create or replace view`;
   - the second table in `truncate a, quotes` or `lock a, quotes`;
   - `storage.objects` and `auth.users`;
   - `create table if not exists <an existing hot table>`, which exempts that table. The committed file `the_it_engineer_hands_the_founder_a_session_he_can_start_from.sql` passes with CREATE INDEX and ENABLE RLS on `it_engineer_finding`;
   - 88 committed files that pass do UPDATE/DELETE on hot tables, so their row locks can be held for up to 120 s.

   Wait of a live reader with an 8 s statement_timeout [L]:

   | Configuration | Live reader's wait | Outcome |
   |---|---|---|
   | Old: no lock_timeout, behind a 15 s read | 8.04 s | cancelled |
   | Guard: lock_timeout 1 s, same 15 s read | 0.83 s | survived |
   | acceptStall, replay cut at 5 s | 4.65 s | survived |
   | `quote_items` ALTER + 12 s probe (table not in the list) | 8.03 s | cancelled |
   | `DO`-block ALTER on quotes + 12 s probe | 8.04 s | cancelled |

   **Smallest fix:** set `transaction_timeout` to 5 s on every production replay, not 120 s. That keeps every miss, row locks included, under 8 s. Keep the regex only as an early refusal.
2. **The hot-table list is stale (`replay_guard.mjs:38-43`)** [S].
   - 3 of its 24 names are not tables: `quote_lines`, `login_otp`, `conversation_turn`.
   - Busy tables missing from it:
     - `quote_items` (427 K reads; the quotation path);
     - `it_refusal_policy` (11.6 M);
     - `sales_knowledge` (9.3 M);
     - `model_registry` (7.0 M);
     - `it_hold_signature` (6.9 M);
     - `decision_policy` (2.0 M);
     - `seat_duty`, `wa_messages`, `storage.objects`.
   - Recommendation: drop the list. Refuse any lock stronger than ROW EXCLUSIVE on any existing relation, read from pg_class once before sending.
3. **The pending probe never passes on production (`…_probe.sql`).**
   - Lines 8-12 insert into `customers.is_demo`, which is a generated column on production [S: `attgenerated='s'`].
   - Lines 22-26 build `'PROBE FAILED…' || r1`; text concatenated with jsonb resolves to jsonb, so every run fails with "invalid input syntax for type json".
   - With both fixed, his own `rehearse_sql.mjs` with `QD_LOCAL_DB_URL` answers PROBE OK [L]. His committed probe fails the same way.
   - Five planned mutants plus two extra variants [L]:
     - the probe catches re-signing twice within 5 minutes, and re-signing an already-signed customer;
     - it misses demo counted as real, the hourly finding re-keyed every hour, a customer with no acceptance being re-signed, escalation never firing, and the escalation row being duplicated.
   - Fix: add fixtures for 3 prior attempts, for a null acceptance, and for a demo-only gap.
   - The file itself is clean: grants per signature, `search_path` pinned, no new table, and pg_cron does not overlap runs. A real apply locks only `cron.job`, `cron_registry` and `writer_seat`, at ROW EXCLUSIVE [L].
4. **`apply_sql.mjs` does not go through the guard (`apply_sql.mjs:265-283`).**
   - It sends the file as one request, so it runs as one implicit transaction and a lock timeout rolls all of it back [R]. Retries are 6 tries, a fixed 10 s apart.
   - It sets no transaction timeout. A file's own `set lock_timeout` overrides the 2 s: 3 s in two of this week's files, 15 s in one committed file. A backfill holds its locks with no limit.
   - Fix: cap the file's lock_timeout at 2 s in apply too, and add a 60 s `transaction_timeout` when a statement locks a hot table.
5. **`safe_replay.mjs:152` keeps `db.mjs`'s retry on.** If the API answers the killed session with a 5xx, the replay is re-sent up to 7 times (inferred; not tested on production). Fix: pass `retry:false` on the production path.
6. **The default is still production.**
   - `npm test`, run with a token, rehearses 8 `rehearseChain` checks and the other `replaySql` callers on production (they now go through the guard).
   - About 40 scripts POST straight to the query endpoint and bypass the guard.
   - Fix: `replaySql` refuses production unless `target:'production'` or `QD_REPLAY_ON_PRODUCTION=1` is given, and the local database becomes a script.
   - The advisory lock is fine: it is released when the transaction ends or the holder dies, and the file's own lock waits are capped by the 1 s `lock_timeout`.
7. **`supplier_api/context.ts:22-25`: `cause` can carry personal data into agent_runs.** 233 committed `raise exception` messages put an email, phone or name into the text. Fix: mask emails and phone numbers before `annotate`.
8. **`kyc/index.ts:30-41`: the finding call can push the customer past his page's timeout.** It is awaited after up to about 27 s of retries. Behind the same lock that is past the page's 30 s abort, so he sees a timeout instead of the sentence. Fix: run it with `waitUntil`.
9. **`tightenLimits` misses `set lock_timeout to default`, `reset lock_timeout`, `reset all` and `set_config`.** No committed file uses them, so this is low priority.
10. **`spec_fill` (`workflow.ts:463-471, 552-557`) can deliver twice.** Two tabs or a double submit both deliver. If the second hold update fails after delivery, the next press delivers again. Fix: compare-and-set the hold before delivering (not a blocker).

### Product: verified
- **The retries are idempotent:** the same values within one request, and a compare-and-set in compliance_archive.
- **Customer page (ProfileGate), on the 503:** stays on the step, re-enables the button, and shows the sentence in English and Arabic ([L] scratch test, removed).
- **Supplier ProfileForm, on the 503:** shows `terms_cert_failed` and stops.
- **Acceptance is enforced on the server**, so it is not a blocker:
  - `create_inquiry` requires `tos_accepted_at` (`customer_api/actions/inquiry_create.ts:101`);
  - a supplier's quote requires `accepted_terms_at` (`supplier_api/actions/quotes.ts:213`).
- **Gap:** `supplier_api accept_terms` (`profile.ts:78`) answers a lock blip with a generic 500. It should go through `writeRecorded` too.
- **Two tests are missing:**
  - kyc's handler with the write failing 3 times, expecting `503 terms_not_recorded` and no certificate call;
  - ProfileGate never calling `onDone` on `terms_not_recorded`.

### Suites
- **Deno, this branch:** 2536 passed, 0 failed, 1 ignored.
- **Merged locally with the three sales_engineer branches:**
  - no textual conflicts;
  - kyc, compliance_archive, supplier_api and line_specs: 399 passed, 0 failed;
  - `deno check` on the three functions passes.
- **`tsc`:** exit 0.
- **Node checks:** 7/0, 4/0 and 9/0. No test was weakened; one expected prefix regex was updated and is now stricter.

### The three open branches' files
All four main files are refused for production rehearsal, so the operator rehearses them locally and applies them with `apply_sql`:
- **accountant:** the file sets its own 3 s lock_timeout and backfills `transactions`. Its `closes_every_loop` file builds a non-concurrent index on `agent_actions`.
- **sales_engineer:** backfills `quotes`.
- **ceo:** the file sets 3 s. Its three CONCURRENTLY index files pass and are applied alone.

### Local database commands (these worked)
```
mkdir -p /tmp/pg-X && chown postgres /tmp/pg-X
su postgres -c "/usr/lib/postgresql/16/bin/initdb -D /tmp/pg-X/data -A trust -U postgres && /usr/lib/postgresql/16/bin/pg_ctl -D /tmp/pg-X/data -o '-p 55461 -k /tmp/pg-X' -l /tmp/pg-X/pg.log start"
node scripts/db/local_from_mirror.mjs --sql-only=/tmp/pg-X/schema.sql
psql -h /tmp/pg-X -p 55461 -U postgres -f /tmp/claude-0/-home-user-quotesdone/1e789c53-f6dc-5392-adad-7c77c9edb8b7/scratchpad/rg_standins.sql
sed -E '/CREATE EXTENSION IF NOT EXISTS (pg_cron|pg_net|supabase_vault|vector|pg_stat_statements|pgcrypto|"uuid-ossp"|pg_trgm|plpgsql)/d; s/\bvector\([0-9]+\)/real[]/g; s/public\.vector\b/real[]/g' /tmp/pg-X/schema.sql > /tmp/pg-X/local.sql
for p in 1 2 3 4; do psql -h /tmp/pg-X -p 55461 -U postgres -q -f /tmp/pg-X/local.sql >/tmp/pg-X/pass$p.log 2>&1; done
QD_LOCAL_DB_URL='postgresql://postgres@%2Ftmp%2Fpg-X:55461/postgres' node scripts/ci/rehearse_sql.mjs <file> <probe>
```
- The `rg_standins.sql` file holds the stand-ins for roles, auth, storage, cron, net and vault.
- After 4 passes: 808 tables, 2,175 routines, 374 policies, 403 triggers, and 110 cron jobs, all inactive.
- The probes also need seed rows:
  - dummy `cred_db_internal` and `project_ref` rows in `app_secrets`;
  - `org_role` and `org_agents` rows for each seat.
- Postgres 16 has no `transaction_timeout`.

### Release order
1. Items 1, 2, 5 and 6, before anyone rehearses again.
2. Fix the probe and rehearse it locally.
3. Merge, then deploy kyc, compliance_archive and supplier_api.
4. Apply the pending file with its MANIFEST line.
5. The three branches' files: local rehearsal, then `apply_sql`.

**After merge:** count the `terms_not_recorded:*` and `certificate_not_recorded:*` findings and the `cause` values in agent_runs daily for a week. Items 4, 7, 8 and 10 and the `supplier_api accept_terms` retry are follow-ups.

The full review was appended to `/tmp/claude-0/-home-user-quotesdone/1e789c53-f6dc-5392-adad-7c77c9edb8b7/scratchpad/show/REVIEW.md` under "REPLAY GUARD AND ACCEPTANCE 1". The local cluster and both worktrees have been removed.