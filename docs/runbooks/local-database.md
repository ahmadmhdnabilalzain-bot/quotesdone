# A local copy of the production database schema

Owner: it_engineer. Written 9 Nov 2026.

## Why this matters

Until this date nothing in the repository could rebuild the database. `supabase/migrations` replays
414 tables, 8 functions and 0 policies; production holds 784 tables, 2,045 routines, 88 views and 350
policies. Every change was a `scripts/sql` file applied straight to production. So a database defect could
only be reproduced against production itself, and a fix could only be tried there. That is the main reason
bug fixes went round in loops.

Now the committed schema mirror (`supabase/schema/full_schema/`, re-exported from production after every
apply) is turned into a working local Postgres in about 15 seconds, and the result is measured object by
object.

## Use it

```bash
supabase start            # once per machine/session: the local Supabase stack (needs Docker)
npm run db:local          # build the schema locally, then measure it against the mirror
```

Expected tail, measured on 9 Nov 2026 from a clean `supabase db reset --local`:

```
kind        mirror  local  missing
tables         784    784        0
views           88     88        0
routines      2040   2164        0     (local also counts the extensions' own functions)
policies       350    350        0
triggers       398    398        0
cron_jobs       92     92        0
cron jobs active locally: 0 (must be 0)

LOCAL DATABASE MATCHES THE MIRROR
```

The command exits 1 if any object is missing or any cron job is active. Connect with
`docker exec -it supabase_db_<project> psql -U postgres`, or on `postgresql://postgres:postgres@127.0.0.1:54322/postgres`.
To start over: `supabase db reset --local`, then `npm run db:local` again.

Use it to:
- reproduce a database defect: seed `ZZ DEMO` rows locally and call the routine;
- rehearse a new `scripts/sql` file before it goes anywhere near production:
  `docker exec -i supabase_db_<project> psql -U postgres -v ON_ERROR_STOP=1 < scripts/sql/<file>.sql`;
- read a routine's live definition without a production token.

## Without Docker: the database every rehearsal runs on (`scripts/db/local_pg16.mjs`, 13 Nov 2026)

On 13 Nov 2026 rolled-back rehearsals on production held the locks of the changes they rehearsed for 12-15 s and live requests
were cancelled behind them (`.claude/memory/a-rehearsal-on-production-holds-the-locks-of-a-real-change.md`). Since then every
replay (`scripts/lib/safe_replay.mjs`: `rehearse_sql.mjs`, `rehearseChain`, the checks' rolled-back probes) runs on a local
database by default, and on production only with `QD_REPLAY_ON_PRODUCTION=1`, cut at 5 s. A cloud session has no Docker
daemon but has Postgres 16, so this builds the same schema with plain `initdb`:

```bash
node scripts/db/local_pg16.mjs start      # initdb + start, then load the mirror if empty: ~20 s
export QD_LOCAL_DB_URL="$(node scripts/db/local_pg16.mjs url)"
node scripts/ci/rehearse_sql.mjs scripts/sql/<file>.sql scripts/sql/<file>_probe.sql    # PROBE OK, on the local copy
npm test                                  # every replay in it goes here too
node scripts/db/local_pg16.mjs load       # reload after a mirror change
node scripts/db/local_pg16.mjs stop       # stop and delete the directory
```

- `QD_LOCAL_PG_DIR` (default `<tmp>/qd-local-pg16`), `QD_LOCAL_PG_PORT` (default 55433), `QD_PG_BIN` (default
  `/usr/lib/postgresql/16/bin`). As root it runs the server as `postgres` (initdb refuses root); it listens only on a Unix
  socket in its own directory.
- What a plain Postgres lacks is stood in by `scripts/db/local_pg16_standins.sql`: the Supabase roles, `auth.users`,
  `storage.objects`, `cron.job` / `cron.schedule`, `net.http_post` (queues a row, sends nothing), the vault; pgvector columns
  become `real[]`. After the schema it seeds what the probes read first: dummy `project_ref` and `cred_db_internal` rows in
  `app_secrets` (no real secret) and the six seats in `org_role` and `org_agents`.
- Measured 13 Nov 2026: 808 tables, 2,175 routines, 374 policies, 403 triggers, 110 cron jobs (0 active), loaded in ~18 s.
- It holds no row data. A probe that counts production's rows answers differently here; that is what
  `QD_REPLAY_ON_PRODUCTION=1` is for, behind the 5 s cut. Postgres 16 has no `transaction_timeout`, so the cut itself is
  measured on a 17 (production runs 17.6).
- `npm test` / `npm run gate` with a management token and neither `QD_LOCAL_DB_URL` nor `QD_REPLAY_ON_PRODUCTION=1`: every
  replaying check stops with "SAFE REPLAY HAS NO DATABASE" and the command above; nothing is rehearsed on production.

## What it is and is not

- **Schema only.** No rows and no secret values: the mirror carries neither. Nothing in the local database
  can reach a real customer or supplier.
- **No job ever runs.** The mirror schedules 92 pg_cron jobs. Each one is created and switched off in the
  same statement (`qd_local.schedule_off`), so none is active at commit. Measured 0 active.
- **The public schema.** The export covers `public` (plus cron jobs and secret key names). Objects in other
  application schemas (for example `kb_stage`) are not in the mirror, so they are not local either.
- **As fresh as the mirror.** The mirror's banner says when it was captured. After a production apply, the
  release train regenerates it (`node scripts/checks/export_from_either_source_is_identical.mjs --write`).

## How it works (`scripts/db/local_from_mirror.mjs`)

The mirror could not be replayed as committed, for two reasons:
1. `fn_schema_export()` prints each routine with `pg_get_functiondef()`, which ends the body at `$function$`
   with **no semicolon**. psql then reads the whole FUNCTIONS section, about 91,000 lines, as one statement
   and drops it with a single syntax error. The builder adds the terminator to each of the 2,045 bodies.
2. The export has **no `CREATE TYPE`**. The builder reads the enum definitions (`answer_precedence`,
   `gate_state`) from the SQL history, in apply order, and creates them first.

It then sets `check_function_bodies = off`, as `pg_dump` does, and replays in passes until no new object
appears (the export's order is best-effort, so a generated column can name a routine defined later). Two or
three passes converge. `scripts/db/local_from_mirror.test.mjs` pins the three text transformations offline,
so a mirror that changes shape fails `npm test`.

## A production finding it surfaced

With body validation on, these routines fail because they call routines that no longer exist in the mirror:
`fn_ws_ea`, `fn_ws_exec`, `fn_ws_governance`, `fn_ws_notifications`, `fn_ws_operations`, `fn_ea_agenda`
(they name `fn_founder_queue`, `fn_ea_agenda`, `fn_founder_refund_approvals_open`), and
`fn_ad_spend_daily_ceiling` (names `fn_ads_autospend_state`). In production they would fail the same way the
moment they are called. `fn_category_questions` names `kb_stage.questions`, which is outside the mirror's
schema and may exist in production. Recorded in `docs/engineering/tech-debt.md`. This has not been
re-measured against production: this session had no valid production token.

## The longer-term target

The standard end state is ordinary Supabase migrations: one baseline dumped from production, `migration
repair` run once, then every change as a timestamped migration that `supabase db reset` replays locally and
`supabase db push` applies. That move needs a production token, and the canonical-routine check
(`scripts/checks/canonical_routine_manifest.mjs`) must learn the new tier first, so it is planned rather
than done. Until then this builder is how a person gets a real local database.
