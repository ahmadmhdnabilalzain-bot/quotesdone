# Applying the shared pool (ceo, 13 Nov 2026)

File: `scripts/sql/every_seat_reads_one_pool_and_every_hand_over_comes_back.sql`. Its probe:
`scripts/sql/every_seat_reads_one_pool_and_every_hand_over_comes_back_probe.sql`. What it builds:
`docs/architecture/the-office.md`.

**Never rehearse this on production while working.** On 13 Nov a rehearsal held one file's locks on production for the length
of its transaction, and live readers and writers hit their 8-second timeout. Work on a local copy (step 0). The ONE
production rehearsal is the release step (step 2), run by the release session.

## 0. Local copy (every change)

1. Write the schema SQL: `node scripts/db/local_from_mirror.mjs --sql-only=/tmp/pg-w3-schema.sql`. Apply the money and the
   sales branches' files first (the order in section 2): this file needs their routines (`fn_handoff_note_citation`,
   `fn_demo_shadow_record`).
2. Make a cluster OUTSIDE `/tmp/claude-0`, because the sandbox resets that directory's permissions:
   `initdb -D /tmp/pg-w3-author/data -A trust -U postgres`, then
   `pg_ctl -D /tmp/pg-w3-author/data -o "-p 55453 -k /tmp/pg-w3-author -c listen_addresses=" start`.
3. Load the stand-ins:
   - roles `anon`, `authenticated` and `service_role`;
   - schemas `auth`, `storage`, `cron`, `net` and `vault`, each with the few tables and functions the mirror names;
   - a text-backed `vector` type, because pgvector, pg_cron and pg_net are not installed locally.
4. Replay the schema in three passes (`psql -f`; later passes only report "already exists").
5. Load the reference rows: `org_role`, `org_reporting_edge`, `seat_handoff_kind` and the six `org_agents` seats. Read them
   with SELECT from production. Without the seats, `a00_agent_action_resolve_addressee` re-addresses every hand-over to `brief`.
6. Keep that database as `qd_base`.

What could not be loaded:
- `hnsw` indexes, because the vector type is a stand-in;
- the routines whose bodies name `leads`, `quotes` and `customers` before those tables exist; they load on the next pass.

Every pool table and routine loads. The check runs the local copy with:
`QD_POOL_LOCAL_PG="host=/tmp/pg-w3-author port=55453 user=postgres dbname=postgres" node --test scripts/checks/every_seat_reads_one_pool.test.mjs`
This copies `qd_base`, applies the file, runs the probe, and checks that a re-run keeps an edited row.

Delete the cluster when done: `pg_ctl stop`, then remove `/tmp/pg-w3-author`.

## 1. What the apply locks, and why it stays short

No index is built on a busy table, no trigger is dropped on a busy table, and no source table is rewritten or updated in bulk.
Measured LOCAL from `pg_locks` (13 Nov evening, PG16 from the mirror with the money and sales files applied first; tables in
the strongest mode the file holds at its commit):

| table | first apply | re-run | who else uses it |
|---|---|---|---|
| `agent_actions`, `company_event`, `customers`, `seat_judgement` | SHARE ROW EXCLUSIVE (`create or replace trigger`) | SHARE ROW EXCLUSIVE | busy: writers wait for it, readers do not |
| `event_subscription` | ACCESS EXCLUSIVE (columns, constraints, RLS, policy), SHARE (its unique index) | SHARE ROW EXCLUSIVE (the edit trigger) | read on every event insert by the old dispatcher's trigger |
| `event_delivery` | ACCESS EXCLUSIVE (RLS, policy) | none | read on every event insert by `fn_priority_backlog_reorder` |
| `subject_link`, `seat_pool_digest`, `pool_event_class`, `ceo_grant_once` | ACCESS EXCLUSIVE (new tables) | SHARE UPDATE EXCLUSIVE (comments) | written by the link trigger once it exists |
| `seat_handoff_kind`, `decision_policy`, `founder_mail_policy`, `seat_duty` | ROW EXCLUSIVE (rows) | ROW EXCLUSIVE | small reference tables |

How it stays short:
- RLS, policies, indexes, columns and constraints are created only when missing (a `do` block reads the catalogue first), so a
  re-run takes nothing stronger than SHARE ROW EXCLUSIVE anywhere.
