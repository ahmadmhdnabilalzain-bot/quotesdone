// THE ORG CONNECTS LIKE A REAL COMPANY — PROVEN BY EXECUTION, WITH ZERO PAID INFERENCE.
//
// Launch Step 1. The founder's requirement (LAUNCH_READINESS_PLAN.md, 27 Aug 2026): the company runs
// itself toward the CEO's single target, the only human approval is refunds, and every signal a real
// company depends on actually TRAVELS — a target decomposes to departments, a request handed from one
// department reaches another's queue and is acted on, an approval routes to the accountable AI head
// and flows onward, an escalation reaches a real higher owner and the apex reaches the founder.
//
// This harness proves those four signal paths on the LIVE database. Every write path is exercised
// inside a transaction that ALWAYS aborts (a DO block that RAISEs its measurements), so it asserts on
// a real fired signal AND a real non-zero effect while leaving no residue. It calls no model and
// sends nothing outbound — the approval dispatch reaches net.http_post only inside the aborted
// transaction, whose enqueue rolls back with everything else (verified: no row survives).
//
//   node scripts/checks/org_connectivity_signal_path.test.mjs
//
// If the management token is absent it SKIPs (asserting nothing) rather than passing vacuously.
import { readFileSync, existsSync } from 'node:fs';
const PROD = 'htdblwldjkcgjvmqkbeh';
const LOCAL = 'C:/Users/Opera/.supabase/access-token';
const token = (process.env.SUPABASE_ACCESS_TOKEN || (existsSync(LOCAL) ? readFileSync(LOCAL, 'utf8') : '')).trim();
if (!token) { console.log('SKIPPED: no management token, so this asserted nothing.'); process.exit(0); }

// Backoff on 429/5xx: this gate runs in a CI job alongside the Phase C and Phase D gates, which hit
// the same management API concurrently — the acceptance measured ten false failures from a bare 429
// when management-API checks ran in parallel. A RAISE from a probe returns HTTP 400 and is NOT retried
// (it is the expected result); only transport-level throttling is.
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

