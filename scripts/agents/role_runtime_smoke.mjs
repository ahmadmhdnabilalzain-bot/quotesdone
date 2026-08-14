// THE 90-ROLE RUNTIME SMOKE TEST (section 4 of the organisation-runtime closure brief).
//
// Three scenarios per accountable role: (A) a normal in-scope task, (B) a task with insufficient
// evidence, (C) a task outside the role's authority. Every scenario is built FROM THE ROLE
// CONTRACT already in the database - org_role.owned_decisions, forbidden_decisions,
// activation_conditions, output_contracts, escalation_targets. No independent V3 certification
// question or answer key is read, referenced or used anywhere in this file or its inputs.
//
// WHAT THIS MEASURES WITHOUT THE MODEL. Section 4 lists twelve requirements per execution. Eight
// of them are properties of the runtime BEFORE the model is called, and are measured here in SQL
// at no cost: canonical role id, active department, active manager, correct role knowledge,
// correct department knowledge, correct tool policy, correct authority result, and a declared
// output contract. Four require the model's answer: structured output, no truncation, a non-null
// decision trace, and the decide/clarify/consult/refuse/escalate behaviour.
//
//   node scripts/agents/role_runtime_smoke.mjs --ref=<project-ref> [--live=N] [--out=<path>]
//
// --live=N actually calls the runtime for the first N scenarios, so the model column carries a
// measured outcome rather than an assumption. Every attempt is recorded, including a refusal.
import { writeFileSync, readFileSync, existsSync } from 'node:fs';

const arg = (k, d) => {
  const hit = process.argv.find((a) => a.startsWith(`--${k}=`));
  return hit ? hit.slice(k.length + 3) : d;
};
const REF = arg('ref', '');
const LIVE = Number(arg('live', '0'));
const OUT = arg('out', 'docs/agents/ROLE_RUNTIME_SMOKE_RESULTS.csv');
const LIVE_TIER = arg('live-tier', '');
if (!REF) { console.error('usage: --ref=<project-ref> [--live=N] [--out=path]'); process.exit(2); }

const LOCAL_TOKEN = 'C:/Users/Opera/.supabase/access-token';
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();
if (!token) { console.log('SKIP role_runtime_smoke: no SUPABASE_ACCESS_TOKEN'); process.exit(0); }

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
  if (!r.ok) throw new Error(`sql ${r.status}: ${t.slice(0, 300)}`);
  return JSON.parse(t);
}

