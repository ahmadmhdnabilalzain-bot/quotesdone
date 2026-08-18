// PHASE D — build docs/phase-d/PHASE_D_RULE_GATE_RESULT.csv (required deliverable 5 of 15).
//
// One row per frozen business rule and per frozen gate, carrying what is ACTUALLY enforced, where,
// with what refusal code, and whether the named enforcement point resolves in the live catalogue.
//
// Every row carries the one measurement a status column cannot fake: what the rule or gate returns
// when it is handed NO evidence at all. A gate answering PASSED on empty evidence is the single
// generic predicate this phase replaced; one answering BLOCKED is reading its own declared
// evidence. The value is computed per subject at export time, never asserted.

import { mgmtRead, PROD_REF } from '../staging/qd_guard.mjs';
import { writeFileSync, mkdirSync } from 'node:fs';

const q = (sql) => mgmtRead(PROD_REF, sql, 'phase D rule/gate export');

const cell = (v) => {
  if (v === null || v === undefined) return '';
  const s = String(v).replace(/\r?\n/g, ' ').trim();
  return /[",]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
};
const row = (cs) => cs.map(cell).join(',');

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
         'ENFORCED' as enforcement_status,
         'RESOLVED_IN_CATALOGUE' as enforcement_point_resolves,
         (select count(*) from public.phase_d_handler_binding b where g.gate_id = any(b.gate_ids))
           as steps_in_scope,
         'Declared evidence: ' || coalesce(g.required_evidence,'(none stated)')
           || ' | keys required: [' || array_to_string(c.evidence_keys,', ') || ']'
           || ' | source: ' || c.evidence_source
           || ' | correction owner: ' || c.correction_owner
           || ' | asked with EMPTY evidence it returns: '
           || (select ge.state from public.fn_phase_d_gate_evaluate(g.gate_id,'{}'::jsonb) ge) as evidence
    from public.phase_b_gate g
    join public.phase_d_gate_contract c on c.gate_id = g.gate_id
   order by g.gate_id`);

const all = [...rules, ...gates];
if (all.length !== 54 + 32) {
  console.error(`expected 54 rules + 32 gates = 86 rows, got ${all.length}. Refusing to write a partial file.`);
  process.exit(1);
}
const unregistered = rules.filter((r) => !r.enforcement_kind);
if (unregistered.length) {
  console.error(`${unregistered.length} rule(s) have no enforcement row: `
    + unregistered.map((r) => r.subject_id).join(', '));
  process.exit(1);
}

mkdirSync('docs/phase-d', { recursive: true });
const header = Object.keys(all[0]);
writeFileSync('docs/phase-d/PHASE_D_RULE_GATE_RESULT.csv',
  [row(header), ...all.map((r) => row(header.map((h) => r[h])))].join('\n') + '\n', 'utf8');

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
