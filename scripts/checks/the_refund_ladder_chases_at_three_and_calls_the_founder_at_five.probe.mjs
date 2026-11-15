// THE REFUND LADDER CHASES AT THREE AND CALLS THE FOUNDER AT FIVE — proved in ONE aborted transaction
// inside a declared rehearsal window (6 Sep 2026). Nothing survives: the RAISE at the end rolls back the
// ZZ DEMO fixture, every notification, task, refund row and founder alert; the counts come out in the
// exception message. The founder is never paged: the queued rows never commit, so no sender sees them.
//
// The fixture is a reveal paid on Mon 31 Aug 2026 09:00 Dubai (working day 4 by Sun 6 Sep): the sweep
// must chase (one email to the supplier, customer copied; one task on the Customer Success Director) and
// must not chase twice. The reveal is then moved to Wed 26 Aug (past working day 5): the sweep must file
// the refund through fn_refund_request (status requested, founder-gated) and notify the founder ONCE
// (kind refund_final_call, allowed_to_email), and a customer complaint must route to a task, not to him.
//
//   node scripts/checks/the_refund_ladder_chases_at_three_and_calls_the_founder_at_five.probe.mjs
import { sql } from '../lib/db.mjs';
import { replaySql } from '../lib/safe_replay.mjs';   // a rolled-back probe goes through the replay guard (13 Nov 2026)

const probe = `
do $probe$
declare
  v_cust uuid; v_lead bigint; v_inq uuid; v_quote uuid; v_tx uuid; r jsonb; st jsonb;
  n_notif int; n_task int; n_ref int; n_alert int; n_fmail int; n_wa int; n_cmail int; n_ctask int;
  task_agent text; task_dept text; out jsonb := '{}'::jsonb; q0 bigint; t0 bigint;
begin
  insert into public.rehearsal_window (run_tag, opened_by, note)
  values ('qd_run:refund_ladder_probe', 'the_refund_ladder_chases_at_three_and_calls_the_founder_at_five.probe.mjs', 'aborted transaction; nothing survives');
  select coalesce(max(id),0) into q0 from public.notifications;
  select coalesce(max(id),0) into t0 from public.org_tasks;

  insert into public.customers (email, full_name, phone)
  values ('zz-demo-refund-customer@example.invalid', 'ZZ DEMO — Refund Ladder Customer', '+971500000000') returning id into v_cust;
  insert into public.leads (company_name, email)
  values ('ZZ DEMO — Refund Ladder Supplier', 'zz-demo-refund-supplier@example.invalid') returning id into v_lead;
  insert into public.inquiries (customer_id, category, summary, status)
  values (v_cust, 'ZZ DEMO', 'ZZ DEMO — refund ladder rehearsal', 'revealed') returning id into v_inq;
  insert into public.quotes (inquiry_id, supplier_id, quote_amount, status)
  values (v_inq, v_lead, 10000, 'revealed') returning id into v_quote;
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, reveal_fee, fee_status, revealed_at, paid_by, payment_ref)
  values (v_quote, v_inq, v_lead, v_cust, 10000, 300, 'paid', '2026-08-31 09:00+04'::timestamptz, 'card', 'pi_zz_demo_refund_ladder')
  returning id into v_tx;

  -- working day 4 after payment: chase due
  st := public.fn_refund_state(v_tx);
  out := out || jsonb_build_object('day4_state', st->>'state', 'chase_due_at', st->>'chase_due_at', 'founder_call_due_at', st->>'founder_call_due_at', 'refund_deadline', st->>'refund_deadline');
  r := public.fn_refund_ladder_sweep();
  out := out || jsonb_build_object('sweep1', (r - 'cases') - 'ran_at');
  select count(*) into n_notif from public.notifications
   where id > q0 and type = 'supplier_no_response_chase' and channel = 'email'
     and to_email = 'zz-demo-refund-supplier@example.invalid' and 'zz-demo-refund-customer@example.invalid' = any(cc_emails);
  select count(*), max(assigned_agent), max(dept_key) into n_task, task_agent, task_dept
    from public.org_tasks where id > t0 and decided_by = 'fn_refund_ladder_sweep';
  out := out || jsonb_build_object('chase_emails', n_notif, 'chase_tasks', n_task, 'task_agent', task_agent, 'task_dept', task_dept,
                                   'day4_state_after', public.fn_refund_state(v_tx)->>'state');
  r := public.fn_refund_ladder_sweep();
  out := out || jsonb_build_object('sweep2_chased', r->>'chased', 'sweep2_final_calls', r->>'final_calls');

  -- working day 7 after payment: final call due
  update public.transactions set revealed_at = '2026-08-26 09:00+04'::timestamptz, refund_deadline = null where id = v_tx;
  st := public.fn_refund_state(v_tx);
  out := out || jsonb_build_object('day7_state', st->>'state', 'day7_refund_deadline', st->>'refund_deadline');
  r := public.fn_refund_ladder_sweep();
  out := out || jsonb_build_object('sweep3', (r - 'cases') - 'ran_at');
  select count(*) into n_ref from public.refunds where transaction_id = v_tx and status = 'requested' and requested_by = 'refund_ladder_sweep';
  select count(*) into n_alert from public.founder_alerts where dedupe_key = 'refund_final_call:' || v_tx::text and channel = 'email';
  select count(*) into n_fmail from public.notifications where id > q0 and type = 'founder_alert' and kind = 'refund_final_call' and channel = 'email' and to_role = 'founder';
  select count(*) into n_wa    from public.notifications where id > q0 and type = 'founder_alert' and kind = 'refund_final_call' and channel = 'whatsapp';
  select count(*) into n_cmail from public.notifications where id > q0 and coalesce(kind, type) = 'refund_complaint' and to_role in ('founder', 'admin');
  select count(*) into n_ctask from public.org_tasks where id > t0 and result -> 'founder_mail' ->> 'kind' = 'refund_complaint';
  out := out || jsonb_build_object('refund_rows_requested', n_ref, 'founder_alert_email', n_alert, 'founder_email_queued', n_fmail,
                                   'founder_whatsapp_queued', n_wa, 'complaint_emails_to_founder', n_cmail, 'complaint_tasks_routed', n_ctask,
                                   'tx_refund_status', (select refund_status from public.transactions where id = v_tx),
                                   'day7_state_after', public.fn_refund_state(v_tx)->>'state');
  r := public.fn_refund_ladder_sweep();
  out := out || jsonb_build_object('sweep4_chased', r->>'chased', 'sweep4_final_calls', r->>'final_calls');
  out := out || jsonb_build_object('amounts_stated', public.fn_refund_amount_aed(300, '2026-08-26 09:00+04'::timestamptz, now()));
  raise exception 'PROBE_RESULT %', out::text;
end $probe$;`;