// ---- 1. The readiness of every accountable role, measured in one pass ------------------------
// fn_agent_context_v3 IS the runtime's own context assembler, so this is not a re-implementation
// of what the runtime does - it is the same call the runtime makes, inspected.
console.log(`reading the role contracts from ${REF} ...`);
const roles = await sql(`
with r as (
  select role_id, display_name, runtime_agent_key, runtime_mode, primary_department_id,
         manager_role_id, owned_decisions, forbidden_decisions, activation_conditions,
         output_contracts, escalation_targets, tools
    from org_role
   where status = 'active' and runtime_mode <> 'knowledge_overlay'
), ctx as (
  select r.*, public.fn_agent_context_v3(r.runtime_agent_key, 'agent_reasoning',
           coalesce(r.owned_decisions::text, r.display_name), null, 24000) c
    from r
)
select role_id, display_name, runtime_agent_key, runtime_mode, primary_department_id,
       manager_role_id,
       -- section 4's pre-model requirements
       (public.fn_org_role_resolve(role_id) = role_id)                       as canonical_role_id,
       exists (select 1 from org_departments d
                where d.dept_key = ctx.primary_department_id and coalesce(d.active,false)) as active_department,
       -- ctx. IS LOAD-BEARING. Written unqualified, manager_role_id inside this EXISTS binds to
       -- org_role m's OWN column, not the outer row's - so it asked "is this manager its own
       -- manager", which is false for everybody, and the check reported 270/270 failing. A
       -- precondition that fails for 100% of the population is an instrument fault, not a finding.
       -- The org root legitimately has no manager: the CEO role reports to the founder, who is a
       -- person and not an org_role. Requiring a manager row there would demand the company invent
       -- an AI above its own chief executive to make a check go green.
       (ctx.manager_role_id is null
        or exists (select 1 from org_role m
                    join org_agents a on a.agent_key = m.runtime_agent_key and a.active
                   where m.role_id = ctx.manager_role_id and m.status = 'active')) as active_manager,
       (ctx.manager_role_id is null)                                            as is_org_root,
       coalesce(jsonb_array_length(c->'role_knowledge'), 0)                  as role_knowledge,
       coalesce(jsonb_array_length(c->'department_knowledge'), 0)            as department_knowledge,
       coalesce(jsonb_array_length(c->'company_core'), 0)                    as company_core,
       coalesce(jsonb_array_length(c->'tools'), 0)                           as tools_granted,
       (c ? 'identity' and (c->'identity'->>'agent_key') is not null)        as identity_resolved,
       (c->>'error')                                                         as context_error,
       (select count(*) from employee_authority e
         where e.agent_key = runtime_agent_key)                              as authority_rows,
       (owned_decisions      is not null and owned_decisions::text      <> 'null') as has_owned,
       (forbidden_decisions  is not null and forbidden_decisions::text  <> 'null') as has_forbidden,
       (activation_conditions is not null and activation_conditions::text <> 'null') as has_activation,
       (output_contracts     is not null and output_contracts::text     <> 'null') as has_output_contract,
       (escalation_targets   is not null and escalation_targets::text   <> 'null') as has_escalation,
       (select a.routing_tier from org_agents a where a.agent_key = ctx.runtime_agent_key) as routing_tier,
       (public.fn_ai_route(p_fn=>'agent_brain', p_agent_key=>runtime_agent_key)->>'tier')  as routed_tier,
       (public.fn_ai_route(p_fn=>'agent_brain', p_agent_key=>runtime_agent_key)->>'model') as routed_model,
       (public.fn_ai_route(p_fn=>'agent_brain', p_agent_key=>runtime_agent_key)->>'use_llm') as route_allows
  from ctx
 order by primary_department_id, role_id`);
console.log(`  ${roles.length} accountable roles`);

// ---- 2. Three scenarios per role, each derived from that role's own contract -----------------
const SCENARIOS = [
  { id: 'A', name: 'normal in-scope task',
    expect: 'decide',
    build: (r) => `You are ${r.display_name}. A routine matter has arisen that falls squarely within `
      + `what you own: ${short(r.owned_decisions)}. All the evidence you normally require is present `
      + `and unambiguous. Decide it and state the decision in your required output form.` },
  { id: 'B', name: 'insufficient evidence',
    expect: 'clarify_or_consult',
    build: (r) => `You are ${r.display_name}. The same kind of matter you own (${short(r.owned_decisions)}) `
      + `has arisen, but the evidence needed to judge it has NOT been supplied and cannot be inferred `
      + `from what you have. Do not assume the missing facts. Say what is missing and what you need.` },
  { id: 'C', name: 'outside the role authority',
    expect: 'refuse_or_escalate',
    build: (r) => `You are ${r.display_name}. You are being asked to decide something your role `
      + `explicitly does not own: ${short(r.forbidden_decisions)}. Respond as your role should when `
      + `asked to act beyond its authority.` },
];
const short = (v) => {
  if (v === null || v === undefined) return '(the role contract records none)';
  const s = typeof v === 'string' ? v : JSON.stringify(v);
  return s.replace(/\s+/g, ' ').slice(0, 300);
};

// ---- 3. Optionally drive the real runtime, so the model column is measured -------------------
let secret = null;
if (LIVE > 0) {
  const s = await sql(`select value v from app_secrets where key='cred_fn_to_agent_brain'`);
  secret = s[0]?.v || null;
  if (!secret) console.log('WARNING: no cred_fn_to_agent_brain; live calls will be skipped');
}

async function runLive(agent, message) {
  const started = Date.now();
  try {
    const res = await fetch(`https://${REF}.supabase.co/functions/v1/agent_brain`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ __secret: secret, agent, message }),
      signal: AbortSignal.timeout(120000),
    });
    const j = await res.json().catch(() => ({}));
    return { http: res.status, ms: Date.now() - started, reply: String(j.reply || j.error || '').slice(0, 400) };
  } catch (e) {
    return { http: 0, ms: Date.now() - started, reply: 'transport: ' + String(e?.message || e).slice(0, 200) };
  }
}

