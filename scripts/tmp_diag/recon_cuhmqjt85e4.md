## 1. BR-025 in the frozen Phase B register

`public.phase_b_business_rule` (5 columns, all verbatim):

| rule_id | rule_name | rule_text | workflow_scope | rule_type |
|---|---|---|---|---|
| `BR-025` | `Exact terms acceptance` | `Terms acceptance must reference the exact displayed version and hash and remain append-only.` | `W04;W09` | `hard` |

Query: `select * from public.phase_b_business_rule where rule_id='BR-025'`

## 2. How BR-025 is enforced, and where its subject is resolved

`public.phase_d_rule_enforcement` row (verbatim):

```
rule_id           BR-025
rule_type         hard
enforcement_kind  PREDICATE
enforcement_point public.fn_phase_d_rule_check(text,jsonb)
refusal_code      br025_terms_version_mismatch
applies_when      workflow scope W04;W09
required_context  {terms_version,terms_hash}
status            ENFORCED
evidence          Predicate reads the relation D2 bound for the object this rule governs; absent evidence refuses rather than passing.
recorded_at       2026-08-18 15:57:20.732504+00
```

**The predicate** (`fn_phase_d_rule_check`, the `BR-025` block) does *not* need a subject register — it resolves against `public.legal_documents` directly:

```sql
    v_txt  := btrim(coalesce(p_context->>'terms_version',''));
    v_txt2 := lower(btrim(coalesce(p_context->>'terms_hash','')));
    if v_txt = '' or v_txt2 = '' then ... ENFORCED_FAIL ... end if;
    if v_txt2 !~ '^[0-9a-f]{64}$' then ... ENFORCED_FAIL ... end if;
    select count(*) into v_n from public.legal_documents d
     where d.version = v_txt
       and encode(sha256(convert_to(coalesce(d.body_html,''), 'UTF8')), 'hex') = v_txt2;
    v_ok := (v_n >= 1);
```

**The subject IS resolved — but only in `fn_phase_d_rule_applies`, section 3 (the K06 exemption), and it reads `phase_d_fixture_stage`, not `phase_d_context_key_object`:**

```sql
  -- 3. A RULE DOES NOT GOVERN THE WORKFLOW THAT PRODUCES ITS SUBJECT.
  if e.required_context is not null and cardinality(e.required_context) > 0 then
    select st.object_id into v_governs
      from public.phase_d_fixture_stage st
     where st.contributes_ref = any(e.required_context)
     limit 1;
    if v_governs is not null then
      select w.primary_object into v_primary
        from public.phase_b_workflow w where w.workflow_id = s.workflow_id;
      select min(x.step_id) into v_producer
        from public.phase_d_step_effect x
       where x.workflow_id = s.workflow_id and x.effect_object_id = v_governs;
      if (v_primary is not null and v_primary = v_governs) or v_producer is not null then
        applies := false; ...
```

For BR-025 `v_governs` is **NULL**: no `phase_d_fixture_stage` row has `contributes_ref` in `{terms_version, terms_hash}`. Measured — BR-025 is the only rule in the whole enforcement register with a non-empty `required_context` whose subject resolves to nothing in *both* registers while a scoped workflow produces it.

## 3. The nine W09 steps (frozen register)

`select step_id, step_no, step_name, accountable_role_id from public.phase_b_workflow_step where workflow_id='W09' order by step_no` — every step has `accountable_role_id = supplier_onboarding_specialist`, `actor_kind = canonical_role`.

| step | name | step_type | effect object (`phase_d_step_effect`) |
|---|---|---|---|
| W09-S01 | Open supplier onboarding case | intake | supplier_account |
| W09-S02 | Verify supplier contact channels | review | supplier_account |
| W09-S03 | Collect company profile | execution | supplier_capability |
| W09-S04 | Collect supplier documents | execution | supplier_account |
| W09-S05 | Map categories and capabilities | analysis | supplier_capability |
| **W09-S06** | **Capture canonical supplier terms acceptance** | execution | **supplier_terms_acceptance** |
| W09-S07 | Check onboarding completeness | review | supplier_account |
| W09-S08 | Submit independent verification case | handoff | (none) |
| W09-S09 | Close onboarding | closure | (none) |

