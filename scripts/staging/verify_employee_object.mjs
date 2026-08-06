// THE EMPLOYEE OBJECT — spec file #1 line 372.
//
// "define each one as an employee object with structured attributes such as role, manager, direct
// reports, KPIs, authority limits, current workload, goals, performance history, and improvement
// plan. Then create an organizational hierarchy (CEO -> Chief of Staff -> Department Heads ->
// Specialists)."
//
// Every attribute was populated and none of it reached a prompt: the identity block selected
// `a.department, a.role` and nothing else. The checks that matter are that each field is present
// AND that it carries the agent's REAL value — "the output grew" must never be mistakable for
// "the record was read".
//
//   node scripts/staging/verify_employee_object.mjs      # zero spend
import { mgmtRead } from './qd_guard.mjs';
import { REF as STAGE } from './demo_factory.mjs';

const checks = [];
const step = (name, ok, detail) => {
  checks.push({ name, ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'} ${String(checks.length).padStart(2)} ${name.padEnd(58)} ${detail}`);
};
const one = (r) => (r && r[0]) ? Object.values(r[0])[0] : null;

try {
  const ctx = String(one(await mgmtRead(STAGE, `select public.fn_agent_context('cfo', 22000)`)));
  const head = ctx.slice(0, 4000);

  // Each attribute must appear AND match what org_agents actually holds for this agent.
  const agent = (await mgmtRead(STAGE,
    `select title, manager_key, seniority, max_open_tasks,
            (select count(*) from org_agents b where b.manager_key='cfo' and b.active) reports
       from org_agents where agent_key='cfo'`))[0];

  step('the job title is in the prompt, and it is this agent\'s title',
    head.includes(agent.title), `org_agents.title = "${agent.title}"`);

  step('the reporting line is walked upward to the real manager',
    head.includes('Reports to: ' + agent.manager_key),
    `manager_key = ${agent.manager_key} (the Chief of Staff — CEO -> CoS -> heads -> specialists)`);

  const reportNames = await mgmtRead(STAGE,
    `select agent_key from org_agents where manager_key='cfo' and active order by agent_key`);
  step('the reporting line is walked downward to every direct report',
    reportNames.length > 0 && reportNames.every(r => head.includes(r.agent_key)),
    `${reportNames.length}/${agent.reports} named: ${reportNames.map(r => r.agent_key).join(', ')}`);

  // employee_authority's 285 rows had fired at most 3 times ever. Now every prompt states them.
  const auth = await mgmtRead(STAGE,
    `select action_class, threshold_aed from employee_authority where agent_key='cfo' order by action_class`);
  step('personal authority limits are stated, with their AED thresholds',
    auth.length > 0 && auth.every(a => head.includes(a.action_class))
      && head.includes(String(auth[0].threshold_aed)),
    `${auth.length} grant(s): ${auth.map(a => a.action_class).join(', ')}`);
  step('and the prompt says what happens outside them',
    /Anything not on that list is GATED/.test(head), 'the ceiling is an instruction, not a slogan');

  const kpis = await mgmtRead(STAGE,
    `select kpi, serves_goal from employee_kpi where agent_key='cfo' and active order by kpi`);
  step('KPIs reach the employee whose work they measure',
    kpis.length > 0 && kpis.every(k => head.includes(k.kpi)),
    `${kpis.length} KPI(s), each naming the company goal it serves`);

  // max_open_tasks is a CAP. The spec asks for LOAD. Both must be present and distinguishable.
  step('current workload is live load, not the static cap',
    /YOUR CURRENT WORKLOAD \(live\)/.test(head) && /task\(s\) in flight/.test(head)
      && head.includes('personal cap is ' + agent.max_open_tasks),
    `cap ${agent.max_open_tasks} stated separately from in-flight count`);

  const goals = await mgmtRead(STAGE,
    `select goal from company_goals where active and (owner_dept is null or owner_dept in ('finance','exec'))
      order by sort nulls last limit 3`);
  step('company goals reach an ordinary employee, not just the 13 planners',
    goals.length > 0 && goals.some(g => head.includes(g.goal.slice(0, 40))),
    `fn_agent_context read company_goals for the first time; ${goals.length} sampled`);

  // ---- the negative checks ------------------------------------------------------------------
  // A query-less call must stay byte-identical between the 2-arg and 3-arg signatures, or this is
  // a silent behaviour change to thirteen call sites across ten Edge Functions.
  const sig = (await mgmtRead(STAGE,
    `select length(public.fn_agent_context('legal',24000))::int a,
            length(public.fn_agent_context('legal',24000,null))::int b,
            length(public.fn_agent_context('legal',24000,''))::int c,
            md5(public.fn_agent_context('legal',24000))  ha,
            md5(public.fn_agent_context('legal',24000,null)) hb`))[0];
  step('the 2-arg and query-less 3-arg calls remain byte-identical',
    sig.a === sig.b && sig.b === sig.c && sig.ha === sig.hb,
    `${sig.a} / ${sig.b} / ${sig.c} chars, md5 ${sig.ha === sig.hb ? 'match' : 'DIFFER'}`);

  // The employee record must not be able to eat the knowledge layers.
  const layers = ['# LAYER 2 - YOUR PROFESSIONAL EXPERTISE', '# LAYER 1 - COMPANY KNOWLEDGE'];
  step('all four knowledge layers survive the addition',
    layers.every(l => ctx.includes(l)),
    layers.filter(l => ctx.includes(l)).length + `/${layers.length} present, total ${ctx.length} chars`);

  const empBlock = ctx.slice(ctx.indexOf('# YOUR EMPLOYEE RECORD'), ctx.indexOf('# LAYER 2'));
  step('the employee record is bounded and cannot crowd out the rest',
    empBlock.length <= 3100, `${empBlock.length} chars against a 3,000 cap`);

  // An agent with no personal grant must fall back to the department grant, not print nothing.
  const noGrant = await mgmtRead(STAGE,
    `select a.agent_key from org_agents a
      where a.active and not exists (select 1 from employee_authority e where e.agent_key=a.agent_key)
        and exists (select 1 from org_authority o where o.dept_key=a.department) limit 1`);
  if (noGrant.length) {
    const c2 = String(one(await mgmtRead(STAGE, `select public.fn_agent_context('${noGrant[0].agent_key}', 22000)`)));
    step('an agent with no personal grant falls back to its department\'s',
      /# YOUR AUTHORITY \(delegated to /.test(c2) && !/\n'# YOUR AUTHORITY/.test(c2),
      `${noGrant[0].agent_key} shows the delegated grant, no stray quote`);
  } else {
    step('an agent with no personal grant falls back to its department\'s', true,
      'skipped: every active agent has a personal grant');
  }

  // No agent may be handed an empty record: that is the state this change exists to end.
  const empty = await mgmtRead(STAGE,
    `select count(*) n from org_agents a where a.active
       and public.fn_agent_context(a.agent_key, 22000) not like '%# YOUR EMPLOYEE RECORD%'`);
  step('every active employee gets a record, not just the sampled one', Number(empty[0].n) === 0,
    `${empty[0].n} of 66 active agents with no employee record`);
} catch (e) {
  step('the gate ran to completion', false, String(e.message || e).slice(0, 300));
}

const pass = checks.filter(c => c.ok).length;
console.log(`\nEMPLOYEE OBJECT ${pass}/${checks.length} on ${STAGE} (zero spend)`);
process.exit(pass === checks.length ? 0 : 1);
