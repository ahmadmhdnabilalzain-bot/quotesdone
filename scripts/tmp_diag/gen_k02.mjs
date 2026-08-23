// K02 — a nullable parent column demanded nothing, so an assignment was written with no inquiry.
import { writeFileSync } from 'node:fs';
import { liveBody, splice } from './splice.mjs';

const HEADER = `-- K02 — the parent a nullable column did not demand, and the assignment that had no inquiry
--
-- MEASURED 23 Aug 2026 on htdblwldjkcgjvmqkbeh. W12-S06 "Create idempotent supplier assignments"
-- was one of the three steps of the 257 producing no declared effect:
--
--   pd_object_write_produced_nothing :: the write to public.inquiry_matches for supplier_assignment
--   returned no key. Refusing to report a write that produced nothing.
--
-- THE HAND-OVER'S DIAGNOSIS WAS WRONG AND THE MEASUREMENT SAYS SO. It recorded the cause as "the
-- fixture inquiry is not rfq_ready". Driven inside one aborted transaction on 23 Aug 2026, with
-- for_workflow W12, the fixture inquiry scores 100, generic_ready true, category_required_ok true,
-- rfq_ready TRUE, status quote_ready; the supplier is not banned, not matching-blocked, not
-- permanently closed and has no expired licence; public.unsafe_block gained no row; and the same
-- insert issued by hand in the same transaction landed a row and returned its id.
--
-- WHAT ACTUALLY HAPPENED. public.phase_d_object_write builds its statement from the write map and
-- SKIPS any mapped column whose source key the payload does not carry. The map for
-- supplier_assignment is
--
--   {"inquiry_id":"inquiry_id","similarity":"similarity","supplier_id":"owner_ref","match_reason":"match_reason"}
--
-- and the payload carried owner_ref and nothing else, so the statement issued was
-- \`insert into public.inquiry_matches (supplier_id) values (...)\` -- an assignment with NO INQUIRY.
-- public.inquiry_matches carries BEFORE INSERT trigger gate_incomplete_match, which reads
-- \`select rfq_ready from public.inquiries where id = NEW.inquiry_id\`; NEW.inquiry_id was null, the
-- read found no row, ready came back null, and the trigger returned null. The gate was right to
-- refuse an orphan and the writer was right to refuse a write that produced nothing. The defect is
-- upstream of both: nothing supplied the parent.
--
-- WHY NOTHING SUPPLIED IT. public.fn_phase_d_fixture_effect_payload fills "the columns the target
-- relation actually DEMANDS" -- NOT NULL, no default, not generated -- plus any column the
-- committed catalogue speaks for. public.inquiry_matches.inquiry_id is NULLABLE, so it demands
-- nothing, so the parent was never in the population. A filter that can never select the thing that
-- matters.
--
-- THE FIX IS THE OBJECT'S OWN DECLARED PARENT, and it is derived, not listed.
-- public.phase_d_business_object_binding.parent_identity already names it for every object that has
-- one -- inquiry_id for supplier_assignment, transaction_id for invoice_receipt, quote_id for
-- payment_transaction. Where the write map maps a column of that name and the payload does not
-- carry its source key, fn_phase_d_effect_produce asks fn_phase_d_step_context for it. The context
-- resolves an identity from the row it names; a parent is never taken from a fixture constant,
-- because an identity is never a fixture. This runs in production exactly as it runs under a
-- fixture context: a parent is structural, not fixture content.
--
-- AND THE WRITER NOW REFUSES AN ORPHAN BY NAME. Where the declared parent is still unresolved the
-- write stops with pd_object_parent_missing instead of issuing a statement whose only possible
-- outcomes are a silent skip or a foreign-key error two layers down. Five objects have a mapped
-- parent identity on a nullable column -- department_mandate, inquiry, payment_transaction,
-- quotation, supplier_assignment -- and this is the guard for all five.
--
-- THE ELIGIBILITY EVIDENCE AND THE INCLUSION REASON are the remaining two mapped columns,
-- similarity and match_reason. A deterministic handler must not invent either, so they arrive the
-- way the founder's ruling of 21 Aug 2026 provides for: two rows of the committed fixture
-- catalogue, scoped to W12-S06, marked PHASE_D_FIXTURE_DO_NOT_PUBLISH, returning {} in production.
--
-- ROLLBACK: scripts/sql/down/phase_d_k02_the_parent_a_nullable_column_did_not_demand_down.sql
-- re-applies the previous bodies of fn_phase_d_effect_produce and fn_phase_d_object_write and
-- deletes the two catalogue rows.
--
-- GENERATED from the live bodies by scripts/tmp_diag/gen_k02.mjs.
`;