W09-S06 `required_output` = `Immutable supplier acceptance record.`, `acceptance_criteria` = `Displayed version, recorded version and document hash match.`

**BR-025 is bound to all nine.** `phase_d_handler_binding.rule_ids` for every `W09-S01..S09` contains `BR-025` (and BR-026). And `fn_phase_d_rule_applies('BR-025', <step>)` returns `applies=true` for all 9 W09 steps *and* all 7 W04 steps, with `why = 'BR-025 (hard, PREDICATE) applies to W09-Sxx: in scope W04;W09'` — i.e. it falls straight through section 3 with no subject.

## 4. Fixture stages, bindings, write maps

`public.phase_d_fixture_stage` — only two terms rows exist:

| stage_no | stage_key | object_id | requires_stages | **contributes_ref** | contributes_kind | note |
|---|---|---|---|---|---|---|
| 20 | customer_terms_acceptance | customer_terms_acceptance | {customer_account} | **`acceptance_ref`** | OBJECT_KEY | "BR-025 needs the exact version AND hash; the store keeps the accepted pair." |
| 110 | supplier_terms_acceptance | supplier_terms_acceptance | {supplier_account} | **`NULL`** | RESULT_KEY | "W09 append-only acceptance record." |

`phase_d_business_object_binding`: both objects exist, `governing_workflow_id` = `W04` / `W09`, `record_policy=append_only`, `canonical_relation` = `public.v_obj_customer_terms_acceptance` / `public.v_obj_supplier_terms_acceptance` (`relation_kind=PHASE_D_OBJECT_VIEW`, backed by `public.phase_d_object_record`).

`phase_d_object_write_map`: **0 rows** for either object (they are written through `fn_phase_d_object_write`, not a mapped relation).

## 5. `phase_d_context_key_object` — and why W04's and W09's acceptances are different objects

`phase_d_context_key_object` holds **15 rows** and its primary key is `PRIMARY KEY (context_key)` — one object per key. `terms_version` and `terms_hash` are **absent**. The nearest row is:

```
acceptance_ref -> customer_terms_acceptance
  why: "BR-026 refuses a certificate before an acceptance and resolves this against the terms-acceptance record"
```

The two acceptances are genuinely different objects: different `object_id`, different `governing_workflow_id` (W04 vs W09), different `ownership_scope` (CUSTOMER vs SUPPLIER), different canonical view, different fixture stage, different parent (`customer_account` vs `supplier_account`), and different source document — the scenario factory reads `legal_documents.slug='customer-terms'` (**v3**, body sha `20a7b470…`) for one and `slug='supplier-agreement'` (**v5**, body sha `83045bcf…`) for the other, then writes that pair into each record's payload (`fn_phase_d_fixture_scenario`, the `customer_terms_acceptance` and `supplier_terms_acceptance` stage branches).

## 6. The exact mechanism of the 248/257 — measured

The withhold switch is `fn_phase_d_fixture_scenario(… 'for_workflow', <wf>)`. Committed line, `scripts/phase_d/build_step_branch_coverage.mjs:68`:

```js
'for_workflow', case when '${wf}' = 'W12' then '${wf}' else null end));
```

The skip rule inside the factory (leaves only):

```sql
    if v_for_wf is not null
       and not exists (select 1 from public.phase_d_fixture_stage t
                        where st.stage_key = any(t.requires_stages))
       and exists (select 1 from public.phase_d_step_effect x
          where x.workflow_id = v_for_wf and x.effect_object_id = st.object_id) then
      ... 'status','SKIPPED_PRODUCED_BY_THE_WORKFLOW_UNDER_TEST' ... continue;
```

Simulated against live data:

- **`for_workflow='W09'` skips stage 110 `supplier_terms_acceptance` (leaf) and stage 120 `supplier_capability` (leaf).** Stage 100 `supplier_account` is a parent, so it is kept.
- **`for_workflow='W04'` skips nothing at all.** The only W04-produced object is `customer_account` (all 7 W04 `phase_d_step_effect` rows resolve to it, including W04-S04 "Acceptance record linked to exact document version and identity" → `effect_object_id=customer_account`), and `customer_account` is a parent of stage 20. So W04's own acceptance record is never withheld.

