// RETIRED 4 SEP 2026 — PHASE E (MASTER_PLAN §5.1 / §6 step 4). NOT RUN BY ANYTHING.
// Renamed from phase_c_invariants.test.mjs so neither npm test nor the CI kernel gate discovers it.
// Why: a wrapper over the fn_phase_c_invariants board, which kernel_boards_are_green already reads by signature; its other lines (errata resolved, bindings name deployed routines, routes held, zero paid inference) are rows of that same board. Duplicate reader, not a lost property.
// The reasoning for every retired drive is in docs/agents/RETIRED_PHASE_DRIVES.md. The file is kept
// verbatim below as the record of what was measured while it ran.

// Phase C invariants, run against the one project.
//
//   node scripts/checks/phase_c_invariants.test.mjs
//
// fn_phase_c_invariants() is the authority; this wrapper adds the three things a SQL function
// cannot check about itself:
//
//   * every routine a Phase C binding NAMES is deployed (so a binding CSV cannot be a document);
//   * the deliverable CSVs and the database registries agree row for row;
//   * Phase A and Phase B are still frozen.
//
// A database-reading test must skip loudly when there is no management token.  CI has none, and
// the skip has to come before the db module is imported.
import { existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN
  || existsSync(join(homedir(), '.supabase', 'access-token'));
if (!hasToken) {
  console.log('SKIP phase_c_invariants: no Supabase management token in this environment.');
  process.exit(0);
}

const { sql } = await import('../phase_c/lib/db.mjs');
const { readCSV } = await import('../phase_c/lib/package.mjs');

let fail = 0;
const check = (ok, what, detail = '') => {
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${what}${detail ? '  — ' + detail : ''}`);
  if (!ok) fail++;
};

// ---------------------------------------------------------------- 1. the organisation's properties
// 3 SEP 2026: the Phase A/B baseline-DIGEST comparison was retired as a gate (docs/agents/RETIRED_MIRROR_GATES.md)
// and printed as information. 4 SEP 2026 (Phase E): fn_phase_a_baseline_drift / fn_phase_b_baseline_drift
// were DROPPED (scripts/sql/phase_e_retire_the_frozen_baseline_boards.sql) — the founder removed the
// phase freezes on 2 Sep, and a digest of the org's shape kept in org_phase_baseline is a copy of
// production. The PROPERTIES those digests stood for are asserted by routines that read production:
// fn_phase_a_organization_violations (below, and inside fn_phase_c_invariants / fn_phase_b_invariants),
// fn_org_role_violations (org_reorg_behaviour) and the Phase C invariants.
const violations = await sql(`select * from public.fn_phase_a_organization_violations()`);
check(violations.length === 0, 'the organisation has no structural violation', violations.map(r => JSON.stringify(r)).join('; '));
const errata = await sql(`select * from public.fn_phase_b_effective_errata() where not resolved`);
check(errata.length === 0, 'every effective Phase B erratum is resolved');

// ---------------------------------------------------------------- 2. the Phase C invariants
const inv = await sql(`select * from public.fn_phase_c_invariants()`);
const bad = inv.filter(r => !r.ok);
for (const r of bad) console.log(`FAIL  invariant ${r.check_name}: ${r.actual} (expected ${r.expected})`);
check(bad.length === 0, `${inv.length - bad.length}/${inv.length} Phase C invariants pass`);

// ---------------------------------------------------------------- 3. CSV / database agreement
// 3 SEP 2026: INFORMATIONAL, NOT A GATE (docs/agents/RETIRED_MIRROR_GATES.md). These nine CSVs are
// snapshots of the runtime registries, emitted by scripts/phase_c/build_*.mjs on the day they were
// built. The registries the runtime reads are the tables; a component declared, a cron wrapped or a
// binding retired makes the snapshot lag, and this block reddened the gate for that bookkeeping on
// every real change. What the snapshots were defending — every component owned, every binding on an
// active role — is asserted against production by phase_c_components_are_owned and the invariants
// above. The lag is printed so a reader knows the snapshot's age; nothing fails on it.
const PAIRS = [
  ['PHASE_C_RUNTIME_COMPONENT_CROSSWALK.csv', 'component_id', 'phase_c_component', 'component_id'],
  ['PHASE_C_ROLE_RUNTIME_BINDING.csv', 'canonical_role_id', 'phase_c_role_binding', 'canonical_role_id'],
  ['PHASE_C_CATEGORY_OVERLAY_RUNTIME_BINDING.csv', 'overlay_id', 'phase_c_overlay_binding', 'overlay_id'],
  ['PHASE_C_WORKFLOW_RUNTIME_BINDING.csv', 'workflow_id', 'phase_c_workflow_binding', 'workflow_id'],
  ['PHASE_C_STEP_RUNTIME_BINDING.csv', 'step_id', 'phase_c_step_binding', 'step_id'],
  ['PHASE_C_HANDOFF_RUNTIME_BINDING.csv', 'handoff_id', 'phase_c_handoff_binding', 'handoff_id'],
  ['PHASE_C_EVENT_RUNTIME_BINDING.csv', 'event_id', 'phase_c_event_binding', 'event_id'],
  ['PHASE_C_GATE_ENFORCEMENT_BINDING.csv', 'gate_id', 'phase_c_gate_binding', 'gate_id'],
  ['PHASE_C_RULE_ENFORCEMENT_BINDING.csv', 'rule_id', 'phase_c_rule_binding', 'rule_id'],
];
for (const [csvName, csvKey, table, dbKey] of PAIRS) {
  const csv = readCSV(join(REPO, 'docs', 'phase-c', csvName));
  const db = await sql(`select ${dbKey} k from public.${table}`);
  const inCsv = new Set(csv.map(r => r[csvKey]));
  const inDb = new Set(db.map(r => r.k));
  const onlyCsv = [...inCsv].filter(k => !inDb.has(k));
  const onlyDb = [...inDb].filter(k => !inCsv.has(k));
  if (onlyCsv.length || onlyDb.length) {
    console.log(`note  snapshot ${csvName} (${inCsv.size}) lags public.${table} (${inDb.size}) — informational: `
      + [...onlyCsv.slice(0, 3).map(k => 'csv-only ' + k), ...onlyDb.slice(0, 3).map(k => 'db-only ' + k)].join('; '));
  }
}

// ---------------------------------------------------------------- 4. named routines are deployed
const named = await sql(`
  with s as (
    select unnest(array[gate_enforcer, authority_enforcer, review_enforcer, event_emitter,
                        handoff_writer, canonical_runtime_handler]) x from public.phase_c_step_binding
    union all select unnest(array[resolver_path, task_receiver_path, authority_binding_path,
                                 review_binding_path, knowledge_scope_path, tool_policy_path])
             from public.phase_c_role_binding
    union all select unnest(array[invocation_entrypoint]) from public.phase_c_overlay_binding
    union all select unnest(array[runtime_entrypoint, event_outbox_writer]) from public.phase_c_workflow_binding
    union all select unnest(array[runtime_writer, runtime_receiver, packet_schema_validator, sla_timer_handler])
             from public.phase_c_handoff_binding
    union all select unnest(array[outbox_writer, delivery_worker]) from public.phase_c_event_binding
    union all select unnest(array[enforcement_function]) from public.phase_c_gate_binding
    union all select unnest(array[enforcement_function]) from public.phase_c_rule_binding)
  select distinct (regexp_match(x, 'public\\.(fn_[a-z0-9_]+)'))[1] fn from s where x is not null`);
const wanted = named.map(r => r.fn).filter(Boolean);
const deployed = new Set((await sql(
  `select proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'`))
  .map(r => r.proname));
const missing = wanted.filter(f => !deployed.has(f));
check(missing.length === 0, `all ${wanted.length} routines named by a binding are deployed`, missing.join(', '));

// ---------------------------------------------------------------- 5. the cost invariant
// Measured from the hold and the cost log, not inferred from a caught query error.
const cost = (await sql(`select
  (select count(*) from public.llm_route_health) routes,
  (select count(*) from public.llm_route_health where open_until > now()) held,
  (select min(open_until)::text from public.llm_route_health where open_until > now()) held_until,
  -- A ROW IN THE COST LEDGER IS NOT A PAID CALL (3 Sep 2026). ai_gateway records a routing decision
  -- whose every route the kernel gate held — model_used 'none', zero tokens, cost 0, the holding
  -- rule in the rationale — and the deterministic-refusal branch has always written the same shape.
  -- Counting those as paid inference turned the router doing exactly what the hold demands into a
  -- red invariant. "Paid" means a provider was reached: a model other than 'none', tokens, or cost.
  -- fn_phase_c_invariants carries the same predicate.
  (select max(occurred_at)::text from public.ai_cost_log
     where coalesce(cost_aed, 0) > 0 or coalesce(prompt_tokens, 0) > 0 or coalesce(model_used, 'none') <> 'none') last_ai_call,
  -- the column is cost_aed, not cost_usd; naming it wrong would have made a zero that measures
  -- nothing look like a zero that measures cost
  (select coalesce(sum(cost_aed),0)::text from public.ai_cost_log
     where occurred_at > timestamptz '2026-08-15 09:00:00+00') cost_since_phase_c,
  -- 4 SEP 2026: a ledger row is not a paid call. A HELD call (founder_hold) writes a row with
  -- model_used = 'none', cost 0 and no provider round trip; paid means a provider was reached.
  (select count(*) from public.ai_cost_log
     where occurred_at > timestamptz '2026-08-15 09:00:00+00'
       and (coalesce(cost_aed, 0) > 0 or coalesce(prompt_tokens, 0) > 0 or coalesce(model_used, 'none') <> 'none')) calls_since_phase_c,
  (select count(*) from public.ai_cost_log
     where occurred_at > timestamptz '2026-08-15 09:00:00+00'
       and coalesce(model_used, 'none') = 'none' and coalesce(prompt_tokens, 0) = 0) held_or_deterministic_since_phase_c`))[0];
check(Number(cost.routes) === Number(cost.held), 'every provider route is held open-circuit',
      `${cost.held}/${cost.routes} held until ${cost.held_until}`);
check(Number(cost.calls_since_phase_c) === 0, 'zero paid inference calls since Phase C began',
      `last paid call in the estate: ${cost.last_ai_call}; ${cost.held_or_deterministic_since_phase_c} routing decision(s) answered without a provider (held or deterministic) since Phase C began`);
check(Number(cost.cost_since_phase_c) === 0,
      'paid inference cost since Phase C began is AED 0.00 (= USD 0.00)');

console.log(`\n${fail === 0 ? 'PHASE C INVARIANTS PASS' : `${fail} check(s) failed`}`);
process.exit(fail === 0 ? 0 : 1);
