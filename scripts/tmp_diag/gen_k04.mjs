// K04 — the invoice was keyed on its number and the relation is keyed on its transaction.
import { writeFileSync } from 'node:fs';
import { liveBody, splice } from './splice.mjs';

const HEADER = `-- K04 — the invoice was keyed on its number, and the relation is keyed on its transaction
--
-- MEASURED 23 Aug 2026 on htdblwldjkcgjvmqkbeh. W16-S05 was the third of the three steps of the 257
-- producing no declared effect:
--
--   pd_effect_identity_collision :: duplicate key value violates unique constraint
--   "reveal_invoices_pkey"
--
-- ONE WRONG FACT, THREE PLACES IT REACHED. public.reveal_invoices is
--
--   PRIMARY KEY (transaction_id)          -- transaction_id uuid NOT NULL
--   FOREIGN KEY (transaction_id) REFERENCES transactions(id) ON DELETE CASCADE
--   invoice_no text NULL
--
-- and public.phase_d_business_object_binding recorded primary_identity = 'invoice_no' for
-- invoice_receipt. Every bound object was checked against its relation's own primary key on
-- 23 Aug 2026 and this is the ONLY one that disagreed: 1 of 26 EXISTING_TABLE bindings.
--
-- From that one fact:
--   * phase_d_object_reference_strategy.physical_pk_column, business_key_derivation and
--     evidence_lookup are DERIVED from binding.primary_identity (F43), so all three named invoice_no;
--   * phase_d_object_write_map.key_column named invoice_no, so the writer returned the invoice
--     NUMBER as the object's reference and never looked for the row the relation would collide on;
--   * operation is INSERT, so no identity probe ran at all, and the scenario's own invoice_receipt
--     stage (395) had already issued one invoice for that transaction. The second insert hit the
--     primary key.
--
-- THE CORRECTION. The canonical identity of a reveal invoice is its transaction: one invoice per
-- transaction, which is exactly what the relation's primary key says and what the frozen binding's
-- own status_model says -- "issued once per transaction". invoice_no stays, mapped from the
-- business key, an immutable business attribute of the record and not its physical identity. The
-- reference strategy is then RE-DERIVED by F43's own statement rather than edited by hand.
--
-- AND A REPLAY NO LONGER COLLIDES. The two-pass identity probe D18 built for UPSERT_STATE now runs
-- for INSERT as well. An INSERT that would violate a unique index on values THIS CALL SUPPLIES is
-- not a new record; it is the record that already exists. For an INSERT the existing reference is
-- returned with unchanged = true and NOTHING IS UPDATED -- an immutable_revision object is never
-- rewritten by a replay, which is the distinction the UPSERT branch would have lost. Where no
-- unique index resolves an identity the write is still an INSERT and a unique violation is still a
-- real business duplicate.
--
-- NOTHING IS WEAKENED. BR-020 (reveal before payment) and BR-033 (unknown money as success) are
-- enforced by public.fn_phase_d_rule_check against the six-rung ladder in
-- public.phase_d_payment_state and are untouched by this file. The foreign key to
-- public.transactions still refuses an unknown transaction.
--
-- AND IT CANNOT RECUR SILENTLY. scripts/checks/phase_d_object_record_has_a_contract.test.mjs gains
-- an assertion that a binding whose canonical relation has a single-column PRIMARY KEY names that
-- column as its primary_identity.
--
-- ROLLBACK: scripts/sql/down/phase_d_k04_the_invoice_was_keyed_on_its_number_down.sql restores
-- primary_identity = invoice_no, the write map's key_column, the derived strategy row, and the
-- previous body of fn_phase_d_object_write.
--
-- GENERATED from the live body by scripts/tmp_diag/gen_k04.mjs.

-- ---- 1. the fact ------------------------------------------------------------------------------
UPDATE public.phase_d_business_object_binding
   SET primary_identity = 'transaction_id',
       evidence = 'public.reveal_invoices is PRIMARY KEY (transaction_id) with a foreign key into '
               || 'public.transactions; invoice_no is the immutable business number carried on the '
               || 'record, not its identity. immutable_revision: a correction is a credit note or a '
               || 'new document.'
 WHERE object_id = 'invoice_receipt';

-- ---- 2. the write map -------------------------------------------------------------------------
-- key_column becomes the relation's own primary key. column_map is unchanged: invoice_no is still
-- written, from the business key, and is still unique-indexable as a business attribute.
UPDATE public.phase_d_object_write_map
   SET key_column = 'transaction_id'
 WHERE object_id = 'invoice_receipt';

-- ---- 3. the derived reference strategy, re-derived by F43's own statement ----------------------
INSERT INTO public.phase_d_object_reference_strategy
  (object_id, storage_kind, canonical_identity_type, physical_schema, physical_relation,
   physical_pk_column, business_key_derivation, version_rule, ownership_rule, reader, writer,
   evidence_lookup, fixture_creation_service, trace_relationship)
SELECT
  b.object_id,
  case when b.relation_kind = 'PHASE_D_OBJECT_VIEW'          then 'PHASE_D_STORE'
       when b.canonical_relation like 'public.phase_c!_%' escape '!' then 'KERNEL_OWNED'
       else 'EXISTING_TABLE' end,
  case when b.relation_kind = 'PHASE_D_OBJECT_VIEW'          then 'OBJECT_ID_BUSINESS_KEY_VERSION'
       when b.canonical_relation like 'public.phase_c!_%' escape '!' then 'KERNEL_ID'
       else 'RELATION_PRIMARY_KEY' end,
  coalesce(nullif(split_part(b.canonical_relation, '.', 1), ''), 'public'),
  case when position('.' in b.canonical_relation) > 0
       then split_part(b.canonical_relation, '.', 2) else b.canonical_relation end,
  case when b.relation_kind = 'PHASE_D_OBJECT_VIEW' then 'business_key'
       else coalesce(nullif(btrim(b.primary_identity),''), 'id') end,
  case when b.relation_kind = 'PHASE_D_OBJECT_VIEW'
       then 'deterministic: md5(phase_d_fixture:<fixture_run>:<object_id>:<run_id>) inside a fixture '
            || 'run, or the caller-supplied key derived from the run business_object_id prefix'
       else 'the canonical relation''s own primary key, ' || coalesce(nullif(btrim(b.primary_identity),''),'id')
            || ', assigned by the relation' end,
  coalesce(nullif(btrim(b.versioning),''), '(not stated on the frozen binding)'),
  b.ownership_scope || case when coalesce(btrim(b.ownership_column),'') = '' then ' (no ownership column on the relation)'
                            else ' via ' || b.ownership_column end,
  coalesce(nullif(btrim(b.canonical_read_service),''), 'fn_phase_d_object_read'),
  coalesce(nullif(btrim(b.canonical_write_service),''), 'fn_phase_d_object_write'),
  case when b.relation_kind = 'PHASE_D_OBJECT_VIEW'
       then 'public.phase_d_object_record where object_id = <object_id> and business_key = <business_key>'
       else 'public.' || case when position('.' in b.canonical_relation) > 0
                              then split_part(b.canonical_relation,'.',2) else b.canonical_relation end
            || ' where ' || coalesce(nullif(btrim(b.primary_identity),''),'id') || ' = <pk_value>' end,
  case when exists (select 1 from public.phase_d_fixture_stage s where s.object_id = b.object_id)
       then 'fn_phase_d_fixture_scenario stage ' ||
            (select min(s.stage_key) from public.phase_d_fixture_stage s where s.object_id = b.object_id)
       else 'no fixture stage creates this object; it is created by a handler effect or not at all' end,
  coalesce(nullif(btrim(b.trace_relationship),''), '(not stated on the frozen binding)')
FROM public.phase_d_business_object_binding b
WHERE b.object_id = 'invoice_receipt'
ON CONFLICT (object_id) DO UPDATE SET
  storage_kind             = excluded.storage_kind,
  canonical_identity_type  = excluded.canonical_identity_type,
  physical_schema          = excluded.physical_schema,
  physical_relation        = excluded.physical_relation,
  physical_pk_column       = excluded.physical_pk_column,
  business_key_derivation  = excluded.business_key_derivation,
  version_rule             = excluded.version_rule,
  ownership_rule           = excluded.ownership_rule,
  reader                   = excluded.reader,
  writer                   = excluded.writer,
  evidence_lookup          = excluded.evidence_lookup,
  fixture_creation_service = excluded.fixture_creation_service,
  trace_relationship       = excluded.trace_relationship;

`;

