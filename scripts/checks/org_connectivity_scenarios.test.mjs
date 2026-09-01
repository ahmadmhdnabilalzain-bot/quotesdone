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
    -- ONLY REFUNDS REACH THE FOUNDER. The old agent_actions queue must route nothing to him, and
    -- every decision/alert it does route must land on a live accountable authority.
    union all select 19,'agent_action_kinds_routing_to_founder',(select count(*)::text from agent_action_kind_policy where policy='founder'),'0'
    union all select 20,'officer_notify_kinds_without_a_live_authority',(select count(*)::text from agent_action_kind_policy p where p.policy in ('officer','notify') and not exists(select 1 from org_role r join org_agents a on a.agent_key=r.runtime_agent_key and a.active where r.role_id=p.authority_role and r.status='active')),'0'
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
  values (gen_random_uuid(),'supplier_verify','supplier_verify','probe-'||gen_random_uuid()::text,'medium',true,jsonb_build_object('actor','cfo'),'queued') returning id into v_id;
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

// spend/contract needs TWO independent approvals: a head AND the named second authority.
const a4 = await probe(`do $p$ declare v_id uuid; a1 jsonb; a2 jsonb; inv1 text; inv2 text; wrong text; gate boolean; begin
  update org_action_executor set second_authority='legal' where action_class='supplier_verify';
  insert into action_execution (correlation_id,action_class,executor,idempotency_key,risk_tier,reversible,request,status)
  values (gen_random_uuid(),'supplier_verify','supplier_verify','probe-'||gen_random_uuid()::text,'medium',true,jsonb_build_object('actor','cfo'),'queued') returning id into v_id;
  perform fn_action_invoke_dispatch(50); select response->>'invoker' into inv1 from action_execution where id=v_id;
  a1 := fn_action_head_approve(v_id,'approved','head ok',null);
  begin perform fn_action_head_approve(v_id,'approved','x','cfo'); wrong:='NOT_REFUSED'; exception when others then wrong:='REFUSED'; end;
  perform fn_action_invoke_dispatch(50); select response->>'invoker' into inv2 from action_execution where id=v_id;
  a2 := fn_action_head_approve(v_id,'approved','second ok','legal');
  select (approval_decision='approved' and consumed_at is null and (second_authority is null or second_approval_decision='approved'))
    into gate from action_approval where action_execution_id=v_id;
  raise exception 'MARK|parked=%|head=%|nonentitled=%|after_one=%|second=%|gate=%',
    inv1, a1->>'role', wrong, inv2, a2->>'role', gate::text; end $p$;`);
eq('a spend/contract action parks for TWO approvals', a4.parked, 'awaiting_two_approvals');
eq('  -> the department head records the first', a4.head, 'head');
eq('  -> a neither-head-nor-second approver is refused', a4.nonentitled, 'REFUSED');
eq('  -> one approval is not enough to dispatch', a4.after_one, 'awaiting_two_approvals');
eq('  -> the independent second records the second', a4.second, 'second_authority');
eq('  -> only both approvals open the dispatch gate', a4.gate, 'true');

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

// ============================================================================================
console.log('\n== ONLY REFUNDS REACH THE FOUNDER — decisions route to officers, alerts notify ==');
// ============================================================================================
// a genuine major-issue ALERT notifies the founder (Stage 4) and is handed to the accountable
// authority, WITHOUT ever entering his blocking queue.
const f1 = await probe(`do $p$ declare aid bigint; fa0 int; fa1 int; new_agent text; q0 int; q1 int; begin
  select count(*) into fa0 from founder_alerts;
  q0 := (fn_founder_queue(5)->>'waiting_on_you_total')::int;
  insert into agent_actions(agent,kind,status,risk,title,recommendation)
    values('cfo','security_incident','pending','high','ZZ probe — a real alert','probe body') returning id into aid;
  perform fn_agent_action_work_sweep(50);
  select count(*) into fa1 from founder_alerts;
  select agent into new_agent from agent_actions where id=aid;
  q1 := (fn_founder_queue(5)->>'waiting_on_you_total')::int;
  raise exception 'MARK|notified=%|routed_to=%|queue_delta=%', (fa1>fa0)::text, new_agent, (q1-q0); end $p$;`);
