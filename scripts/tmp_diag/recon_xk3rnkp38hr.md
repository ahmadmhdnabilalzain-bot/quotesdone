Full live body dumped to `C:\Users\Opera\quotesdone\scripts\tmp_diag\rc_fixture_def_0.sql` (713 lines, 45,356 chars). Line numbers below are that file's.

---

# 1. SIGNATURE — exactly one overload

```
oid 947749 | public.fn_phase_d_fixture_scenario(p_input jsonb) RETURNS jsonb
LANGUAGE plpgsql | SET search_path TO 'public','pg_temp' | SECURITY INVOKER (no DEFINER clause)
grants: postgres EXECUTE, service_role EXECUTE (revoked from public/anon/authenticated)
```
Query used: `select p.oid, pg_get_function_identity_arguments(p.oid), pg_get_functiondef(p.oid) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_phase_d_fixture_scenario'` → **1 row**.

Input keys read (lines 8–24, 31–36):
| key | var | default |
|---|---|---|
| `label` | `v_label` | REQUIRED, errcode 22023 `pd_fixture_label_missing` |
| `execution_context` | `v_ctx` | must be `'test'`, else 23514 `pd_fixture_not_test_context` |
| `up_to_stage` | `v_upto` | 9999 |
| `created_by` | `v_actor` | `'phase_d_fixture_factory'` |
| **`for_workflow`** | **`v_for_wf`** | **NULL = withhold nothing** |

Preamble also requires `public.fn_phase_d_fixture_context()` to be non-null (hmac over txid, minted by `fn_phase_d_test_context_open`), and refuses `current_user in ('anon','authenticated')`.

---

# 2. THE WITHHOLD — it is `for_workflow`, and it is a THREE-condition skip

The word "withhold" appears **nowhere** in the body. The capability is `for_workflow`, and the manifest status string is `SKIPPED_PRODUCED_BY_THE_WORKFLOW_UNDER_TEST`.

Verbatim, lines 86–117 of `rc_fixture_def_0.sql`:

```plpgsql
  for st in select * from public.phase_d_fixture_stage where stage_no <= v_upto order by stage_no
  loop
    -- A SCENARIO MUST NOT PRE-CREATE THE OBJECT THE WORKFLOW UNDER TEST PRODUCES. W09 writes
    -- supplier_capability, W14 writes quotation, W16 writes payment_transaction; building those
    -- first made the workflow collide with its own output on a unique constraint, and a harness
    -- that seeds the row the step is supposed to create is answering its own question. The set is
    -- read from phase_d_step_effect for that workflow, never listed by hand.
    -- D22. THE EXCLUSION SKIPS LEAVES ONLY, SO A CASCADE IS IMPOSSIBLE BY CONSTRUCTION.
    --
    -- Measured with the old rule: for_workflow on W09 skipped 3 stages and the requires_stages
    -- cascade then blocked 13 MORE, because supplier_account is a parent of half the lineage. The
    -- D9 closure recorded the same shape as closure falling 14 -> 3, which is why the exclusion was
    -- left available and unused. Removing a parent to avoid a collision costs more than it saves.
    --
    -- A stage no other stage requires cannot cascade. supplier_assignment and provider_event are
    -- both leaves, and they are exactly the two collisions left: W12 writes supplier_assignment and
    -- GATE-015 correctly refused the fixture's as a duplicate dispatch. The skip is still recorded
    -- in the manifest as SKIPPED_PRODUCED_BY_THE_WORKFLOW_UNDER_TEST, never silently.
    if v_for_wf is not null
       and not exists (select 1 from public.phase_d_fixture_stage t
                        where st.stage_key = any(t.requires_stages))
       and exists (
         select 1 from public.phase_d_step_effect x
          where x.workflow_id = v_for_wf and x.effect_object_id = st.object_id) then
      v_man := v_man || jsonb_build_array(jsonb_build_object(
        'stage_no', st.stage_no, 'stage_key', st.stage_key, 'object_id', st.object_id,
        'status', 'SKIPPED_PRODUCED_BY_THE_WORKFLOW_UNDER_TEST', 'detail', v_for_wf));
      v_owned := v_owned + 1;
      continue;
    end if;
```

**A stage is withheld iff all three hold:**
1. `for_workflow` was passed non-blank;
2. **the stage is a LEAF** — `not exists (select 1 from phase_d_fixture_stage t where st.stage_key = any(t.requires_stages))`. This is the D22 narrowing and it is the reason a full 30-workflow withhold cannot remove parents;
3. `phase_d_step_effect` has a row `(workflow_id = for_workflow, effect_object_id = st.object_id)`.

Counted into `v_owned`, returned as `stages_left_to_the_workflow_under_test` (line 682), alongside `'for_workflow', v_for_wf`.

