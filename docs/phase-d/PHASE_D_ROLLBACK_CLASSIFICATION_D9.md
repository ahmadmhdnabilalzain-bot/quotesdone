# Phase D — D9 rollback classification

Required by §0 of the D9 brief, and an extension of `PHASE_D_PRODUCTION_DEPLOYMENT_LEDGER.md` rather
than a replacement for it.

**A previous function body is not an adequate rollback for a new table, column, constraint, trigger,
index, grant, RLS policy, enum or registry row.** So every additive DDL operation below is listed
with its own reversal and with the data consequence of taking it.

## Classification of the eleven D9 files

| file | routines | additive DDL | rollback class |
|---|---|---|---|
| `phase_d_d9_one_hundred_and_fifty_nine_contracts_not_one.sql` | 5 | 2 tables, 10 constraints, 1 index, RLS on both | **EXPLICIT_DOWN_REQUIRED** |
| `phase_d_d9b_a_run_in_waiting_handoff_is_not_a_stopped_run.sql` | 1 | none | ROUTINE_RESTORE |
| `phase_d_d9c_a_scenario_built_in_the_order_reality_builds_it.sql` | 3 | 1 table, 3 constraints, RLS; 1 registry-row UPDATE | **EXPLICIT_DOWN_REQUIRED** |
| `phase_d_d9d_a_canonical_write_that_emails_a_supplier.sql` | 3 | 1 registry-row UPDATE | ADDITIVE_SURVIVAL_SAFE |
| `phase_d_d9e_the_lineage_is_quiet_only_because_it_has_no_address.sql` | 2 | none | ROUTINE_RESTORE |
| `phase_d_d9f_the_writer_covers_two_of_the_six_fields_its_scorer_reads.sql` | 2 | 2 registry-row UPDATEs | ADDITIVE_SURVIVAL_SAFE |
| `phase_d_d9g_a_generated_fixture_beat_the_real_reference.sql` | 2 | none | ROUTINE_RESTORE |
| `phase_d_d9h_the_owner_of_a_customer_scoped_object_is_a_customer.sql` | 1 | none | ROUTINE_RESTORE |
| `phase_d_d9i_a_harness_that_seeds_the_row_the_step_creates.sql` | 2 | none | ROUTINE_RESTORE |
| `phase_d_d9j_a_run_that_cannot_see_what_it_just_created.sql` | 1 | none | ROUTINE_RESTORE |
| `phase_d_d9k_the_kernel_has_no_rejection_door.sql` | 4 | none | ROUTINE_RESTORE |

**IRREVERSIBLE_WITH_FOUNDER_APPROVAL: 0.** Nothing in D9 destroys data, drops a column, narrows a
type, or removes a row that cannot be recreated from the frozen registries.

---

## Every additive DDL operation, with its own reversal

### 1. `public.phase_d_handoff_contract` — created

| | |
|---|---|
| reason | one acceptance contract per effective handoff. `fn_phase_c_handoff_packet_valid` checks a fixed five-key list for all 159 and never reads a handoff's own `required_packet`. |
| can data exist | yes — 159 rows, every column **derived** from `public.phase_b_handoff` |
| rollback SQL | `drop table public.phase_d_handoff_contract cascade;` |
| rollback data consequence | **none that is not reproducible.** Re-running the file regenerates all 159 rows, and `required_packet_sha256` is how that is proved rather than assumed. `cascade` is needed because `phase_d_handoff_acceptance.handoff_id` references it — drop the acceptance ledger first if its rows are to be kept. |
| survival-safe | **yes** — nothing outside Phase D reads it and no frozen object references it |

### 2. `public.phase_d_handoff_acceptance` — created

| | |
|---|---|
| reason | one decision per handoff run. `UNIQUE (handoff_run_id)` is the idempotency guarantee, as a constraint rather than a convention. |
| can data exist | yes — one row per accepted or rejected handoff run. **Zero rows survive this session**: every drive ran in an aborted transaction. |
| rollback SQL | `drop table public.phase_d_handoff_acceptance;` |
| rollback data consequence | **the audit trail of Phase D handoff decisions is lost, and it is not reconstructible.** `phase_c_handoff_run` records the kernel's status but not the packet digest, the SLA due time and breach flag, the rejection code, the missing item, or the accountability pair either side of acceptance. If any row exists at rollback time, export it first. |
| survival-safe | **yes** — no frozen object references it |

### 3. `public.phase_d_fixture_stage` — created

| | |
|---|---|
| reason | the scenario stages in foreign-key order, each naming the canonical object service that produces it and the reference it contributes |
| can data exist | yes — 24 declared rows, all of them in the file |
| rollback SQL | `drop table public.phase_d_fixture_stage cascade;` |
| rollback data consequence | none — re-running the file restores all 24 rows. Note the driver reads `contributes_ref` from this table, so dropping it makes `fn_phase_d_drive_workflow` unable to fold produced references back into the rule context. |
| survival-safe | **yes** |

