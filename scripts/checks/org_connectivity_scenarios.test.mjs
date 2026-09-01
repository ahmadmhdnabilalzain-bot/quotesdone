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

// spend/contract needs TWO independent approvals: a head AND the named second authority.
const a4 = await probe(`do $p$ declare v_id uuid; a1 jsonb; a2 jsonb; inv1 text; inv2 text; wrong text; gate boolean; begin
  update org_action_executor set second_authority='legal' where action_class='supplier_verify';
  insert into action_execution (correlation_id,action_class,executor,idempotency_key,risk_tier,reversible,request,status)
  values (gen_random_uuid(),'supplier_verify','supplier_verify','probe-'||gen_random_uuid()::text,'medium',true,'{}'::jsonb,'queued') returning id into v_id;
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

console.log(`\n${fail === 0 ? 'PASS' : 'FAIL'} — ${fail} assertion(s) failed`);
process.exit(fail ? 1 : 0);
