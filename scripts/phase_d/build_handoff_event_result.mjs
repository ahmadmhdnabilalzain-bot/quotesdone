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
//
// IT WAS TWO FILES PRETENDING TO BE ONE, AND NOTHING COULD PARSE IT.
//
// 19 Aug 2026. csv() already terminates its output with '\n'; the write concatenated
// `csv(H_COLS, handoffs) + '\n' + csv(E_COLS, events)`, adding a second. The committed deliverable
// was therefore 509 lines with a field-count histogram of {1: 1, 19: 160, 21: 348}: a 19-column
// header, 159 handoff rows, a bare blank line, a SECOND 21-column header, and 347 event rows. Every
// CSV reader in existence reads that as a 19-column table whose 161st row is empty and whose 162nd
// row is data — the event half was unreadable to anything but a human eye.
//
// It is one table now, over a union of both column sets, with `record_kind` first. The two halves
// genuinely are one artefact — §4 and §10 are the two directions work moves — so the fix is a
// single header rather than two files: PHASE_D_HANDOFF_EVENT_RESULT.csv is required deliverable 6
// by that name, and splitting it would have made deliverable 6 disappear.
import { writeFileSync } from 'node:fs';
import { mgmtRead, PROD_REF } from '../staging/qd_guard.mjs';
import { outPath, provenance } from './lib/deliverable.mjs';

const cell = (v) => {
  const s = v === null || v === undefined ? '' : String(v);
  return /[",\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
};

// `kind` is the discriminator both halves already carried; it is renamed `record_kind` in the union
// header so a reader of the file cannot mistake it for a handoff_type or an event category.
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

// ONE HEADER, ONE FIELD COUNT. The union preserves column order — the three shared columns first,
// then the handoff-only columns, then the event-only ones — so a handoff row is blank in the event
// columns and vice versa, and every record in the file has the same arity.
const UNION = ['record_kind', ...H_COLS.slice(1),
               ...E_COLS.slice(1).filter((c) => !H_COLS.includes(c))];
const all = [...handoffs, ...events].map((r) => ({ ...r, record_kind: r.kind }));
const body = [UNION.join(',')]
  .concat(all.map((r) => UNION.map((c) => cell(r[c])).join(',')))
  .join('\n') + '\n';

// THE HISTOGRAM IS THE ASSERTION, and it is computed the way a reader's parser would compute it —
// quote-aware, because a naive split on ',' reports a different arity for every row carrying a
// comma inside a quoted cell and would make this check noise. One field count, one header, or the
// file is not written.
const arityOf = (line) => {
  let n = 1, q = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (q) { if (c === '"' && line[i + 1] === '"') i++; else if (c === '"') q = false; }
    else if (c === '"') q = true;
    else if (c === ',') n++;
  }
  return n;
};
const arities = new Set(body.trimEnd().split('\n').map(arityOf));
if (arities.size !== 1 || !arities.has(UNION.length)) {
  console.error(`the file would carry field count(s) ${[...arities].sort((a, b) => a - b).join(', ')} `
    + `against a ${UNION.length}-column header. Two headers in one CSV is the defect this rewrite `
    + 'exists to remove; refusing to write it.');
  process.exit(1);
}

writeFileSync(outPath('PHASE_D_HANDOFF_EVENT_RESULT.csv'),
  provenance({
    command: 'node scripts/phase_d/build_handoff_event_result.mjs',
    numerator: all.length,
    denominator: wantH + wantE,
    of: `frozen subjects (${wantH} handoffs + ${wantE} events)`,
    attribution: 'one row per handoff contract and per event reconciliation over a union of both '
      + 'column sets; record_kind says which',
  }) + body);

const observed = events.filter((e) => e.runtime_observation === 'OBSERVED_IN_OUTBOX').length;
const claimed = events.filter((e) => e.structural_status === 'CONNECTED').length;
const loops = events.filter((e) => e.is_self_loop === 'true').length;

console.log(`PHASE_D_HANDOFF_EVENT_RESULT.csv  ${handoffs.length} handoffs + ${events.length} events`);
console.log(`  handoff contracts            ${handoffs.length} / ${wantH}`);
console.log(`  events reconciled            ${events.length} / ${wantE}`);
console.log(`  structurally CONNECTED       ${claimed}`);
console.log(`  observed in the outbox       ${observed}   <- the measurement, not the claim`);
console.log(`  self-loops (producer=consumer) ${loops}   <- ratcheted, needs a Phase B change request`);