That is the whole asymmetry.

Chain, verified end to end:

1. `fn_phase_d_dispatch_step` line ~102: `v_cx := public.fn_phase_d_step_context(v_step_run);` → passed to the handler as `'context', v_cx->'context'`.
2. `fn_phase_d_step_context`, `terms_version`/`terms_hash` branch, resolves **only** from a live acceptance record owned by the run's party:
```sql
        select o.payload ->> v_k into v_val_txt
          from public.phase_d_object_record o
         where o.superseded_by is null
           and o.payload ? 'terms_version' and o.payload ? 'terms_hash'
           and o.owner_ref in (v_row_id, v_run_key)
         order by (o.owner_ref = v_row_id) desc, o.record_id desc limit 1;
```
With stage 110 skipped there is no such record → unresolved → falls to the fixture-catalogue door, which answers PDF-3104/PDF-3105.
3. `fn_phase_d_handler_execute` calls `fn_phase_d_rule_check('BR-025', … || p_input->'context')` and, on a hard `ENFORCED_FAIL`, raises `pd_rule_refused` (errcode 23514) **before any effect is produced**.

Executed both arms of the predicate on production (read-only, `STABLE`):

```
context = catalogue PDF-3104/PDF-3105 →
  state ENFORCED_FAIL, ok false, evidence_absent false,
  reason "BR-025: acceptance names version phase-d-fixture-terms-v1 at digest 5d31c13d1f0f,
          which matches 0 row(s) in public.legal_documents whose displayed body hashes to
          exactly that digest"

context = supplier-agreement v5 / 83045bcfa2cc… →
  state ENFORCED_PASS, ok true,
  reason "…matches 1 row(s)…"
```

`evidence_absent=false`, so the refusal is `pd_rule_refused`, not `pd_evidence_absent`.

BR-026 does **not** also block: its subject resolves (`acceptance_ref` → `customer_terms_acceptance`), and its predicate accepts `object_id in ('customer_terms_acceptance','supplier_terms_acceptance')`, with stage 20 still built during a W09 strict run.

## 7. Verdict on §5 of `docs/phase-d/PHASE_D_HANDOVER_2026-08-23_R2.md`

**PARTLY CONFIRMED, ONE CLAIM CONTRADICTED.**

- CONFIRMED: "the nine that fall are all of W09, blocked by BR-025 needing a terms acceptance W09-S06 is itself the step that records" — exact. BR-025 is bound to all 9 steps, applies to all 9, and refuses at all 9 once stage 110 is withheld.
- CONFIRMED: "`phase_d_fixture_stage.contributes_ref` is null for `supplier_terms_acceptance`" — measured, stage_no 110, `contributes_ref IS NULL`.
- CONFIRMED: "W04 and W09 own different acceptances" — measured across seven columns and two source documents.
- **CONTRADICTED:** "`phase_d_context_key_object` cannot map `terms_version`/`terms_hash` to one object" is presented as *the* reason the subject is underivable. `phase_d_context_key_object` is **never read by `fn_phase_d_rule_applies`** — I read the complete body; it reads `phase_b_business_rule`, `phase_b_workflow_step`, `phase_d_rule_enforcement`, `phase_b_handoff`, **`phase_d_fixture_stage`**, `phase_b_workflow`, `phase_d_step_effect` and nothing else. Registering `terms_version` there would not make BR-025's subject derivable, and could not anyway: `PRIMARY KEY (context_key)` admits one object per key, and both doors that read it (`phase_d_effect_ledger.result_reference` and `phase_d_scenario_record.canonical_ref`) return a canonical *identity*, which is the wrong shape for a version string. The single register that actually decides BR-025's subject is `phase_d_fixture_stage.contributes_ref`, and the `= any(required_context)` + workflow-scoped `v_producer` lookup already expresses per-workflow subjecthood correctly — no second row is needed.
- NOT MEASURED: that BR-025 is the *only* blocker of the nine. Confirming that requires running the strict harness, which writes. What is measured is that BR-025 alone is sufficient to refuse all nine, and that BR-026 is not a second blocker.