eq('a major-issue alert notifies the founder (Stage 4)', f1.notified, 'true');
eq('  -> and is handed to the accountable authority', f1.routed_to, 'cto');
eq('  -> and never enters his blocking queue', f1.queue_delta, '0');
// an officer DECISION is re-addressed to the accountable authority, not the founder
const f2 = await probe(`do $p$ declare aid bigint; new_agent text; begin
  insert into agent_actions(agent,kind,status,risk,title,recommendation)
    values('cfo','finance_marketing_budget','pending','medium','ZZ probe — a budget decision','probe body') returning id into aid;
  perform fn_agent_action_work_sweep(50);
  select agent into new_agent from agent_actions where id=aid;
  raise exception 'MARK|routed_to=%', new_agent; end $p$;`);
eq('an officer decision routes to the accountable AI authority', f2.routed_to, 'sales_director');
// the schema itself now refuses to put a non-refund kind in front of the founder
const f3 = await probe(`do $p$ declare refused text; begin
  begin insert into agent_action_kind_policy(kind,policy) values('zz_probe_kind','founder'); refused:='NOT_REFUSED';
  exception when others then refused:='REFUSED'; end;
  raise exception 'MARK|refused=%', refused; end $p$;`);
eq('the policy CHECK refuses a founder-routed kind (structural)', f3.refused, 'REFUSED');

// ============================================================================================
console.log('\n== LEARNING LOOP — a missed KPI opens remediation; training feeds learning_speed ==');
// ============================================================================================
// "We missed the target — now what?" A missed KPI opens a remediation against the responsible
// employee and queues fresh practice; a non-employee owner cannot carry one (the FK), so it is
// skipped rather than crashing the whole review.
const l1 = await probe(`do $p$ declare res jsonb; orphan int; begin
  res := fn_kpi_review();
  select count(*) into orphan from agent_remediation ar
   where ar.failure_class='kpi_miss'
     and not exists (select 1 from org_agents o where o.agent_key=ar.agent_key and o.active);
  raise exception 'MARK|missed=%|remediations=%|practice=%|orphan=%',
    res->>'missed', res->>'remediations_opened', res->>'practice_assigned', orphan; end $p$;`);
eq('a missed KPI opens a remediation', Number(l1.remediations) > 0 ? 'yes' : 'no', 'yes');
eq('  -> and queues practice for the employee', Number(l1.practice) > 0 ? 'yes' : 'no', 'yes');
eq('  -> never opened against a non-employee', l1.orphan, '0');
// training now feeds reputation: learning_speed is measurable from graded attempts, not hardcoded NULL.
const l2 = await probe(`do $p$ declare n int; begin
  select count(*) into n from (
    select agent_key from agent_training_attempt where passed is not null group by agent_key) z;
  raise exception 'MARK|agents=%', n; end $p$;`);
eq('learning_speed is measurable from graded training', Number(l2.agents) > 0 ? 'yes' : 'no', 'yes');

