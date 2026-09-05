// NOTHING ROUTES TO THE FOUNDER EXCEPT A STRIPE REFUND.
//
// 5 Sep 2026. He opened the OS and saw non-refund things "waiting for his approval". The audit that
// day found six founder-facing routines counting every open agent_action as his, decision_policy
// naming him for six non-refund kinds and eight review gates, and fn_autonomy_class hard-coding
// four more. phase_c_action_class and the founder_approval_request triggers were already right.
//
// This check reads production and asserts that policy, runtime and every founder-facing surface
// say the same thing. It calls the routines — a row in a policy table is a claim; the list a
// surface renders is the behaviour.
//
//   node --test scripts/checks/founder_approval_is_refunds_only.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { sql } from '../phase_c/lib/db.mjs';

const REFUND = /refund|payout|payment|withdraw|transfer|money|charge/i;
const q = (s) => sql(`set statement_timeout = '8s'; ${s}`);
const one = async (s) => (await q(s))[0];

test('agent_action_kind_policy: policy = founder only for a refund kind', async () => {
  const rows = await q(`select kind from public.agent_action_kind_policy where policy = 'founder'`);
  const bad = rows.map(r => r.kind).filter(k => !REFUND.test(k));
  assert.deepEqual(bad, [], `non-refund kinds route to the founder: ${bad.join(', ')}`);
});

test('decision_policy: action_autonomy never says founder; founder_review_gates are refunds only', async () => {
  const r = await one(`select
      (select value from public.decision_policy where key = 'action_autonomy') autonomy,
      (select value from public.decision_policy where key = 'founder_review_gates') gates`);
  const founderKinds = Object.entries(r.autonomy || {}).filter(([k, v]) => v === 'founder' && !REFUND.test(k)).map(([k]) => k);
  assert.deepEqual(founderKinds, [], `action_autonomy names the founder for: ${founderKinds.join(', ')}`);
  const roles = await q(`select role_id from public.org_role where status = 'active'`);
  const active = new Set(roles.map(x => x.role_id));
  const dangling = Object.entries(r.autonomy || {}).filter(([, v]) => v !== 'ack' && !active.has(v)).map(([k, v]) => `${k}=${v}`);
  assert.deepEqual(dangling, [], `action_autonomy names a role that is not active: ${dangling.join(', ')}`);
  const badGates = (r.gates || []).filter(g => !REFUND.test(g));
  assert.deepEqual(badGates, [], `founder_review_gates lists non-refund gates: ${badGates.join(', ')}`);
});

test('phase_c_action_class: founder_approval_required only for refund_decision', async () => {
  const rows = await q(`select action_class from public.phase_c_action_class where founder_approval_required`);
  assert.deepEqual(rows.map(r => r.action_class).sort(), ['refund_decision']);
});

test('fn_autonomy_class returns founder for a refund and for nothing else', async () => {
  const r = await one(`select
      public.fn_autonomy_class('refund_request', null, null) refund,
      array_remove(array[
        case when public.fn_autonomy_class('legal_action', null, null) = 'founder' then 'legal_action' end,
        case when public.fn_autonomy_class('strategy_change', null, null) = 'founder' then 'strategy_change' end,
        case when public.fn_autonomy_class('partnership', null, null) = 'founder' then 'partnership' end,
        case when public.fn_autonomy_class('security_incident_executive', null, null) = 'founder' then 'security_incident_executive' end,
        case when public.fn_autonomy_class('legal_flag', null, null) = 'founder' then 'legal_flag' end,
        case when public.fn_autonomy_class('security_incident', null, null) = 'founder' then 'security_incident' end,
        case when public.fn_autonomy_class('customer_escalation', null, null) = 'founder' then 'customer_escalation' end,
        case when public.fn_autonomy_class('approve_supplier', 'leads', 'reject') = 'founder' then 'approve_supplier' end,
        case when public.fn_autonomy_class('delete_customer', 'customers', null) = 'founder' then 'delete_customer' end
      ], null) founder_for`);
  assert.equal(r.refund, 'founder', 'a refund kind must still reach the founder');
  assert.deepEqual(r.founder_for, [], `fn_autonomy_class returns founder for: ${r.founder_for.join(', ')}`);
});