**Consequence of the leaf condition (measured):** 8 stages are produced by a workflow but are NOT leaves, so `for_workflow` can never withhold them regardless of which workflow is named:

| stage_no | stage_key | object_id | produced by | required_by |
|---|---|---|---|---|
| 5 | company_objective | company_objective | W01 | department_mandate |
| 10 | customer_account | customer_account | **W04** | customer_case, customer_terms_acceptance, inquiry, invoice_receipt, payment_transaction, quotation_comparison, refund_dispute_case |
| 30 | inquiry | inquiry | **W05** | 10 stages |
| 70 | inquiry_document | inquiry_document | W07 | document_extraction, supplier_safe_package |
| 100 | supplier_account | supplier_account | **W09** | 9 stages |
| 150 | quotation | quotation | **W14** | payment_transaction, quotation_comparison, quotation_evaluation, quotation_revision |
| 170 | quotation_comparison | quotation_comparison | W15 | customer_selection |
| 190 | payment_transaction | payment_transaction | **W16** | invoice_receipt, provider_event, reconciliation_case, refund_dispute_case, reveal_transaction |

Leaf stages that a workflow DOES produce (i.e. the ones `for_workflow` can actually withhold) — 30 of the 52 stages; the W09 ones are `supplier_terms_acceptance` (110) and `supplier_capability` (120); W12's are `supplier_assignment` (140) and `dispatch_batch` (355).

Other skip statuses in the same loop, for contrast:
- `SKIPPED_PARENT_NOT_CREATED` (lines 118–127) — cascade from `requires_stages`, counted into `v_blocked`.
- `BLOCKED_NO_REFERENCE_DATA` (lines 129–141) — `reference_relation` holds 0 rows.
- `REFUSED` / `SETTLE_REFUSED` — exception handler, lines 599–612 and 512–518.

Return shape (lines 674–712): `ok, label, fixture_run_id, evidence_manifest, stages_created, stages_not_created, stages_left_to_the_workflow_under_test, for_workflow, stages_declared, parent_refs, parent_ref_keys, manifest, notifications_written_by_this_scenario, deliverable_notifications_written_by_this_scenario, kernel_trigger_rows_written_by_this_scenario, outbound_http_requests_written_by_this_scenario, external_effects, paid_calls, note`.

`parent_refs` is populated ONLY for stages with a non-null `contributes_ref` (lines 578–590) — **a withheld stage contributes nothing to `parent_refs`**, and a stage with `contributes_ref IS NULL` contributes nothing even when created. `supplier_terms_acceptance.contributes_ref IS NULL` (see §4), which is exactly why nothing survives to satisfy BR-025.

---

# 3. CALLERS, and the "W12 and no other workflow" hard-code

`grep -rn "fn_phase_d_fixture_scenario" scripts/ supabase/ docs/` — active (non-migration) callers, all in `C:\Users\Opera\quotesdone\`:

**Callers that pass the withhold, hard-coded to W12 — this is the exact spot, 9 lines in 7 files:**

| file:line | literal |
|---|---|
| `scripts/phase_d/build_workflow_implementation_result.mjs:76` | `'for_workflow', case when wf.workflow_id = 'W12' then wf.workflow_id else null end));` |
| `scripts/phase_d/build_step_branch_coverage.mjs:68` | `'for_workflow', case when '${wf}' = 'W12' then '${wf}' else null end));` |
| `scripts/phase_d/build_four_mode_result.mjs:61` | `'for_workflow', case when '${wf}' = 'W12' then '${wf}' else null end));` |
| `scripts/phase_d/build_four_mode_result.mjs:293` | `'for_workflow', case when '__WF__' = 'W12' then '__WF__' else null end));` |
| `scripts/phase_d/build_transaction_local_evidence.mjs:55` | `'for_workflow', case when '__WF__' = 'W12' then '__WF__' else null end));` |
| `scripts/phase_d/observe_events_live.mjs:61` | `'for_workflow', case when '${wf}' = 'W12' then '${wf}' else null end));` |
| `scripts/phase_d/run_step_cases_live.mjs:83` | `'for_workflow', case when '${wf}' = 'W12' then '${wf}' else null end));` |
| `scripts/phase_d/run_step_cases_live.mjs:286` | `'for_workflow', case when '${wf}' = 'W12' then '${wf}' else null end));` |
| `scripts/checks/phase_d_the_three_steps_that_had_no_effect.test.mjs:63` | `'for_workflow', case when '${wf}' = 'W12' then '${wf}' else null end));` |
| `scripts/checks/phase_d_the_three_steps_that_had_no_effect.test.mjs:286` | `'for_workflow','W12'` (unconditional; label `chk-gates`) |

**The canonical statement of the policy is `scripts/phase_d/build_workflow_implementation_result.mjs:72-76`, verbatim:**

```js
      -- THE EXCLUSION IS USED WHERE A WORKFLOW COLLIDES WITH A SEEDED LEAF, NOT EVERYWHERE.
      -- Measured: applying it to W16 as well dropped W16 from 4/9 to 1/9, and the D9 measurement of
      -- the un-narrowed version was closure 14 -> 3. W12 dispatches to the supplier_assignment the
      -- factory seeds, so W12 is where it is used, and the row records it.
      'for_workflow', case when wf.workflow_id = 'W12' then wf.workflow_id else null end));
