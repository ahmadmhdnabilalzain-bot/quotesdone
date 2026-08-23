// K03 — the parent of the record a step writes is a fact of that step, whether or not a rule asks.
import { writeFileSync } from 'node:fs';
import { liveBody, splice } from './splice.mjs';

const HEADER = `-- K03 — the parent of the record a step writes is a fact of that step, asked for or not
--
-- MEASURED 23 Aug 2026 on htdblwldjkcgjvmqkbeh, immediately after K02 added the orphan guard.
-- W16-S01 "Create payment request", which had produced an effect on every previous drive, refused:
--
--   pd_object_parent_missing :: payment_transaction declares parent identity quote_id, the write map
--   reads it from payload key quote_id, and this call supplies none.
--
-- THAT IS THE GUARD WORKING, AND IT FOUND A SECOND INSTANCE OF THE SAME DEFECT. W16-S01's required
-- action is "Create the canonical payment request FROM THE APPROVED REVEAL CHARGE" -- a reveal
-- charge is a charge to reveal a QUOTE -- and public.transactions.quote_id is nullable, so every
-- drive had been recording a reveal payment that belonged to no quote and nothing had noticed.
-- public.transactions carries a PARTIAL unique index on (quote_id) WHERE quote_id IS NOT NULL, so
-- a null there also opts the row out of the one constraint that stops two payments for one quote.
--
-- WHY THE CONTEXT DID NOT HAVE IT. public.fn_phase_d_step_context builds its key list from exactly
-- two sources: the required_context of the step's rules, and the evidence_keys of the step's gates.
-- quote_id is in neither for W16-S01, so the resolver was never asked for it -- although
-- public.phase_d_context_key_object registers quote_id -> quotation and the G08 machinery would
-- have resolved it from the quotation the scenario created.
--
-- THE CONTEXT NOW ALSO CARRIES THE PARENT OF THE RECORD THE STEP WRITES. A third arm is added to
-- the key list, derived: the effect object's own binding.parent_identity, where the object's write
-- map maps a column of that name from a payload key. A step that writes no business object adds
-- nothing; a rule or gate that already asks for the key is unaffected, because the list is a
-- distinct union. Nothing is named in this body.
--
-- ROLLBACK: scripts/sql/down/phase_d_k03_the_parent_is_a_fact_of_the_step_down.sql re-applies the
-- previous body of fn_phase_d_step_context.
--
-- GENERATED from the live body by scripts/tmp_diag/gen_k03.mjs.
`;

const ctx = splice(await liveBody('fn_phase_d_step_context'), [
  [`  select coalesce(array_agg(distinct k), '{}') into v_keys from (
    select unnest(re.required_context) k from public.phase_d_rule_enforcement re
     where re.rule_id = any (coalesce(b.rule_ids,'{}'))
    union
    select unnest(gc.evidence_keys) k from public.phase_d_gate_contract gc
     where gc.gate_id = any (coalesce(b.gate_ids,'{}'))) q(k);`,
   `  select coalesce(array_agg(distinct k), '{}') into v_keys from (
    select unnest(re.required_context) k from public.phase_d_rule_enforcement re
     where re.rule_id = any (coalesce(b.rule_ids,'{}'))
    union
    select unnest(gc.evidence_keys) k from public.phase_d_gate_contract gc
     where gc.gate_id = any (coalesce(b.gate_ids,'{}'))
    -- K03. THE PARENT OF THE RECORD THIS STEP WRITES. The list was the union of what the step's
    -- rules and gates ask for, and nothing else, so a key no rule happens to name was never
    -- resolved even where the estate could answer it. W16-S01 wrote a reveal payment that belonged
    -- to no quote for exactly that reason. The object's own frozen binding names its parent and the
    -- write map names the payload key that carries it; both are read here. A step that writes no
    -- business object adds nothing, and a key a rule already asks for is unchanged -- this is a
    -- distinct union.
    union
    select wm.column_map->>bb.parent_identity k
      from public.phase_d_business_object_binding bb
      join public.phase_d_object_write_map wm on wm.object_id = bb.object_id
     where bb.object_id = ec.effect_object_id
       and coalesce(btrim(bb.parent_identity),'') <> ''
       and wm.column_map ? bb.parent_identity
       and wm.column_map->>bb.parent_identity not in ('business_key','owner_ref','state')
    ) q(k);`],
]);

writeFileSync('scripts/sql/phase_d_k03_the_parent_is_a_fact_of_the_step.sql', HEADER + ctx + ';\n');
console.log('written');
