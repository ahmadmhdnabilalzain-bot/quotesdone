# Phase B — production deployment evidence

## Where and when

| | |
| --- | --- |
| production project | `htdblwldjkcgjvmqkbeh` (the only project; staging was deleted 15 Aug 2026) |
| branch | `phase-b/business-workflow-closure` |
| deployed at | 15 Aug 2026, ~07:5x UTC (Dubai is UTC+4) |
| deploy method | `node scripts/apply_sql.mjs <file> --apply --ddl` — posts the committed bytes and reads the definitions back out of the database |

## The committed migration

Applied in this order. Each file is one implicit transaction; the digests are of the bytes that
were posted.

| # | file | KB | sha256 |
| --- | --- | --- | --- |
| 1 | `scripts/sql/phase_b_01_workflow_registry_schema.sql` | 20 | `01158ab8f60035823d14e2760b5641bfda94515582496707ca34de7379681862` |
| 2 | `scripts/sql/phase_b_02_identity_aliases.sql` | 25 | `b5fb12776078f09a806d875e8c7c8da783b4484388c829e3ae87925798e6c940` |
| 3 | `scripts/sql/phase_b_03_registry_core.sql` | 66 | `27e0654b46035735a5d00c94efb7f5472f964cb35c6e54c555166c0f01a15d5f` |
| 4 | `scripts/sql/phase_b_04_steps.sql` | 195 | `0bddf369d9ac1b67e9f9935617e0bca9880f15a1831bc63e572f30a9c208c0df` |
| 5 | `scripts/sql/phase_b_05_handoffs_and_exceptions.sql` | 129 | `0a5d7735984f289335dc3a1e68b7cf51b31ec852efeb95d915c120c7226018dd` |
| 6 | `scripts/sql/phase_b_06_events.sql` | 111 | `ea24f17afc23f81d002a8f05c2af29ba2569abff4df96b3260a24d688f1e3f89` |
| 7 | `scripts/sql/phase_b_07_crosswalk.sql` | 294 | `502e067a4dcba0ebc631f17e676eb6bf33b0f8b112fc24721170d9672552973a` |
| 8 | `scripts/sql/phase_b_08_validators.sql` | 19 | `c66c6a1281e62670cbff90f2b9347332911ca00486a67f1b07c5e8df55c743b2` |

**Exact rollback:** `scripts/sql/phase_b_workflow_closure_rollback.sql`
sha256 `a64833d57ce1f5a53ae99a66a0d942fcb73fe50b3ef7d20b73a5d5f3a9768995`

The SQL is generated from the checksummed package by `scripts/phase_b/gen_migration.mjs`, and
`scripts/checks/phase_b_invariants.test.mjs` regenerates it on every run and fails if a single
byte differs. The repository and the founder-approved document cannot drift apart silently.

## Aborted rehearsal, before anything was written

The exact committed bytes — all eight files concatenated, 860 KB — were posted to production
inside one implicit transaction ending in a `raise exception` that first reads the post-change
counts. The numbers came out; nothing committed.

```
node scripts/phase_b/rehearse.mjs
```

```
REHEARSAL workflows=30 steps=257 handoffs=161 events=347 crosswalk=719 aliases=237
          invariants=71/71 FAILED=[none]
```

Production fingerprint, taken before and again after the abort:

```
{"org_roles":180,"org_role_aliases":168,"org_departments":32,"org_workflow_ownership":30,
 "phase_a_drift":0,"phase_a_violations":0,"cron_jobs":205,"cron_active":186,
 "llm_routes_held":8,"phase_b_tables":0,"public_functions":991,"public_triggers":175}
digest 544fbacbbae9d886f755afc5a283cb909fc5d126fb5c46f6cbbacc735c0cd66c
```

Identical before and after. The rehearsal script refuses to report success if the digest moves,
and refuses to report success if the migration does **not** raise — a rehearsal that commits is
not a rehearsal.

The rehearsal earned its place twice. It caught the owner guard refusing `founder` as an
independent reviewer — the founder *is* W01's reviewer in the frozen Phase A registry, so the
guard would have made the one review he performs unstorable. And it caught
`integrity.dispatch_without_quote_ready_gate` asking the wrong question. Both were fixed before
a single byte reached production.

## What the deployment created

17 tables, 8 functions, 3 triggers, 69 alias rows.

| table | rows |
| --- | --- |
| `phase_b_workflow` | 30 |
| `phase_b_workflow_step` | 257 |
| `phase_b_handoff` | 161 |
| `phase_b_event` | 347 |
| `phase_b_crosswalk` | 719 |
| `phase_b_business_object` | 56 |
| `phase_b_business_rule` | 54 |
| `phase_b_exception` | 50 |
| `phase_b_sla_policy` | 34 |
| `phase_b_gate` | 32 |
| `phase_b_dynamic_actor` | 21 |
| `phase_b_workflow_transition` | 35 |
| `phase_b_step_transition` | 19 |
| `phase_b_workflow_state` | 14 |
| `phase_b_step_state` | 11 |
| `phase_b_founder_boundary` | 10 |
| `phase_b_package_erratum` | 3 |

`org_role_alias` went from 168 to 237 rows: 45 `packaged_role_id` and 24 `title`. One packaged
name (`chief_product_technology_officer`) already had an alias and was left alone.

No `SECURITY DEFINER` function was created, so there is no `PUBLIC EXECUTE` grant to revoke. The
registry is readable structure, not an authority escalation.

## Post-deployment verification

```bash
node scripts/checks/phase_b_invariants.test.mjs                        # 77/77
node scripts/checks/phase_b_guards_reject_injected_defects.test.mjs    # 18/18 fired
node scripts/phase_b/validate_package.mjs                              # 84/84
```

Phase A, re-measured after deployment:

```
phase_a_drift_rows      0
phase_a_violations      0
active_departments      10
canonical_roles         90
category_overlays       86
org_workflow_ownership  30
```

Nothing activated:

```
cron_jobs         205   (unchanged from preflight)
cron_active       186   (unchanged from preflight)
llm_routes_held     8   (all 8 open until 2126-08-15)
customers           0
inquiries           0
workflow_run      323   (unchanged from preflight)
phase_b cron jobs   0
```

## Rollback readiness

`scripts/sql/phase_b_workflow_closure_rollback.sql` drops the 17 tables, the 3 triggers and the
8 functions, and deletes the alias rows Phase B added — matched on the reason text the forward
migration wrote, never on alias name alone, so an alias that already existed under a different
reason is left to whoever created it.

It touches nothing Phase A owns. After it runs, both of these must hold:

```sql
select count(*) from public.fn_phase_a_baseline_drift();               -- 0
select count(*) from information_schema.tables
 where table_schema = 'public' and table_name like 'phase\_b\_%';      -- 0
```

Rolling back discards the crosswalk measurement. That is deliberate: it is reproducible from the
repository, and a stale measurement left behind after a rollback is worse than none.

```bash
node scripts/phase_b/inventory_estate.mjs > docs/phase-b/_inventory.json && node scripts/phase_b/build_crosswalk.mjs
```

## Zero paid inference

No OpenRouter request, no other paid provider call, no LLM invocation of any kind occurred
during Phase B. All 8 routes in `llm_route_health` remain held open-circuit until 2126-08-15;
the hold was not released and no request was made against it.

Paid inference cost for Phase B: **USD 0.00**.
