# Rollback runbook

Closes independent audit finding **8.3 — "Rollback procedures", FAIL, severity critical**:
*"there are no Phase 1 rollback artefacts at all"*, and *"the one rollback that does exist is
broken as written"*.

Read this before an incident, not during one.

## If something is wrong right now

Do this first. It takes one statement, deletes nothing, and is reversible:

```sql
select public.fn_phase1_disarm('you@quotesdone.com', 'what is happening');
```

Every mutating admin action now passes without Control Mode. Nothing is dropped and nothing is
deleted. Actions that pass while disarmed are still written to `control_mode_audit` as
`action_allowed_phase1_disarmed`, so the record of what was done under the relaxed control
survives — during an incident that is the most valuable data in the database.

Check what you did, and put it back when the incident is over:

```sql
select public.fn_phase1_status();
select public.fn_phase1_rearm('you@quotesdone.com', 'incident closed, restoring the gate');
```

Everything is recorded in `public.phase1_rollback_log`, which is append-only — rows there cannot
be edited or deleted, including by the person who wrote them.

## Files

| File | Covers | Destructive |
|---|---|---|
| *(no file — `fn_phase1_disarm` / `fn_phase1_rearm`)* | Phase 1, tier 0 | no |
| `phase1_down.sql` section 1 | Phase 1, tier 1 revert | no |
| `phase1_down.sql` section 2 | Phase 1, tier 2 teardown | **yes** |
| `p2_c1_stage_a_down.sql` | P2-C1 Stage A | yes |
| `p2_c1_stage_b_down.sql` | P2-C1 Stage B | yes |
| `phase1_containment_down.sql` | Phase 1 containment (already removed by Phase 0) | yes |

## The three tiers, and why

Phase 1's tables are the refunds ledger and the Control Mode audit trail. They are **financial and
security evidence.** A rollback that drops them turns a bad deploy into an unreconstructable one —
and a rollback nobody dares run is not a rollback at all. So rollback is graded by what it costs:

- **Tier 0 — disarm.** Stop Phase 1 *gating* the system. Every row stays. Seconds. Reversible.
  This is the one you will actually use.
- **Tier 1 — revert.** Restore the pre-Phase-1 function definitions. Evidence tables and all their
  rows stay. Use when Phase 1's *logic* is wrong but its records are still wanted — the normal case.
- **Tier 2 — teardown.** Drop the objects. Requires a verified evidence export first; the script
  refuses to proceed without one. Use only when Phase 1 is being abandoned, not fixed.

Escalate one tier at a time.

## What no tier can undo

Stated here so it is not discovered mid-incident.

- **`p1h_06`.** It deactivated the non-primary Control Mode identity *and* added the unique index
  `control_mode_identity_one_active_per_phone`. The deactivation cannot be undone while the index
  stands — rehearsal confirmed it, `23505` duplicate key. Reverting means dropping the index, which
  reinstates two admin identities on one phone. Section 1.3 leaves it alone unless you set
  `qd.revert_p1h_06 = 'on'`.
- **`p1h_10`.** Re-tightening `refunds.amount_fils` to `NOT NULL` only works if no refund with an
  unknown amount exists. If one does, it is a real refund and the constraint stays relaxed.
  Resolve it with `fn_refund_amount_resolve()` first.
- **Consumed challenges and closed sessions.** Single-use security artefacts. Re-opening a consumed
  challenge would be a vulnerability, not a restoration.
- **Money that moved.** Dropping a ledger row does not un-refund a refund. It only makes it
  unreconcilable. That is why tier 2 demands an export.

## Rehearsing

Any of these can be rehearsed against production without consequence, because Postgres DDL is
transactional — wrap it and abort.

```sql
begin;
select public.fn_phase1_rollback_rehearse('your.name');   -- tier 0, self-asserting
rollback;
```

For tiers 1 and 2, paste the section inside `begin; ... rollback;` and read
`select public.fn_phase1_status();` before the abort.

**Rehearse before you need it.** The 3 August 2026 rehearsal of `phase1_down.sql` found two defects
in its own first draft, both of which would have struck an operator mid-rollback:

1. §1.3 reactivating the Control Mode identities is impossible while `p1h_06`'s unique index stands.
2. §1.5 `update cron.job set active = false` is denied to the Supabase roles (`42501`); the
   supported route is `cron.alter_job()`.

Neither was visible by reading the SQL. A rollback that has never been executed is a document, not
a procedure.

## Known correction to `p2_c1_stage_b_down.sql`

Its mandatory step 2 named five files under `supabase/migrations/` with a `2026080219xx` prefix.
**None of those paths existed** — the files had been moved to `migrations-superseded-consolidated/`
— and step 1 drops `shared.brand_acceptance_policy` with `cascade` *before* step 2 runs, so an
operator following the procedure was left with Stage A dropped and nothing at the path given to
restore it.

Corrected 3 August 2026. Step 2 now names the **eleven applied** Stage A migrations
(`20260802165328` … `20260802170530`), verified against `supabase_migrations.schema_migrations`.
Pointing it at `migrations-superseded-consolidated/` would have been wrong even had the files been
there: that directory holds the superseded authoring set, so it would have restored a *different*
Stage A from the one being rolled back to.

Pre-flight before running it:

```powershell
Get-ChildItem supabase\migrations -Filter '*p2_c1_stage_a*' | Measure-Object   # expect 11
```

## After a tier 2 teardown

`fn_control_mode_require` is gone, and three deployed edge functions call it by RPC: **`os_ops`**,
**`refunds_api`**, **`os_api`**. They fail *closed* — a failed RPC is treated as "not allowed" — so
a teardown without a redeploy locks every mutating admin action rather than opening it. That is the
safe failure, but it is still an outage. Redeploy all three in the same window.