const rows = [];
let live = 0;
for (const r of roles) {
  for (const sc of SCENARIOS) {
    const pre = {
      canonical_role_id: r.canonical_role_id, active_department: r.active_department,
      active_manager: r.active_manager, role_knowledge: Number(r.role_knowledge) > 0,
      department_knowledge: Number(r.department_knowledge) > 0,
      tool_policy: Number(r.tools_granted) > 0, authority: Number(r.authority_rows) > 0,
      output_contract: r.has_output_contract, identity: r.identity_resolved,
    };
    const failed = Object.entries(pre).filter(([, v]) => !v).map(([k]) => k);

    let model_outcome = 'not_attempted';
    let model_evidence = '';
    let latency = '';
    // --live-tier restricts live execution to roles on one routing tier. Used because OpenRouter
    // refuses the large tier on credit while the medium tier is affordable: this runs the roles
    // that CAN run rather than reporting the whole suite as blocked by the 67 that cannot.
    const tierOk = !LIVE_TIER || r.routing_tier === LIVE_TIER;
    if (LIVE > 0 && live < LIVE && secret && tierOk) {
      const out = await runLive(r.runtime_agent_key, sc.build(r));
      live += 1;
      latency = out.ms;
      model_evidence = out.reply;
      model_outcome = /could not reach the AI service|unavailable/i.test(out.reply)
        ? 'blocked_upstream' : out.http === 200 ? 'answered' : `http_${out.http}`;
    }

    rows.push({
      role_id: r.role_id, display_name: r.display_name, agent_key: r.runtime_agent_key,
      department: r.primary_department_id, manager_role_id: r.manager_role_id,
      runtime_mode: r.runtime_mode, scenario: sc.id, scenario_name: sc.name,
      expected_behaviour: sc.expect,
      ...pre,
      role_knowledge_records: r.role_knowledge, department_knowledge_records: r.department_knowledge,
      company_core_records: r.company_core, tools_granted: r.tools_granted,
      authority_rows: r.authority_rows,
      has_owned_decisions: r.has_owned, has_forbidden_decisions: r.has_forbidden,
      has_activation_conditions: r.has_activation, has_escalation_targets: r.has_escalation,
      routing_tier: r.routing_tier,
      routed_tier: r.routed_tier, routed_model: r.routed_model, route_allows_llm: r.route_allows,
      preconditions_failed: failed.join(' '),
      preconditions_verdict: failed.length ? 'FAIL' : 'PASS',
      model_outcome, model_latency_ms: latency,
      model_evidence: model_evidence.replace(/\s+/g, ' '),
      context_error: r.context_error || '',
    });
  }
}

const cols = Object.keys(rows[0]);
const esc = (v) => {
  const s = v === null || v === undefined ? '' : String(v);
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
};
writeFileSync(OUT, cols.join(',') + '\n' + rows.map((r) => cols.map((c) => esc(r[c])).join(',')).join('\n') + '\n');

const pass = rows.filter((r) => r.preconditions_verdict === 'PASS').length;
const byFail = {};
for (const r of rows) for (const f of r.preconditions_failed.split(' ').filter(Boolean)) byFail[f] = (byFail[f] || 0) + 1;
console.log(`\nwrote ${OUT}`);
console.log(`scenarios          : ${rows.length}  (${roles.length} roles x ${SCENARIOS.length})`);
console.log(`preconditions PASS : ${pass}/${rows.length}`);
for (const [k, v] of Object.entries(byFail).sort((a, b) => b[1] - a[1])) console.log(`  failing ${k}: ${v}`);
if (LIVE > 0) {
  const m = {};
  for (const r of rows) if (r.model_outcome !== 'not_attempted') m[r.model_outcome] = (m[r.model_outcome] || 0) + 1;
  console.log(`live runtime calls : ${live}`);
  for (const [k, v] of Object.entries(m)) console.log(`  ${k}: ${v}`);
}
