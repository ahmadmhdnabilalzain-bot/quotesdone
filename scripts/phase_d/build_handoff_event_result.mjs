// PHASE D DELIVERABLE — PHASE_D_HANDOFF_EVENT_RESULT.csv
//
// §4 and §10 in one artefact, because they are the two halves of "how does work and news move
// between owners": 159 handoff contracts and 347 event reconciliations.
//
//   node scripts/phase_d/build_handoff_event_result.mjs
//
// The event half carries TWO status columns on purpose. `structural_status` is Phase C's
// connection_status — a claim about whether a producer, a consumer role and an outbox writer exist.
// `runtime_observation` is derived from public.phase_c_event_outbox and is the only column that can
// say an event has actually happened. Measured on production: 287 events say CONNECTED and 14 have
// ever appeared in the outbox. One column was answering two questions and this splits them.
//
// The script exits 1 rather than writing fewer rows than the frozen registries hold.
import { writeFileSync, mkdirSync } from 'node:fs';
import { mgmtRead, PROD_REF } from '../staging/qd_guard.mjs';

const cell = (v) => {
  const s = v === null || v === undefined ? '' : String(v);
  return /[",\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
};
const csv = (cols, rows) =>
  [cols.join(',')].concat(rows.map((r) => cols.map((c) => cell(r[c])).join(','))).join('\n') + '\n';

const H_COLS = ['kind', 'id', 'workflow_id', 'from_step_id', 'to_step_id', 'sending_role_id',
  'receiving_role_id', 'handoff_type', 'packet_keys', 'distinguishing_key', 'source_object_id',
  'rejection_code', 'return_owner_role_id', 'accountable_before_accept', 'accountable_after_accept',
  'sla_policy_id', 'sla_target', 'closure_condition', 'acceptance_criteria'];

const E_COLS = ['kind', 'id', 'event_name', 'workflow_id', 'factual_state_change', 'producer',
  'producer_resolves', 'primary_consumer_role_id', 'consumer_resolves', 'structural_status',
  'runtime_observation', 'emissions_observed', 'outbox_relation', 'dedupe_key',
  'idempotency_mechanism', 'correlation_available', 'causation_available', 'trace_available',
  'external_effect_relation', 'cancellation_behaviour', 'is_self_loop'];

const handoffs = await mgmtRead(PROD_REF, `
  select 'handoff' as kind, handoff_id as id, workflow_id, from_step_id, to_step_id,
         sending_role_id, receiving_role_id, handoff_type,
         array_to_string(packet_keys, ';') as packet_keys, distinguishing_key,
         coalesce(source_object_id,'') as source_object_id, rejection_code, return_owner_role_id,
         accountable_before_accept, accountable_after_accept, sla_policy_id,
         sla_target::text as sla_target, closure_condition, acceptance_criteria
    from public.phase_d_handoff_contract order by handoff_id`);

const events = await mgmtRead(PROD_REF, `
  select 'event' as kind, event_id as id, event_name, workflow_id, factual_state_change, producer,
         producer_resolves::text, coalesce(primary_consumer_role_id,'') as primary_consumer_role_id,
         consumer_resolves::text, structural_status, runtime_observation,
         emissions_observed::text, outbox_relation, coalesce(dedupe_key,'') as dedupe_key,
         idempotency_mechanism, correlation_available::text, causation_available::text,
         trace_available::text, external_effect_relation, cancellation_behaviour, is_self_loop::text
    from public.phase_d_event_reconciliation order by event_id`);

const want = await mgmtRead(PROD_REF, `
  select (select count(*) from public.phase_b_handoff)::int as h,
         (select count(*) from public.phase_b_event)::int   as e`);
const wantH = want?.[0]?.h ?? 0;
const wantE = want?.[0]?.e ?? 0;

if (handoffs.length !== wantH || events.length !== wantE) {
  console.error(`handoffs ${handoffs.length}/${wantH}, events ${events.length}/${wantE} — `
    + 'refusing to write a partial export.');
  process.exit(1);
}

mkdirSync('docs/phase-d', { recursive: true });
writeFileSync('docs/phase-d/PHASE_D_HANDOFF_EVENT_RESULT.csv',
  csv(H_COLS, handoffs) + '\n' + csv(E_COLS, events));

const observed = events.filter((e) => e.runtime_observation === 'OBSERVED_IN_OUTBOX').length;
const claimed = events.filter((e) => e.structural_status === 'CONNECTED').length;
const loops = events.filter((e) => e.is_self_loop === 'true').length;

console.log(`PHASE_D_HANDOFF_EVENT_RESULT.csv  ${handoffs.length} handoffs + ${events.length} events`);
console.log(`  handoff contracts            ${handoffs.length} / ${wantH}`);
console.log(`  events reconciled            ${events.length} / ${wantE}`);
console.log(`  structurally CONNECTED       ${claimed}`);
console.log(`  observed in the outbox       ${observed}   <- the measurement, not the claim`);
console.log(`  self-loops (producer=consumer) ${loops}   <- ratcheted, needs a Phase B change request`);
