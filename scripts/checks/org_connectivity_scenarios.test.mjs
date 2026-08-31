// THE ORG CONNECTIVITY IS CORRECT UNDER PRESSURE — ADVERSARIAL SCENARIOS, ZERO PAID INFERENCE.
//
// The companion to org_connectivity_signal_path.test.mjs. That file proves the happy path travels;
// this one proves the org REFUSES what a real company must refuse, and that the connectivity
// properties hold ACROSS THE WHOLE ESTATE (every role, every department) — not in one example.
//
// Every write is an aborted-transaction probe (a DO block that RAISEs its measurements and rolls
// back), so it asserts on a real fired signal AND a real non-zero effect while leaving zero residue.
// No model is called; nothing goes outbound. Verified after authoring: 0 residue on production.
//
//   node scripts/checks/org_connectivity_scenarios.test.mjs
import { readFileSync, existsSync } from 'node:fs';
const PROD = 'htdblwldjkcgjvmqkbeh';
const LOCAL = 'C:/Users/Opera/.supabase/access-token';
const token = (process.env.SUPABASE_ACCESS_TOKEN || (existsSync(LOCAL) ? readFileSync(LOCAL, 'utf8') : '')).trim();
if (!token) { console.log('SKIPPED: no management token, so this asserted nothing.'); process.exit(0); }

