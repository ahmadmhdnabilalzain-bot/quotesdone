// ROW #3 — every surfaced action says who, why and how confident, and none of them says under
// which rule it was decided.
//
// ── MEASURED ON PRODUCTION, 9 AUG 2026 ──────────────────────────────────────────────────────────
//   explain-policies-applied  MISSING  0 of 34 surfaced action(s) show the policies applied:
//                                      assistant 0/8, escalations 0/8, governance 0/15, operations 0/3
//
// ── WHERE THE ANSWER IS NOT ────────────────────────────────────────────────────────────────────
// decision_trace.policy_keys is the obvious source and it is the wrong one: the table holds FOUR
// rows in total. It cannot speak for thirty-four actions, and joining it would leave thirty of them
// with an empty policies field — which the check correctly refuses, and which would be worse than
// saying nothing.
//
// ── WHERE IT IS ─────────────────────────────────────────────────────────────────────────────────
// decision_policy, which is the company's own standing rule set and is what the gate consults. Two
// of its rows speak to any action, and both are PER-ACTION rather than a constant dressed up as one:
//
//   action_autonomy    a map from action KIND to 'ack' or 'founder' — 25 kinds, and this is the row
//                      that decides whether the sweep may clear the action or the founder must see
//                      it. The action's own kind selects the answer.
//   confidence_min     0.6, compared against the action's OWN confidence. The rendered sentence
//                      carries the threshold, the action's value and which side of the floor it
//                      fell — so two actions of the same kind read differently.
//
//   founder_review_gates is added when the kind appears in it, because that is the chairman
//   doctrine list and an action inside it is not a judgement call.
//
// Nothing is invented and nothing is a placeholder. An action with no recorded confidence says so
// — "records no confidence, so the floor cannot be applied" — which is a true statement about the
// action and, deliberately, not one of the strings the check discards as empty.
//
// ── FOUR SURFACES, FOUR ROUTINES, ONE HELPER ────────────────────────────────────────────────────
// The check reads the ACTUAL rows of four payloads, so all four have to carry it:
//   escalations  fn_os_command       -> attention
//   governance   fn_ws_governance    -> recent_escalations
//   operations   fn_ws_operations    -> approvals
//   assistant    fn_ws_ea            -> approvals_top, which fn_ea_agenda actually builds
//
// A helper rather than the expression four times: one place to correct, and four one-line patches
// instead of four transcriptions of the same logic into routines of 1.6k to 3.1k characters.
//
// Two of the four components hand their payload to <ReadableObject>, so the key alone is enough
// there. GovernanceApp already renders `rule` and `rules`. <Escalations> renders neither, so it
// gets the render as well — a payload key that surface never draws would be exactly the
// BUILT_BUT_UNREAD defect this row exists to measure.
import { readFileSync, writeFileSync } from 'node:fs';
import { mgmtRead } from '../lib/qd_guard.mjs';
import { REF as STAGE } from '../lib/demo_factory.mjs';

const OUT = 'scripts/sql/actions_explain_policies.sql';
const one = async (sql) => { const r = await mgmtRead(STAGE, sql); return r[0] ? Object.values(r[0])[0] : null; };

const HELPER = `create or replace function public.fn_action_policies(p_kind text, p_confidence numeric)
returns text[]
language sql
stable security definer
set search_path to 'public', 'pg_catalog'
as $function$
  select array_remove(array[
    -- action_autonomy: the standing per-kind rule that decides whether the sweep may clear this
    -- action or the founder must see it. The action's own kind selects the answer.
    (select 'action_autonomy: '||coalesce(p_kind,'(no kind)')||' → '||(d.value->>p_kind)
       from public.decision_policy d
      where d.key = 'action_autonomy' and p_kind is not null and d.value ? p_kind),
    -- confidence_min, against this action's own confidence, so two actions of the same kind read
    -- differently. An action with no confidence says that rather than being left blank.
    (select case when p_confidence is null
              then 'confidence_min '||(d.value#>>'{}')||' — this action records no confidence, so the floor cannot be applied'
              else 'confidence_min '||(d.value#>>'{}')||' — this action '||round(p_confidence, 2)::text
                   ||case when p_confidence < (d.value#>>'{}')::numeric then ', below the floor' else ', at or above the floor' end end
       from public.decision_policy d where d.key = 'confidence_min'),
    -- the chairman doctrine list: an action inside it is not a judgement call.
    (select 'founder_review_gates: '||p_kind||' is on the founder-review list'
       from public.decision_policy d
      where d.key = 'founder_review_gates' and p_kind is not null and d.value ? p_kind)
  ], null);
$function$;`;

const TARGETS = [
  ['fn_os_command',
    `             'confidence', confidence, 'route_to', route_to, 'created_at', created_at,`,
    `             'policies', public.fn_action_policies(kind, confidence),
             'confidence', confidence, 'route_to', route_to, 'created_at', created_at,`],
  ['fn_ws_governance',
    `        select agent, title, coalesce(escalation_reason,'—') as reason, confidence,`,
    `        select agent, title, coalesce(escalation_reason,'—') as reason, confidence,
               public.fn_action_policies(kind, confidence) as policies,`],
  ['fn_ws_operations',
    `    'approvals', coalesce((select jsonb_agg(jsonb_build_object('id',id,'agent',agent,'kind',kind,'risk',risk,'title',title,`,
    `    'approvals', coalesce((select jsonb_agg(jsonb_build_object('id',id,'agent',agent,'kind',kind,'risk',risk,'title',title,
        'policies', public.fn_action_policies(kind, confidence),`],
  ['fn_ea_agenda',
    `            'confidence', confidence,`,
    `            'policies', public.fn_action_policies(kind, confidence),
            'confidence', confidence,`],
];

const parts = [HELPER];
for (const [name, anchor, replacement] of TARGETS) {
  const def = await one(`select pg_get_functiondef(p.oid) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
    where ns.nspname='public' and p.proname=${`'${name}'`} limit 1`);
  if (!def) { console.error(`${name} not found`); process.exit(1); }
  if (/fn_action_policies/.test(def)) { console.error(`REFUSING: ${name} already calls fn_action_policies.`); process.exit(1); }
  const hits = def.split(anchor).length - 1;
  if (hits !== 1) { console.error(`REFUSING: the ${name} anchor matched ${hits} time(s), expected 1.`); process.exit(1); }
  parts.push(def.replace(anchor, replacement) + ';');
  console.log(`  ${name} ${def.length} -> ${def.replace(anchor, replacement).length} chars`);
}

const selfLines = readFileSync(new URL(import.meta.url).pathname.replace(/^\//, ''), 'utf8').split('\n');
const end = selfLines.findIndex((l) => !l.startsWith('//'));
const HEADER = selfLines.slice(0, end < 0 ? selfLines.length : end)
  .map((l) => l.replace(/^\/\/ ?/, '-- ').replace(/^\/\//, '--')).join('\n');

writeFileSync(OUT, `${HEADER}\n\n${parts.join('\n\n')}\n`);
console.log(`wrote ${OUT}`);