// ============================================================================================
console.log('\n== INCIDENTS — every incident is owned, tracked, and chased past SLA ==');
// ============================================================================================
// Opening an incident sets an owner (the security.event incident-response subscriber) and opens ONE
// linked task in the owner's department; starting the task acknowledges the incident; completing it
// resolves the incident; an overdue high incident is re-escalated to the founder-alert channel.
const iw = await probe(`do $p$ declare v_id bigint; v_owner text; v_task bigint; v_dept text; v_ac text;
  v_ack timestamptz; v_st text; v_fa0 int; v_fa1 int; e jsonb; v_over bigint; begin
  insert into os_incidents(title,kind,severity,detail,opened_by)
    values('ZZ probe incident','silent_failure','high',jsonb_build_object('description','probe'),'os') returning id into v_id;
  select owner, org_task_id into v_owner, v_task from os_incidents where id=v_id;
  select dept_key, action_class into v_dept, v_ac from org_tasks where id=v_task;
  update org_tasks set status='in_progress' where id=v_task; select acknowledged_at into v_ack from os_incidents where id=v_id;
  update org_tasks set status='done' where id=v_task; select status into v_st from os_incidents where id=v_id;
  insert into os_incidents(title,kind,severity,detail,opened_by,opened_at)
    values('ZZ probe overdue','silent_failure','high','{}'::jsonb,'os',now()-interval '2 days') returning id into v_over;
  update os_incidents set due_at=now()-interval '1 day', escalated_at=null where id=v_over;
  select count(*) into v_fa0 from founder_alerts; e := fn_os_incident_watchdog(); select count(*) into v_fa1 from founder_alerts;
  raise exception 'MARK|owner=%|task_dept=%|task_ac=%|ack=%|status=%|reesc=%|fa_delta=%',
    v_owner, v_dept, v_ac, (v_ack is not null)::text, v_st, (e->>'reescalated'), (v_fa1-v_fa0); end $p$;`);
eq('a new incident is owned by the security incident-response role', iw.owner, 'security');
eq('  -> opens ONE linked task in the owner’s department', iw.task_dept, 'assurance');
eq('  -> tagged as incident work', iw.task_ac, 'incident');
eq('starting the task acknowledges the incident', iw.ack, 'true');
eq('completing the task resolves the incident', iw.status, 'resolved');
eq('the watchdog re-escalates an overdue high incident', iw.reesc, '1');
eq('  -> and it reaches the founder-alert channel', iw.fa_delta, '1');
// org-wide, at rest: no OPEN incident is left without an owner
const io = await q(`select 'open_incidents_without_an_owner' k,
  (select count(*)::text from os_incidents where status='open' and coalesce(owner,'')='') v, '0' e`);
for (const r of io) eq(r.k, r.v, r.e);

// ============================================================================================
console.log('\n== SURVIVAL LINE — the board sees runway, cash and burn ==');
// ============================================================================================
// The weekly exec meeting reads fn_ws_finance, carries cash/burn/runway in its metrics and a finance
// health verdict, and writes a report_type='finance' board report. (Aborted; the meeting is heavy but
// every write rolls back.)
const sv = await probe(`do $p$ declare res jsonb; v_br int; begin
  res := fn_exec_meeting();
  select count(*) into v_br from board_reports where report_type='finance' and week_start=date_trunc('week',current_date)::date;
  raise exception 'MARK|fin_health=%|has_cash=%|has_burn=%|has_runway=%|finance_report=%',
    (res ? 'finance_health')::text, (res->'metrics' ? 'cash_aed')::text, (res->'metrics' ? 'monthly_burn_aed')::text,
    (res->'metrics' ? 'runway_months')::text, (v_br>0)::text; end $p$;`);
eq('the exec meeting carries a finance health verdict', sv.fin_health, 'true');
eq('  -> cash on the board metrics', sv.has_cash, 'true');
eq('  -> monthly burn on the board metrics', sv.has_burn, 'true');
eq('  -> runway on the board metrics', sv.has_runway, 'true');
eq('a report_type=finance board report is written each week', sv.finance_report, 'true');

// ============================================================================================
console.log('\n== OS COVERAGE — every active department maps to an operating system ==');
// ============================================================================================
// customer_experience and assurance were buried inside the marketplace and operations OS; now each of
// the ten departments maps to its own operating system, so the weekly review surfaces all of them.
const oc = await q(`select 'active_departments_without_an_operating_system' k,
  (select count(*)::text from org_departments d where d.active
     and not exists(select 1 from os_department od where od.dept_key=d.dept_key)) v, '0' e
  union all select 'both_new_operating_systems_present',
  (select (count(*)=2)::text from operating_system where os_key in ('customer_experience','assurance') and active), 'true'`);
for (const r of oc) eq(r.k, r.v, r.e);

