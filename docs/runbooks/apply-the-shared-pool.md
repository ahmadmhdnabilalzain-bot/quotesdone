# Applying the shared pool (ceo, 13 Nov 2026)

File: `scripts/sql/every_seat_reads_one_pool_and_every_hand_over_comes_back.sql`. Its probe:
`scripts/sql/every_seat_reads_one_pool_and_every_hand_over_comes_back_probe.sql`. What it builds:
`docs/architecture/the-office.md`.

**Never rehearse this on production while working.** On 13 Nov a rehearsal held one file's locks on production for the length
of its transaction, and live readers and writers hit their 8-second timeout. Work on a local copy (step 0). The ONE
production rehearsal is the release step (step 2), run by the release session.

## 0. Local copy (every change)

1. Write the schema SQL: `node scripts/db/local_from_mirror.mjs --sql-only=/tmp/pg-w3-schema.sql`.
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

No index is built on a busy table, and no source table is rewritten or updated in bulk. The pool reads its own
`subject_link` (a new table) and primary-key ranges.

| statement | table | lock | how long |
|---|---|---|---|
| add columns (constant default or nullable), constraints, unique index, policies, the edit trigger | `event_subscription`, `event_delivery` (0 rows each) | ACCESS EXCLUSIVE | the transaction; nothing reads them yet |
| create `subject_link`, `seat_pool_digest`, `pool_event_class` | new | none for others | |
| seed merge, `seat_handoff_kind` rows and the it.finding→ceo handler, `decision_policy`, `founder_mail_policy`, `seat_duty` | small reference tables | ROW EXCLUSIVE | the transaction |
| LAST: `create trigger zz_pool_link` on `company_event`, `agent_actions`, `seat_judgement` | busy | SHARE ROW EXCLUSIVE (blocks writes, not reads) | from the statement to the commit: milliseconds, because they are the last statements |
| LAST: `drop trigger trg_company_event_dispatch` and its function | `company_event` | ACCESS EXCLUSIVE | the same |

The file sets `lock_timeout = '1500ms'`. If a writer holds `company_event` longer, the apply fails at once and is simply
re-run: it never queues every later writer behind itself. Apply off-peak.

Back-fill (the last 30 days of links) is not in the apply. The duty does it in batches of 2,000 per table per tick, downward
from the oldest linked row: a key range, no update of the source tables, no export trigger fired.

## 2. Order

1. Merge. Apply the file: `node scripts/apply_sql.mjs scripts/sql/every_seat_reads_one_pool_and_every_hand_over_comes_back.sql --apply --ddl`.
   Then delete `scripts/sql/pending/every_seat_reads_one_pool_and_every_hand_over_comes_back.txt` and append the file to the
   END of `MANIFEST.txt`.
2. Release rehearsal, once, by the release session:
   `QD_POOL_RELEASE_REHEARSAL=1 node --test scripts/checks/every_seat_reads_one_pool.test.mjs` must print `PROBE OK`.
   The probe writes ZZ DEMO rows only and always rolls back.
3. Deploy every function that imports `_shared/think.ts`, `_shared/ai_reply.ts` or `_shared/support_reply.ts`, plus
   `ceo_agent`, `resilience_ping` (the replay runs `ceo.it_finding`) and the seats' edge functions.
   Until the SQL is live, the TS reads an empty pool and goes on as before.
4. Regenerate the mirror: `node scripts/checks/export_from_either_source_is_identical.mjs --write`.

## 3. The two lines for fn_founder_brief (the money-side branch owns that brief)

Until those lines are added, the founder is told by `fn_ceo_tells_the_founder_daily`: one e-mail a day, deduplicated, kind
`ceo_needs_the_founder`. Add, where the brief builds its lines (`v_lines` here stands for its text accumulator):

```sql
v_pool := public.fn_founder_brief_overdue_handoffs(8);
if (v_pool->>'count')::int > 0 then v_lines := v_lines || E'\nThe CEO needs you on ' || (v_pool->>'count') || ' item(s): ' || (select string_agg(l, '; ') from jsonb_array_elements_text(v_pool->'lines') l); end if;
```

## 4. After the apply, watch

- `seat_duty` `ceo.company_pool`: `last_ok_at` every 15 minutes; `avg_ms` (measured locally: 234–365 ms on a busy day of 5,000
  events and 500 open hand-overs); `failures`.
- `seat_pool_digest.built_at` advancing, and `subject_link` growing as the back-fill reaches 30 days.
- `reasoning_held_question` on `ceo.it_finding`: at most 30 a day. Their `result` (the decision) is written onto the it.finding as
  `evidence.ceo_decision`, and `ceo.decision_closed` hand-overs reach the it_engineer.
- `ai_cost_log` for the CEO's `routine_employee_reasoning`: about AED 0.0106 a call.
- The first `handoff.overdue.escalated` events, and who decides them.
- `company_event` insert latency in the apply minute.