try {
  await replaySql(probe, { label: 'the refund ladder probe' });
  console.log('UNEXPECTED: the probe committed (no RAISE reached)');
  process.exit(2);
} catch (e) {
  // the management API returns the RAISE text inside a JSON-encoded message: quotes arrive escaped and the
  // PL/pgSQL CONTEXT line follows on a literal \n
  const msg = String(e.message || e);
  const at = msg.indexOf('PROBE_RESULT ');
  if (at < 0) { console.log('PROBE FAILED BEFORE ITS RESULT:', msg.slice(0, 1500)); process.exit(1); }
  let body = msg.slice(at + 'PROBE_RESULT '.length);
  const end = body.indexOf('\\nCONTEXT'); if (end >= 0) body = body.slice(0, end);
  body = body.replace(/\\"/g, '"').replace(/"\}"\s*$/, '"}');
  const out = JSON.parse(body.slice(0, body.lastIndexOf('}') + 1));
  console.log(JSON.stringify(out, null, 1));
  const expect = {
    day4_state: 'chase_due', chase_emails: 1, chase_tasks: 1, task_agent: 'followup', task_dept: 'customer_experience',
    day4_state_after: 'chased', sweep2_chased: '0', sweep2_final_calls: '0', day7_state: 'final_call_due',
    refund_rows_requested: 1, founder_alert_email: 1, founder_email_queued: 1, complaint_emails_to_founder: 0,
    tx_refund_status: 'requested', day7_state_after: 'final_call_sent', sweep4_chased: '0', sweep4_final_calls: '0',
  };
  const bad = Object.entries(expect).filter(([k, v]) => String(out[k]) !== String(v));
  if (bad.length) { console.log('MISMATCH:', bad.map(([k, v]) => `${k}: expected ${v}, got ${out[k]}`).join('; ')); process.exit(1); }
  console.log('REFUND_LADDER_PROBE_OK: chase at working day 3 (1 email supplier+cc customer, 1 task on followup/customer_experience), idempotent; final call at working day 5 (1 refunds row requested via fn_refund_request, 1 founder email refund_final_call, 0 complaint emails to the founder), idempotent; everything rolled back');
  process.exit(0);
}
