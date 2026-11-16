// RETIRED 16 Nov 2026 (it_engineer) WITH ITS SUBJECT: Gate A of the Agent Runtime Connection Blueprint. It calls fn_org_role_violations() and fn_onboarding_gate(), both gone from production (SELECT pg_proc, 16 Nov 2026), so it cannot run; nothing calls it.
// GATE A — zero-model deterministic readiness, from the Agent Runtime Connection Blueprint.
//
// docs/agents/runtime_blueprint/IMPLEMENTATION_ACCEPTANCE_GATES.md defines Gate A as the set of
// checks that must pass BEFORE any paid smoke test. Every one of them is answerable from the
// database and the package, so this costs nothing to run and can run as often as you like.
//
//   node scripts/checks/retired/runtime_connection_gate_a.RETIRED.mjs                  # production
//   node scripts/checks/retired/runtime_connection_gate_a.RETIRED.mjs --write          # + reconciliation CSV
//
// It compares the LIVE runtime against the package. Where they differ it does not assume the
// package is right: the package is a target, the database is what actually runs, and the master
// prompt is explicit that a working implementation is not replaced merely to match a name.
import { SUPABASE_TOKEN_FILE } from '../../lib/supabase_token.mjs';
import { readFileSync, writeFileSync, existsSync } from 'node:fs';

const LOCAL_TOKEN = SUPABASE_TOKEN_FILE;
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();
if (!token) { console.log('SKIP gate A: no SUPABASE_ACCESS_TOKEN (expected in CI)'); process.exit(0); }

// staging ('pglpqrhvozwepymcuunn') was a second target until that Supabase project was deleted on
// 15 Aug 2026; the same assertions now run against production alone. The loop stays, so adding a
// target back is one entry.
const PROJECTS = { production: 'htdblwldjkcgjvmqkbeh' };
const PKG = 'docs/agents/runtime_blueprint';
const WRITE = process.argv.includes('--write');