```

To make every workflow withhold its own output, that expression becomes `'for_workflow', wf.workflow_id` (or `'${wf}'`) in all 9–10 places above.

**Callers that pass NO withhold (`for_workflow` absent → nothing skipped):**
- `scripts/checks/kernel_positive_controls.test.mjs:158` — `'up_to_stage', 30` only
- `scripts/checks/phase_d_the_three_steps_that_had_no_effect.test.mjs:388` — label `chk-w16-neg`
- `scripts/phase_d/prove_object_reference_round_trip.mjs:38, 78, 79, 142`

**Migration/SQL files that CREATE OR REPLACE the function** (superseded chain; the live body is the last applied): `scripts/sql/phase_d_d9c_...:128`, `d9d:60`, `d9e:51`, `d9f:111`, `d9g:406`, `d9i:448`, `d17:488`, `d22:674`, `f08:27`, `f10`, `f13`, `f15`, `f41`, `f42`, `f45`, `f46`, `f48`, `g10`, … plus `supabase/schema/full_schema.sql`. `for_workflow` was introduced in `scripts/sql/phase_d_d9i_a_harness_that_seeds_the_row_the_step_creates.sql:19`; narrowed to leaves-only in `scripts/sql/phase_d_d22_a_company_scoped_owner_is_still_a_foreign_key.sql:35,734`. `scripts/sql/phase_d_d22_...:1058` holds the control that asserts the W09 cascade is gone.

Doc that states the boundary: `docs/phase-d/PHASE_D_HANDOVER_2026-08-23_R2.md:99-107`.

---

# 4. `public.phase_d_fixture_stage` — schema + terms-acceptance rows

```
stage_no                 integer                  NOT NULL
stage_key                text                     NOT NULL
object_id                text                     NOT NULL
requires_stages          text[]                   NOT NULL  DEFAULT '{}'::text[]
contributes_ref          text                     NULL
reference_relation       text                     NULL
note                     text                     NOT NULL
working_state            text                     NOT NULL
working_state_evidence   text                     NOT NULL
contributes_kind         text                     NOT NULL  DEFAULT 'RESULT_KEY'::text
working_payload          jsonb                    NOT NULL  DEFAULT '{}'::jsonb
working_payload_evidence text                     NULL
```
52 rows. **No row has `stage_key='notification'`** (count = 0) even though the function's elsif chain has a `'notification'` branch at line 212 — that is the 55/56 notification-stage decision recorded in memory.

**The two terms-acceptance rows, in full:**

```
stage_no  20
stage_key                customer_terms_acceptance
object_id                customer_terms_acceptance
requires_stages          {customer_account}
contributes_ref          acceptance_ref              <-- NON-NULL
reference_relation       null
working_state            accepted
working_state_evidence   PHASE_D_DECLARATION: an acceptance record exists only once accepted;
                         BR-001 reads terms_version and terms_hash, not a pending state
LEAF: yes  |  produced_by_workflows (phase_d_step_effect): NULL — no workflow declares it
```

```
stage_no  110
stage_key                supplier_terms_acceptance
object_id                supplier_terms_acceptance
requires_stages          {supplier_account}
contributes_ref          NULL                        <-- THE GAP
contributes_kind         RESULT_KEY (default)
reference_relation       null
working_state            accepted
working_state_evidence   PHASE_D_DECLARATION: as customer_terms_acceptance
LEAF: yes  |  produced_by_workflows: W09  (phase_d_step_effect W09-S06)
```

So with `for_workflow='W09'`, stage 110 IS withheld (leaf + W09 produces it), and because `contributes_ref IS NULL` the loop at lines 578–590 never adds anything to `parent_refs` for it even when it IS built. Nothing downstream can name the supplier acceptance.

The stage's payload branch, verbatim (lines 258–262):
```plpgsql
    elsif st.stage_key = 'supplier_terms_acceptance' then
      v_owner := v_refs->>'supplier_id';
      v_pay := v_pay || jsonb_build_object('terms_version', v_sup_ver,
        'terms_hash',  v_sup_hash,
        'supplier_id', v_refs->>'supplier_id');
