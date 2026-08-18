// PHASE D — build PHASE_D_RULE_GATE_RESULT.csv (required deliverable 5 of 15).
//
// One row per frozen business rule and per frozen gate, carrying what is ACTUALLY enforced and
// where. The gate half is deliberately unflattering: all 32 gates currently resolve to one
// generic predicate in fn_phase_c_gate_evaluate that checks an evidence envelope and the actor,
// and never reads the gate's own declared required_evidence. That is recorded as UNENFORCED
// rather than described as "enforced through the canonical boundary", which is the wording this
// phase removed from the rule scorer.

import { mgmtRead, PROD_REF } from '../staging/qd_guard.mjs';
import { writeFileSync } from 'node:fs';

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
         e.evidence
    from public.phase_b_business_rule r
    left join public.phase_d_rule_enforcement e on e.rule_id = r.rule_id
   order by r.rule_id`);

const gates = await q(`
  select 'GATE' as subject_kind, g.gate_id as subject_id, g.gate_name as subject_name,
         g.gate_type as rule_type, g.workflow_scope,
         'GENERIC_ENVELOPE_ONLY' as enforcement_kind,
         'public.fn_phase_c_gate_evaluate(text,jsonb)' as enforcement_point,
         'k3_gate_failed' as refusal_code,
         'evaluated by the frozen fn_kernel_step_complete for every step whose workflow is in scope'
           as applies_when,
         'evidence_ref;actor_role_id' as required_context,
         'OUTSTANDING' as enforcement_status,
         'RESOLVED_IN_CATALOGUE' as enforcement_point_resolves,
         (select count(*) from public.phase_d_handler_binding b where g.gate_id = any(b.gate_ids))
           as steps_in_scope,
         'The gate IS evaluated on every step completion and a hard gate failure does raise. But '
      || 'fn_phase_c_gate_evaluate applies ONE predicate to all 32: an evidence object must exist '
      || 'and carry evidence_ref and actor_role_id, and the actor must resolve to an active '
      || 'canonical role. It never reads this gate''s own required_evidence ('
      || replace(coalesce(g.required_evidence,''), '''', '')
      || '), so all 32 gates are behaviourally one gate. Phase D records this rather than '
      || 'reporting the gate as enforced.' as evidence
    from public.phase_b_gate g
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

const header = Object.keys(all[0]);
writeFileSync('docs/phase-d/PHASE_D_RULE_GATE_RESULT.csv',
  [row(header), ...all.map((r) => row(header.map((h) => r[h])))].join('\n') + '\n', 'utf8');

const n = (p) => all.filter(p).length;
console.log(`PHASE_D_RULE_GATE_RESULT.csv — ${all.length} rows (${rules.length} rules + ${gates.length} gates)`);
console.log(`  rules ENFORCED                     ${n((r) => r.subject_kind === 'RULE' && r.enforcement_status === 'ENFORCED')}`);
console.log(`  rules OUTSTANDING                  ${n((r) => r.subject_kind === 'RULE' && r.enforcement_status === 'OUTSTANDING')}`);
console.log(`  gates OUTSTANDING                  ${n((r) => r.subject_kind === 'GATE')}`);
console.log(`  enforcement points NAMED_BUT_ABSENT ${n((r) => r.enforcement_point_resolves === 'NAMED_BUT_ABSENT')}`);
