# Applying the shared pool and the CEO's authority (ceo, 13 Nov 2026; updated 15 Nov 2026)

Three files, in this order (founder ledger 1688, then 1696 and 1701 of 15 Nov 2026), each with its probe:

1. `scripts/sql/the_company_limits_bind_every_seat_and_the_ceo_changes_one_only_after_a_day.sql` (+ `_probe.sql`): the company
   limits (per action and per day, AED; append-only; a change takes effect 24 hours after it is written), the spend
   commitments, the money / deploy / gate classifiers and the message-gate reading. The pool's authority check reads them.
2. `scripts/sql/every_seat_reads_one_pool_and_every_hand_over_comes_back.sql` (+ `_probe.sql`): the pool, the CEO's judgement,
   the orders and the authority check. Since 15 Nov nothing in it asks the founder: the CEO decides inside the limits.
3. `scripts/sql/the_ceo_reads_supplier_coverage_and_orders_the_seats_to_grow_it.sql` (+ `_probe.sql`): the coverage target
   (proposed at apply, confirmed by the CEO's first run), the coverage and funnel readings, the CEO's daily supply loop that
   orders the seats, and the founder's daily summary (information, never a question).

What they build: `docs/architecture/the-office.md`.

**Never rehearse this on production while working.** On 13 Nov a rehearsal held one file's locks on production for the length
of its transaction, and live readers and writers hit their 8-second timeout. Work on a local copy (step 0). The ONE
production rehearsal is the release step (step 2), run by the release session.

## 0. Local copy (every change)

1. Write the schema SQL: `env -u SUPABASE_ACCESS_TOKEN -u SUPABASE_DB_URL node scripts/db/local_from_mirror.mjs --sql-only=/tmp/pg-w3-schema.sql`.
   The money and sales branches' routines the pool needs (`fn_handoff_note_citation`, `fn_demo_shadow_record`) are on main
   and in the mirror since 15 Nov.
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
   The limits file seeds from `ad_spend_policy` (row `default`), the coverage file from `trade_opening_rule` (id 1): load both
   (production, SELECT 15 Nov: AED 30 / AED 30; open at 10, floor 5).
6. Keep that database as `qd_base`.

What could not be loaded:
- `hnsw` indexes, because the vector type is a stand-in;
- the routines whose bodies name `leads`, `quotes` and `customers` before those tables exist; they load on the next pass.

Every pool table and routine loads. The check runs the local copy with:
`QD_POOL_LOCAL_PG="host=/tmp/pg-w3-author port=55453 user=postgres dbname=postgres" node --test scripts/checks/every_seat_reads_one_pool.test.mjs`
This copies `qd_base`, applies the limits file and the pool file, runs the probe, and checks that a re-run keeps an edited row.

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

The two other files (LOCAL, 15 Nov 2026, the same `pg_locks` reading; ACCESS SHARE reads left out):

| file | first apply | re-run |
|---|---|---|
| limits | ACCESS EXCLUSIVE on its two new tables only | SHARE ROW EXCLUSIVE on `company_limit_change` (`create or replace trigger`), SHARE UPDATE EXCLUSIVE (comments) |
| coverage | ACCESS EXCLUSIVE on its two new tables only; ROW EXCLUSIVE on `seat_duty`, `founder_mail_policy` (+ its history), `seat_playbook` | ROW EXCLUSIVE on `seat_duty`, `founder_mail_policy`, `supplier_coverage_target`; SHARE UPDATE EXCLUSIVE (comments) |

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

THE STALL, MEASURED (LOCAL, PG16 from the mirror, 15 Nov 2026; the third review's `live.sh`: a writer holds one insert open
for 4 s, the apply starts 0.5 s later, an event writer and a hand-over writer insert every 50 ms in autocommit and report their
worst insert). The earlier figure here, 198 ms / 54 ms, was wrong: it measured the event writer while the open writer was on
`agent_actions`, the one case where events do not wait.

| file, run | open writer on | apply | worst hand-over insert | worst event insert |
|---|---|---|---|---|
| pool, first apply | `agent_actions` | fails at 1,623 ms (lock timeout), rolls back | 1,484 ms (1 insert over 100 ms) | 20 ms |
| pool, re-run | `agent_actions` | fails at 1,610 ms | 1,493 ms (1) | 9 ms |
| pool, first apply | `company_event` | fails at 1,669 ms | 1,480 ms (1) | 1,488 ms (1) |
| pool, re-run | `company_event` | fails at 1,694 ms | 1,526 ms (1) | 1,455 ms (1) |
| limits, first apply | either | 58–76 ms, applies | 18 ms | 21 ms |
| coverage, first apply | either | 80–115 ms, applies | 13 ms | 12 ms |

So each failed attempt of the pool file stalls ONE write of each kind it queues behind for about 1.5 s (the third review
measured 1.45–1.67 s); three attempts stall up to about 4.5–5 s of writes in all. The limits and coverage files touch no busy
table. With no writer: limits 55–95 ms, pool 116–225 ms, coverage 62–115 ms.

Back-fill (the last 30 days of links) is not in the apply. The duty does it in batches of 2,000 per table per tick, downward
from the oldest linked row: a key range, no update of the source tables, no export trigger fired.

## 2. Order

The money and sales branches are on main (15 Nov). The three CEO files re-apply cleanly in the order below (LOCAL, twice,
each probe PROBE OK both times).

0. Merge. Apply the limits file (any minute: no busy table):
   `node scripts/apply_sql.mjs scripts/sql/the_company_limits_bind_every_seat_and_the_ceo_changes_one_only_after_a_day.sql --apply --ddl --seat ceo`,
   its pending note goes, the file is appended to the END of `MANIFEST.txt`. Check: `select public.fn_company_limits()` shows
   both limits.
1. At a minute the money runbook's rule 2 read shows no transaction open longer than 5 s, apply the pool file:
   `node scripts/apply_sql.mjs scripts/sql/every_seat_reads_one_pool_and_every_hand_over_comes_back.sql --apply --ddl --seat ceo`.
   On `55P03 lock timeout`: wait 30 s, read again, re-run; at most 3 times. Then delete
   `scripts/sql/pending/every_seat_reads_one_pool_and_every_hand_over_comes_back.txt` and append the file to the END of
   `MANIFEST.txt`. Check: `pg_trigger` has `zz_pool_link` on `company_event`, `agent_actions`, `seat_judgement` and
   `z41_customer_verified_is_told_to_the_pool` on `customers`; `pg_get_functiondef('public.trg_company_event_dispatch()')`
   contains `RETIRED`.
1b. Apply the coverage file (any minute):
   `node scripts/apply_sql.mjs scripts/sql/the_ceo_reads_supplier_coverage_and_orders_the_seats_to_grow_it.sql --apply --ddl --seat ceo`,
   pending note, MANIFEST line. Check: `select status, count(*) from supplier_coverage_target group by 1` shows the proposal.
2. Release rehearsal, once, by the release session:
   `QD_POOL_RELEASE_REHEARSAL=1 node --test scripts/checks/every_seat_reads_one_pool.test.mjs` must print `PROBE OK`.
   The probe writes ZZ DEMO rows (and two `storage.objects` rows under `zz-demo-pool-probe/`) only and always rolls back.
3. Deploy every function that imports `_shared/think.ts`, `_shared/ai_reply.ts` or `_shared/support_reply.ts` (routing.ts
   FIRST among them: without `authority` in its lists the CEO's questions of authority run on his Opus route), plus
   `ceo_agent` (coverage, limit, target), `resilience_ping` (the replay runs `ceo.it_finding`, `ceo.overdue_handoff` and
   `ceo.authority`), `sales_engineer` ('match' on the subject-aware rule, 202 when it asked the CEO), `accountant` and
   `marketing` (a CEO order is reported). Until the SQL is live, the TS reads an empty pool and 'match' falls back to the
   three-argument rule, so the deploy order is not a hazard.
4. A later quiet minute, the dispatcher's trigger, alone:
   `node scripts/apply_sql.mjs scripts/sql/the_department_dispatcher_trigger_goes_once_its_body_is_a_no_op.sql --apply --ddl --seat ceo`
   (same retry rule), then its pending note goes and the file is appended to `MANIFEST.txt`.
5. Regenerate the mirror: `node scripts/checks/export_from_either_source_is_identical.mjs --write`.

## 3. The founder is told, never asked (founder ledger 1696, 15 Nov 2026)

There are no "lines for fn_founder_brief" any more and no `ceo_needs_the_founder` mail: nothing waits on him. The CEO's day
reaches him once, after 07:00 Dubai, from the `ceo.supply_coverage` duty: `fn_ceo_daily_summary_to_the_founder`, kind
`ceo_daily_summary` (severity info; `founder_mail_policy` can silence it). It says supplier coverage against target, the
funnel, the CEO's decisions of the last day with their reasons (IT findings, late hand-overs, seats' questions of authority,
his own authority, the supply orders and targets), the company limits with any waiting change, and the open orders.

## 4. After the apply, watch

- `seat_duty` `ceo.company_pool`: `last_ok_at` every 15 minutes; `avg_ms` (measured locally: 234–365 ms on a busy day of 5,000
  events and 500 open hand-overs); `failures`.
- `seat_pool_digest.built_at` advancing, and `subject_link` growing as the back-fill reaches 30 days.
- `reasoning_held_question` on `ceo.it_finding`, `ceo.overdue_handoff` and `ceo.authority`: at most 30 a day, re-asks included
  (`fn_ceo_judgement_room()->>'asked_today'`). The decision is written onto the hand-over as `evidence.ceo_decision`;
  `ceo.order` hand-overs open in the seats' queues and close when they report; `ceo.decision_closed` reaches the it_engineer.
- `ceo_grant_once`: rows granted, used (`used_at`) and expired unused.
- `ai_cost_log` for the CEO's `routine_employee_reasoning`: about AED 0.0106 a call.
- The first `handoff.overdue.escalated` events and `detail.silence.escalated_to`: the silent seat's superior (the CEO for his
  staff), and the CEO himself for his own (never the founder).
- `seat_duty` `ceo.supply_coverage`: one `ceo_supply_decision` row of kind `run` a day; on the first run `confirm_targets`; the
  `ceo.order` hand-overs with `detail.path = 'coverage'` (no invitation order while `invite_enabled` is false: the `no_order`
  row says so); `founder_alerts` with `dedupe_key` `ceo_daily_summary:<day>`.
- `company_spend_commitment` per day against `fn_company_limits()`, and `company_limit_change` rows set by the CEO (each in
  force a day after it was written).
- `company_event` insert latency in the apply minute.