```
`v_sup_ver`/`v_sup_hash` come from lines 72–74:
```plpgsql
  select d.version, encode(sha256(convert_to(coalesce(d.body_html,''),'UTF8')),'hex')
    into v_sup_ver, v_sup_hash
    from public.legal_documents d where d.slug = 'supplier-agreement' order by d.version desc limit 1;
```
(customer half is `slug='customer-terms'` into `v_terms_ver`/`v_terms_hash`, lines 69–71; used at the `customer_terms_acceptance` branch, line 180.)

`phase_d_step_effect` row for the acceptance:
```
step_id W09-S06 | workflow_id W09 | step_type execution | DOMAIN_MUTATION
effect_object_id  supplier_terms_acceptance
object_resolution MATCHED_STEP_TEXT
effect_relation   public.v_obj_supplier_terms_acceptance
effect_service    public.fn_phase_d_effect_produce(jsonb)
effect_operation  OBJECT_STATE_WRITE
actual_caller     NOT_YET_REACHED - no path has opened this step
implementation_depth BUSINESS_EFFECT_CONNECTED
```
It is the ONLY row in `phase_d_step_effect` whose `effect_object_id` contains "terms". W09's other effect objects: S01/S02/S04/S07 → `supplier_account`; S03/S05 → `supplier_capability`; S06 → `supplier_terms_acceptance`; S08/S09 → NULL.

---

# 5. `public.phase_d_context_key_object` — schema + ALL 15 rows

```
context_key  text                     NOT NULL
object_id    text                     NOT NULL
why          text                     NOT NULL
recorded_at  timestamptz              NOT NULL DEFAULT now()
```

| context_key | object_id | why |
|---|---|---|
| acceptance_ref | customer_terms_acceptance | BR-026 refuses a certificate before an acceptance and resolves this against the terms-acceptance record |
| approved_revision_ref | quotation_revision | BR-035 compares the approved revision with the published one; both are IMMUTABLE_REVISION records |
| artifact_ref | ux_specification | BR-036 requires the reviewer to have reviewed the artifact itself; the artifact is the revision record |
| caller_customer_id | customer_account | BR-019 decides visibility from who is asking, which is a customer account |
| comparison_id | quotation_comparison | BR-019 resolves the comparison whose visibility it is judging |
| document_id | inquiry_document | GATE-012 and the extraction steps judge the document revision this key names; public.documents is its canonical relation |
| inquiry_id | inquiry | BR-013 refuses a quote against an inquiry that is not quote-ready, reading public.inquiries |
| provider_event_id | provider_event | BR-032 refuses a replayed provider event, reading the recorded event |
| publishing_revision_ref | quotation_revision | BR-035, the other half of the same comparison |
| quote_id | quotation | BR-015 and BR-018 judge the supplier quotation this key names; public.quotes is its canonical relation |
| quote_revision_ref | quotation_revision | BR-018 asks whether the supplier quote is still supplier-authored, against the revision record |
| refund_id | refund_dispute_case | GATE-020 and BR-032 judge the refund case this key names; public.refunds is its canonical relation |
| safe_package_ref | supplier_safe_package | BR-012 requires an approved supplier-safe package record |
| supplier_id | supplier_account | BR-015 requires an approved, verified supplier, reading public.leads |
| transaction_id | payment_transaction | BR-020 refuses a reveal before payment, reading public.transactions |

12 rows at `2026-08-22 20:41:48.519959+00`, 3 (`document_id`, `quote_id`, `refund_id`) at `2026-08-22 22:33:29.885808+00`.

**No row maps `terms_version` or `terms_hash` to any object**, and the only acceptance entry is `acceptance_ref → customer_terms_acceptance`. That is the register gap the handover names: BR-025's subject (the *supplier* acceptance for W09) is unresolvable from either register — `phase_d_fixture_stage.contributes_ref IS NULL` for stage 110, and `phase_d_context_key_object` has no supplier-side acceptance key.

---

# What I did NOT measure
- I did not run `fn_phase_d_fixture_scenario` (any run writes rows, even inside an aborted transaction — read-only mandate). All statements about skip counts under a full withhold are quoted from `docs/phase-d/PHASE_D_HANDOVER_2026-08-23_R2.md:99-107`, not re-measured.
- `phase_d_object_write_map`, `phase_d_object_state_contract`, `phase_d_fixture_catalogue`, `fn_phase_d_object_write` bodies — not dumped, out of scope; say the word and I will.

Diag scripts left at `C:\Users\Opera\quotesdone\scripts\tmp_diag\rc_fixture_scenario.mjs`, `rc_tables.mjs`, `rc_effect.mjs`, `rc_more.mjs`; full body at `C:\Users\Opera\quotesdone\scripts\tmp_diag\rc_fixture_def_0.sql`. Nothing committed.