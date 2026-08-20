// PHASE D — build docs/phase-d/PHASE_D_RULE_GATE_RESULT.csv (required deliverable 5 of 15).
//
// One row per frozen business rule and per frozen gate, carrying what is ACTUALLY enforced, where,
// with what refusal code, and whether the named enforcement point resolves in the live catalogue.
//
// Every row carries the one measurement a status column cannot fake: what the rule or gate returns
// when it is handed NO evidence at all. A gate answering PASSED on empty evidence is the single
// generic predicate this phase replaced; one answering BLOCKED is reading its own declared
// evidence. The value is computed per subject at export time, never asserted.

// TWO OF THE GATE COLUMNS WERE STRING CONSTANTS SITTING IN A MEASUREMENT COLUMN.
//
// 19 Aug 2026. The rules half of this export derives `enforcement_status` and
// `enforcement_point_resolves` from the registry and the live catalogue (the `case … exists (select
// 1 from pg_proc …)` at the top of the rules query). The gates half, twenty lines below, wrote
// 'ENFORCED' and 'RESOLVED_IN_CATALOGUE' as literals — so all 32 GATE rows read as enforced and
// resolved because the query said so, not because anything was true. The committed CSV summarised
// as {"RULE / ENFORCED": 54, "GATE / ENFORCED": 32}: half of that was a measurement and half was a
// sentence, and nothing in the file told them apart.
//
// `phase_d_gate_contract` has no status column of its own — measured, it carries gate_id,
// evidence_keys, predicate_kind, refusal_code, correction_owner, evidence_source, recorded_at — so
// the status a gate CAN have is whether it is registered in the enforcement mechanism at all. The
// join is therefore a LEFT JOIN now: an unregistered gate appears as a row saying NO_CONTRACT_ROW
// rather than vanishing from the export and taking the denominator with it.
import { mgmtRead, PROD_REF } from '../staging/qd_guard.mjs';
import { writeFileSync } from 'node:fs';
import { outPath, provenance } from './lib/deliverable.mjs';

const q = (sql) => mgmtRead(PROD_REF, sql, 'phase D rule/gate export');