// A probe is a DO block that RAISEs 'MARK|k=v|k=v'. Run it, expect it to throw, return the fields.
const probe = async (marker, sql) => {
  try { await q(sql); return { __error: 'probe did not raise — it should always abort' }; }
  catch (e) {
    const t = String(e.message); const i = t.indexOf(marker + '|');
    if (i < 0) return { __error: t.slice(0, 300) };
    // The message is the raw HTTP body (JSON), where the newline before CONTEXT is the literal two
    // chars \n, not a real newline. Cut the marker fields at the first of: literal \n, CONTEXT, or ".
    const seg = t.slice(i + marker.length + 1).split(/\\n|CONTEXT|"/)[0].trim();
    const out = {};
    for (const kv of seg.split('|')) { const j = kv.indexOf('='); if (j > 0) out[kv.slice(0, j)] = kv.slice(j + 1); }
    return out;
  }
};

let fail = 0;
const eq = (label, got, want) => {
  const ok = String(got) === String(want);
  if (!ok) fail++;
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${label.padEnd(64)} ${got}${ok ? '' : `  (expected ${want})`}`);
};
const truthy = (label, cond, detail = '') => {
  if (!cond) fail++;
  console.log(`${cond ? 'ok  ' : 'FAIL'}  ${label.padEnd(64)} ${detail}`);
};

// ============================================================================================
console.log('\n== REQ 1 — TARGET CASCADE (CEO target -> department -> role -> owned work) ==');
// ============================================================================================
const r1 = (await q(`
  select 'aed_1m_present_and_cascadeable' k,
         (exists(select 1 from company_goals
                  where key='revenue_annual' and target_value=1000000 and active
                    and coalesce(measure_sql,'')<>''
                    and owner_dept in (select dept_key from org_departments where active)))::text v, 'true' e
  union all
  select 'objective_cascade_revenue_aed',
         (fn_objective_cascade()->>'revenue_objective_aed'), '1000000'
  union all
  select 'dept_objectives_link_to_a_goal_gt0',
         ((fn_objective_cascade()->>'department_objectives_linked_to_a_company_goal')::int > 0)::text, 'true'
`));
for (const r of r1) eq(r.k, r.v, r.e);

// A NEW target cascades to its owning department the moment it is set (trg_goal_cascade). Aborted.
const p1a = await probe('CASCADE', `do $p$
  declare before int; after int; d text;
  begin
    select count(*) into before from department_objective where goal_key='zz_probe_target';
    insert into company_goals (key, goal, category, metric, target_value, unit, owner_dept, horizon, active, measure_sql, direction)
    values ('zz_probe_target','ZZ PROBE cascade sub-goal','Financial','revenue',500000,'AED','finance','year_1',true,'select 0','at_least');
    select count(*), max(dept_key) into after, d from department_objective where goal_key='zz_probe_target' and active;
    raise exception 'CASCADE|before=%|after=%|dept=%', before, after, d;
  end $p$;`);
truthy('a new target cascades to a department_objective', p1a.before === '0' && p1a.after === '1' && p1a.dept === 'finance',
       `before=${p1a.before} after=${p1a.after} dept=${p1a.dept}`);

// The open work reaches an accountable owner: one sweep fills the department (fn_org_task_assign). Aborted.
const p1b = await probe('ASSIGN', `do $p$
  declare before_null int; res jsonb; now_owned int; still_null int;
  begin
    select count(*) into before_null from org_tasks where status in ('assigned','in_progress') and assigned_agent is null;
    res := fn_org_task_assign(500);
    select count(*) into now_owned  from org_tasks where status in ('assigned','in_progress') and assigned_agent is not null;
    select count(*) into still_null from org_tasks where status in ('assigned','in_progress') and assigned_agent is null;
    raise exception 'ASSIGN|before_null=%|assigned=%|now_owned=%|still_null=%',
      before_null, (res->>'assigned'), now_owned, still_null;
  end $p$;`);
truthy('a sweep gives every unowned open task a real owner',
       Number(p1b.assigned) >= Number(p1b.before_null) && p1b.still_null === '0' && Number(p1b.assigned) > 0,
       `unowned_before=${p1b.before_null} assigned=${p1b.assigned} still_unowned=${p1b.still_null}`);

// ============================================================================================
console.log('\n== REQ 2 — INTER-DEPARTMENT MESSAGING (finance -> legal: received AND acted on) ==');
// ============================================================================================
const p2 = await probe('HANDOFF', `do $p$
  declare v_open jsonb; v_id bigint; v_action bigint; v_recv text; v_landed boolean; v_recv_ok boolean;
          v_acc jsonb; v_sa text; v_close jsonb; v_sc text;
  begin
    v_open := fn_handoff_open(jsonb_build_object(
      'from_dept','finance','accountable_owner','cfo','to_dept','legal','to_role','general_counsel',
      'purpose','Review the vendor NDA indemnity clause for UAE enforceability',
      'requested_action','Confirm the indemnity clause is enforceable under UAE law and note carve-outs',
      'escalation_conditions','If not reviewed within 2 business days, escalate to the legal department head',
      'deadline',(now()+interval '3 days')::text,
      'evidence', jsonb_build_array(jsonb_build_object('doc','NDA draft v2 attached')),
      'acceptance_criteria', jsonb_build_array('NDA text provided','UAE jurisdiction confirmed'),
      'closure_criteria', jsonb_build_array('Legal opinion recorded')));
    if not coalesce((v_open->>'ok')::boolean,false) then raise exception 'HANDOFF|open_ok=false|why=%', v_open::text; end if;
    v_id := (v_open->>'id')::bigint; v_action := (v_open->>'action_id')::bigint; v_recv := v_open->>'receiving_agent';
    -- RECEIVED: the transport row lands in the receiver's own queue (the table fn_agent_handoff_inbox reads).
    select exists(select 1 from agent_actions where id=v_action and agent=v_recv and kind='handoff'
                   and status='needs_review' and target_id=v_id::text) into v_landed;
    select exists(select 1 from org_agents where agent_key=v_recv and active and department='legal') into v_recv_ok;
    -- ACTED ON: the receiver accepts, then closes with proof -> the sender is notified (routes onward).
    v_acc := fn_handoff_respond(v_id, v_recv, 'accept');
    select status into v_sa from handoff_contract where id=v_id;
    v_close := fn_handoff_close(v_id, v_recv, jsonb_build_array(
      jsonb_build_object('criterion','Legal opinion recorded','evidence','Opinion: enforceable, one carve-out noted')));
    select status into v_sc from handoff_contract where id=v_id;
    raise exception 'HANDOFF|open_ok=%|recv_active_in_legal=%|landed_in_queue=%|accept_ok=%|status_accept=%|close_ok=%|status_close=%',
      (v_open->>'ok'), v_recv_ok::text, v_landed::text, (v_acc->>'ok'), v_sa, (v_close->>'ok'), v_sc;
  end $p$;`);
eq('handoff opens (contract accepted by the sender dept)', p2.open_ok, 'true');
eq('receiver resolves to an active employee of the target dept', p2.recv_active_in_legal, 'true');
eq('signal received: row in the receiving role\'s queue', p2.landed_in_queue, 'true');
eq('receiver accepts the handoff', p2.accept_ok, 'true');
eq('  -> handoff_contract status', p2.status_accept, 'accepted');
eq('receiver closes with proof (routes onward, sender notified)', p2.close_ok, 'true');
eq('  -> handoff_contract status', p2.status_close, 'closed');

// ============================================================================================
console.log('\n== REQ 3 — APPROVAL SEQUENCE (consequential -> AI head -> onward; refunds -> founder only) ==');
// ============================================================================================
const p3 = await probe('APPROVAL', `do $p$
  declare v_id uuid; s1 jsonb; s2 jsonb; ap record; inv1 text; inv2 text; st2 text; v_wrong text;
  begin
    insert into action_execution (correlation_id, action_class, executor, idempotency_key, risk_tier, reversible, request, status)
    values (gen_random_uuid(),'supplier_verify','supplier_verify','probe-'||gen_random_uuid()::text,'medium',true,
            jsonb_build_object('probe',true),'queued')
    returning id into v_id;
    s1 := fn_action_invoke_dispatch(50);
    select response->>'invoker' into inv1 from action_execution where id=v_id;
    select * into ap from action_approval where action_execution_id=v_id;
    begin
      perform fn_action_head_approve(v_id,'approved','probe wrong approver','cfo');
      v_wrong := 'NOT_REFUSED';
    exception when others then v_wrong := 'REFUSED'; end;
    perform fn_action_head_approve(v_id,'approved','probe entitled head','procurement');
    s2 := fn_action_invoke_dispatch(50);
    select response->>'invoker', status into inv2, st2 from action_execution where id=v_id;
    raise exception 'APPROVAL|parked=%|approver=%|decision=%|wrong=%|dispatched=%|status2=%',
      inv1, ap.accountable_approver, ap.approval_decision, v_wrong, inv2, st2;
  end $p$;`);
eq('consequential action routes to the accountable AI head', p3.parked, 'awaiting_head_approval');
eq('  -> entitled approver (marketplace/medium)', p3.approver, 'procurement');
eq('  -> approval request recorded', p3.decision, 'requested');
eq('a non-entitled approver is refused', p3.wrong, 'REFUSED');
eq('after the entitled head approves, it flows onward and dispatches', p3.dispatched, 'dispatched');
eq('  -> action moves to running', p3.status2, 'running');

// Refund-only founder gate: exactly one action class reserved to the founder, and it is the refund one.
const r3 = (await q(`
  select 'founder_reserved_action_classes' k,
         (select count(*)::text from org_action_executor where required_authority='founder') v, '1' e
  union all
  select 'and_it_is_the_refund_one',
         (select string_agg(action_class,',') from org_action_executor where required_authority='founder'),
         'refund_within_window'
`));
for (const r of r3) eq(r.k, r.v, r.e);

// ============================================================================================
console.log('\n== REQ 4 — ESCALATION (up the line to a real owner; only the apex reaches the founder) ==');
// ============================================================================================
const r4 = (await q(`
  select 'ceo_escalates_to_founder' k,
         (fn_should_escalate('{"actor":"ceo","confidence":0.1}'::jsonb)->>'route_to') v, 'founder' e
  union all
  select 'a_non_apex_role_escalates_up_to_its_manager',
         (fn_should_escalate('{"actor":"bookkeeper","confidence":0.1}'::jsonb)->>'route_to'), 'cfo'
  union all
  select 'escalation_target_is_an_active_agent',
         (exists(select 1 from org_agents a where a.agent_key=(fn_should_escalate('{"actor":"spec_mep","confidence":0.1}'::jsonb)->>'route_to') and a.active))::text, 'true'
  union all
  select 'only_the_ceo_points_at_the_founder',
         (select count(distinct role_id)::text from org_role, lateral unnest(coalesce(escalation_targets,'{}')) t
           where status='active' and t='founder'), '1'
  union all
  select 'declared_escalation_graph_has_no_self_or_dead_internal_edge',
         (select count(*)::text from (
            select r.role_id, t, fn_org_role_resolve(t) res
            from org_role r, lateral unnest(coalesce(r.escalation_targets,'{}')) t
            where r.status='active') z
          where (res = role_id) or (t<>'founder' and t not ilike 'external%' and res is null)), '0'
  union all
  select 'unsafe_escalation_routes_to_an_active_owner',
         (select (count(*) filter (where route_active))::text from (
            select (fn_unsafe_escalation_route(class_key, null)->>'route_to') rt,
                   exists(select 1 from org_agents a where a.agent_key=(fn_unsafe_escalation_route(class_key, null)->>'route_to') and a.active) route_active
            from unsafe_class) z), (select count(*)::text from unsafe_class)
`));
for (const r of r4) eq(r.k, r.v, r.e);

// ============================================================================================
console.log('\n== REACHABILITY — every active department can receive a handoff ==');
// ============================================================================================
const rr = (await q(`
  select 'active_departments_with_no_active_employee' k,
         (select count(*)::text from org_departments d where d.active
            and not exists (select 1 from org_agents a where a.department=d.dept_key and a.active)) v, '0' e
  union all
  select 'active_department_count',
         (select count(*)::text from org_departments where active), '10'
  union all
  select 'every_active_dept_resolves_an_approver_for_medium_and_high',
         (select count(*)::text from org_departments d where d.active
           and ((fn_action_resolve_approver(d.dept_key,'medium')->>'approver') is null
             or (fn_action_resolve_approver(d.dept_key,'high')->>'approver') is null)), '0'
`));
for (const r of rr) eq(r.k, r.v, r.e);

console.log(`\n${fail === 0 ? 'PASS' : 'FAIL'} — ${fail} assertion(s) failed`);
process.exit(fail ? 1 : 0);
