// Two registers section 9 asks for, from one pass over the database.
//
//   docs/agents/CATEGORY_OVERLAY_SMOKE_RESULTS.csv   - section 6, one row per category overlay
//   docs/agents/HISTORICAL_SELF_REVIEW_REGISTER.csv  - section 3, one row per historical self-review
//
// Neither reads any independent V3 certification question or answer key. The overlay scenarios are
// derived from each overlay's own contract in org_role and from the category record it covers.
//
//   node scripts/agents/overlay_and_review_registers.mjs --ref=<project-ref>
import { SUPABASE_TOKEN_FILE } from '../lib/supabase_token.mjs';
import { writeFileSync, readFileSync, existsSync } from 'node:fs';

const arg = (k, d) => {
  const hit = process.argv.find((a) => a.startsWith(`--${k}=`));
  return hit ? hit.slice(k.length + 3) : d;
};
const REF = arg('ref', '');
if (!REF) { console.error('usage: --ref=<project-ref>'); process.exit(2); }
const LOCAL_TOKEN = SUPABASE_TOKEN_FILE;
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();
if (!token) { console.log('SKIP registers: no SUPABASE_ACCESS_TOKEN'); process.exit(0); }

async function sql(query, attempt = 0) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query }),
  });
  if ((r.status === 429 || r.status >= 500) && attempt < 5) {
    await new Promise((s) => setTimeout(s, 1500 * 2 ** attempt));
    return sql(query, attempt + 1);
  }
  const t = await r.text();
  if (!r.ok) throw new Error(`sql ${r.status}: ${t.slice(0, 400)}`);
  return JSON.parse(t);
}