const cell = (v) => {
  if (v === null || v === undefined) return '';
  const s = String(v).replace(/\r?\n/g, ' ').trim();
  return /[",]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
};
const row = (cs) => cs.map(cell).join(',');

// A COLUMN THAT LOOKED TWO-STATE AND HAD ONE REACHABLE STATE.
//
// The gates half derived `enforcement_point_resolves` from `exists (select 1 from pg_proc …)`, which
// reads as a measurement — and the SAME select also invoked public.fn_phase_d_gate_evaluate for the
// empty-evidence probe. So 'NAMED_BUT_ABSENT' could never be written: if the routine were absent,
// Postgres would refuse the whole statement and the builder would exit non-zero with no CSV at all.
// The column agreed with itself in the only circumstance it could ever be read.
//
// MEASURED, not reasoned, 20 Aug 2026. Running the exact two-part shape against production with the
// routine name suffixed `_ABSENT_PROBE` returns SQLSTATE 42883 `function … does not exist` pointing
// at the invocation line — the CASE never gets to produce a row. Resolving it in a query that does
// not invoke anything returns RESOLVED_IN_CATALOGUE for the real name and NAMED_BUT_ABSENT for the
// absent one, both measured. The routine resolves today: public.fn_phase_d_gate_evaluate(p_gate_id
// text, p_evidence jsonb).
//
// So the resolution is settled FIRST, here, invoking nothing — and the gates query below asks for
// the empty-evidence probe only when the routine is actually there. When it is not, the export is
// still produced: 32 rows saying NAMED_BUT_ABSENT, with an evidence column that says the probe was
// not asked and why. That was measured too — the absent-branch shape returns all 32 gate rows.
// Refusing to build would have been the easier change and it would have kept the column one-state,
// which is the defect rather than the fix.
const gateFn = 'fn_phase_d_gate_evaluate';
const gateFnResolves = (await q(
  `select exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                   where n.nspname='public' and p.proname='${gateFn}') as ok`))?.[0]?.ok === true;

// The empty-evidence probe, or a stated reason there is none. This is the ONE place the routine is
// named as a call, so the absent case never reaches the planner.
const gateProbe = gateFnResolves
  ? `(select ge.state from public.${gateFn}(g.gate_id,'{}'::jsonb) ge)`
  : `'(not asked — public.${gateFn} is not in the catalogue)'`;

// enforcement_point_resolves below is a LITERAL in the SQL and still a measurement: it carries the
// result of the catalogue read above, taken in a query that invokes nothing. Do not "fix" it back
// into an inline exists(select 1 from pg_proc ...) beside the probe — that is what made the absent
// state unreachable.

const rules = await q(`
  select 'RULE' as subject_kind, r.rule_id as subject_id, r.rule_name as subject_name,
         r.rule_type, r.workflow_scope,
         e.enforcement_kind, e.enforcement_point, e.refusal_code, e.applies_when,
         array_to_string(e.required_context,';') as required_context,
         e.status as enforcement_status,
         case when e.enforcement_point like 'public.fn_%'
                   and exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                                where n.nspname='public'
                                  and p.proname = split_part(split_part(e.enforcement_point,'.',2),'(',1))
              then 'RESOLVED_IN_CATALOGUE'
              when e.enforcement_point like 'public.fn_%' then 'NAMED_BUT_ABSENT'
              else 'NOT_A_ROUTINE' end as enforcement_point_resolves,
         (select count(*) from public.phase_d_handler_binding b where r.rule_id = any(b.rule_ids))
           as steps_in_scope,
         e.evidence || ' | asked with EMPTY context it returns: '
           || (select rc.state from public.fn_phase_d_rule_check(r.rule_id,'{}'::jsonb) rc) as evidence
    from public.phase_b_business_rule r
    left join public.phase_d_rule_enforcement e on e.rule_id = r.rule_id
   order by r.rule_id`);

const gates = await q(`
  select 'GATE' as subject_kind, g.gate_id as subject_id, g.gate_name as subject_name,
         g.gate_type as rule_type, g.workflow_scope,
         c.predicate_kind as enforcement_kind,
         'public.fn_phase_d_gate_evaluate(text,jsonb)' as enforcement_point,
         c.refusal_code,
         'workflow scope ' || g.workflow_scope
           || '; step-level applicability decided by public.fn_phase_d_gate_applies' as applies_when,
         array_to_string(c.evidence_keys,';') as required_context,
         case when c.gate_id is null then 'NO_CONTRACT_ROW' else 'ENFORCED' end as enforcement_status,
         '${gateFnResolves ? 'RESOLVED_IN_CATALOGUE' : 'NAMED_BUT_ABSENT'}'
           as enforcement_point_resolves,
         (select count(*) from public.phase_d_handler_binding b where g.gate_id = any(b.gate_ids))
           as steps_in_scope,
         'Declared evidence: ' || coalesce(g.required_evidence,'(none stated)')
           || ' | keys required: [' || coalesce(array_to_string(c.evidence_keys,', '),'(no contract row)') || ']'
           || ' | source: ' || coalesce(c.evidence_source,'(no contract row)')
           || ' | correction owner: ' || coalesce(c.correction_owner,'(no contract row)')
           || ' | asked with EMPTY evidence it returns: '
           || ${gateProbe} as evidence
    from public.phase_b_gate g
    left join public.phase_d_gate_contract c on c.gate_id = g.gate_id
   order by g.gate_id`);

// THE EXPECTED ROW COUNT IS THE REGISTRY'S, NOT A NUMBER SOMEBODY TYPED.
//
// `if (all.length !== 54 + 32)` was correct on the day it was written and is a rubber stamp for as
// long as it stays correct: a frozen registry that gains or loses a rule makes the builder refuse
// to run rather than report the change. The zero-guard beside it is the other half — a registry
// that reads back empty must never satisfy "0 of 0".
const want = await q(`select (select count(*) from public.phase_b_business_rule)::int as r,
                             (select count(*) from public.phase_b_gate)::int as g`);
const wantR = want?.[0]?.r ?? 0;
const wantG = want?.[0]?.g ?? 0;
if (!wantR || !wantG) {
  console.error(`phase_b_business_rule holds ${wantR} row(s) and phase_b_gate holds ${wantG} — `
    + 'refusing to write a deliverable over an empty registry.');
  process.exit(1);
}

const all = [...rules, ...gates];
if (rules.length !== wantR || gates.length !== wantG) {
  console.error(`read ${rules.length}/${wantR} rule(s) and ${gates.length}/${wantG} gate(s). `
    + 'Refusing to write a partial file.');
  process.exit(1);
}
const unregistered = rules.filter((r) => !r.enforcement_kind);
if (unregistered.length) {
  console.error(`${unregistered.length} rule(s) have no enforcement row: `
    + unregistered.map((r) => r.subject_id).join(', '));
  process.exit(1);
}

const header = Object.keys(all[0]);
writeFileSync(outPath('PHASE_D_RULE_GATE_RESULT.csv'),
  provenance({
    command: 'node scripts/phase_d/build_rule_gate_result.mjs',
    numerator: all.length,
    denominator: wantR + wantG,
    of: `frozen subjects (${wantR} business rules + ${wantG} gates)`,
    attribution: 'one row per registered subject; enforcement_status and enforcement_point_resolves '
      + 'are derived from the live catalogue for both halves — the gates half resolves its '
      + 'enforcement point in a query that does not invoke it, so both states are reachable',
  })
  + [row(header), ...all.map((r) => row(header.map((h) => r[h])))].join('\n') + '\n', 'utf8');

const n = (p) => all.filter(p).length;
const isGate = (r) => r.subject_kind === 'GATE';
const isRule = (r) => r.subject_kind === 'RULE';
console.log(`PHASE_D_RULE_GATE_RESULT.csv — ${all.length} rows (${rules.length} rules + ${gates.length} gates)`);
console.log(`  rules ENFORCED                      ${n((r) => isRule(r) && r.enforcement_status === 'ENFORCED')}`);
console.log(`  rules OUTSTANDING                   ${n((r) => isRule(r) && r.enforcement_status === 'OUTSTANDING')}`);
console.log(`  rules FAILING on empty context      ${n((r) => isRule(r) && /returns: ENFORCED_FAIL/.test(r.evidence))}`);
console.log(`  gates ENFORCED                      ${n((r) => isGate(r) && r.enforcement_status === 'ENFORCED')}`);
console.log(`  gates BLOCKING on empty evidence    ${n((r) => isGate(r) && /returns: BLOCKED/.test(r.evidence))}`);
console.log(`  gates PASSING on empty evidence     ${n((r) => isGate(r) && /returns: PASSED/.test(r.evidence))}  (measured; need no caller evidence)`);
console.log(`  enforcement points NAMED_BUT_ABSENT ${n((r) => r.enforcement_point_resolves === 'NAMED_BUT_ABSENT')}`);
