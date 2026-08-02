# Stage B.7 (Part 3 — interpretation gap corrections) — recovery manifest

**Status at the time this manifest is committed: APPLIED TO PRODUCTION, NOT YET RECOVERED INTO THIS
REPOSITORY.** Six migrations are applied to project `htdblwldjkcgjvmqkbeh` and recorded in
`supabase_migrations.schema_migrations`; the SQL is not yet in `supabase/migrations/`.

The manifest is committed *before* the recovery runs, so the recovered files can be verified against
a checksum that could not have been fitted to them. Each recovered file must hash to the SHA-256
below, computed over `array_to_string(statements, E';\n') || ';'` — the exact form the migration is
stored in.

| # | Version | Name | SHA-256 | chars |
|---|---|---|---|---|
| 1 | 20260802205000 | p2_c1_stage_b7_party_and_supply_semantics | `bc0d12d829932f3e4f41fc7c045952ee5fa85bcf0cc6c29c04ae27d48167f216` | 13,273 |
| 2 | 20260802205100 | p2_c1_stage_b7_scope_detect_semantic | `cb9ea8b87aed3d206ac5c673c825c5c8226beb0197510b7a786ab87364ba97bc` | 22,210 |
| 3 | 20260802205200 | p2_c1_stage_b7_arabic_scope_containers | `8b342509a1c951359cecb9059e7f70d60837360f6303bb4886db91b98ffa1878` | 4,864 |
| 4 | 20260802205300 | p2_c1_stage_b7_hvac_phrase_identification | `12aa50147a63e974b40d1dd8af2dcfded32f06d0ea432f7521160b2b1cce098b` | 3,138 |
| 5 | 20260802205400 | p2_c1_stage_b7_regression_suite | `11d635b881c999f52b61a28625c2f90b4830f36da1e14c2963de99a9374f44a1` | 13,075 |
| 6 | 20260802205500 | p2_c1_stage_b7_operator_rollback | `837cf29ad6a3f997edffa1ee1ff4c702e0dc5d3eb0db7d9c75daa8616ffc25fd` | 21,537 |

Total 78,097 characters. **Execution order is the version order above and must be preserved** —
migration 2 replaces `fn_scope_detect`, migration 3 replaces `fn_mep_full_scope`, and migration 6
restores both to their Stage B.6 bodies.

## What this stage changes

Part 3 of P2-C1: the four interpretation gaps holdout v1 exposed. No evidence weight was added or
changed, no holdout expectation was edited, no route was activated.

1. `excluded` vs `by_others` is composed from a removal marker plus the presence or absence of an
   identified responsible party, instead of two phrase lists.
2. Arabic gains a `scope_container` class (`حزمة`, `باقة`, `طقم`, `مجموعة`) that widens scope only
   beside an MEP anchor in the same clause. English `package` is reclassified into the same class.
3. Unambiguous multi-token HVAC phrases (`central AC`, `AC unit`, `split AC`) confirm; the bare
   abbreviation `ac` / `a/c` is a `trade_hint` that proposes and asks.
4. Supply attributed to a counterparty produces `client_supplied` on the supply component, leaving
   the trade active for installation, testing and commissioning.

## Verification query

```sql
select version, name,
       encode(extensions.digest(array_to_string(statements, E';\n') || ';', 'sha256'),'hex') as sha256
  from supabase_migrations.schema_migrations
 where version between '20260802205000' and '20260802205500'
 order by version;
```

## Rollback

```sql
select public.fn_p2c1_rollback_stage_b7('rehearse','ops:you');
select public.fn_p2c1_rollback_stage_b7('commit','ops:you');
```

Roll B.7 back **before** B.6. It restores the Stage B.6 bodies of `fn_scope_detect` and
`fn_mep_full_scope`, deletes the B.7 vocabulary, and aborts unless every prior suite returns to its
prior number — including holdout v1 at exactly **49/54, 0 false positives, 5 false negatives**,
which is its result of record. The evidence columns on the append-only
`inquiry_scope_disposition` table are deliberately retained and named in the rollback report.