const esc = (v) => {
  const s = v === null || v === undefined ? '' : String(v).replace(/\s+/g, ' ');
  return /[",]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
};
const write = (path, rows) => {
  if (!rows.length) { writeFileSync(path, '(no rows)\n'); return; }
  const cols = Object.keys(rows[0]);
  writeFileSync(path, cols.join(',') + '\n'
    + rows.map((r) => cols.map((c) => esc(r[c])).join(',')).join('\n') + '\n');
};

// ---- SECTION 6: the 86 category overlays ------------------------------------------------------
// Measured without the model: overlay resolution, the canonical category it covers, whether
// category knowledge is actually retrievable for it, whether the never-infer rules and mandatory
// fields exist to be loaded, and - the safety property - that the overlay cannot dispatch.
const overlays = await sql(`
with o as (
  select role_id, display_name, runtime_agent_key, primary_department_id,
         owned_decisions, forbidden_decisions, output_contracts, escalation_targets,
         -- role_id is category_overlay_<NNN>_<category-key>
         -- org_category_identity.category_key KEEPS the number prefix (001_construction-...).
         -- Stripping it made all four category joins miss and reported 86/86 failing - an
         -- instrument fault, not a finding. A check that fails for the whole population is
         -- almost always measuring the wrong thing.
         substring(role_id from '^category_overlay_(.*)$') as cat_key
    from org_role
   where status = 'active' and runtime_mode = 'knowledge_overlay'
)
select o.role_id, o.display_name, o.primary_department_id,
       public.fn_org_role_resolve(o.role_id) as overlay_resolves_to,
       (public.fn_org_role_resolve(o.role_id) is not null) as overlay_resolution,
       i.category_key, i.route_key, i.owner_agent, i.readiness,
       (i.category_key is not null) as canonical_category,
       (select count(*) from ops_knowledge k
         where k.runtime_eligible and k.supersession_state = 'current'
           and k.layer = 'category_specialist' and k.category_key = i.category_key) as category_knowledge,
       -- Mandatory fields, never-infer rules and regulatory gates live INSIDE the category
       -- knowledge documents (record_type md/yaml), not in a table, so they are measured by
       -- searching the runtime-eligible content the overlay would actually be handed. That is a
       -- presence test over content, not a judgement that the content is correct.
       (select count(*) from ops_knowledge k where k.category_key = o.cat_key
         and k.runtime_eligible and k.supersession_state = 'current'
         and k.content ~* '(mandatory|required field|must (be )?(specified|provided)|required inform)') as mandatory_field_rows,
       (select count(*) from ops_knowledge k where k.category_key = o.cat_key
         and k.runtime_eligible and k.supersession_state = 'current'
         and k.content ~* '(regulat|compliance|civil defence|municipality|ESMA|certif)') as compliance_rows,
       (o.forbidden_decisions::text ~* 'inferring an unstated') as never_infer_rule_declared,
       -- the accountable RFQ role the overlay's result must return to
       (i.owner_agent is not null and exists
         (select 1 from org_agents a where a.agent_key = i.owner_agent and a.active)) as returns_to_accountable_role,
       (o.forbidden_decisions is not null) as never_infer_rules_declared,
       (o.output_contracts is not null)    as output_contract_declared,
       (o.escalation_targets is not null)  as escalation_declared,
       -- THE SAFETY PROPERTY, and it is structural rather than behavioural: an overlay carries no
       -- runtime_agent_key at all, so there is no identity for a dispatch authority to attach to.
       -- It is knowledge the accountable role reads, never an actor that can send anything.
       (o.runtime_agent_key is null
        and not exists (select 1 from employee_authority e
                         where e.agent_key = o.role_id and e.max_tier = 'autonomous')) as cannot_independently_dispatch
  from o
  left join org_category_identity i on i.category_key = o.cat_key
 order by o.role_id`);

const ovRows = overlays.map((o) => {
  const checks = {
    overlay_resolution: o.overlay_resolution,
    canonical_category: o.canonical_category,
    category_knowledge_retrieved: Number(o.category_knowledge) > 0,
    mandatory_fields_identified: Number(o.mandatory_field_rows) > 0,
    never_infer_rules_loaded: o.never_infer_rule_declared,
    output_contract: o.output_contract_declared,
    escalation_path: o.escalation_declared,
    returns_to_accountable_role: o.returns_to_accountable_role,
    cannot_independently_dispatch: o.cannot_independently_dispatch,
  };
  const failed = Object.entries(checks).filter(([, v]) => !v).map(([k]) => k);
  return {
    role_id: o.role_id, display_name: o.display_name, route_key: o.route_key, owner_agent: o.owner_agent,
    department: o.primary_department_id, resolves_to: o.overlay_resolves_to,
    category_key: o.category_key || '', readiness: o.readiness || '',
    compliance_records: o.compliance_rows,
    ...checks,
    category_knowledge_records: o.category_knowledge,
    mandatory_field_rows: o.mandatory_field_rows,
    preconditions_failed: failed.join(' '),
    preconditions_verdict: failed.length ? 'FAIL' : 'PASS',
    // the questioning / blocking / refusal behaviours need the model, which is credit-blocked
    behavioural_outcome: 'blocked_upstream_insufficient_credit',
  };
});
write('docs/agents/CATEGORY_OVERLAY_SMOKE_RESULTS.csv', ovRows);

// ---- SECTION 3: the historical self-review register -------------------------------------------
// Classified per the brief. "Self" is computed on the CANONICAL identity of both sides, not on the
// raw strings, so an author and reviewer who are one employee under two names are counted as one.
const reviews = await sql(`
with r as (
  select rc.id, rc.subject_type, rc.subject_id, rc.dept_key, rc.stage, rc.decision,
         rc.created_at, rc.author_agent, rc.reviewer_agent,
         coalesce(public.fn_org_agent_resolve(rc.author_agent), rc.author_agent)   a,
         coalesce(public.fn_org_agent_resolve(rc.reviewer_agent), rc.reviewer_agent) rv
    from review_chain rc
   where rc.reviewer_agent is not null
), self as (select * from r where a = rv),
indep as (
  select subject_id,
         count(*) filter (where a <> rv and decision = 'approve') indep_approvals,
         string_agg(distinct case when a <> rv and decision='approve' then stage||' by '||rv end, '; ') indep_trail
    from r group by subject_id
)
select s.id, s.subject_type, s.subject_id, s.dept_key, s.stage, s.decision, s.created_at,
       s.author_agent as author_as_written, s.reviewer_agent as reviewer_as_written,
       s.a as effective_identity,
       coalesce(i.indep_approvals, 0) as independent_approvals_on_same_subject,
       coalesce(i.indep_trail, '') as independent_review_trail,
       t.status as subject_status
  from self s
  left join indep i on i.subject_id = s.subject_id
  left join org_tasks t on t.id::text = s.subject_id
 order by s.created_at, s.id`);

const revRows = reviews.map((s) => {
  const releasing = s.decision === 'approve' && s.stage !== 'ownership';
  const indep = Number(s.independent_approvals_on_same_subject) > 0;
  let cls;
  if (!releasing) {
    cls = 'non_consequential';           // an ownership claim or a refusal releases nothing
  } else if (indep) {
    cls = 'already_independently_reviewed';
  } else if (['cancelled', 'superseded', 'duplicate'].includes(s.subject_status)) {
    cls = 'superseded';
  } else {
    cls = 'requires_independent_re_review';
  }
  return {
    review_chain_id: s.id, created_at: s.created_at, subject_type: s.subject_type,
    subject_id: s.subject_id, department: s.dept_key, stage: s.stage, decision: s.decision,
    author_as_written: s.author_as_written, reviewer_as_written: s.reviewer_as_written,
    effective_identity: s.effective_identity,
    releases_work: releasing,
    independent_approvals_on_same_subject: s.independent_approvals_on_same_subject,
    independent_review_trail: s.independent_review_trail,
    subject_status: s.subject_status || '(not an org_task)',
    classification: cls,
  };
});
write('docs/agents/HISTORICAL_SELF_REVIEW_REGISTER.csv', revRows);

const tally = (rows, k) => rows.reduce((m, r) => ((m[r[k]] = (m[r[k]] || 0) + 1), m), {});
console.log(`overlays                 : ${ovRows.length}`);
console.log(`  preconditions PASS     : ${ovRows.filter((r) => r.preconditions_verdict === 'PASS').length}/${ovRows.length}`);
const ovFail = {};
for (const r of ovRows) for (const f of r.preconditions_failed.split(' ').filter(Boolean)) ovFail[f] = (ovFail[f] || 0) + 1;
for (const [k, v] of Object.entries(ovFail).sort((a, b) => b[1] - a[1])) console.log(`    failing ${k}: ${v}`);
console.log(`  cannot dispatch        : ${ovRows.filter((r) => r.cannot_independently_dispatch).length}/${ovRows.length}`);
console.log(`\nhistorical self-reviews  : ${revRows.length}`);
for (const [k, v] of Object.entries(tally(revRows, 'classification'))) console.log(`  ${k}: ${v}`);