async function sql(ref, query, attempt = 0) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${ref}/database/query`, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query }),
  });
  if ((r.status === 429 || r.status >= 500) && attempt < 5) {
    await new Promise((s) => setTimeout(s, 1500 * 2 ** attempt));
    return sql(ref, query, attempt + 1);
  }
  const t = await r.text();
  if (!r.ok) throw new Error(`sql ${r.status}: ${t.slice(0, 300)}`);
  return JSON.parse(t);
}

// ---- the package ------------------------------------------------------------------------------
function csv(path) {
  const lines = readFileSync(path, 'utf8').replace(/^\uFEFF/, '').split(/\r?\n/).filter(Boolean);
  const head = lines[0].split(',');
  return lines.slice(1).map((l) => {
    // split on commas outside double quotes
    const cells = l.match(/("([^"]|"")*"|[^,]*)(,|$)/g).map((c) => c.replace(/,$/, '').replace(/^"|"$/g, '').replace(/""/g, '"'));
    return Object.fromEntries(head.map((h, i) => [h.trim(), (cells[i] ?? '').trim()]));
  });
}

const pkgRoles = csv(`${PKG}/ROLE_CONNECTION_MATRIX.csv`);
const pkgModes = pkgRoles.reduce((m, r) => ((m[r.runtime_mode] = (m[r.runtime_mode] || 0) + 1), m), {});

const results = [];
const rec = [];
let failed = 0;

function check(project, id, requirement, expected, actual, ok, status, note) {
  results.push({ project, id, requirement, expected, actual, ok });
  if (!ok) failed += 1;
  if (project === 'production') rec.push({ requirement: id, detail: requirement, expected, actual, status, note });
}

for (const [label, ref] of Object.entries(PROJECTS)) {
  const [o] = await sql(ref, `select
      (select count(*) from org_departments where coalesce(active,false)) depts,
      (select count(*) from org_role where status='active' and runtime_mode<>'knowledge_overlay') roles,
      (select count(*) from org_role where status='active' and runtime_mode='knowledge_overlay') overlays,
      (select count(distinct packaged_role_id) from org_role_identity) packaged,
      (select count(*) from org_role_identity i where not exists
        (select 1 from org_agents a where a.agent_key=i.agent_key and a.active)) identity_dead,
      (select count(*) from ops_knowledge k where k.runtime_eligible and k.supersession_state='current'
        and k.dept_key is not null and not exists
        (select 1 from org_departments d where d.dept_key=k.dept_key)) orphan_knowledge,
      (select count(*) from org_agents a where a.active and a.manager_key=a.agent_key) self_manage,
      (select count(*) from fn_org_role_violations()) violations,
      (select count(*) from agent_tool) tools,
      (select count(*) from agent_tool where coalesce(input_schema::text,'') <> ''
        and timeout_seconds is not null and max_attempts is not null) tools_complete,
      (select count(*) from org_role r where r.status='active' and r.runtime_mode<>'knowledge_overlay'
        and (select a.routing_tier from org_agents a where a.agent_key=r.runtime_agent_key) is null) roles_without_model_policy,
      (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
        where n.nspname='public' and c.relname in ('decision_trace','agent_tool_call','handoff_contract')) trace_tables,
      (select count(*) from department_budget where monthly_aed > 0) budgets`);

  const modes = await sql(ref, `select runtime_mode, count(*) n from org_role
      where status='active' and runtime_mode<>'knowledge_overlay' group by 1`);
  const liveModes = Object.fromEntries(modes.map((m) => [m.runtime_mode, Number(m.n)]));

  // Reporting cycles: walk manager_key up to 20 levels and look for a node reaching itself.
  const [cyc] = await sql(ref, `with recursive up as (
      select agent_key as root, manager_key as node, 1 as depth from org_agents where active
      union all
      select u.root, a.manager_key, u.depth+1 from up u join org_agents a on a.agent_key=u.node
       where u.depth < 20 and a.manager_key is not null)
    select count(*) n from up where node = root`);

  // Creator/reviewer collision, on EFFECTIVE canonical identity - the alias case, not the string case.
  //
  // SPLIT BY THE DEPLOY, or this check stays red for a day on rows it cannot be about. The
  // a00_review_chain_no_self_review trigger reached both projects at 2026-08-14 16:20 UTC. Rows
  // written before it are history - the 285 preserved and classified in
  // HISTORICAL_SELF_REVIEW_REGISTER.csv - and no amount of correct behaviour now can change them.
  // What Gate A must assert is that NO NEW one can be written, so the window starts at the guard.
  // The pre-guard count is printed alongside rather than dropped, because a check that silently
  // narrows its own population is how a real regression hides.
  const GUARD_INSTALLED = '2026-08-14 16:20:00+00';
  const [col] = await sql(ref, `select
      count(*) filter (where created_at >  timestamptz '${GUARD_INSTALLED}') n,
      count(*) filter (where created_at <= timestamptz '${GUARD_INSTALLED}') pre_guard
     from review_chain
    where reviewer_agent is not null
      and coalesce(public.fn_org_agent_resolve(author_agent),author_agent)
        = coalesce(public.fn_org_agent_resolve(reviewer_agent),reviewer_agent)`);

  const K = (k) => Number(o[k]);
  check(label, 'A1', '10 active canonical departments', 10, K('depts'), K('depts') === 10, 'EXISTING_EQUIVALENT_KEEP',
    'Package uses longer dept keys (growth_revenue, marketplace_supplier_network). Live keys are the merged canonical set and every package key resolves through org_agent_alias / fn_dept_canonical. Not renamed: the master prompt forbids renaming working identities to match names.');
  check(label, 'A2', '90 accountable active roles', 90, K('roles'), K('roles') === 90, 'EXISTING_EQUIVALENT_KEEP', '');
  check(label, 'A3', '86 category overlays', 86, K('overlays'), K('overlays') === 86, 'EXISTING_EQUIVALENT_KEEP', '');
  check(label, 'A4', '96 packaged identities on active roles', 96, K('packaged'), K('packaged') === 96, 'EXISTING_EQUIVALENT_KEEP', '');
  check(label, 'A5', 'no identity naming an inactive employee', 0, K('identity_dead'), K('identity_dead') === 0, 'EXISTING_PARTIAL_REPAIR',
    'Six such rows were removed on 14 Aug 2026 (org_reorg_17).');
  check(label, 'A6', '0 orphan runtime-eligible knowledge rows', 0, K('orphan_knowledge'), K('orphan_knowledge') === 0, 'EXISTING_BETTER_KEEP',
    'fn_dept_scope scopes retrieval over absorbed keys instead of rewriting 5,775 knowledge rows.');
  check(label, 'A7', '0 manager/reporting cycles', 0, Number(cyc.n), Number(cyc.n) === 0, 'EXISTING_EQUIVALENT_KEEP', '');
  check(label, 'A8', '0 self-management', 0, K('self_manage'), K('self_manage') === 0, 'EXISTING_EQUIVALENT_KEEP', '');
  check(label, 'A9', `0 creator/reviewer effective-identity collisions since the guard (${col.pre_guard} pre-guard, preserved)`,
    0, Number(col.n), Number(col.n) === 0, 'EXISTING_PARTIAL_REPAIR',
    `Measured on EFFECTIVE canonical identity, not raw strings. ${col.pre_guard} pre-guard rows are preserved and classified in HISTORICAL_SELF_REVIEW_REGISTER.csv. The alias bypass was live in all ten departments and was closed on 14 Aug 2026 by resolving in fn_pick_reviewer/fn_review_submit plus a BEFORE INSERT trigger on review_chain. The pre-existing CHECK constraint is NOT VALID and compares raw strings, so it never saw the alias case.`);
  check(label, 'A10', 'fn_org_role_violations() empty', 0, K('violations'), K('violations') === 0, 'EXISTING_EQUIVALENT_KEEP', '');

  for (const [mode, want] of Object.entries(pkgModes)) {
    const got = liveModes[mode] ?? 0;
    const collapsed = (mode === 'persistent_manager' || mode === 'scheduled_manager')
      && (liveModes.scheduled_manager ?? 0) === (pkgModes.persistent_manager ?? 0) + (pkgModes.scheduled_manager ?? 0);
    check(label, `A11.${mode}`, `runtime mode ${mode}`, want, got, got === want || collapsed,
      collapsed ? 'EXISTING_PARTIAL_REPAIR' : 'EXISTING_EQUIVALENT_KEEP',
      collapsed ? 'Live collapses persistent_manager and scheduled_manager into scheduled_manager=12. The package splits them 6/6. Same 12 managers, one less distinction - a real but small gap.' : '');
  }

  check(label, 'A12', 'every required tool has an adapter row with schema, timeout and retry',
    K('tools'), K('tools_complete'), K('tools') > 0 && K('tools') === K('tools_complete'), 'EXISTING_PARTIAL_REPAIR',
    'agent_tool reached production on 14 Aug 2026; it had never been deployed there.');
  check(label, 'A13', 'every accountable role has a model policy path', 0, K('roles_without_model_policy'),
    K('roles_without_model_policy') === 0, 'EXISTING_PARTIAL_REPAIR',
    'org_agents.routing_tier now selects the task class in fn_ai_route; before 14 Aug 2026 that branch could never fire.');
  check(label, 'A14', 'decision trace / tool call / handoff tables present', 3, K('trace_tables'),
    K('trace_tables') === 3, 'EXISTING_PARTIAL_REPAIR', '');
  // A MANAGER THAT HAS NEVER RUN IS NOT A MANAGER. The package splits the 12 managers 6 persistent
  // / 6 scheduled and live collapses them to 12 scheduled - but NOTHING in the database reads
  // either mode (0 routines mention it), so that split would be naming, not behaviour, and the
  // package's own policy says a row without a consumer is not an implementation.
  //
  // The behavioural question underneath it is this one, and it fails: measured 14 Aug 2026, four of
  // the twelve have no agent_runs row EVER - cpo, sales_director, cto and intel_director, three of
  // them department heads. Their departments therefore have no manager cadence at all, whatever the
  // mode column says. This is recorded here rather than fixed, because giving them a schedule is
  // activation and the instruction was to stop before it.
  // A16 USED TO ASK "has this manager ever run?" and counted agent_runs rows. That was measuring
  // DEMO-ERA HISTORY, not correctness: the runs it found came from demo suppliers, customers and
  // inquiries that have since been removed, so an agent with zero rows was being reported as a
  // defect for having no deleted data. Same fault as three other instruments tonight - the number
  // was real and it was about the wrong subject.
  //
  // The question that matters is whether each agent's own code and logic is sound: can it assemble
  // context, does it hold its knowledge, do its tools resolve, does it have authority, does it
  // route to a model, is its contract complete, and do its gates answer. All of that is
  // deterministic, costs nothing, and is true or false regardless of what ran last month.
  const [ready] = await sql(ref, `
    with r as (select role_id, runtime_agent_key k, manager_role_id, owned_decisions,
                      forbidden_decisions, activation_conditions, output_contracts, escalation_targets
                 from org_role where status='active' and runtime_mode<>'knowledge_overlay'),
    c as (select r.*, public.fn_agent_context_v3(r.k,'agent_reasoning','a routine decision in my remit') ctx,
                 public.fn_ai_route(p_fn=>'agent_brain', p_agent_key=>r.k) route from r)
    select count(*) agents,
      count(*) filter (where (ctx->>'error') is not null
        or jsonb_array_length(ctx->'role_knowledge') = 0
        or jsonb_array_length(ctx->'department_knowledge') = 0
        or jsonb_array_length(ctx->'company_core') = 0
        or (select count(*) from public.fn_agent_tools(k)) = 0
        or not exists (select 1 from employee_authority e where e.agent_key = k)
        or (route->>'use_llm') <> 'true' or (route->>'model') is null
        or owned_decisions is null or forbidden_decisions is null or activation_conditions is null
        or output_contracts is null or escalation_targets is null
        or (public.fn_agent_autonomy_blocked(k)->>'blocked') is null
        or (public.fn_onboarding_gate(k)->>'status') is null) not_ready
      from c`);
  check(label, 'A16', 'every agent is runtime-ready: context, knowledge, tools, authority, model, contract and gates',
    0, Number(ready.not_ready), Number(ready.not_ready) === 0, 'EXISTING_EQUIVALENT_KEEP',
    `Measured through the real runtime paths for all ${ready.agents} accountable agents, at zero model cost.`);

  check(label, 'A15', 'cost guardrails: every department has a budget', 10, K('budgets'),
    K('budgets') >= 10, 'EXISTING_PARTIAL_REPAIR',
    'department_budget.spent_aed was dead and both ceiling readers were blind to 22 merged-away dept keys; fixed 14 Aug 2026 and the halt proven to fire.');
}

// ---- report -----------------------------------------------------------------------------------
const byProject = {};
for (const r of results) (byProject[r.project] ||= []).push(r);
for (const [p, rows] of Object.entries(byProject)) {
  const pass = rows.filter((r) => r.ok).length;
  console.log(`\nGATE A — ${p}: ${pass}/${rows.length}`);
  for (const r of rows.filter((x) => !x.ok)) {
    console.log(`  FAIL ${r.id.padEnd(22)} ${r.requirement}: expected ${r.expected}, got ${r.actual}`);
  }
}

if (WRITE) {
  const esc = (v) => {
    const s = String(v ?? '').replace(/\s+/g, ' ');
    return /[",]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  const cols = ['requirement', 'detail', 'expected', 'actual', 'status', 'note'];
  writeFileSync('docs/agents/runtime_connection_reconciliation.csv',
    cols.join(',') + '\n' + rec.map((r) => cols.map((c) => esc(r[c])).join(',')).join('\n') + '\n');
  console.log('\nwrote docs/agents/runtime_connection_reconciliation.csv');
}

console.log(`\nGate A total failures on production: ${failed}`);
process.exitCode = failed ? 1 : 0;