// ---- 1. fn_phase_d_effect_produce: fill the declared parent -----------------------------------
const produce = splice(await liveBody('fn_phase_d_effect_produce'), [
  [`  v_cap        jsonb;   -- F05: the accepted capability result for this step run, or null`,
   `  v_cap        jsonb;   -- F05: the accepted capability result for this step run, or null
  v_parent_col text;    -- K02: the parent identity the object's binding declares
  v_parent_src text;    -- K02: the payload key the write map reads it from
  v_parent_val jsonb;   -- K02: what the step context resolves for it`],
  [`  -- ---- the seven types -------------------------------------------------------------------`,
   `  -- ---- K02. THE PARENT THE OBJECT DECLARES -------------------------------------------------
  -- public.phase_d_object_write skips a mapped column whose source key the payload does not carry,
  -- and fn_phase_d_fixture_effect_payload only fills columns the RELATION demands. A parent column
  -- that is nullable demands nothing, so supplier_assignment was written with no inquiry_id and a
  -- BEFORE trigger dropped the row. The object's own binding already names its parent; that is read
  -- here, and the value comes from the step context, which resolves an identity from the row it
  -- names. Nothing is invented and no constant is used: an identity is never a fixture.
  select bb.parent_identity, wm.column_map->>bb.parent_identity
    into v_parent_col, v_parent_src
    from public.phase_d_business_object_binding bb
    join public.phase_d_object_write_map wm on wm.object_id = bb.object_id
   where bb.object_id = e.effect_object_id
     and coalesce(btrim(bb.parent_identity),'') <> ''
     and wm.column_map ? bb.parent_identity;
  if v_parent_src is not null
     and v_parent_src not in ('business_key','owner_ref','state')
     and (not (v_payload ? v_parent_src) or v_payload->v_parent_src = 'null'::jsonb) then
    v_parent_val := (public.fn_phase_d_step_context(v_step_run))->'context'->v_parent_src;
    if v_parent_val is not null and v_parent_val <> 'null'::jsonb then
      v_payload := v_payload || jsonb_build_object(v_parent_src, v_parent_val);
    end if;
  end if;

  -- ---- the seven types -------------------------------------------------------------------`],
]);

// ---- 2. fn_phase_d_object_write: refuse an orphan by name --------------------------------------
const write = splice(await liveBody('fn_phase_d_object_write'), [
  [`  -- D18: identity resolution for UPSERT_STATE.
  v_ident_val  text;`,
   `  -- K02: the parent the object declares.
  v_parent_src text;
  -- D18: identity resolution for UPSERT_STATE.
  v_ident_val  text;`],
  [`    for v_col in
      select k.key as col, wm.column_map->>k.key as src,`,
   `    -- K02. AN ORPHAN IS REFUSED BY NAME. Where the object's binding declares a parent identity,
    -- the write map maps a column of that name, and this call supplies no value for it, the row
    -- about to be written belongs to nothing. Issuing it can only end in a silent BEFORE-trigger
    -- skip -- which is exactly how W12-S06 lost its effect -- or a foreign-key error two layers
    -- down. A NOT NULL column is left to the relation's own 23502; this covers the nullable ones,
    -- which is where the hole was.
    select wm.column_map->>b.parent_identity into v_parent_src
      from pg_attribute a
     where a.attrelid = wm.target_relation::regclass
       and a.attname = b.parent_identity and a.attnum > 0 and not a.attnotnull
       and coalesce(btrim(b.parent_identity),'') <> ''
       and wm.column_map ? b.parent_identity;
    if v_parent_src is not null
       and v_parent_src not in ('business_key','owner_ref','state')
       and (not (v_supplied ? v_parent_src) or v_supplied->v_parent_src = 'null'::jsonb) then
      raise exception 'fn_phase_d_object_write: % declares parent identity %, the write map reads it from payload key %, and this call supplies none. A % row that belongs to no % is not a business record. (pd_object_parent_missing)',
        v_object, b.parent_identity, v_parent_src, wm.target_relation, b.parent_identity
        using errcode = '23502';
    end if;

    for v_col in
      select k.key as col, wm.column_map->>k.key as src,`],
]);

// ---- 3. the two catalogue rows -----------------------------------------------------------------
const CATALOGUE = `
-- The eligibility evidence and the inclusion reason W12-S06's effect must carry. Scoped to the
-- step, so nothing else in the estate can be filled by them. The checksum column is computed by
-- a10_phase_d_fixture_catalogue_checksum and is never supplied here.
insert into public.phase_d_fixture_catalogue
  (fixture_id, fixture_version, workflow_id, step_id, scope, field_key, value, value_kind,
   expected_schema, expected_result, prohibited_external_use, marker_exemption)
values
  ('PDF-5001', 1, 'W12', 'W12-S06', 'EFFECT_PAYLOAD', 'match_reason',
   to_jsonb('PHASE_D_FIXTURE_DO_NOT_PUBLISH — included by deterministic capability match on the routed trade; no supplier was contacted'::text),
   'text',
   'free text; public.inquiry_matches.match_reason is the inclusion reason BR-016 and GATE-015 read',
   'the supplier-assignment effect records WHY this supplier was included instead of leaving the column null',
   'Never send to a supplier. The assignment is created inside a transaction that is aborted.',
   null),
  ('PDF-5002', 1, 'W12', 'W12-S06', 'EFFECT_PAYLOAD', 'similarity',
   to_jsonb(0.90::numeric),
   'number',
   'numeric 0..1; public.inquiry_matches.similarity is the eligibility evidence the assignment carries',
   'the supplier-assignment effect records the match strength it was created on',
   'Never quote to a supplier or a customer as a real match score.',
   'similarity is numeric; a text marker cannot be stored in it and the value is scoped to one fixture step.')
on conflict (fixture_id) do update
  set fixture_version = excluded.fixture_version, workflow_id = excluded.workflow_id, step_id = excluded.step_id, scope = excluded.scope,
      field_key = excluded.field_key, value = excluded.value, value_kind = excluded.value_kind,
      expected_schema = excluded.expected_schema, expected_result = excluded.expected_result,
      prohibited_external_use = excluded.prohibited_external_use,
      marker_exemption = excluded.marker_exemption;
`;

writeFileSync(
  'scripts/sql/phase_d_k02_the_parent_a_nullable_column_did_not_demand.sql',
  HEADER + produce + ';\n\n' + write + ';\n' + CATALOGUE);
console.log('written');