// ============================================================================================
console.log('\n== MEASUREMENT SPINE — work and KPIs are tied to objectives ==');
// ============================================================================================
// A task is tied to its department objective at creation (the exact one if its text names a goal_key,
// else the department's primary objective); KPIs are tied to their operating system's objective.
const sp = await probe(`do $p$ declare v_gk text; v_precise bigint; v_oid1 bigint; v_oid2 bigint; v_valid bool; begin
  select goal_key, id into v_gk, v_precise from department_objective where dept_key='finance' and active and status='active' and coalesce(goal_key,'')<>'' order by id limit 1;
  insert into org_tasks(dept_key,title,detail,status,tier,needs_founder,action_class) values('finance','ZZ probe plain','no key','proposed','advisory',false,'recommend') returning objective_id into v_oid1;
  select exists(select 1 from department_objective o where o.id=v_oid1 and o.dept_key='finance' and o.active) into v_valid;
  insert into org_tasks(dept_key,title,detail,status,tier,needs_founder,action_class) values('finance','ZZ probe '||v_gk,'targets '||v_gk,'proposed','advisory',false,'recommend') returning objective_id into v_oid2;
  raise exception 'MARK|default_valid=%|precise=%', v_valid::text, (v_oid2=v_precise)::text; end $p$;`);
eq('a departmental task is tied to a real department objective', sp.default_valid, 'true');
eq('  -> a task naming a goal_key gets that exact objective', sp.precise, 'true');
const spr = await q(`select 'open_dept_tasks_without_an_objective' k,
  (select count(*)::text from org_tasks t where t.objective_id is null and coalesce(t.dept_key,'')<>''
     and exists(select 1 from department_objective o where o.dept_key=t.dept_key and o.active and o.status='active')) v, '0' e
  union all select 'active_kpis_tied_to_an_os_objective_gt0',
  ((select count(*) from employee_kpi where active and serves_objective is not null) > 0)::text, 'true'
  union all select 'org_tasks_with_a_dangling_objective_fk',
  (select count(*)::text from org_tasks t where t.objective_id is not null and not exists(select 1 from department_objective o where o.id=t.objective_id)), '0'`);
for (const r of spr) eq(r.k, r.v, r.e);

// ============================================================================================
console.log('\n== EVENTS — the five missing emitters can wake their workflows ==');
// ============================================================================================
// Each of the five events with an active subscriber now has an emitter: four AFTER triggers on the
// real originating tables, and a cross-department-conflict detector for the one with no source table.
const ev = await probe(`do $p$ declare v_cd int; v_cc int; v_ch int; v_cp int; v_dc int; begin
  insert into content_drafts(channel,category,title,body,status,source) values('blog','news','ZZ ev probe','b','draft','x');
  select count(*) into v_cd from company_event where event_type='content.drafted' and payload->>'title'='ZZ ev probe';
  insert into feedback(source,subject_type,subject_id,rating,comment) values('survey','customer','zzev',1,'x');
  select count(*) into v_cc from company_event where event_type='customer.complaint' and payload->>'subject_id'='zzev';
  insert into customer_score(customer_id,rfqs_posted,rfqs_awarded,churn_risk,computed_at) values(999999002,0,0,0.9,now());
  select count(*) into v_ch from company_event where event_type='customer.churn_signal' and entity_id='999999002';
  insert into phase_d_object_record(object_id,business_key,version,state,owner_scope,owner_ref,payload,created_by)
    values('content_campaign','zzev_camp',1,'active','COMPANY','company',jsonb_build_object('t','x'),'x');
  update phase_d_object_record set state='published' where object_id='content_campaign' and business_key='zzev_camp';
  select count(*) into v_cp from company_event where event_type='campaign.published' and payload->>'business_key'='zzev_camp';
  insert into decision_log(actor,kind,decision,created_at) values('cfo','zzev_conflict','approve',now()),('cto','zzev_conflict','reject',now());
  perform fn_emit_department_conflict();
  select count(*) into v_dc from company_event where event_type='department.conflict' and entity_id='zzev_conflict';
  raise exception 'MARK|content=%|complaint=%|churn=%|campaign=%|conflict=%', v_cd,v_cc,v_ch,v_cp,v_dc; end $p$;`);