### 4. Constraints created (13)

`phase_d_handoff_contract_pkey`, `phase_d_handoff_contract_handoff_id_fkey`,
`phase_d_handoff_contract_keys_ck`, `phase_d_handoff_contract_owner_ck`,
`phase_d_handoff_acceptance_pkey`, `phase_d_handoff_acceptance_handoff_id_fkey`,
`phase_d_handoff_acceptance_outcome_ck`, `phase_d_handoff_acceptance_reject_ck`,
`phase_d_handoff_acceptance_accept_ck`, `phase_d_handoff_acceptance_one_per_run`,
`phase_d_fixture_stage_pkey`, `phase_d_fixture_stage_stage_key_key`,
`phase_d_fixture_stage_object_id_fkey`.

Each is dropped with its own table, so **no rollback touches an object that existed before D9**. None
was added to a pre-existing table.

The two foreign keys are declared explicitly in the files, using the identity Postgres itself
generates, because the canonical routine engine can only derive an auto-generated constraint name
when `references` sits on the same source line as its column — a clause wrapped for readability
reads to it as uncommitted DDL. The instrument is not wrong, so the files were made explicit rather
than the check taught to accept a shape it cannot attribute.

### 5. Index created (1)

`phase_d_handoff_acceptance_run_idx` on `(run_id, outcome)`.
Rollback: `drop index if exists public.phase_d_handoff_acceptance_run_idx;` — dropped with the table
in any case. No data consequence.

### 6. RLS enabled (3 tables)

Reversal: `alter table <t> disable row level security;`

All three are revoked from `anon` and `authenticated` and granted only to `service_role`, so RLS here
is defence in depth and not the control. **No policy was added to any of the 536 RLS-on /
zero-policy tables**, deliberately: most internal workflow, kernel and agent tables should remain
server-only deny-all.

### 7. Registry-row UPDATEs to `public.phase_d_object_write_map` (3)

| object | change | rollback SQL | rollback data consequence |
|---|---|---|---|
| `supplier_account` | `+ verified` | `update public.phase_d_object_write_map set column_map = column_map - 'verified' where object_id = 'supplier_account';` | the object's own `approved` state becomes unreachable through its canonical writer again, because `public.leads` carries `CHECK (approval_status <> 'approved' OR verified = true)`. BR-015 becomes unsatisfiable by any canonical path — which is exactly the state D9 found. |
| `inquiry` | `+ rfq_ready` (D9d) then `- rfq_ready` (D9f) | net zero, nothing to reverse | none. `rfq_ready` is derived by `trg_rfq_complete` and was never writable; D9d's repair was wrong and D9f removed it. |
| `inquiry` | `+ emirate, scope_type, budget, trades` | `update public.phase_d_object_write_map set column_map = column_map - 'emirate' - 'scope_type' - 'budget' - 'trades' where object_id = 'inquiry';` | the canonical writer drops back to **45 of the 100 points** `fn_rfq_score` measures against a 70 bar. No Phase D path can then produce a quote-ready inquiry, `trg_gate_incomplete_match` silently drops any supplier assignment referencing it, and W12 with everything downstream of a dispatch becomes undrivable. |

**No column was removed from any target table. No enum was altered. No trigger was created, altered
or dropped. No RLS policy was created on a pre-existing table. No grant was widened.**

Every SECURITY DEFINER routine created here is revoked from PUBLIC in the same file and granted only
to `service_role` — `revoke … from anon` alone is a silent no-op when the grant is held through
PUBLIC.

---

## Required results

| required | result |
|---|---|
| deployed Phase D migrations with no rollback classification | **0** |
| additive changes requiring an explicit down but having none | **0** |
| production ahead of main | **false** — every routine here is committed on the branch and merges through the PR |

---

## One deployment defect found and corrected in this session

Re-applying `phase_d_d9c` to name a constraint explicitly **silently reverted**
`fn_phase_d_fixture_scenario` and `fn_phase_d_fixture_state` to that file's older bodies, discarding
four later increments.

`apply_sql.mjs` printed `read back and identical to the file` both times and was correct: the
read-back covers the file it was given, not the increments applied after it. Only
`canonical_routines.test.mjs` caught it, as `repository -> production drift: 2`. All eleven files
were re-applied in dependency order and drift returned to **0 in both directions**.

**The rule this leaves behind:** re-applying an earlier file in a chain is not idempotent with
respect to later files that replace the same routine. Re-apply the whole chain, in order, and let
the canonical routine engine — not the apply tool — be the judge.
