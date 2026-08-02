# Stage B.6 — recovery manifest

**Status: NOT YET RECOVERED INTO THIS REPOSITORY.** Twelve migrations are applied to project
`htdblwldjkcgjvmqkbeh` and recorded in `supabase_migrations.schema_migrations`, but the SQL is not
yet in `supabase/migrations/`. HEAD is `ceeafd7`.

This manifest exists so the recovery can be *verified*, not just performed. Each recovered file must
hash to the SHA-256 below, computed over `array_to_string(statements, E';\n') || ';'` — the exact
form the migration is stored in.

| # | Version | Name | SHA-256 | chars |
|---|---|---|---|---|
| 1 | 20260802181006 | p2_c1_stage_b6_frozen_holdout_schema | `f0e8659ea527ea7f4e5e538490724fe5aa2976392a00fdc7a7dee692cef445e3` | 4,740 |
| 2 | 20260802181147 | p2_c1_stage_b6_frozen_holdout_cases | `e785329adb291c1efb69e6d38b00f56c9551f256105187c9cd1fe4a38b5c6beb` | 9,827 |
| 3 | 20260802181351 | p2_c1_stage_b6_scope_disposition_schema | `9027eb00f0d9dda56421ddee2cb9b15bd98027c826b0c1df0a0a16ccd0138e76` | 12,636 |
| 4 | 20260802181524 | p2_c1_stage_b6_scope_detection_and_resolution | `8f750626c1f688efb9cc0d4a2ac80c5767b4707c1a910a25f8c48990f120012a` | 16,501 |
| 5 | 20260802181729 | p2_c1_stage_b6_fix_trade_aggregation_and_english_plurals | `4974901c57c353b74aec2cfb33a6a243adbabab8f60a8d812801d12832a98ce8` | 9,188 |
| 6 | 20260802181851 | p2_c1_stage_b6_dispatch_integration_and_tests | `fb60097f411ed91a010b6172837f4eb30b781094a96434385b224f9126f490bc` | 13,383 |
| 7 | 20260802181932 | p2_c1_stage_b6_fix_arabic_internal_definite_article | `41bff6141f4f177e700f761874a578800cf33bbff0957fd0bde28f33d6be4196` | 1,433 |
| 8 | 20260802182107 | p2_c1_stage_b6_fix_regex_aware_term_position | `7d7a5bb4be82b0e9e63ef21b4ee271749589874eb64d68fcf774fe869678d9e7` | 8,517 |
| 9 | 20260802182230 | p2_c1_stage_b6_blocker_rename_compat | `3b66e052956c42d6bf22c25f0be9bdf5bc557989b78976ea9e37c70300435b71` | 8,647 |
| 10 | 20260802182259 | p2_c1_stage_b6_holdout_runner | `cba0bb644ec36baae1269575c21b019e12594404bb8f73a0d536d23e7425435b` | 5,324 |
| 11 | 20260802182423 | p2_c1_stage_b6_fix_scope_adjacency_separator | `179c9b90ce342fcf6b752bfa486f9f6e930e0a7490635ef3299dc83202418a68` | 2,238 |
| 12 | 20260802182544 | p2_c1_stage_b6_operator_rollback | `57e61e516b9cb0a909e305dbdd49376b2240a91e8e6e4240dbbd4a468b65ae77` | 7,328 |

Total 99,762 characters. **Execution order is the version order above and must be preserved** —
migrations 5, 7, 8 and 11 are corrections that replace functions created by 4 and 6.

## Verification query

```sql
select version, name,
       encode(extensions.digest(array_to_string(statements, E';\n') || ';', 'sha256'),'hex') as sha256
  from supabase_migrations.schema_migrations
 where version between '20260802181006' and '20260802182544'
 order by version;
```

## Rollback

Stage B.6 has a single operator entry point, created by migration 12:

```sql
select public.fn_p2c1_rollback_stage_b6('rehearse','ops:you');  -- always safe: aborts
select public.fn_p2c1_rollback_stage_b6('commit','ops:you');    -- performs it
```

One transaction: drop the nine B.6 objects, restore the Stage B.5 matcher and dispatch report,
verify the object count reaches zero, re-run Stage A and Stage B and abort unless both are 14/14.

**Roll B.6 back BEFORE `fn_p2c1_rollback_stage_b`** — B.6 sits on top of the Stage B/B.5 objects.

Rehearsed 2 Aug 2026: `9 B.6 objects -> 0 | stage_a 14/14 | stage_b 14/14 | lang_parity 23/23 |
scope_tests 12/12`, then aborted.

## Why this is not yet recovered

Moving 99,762 characters of SQL out of the database and into files requires it to pass through the
assistant's context twice (read, then write). That did not fit in the session that produced it, and
a partially written migration set is worse than none.

The cheap fix is a credential the *device* can use to pull the SQL directly, writing the files with
no round trip:

- a Supabase **personal access token** (`~/.supabase/access-token`, or `SUPABASE_ACCESS_TOKEN`), or
- the **database password** for direct `psql`/Node access.

Neither is present on `operations-ag` today (checked: no access-token file, no `SUPABASE_*` env vars).
With either, recovery becomes a ~30-line script and a checksum comparison.