eq('content.drafted fires on a new content draft', ev.content, '1');
eq('customer.complaint fires on a low-rating feedback', ev.complaint, '1');
eq('customer.churn_signal fires when churn risk enters the danger band', ev.churn, '1');
eq('campaign.published fires when a campaign object is published', ev.campaign, '1');
eq('department.conflict fires on a cross-department decision conflict', ev.conflict, '1');
const es = await q(`select 'five_new_events_all_have_active_subscribers' k,
  (select count(distinct event_type)::text from event_subscription where active
     and event_type in ('content.drafted','customer.complaint','customer.churn_signal','campaign.published','department.conflict')) v, '5' e`);
for (const r of es) eq(r.k, r.v, r.e);

// ============================================================================================
console.log('\n== GOAL RETIREMENT — the re-plan flows through the kernel, with an owner ==');
// ============================================================================================
// Retiring a company goal now emits goal.retired (the emit was broken — a trigger function called with
// positional args and swallowed) and starts a run of the runtime workflow goal_retirement_replan, whose
// steps are accountable to corporate_performance_director. No frozen Phase B row moves.
const gr = await probe(`do $p$ declare v_key text; v_ev int; v_rb int; v_ra int; v_owner text; begin
  select key into v_key from company_goals where active order by key limit 1;
  select count(*) into v_rb from workflow_run where workflow_key='goal_retirement_replan';
  update company_goals set active=false where key=v_key;
  select count(*) into v_ev from company_event where event_type='goal.retired' and entity_id=v_key;
  perform fn_workflow_start_due(60);
  select count(*) into v_ra from workflow_run where workflow_key='goal_retirement_replan';
  select actor_role into v_owner from workflow_step where workflow_key='goal_retirement_replan' and step_no=1;
  raise exception 'MARK|emitted=%|run_started=%|owner=%', v_ev, (v_ra>v_rb)::text, v_owner; end $p$;`);
eq('retiring a company goal emits goal.retired', gr.emitted, '1');
eq('  -> a kernel workflow run starts from it', gr.run_started, 'true');
eq('  -> its steps are accountable to corporate performance', gr.owner, 'corporate_performance_director');
const grr = await q(`select 'goal_retirement_wiring_gap_open' k,
  (select count(*)::text from phase_b_phase_c_wiring_gap where gap ilike '%goal%retir%') v, '0' e
  union all select 'phase_a_and_b_baselines_undrifted',
  ((select count(*) from fn_phase_a_baseline_drift()) + (select count(*) from fn_phase_b_baseline_drift()) = 0)::text, 'true'`);
for (const r of grr) eq(r.k, r.v, r.e);