## 8. The minimal change

**One UPDATE, two columns, one row. No DDL, no routine edit, no new register.**

```sql
UPDATE public.phase_d_fixture_stage
   SET contributes_ref  = 'terms_version',
       contributes_kind = 'PAYLOAD_VALUE'
 WHERE stage_no = 110
   AND stage_key = 'supplier_terms_acceptance'
   AND contributes_ref IS NULL;
```

- table: `public.phase_d_fixture_stage`; row: `stage_no = 110`; columns: `contributes_ref`, `contributes_kind`.
- `PAYLOAD_VALUE` is already admitted by the live CHECK (`RESULT_KEY, STATE, PAYLOAD_VALUE, OBJECT_KEY`) and is the established precedent for exactly this shape — stage 245 `artifact_revision` → `ux_specification`, `contributes_ref='artifact_sha256'`, `contributes_kind='PAYLOAD_VALUE'`, introduced by `scripts/sql/phase_d_f40_a_stage_that_contributed_nothing_still_answered_with_its_row_id.sql:45-50`. The factory's `PAYLOAD_VALUE` branch reads `o.payload #>> array[st.contributes_ref]`, and the stage already writes `terms_version` into that payload (`fn_phase_d_fixture_scenario`, `elsif st.stage_key = 'supplier_terms_acceptance'`). `RESULT_KEY` would put a uuid under the name `terms_version` — wrong; the kind must change with the ref.

What it does: `fn_phase_d_rule_applies` section 3 resolves `v_governs = 'supplier_terms_acceptance'`, `v_producer = 'W09-S06'` from `phase_d_step_effect`, and returns `applies=false` for all nine W09 steps with `why = 'BR-025 governs supplier_terms_acceptance and W09 is the workflow that produces it (first produced at W09-S06); the rule guards its use downstream, not its creation'`. This is byte-for-byte the K06 shape already accepted for BR-018/W14 and BR-032/W16.

Verified it does not disturb W04: `v_governs` becomes `supplier_terms_acceptance`, W04's `primary_object` is `customer_account`, and no W04 step's `effect_object_id` is `supplier_terms_acceptance` → `v_producer` NULL → BR-025 still applies to all 7 W04 steps, still fed by stage 20 (never withheld), still passing on `customer-terms v3 / 20a7b470…`. And no other stage carries `terms_version` or `terms_hash`, so the `limit 1` without ORDER BY stays deterministic.

Also checked for the "row added without its artefact" trap: `phase_d_fixture_stage` is guarded by no committed CSV and no `scripts/checks/*.test.mjs` comparison (the only check touching it, `phase_d_the_three_steps_that_had_no_effect.test.mjs:67`, reads `contributes_ref` for the *primary object* stage — `supplier_account`, stage 100 — and is unaffected). `PHASE_D_FIXTURE_CATALOGUE.csv` covers `phase_d_fixture_catalogue`, a different table.

**Known consequence, stated rather than hidden:** the K06 exemption is workflow-wide, not step-ordered, so BR-025 would also stop governing W09-S07/S08/S09, which run *after* the acceptance exists. That is the same trade-off K06 already made twice. A step-ordered exemption (`v_producer` compared against `s.step_no`) would be the tighter fix and is a change to `fn_phase_d_rule_applies`, not to a register.

**The reachability alternative is not recommended:** making stage 110 a non-leaf (so the skip predicate spares it) would re-seed the very row W09-S06 exists to create — the defect the strict harness was written to expose.

Files: `C:\Users\Opera\quotesdone\scripts\tmp_diag\w09_fn_bodies.txt` (full `fn_phase_d_rule_check` + `fn_phase_d_rule_applies`), `w09_ctx_bodies.txt` (`fn_phase_d_step_context`), `w09_scenario.txt` (`fn_phase_d_fixture_scenario`), `w09_handler.txt` (`fn_phase_d_dispatch_step` + `fn_phase_d_handler_execute`), and the recon scripts `w09_recon2..12.mjs`. No writes, no git, no paid provider calls.