const q = async (text, attempt = 0) => {
  const r = await fetch(`https://api.supabase.com/v1/projects/${PROD}/database/query`, {
    method: 'POST', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: text }),
  });
  const b = await r.text();
  if ((r.status === 429 || r.status >= 500) && attempt < 7) {
    await new Promise((res) => setTimeout(res, Math.min(2000 * 2 ** attempt, 60000)));
    return q(text, attempt + 1);
  }
  if (!r.ok) throw new Error(`HTTP ${r.status}: ${b.slice(0, 900)}`);
  return JSON.parse(b);
};
// A probe RAISEs 'MARK|k=v|...'; run it, expect it to throw, return the parsed fields.
const probe = async (sql) => {
  try { await q(sql); return { __error: 'probe did not raise — it must always abort' }; }
  catch (e) {
    const t = String(e.message); const i = t.indexOf('MARK|');
    if (i < 0) return { __error: t.slice(0, 300) };
    const seg = t.slice(i + 5).split(/\\n|CONTEXT|"/)[0].trim();
    const out = {}; for (const kv of seg.split('|')) { const j = kv.indexOf('='); if (j > 0) out[kv.slice(0, j)] = kv.slice(j + 1); }
    return out;
  }
};

let fail = 0;
const eq = (label, got, want) => { const ok = String(got) === String(want); if (!ok) fail++;
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${label.padEnd(64)} ${got}${ok ? '' : `  (expected ${want})`}`); };

const HB = `'from_dept','legal','accountable_owner','compliance_mgr','to_dept','finance','to_role','ap specialist',
  'purpose','Reconcile the August vendor ledger against the bank feed',
  'requested_action','Match every invoice to a purchase order and flag any gap over 5 percent',
  'escalation_conditions','if the mismatch exceeds five percent of the month',
  'deadline',(now()+interval '3 days')::text,
  'closure_criteria', jsonb_build_array('ledger reconciled'),
  'evidence', jsonb_build_array(jsonb_build_object('note','prior period reconciled')),
  'acceptance_criteria', jsonb_build_array('scope is clear')`;

// ============================================================================================
console.log('\n== ORG-WIDE INVARIANTS (every role, every department — not one example) ==');
// ============================================================================================
const inv = await q(`
  with dep as (select dept_key, lead_agent from org_departments where active),
  ag as (select agent_key, department, active, manager_key from org_agents where active),
  esc as (select r.role_id, t as target, fn_org_role_resolve(t) resolved
          from org_role r, lateral unnest(coalesce(r.escalation_targets,'{}'::text[])) t where r.status='active')
  select k,v,e from (
    select 1 ord,'active_departments' k,(select count(*)::text from dep) v,'10' e
    union all select 2,'agents_without_manager_is_apex_only',(select count(*)::text from ag where manager_key is null),'1'
    union all select 3,'the_apex_is_ceo',(select string_agg(agent_key,',') from ag where manager_key is null),'ceo'
    union all select 4,'agents_managed_by_inactive_or_missing',(select count(*)::text from ag a where a.manager_key is not null and not exists(select 1 from org_agents m where m.agent_key=coalesce(fn_org_agent_resolve(a.manager_key),a.manager_key) and m.active)),'0'
    union all select 5,'agents_self_managed',(select count(*)::text from ag a where a.manager_key is not null and coalesce(fn_org_agent_resolve(a.manager_key),a.manager_key)=a.agent_key),'0'
    union all select 6,'departments_with_no_active_employee',(select count(*)::text from dep d where not exists(select 1 from ag a where a.department=d.dept_key)),'0'
    union all select 7,'departments_without_a_medium_approver',(select count(*)::text from dep d where (fn_action_resolve_approver(d.dept_key,'medium')->>'approver') is null),'0'
    union all select 8,'departments_without_a_high_approver',(select count(*)::text from dep d where (fn_action_resolve_approver(d.dept_key,'high')->>'approver') is null),'0'
    union all select 9,'founder_reserved_action_classes',(select count(*)::text from org_action_executor where required_authority='founder'),'1'
    union all select 10,'the_founder_class_is_refund',(select string_agg(action_class,',') from org_action_executor where required_authority='founder'),'refund_within_window'
    union all select 11,'ceo_escalates_to_founder',(fn_should_escalate('{"actor":"ceo","confidence":0.1}'::jsonb)->>'route_to'),'founder'
    union all select 12,'only_the_ceo_points_at_the_founder',(select count(distinct role_id)::text from esc where target='founder'),'1'
    union all select 13,'escalation_self_edges',(select count(*)::text from esc where resolved=role_id),'0'
    union all select 14,'escalation_dead_internal_edges',(select count(*)::text from esc where target<>'founder' and target not ilike 'external%' and resolved is null),'0'
    union all select 15,'unsafe_escalation_classes_without_an_active_owner',(select count(*)::text from unsafe_class u where not exists(select 1 from org_agents a where a.agent_key=(fn_unsafe_escalation_route(u.class_key,null)->>'route_to') and a.active)),'0'
    union all select 16,'revenue_objective_aed',(fn_objective_cascade()->>'revenue_objective_aed'),'1000000'
    union all select 17,'department_objectives_with_a_dangling_goal_key',(select count(*)::text from department_objective o where coalesce(o.goal_key,'')<>'' and o.active and not exists(select 1 from company_goals g where g.key=o.goal_key and g.active)),'0'
    union all select 18,'cascadeable_goals_missing_their_objective',(select count(*)::text from company_goals g where g.active and coalesce(g.measure_sql,'')<>'' and exists(select 1 from org_departments d where d.dept_key=g.owner_dept and d.active) and not exists(select 1 from department_objective o where o.goal_key=g.key and o.active)),'0'
  ) z order by ord`);
for (const r of inv) eq(r.k, r.v, r.e);

// ============================================================================================
console.log('\n== MESSAGING — the handoff refuses what a real company must refuse ==');
// ============================================================================================
// to a department that exists but has NO active employee
const h1 = await probe(`do $p$ declare r jsonb; begin
  r := fn_handoff_open(jsonb_build_object(${HB}) || jsonb_build_object('to_dept','ai_dept','to_role','ai specialist'));
  raise exception 'MARK|ok=%|reason=%',(r->>'ok'),(r->>'reason'); end $p$;`);
eq('handoff to an empty department is refused', h1.ok, 'false');
eq('  -> reason', h1.reason, 'receiving department has no active employee to accept it');
// to an unknown department
const h2 = await probe(`do $p$ declare r jsonb; begin
  r := fn_handoff_open(jsonb_build_object(${HB}) || jsonb_build_object('to_dept','zz_no_such_dept'));
  raise exception 'MARK|ok=%|reason=%',(r->>'ok'),(r->>'reason'); end $p$;`);
eq('handoff to an unknown department is refused', h2.ok, 'false');
eq('  -> reason', h2.reason, 'unknown receiving department');
// accountable owner not a member of the originating department
const h3 = await probe(`do $p$ declare r jsonb; begin
  r := fn_handoff_open(jsonb_build_object(${HB}) || jsonb_build_object('accountable_owner','ap_specialist'));
  raise exception 'MARK|ok=%|reason=%',(r->>'ok'),(r->>'reason'); end $p$;`);
eq('handoff whose owner is not in the from-dept is refused', h3.ok, 'false');
eq('  -> reason', h3.reason, 'accountable owner does not belong to the originating department');
// an incomplete contract
const h4 = await probe(`do $p$ declare r jsonb; begin
  r := fn_handoff_open(jsonb_build_object('from_dept','legal','accountable_owner','compliance_mgr',
       'to_dept','finance','to_role','ap specialist','purpose','short','requested_action','tiny','escalation_conditions','if x'));
  raise exception 'MARK|ok=%|reason=%',(r->>'ok'),(r->>'reason'); end $p$;`);
eq('an incomplete handoff contract is refused', h4.ok, 'false');
eq('  -> reason', h4.reason, 'the handoff contract is not complete enough to open');
// accept by an agent not in the receiving department
const h5 = await probe(`do $p$ declare o jsonb; a jsonb; begin
  o := fn_handoff_open(jsonb_build_object(${HB}));
  a := fn_handoff_respond((o->>'id')::bigint, 'compliance_mgr', 'accept');  -- compliance_mgr is legal, not finance
  raise exception 'MARK|open_ok=%|accept_ok=%|reason=%',(o->>'ok'),(a->>'ok'),(a->>'reason'); end $p$;`);
eq('accept by a non-member of the receiving dept is refused', h5.accept_ok, 'false');
eq('  -> reason', h5.reason, 'only an active employee of the receiving department may answer');
// close without proof of the closure criteria
const h6 = await probe(`do $p$ declare o jsonb; recv text; a jsonb; cl jsonb; begin
  o := fn_handoff_open(jsonb_build_object(${HB})); recv := o->>'receiving_agent';
  a := fn_handoff_respond((o->>'id')::bigint, recv, 'accept');
  cl := fn_handoff_close((o->>'id')::bigint, recv, '[]'::jsonb);   -- no closure evidence
  raise exception 'MARK|accept_ok=%|close_ok=%|reason=%',(a->>'ok'),(cl->>'ok'),(cl->>'reason'); end $p$;`);
eq('close without recorded proof is refused', h6.close_ok, 'false');
eq('  -> reason', h6.reason, 'closure criteria without recorded proof');
// idempotency: the same handoff opened twice returns the same one, not a second contract
const h7 = await probe(`do $p$ declare o1 jsonb; o2 jsonb; begin
  o1 := fn_handoff_open(jsonb_build_object(${HB}));
  o2 := fn_handoff_open(jsonb_build_object(${HB}));
  raise exception 'MARK|first_ok=%|second_duplicate=%|same_id=%',
    (o1->>'ok'), (o2->>'duplicate'), ((o1->>'id')=(o2->>'id'))::text; end $p$;`);
eq('a duplicate handoff is deduplicated, not doubled', h7.second_duplicate, 'true');
eq('  -> returns the same contract id', h7.same_id, 'true');

// ============================================================================================
console.log('\n== APPROVAL — refunds are founder-only; the wrong things cannot be approved ==');
// ============================================================================================
// a refund can NEVER be approved by any AI — not a head, not the CEO
const a1 = await probe(`do $p$ declare v_id uuid; s jsonb; inv text; ceo_try text; head_try text; begin
  insert into action_execution (correlation_id,action_class,executor,idempotency_key,risk_tier,reversible,request,status)
  values (gen_random_uuid(),'refund_within_window','refund_within_window','probe-'||gen_random_uuid()::text,'high',false,'{}'::jsonb,'queued') returning id into v_id;
  s := fn_action_invoke_dispatch(50); select response->>'invoker' into inv from action_execution where id=v_id;
  begin perform fn_action_head_approve(v_id,'approved','x','ceo'); ceo_try:='NOT_REFUSED'; exception when others then ceo_try:='REFUSED'; end;
  begin perform fn_action_head_approve(v_id,'approved','x','cfo'); head_try:='NOT_REFUSED'; exception when others then head_try:='REFUSED'; end;
  raise exception 'MARK|dispatch=%|parked_for_head=%|ceo=%|head=%', inv,(inv='awaiting_head_approval')::text,ceo_try,head_try; end $p$;`);
eq('a refund is refused by the dispatcher (never parked for a head)', a1.dispatch, 'refused');
eq('  -> not routed to any AI head', a1.parked_for_head, 'false');
eq('  -> the CEO cannot approve a refund', a1.ceo, 'REFUSED');
eq('  -> a department head cannot approve a refund', a1.head, 'REFUSED');
// a non-entitled approver is refused; the entitled head approves and it dispatches
const a2 = await probe(`do $p$ declare v_id uuid; s1 jsonb; s2 jsonb; ap record; inv1 text; inv2 text; wrong text; begin
  insert into action_execution (correlation_id,action_class,executor,idempotency_key,risk_tier,reversible,request,status)
  values (gen_random_uuid(),'supplier_verify','supplier_verify','probe-'||gen_random_uuid()::text,'medium',true,'{}'::jsonb,'queued') returning id into v_id;
  s1 := fn_action_invoke_dispatch(50); select response->>'invoker' into inv1 from action_execution where id=v_id;
  select * into ap from action_approval where action_execution_id=v_id;
  begin perform fn_action_head_approve(v_id,'approved','x','cfo'); wrong:='NOT_REFUSED'; exception when others then wrong:='REFUSED'; end;
  perform fn_action_head_approve(v_id,'approved','x','procurement');
  s2 := fn_action_invoke_dispatch(50); select response->>'invoker' into inv2 from action_execution where id=v_id;
  raise exception 'MARK|parked=%|approver=%|wrong=%|dispatched=%', inv1, ap.accountable_approver, wrong, inv2; end $p$;`);
eq('a consequential action parks for the accountable head', a2.parked, 'awaiting_head_approval');
eq('  -> entitled approver (marketplace/medium)', a2.approver, 'procurement');
eq('  -> a non-entitled approver is refused', a2.wrong, 'REFUSED');
eq('  -> the entitled head approves and it dispatches onward', a2.dispatched, 'dispatched');
// an irreversible action with no compensation cannot be dispatched at all
const a3 = await probe(`do $p$ declare v_id uuid; s jsonb; inv text; cls text; begin
  select action_class into cls from org_action_executor where kind='edge' and active and not reversible and compensation_action_class is null limit 1;
  insert into action_execution (correlation_id,action_class,executor,idempotency_key,risk_tier,reversible,request,status)
  values (gen_random_uuid(),cls,cls,'probe-'||gen_random_uuid()::text,'medium',false,'{}'::jsonb,'queued') returning id into v_id;
  s := fn_action_invoke_dispatch(50); select response->>'invoker' into inv from action_execution where id=v_id;
  raise exception 'MARK|class=%|invoker=%', cls, inv; end $p$;`);
eq('an irreversible-no-compensation action is refused (never dispatched)', a3.invoker, 'refused');

// ============================================================================================
console.log('\n== CASCADE — a measurable target hands down; an unmeasurable one cannot ==');
// ============================================================================================
// positive: a new measurable target cascades to a department objective at once
const c1 = await probe(`do $p$ declare before int; after int; d text; begin
  select count(*) into before from department_objective where goal_key='zz_probe_measurable';
  insert into company_goals (key,goal,category,metric,target_value,unit,owner_dept,horizon,active,measure_sql,direction)
  values ('zz_probe_measurable','ZZ measurable probe','Financial','revenue',500000,'AED','finance','year_1',true,'select 0','at_least');
  select count(*), max(dept_key) into after, d from department_objective where goal_key='zz_probe_measurable' and active;
  raise exception 'MARK|before=%|after=%|dept=%', before, after, d; end $p$;`);
eq('a new measurable target cascades to a department objective', c1.after, '1');
eq('  -> owned by the right department', c1.dept, 'finance');
// negative: a goal with NO measure cannot cascade (it would be untrackable)
const c2 = await probe(`do $p$ declare after int; begin
  insert into company_goals (key,goal,category,metric,target_value,unit,owner_dept,horizon,active,measure_sql,direction)
  values ('zz_probe_nomeasure','ZZ no-measure probe','Financial','revenue',500000,'AED','finance','year_1',true,'','at_least');
  select count(*) into after from department_objective where goal_key='zz_probe_nomeasure' and active;
  raise exception 'MARK|after=%', after; end $p$;`);
eq('a goal with no measure does NOT cascade (correctly)', c2.after, '0');
// assignment fills the department and never breaks its own rules
const c3 = await probe(`do $p$ declare res jsonb; cross_dept int; over_cap int; begin
  res := fn_org_task_assign(500);
  select count(*) into cross_dept from org_tasks t join org_agents a on a.agent_key=t.assigned_agent
    where t.status in ('assigned','in_progress') and a.department is distinct from t.dept_key;
  select count(*) into over_cap from (select a.agent_key from org_agents a where a.active
    group by a.agent_key having (select count(*) from org_tasks o where o.assigned_agent=a.agent_key and o.status in ('assigned','in_progress'))
      > coalesce((select max_open_tasks from org_agents x where x.agent_key=a.agent_key),6)) z;
  raise exception 'MARK|assigned=%|cross_dept=%|over_cap=%', (res->>'assigned'), cross_dept, over_cap; end $p$;`);
eq('a sweep assigns tasks and never crosses a department boundary', c3.cross_dept, '0');
eq('  -> and never exceeds any agent\u2019s capacity', c3.over_cap, '0');

console.log(`\n${fail === 0 ? 'PASS' : 'FAIL'} — ${fail} assertion(s) failed`);
process.exit(fail ? 1 : 0);