// ============================================================================================
console.log('\n== EXECUTOR TEETH — spend is checked, blocked employees refused, escalation consumed ==');
// ============================================================================================
const dt = await probe(`do $p$ declare v1 uuid; v2 uuid; v3 uuid; inv1 text; inv2 text; inv3 text; v_check text;
  v_agent text; v_rem bigint; vb uuid; invb text; v_res jsonb; v_task int; begin
  update department_budget set monthly_aed=1000000, spent_aed=0 where dept_key='finance';
  insert into action_execution(correlation_id,action_class,executor,idempotency_key,risk_tier,reversible,request,status)
    values(gen_random_uuid(),'expense_log','expense_log','t1-'||gen_random_uuid()::text,'low',true,jsonb_build_object('amount',500,'actor','zz_probe_actor'),'queued') returning id into v1;
  perform fn_action_invoke_dispatch(50); select response->>'invoker' into inv1 from action_execution where id=v1;
  insert into action_execution(correlation_id,action_class,executor,idempotency_key,risk_tier,reversible,request,status)
    values(gen_random_uuid(),'expense_log','expense_log','t2-'||gen_random_uuid()::text,'low',true,jsonb_build_object('amount',50000,'actor','zz_probe_actor'),'queued') returning id into v2;
  perform fn_action_invoke_dispatch(50); select response->>'invoker' into inv2 from action_execution where id=v2;
  insert into action_execution(correlation_id,action_class,executor,idempotency_key,risk_tier,reversible,request,status)
    values(gen_random_uuid(),'expense_log','expense_log','t3-'||gen_random_uuid()::text,'low',true,jsonb_build_object('amount',5000000,'actor','zz_probe_actor'),'queued') returning id into v3;
  perform fn_action_invoke_dispatch(50); select response->>'invoker' into inv3 from action_execution where id=v3;
  begin update org_action_executor set second_authority=null where action_class='collections_chase'; v_check:='NOT_REFUSED'; exception when others then v_check:='REFUSED'; end;
  select agent_key into v_agent from org_agents where active and manager_key is not null order by agent_key limit 1;
  insert into agent_remediation(agent_key,failure_class,competency,status,blocks_autonomy,attempts,max_attempts) values(v_agent,'kpi_miss','zzc','open',true,3,3) returning id into v_rem;
  insert into action_execution(correlation_id,action_class,executor,idempotency_key,risk_tier,reversible,request,status)
    values(gen_random_uuid(),'supplier_verify','supplier_verify','tb-'||gen_random_uuid()::text,'medium',true,jsonb_build_object('actor',v_agent),'queued') returning id into vb;
  perform fn_action_invoke_dispatch(50); select response->>'invoker' into invb from action_execution where id=vb;
  update agent_remediation set status='escalated' where id=v_rem;
  v_res := fn_agent_remediation_escalate_consume();
  select count(*) into v_task from org_tasks where title like 'Remediation escalated: '||v_agent||'%' and status<>'done';
  raise exception 'MARK|forced=%|over10k=%|unaffordable=%|check=%|blocked=%|handled=%|task=%',
    inv1,inv2,inv3,v_check,(invb='refused')::text,(v_res->>'handled'),v_task; end $p$;`);
eq('a low-risk money executor with a second authority forces two approvals', dt.forced, 'awaiting_two_approvals');
eq('a spend over AED 10k routes to the founder', dt.over10k, 'awaiting_founder_approval');
eq('an unaffordable spend is refused', dt.unaffordable, 'refused');
eq('a medium/high money executor cannot drop its second authority', dt.check, 'REFUSED');
eq('an autonomy-blocked employee’s action is refused by the dispatcher', dt.blocked, 'true');
eq('an escalated remediation opens a manager task', dt.handled, '1');
eq('  -> exactly one, deduplicated', dt.task, '1');

// ============================================================================================
console.log('\n== PROMOTION — the org can promote, not only punish (and respects the hold) ==');
// ============================================================================================
const pr = await probe(`do $p$ declare v_paused text; v_agent text; v_res jsonb; v_sen text; v_wide int; begin
  select fn_promotion_review()->>'status' into v_paused;
  delete from company_stand_down;
  select agent_key into v_agent from org_agents where active and seniority is not null order by agent_key limit 1;
  update org_agents set seniority='junior' where agent_key=v_agent;
  insert into agent_reputation(agent_key,correctness,reliability,score,tier,computed_at) values(v_agent,95,100,90,'senior_trusted',now())
    on conflict (agent_key) do update set correctness=95,reliability=100,tier='senior_trusted',computed_at=now();
  insert into agent_runs(agent,started_at,finished_at,status) select v_agent,now()-interval '1 day',now(),'ok' from generate_series(1,60);
  insert into employee_authority(agent_key,action_class,max_tier,threshold_aed,note) values(v_agent,'zz_probe_grant','gated',0,'Advisory-safe action, may run autonomously');
  v_res := fn_promotion_review();
  select seniority into v_sen from org_agents where agent_key=v_agent;
  select count(*) into v_wide from employee_authority where agent_key=v_agent and action_class='zz_probe_grant' and max_tier='autonomous';
  raise exception 'MARK|paused=%|promoted_gt0=%|seniority=%|widened=%', v_paused, ((v_res->>'promoted')::int>0)::text, v_sen, v_wide; end $p$;`);