- The order of the tail: the triggers on `seat_judgement`, `customers` and `agent_actions` (the locks that may WAIT for a long
  writer); then the DDL and seed of `event_subscription` and `event_delivery` (ACCESS EXCLUSIVE on the first apply, which the
  event stream's readers need, so it is taken only after every lock that may wait); then the trigger on `company_event`; then
  the commit.
- The department dispatcher's trigger is NOT dropped by this file: its function's body becomes `return null` (no table lock).
  `scripts/sql/the_department_dispatcher_trigger_goes_once_its_body_is_a_no_op.sql` drops the trigger and the function later,
  alone (ACCESS EXCLUSIVE on `company_event` for the drop; it refuses to run while the old body is still there).
- The file sets `lock_timeout = '1500ms'`: a lock it cannot get in 1.5 s fails the file, which rolls back whole.

Measured LOCAL with a concurrent writer holding `agent_actions` open for 4 s: the apply failed at 1.6–1.7 s on its lock timeout
and rolled back; the worst `company_event` insert meanwhile took 198 ms on a first apply and 54 ms on a re-run (each including
about 50 ms of psql start-up). Before this order it was 1,584 ms (first apply). With no writer: the file takes 130–220 ms.

Back-fill (the last 30 days of links) is not in the apply. The duty does it in batches of 2,000 per table per tick, downward
from the oldest linked row: a key range, no update of the source tables, no export trigger fired.

## 2. Order

Release order across the three branches: money (`docs/runbooks/a_paid_reveal_release_13_nov_2026.md`, its six files) ->
sales (`a_paid_reveal_closes_the_request_and_everyone_on_it_is_told.sql`) -> this file. All three re-apply cleanly in that
order (LOCAL, twice).

1. Merge. At a minute the money runbook's rule 2 read shows no transaction open longer than 5 s, apply the file:
   `node scripts/apply_sql.mjs scripts/sql/every_seat_reads_one_pool_and_every_hand_over_comes_back.sql --apply --ddl --seat ceo`.
   On `55P03 lock timeout`: wait 30 s, read again, re-run; at most 3 times. Then delete
   `scripts/sql/pending/every_seat_reads_one_pool_and_every_hand_over_comes_back.txt` and append the file to the END of
   `MANIFEST.txt`. Check: `pg_trigger` has `zz_pool_link` on `company_event`, `agent_actions`, `seat_judgement` and
   `z41_customer_verified_is_told_to_the_pool` on `customers`; `pg_get_functiondef('public.trg_company_event_dispatch()')`
   contains `RETIRED`.
2. Release rehearsal, once, by the release session:
   `QD_POOL_RELEASE_REHEARSAL=1 node --test scripts/checks/every_seat_reads_one_pool.test.mjs` must print `PROBE OK`.
   The probe writes ZZ DEMO rows (and two `storage.objects` rows under `zz-demo-pool-probe/`) only and always rolls back.
3. Deploy every function that imports `_shared/think.ts`, `_shared/ai_reply.ts` or `_shared/support_reply.ts`, plus
   `ceo_agent`, `resilience_ping` (the replay runs `ceo.it_finding`, `ceo.overdue_handoff` and `ceo.authority`) and the seats'
   edge functions. Until the SQL is live, the TS reads an empty pool and goes on as before.
4. A later quiet minute, the dispatcher's trigger, alone:
   `node scripts/apply_sql.mjs scripts/sql/the_department_dispatcher_trigger_goes_once_its_body_is_a_no_op.sql --apply --ddl --seat ceo`
   (same retry rule), then its pending note goes and the file is appended to `MANIFEST.txt`.
5. Regenerate the mirror: `node scripts/checks/export_from_either_source_is_identical.mjs --write`.

## 3. The lines for fn_founder_brief (the money-side branch owns that brief)

Until they are added, the founder is told by `fn_ceo_tells_the_founder_daily`: one e-mail a day, deduplicated, kind
`ceo_needs_the_founder`. In the money branch's `fn_founder_brief` the text accumulator is `v_body`: declare `v_pool jsonb;`, then
after `v_body := v_body || public.fn_founder_brief_ceo_lines(v_from, v_to);` add

```sql
v_pool := public.fn_founder_brief_overdue_handoffs(8);
if (v_pool->>'count')::int > 0 then v_body := v_body || E'\nThe CEO needs you on ' || (v_pool->>'count') || ' item(s): ' || (select string_agg(l, '; ') from jsonb_array_elements_text(v_pool->'lines') l); end if;
```

and then retire `fn_ceo_tells_the_founder_daily` from the `ceo.company_pool` tick, or he is told the same items twice a day.

## 4. After the apply, watch

- `seat_duty` `ceo.company_pool`: `last_ok_at` every 15 minutes; `avg_ms` (measured locally: 234–365 ms on a busy day of 5,000
  events and 500 open hand-overs); `failures`.
- `seat_pool_digest.built_at` advancing, and `subject_link` growing as the back-fill reaches 30 days.
- `reasoning_held_question` on `ceo.it_finding`, `ceo.overdue_handoff` and `ceo.authority`: at most 30 a day, re-asks included
  (`fn_ceo_judgement_room()->>'asked_today'`). The decision is written onto the hand-over as `evidence.ceo_decision`;
  `ceo.order` hand-overs open in the seats' queues and close when they report; `ceo.decision_closed` reaches the it_engineer.
- `ceo_grant_once`: rows granted, used (`used_at`) and expired unused.
- `ai_cost_log` for the CEO's `routine_employee_reasoning`: about AED 0.0106 a call.
- The first `handoff.overdue.escalated` events and `detail.silence.escalated_to`: the CEO for his staff, the founder only for
  the CEO's own.
- `company_event` insert latency in the apply minute.