const write = splice(await liveBody('fn_phase_d_object_write'), [
  [`    if wm.operation = 'UPSERT_STATE' then
      -- D18. AN UPSERT MUST LOOK FOR THE ROW IT WOULD WRITE, NOT FOR A DIFFERENT ONE.`,
   `    -- K04. THE IDENTITY PROBE RUNS FOR AN INSERT TOO. An INSERT that would violate a unique
    -- index on values this call supplies is not a new record: it is the record that already exists.
    -- W16-S05 collided on reveal_invoices_pkey because operation INSERT skipped the probe entirely
    -- and the scenario had already issued the invoice for that transaction. For an INSERT the
    -- existing reference is returned and NOTHING is updated -- see the branch below -- so an
    -- immutable_revision object is never rewritten by a replay.
    if wm.operation in ('UPSERT_STATE', 'INSERT') then
      -- D18. AN UPSERT MUST LOOK FOR THE ROW IT WOULD WRITE, NOT FOR A DIFFERENT ONE.`],
  [`      if v_existing is not null then
        if cardinality(v_sets) = 0 then`,
   `      if v_existing is not null then
        -- K04. AN INSERT NEVER UPDATES WHAT IT FOUND. The row already exists under the identity
        -- this call carries; that is the declared completion condition met, not a second record and
        -- not a rewrite of the first.
        if wm.operation = 'INSERT' or cardinality(v_sets) = 0 then`],
]);

writeFileSync(
  'scripts/sql/phase_d_k04_the_invoice_was_keyed_on_its_number.sql',
  HEADER + write + ';\n');
console.log('written');