eq('promotion review respects the founder stand-down', pr.paused, 'PAUSED_BY_FOUNDER_STANDDOWN');
eq('a qualifying employee is promoted (seniority advances)', pr.seniority, 'specialist');
eq('  -> and their advisory-safe authority widens to autonomous', pr.widened, '1');
eq('  -> at least one promotion once the hold is lifted', pr.promoted_gt0, 'true');

// ============================================================================================
console.log('\n== APEX BACKUP — a deputy stands in for the CEO before the generic fallback ==');
// ============================================================================================
const ab = await q(`select 'the_ceo_still_routes_to_the_founder' k,
  (fn_should_escalate('{"actor":"ceo","confidence":0.1}')->>'route_to') v, 'founder' e
  union all select 'an_unresolved_escalation_reaches_the_named_apex_backup',
  (fn_should_escalate('{"actor":"zz_unresolvable_actor","confidence":0.1}')->>'route_basis'), 'apex_backup'
  union all select 'the_apex_backup_is_the_coo_not_the_generic_exec_fallback',
  (fn_should_escalate('{"actor":"zz_unresolvable_actor","confidence":0.1}')->>'route_to'), 'ops_director'
  union all select 'a_reporting_line_escalation_is_unaffected',
  (fn_should_escalate('{"actor":"bookkeeper","confidence":0.1}')->>'route_basis'), 'reporting_line'`);
for (const r of ab) eq(r.k, r.v, r.e);

// ============================================================================================
console.log('\n== STEP BINDINGS — every owner is a real role or the frozen spec’s own owner ==');
// ============================================================================================
const sb = await q(`select 'w14_s05_binding_owner_is_the_amended_role' k,
  (select accountable_role_id from phase_c_step_binding where step_id='W14-S05') v, 'quote_evaluation' e
  union all select 'step_binding_owners_absent_from_org_role_and_diverging_from_the_spec',
  (select count(*)::text from phase_c_step_binding b join phase_b_workflow_step s on s.step_id=b.step_id
    where b.accountable_role_id is not null
      and not exists(select 1 from org_role r where r.role_id=b.accountable_role_id)
      and not exists(select 1 from org_role_alias a where a.alias=b.accountable_role_id)
      and b.accountable_role_id <> s.accountable_role_id), '0'`);
for (const r of sb) eq(r.k, r.v, r.e);

// ============================================================================================
console.log('\n== ACTION AUTHOR — self-approval fails closed on an unattributed action ==');
// ============================================================================================
const au = await probe(`do $p$ declare v1 uuid; v2 uuid; a1 text; a2 text; v_auth text; begin
  insert into action_execution(correlation_id,action_class,executor,idempotency_key,risk_tier,reversible,request,status)
    values(gen_random_uuid(),'supplier_verify','supplier_verify','au1-'||gen_random_uuid()::text,'medium',true,'{}'::jsonb,'queued') returning id into v1;
  perform fn_action_invoke_dispatch(50);
  begin perform fn_action_head_approve(v1,'approved','x','procurement'); a1:='NOT_REFUSED'; exception when others then a1:='REFUSED'; end;
  insert into action_execution(correlation_id,action_class,executor,idempotency_key,risk_tier,reversible,request,status)
    values(gen_random_uuid(),'supplier_verify','supplier_verify','au2-'||gen_random_uuid()::text,'medium',true,jsonb_build_object('actor','procurement'),'queued') returning id into v2;
  select author into v_auth from action_execution where id=v2;
  perform fn_action_invoke_dispatch(50);
  begin perform fn_action_head_approve(v2,'approved','x','procurement'); a2:='NOT_REFUSED'; exception when others then a2:='REFUSED'; end;
  raise exception 'MARK|no_author_refused=%|author_stamped=%|self_approval_refused=%', a1, v_auth, a2; end $p$;`);
eq('an action with no recorded author cannot be approved', au.no_author_refused, 'REFUSED');
eq('the author is stamped from the queuing actor', au.author_stamped, 'procurement');
eq('the author may not approve their own work', au.self_approval_refused, 'REFUSED');

console.log(`\n${fail === 0 ? 'PASS' : 'FAIL'} — ${fail} assertion(s) failed`);
process.exit(fail ? 1 : 0);