test('every founder-facing surface lists only the refund queue as his', async () => {
  const r = await one(`select
      public.fn_founder_refund_approvals_open() refunds,
      public.fn_founder_queue(200) fq,
      public.fn_ws_exec_home()->>'decisions_open' exec_home,
      public.fn_ws_operations() ops,
      public.fn_ws_governance()#>>'{kpis,open_for_review}' governance,
      public.fn_ws_notifications() bell,
      public.fn_ws_exec() ws_exec,
      public.fn_ops_dashboard()#>>'{operations,escalations}' dashboard_escalations,
      (select count(*) from public.founder_alerts where public.fn_alert_severe(level) and created_at >= now() - interval '24 hours') severe_alerts`);
  const refunds = Number(r.refunds);
  const queueIds = new Set((r.fq.waiting_on_you || []).map(x => String(x.id)));
  assert.equal(r.fq.waiting_on_you.length, refunds, 'fn_founder_queue total and list disagree');
  for (const x of r.fq.waiting_on_you) assert.match(String(x.kind), REFUND, `founder queue lists a non-refund item: ${x.kind}`);
  assert.equal(Number(r.exec_home), refunds, 'fn_ws_exec_home.decisions_open is not the refund count');
  assert.equal(Number(r.ops.kpis.approvals_pending), refunds, 'fn_ws_operations.kpis.approvals_pending is not the refund count');
  for (const a of r.ops.approvals || []) assert.ok(queueIds.has(String(a.id)), `fn_ws_operations.approvals lists ${a.id}, not in the founder queue`);
  for (const h of r.ops.held || []) assert.ok(h.holder, `fn_ws_operations.held row ${h.id} names no holder`);
  assert.equal(Number(r.governance), refunds, 'fn_ws_governance.kpis.open_for_review is not the refund count');
  assert.equal(Number(r.bell.important.count), refunds, 'the bell counts something other than refund approvals as important');
  for (const a of r.bell.important.rows || []) assert.ok(queueIds.has(String(a.id)), `bell important row ${a.id} is not in the founder queue`);
  for (const a of r.ws_exec.approvals || []) assert.ok(queueIds.has(String(a.id)), `fn_ws_exec.approvals lists ${a.id}, not in the founder queue`);
  for (const a of r.ws_exec.command.attention || []) assert.ok(a.holder && a.yours === false, `fn_os_command.attention row ${a.id} is not marked held with a role`);
  assert.equal(Number(r.dashboard_escalations), refunds + Number(r.severe_alerts), 'fn_ops_dashboard escalations is not refunds + severe alerts');
});

test('the daily brief puts only refunds under DECISIONS NEEDED (aborted probe, nothing sent)', async () => {
  let msg = '';
  try {
    await q(`do $$ declare v text; begin
      perform public.fn_founder_brief();
      select body into v from public.notifications where type = 'founder_brief' order by id desc limit 1;
      raise exception 'PROBE:%', substring(v from 'DECISIONS NEEDED.*?QUALITY, COST');
    end $$;`);
  } catch (e) { msg = String(e.message); }
  assert.match(msg, /PROBE:/, 'the probe did not raise, so the brief run may have committed');
  const dec = msg.split('PROBE:')[1] || '';
  const decisions = dec.split('WITH THE ORGANISATION')[0];
  assert.match(dec, /WITH THE ORGANISATION/, 'no WITH THE ORGANISATION section');
  assert.doesNotMatch(decisions, /objective step|KYC|trade licence|severe alert|awaiting your approval\/input/i,
    `DECISIONS NEEDED still carries department work:\n${decisions.slice(0, 400)}`);
});
